import AVFoundation
import Foundation

final class AVPlayerAudioBridge {

    private let player = AVPlayer()

    private var statusObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private var baseRate: Float = 1.0
    private var didSignalReady = false

    var onReady: (() -> Void)?
    var onStall: (() -> Void)?
    var onKeepUp: (() -> Void)?
    var onEnded: (() -> Void)?
    var onFailed: ((String) -> Void)?

    var currentTime: TimeInterval {
        let t = player.currentTime()
        guard t.isValid, !t.isIndefinite else { return 0 }
        let s = t.seconds
        return s.isFinite ? s : 0
    }

    var statusLabel: String {
        switch player.currentItem?.status {
        case .readyToPlay: return "ready"
        case .failed: return "failed"
        case .unknown: return "unknown"
        case nil: return "none"
        @unknown default: return "unknown"
        }
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .pause
    }

    deinit { teardown() }

    func configure(url: URL, headers: [String: String], startPosition: TimeInterval) {
        teardown()
        didSignalReady = false
        let options: [String: Any] =
            headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        install(item: item, startPosition: startPosition)
    }

    private func install(item: AVPlayerItem, startPosition: TimeInterval) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async { self.handleStatus(item, startPosition: startPosition) }
        }
        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) {
            [weak self] item, _ in
            guard let self, item.isPlaybackBufferEmpty else { return }
            DispatchQueue.main.async { self.onStall?() }
        }
        keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
            [weak self] item, _ in
            guard let self, item.isPlaybackLikelyToKeepUp else { return }
            DispatchQueue.main.async { self.onKeepUp?() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in self?.onEnded?() }

        player.replaceCurrentItem(with: item)
    }

    private func handleStatus(_ item: AVPlayerItem, startPosition: TimeInterval) {
        switch item.status {
        case .readyToPlay:
            if startPosition > 0 {
                player.seek(
                    to: CMTime(seconds: startPosition, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero
                ) { [weak self] _ in
                    self?.signalReadyOnce()
                }
            } else {
                signalReadyOnce()
            }
        case .failed:
            onFailed?("avplayer_item_failed:\(Self.describe(item.error) ?? "unknown")")
        default:
            break
        }
    }

    private static func describe(_ error: Error?) -> String? {
        guard let error = error as NSError? else { return nil }
        let underlying =
            (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { ":\($0.domain)/\($0.code)" }
            ?? ""
        return "\(error.domain)/\(error.code)\(underlying)"
    }

    private func signalReadyOnce() {
        guard !didSignalReady else { return }
        didSignalReady = true
        onReady?()
    }

    func play() { player.rate = baseRate }
    func pause() { player.rate = 0 }
    func resume() { player.rate = baseRate }

    func setRate(_ rate: Float) {
        baseRate = rate
        if player.timeControlStatus != .paused { player.rate = rate }
    }

    func seek(to seconds: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            completion?(finished)
        }
    }

    func stop() {
        teardown()
    }

    private func teardown() {
        statusObservation?.invalidate()
        statusObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        keepUpObservation?.invalidate()
        keepUpObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        didSignalReady = false
    }
}
