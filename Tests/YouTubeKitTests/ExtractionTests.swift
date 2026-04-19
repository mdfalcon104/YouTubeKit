//
//  ExtractionTests.swift
//  YouTubeKit
//
//  Created by Alexander Eichhorn on 04.09.21.
//

import XCTest
@testable import YouTubeKit

@available(iOS 15.0, watchOS 8.0, tvOS 15.0, macOS 12.0, *)
final class ExtractionTests: XCTestCase {
    
    func testExtractVideoID() {
        let url = "https://www.youtube.com/watch?v=2lAe1cqCOXo"
        let videoID = Extraction.extractVideoID(from: url)
        XCTAssertEqual(videoID, "2lAe1cqCOXo")
    }

    func testJSURLUsesExtractedPlayerPath() throws {
        let html = #"ytcfg.set({"STS":20515});var ytInitialPlayerResponse = {};var ytplayer = {"config":{"assets":{"js":"/s/player/6c5cb4f4/player_ias.vflset/en_US/base.js"}}};"#
        let jsURL = try Extraction.jsURL(html: html)
        XCTAssertEqual(jsURL, "https://youtube.com/s/player/6c5cb4f4/player_ias.vflset/en_US/base.js")
    }

    func testGetYTPlayerJSMatchesMainVariant() throws {
        let html = #"<script src="/s/player/6c5cb4f4/player_ias.vflset/en_US/base.js"></script>"#
        let path = try Extraction.getYTPlayerJS(html: html)
        XCTAssertEqual(path, "/s/player/6c5cb4f4/player_ias.vflset/en_US/base.js")
    }

    func testGetYTPlayerJSMatchesTVVariant() throws {
        let html = #"<script src="/s/player/76ad2fe8/tv-player-ias.vflset/tv-player-ias.js"></script>"#
        let path = try Extraction.getYTPlayerJS(html: html)
        XCTAssertEqual(path, "/s/player/76ad2fe8/tv-player-ias.vflset/tv-player-ias.js")
    }

    func testGetYTPlayerJSMatchesTVEs6Variant() throws {
        let html = #"<script src="/s/player/631d3938/tv-player-es6.vflset/tv-player-es6.js"></script>"#
        let path = try Extraction.getYTPlayerJS(html: html)
        XCTAssertEqual(path, "/s/player/631d3938/tv-player-es6.vflset/tv-player-es6.js")
    }

    func testGetYTPlayerJSMatchesEs6Variant() throws {
        let html = #"<script src="/s/player/010fbc8d/player_es6.vflset/en_US/base.js"></script>"#
        let path = try Extraction.getYTPlayerJS(html: html)
        XCTAssertEqual(path, "/s/player/010fbc8d/player_es6.vflset/en_US/base.js")
    }

    func testGetYTPlayerJSMatchesPhoneVariant() throws {
        let html = #"<script src="/s/player/20830619/player-plasma-ias-phone-en_US.vflset/base.js"></script>"#
        let path = try Extraction.getYTPlayerJS(html: html)
        XCTAssertEqual(path, "/s/player/20830619/player-plasma-ias-phone-en_US.vflset/base.js")
    }

    func testSignatureTimestampUsesExtractedValue() throws {
        let js = "signatureTimestamp:20515"
        let signatureTimestamp = Extraction.extractSignatureTimestamp(fromJS: js)
        XCTAssertEqual(signatureTimestamp, 20515)
    }

    func testSignatureTimestampReturnsNilWhenMissing() throws {
        let js = "const player = {}"
        let signatureTimestamp = Extraction.extractSignatureTimestamp(fromJS: js)
        XCTAssertNil(signatureTimestamp)
    }

    func testExtractYtCfgParsesEmbeddedEncryptedHostFlags() throws {
        let html = #"ytcfg.set({"VISITOR_DATA":"visitor","WEB_PLAYER_CONTEXT_CONFIGS":{"WEB_PLAYER_CONTEXT_CONFIG_ID_EMBEDDED_PLAYER":{"encryptedHostFlags":"test-flags"}}});"#
        let ytcfg = try Extraction.extractYtCfg(from: html)
        XCTAssertEqual(ytcfg.embeddedPlayerEncryptedHostFlags, "test-flags")
    }
    
}
