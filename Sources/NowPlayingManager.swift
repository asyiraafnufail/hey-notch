import Cocoa

typealias MRNowPlayingInfoCallback = @convention(block) ([String: Any]?) -> Void
typealias MRGetNowPlayingInfoFunc = @convention(c) (DispatchQueue, @escaping MRNowPlayingInfoCallback) -> Void

final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private var getNowPlayingInfoFunc: MRGetNowPlayingInfoFunc?

    private init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) {
            if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
                getNowPlayingInfoFunc = unsafeBitCast(sym, to: MRGetNowPlayingInfoFunc.self)
            }
        }
    }

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
}
