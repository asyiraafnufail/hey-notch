import Cocoa

typealias MRNowPlayingInfoCallback = @convention(block) ([String: Any]?) -> Void
typealias MRGetNowPlayingInfoFunc = @convention(c) (DispatchQueue, @escaping MRNowPlayingInfoCallback) -> Void
typealias MRSendCommandFunc = @convention(c) (UInt32, CFDictionary?) -> DarwinBoolean
typealias MRGetIsPlayingFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (DarwinBoolean) -> Void) -> Void

final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private var getNowPlayingInfoFunc: MRGetNowPlayingInfoFunc?
    private var sendCommandFunc: MRSendCommandFunc?
    private var getIsPlayingFunc: MRGetIsPlayingFunc?

    private init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) {
            if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
                getNowPlayingInfoFunc = unsafeBitCast(sym, to: MRGetNowPlayingInfoFunc.self)
            }
            if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
                sendCommandFunc = unsafeBitCast(sym, to: MRSendCommandFunc.self)
            }
            if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
                getIsPlayingFunc = unsafeBitCast(sym, to: MRGetIsPlayingFunc.self)
            }
        }
    }

    // MARK: - Query Track Metadata
    func queryNowPlaying(completion: @escaping (String?, String?) -> Void) {
        guard let getInfo = getNowPlayingInfoFunc else {
            completion(nil, nil)
            return
        }
        getInfo(DispatchQueue.main) { info in
            guard let info = info else {
                completion(nil, nil)
                return
            }
            let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
            let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
            completion(title, artist)
        }
    }

    // MARK: - Query Playback State
    func checkIsPlaying(completion: @escaping (Bool) -> Void) {
        guard let getPlaying = getIsPlayingFunc else {
            completion(false)
            return
        }
        getPlaying(DispatchQueue.main) { isPlaying in
            completion(isPlaying.boolValue)
        }
    }

    // MARK: - Media Remote Commands (Zero Permission, Control Center Protocol)
    // MRMediaRemoteCommandTogglePlayPause = 2
    // MRMediaRemoteCommandNextTrack = 4
    // MRMediaRemoteCommandPreviousTrack = 5
    @discardableResult
    func togglePlayPause() -> Bool {
        if let send = sendCommandFunc {
            return send(2, nil).boolValue
        }
        return false
    }

    @discardableResult
    func nextTrack() -> Bool {
        if let send = sendCommandFunc {
            return send(4, nil).boolValue
        }
        return false
    }

    @discardableResult
    func previousTrack() -> Bool {
        if let send = sendCommandFunc {
            return send(5, nil).boolValue
        }
        return false
    }
}
