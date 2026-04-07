import XCTest
@testable import YouTubeKit

private typealias YTStream = YouTubeKit.Stream

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
final class BestStreamTests: XCTestCase {

    // MARK: - Helpers

    /// Create an audio-only stream (no video codec) with given itag and audio codec string.
    private func makeAudioStream(itag: Int, codec: String, ext: String = "m4a") -> YTStream {
        try! YTStream(remoteStream: RemoteStream(
            url: URL(string: "https://example.com/stream/\(itag)")!,
            itag: itag,
            ext: ext,
            videoCodec: nil,
            audioCodec: codec,
            averageBitrate: nil,
            audioBitrate: nil,
            videoBitrate: nil,
            filesize: nil
        ))
    }

    /// Create a progressive (muxed) stream with both video and audio codecs.
    private func makeProgressiveStream(itag: Int,
                                       videoCodec: String = "avc1.42001E",
                                       audioCodec: String = "mp4a.40.2") -> YTStream {
        try! YTStream(remoteStream: RemoteStream(
            url: URL(string: "https://example.com/stream/\(itag)")!,
            itag: itag,
            ext: "mp4",
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            averageBitrate: nil,
            audioBitrate: nil,
            videoBitrate: nil,
            filesize: nil
        ))
    }

    /// Create a video-only stream (no audio codec).
    private func makeVideoOnlyStream(itag: Int, videoCodec: String = "avc1.42001E") -> YTStream {
        try! YTStream(remoteStream: RemoteStream(
            url: URL(string: "https://example.com/stream/\(itag)")!,
            itag: itag,
            ext: "mp4",
            videoCodec: videoCodec,
            audioCodec: nil,
            averageBitrate: nil,
            audioBitrate: nil,
            videoBitrate: nil,
            filesize: nil
        ))
    }

    // MARK: - pickBestStream: edge cases

    func testPickBestStreamEmptyReturnsNil() {
        let streams: [YTStream] = []
        XCTAssertNil(streams.pickBestStream())
    }

    func testPickBestStreamVideoOnlyReturnsNil() {
        let streams = [
            makeVideoOnlyStream(itag: 136),  // 720p video-only
            makeVideoOnlyStream(itag: 137),  // 1080p video-only
        ]
        XCTAssertNil(streams.pickBestStream())
    }

    func testPickBestStreamOnlyProgressiveReturnsNil() {
        let streams = [
            makeProgressiveStream(itag: 18),   // 360p + 96kbps
            makeProgressiveStream(itag: 22),   // 720p + 192kbps
        ]
        XCTAssertNil(streams.pickBestStream())
    }

    func testPickBestStreamOnlyOpusReturnsNil() {
        // Opus is not natively playable → all candidates filtered out
        let streams = [
            makeAudioStream(itag: 249, codec: "opus", ext: "webm"),  // 50kbps
            makeAudioStream(itag: 250, codec: "opus", ext: "webm"),  // 70kbps
            makeAudioStream(itag: 251, codec: "opus", ext: "webm"),  // 160kbps
        ]
        XCTAssertNil(streams.pickBestStream())
    }

    func testPickBestStreamMixedVideoAndAudioOnlyNoPlayableAudio() {
        // Video-only + opus audio-only → no playable audio candidates
        let streams = [
            makeVideoOnlyStream(itag: 136),
            makeAudioStream(itag: 249, codec: "opus", ext: "webm"),
        ]
        XCTAssertNil(streams.pickBestStream())
    }

    // MARK: - pickBestStream: single candidate

    func testPickBestStreamSingleMp4aCandidate() {
        let streams = [
            makeAudioStream(itag: 140, codec: "mp4a.40.2"),  // 128kbps
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 140)
    }

    func testPickBestStreamSingleLowBitrateMp4a() {
        let streams = [
            makeAudioStream(itag: 139, codec: "mp4a.40.5"),  // 48kbps
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 139)
    }

    // MARK: - pickBestStream: bitrate selection

    func testPickBestStreamPreferHigherKbpsWhenBothMatchTarget() {
        // itag 140 (128kbps) and itag 141 (256kbps) both match a target exactly (tie=0).
        // kbps tiebreaker selects 256kbps.
        let streams = [
            makeAudioStream(itag: 140, codec: "mp4a.40.2"),  // 128kbps
            makeAudioStream(itag: 141, codec: "mp4a.40.2"),  // 256kbps
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 141)
    }

