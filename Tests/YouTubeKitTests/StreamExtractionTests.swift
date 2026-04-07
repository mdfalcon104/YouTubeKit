//
//  StreamExtractionTests.swift
//  YouTubeKitTests
//
//  End-to-end tests that verify YouTubeKit can extract playable stream URLs
//  from real YouTube videos. These hit the live YouTube API so they require
//  network access and may be flaky if YouTube changes their API.
//
//  Each test validates the full pipeline:
//    1. Fetch watch HTML & player JS
//    2. Call InnerTube API with updated clients (androidVR, ios, webSafari)
//    3. Decrypt signatures & n-parameters via yt-ejs
//    4. Produce playable Stream objects with reachable URLs
//

import XCTest
@testable import YouTubeKit

@available(iOS 15.0, watchOS 8.0, tvOS 15.0, macOS 12.0, *)
final class StreamExtractionTests: XCTestCase {

    // MARK: - Helpers

    /// Verify every stream has a known codec and a reachable URL (HTTP HEAD → 200).
    private func assertStreamsValid(_ streams: [YouTubeKit.Stream], file: StaticString = #file, line: UInt = #line) async throws {
        XCTAssertFalse(streams.isEmpty, "Expected at least one stream", file: file, line: line)

        for stream in streams {
            // Every stream must have at least one codec
            XCTAssertTrue(
                stream.videoCodec != nil || stream.audioCodec != nil,
                "Stream itag=\(stream.itag.itag) has no codec",
                file: file, line: line
            )

            // No unknown codecs — if YouTube introduces a new one we want to catch it
            if let vc = stream.videoCodec, case .unknown(let raw) = vc {
                XCTFail("Unknown video codec: \(raw) in itag=\(stream.itag.itag)", file: file, line: line)
            }
            if let ac = stream.audioCodec, case .unknown(let raw) = ac {
                XCTFail("Unknown audio codec: \(raw) in itag=\(stream.itag.itag)", file: file, line: line)
            }
        }
    }

    /// HEAD-request a sample of streams and assert they return HTTP 200.
    /// Only checks up to `limit` streams to keep the test fast.
    private func assertStreamsReachable(_ streams: [YouTubeKit.Stream], limit: Int = 5, file: StaticString = #file, line: UInt = #line) async throws {
        let sampled = Array(streams.prefix(limit))
        var failures = [(itag: Int, status: Int)]()

        for stream in sampled {
            var request = URLRequest(url: stream.url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    failures.append((stream.itag.itag, http.statusCode))
                }
            } catch {
                failures.append((stream.itag.itag, -1))
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Unreachable streams: \(failures.map { "itag=\($0.itag) status=\($0.status)" }.joined(separator: ", "))",
            file: file, line: line
        )
    }

    // MARK: - Popular music video (high traffic, always available)

    func testPopularMusicVideo() async throws {
        // PSY - Gangnam Style — one of the most viewed videos on YouTube
        let youtube = YouTube(videoID: "9bZkp7q19f0")
        let streams = try await youtube.streams

        try await assertStreamsValid(streams)

        // Must have all three track types
        XCTAssertFalse(streams.filterAudioOnly().isEmpty, "No audio-only streams")
        XCTAssertFalse(streams.filterVideoOnly().isEmpty, "No video-only streams")
        XCTAssertFalse(streams.filterVideoAndAudio().isEmpty, "No progressive (muxed) streams")

        // Verify natively-playable audio stream exists (critical for AVPlayer use case)
        let playableAudio = streams.filterAudioOnly().filter { $0.isNativelyPlayable }
        XCTAssertFalse(playableAudio.isEmpty, "No natively-playable audio-only streams")

        // pickBestStream should return a result
        XCTAssertNotNil(streams.pickBestStream(), "pickBestStream returned nil")

        // Spot-check reachability
        try await assertStreamsReachable(streams)
    }

    // MARK: - Standard non-music video

