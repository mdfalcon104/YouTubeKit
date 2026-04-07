//
//  InnerTube.swift
//  YouTubeKit
//
//  Created by Alexander Eichhorn on 05.09.21.
//

import Foundation

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
class InnerTube {
    
    private struct Client {
        let name: String
        let version: String
        let screen: String?
        let apiKey: String
        let internalID: Int
        let userAgent: String?
        var playerParams: String? = nil

        var androidSdkVersion: Int? = nil
        var deviceModel: String? = nil
        
        var context: Context {
            // Include hl/timeZone/utcOffsetMinutes — YouTube requires these for consistent responses.
            // Without them, some regions may get restricted or differently-formatted data (yt-dlp default).
            let client = Context.ContextClient(clientName: name, clientVersion: version, clientScreen: screen, androidSdkVersion: androidSdkVersion, deviceModel: deviceModel, hl: "en", timeZone: "UTC", utcOffsetMinutes: 0)
            let thirdParty = screen == "EMBED" ? Context.ThirdParty(embedUrl: "https://www.youtube.com/") : nil
            return Context(client: client, thirdParty: thirdParty)
        }
        
        var headers: [String: String] {
            [
                "User-Agent": userAgent ?? "",
                "X-Youtube-Client-Version": version,
                "X-Youtube-Client-Name": "\(internalID)",
            ].filter { !$0.value.isEmpty }
        }
    }
    
    private struct Context: Encodable {
        let client: ContextClient
        var thirdParty: ThirdParty?

        struct ContextClient: Encodable {
            let clientName: String
            let clientVersion: String
            let clientScreen: String?
            let androidSdkVersion: Int?
            let deviceModel: String?
            // yt-dlp sends these locale fields in every request (Jan 2026).
            // YouTube uses them to determine response format; missing fields may cause
            // different/restricted responses for some regions.
            let hl: String?
            let timeZone: String?
            let utcOffsetMinutes: Int?
        }

        struct ThirdParty: Encodable {
            let embedUrl: String
        }
    }
    