    func testPickBestStreamPreferCloserToTargetOverHigherKbps() {
        // itag 141 (256kbps, delta=0) vs itag 258 (384kbps, delta=128 from target 256).
        // 256kbps wins via tie score despite lower raw kbps.
        let streams = [
            makeAudioStream(itag: 258, codec: "mp4a.40.2"),  // 384kbps, tie=-128
            makeAudioStream(itag: 141, codec: "mp4a.40.2"),  // 256kbps, tie=0
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 141)
    }

    func testPickBestStreamAmongAllMp4aBitrates() {
        // 48, 128, 256 all match targets exactly (tie=0).
        // kbps tiebreaker: 256 > 128 > 48.
        let streams = [
            makeAudioStream(itag: 139, codec: "mp4a.40.5"),  // 48kbps
            makeAudioStream(itag: 140, codec: "mp4a.40.2"),  // 128kbps
            makeAudioStream(itag: 141, codec: "mp4a.40.2"),  // 256kbps
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 141)
    }

    func testPickBestStreamNonTargetBitrateLoses() {
        // itag 256 (192kbps) closest target is 160, delta=32, tie=-32
        // itag 140 (128kbps) matches target exactly, tie=0
        // 128kbps wins via tie score.
        let streams = [
            makeAudioStream(itag: 256, codec: "mp4a.40.2"),  // 192kbps, tie=-32
            makeAudioStream(itag: 140, codec: "mp4a.40.2"),  // 128kbps, tie=0
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 140)
    }

    // MARK: - pickBestStream: filtering

    func testPickBestStreamIgnoresOpusAndProgressiveStreams() {
        let streams = [
            makeAudioStream(itag: 251, codec: "opus", ext: "webm"),   // not natively playable
            makeProgressiveStream(itag: 22),                           // has video, excluded
            makeAudioStream(itag: 140, codec: "mp4a.40.2"),           // 128kbps ✓
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 140)
    }

    func testPickBestStreamIgnoresVideoOnlyStreams() {
        let streams = [
            makeVideoOnlyStream(itag: 136),                           // no audio
            makeAudioStream(itag: 139, codec: "mp4a.40.5"),           // 48kbps ✓
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 139)
    }