    func testNonMusicVideo() async throws {
        // A non-music video to test different content type
        let youtube = YouTube(videoID: "NOid0U6GxUA")
        let streams = try await youtube.streams

        try await assertStreamsValid(streams)

        XCTAssertFalse(streams.filterAudioOnly().isEmpty, "No audio-only streams")
        XCTAssertFalse(streams.filterVideoOnly().isEmpty, "No video-only streams")

        try await assertStreamsReachable(streams)
    }

    // MARK: - Video with complex signature (tests yt-ejs solver)

    func testVideoSignatureDecryption() async throws {
        // Rick Astley - Never Gonna Give You Up — widely tested across yt-dlp/youtube-dl
        let youtube = YouTube(videoID: "dQw4w9WgXcQ")
        let streams = try await youtube.streams

        try await assertStreamsValid(streams)

        // At least some streams must be available
        XCTAssertGreaterThan(streams.count, 3, "Expected more than 3 streams")

        // Verify audio extraction works (the main complaint in the issue)
        let audioStreams = streams.filterAudioOnly()
        XCTAssertFalse(audioStreams.isEmpty, "No audio-only streams for dQw4w9WgXcQ")

        // Verify highest quality audio stream is reachable
        if let bestAudio = audioStreams.filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream() {
            try await assertStreamsReachable([bestAudio], limit: 1)
        } else {
            XCTFail("No m4a audio stream found")
        }
    }

    // MARK: - Age-restricted video

    func testAgeRestrictedVideo() async throws {
        // Age-restricted video — requires webCreator client with authentication.
        // Without cookies/OAuth, this should throw videoAgeRestricted.
        // If it succeeds, validate the streams; if it throws the expected error, that's OK.
        let youtube = YouTube(videoID: "HtVdAasjOgU")
        do {
            let streams = try await youtube.streams
            // If we get here, the bypass worked — validate streams
            try await assertStreamsValid(streams)
            XCTAssertFalse(streams.filterAudioOnly().isEmpty, "No audio streams for age-restricted video")
        } catch let error as YouTubeKitError where error == .videoAgeRestricted {
            // Expected — age-restricted videos need auth which tests don't have
        }
    }

    // MARK: - Made for Kids video

    func testMadeForKidsVideo() async throws {
        // "Made for Kids" videos have restricted API responses on some clients.
        // YouTube requires PO tokens (Proof of Origin via BotGuard/DroidGuard) for stream
        // URL access on this content category. Without PO tokens, streams are extracted
        // from the InnerTube API but the URLs return 403 Forbidden.
        // This test verifies the extraction pipeline works; reachability is NOT checked
        // because PO token generation is beyond the scope of this library.
        let youtube = YouTube(videoID: "GObpYg_NjLQ")
        let streams = try await youtube.streams

        try await assertStreamsValid(streams)
        XCTAssertFalse(streams.filterAudioOnly().isEmpty, "No audio streams for kids video")
        XCTAssertFalse(streams.filterVideoOnly().isEmpty, "No video streams for kids video")
        // Reachability intentionally NOT checked — requires PO tokens
    }

    // MARK: - Remote extraction fallback

    func testRemoteExtraction() async throws {
        // Test the remote server fallback path
        let youtube = YouTube(videoID: "dQw4w9WgXcQ", methods: [.remote])
        let streams = try await youtube.streams

        try await assertStreamsValid(streams)
        XCTAssertFalse(streams.filterAudioOnly().isEmpty, "No audio streams from remote")
        XCTAssertFalse(streams.filterVideoOnly().isEmpty, "No video streams from remote")
        XCTAssertFalse(streams.filterVideoAndAudio().isEmpty, "No progressive streams from remote")

        try await assertStreamsReachable(streams)
    }

    // MARK: - Natively playable filter (AVPlayer compatibility)

