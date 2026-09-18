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

        guard let result = BoundedProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: [script.path, library.path, "get"],
            timeout: 3,
            outputLimit: 4 * 1_024 * 1_024
        ), result.terminationStatus == 0 else { return nil }
        let line: Data
        if let newlineIndex = result.output.firstIndex(of: 0x0A) {
            line = result.output.subdata(in: result.output.startIndex..<newlineIndex)
        } else {
            line = result.output
        }
        return try? JSONDecoder().decode(TrackInfo.self, from: line)
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
        guard let result = runJavaScript(script, outputLimit: 256 * 1_024) else { return nil }
        return try? JSONDecoder().decode(Result.self, from: result)
    }

    static func readArtwork() -> String? {
        let script = #"ObjC.import('Foundation'); $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load; const item=$.NSClassFromString('MRNowPlayingRequest').localNowPlayingItem; if(!item) ''; else { const d=item.nowPlayingInfo.valueForKey('kMRMediaRemoteNowPlayingInfoArtworkData'); const raw=ObjC.unwrap(d); raw ? ObjC.unwrap(d.base64EncodedStringWithOptions(0)) : '' }"#
        guard let data = runJavaScript(script, outputLimit: 8 * 1_024 * 1_024),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func runJavaScript(_ script: String, outputLimit: Int) -> Data? {
        guard let result = BoundedProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-l", "JavaScript", "-e", script],
            timeout: 3,
            outputLimit: outputLimit
        ), result.terminationStatus == 0 else { return nil }
        return result.output
    }
}

enum PlaybackQueueReader {
    static func readNext() -> UpcomingTrack? {
        let script = #"ObjC.import('Foundation'); $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load; const q=$.NSClassFromString('MRNowPlayingRequest').localPlaybackQueue; const item=q.contentItemWithOffset(1); if(ObjC.unwrap(item)===undefined) JSON.stringify({}); else { const m=item.metadata; const g=(k)=>{const v=m.valueForKey(k); return v ? ObjC.unwrap(v) : null}; JSON.stringify({title:g('title')||g('__title')||'',artist:g('trackArtistName')||''}) }"#
        guard let result = BoundedProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-l", "JavaScript", "-e", script],
            timeout: 3,
            outputLimit: 256 * 1_024
        ), result.terminationStatus == 0,
              let decoded = try? JSONDecoder().decode(UpcomingTrack.self, from: result.output),
              !decoded.title.isEmpty else { return nil }
        return decoded
    }
}
