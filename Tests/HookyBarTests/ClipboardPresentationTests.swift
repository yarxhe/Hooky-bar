import Foundation
import Testing
@testable import HookyBar

struct ClipboardPresentationTests {
    private func item(_ text: String) -> ClipboardItem {
        ClipboardItem(id: "preview", sourceID: "test", sourceName: "Test",
            sourceBundleIdentifier: nil, kind: .text, text: text, fileURL: nil, createdAt: Date())
    }

    @Test func linkLabelContainsOnlyHost() {
        #expect(item(" https://example.com/path?q=value \n").linkHost == "example.com")
        #expect(item("file:///tmp/example.txt").linkHost == nil)
        #expect(item("ordinary text").linkHost == nil)
    }

    @Test func previewDoesNotAlterOriginalText() {
        let text = "const value = {\n  title: 'Hello'\n};"
        let entry = item(text)
        #expect(entry.isProbablyCode)
        #expect(entry.text == text)
    }

    @Test func screenshotOpenRejectsRemoteAndMissingFiles() {
        let adapter = ScreenshotClipboardAdapter()
        for url in [URL(string: "https://example.com/image.png")!,
                    URL(fileURLWithPath: "/nonexistent-hooky-screenshot.png")] {
            let entry = ClipboardItem(id: "invalid", sourceID: adapter.id, sourceName: "Test",
                sourceBundleIdentifier: nil, kind: .screenshot, text: nil, fileURL: url, createdAt: Date())
            #expect(!adapter.open(entry).succeeded)
        }
    }
}