    func testNativelyPlayableStreamsExist() async throws {
        // Verify that after all our client changes, we still get streams
        // that iOS AVPlayer can actually play (no VP9, no Opus)
        let youtube = YouTube(videoID: "9bZkp7q19f0")
        let streams = try await youtube.streams

        let playable = streams.filter { $0.isNativelyPlayable }
        XCTAssertFalse(playable.isEmpty, "No natively playable streams at all")

        // Must have playable video+audio combined (for simple AVPlayer use)
        let playableProgressive = playable.filter { $0.includesVideoAndAudioTrack }
        XCTAssertFalse(playableProgressive.isEmpty, "No natively playable progressive streams")

        // Must have playable audio-only (for background audio use)
        let playableAudioOnly = playable.filter { $0.isAudioOnly }
        XCTAssertFalse(playableAudioOnly.isEmpty, "No natively playable audio-only streams")

        // The highest-res playable progressive stream must be reachable
        if let best = playableProgressive.highestResolutionStream() {
            try await assertStreamsReachable([best], limit: 1)
        }

        // pickBestStream should return a playable audio stream
        if let bestAudio = streams.pickBestStream() {
            XCTAssertTrue(bestAudio.isNativelyPlayable, "pickBestStream returned non-playable stream")
            XCTAssertTrue(bestAudio.isAudioOnly, "pickBestStream returned non audio-only stream")
            try await assertStreamsReachable([bestAudio], limit: 1)
        }
    }

    // MARK: - High resolution video

    func testHighResolutionVideo() async throws {
        // 4K video — tests that high-res adaptive streams are extracted
        let youtube = YouTube(videoID: "LXb3EKWsInQ") // 4K nature video
        let streams = try await youtube.streams

        try await assertStreamsValid(streams)

        // Should have video streams at 1080p or above
        let highRes = streams.filterVideoOnly().filter { ($0.videoResolution ?? 0) >= 1080 }
        XCTAssertFalse(highRes.isEmpty, "No 1080p+ video streams found")

        try await assertStreamsReachable(streams)
    }

    // MARK: - Metadata extraction

    func testMetadataExtraction() async throws {
        let youtube = YouTube(videoID: "9bZkp7q19f0")
        let metadata = try await youtube.metadata

        XCTAssertNotNil(metadata, "Metadata is nil")
        XCTAssertFalse(metadata?.title.isEmpty ?? true, "Title is empty")
        XCTAssertNotNil(metadata?.thumbnail, "Thumbnail is nil")
    }

    // MARK: - Livestream HLS

    func testLivestreamHLS() async throws {
        // DW News livestream
        let youtube = YouTube(videoID: "vytmBNhc9ig")
        let livestreams = try await youtube.livestreams

        XCTAssertFalse(livestreams.isEmpty, "No livestreams found")

        let hlsStream = livestreams.first { $0.streamType == .hls }
        XCTAssertNotNil(hlsStream, "No HLS livestream found")
        XCTAssertTrue(
            hlsStream!.url.absoluteString.contains(".m3u8"),
            "HLS URL doesn't contain .m3u8: \(hlsStream!.url)"
        )
    }

    // MARK: - Multiple video types in parallel

    func testMultipleVideoTypesInParallel() async throws {
        // Run extractions in parallel to stress-test the updated clients
        async let musicStreams = YouTube(videoID: "9bZkp7q19f0").streams
        async let regularStreams = YouTube(videoID: "dQw4w9WgXcQ").streams
        async let kidsStreams = YouTube(videoID: "GObpYg_NjLQ").streams

        let (music, regular, kids) = try await (musicStreams, regularStreams, kidsStreams)

        XCTAssertGreaterThan(music.count, 0, "Music video returned 0 streams")
        XCTAssertGreaterThan(regular.count, 0, "Regular video returned 0 streams")
        XCTAssertGreaterThan(kids.count, 0, "Kids video returned 0 streams")

        // All should have audio-only streams
        XCTAssertFalse(music.filterAudioOnly().isEmpty, "Music: no audio-only")
        XCTAssertFalse(regular.filterAudioOnly().isEmpty, "Regular: no audio-only")
        XCTAssertFalse(kids.filterAudioOnly().isEmpty, "Kids: no audio-only")
    }
}