    // overview of clients: https://github.com/zerodytrash/YouTube-Internal-Clients
    // Client versions synced with yt-dlp as of April 2026
    private let defaultClients = [
        // WEB client — SABR-only since Feb 2025, no downloadable stream URLs returned.
        // Kept for metadata/ytcfg extraction but should NOT be used for stream fetching.
        ClientType.web: Client(name: "WEB", version: "2.20260114.08.00", screen: nil, apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", internalID: 1, userAgent: "Mozilla/5.0"),
        // WEB with Safari UA — also SABR-only for adaptive formats, but may return pre-merged HLS.
        ClientType.webSafari: Client(name: "WEB", version: "2.20260114.08.00", screen: nil, apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", internalID: 1, userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)"),
        // ANDROID — bumped from 20.10.38 to 21.02.35 (Jan 2026 yt-dlp #15726).
        // YouTube deprecated 20.x Android versions; old versions may get empty/blocked responses.
        ClientType.android: Client(name: "ANDROID", version: "21.02.35", screen: nil, apiKey: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w", internalID: 3, userAgent: "com.google.android.youtube/21.02.35 (Linux; U; Android 11) gzip", playerParams: "CgIQBg==", androidSdkVersion: 30),
        // androidSdkless REMOVED — YouTube fully deprecated this client in Jan 2026 (yt-dlp #15726).
        // ANDROID_MUSIC — version kept; not typically used for stream extraction.
        ClientType.androidMusic: Client(name: "ANDROID_MUSIC", version: "5.16.51", screen: nil, apiKey: "AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI", internalID: 21, userAgent: "com.google.android.apps.youtube.music/5.16.51 (Linux; U; Android 11) gzip", playerParams: "CgIQBg==", androidSdkVersion: 30),
        // ANDROID_VR — pinned at 1.65.10 intentionally (yt-dlp default).
        // Versions >1.65 return SABR-only streams. This is the safest client for stream URLs:
        // no PO token required, no JS player needed, returns full HTTPS format URLs.
        ClientType.androidVR: Client(name: "ANDROID_VR", version: "1.65.10", screen: nil, apiKey: "", internalID: 28, userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip", androidSdkVersion: 32, deviceModel: "Quest 3"),
        // WEB_EMBEDDED_PLAYER — version already current.
        ClientType.webEmbed: Client(name: "WEB_EMBEDDED_PLAYER", version: "1.20260115.01.00", screen: "EMBED", apiKey: "", internalID: 56, userAgent: "Mozilla/5.0"),
        // WEB_CREATOR — bumped from 1.20250922.03.00 to 1.20260114.05.00 (Jan 2026 yt-dlp).
        // Requires authentication; used for age-gated content bypass.
        ClientType.webCreator: Client(name: "WEB_CREATOR", version: "1.20260114.05.00", screen: nil, apiKey: "", internalID: 62, userAgent: nil),
        // ANDROID_EMBEDDED_PLAYER — kept for embed fallback.
        ClientType.androidEmbed: Client(name: "ANDROID_EMBEDDED_PLAYER", version: "18.11.34", screen: "EMBED", apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", internalID: 3, userAgent: "com.google.android.youtube/18.11.34 (Linux; U; Android 11) gzip"),
        // TVHTML5 — bumped from 7.20250923.13.00 to 7.20260114.12.00 (Jan 2026 yt-dlp).
        // TV client still returns HTTPS format URLs (not SABR-only).
        ClientType.tv: Client(name: "TVHTML5", version: "7.20260114.12.00", screen: nil, apiKey: "", internalID: 7, userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version (unlike Gecko) cobalt/26 (unlike Gecko)"),
        // TVHTML5_SIMPLY_EMBEDDED_PLAYER — kept for embed fallback.
        ClientType.tvEmbed: Client(name: "TVHTML5_SIMPLY_EMBEDDED_PLAYER", version: "2.0", screen: "EMBED", apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", internalID: 85, userAgent: "Mozilla/5.0"),
        // IOS — bumped from 20.10.4 to 21.02.3 (Jan 2026 yt-dlp #15726).
        // YouTube deprecated 20.x iOS versions; old versions may get empty/blocked responses.
        // Returns HTTPS format URLs without requiring JS player.
        ClientType.ios: Client(name: "IOS", version: "21.02.3", screen: nil, apiKey: "", internalID: 5, userAgent: "com.google.ios.youtube/21.02.3 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)", deviceModel: "iPhone16,2"),
        // IOS_MUSIC — kept for potential music content extraction.
        ClientType.iosMusic: Client(name: "IOS_MUSIC", version: "5.21", screen: nil, apiKey: "AIzaSyBAETezhkwP0ZWA02RsqT1zu78Fpt0bC_s", internalID: 26, userAgent: "com.google.ios.youtubemusic/5.21 (iPhone14,3; U; CPU iOS 15_6 like Mac OS X)", deviceModel: "iPhone14,3"),
        // MEDIA_CONNECT_FRONTEND — special client used as last-resort fallback for progressive streams.
        ClientType.mediaConnectFrontend: Client(name: "MEDIA_CONNECT_FRONTEND", version: "0.1", screen: nil, apiKey: "", internalID: 0, userAgent: nil),
        // MWEB — bumped from 2.20250925.01.00 to 2.20260115.01.00 (Jan 2026 yt-dlp).
        ClientType.mWeb: Client(name: "MWEB", version: "2.20260115.01.00", screen: nil, apiKey: "", internalID: 2, userAgent: nil)
    ]
    
    enum ClientType: String {
        // androidSdkless removed — YouTube deprecated this client in Jan 2026 (yt-dlp #15726)
        case web, webSafari, android, androidMusic, androidVR, webEmbed, webCreator, androidEmbed, tv, tvEmbed, ios, iosMusic, mediaConnectFrontend, mWeb
    }
    
    private var accessToken: String?
    private var refreshToken: String?
    
    private let useOAuth: Bool
    private let allowCache: Bool
    
    private let apiKey: String
    private let context: Context
    private let headers: [String: String]
    private let playerParams: String?
    private let encryptedHostFlags: String?

    private let ytcfg: Extraction.YtCfg
    private let signatureTimestamp: Int?
    
    private let baseURL = "https://www.youtube.com/youtubei/v1"
    
    init(client: ClientType = .ios, signatureTimestamp: Int?, ytcfg: Extraction.YtCfg, useOAuth: Bool = false, allowCache: Bool = true) {
        // Single lookup instead of four force-unwraps — crashes with a clear message
        // if a ClientType is added without a matching entry (audit HIGH).
        guard let clientDef = defaultClients[client] else {
            preconditionFailure("Missing client definition for \(client.rawValue)")
        }
        self.context = clientDef.context
        self.apiKey = clientDef.apiKey
        self.headers = clientDef.headers
        self.playerParams = clientDef.playerParams
        self.encryptedHostFlags = client == .webEmbed ? ytcfg.embeddedPlayerEncryptedHostFlags : nil
        self.signatureTimestamp = signatureTimestamp
        self.ytcfg = ytcfg
        self.useOAuth = useOAuth
        self.allowCache = allowCache
        
        if useOAuth && allowCache {
            // TODO: load from cache file
        }
    }
    
    func cacheTokens() {
        guard allowCache else { return }
        // TODO: cache access and refresh tokens
    }
    
    func refreshBearerToken(force: Bool = false) {
        guard useOAuth else { return }
        // TODO: implement refresh of access token
    }
    
    func fetchBearerToken() {
        // TODO: fetch tokens
    }
    
    private struct BaseData: Encodable {
        let context: Context
    }
    
    private var baseData: BaseData {
        return BaseData(context: context)
    }
    
    private var baseParams: [URLQueryItem] {
        [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "contentCheckOk", value: "true"),
            URLQueryItem(name: "racyCheckOk", value: "true")
        ]
    }
    
    private func callAPI<D: Encodable, T: Decodable>(endpoint: String, query: [URLQueryItem], object: D) async throws -> T {
        let data = try JSONEncoder().encode(object)
        return try await callAPI(endpoint: endpoint, query: query, data: data)
    }
    
    private func callAPI<T: Decodable>(endpoint: String, query: [URLQueryItem], data: Data) async throws -> T {

        // TODO: handle oauth case

        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = query

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "post"
        request.httpBody = data
        // Timeout prevents indefinite hang on network stalls (audit P0)
        request.timeoutInterval = 15
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Use client-specific UA from headers first; fall back to ytcfg or generic Safari UA.
        // A realistic User-Agent is critical — YouTube validates UA against clientName/Version
        // and may reject mismatched combinations with empty responses (yt-dlp #14707).
        request.addValue(ytcfg.userAgent ?? "Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.addValue("en-US,en", forHTTPHeaderField: "accept-language")

        // Visitor data identifies the session — YouTube uses it to track request context.
        // Missing visitor data can cause some clients to return restricted responses.
        if let visitorData = ytcfg.visitorData, !visitorData.isEmpty {
            request.addValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        // Origin header — YouTube validates this matches the innertube host.
        // Must be present for web-based clients; mobile clients are more lenient.
        request.addValue("https://www.youtube.com", forHTTPHeaderField: "Origin")

        // Apply client-specific headers (X-YouTube-Client-Name, X-YouTube-Client-Version, User-Agent).
        // These override the defaults above when the client has specific values.
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // TODO: handle oauth auth case again

        let (responseData, _) = try await URLSession.shared.data(for: request)

        return try JSONDecoder().decode(T.self, from: responseData)
    }
    
    struct VideoInfo: Decodable {
        let playabilityStatus: PlayabilityStatus?
        let streamingData: StreamingData?
        let videoDetails: VideoDetails?

        struct PlayabilityStatus: Decodable {
            let status: String?
            let reason: String?
        }

        struct VideoDetails: Decodable {
            let videoId: String
            let title: String?
            let shortDescription: String?
            let thumbnail: Thumbnail

            struct Thumbnail: Decodable {
                let thumbnails: [ThumbnailMetadata]

                struct ThumbnailMetadata: Decodable {
                    let url: URL
                    let width: Int
                    let height: Int
                }
            }
        }
    }
    
    struct StreamingData: Decodable {
        let expiresInSeconds: String?
        let formats: [Format]?
        let adaptiveFormats: [Format]? // actually slightly different Format object (TODO)
        let onesieStreamingUrl: String?
        let hlsManifestUrl: String?
        
        struct Format: Decodable {
            let itag: Int
            var url: String?
            let mimeType: String
            let bitrate: Int?
            let width: Int?
            let height: Int?
            let lastModified: String?
            let contentLength: String?
            let quality: String
            let fps: Int?
            let qualityLabel: String?
            let averageBitrate: Int?
            let audioQuality: String?
            let approxDurationMs: String?
            let audioSampleRate: String?
            let audioChannels: Int?
            let audioTrack: AudioTrack?
            let signatureCipher: String? // not tested yet
            var s: String? // assigned from Extraction.applyDescrambler
            var sp: String? // signature parameter name from signatureCipher
        }
        
        struct AudioTrack: Decodable {
            let displayName: String
            let id: String
            let audioIsDefault: Bool
        }
    }
    
    private struct PlaybackContext: Encodable {
        let contentPlaybackContext: Context
        
        struct Context: Encodable {
            let html5Preference = "HTML5_PREF_WANTS"
            let signatureTimestamp: Int?
            let encryptedHostFlags: String?
        }
    }
    
    private struct PlayerRequest: Encodable {
        let context: Context
        let videoId: String
        let params: String?
        let playbackContext: PlaybackContext
        let contentCheckOk: Bool = true
        let racyCheckOk: Bool = true
    }
    
    private func playerRequest(forVideoID videoID: String) -> PlayerRequest {
        let playbackContext = PlaybackContext(contentPlaybackContext: PlaybackContext.Context(signatureTimestamp: signatureTimestamp, encryptedHostFlags: encryptedHostFlags))
        return PlayerRequest(context: context, videoId: videoID, params: playerParams, playbackContext: playbackContext)
    }
    
    func player(videoID: String) async throws -> VideoInfo {
        let endpoint = baseURL + "/player"
        // Only include API key if non-empty — many newer clients (androidVR, ios, tv)
        // use empty apiKey and rely on context alone for auth (yt-dlp pattern).
        // Including an empty "key" param can cause 400 errors on some endpoints.
        var query = [URLQueryItem(name: "prettyPrint", value: "false")]
        if !apiKey.isEmpty {
            query.insert(URLQueryItem(name: "key", value: apiKey), at: 0)
        }
        let request = playerRequest(forVideoID: videoID)
        return try await callAPI(endpoint: endpoint, query: query, object: request)
    }
    
    // TODO: change result type
    func search(query: String, continuation: String? = nil) async throws -> [String: String] {
        
        struct SearchObject: Encodable {
            let context: Context
            let continuation: String?
        }
        
        let query = baseParams + [
            URLQueryItem(name: "query", value: query)
        ]
        let object = SearchObject(context: context, continuation: continuation)
        return try await callAPI(endpoint: baseURL + "/search", query: query, object: object)
    }
    
    // TODO: change result type
    func verifyAge(videoID: String) async throws -> [String: String] {
        
        struct RequestObject: Encodable {
            let nextEndpoint: NextEndpoint
            let setControvercy: Bool
            let context: Context
            
            struct NextEndpoint: Encodable {
                let urlEndpoint: URLEndpoint
            }
            
            struct URLEndpoint: Encodable {
                let url: String
            }
        }
        
        let object = RequestObject(nextEndpoint: RequestObject.NextEndpoint(urlEndpoint: RequestObject.URLEndpoint(url: "/watch?v=\(videoID)")), setControvercy: true, context: context)
        return try await callAPI(endpoint: baseURL + "/verify_age", query: baseParams, object: object)
    }
    
    // TODO: change result type
    func getTranscript(videoID: String) async throws -> [String: String] {
        let query = baseParams + [
            URLQueryItem(name: "videoID", value: videoID)
        ]
        return try await callAPI(endpoint: baseURL + "/get_transcript", query: query, object: baseData)
    }
    
}
