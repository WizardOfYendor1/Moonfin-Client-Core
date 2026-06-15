import Foundation
import Network

final class LoopbackHTTPServer {

    private let root: URL
    private let queue = DispatchQueue(label: "org.moonfin.loopback.http")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    init(root: URL) { self.root = root }

    func start() -> UInt16? {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        guard let listener = try? NWListener(using: params, on: .any) else { return nil }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)

        guard let rawPort = listener.port?.rawValue, rawPort != 0 else {
            listener.cancel()
            self.listener = nil
            return nil
        }
        port = rawPort
        return rawPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(conn, requestHead: buf.subdata(in: buf.startIndex..<headerEnd.lowerBound))
            } else if error != nil || isComplete || buf.count > 64 * 1024 {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func respond(_ conn: NWConnection, requestHead: Data) {
        guard let head = String(data: requestHead, encoding: .utf8) else { return finish(conn, status: "400 Bad Request") }
        let lines = head.components(separatedBy: "\r\n")
        let request = lines.first?.components(separatedBy: " ") ?? []
        guard request.count >= 2, request[0] == "GET" || request[0] == "HEAD" else {
            return finish(conn, status: "405 Method Not Allowed")
        }
        let isHead = request[0] == "HEAD"
        var path = request[1]
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !rel.isEmpty, !rel.contains("..") else { return finish(conn, status: "403 Forbidden") }

        let fileURL = root.appendingPathComponent(rel)
        guard let fileData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return finish(conn, status: "404 Not Found")
        }

        let contentType = Self.mimeType(for: fileURL.pathExtension)
        let total = fileData.count
        let rangeLine = lines.dropFirst().first { $0.lowercased().hasPrefix("range:") }

        if let rangeLine, let (start, end) = Self.parseRange(rangeLine, total: total) {
            let body = fileData.subdata(in: start..<(end + 1))
            var resp = "HTTP/1.1 206 Partial Content\r\n"
            resp += "Content-Type: \(contentType)\r\n"
            resp += "Content-Range: bytes \(start)-\(end)/\(total)\r\n"
            resp += "Content-Length: \(body.count)\r\n"
            resp += "Accept-Ranges: bytes\r\nConnection: close\r\n\r\n"
            var out = Data(resp.utf8)
            if !isHead { out.append(body) }
            send(conn, out)
        } else {
            var resp = "HTTP/1.1 200 OK\r\n"
            resp += "Content-Type: \(contentType)\r\n"
            resp += "Content-Length: \(total)\r\n"
            resp += "Accept-Ranges: bytes\r\nConnection: close\r\n\r\n"
            var out = Data(resp.utf8)
            if !isHead { out.append(fileData) }
            send(conn, out)
        }
    }

    private func finish(_ conn: NWConnection, status: String) {
        let resp = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        send(conn, Data(resp.utf8))
    }

    private func send(_ conn: NWConnection, _ data: Data) {
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "mp4", "m4s": return "video/mp4"
        default: return "application/octet-stream"
        }
    }

    private static func parseRange(_ header: String, total: Int) -> (Int, Int)? {
        guard total > 0,
              let eq = header.firstIndex(of: "="),
              header[..<eq].lowercased().hasSuffix("bytes") else { return nil }
        let spec = header[header.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        let bounds = spec.components(separatedBy: "-")
        guard bounds.count == 2 else { return nil }
        let startStr = bounds[0].trimmingCharacters(in: .whitespaces)
        let endStr = bounds[1].trimmingCharacters(in: .whitespaces)
        if startStr.isEmpty {
            guard let suffix = Int(endStr), suffix > 0 else { return nil }
            return (max(0, total - suffix), total - 1)
        }
        guard let start = Int(startStr), start < total else { return nil }
        let end = endStr.isEmpty ? total - 1 : min(Int(endStr) ?? (total - 1), total - 1)
        guard end >= start else { return nil }
        return (start, end)
    }
}
