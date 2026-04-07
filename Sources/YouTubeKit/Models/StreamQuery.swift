//
//  StreamQuery.swift
//  YouTubeKit
//
//  Created by Alexander Eichhorn on 04.09.21.
//

import Foundation

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
public extension Collection where Element == Stream {
    
    func sorted<T: Comparable>(by keyPath: KeyPath<Stream, T>, ascending: Bool = true) -> [Stream] {
        if ascending {
            return sorted { a, b in
                return a[keyPath: keyPath] < b[keyPath: keyPath]
            }
        } else {
            return sorted { a, b in
                return a[keyPath: keyPath] > b[keyPath: keyPath]
            }
        }
    }
    
    func stream(withITag itag: Int) -> Stream? {
        first(where: { $0.itag.itag == itag })
    }
    
    func streams(withExactResolution resolution: Int) -> [Stream] {
        filter { $0.itag.videoResolution == resolution }
    }
    
    func filter(byResolution resolution: (Int?) -> Bool) -> [Stream] {
        filter { resolution($0.itag.videoResolution) }
    }
    
    /// get stream with lowest video resolution
    func lowestResolutionStream() -> Stream? {
        min(byProperty: { $0.itag.videoResolution ?? .max })
    }
    
    /// get stream with highest video resolution
    func highestResolutionStream() -> Stream? {
        max(byProperty: { $0.itag.videoResolution ?? 0 })
    }
    
    /// get stream with lowest audio bitrate
    /// - note: potentially returns stream without audio if none exist
    func lowestAudioBitrateStream() -> Stream? {
        min(byProperty: { $0.itag.audioBitrate ?? .max })
    }
    
    /// get stream with highest audio bitrate
    /// - note: potentially returns stream without audio if none exist
    func highestAudioBitrateStream() -> Stream? {
        max(byProperty: { $0.itag.audioBitrate ?? 0 })
    }
    
    /// only returns streams which contain audio, but no video
    func filterAudioOnly() -> [Stream] {
        filter { $0.includesAudioTrack && !$0.includesVideoTrack }
    }
    
    /// only returns streams which contain video, but no audio
    func filterVideoOnly() -> [Stream] {
        filter { $0.includesVideoTrack && !$0.includesAudioTrack }
    }
    
    /// only returns streams which contain both audio and video
    func filterVideoAndAudio() -> [Stream] {
        filter { $0.includesVideoAndAudioTrack }
    }

    /// Pick the best audio-only natively-playable stream.
    /// Ranking: audio-only > muxed, codec (opus > mp4a > other), closest to target bitrate, then highest kbps.
    func pickBestStream() -> Stream? {
        let candidates = filterAudioOnly()
            .filter { $0.isNativelyPlayable }
        guard !candidates.isEmpty else { return nil }

        return candidates.max { lhs, rhs in
            let a = lhs.audioScoreTuple()
            let b = rhs.audioScoreTuple()
            if a.primary != b.primary { return a.primary < b.primary }
            if a.codec   != b.codec   { return a.codec   < b.codec }
            if a.tie     != b.tie     { return a.tie     < b.tie }
            return a.kbps < b.kbps
        }
    }

}

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
extension Stream {

    /// Scoring tuple for audio stream ranking.
    /// Higher values are better for each component.
    func audioScoreTuple(targets: [Int] = [256, 160, 128, 96, 70, 64, 50, 48])
    -> (primary: Int, codec: Int, tie: Int, kbps: Int) {
        let primary = isAudioOnly ? 2 : 1
        let codec   = audioCodecRank.rawValue
        let kbps    = audioKbps
        let delta   = targets.map { abs(kbps - $0) }.min() ?? .max
        return (primary, codec, -delta, kbps)
    }

}
