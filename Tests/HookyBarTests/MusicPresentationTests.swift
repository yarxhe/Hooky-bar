import AppKit
import Combine
import SwiftUI
import Testing
@testable import HookyBar

@Suite("Music presentation")
@MainActor
struct MusicPresentationTests {
    @Test func navigationFailureUnblocksClockWithoutCancellingNewerCommand() {
        let store = MusicStore()
        store.navigationCommandGeneration = 2
        store.manualTrackChangePending = true
        store.ignoreRemoteElapsedUntil = .distantFuture
        store.nowPlaying.elapsed = 42
        store.finishUnconfirmedNavigation(generation: 1)
        #expect(store.manualTrackChangePending)
        store.finishUnconfirmedNavigation(generation: 2)
        #expect(!store.manualTrackChangePending)
        #expect(store.ignoreRemoteElapsedUntil == .distantPast)
        #expect(store.nowPlaying.elapsed == 42)
    }

    @Test func replacementArtworkRemainsAvailableWithoutReplayingTransition() throws {
        let store = MusicStore()
        store.applyAdapterSnapshot(snapshot("First", nil), marksSystemOwnership: false)
        let revision = store.trackPresentationRevision
        let red = artwork(.red)
        let blue = artwork(.blue)
        store.applyAdapterSnapshot(snapshot("First", red), marksSystemOwnership: false)
        #expect(store.nowPlaying.artwork === red)
        store.applyAdapterSnapshot(snapshot("First", blue), marksSystemOwnership: false)
        #expect(store.nowPlaying.artwork === blue)
        for _ in 0..<3 {
            store.applyAdapterSnapshot(snapshot("First", nil), marksSystemOwnership: false)
        }
        #expect(store.nowPlaying.artwork === blue)
        #expect(store.trackPresentationRevision == revision)
        store.clearSelectedTrack()
        #expect(store.nowPlaying.artwork == nil)
    }

    @Test func backgroundPaletteInterpolatesWithoutChangingSlotCount() throws {
        let start = BackgroundPalette(colors: [Color(.sRGB, red: 1, green: 0, blue: 0)])
        let end = BackgroundPalette(colors: [Color(.sRGB, red: 0, green: 0, blue: 1), .black])
        var difference = end - start
        difference.scale(by: 0.5)
        let midpoint = start + difference
        #expect(midpoint.colors.count == 3)
        let color = try #require(NSColor(midpoint.colors[0]).usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 0.5) < 0.001)
        #expect(abs(color.blueComponent - 0.5) < 0.001)
        #expect((start + (end - start) - end).magnitudeSquared < 0.000001)
        #expect(BackgroundPalette(colors: []).colors.count == 3)
    }

    @Test func partialArtistDoesNotReplayTrackTransition() {
        let store = MusicStore()
        func update(_ artist: String) {
            store.applyAdapterSnapshot(
                MusicAdapterSnapshot(title: "Same title", artist: artist, duration: 120,
                                     elapsed: 0, isPlaying: false, artwork: nil, rating: nil),
                marksSystemOwnership: false
            )
        }
        update("")
        let revision = store.trackPresentationRevision
        update("Artist")
        #expect(store.trackPresentationRevision == revision)
        #expect(store.nowPlaying.artist == "Artist")
        update("")
        #expect(store.trackPresentationRevision == revision)
        #expect(store.nowPlaying.artist == "Artist")
        update("Different artist")
        #expect(store.trackPresentationRevision == revision + 1)
    }

    @Test func dominantArtworkColorWinsOverTinyBrightMark() throws {
        let image = artwork(.init(srgbRed: 0.55, green: 0.08, blue: 0.06, alpha: 1))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        let palette = ArtworkPalette.colors(from: image)
        let first = try #require(palette.first)
        let rgb = try #require(NSColor(first).usingColorSpace(.sRGB))
        #expect(rgb.redComponent > rgb.greenComponent * 2)
        #expect(palette.count == 1)
    }

    @Test func monochromeArtworkKeepsNeutralPalette() throws {
        for color in ArtworkPalette.colors(from: artwork(.gray)) {
            let rgb = try #require(NSColor(color).usingColorSpace(.sRGB))
            #expect(rgb.saturationComponent < 0.01)
        }
    }

    @Test func oversizedArtworkIsBoundedForPlayerPresentation() throws {
        let image = NSImage(size: NSSize(width: 1_024, height: 1_024))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: 1_024, height: 1_024).fill()
        image.unlockFocus()

        let compact = try #require(ArtworkPalette.displayArtwork(from: image))
        let pixels = try #require(compact.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(max(pixels.width, pixels.height) <= 512)
    }

    @Test func lateArtworkUpdatesPaletteWithoutReplayingTrackTransition() {
        let store = MusicStore()
        let red = artwork(.red)
        store.applyAdapterSnapshot(snapshot("First", red), marksSystemOwnership: false)
        #expect(store.visualizerColors != ArtworkPalette.fallback)
        let previousPalette = store.visualizerColors

        store.applyAdapterSnapshot(snapshot("Second", nil), marksSystemOwnership: false)
        #expect(store.visualizerColors == previousPalette)
        let trackRevision = store.trackPresentationRevision
        let artRevision = store.artworkPresentationRevision
        let blue = artwork(.blue)
        store.applyAdapterSnapshot(snapshot("Second", blue), marksSystemOwnership: false)
        #expect(store.trackPresentationRevision == trackRevision)
        #expect(store.artworkPresentationRevision == artRevision + 1)
        #expect(store.visualizerColors != ArtworkPalette.fallback)

        var updates = 0
        let subscription = store.$visualizerColors.dropFirst().sink { _ in updates += 1 }
        for _ in 0..<3 {
            store.applyAdapterSnapshot(snapshot("Second", blue), marksSystemOwnership: false)
        }
        #expect(updates == 0)
        #expect(store.artworkPresentationRevision == artRevision + 1)
        withExtendedLifetime(subscription) {}
        store.clearSelectedTrack()
        #expect(store.visualizerColors == ArtworkPalette.fallback)
    }

    private func artwork(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        return image
    }

    private func snapshot(_ title: String, _ artwork: NSImage?) -> MusicAdapterSnapshot {
        MusicAdapterSnapshot(title: title, artist: "Test", duration: 120, elapsed: 0,
                             isPlaying: false, artwork: artwork, rating: nil)
    }
}