    func testPickBestStreamFromRealisticMix() {
        // Simulate a real YouTube response with video-only, progressive, opus, and mp4a streams
        let streams = [
            makeVideoOnlyStream(itag: 136),                                // 720p video
            makeVideoOnlyStream(itag: 137),                                // 1080p video
            makeProgressiveStream(itag: 18),                               // 360p muxed
            makeProgressiveStream(itag: 22),                               // 720p muxed
            makeAudioStream(itag: 249, codec: "opus", ext: "webm"),        // 50kbps opus
            makeAudioStream(itag: 250, codec: "opus", ext: "webm"),        // 70kbps opus
            makeAudioStream(itag: 251, codec: "opus", ext: "webm"),        // 160kbps opus
            makeAudioStream(itag: 139, codec: "mp4a.40.5"),               // 48kbps mp4a
            makeAudioStream(itag: 140, codec: "mp4a.40.2"),               // 128kbps mp4a
            makeAudioStream(itag: 141, codec: "mp4a.40.2"),               // 256kbps mp4a
        ]
        // Only mp4a audio-only streams pass the filter. All match targets → kbps tiebreaker → 256.
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 141)
    }

    // MARK: - pickBestStream: order independence

    func testPickBestStreamOrderIndependent() {
        let stream48  = makeAudioStream(itag: 139, codec: "mp4a.40.5")
        let stream128 = makeAudioStream(itag: 140, codec: "mp4a.40.2")
        let stream256 = makeAudioStream(itag: 141, codec: "mp4a.40.2")

        XCTAssertEqual([stream48, stream128, stream256].pickBestStream()?.itag.itag, 141)
        XCTAssertEqual([stream256, stream48, stream128].pickBestStream()?.itag.itag, 141)
        XCTAssertEqual([stream128, stream256, stream48].pickBestStream()?.itag.itag, 141)
    }

    // MARK: - pickBestStream: codec ranking with natively playable non-mp4a

    #if !os(watchOS)
    func testPickBestStreamPrefersMp4aOverEc3() {
        // ec3 is natively playable (non-watchOS) but ranks as .other
        let streams = [
            makeAudioStream(itag: 328, codec: "ec-3"),                // ec3, 0 kbps, codec=.other
            makeAudioStream(itag: 139, codec: "mp4a.40.5"),           // mp4a, 48kbps, codec=.mp4a
        ]
        // mp4a (rank 2) beats ec3 (rank 1)
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 139)
    }

    func testPickBestStreamPrefersMp4aOverAc3() {
        let streams = [
            makeAudioStream(itag: 380, codec: "ac-3"),                // ac3, 0 kbps, codec=.other
            makeAudioStream(itag: 140, codec: "mp4a.40.2"),           // mp4a, 128kbps
        ]
        XCTAssertEqual(streams.pickBestStream()?.itag.itag, 140)
    }
    #endif

    // MARK: - audioScoreTuple

    func testScoreTupleAudioOnlyPrimaryIs2() {
        let audioOnly = makeAudioStream(itag: 140, codec: "mp4a.40.2")
        XCTAssertEqual(audioOnly.audioScoreTuple().primary, 2)
    }

    func testScoreTupleProgressivePrimaryIs1() {
        let progressive = makeProgressiveStream(itag: 18)
        XCTAssertEqual(progressive.audioScoreTuple().primary, 1)
    }

    func testScoreTupleCodecRankingMp4aHigherThanOpus() {
        let mp4a = makeAudioStream(itag: 140, codec: "mp4a.40.2")
        let opus = makeAudioStream(itag: 251, codec: "opus", ext: "webm")

        // mp4a ranks higher — natively playable in AVPlayer
        XCTAssertGreaterThan(
            mp4a.audioScoreTuple().codec,
            opus.audioScoreTuple().codec
        )
    }

    func testScoreTupleCodecRankingOpusHigherThanUnknown() {
        let opus = makeAudioStream(itag: 251, codec: "opus", ext: "webm")
        let unknown = makeAudioStream(itag: 328, codec: "ec-3")

        XCTAssertGreaterThan(
            opus.audioScoreTuple().codec,
            unknown.audioScoreTuple().codec
        )
    }

    func testScoreTupleKbpsValues() {
        XCTAssertEqual(makeAudioStream(itag: 139, codec: "mp4a.40.5").audioScoreTuple().kbps, 48)
        XCTAssertEqual(makeAudioStream(itag: 140, codec: "mp4a.40.2").audioScoreTuple().kbps, 128)
        XCTAssertEqual(makeAudioStream(itag: 141, codec: "mp4a.40.2").audioScoreTuple().kbps, 256)
        XCTAssertEqual(makeAudioStream(itag: 251, codec: "opus", ext: "webm").audioScoreTuple().kbps, 160)
    }

    func testScoreTupleTieIsZeroWhenExactTargetMatch() {
        // 128kbps matches target 128 exactly → delta=0, tie=0
        let stream = makeAudioStream(itag: 140, codec: "mp4a.40.2")
        XCTAssertEqual(stream.audioScoreTuple().tie, 0)
    }

    func testScoreTupleTieIsNegativeDeltaForNonTarget() {
        // 384kbps closest target is 320, delta=64, tie=-64
        let stream384 = makeAudioStream(itag: 258, codec: "mp4a.40.2")
        XCTAssertEqual(stream384.audioScoreTuple().tie, -64)
    }

    func testScoreTupleTieDeltaForMidRangeBitrate() {
        // 192kbps closest target is 160, delta=32, tie=-32
        let stream192 = makeAudioStream(itag: 256, codec: "mp4a.40.2")
        XCTAssertEqual(stream192.audioScoreTuple().tie, -32)
    }

    func testScoreTupleAllStandardBitratesMatchTargets() {
        // All standard audio itag bitrates appear in the target list
        let standardItags: [(Int, String)] = [
            (139, "mp4a.40.5"),  // 48kbps  → target 48
            (140, "mp4a.40.2"),  // 128kbps → target 128
            (141, "mp4a.40.2"),  // 256kbps → target 256
            (249, "opus"),       // 50kbps  → target 50
            (250, "opus"),       // 70kbps  → target 70
            (251, "opus"),       // 160kbps → target 160
        ]
        for (itag, codec) in standardItags {
            let ext = codec == "opus" ? "webm" : "m4a"
            let stream = makeAudioStream(itag: itag, codec: codec, ext: ext)
            XCTAssertEqual(stream.audioScoreTuple().tie, 0,
                           "itag \(itag) (\(stream.audioKbps)kbps) should match a target exactly")
        }
    }

    func testScoreTupleCustomTargets() {
        let stream = makeAudioStream(itag: 140, codec: "mp4a.40.2")  // 128kbps
        // Custom targets without 128: closest is 64 (delta=64)
        let score = stream.audioScoreTuple(targets: [256, 64])
        XCTAssertEqual(score.tie, -64)
    }

    func testScoreTupleEmptyTargets() {
        let stream = makeAudioStream(itag: 140, codec: "mp4a.40.2")
        let score = stream.audioScoreTuple(targets: [])
        XCTAssertEqual(score.tie, -Int.max)
    }

    // MARK: - audioCodecRank

    func testAudioCodecRankMp4a() {
        let stream = makeAudioStream(itag: 140, codec: "mp4a.40.2")
        XCTAssertEqual(stream.audioCodecRank, AudioCodecRank.mp4a)
    }

    func testAudioCodecRankOpus() {
        let stream = makeAudioStream(itag: 251, codec: "opus", ext: "webm")
        XCTAssertEqual(stream.audioCodecRank, AudioCodecRank.opus)
    }

    func testAudioCodecRankEc3IsOther() {
        let stream = makeAudioStream(itag: 328, codec: "ec-3")
        XCTAssertEqual(stream.audioCodecRank, AudioCodecRank.other)
    }

    func testAudioCodecRankAc3IsOther() {
        let stream = makeAudioStream(itag: 380, codec: "ac-3")
        XCTAssertEqual(stream.audioCodecRank, AudioCodecRank.other)
    }

    func testAudioCodecRankUnknownCodecIsOther() {
        let stream = makeAudioStream(itag: 140, codec: "vorbis")
        XCTAssertEqual(stream.audioCodecRank, AudioCodecRank.other)
    }

    func testAudioCodecRankVideoOnlyIsOther() {
        let stream = makeVideoOnlyStream(itag: 136)
        XCTAssertEqual(stream.audioCodecRank, AudioCodecRank.other)
    }

    func testAudioCodecRankOrdering() {
        XCTAssertLessThan(AudioCodecRank.other, AudioCodecRank.opus)
        XCTAssertLessThan(AudioCodecRank.opus, AudioCodecRank.mp4a)
    }

    // MARK: - isAudioOnly

    func testIsAudioOnlyTrueForAudioStream() {
        let stream = makeAudioStream(itag: 140, codec: "mp4a.40.2")
        XCTAssertTrue(stream.isAudioOnly)
    }

    func testIsAudioOnlyFalseForProgressive() {
        let stream = makeProgressiveStream(itag: 18)
        XCTAssertFalse(stream.isAudioOnly)
    }

    func testIsAudioOnlyFalseForVideoOnly() {
        let stream = makeVideoOnlyStream(itag: 136)
        XCTAssertFalse(stream.isAudioOnly)
    }

    // MARK: - audioKbps

    func testAudioKbpsFromItagTable() {
        XCTAssertEqual(makeAudioStream(itag: 139, codec: "mp4a.40.5").audioKbps, 48)
        XCTAssertEqual(makeAudioStream(itag: 140, codec: "mp4a.40.2").audioKbps, 128)
        XCTAssertEqual(makeAudioStream(itag: 141, codec: "mp4a.40.2").audioKbps, 256)
        XCTAssertEqual(makeAudioStream(itag: 249, codec: "opus", ext: "webm").audioKbps, 50)
        XCTAssertEqual(makeAudioStream(itag: 250, codec: "opus", ext: "webm").audioKbps, 70)
        XCTAssertEqual(makeAudioStream(itag: 251, codec: "opus", ext: "webm").audioKbps, 160)
    }

    func testAudioKbpsZeroForVideoOnly() {
        let stream = makeVideoOnlyStream(itag: 136)
        XCTAssertEqual(stream.audioKbps, 0)
    }

    func testAudioKbpsZeroForNilAudioBitrate() {
        // itag 328 has nil audioBitrate in the table
        let stream = makeAudioStream(itag: 328, codec: "ec-3")
        XCTAssertEqual(stream.audioKbps, 0)
    }

    func testAudioKbpsForProgressiveStream() {
        // itag 18 has audioBitrate=96 in the progressive table
        let stream = makeProgressiveStream(itag: 18)
        XCTAssertEqual(stream.audioKbps, 96)
    }
}
