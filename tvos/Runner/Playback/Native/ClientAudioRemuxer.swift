import Foundation

final class ClientAudioRemuxer {

    private let queue = DispatchQueue(label: "org.moonfin.clientaudio.remux")
    private let cancelPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private var tempDir: URL?
    private var server: LoopbackHTTPServer?

    init() { cancelPtr.initialize(to: 0) }

    deinit {
        cancelPtr.pointee = 1
        let ptr = cancelPtr
        queue.async { ptr.deinitialize(count: 1); ptr.deallocate() }
        server?.stop()
        cleanupTempDir()
    }

    func start(sourceURL: String, audioStreamIndex: Int) async -> URL? {
        cancelPtr.pointee = 0

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moonfin-hybrid-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir

        let srv = LoopbackHTTPServer(root: dir)
        guard let port = srv.start() else { cleanupTempDir(); return nil }
        server = srv

        let playlistName = "audio.m3u8"
        let path = dir.path
        let cancel = cancelPtr
        queue.async {
            _ = moonfin_remux_audio_to_hls(sourceURL, Int32(audioStreamIndex), path, playlistName, 4.0, cancel)
        }

        let playlistURL = dir.appendingPathComponent(playlistName)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if cancelPtr.pointee != 0 { break }
            if let contents = try? String(contentsOf: playlistURL, encoding: .utf8), contents.contains(".m4s") {
                return URL(string: "http://127.0.0.1:\(port)/\(playlistName)")
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        stop()
        return nil
    }

    func stop() {
        cancelPtr.pointee = 1
        server?.stop()
        server = nil
        cleanupTempDir()
    }

    private func cleanupTempDir() {
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir) }
        tempDir = nil
    }
}
