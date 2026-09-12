import Cocoa
import FlutterMacOS
import XCTest

@testable import Moonfin

/// Subtitle overlay cue selection. The overlay holds the only copy of a sidecar
/// track's cues (the engine publishes such a file once and clears its drain
/// target), so anything it drops is gone for the rest of the session.
final class SubtitleOverlayTests: XCTestCase {

    private func cue(_ body: String, _ start: TimeInterval, _ end: TimeInterval) -> SubtitleEvent {
        SubtitleEvent(
            startTime: start, endTime: end, text: body,
            bitmap: nil, bitmapWidth: 0, bitmapHeight: 0)
    }

    private let overlayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeOverlay() -> SubtitleOverlay {
        SubtitleOverlay(frame: overlayBounds)
    }

    // MARK: - Selection

    func testCuesSharingAWindowAreAllSelected() {
        let cues = [cue("You know what I think?", 10, 14), cue("Maybe.", 11, 13)]
        let covering = SubtitleOverlay.activeEvents(in: cues, at: 12)
        XCTAssertEqual(covering.count, 2)
    }

    func testSelectionIsHalfOpenOnTheEndTime() {
        let cues = [cue("A", 10, 12), cue("B", 12, 14)]
        XCTAssertEqual(SubtitleOverlay.activeEvents(in: cues, at: 12).map(\.text), ["B"])
    }

    func testSelectionIsEmptyBetweenCues() {
        let cues = [cue("A", 10, 12), cue("B", 14, 16)]
        XCTAssertTrue(SubtitleOverlay.activeEvents(in: cues, at: 13).isEmpty)
    }

    // MARK: - Rendering

    func testSimultaneousSpeakersBothRender() {
        let overlay = makeOverlay()
        overlay.setEvents([cue("- Look at me.", 10, 14), cue("- I am looking.", 10, 14)])
        overlay.update(currentTime: 11)

        XCTAssertEqual(overlay.activeText, "- Look at me.\n- I am looking.")
    }

    /// The reported failure: a sidecar track publishes once, the clock jumps
    /// forward (a seek, a seam shift, a recovery reload landing on its target
    /// before the picture catches up) and then plays the skipped region. Every
    /// line in it has to still be there.
    func testCuesSurviveAForwardClockJump() {
        let overlay = makeOverlay()
        overlay.setEvents([
            cue("You know what I think?", 5, 7),
            cue("You have to forget her.", 9, 11),
            cue("Look at me.", 600, 602),
        ])

        overlay.update(currentTime: 601)
        XCTAssertEqual(overlay.activeText, "Look at me.")

        overlay.update(currentTime: 6)
        XCTAssertEqual(overlay.activeText, "You know what I think?")
        overlay.update(currentTime: 10)
        XCTAssertEqual(overlay.activeText, "You have to forget her.")
    }

    /// The engine rewrites a cue's end time in place to close an open-ended
    /// line, so identity cannot rest on the start time alone.
    func testARewrittenEndTimeRetiresTheLine() {
        let overlay = makeOverlay()
        overlay.setEvents([cue("Maybe.", 10, 20)])
        overlay.update(currentTime: 15)
        XCTAssertEqual(overlay.activeText, "Maybe.")

        overlay.setEvents([cue("Maybe.", 10, 12)])
        XCTAssertEqual(overlay.activeText, "")
    }

    func testClearDropsTheVisibleLine() {
        let overlay = makeOverlay()
        overlay.setEvents([cue("Look at me.", 10, 14)])
        overlay.update(currentTime: 11)
        XCTAssertFalse(overlay.activeText.isEmpty)

        overlay.clear()
        XCTAssertEqual(overlay.activeText, "")
    }

    // MARK: - ASS canvas

    // Only a picture that fits inside the overlay moves the canvas, every other
    // case lands on the bounds.

    private func canvas(forVideoRect rect: CGRect?) -> CGRect {
        let overlay = makeOverlay()
        if let rect {
            overlay.videoRectProvider = { rect }
        }
        return overlay.assCanvas
    }

    func testLetterboxedPictureIsTheCanvas() {
        let picture = CGRect(x: 0, y: 135, width: 1920, height: 810)
        XCTAssertEqual(canvas(forVideoRect: picture), picture)
    }

    func testPillarboxedPictureIsTheCanvas() {
        let picture = CGRect(x: 240, y: 0, width: 1440, height: 1080)
        XCTAssertEqual(canvas(forVideoRect: picture), picture)
    }

    func testFillModeStaysOnTheBounds() {
        let picture = CGRect(x: -480, y: 0, width: 2880, height: 1080)
        XCTAssertEqual(canvas(forVideoRect: picture), overlayBounds)
    }

    func testStretchStaysOnTheBounds() {
        XCTAssertEqual(canvas(forVideoRect: overlayBounds), overlayBounds)
    }

    func testNoMeasuredPictureStaysOnTheBounds() {
        XCTAssertEqual(canvas(forVideoRect: .zero), overlayBounds)
    }

    func testNoProviderStaysOnTheBounds() {
        XCTAssertEqual(canvas(forVideoRect: nil), overlayBounds)
    }
}
