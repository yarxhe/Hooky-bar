import Cocoa
import MediaRemoteAdapter
import SwiftUI

/// MediaRemoteAdapter's asynchronous one-shot reader can miss a very large
/// artwork payload when it arrives in several pipe chunks. This small fallback
/// reads the same native adapter to EOF and is used only while reconnecting.
enum DirectMediaSnapshotReader {
    static func read() -> TrackInfo? {
        guard let resources = Bundle.main.resourceURL,
              let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let script = resources
            .appendingPathComponent("MediaRemoteAdapter_MediaRemoteAdapter.bundle")
            .appendingPathComponent("Contents/Resources/run.pl")
        let library = executableDirectory.appendingPathComponent("libMediaRemoteAdapter.dylib")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: library.path) else { return nil }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, library.path, "get"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let line: Data
            if let newlineIndex = data.firstIndex(of: 0x0A) {
                line = data.subdata(in: data.startIndex..<newlineIndex)
            } else {
                line = data
            }
            return try? JSONDecoder().decode(TrackInfo.self, from: line)
        } catch {
            return nil
        }
    }
}

struct NowPlayingReader {
    struct Result: Decodable {
        let title: String?
        let artist: String?
        let duration: Double
        let elapsed: Double
        let rate: Double
        let liked: Bool?
    }

    static func read() -> Result? {
        let script = #"ObjC.import('Foundation'); $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load; const i=$.NSClassFromString('MRNowPlayingRequest').localNowPlayingItem.nowPlayingInfo; const g=(k)=>{const v=i.valueForKey(k); return v ? ObjC.unwrap(v) : null}; JSON.stringify({title:g('kMRMediaRemoteNowPlayingInfoTitle'),artist:g('kMRMediaRemoteNowPlayingInfoArtist'),duration:g('kMRMediaRemoteNowPlayingInfoDuration')||0,elapsed:g('kMRMediaRemoteNowPlayingInfoElapsedTime')||0,rate:g('kMRMediaRemoteNowPlayingInfoPlaybackRate')||0,liked:g('kMRMediaRemoteNowPlayingInfoIsLiked')})"#
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(Result.self, from: pipe.fileHandleForReading.readDataToEndOfFile())
    }

    static func readArtwork() -> String? {
        let script = #"ObjC.import('Foundation'); $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load; const item=$.NSClassFromString('MRNowPlayingRequest').localNowPlayingItem; if(!item) ''; else { const d=item.nowPlayingInfo.valueForKey('kMRMediaRemoteNowPlayingInfoArtworkData'); const raw=ObjC.unwrap(d); raw ? ObjC.unwrap(d.base64EncodedStringWithOptions(0)) : '' }"#
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let value = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

enum PlaybackQueueReader {
    static func readNext() -> UpcomingTrack? {
        let script = #"ObjC.import('Foundation'); $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load; const q=$.NSClassFromString('MRNowPlayingRequest').localPlaybackQueue; const item=q.contentItemWithOffset(1); if(ObjC.unwrap(item)===undefined) JSON.stringify({}); else { const m=item.metadata; const g=(k)=>{const v=m.valueForKey(k); return v ? ObjC.unwrap(v) : null}; JSON.stringify({title:g('title')||g('__title')||'',artist:g('trackArtistName')||''}) }"#
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let decoded = try? JSONDecoder().decode(UpcomingTrack.self, from: pipe.fileHandleForReading.readDataToEndOfFile()),
              !decoded.title.isEmpty else { return nil }
        return decoded
    }
}

enum ArtworkPalette {
    static func colors(from image: NSImage) -> [Color] {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { return [.yellow, .orange] }
        let stepX = max(1, bitmap.pixelsWide / 18)
        let stepY = max(1, bitmap.pixelsHigh / 18)
        var samples: [(color: NSColor, hue: CGFloat, score: CGFloat)] = []
        for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                guard saturation > 0.22, brightness > 0.18, alpha > 0.5 else { continue }
                samples.append((color, hue, saturation * 0.72 + brightness * 0.28))
            }
        }
        var selected: [(NSColor, CGFloat)] = []
        for sample in samples.sorted(by: { $0.score > $1.score }) {
            let isDifferent = selected.allSatisfy { min(abs($0.1 - sample.hue), 1 - abs($0.1 - sample.hue)) > 0.10 }
            if isDifferent { selected.append((sample.color, sample.hue)) }
            if selected.count == 3 { break }
        }
        return selected.isEmpty ? [.yellow, .orange] : selected.map { Color(nsColor: $0.0) }
    }
}
