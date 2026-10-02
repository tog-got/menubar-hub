import Foundation
import AppKit
import WebKit
import UserNotifications

public protocol VideoDownloaderDelegate: AnyObject {
    func didUpdateDownloadProgress(percent: Double, serviceName: String)
    func didFinishDownload(filename: String, serviceName: String)
    func didFailDownload(error: String)
}

public class VideoDownloader: NSObject, WKScriptMessageHandler, URLSessionDownloadDelegate {
    public static let shared = VideoDownloader()
    public weak var delegate: VideoDownloaderDelegate?
    
    private struct DownloadTaskMetadata {
        let serviceName: String
        let serviceID: ServiceID
        let quality: String
        let format: String
        let isAudio: Bool
    }
    
    private var downloadSession: URLSession!
    private var activeTasks: [Int: DownloadTaskMetadata] = [:]
    private var activeCookieStores: [String: WKHTTPCookieStore] = [:]
    
    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90.0
        config.timeoutIntervalForResource = 600.0
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "videoSaveHandler", let dict = message.body as? [String: Any] {
            let serviceName = dict["service"] as? String ?? "Video"
            let quality = dict["quality"] as? String ?? "Original HD"
            let format = dict["format"] as? String ?? "mp4"
            let isAudio = dict["isAudio"] as? Bool ?? false
            let serviceID = ServiceID.allCases.first { $0.name == serviceName || $0.rawValue == (dict["serviceId"] as? String) } ?? .tiktok
            
            // 1. If Base64 video data received directly from JS
            if let base64Data = dict["dataBase64"] as? String,
               let data = Data(base64Encoded: base64Data), !data.isEmpty {
                
                let validation = validateMediaData(data, isAudio: isAudio)
                if !validation.isValid {
                    DispatchQueue.main.async {
                        self.delegate?.didFailDownload(error: validation.errorMsg ?? "Invalid media stream")
                        self.showErrorAlert(message: validation.errorMsg ?? "Detected a preview image instead of video stream.\nPlease ensure the video is playing and try again.")
                    }
                    return
                }
                
                saveVideoData(data, serviceName: serviceName, format: validation.format, isAudio: isAudio)
                return
            }
            
            // 2. If Direct CDN/MP4 URL extracted
            if let directUrlStr = dict["directUrl"] as? String,
               let directUrl = URL(string: directUrlStr) {
                startDownload(url: directUrl, service: serviceID, serviceName: serviceName, quality: quality, format: format, isAudio: isAudio)
                return
            }
            
            // 3. If Error occurred
            if let errorMsg = dict["error"] as? String {
                DispatchQueue.main.async {
                    self.delegate?.didFailDownload(error: errorMsg)
                    self.showErrorAlert(message: errorMsg)
                }
            }
        }
    }
    
    public func downloadVideo(from webView: WKWebView, service: ServiceID, quality: String) {
        activeCookieStores[service.rawValue] = webView.configuration.websiteDataStore.httpCookieStore
        
        let script = """
        (function() {
            var service = "\(service.name)";
            var serviceId = "\(service.rawValue)";
            var quality = "\(quality)";

            function postError(msg) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({ error: msg });
            }

            function postSuccessData(base64, format, isAudio) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({
                    dataBase64: base64,
                    service: service,
                    serviceId: serviceId,
                    quality: quality,
                    format: format || "mp4",
                    isAudio: isAudio || false
                });
            }

            function postDirectUrl(url, format, isAudio) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({
                    directUrl: url,
                    service: service,
                    serviceId: serviceId,
                    quality: quality,
                    format: format || "mp4",
                    isAudio: isAudio || false
                });
            }

            function cleanUrl(raw) {
                if (!raw || typeof raw !== 'string') return null;
                var u = raw.replace(/\\\\u0026/g, '&')
                           .replace(/\\\\u002F/g, '/')
                           .replace(/\\\\/g, '')
                           .replace(/&amp;/g, '&')
                           .trim();
                return u;
            }

            function isImageUrl(u) {
                if (!u) return false;
                var low = u.toLowerCase();
                if (low.indexOf('.jpeg') !== -1 || low.indexOf('.jpg') !== -1 ||
                    low.indexOf('.png') !== -1 || low.indexOf('.webp') !== -1 ||
                    low.indexOf('~tplv') !== -1 || low.indexOf('mime=image') !== -1 ||
                    low.indexOf('format=jpg') !== -1 || low.indexOf('avatar') !== -1 ||
                    low.indexOf('/image/') !== -1 || low.indexOf('cover') !== -1 ||
                    low.indexOf('tos-alisg-p-') !== -1 || low.indexOf('tos-maliva-p-') !== -1 ||
                    low.indexOf('tos-useast2a-p-') !== -1 || low.indexOf('tos-useast5-p-') !== -1 ||
                    low.indexOf('profile_pic') !== -1 || (low.indexOf('scontent') !== -1 && low.indexOf('/v/t51.') !== -1 && low.indexOf('.jpg') !== -1)) {
                    return true;
                }
                return false;
            }

            function isValidMediaUrl(u) {
                if (!u || typeof u !== 'string') return false;
                if (u.indexOf('http://') !== 0 && u.indexOf('https://') !== 0 && u.indexOf('blob:') !== 0) return false;
                if (isImageUrl(u)) return false;
                return true;
            }

            // --- 1. PINPOINT ACTIVE VIDEO IN VIEWPORT CENTER ---
            var vpWidth = window.innerWidth;
            var vpHeight = window.innerHeight;
            var vpCenterX = vpWidth / 2;
            var vpCenterY = vpHeight / 2;

            var allVideos = Array.from(document.querySelectorAll('video'));
            var candidates = allVideos.map(function(vid) {
                var rect = vid.getBoundingClientRect();
                var isVisible = (rect.bottom > 20 && rect.top < vpHeight - 20 && rect.right > 20 && rect.left < vpWidth - 20);
                var vidCenterX = rect.left + rect.width / 2;
                var vidCenterY = rect.top + rect.height / 2;
                var dist = Math.sqrt(Math.pow(vidCenterX - vpCenterX, 2) + Math.pow(vidCenterY - vpCenterY, 2));
                var isPlaying = (!vid.paused && vid.currentTime > 0.01 && !vid.ended);
                var lastPlayed = vid.__menubarHubLastPlayed || 0;
                
                return {
                    element: vid,
                    rect: rect,
                    isVisible: isVisible,
                    dist: dist,
                    isPlaying: isPlaying,
                    lastPlayed: lastPlayed,
                    currentTime: vid.currentTime
                };
            }).filter(function(c) {
                return c.isVisible;
            });

            candidates.sort(function(a, b) {
                if (a.isPlaying !== b.isPlaying) {
                    return a.isPlaying ? -1 : 1;
                }
                return a.dist - b.dist;
            });

            var activeVideo = candidates.length > 0 ? candidates[0].element : null;

            var activeContainer = null;
            if (activeVideo) {
                activeContainer = activeVideo.closest('[data-e2e="recommend-list-item-container"]') ||
                                  activeVideo.closest('[data-e2e="feed-item"]') ||
                                  activeVideo.closest('[data-e2e="user-post-item"]') ||
                                  activeVideo.closest('div[class*="DivItemContainer"]') ||
                                  activeVideo.closest('div[class*="DivVideoCardContainer"]') ||
                                  activeVideo.closest('div[class*="DivVideoWrapper"]') ||
                                  activeVideo.closest('article[data-testid="tweet"]') ||
                                  activeVideo.closest('article') ||
                                  activeVideo.closest('div[role="dialog"]') ||
                                  activeVideo.closest('div[role="article"]') ||
                                  activeVideo.parentElement.parentElement;
            }

            if (!activeContainer) {
                var centerEl = document.elementFromPoint(vpCenterX, vpCenterY) || document.body;
                activeContainer = centerEl.closest('[data-e2e="recommend-list-item-container"], [data-e2e="feed-item"], [data-e2e="user-post-item"], div[class*="DivItemContainer"], article[data-testid="tweet"], article, div[role="dialog"], div[role="article"]') || centerEl;
                if (!activeVideo && activeContainer) {
                    activeVideo = activeContainer.querySelector('video');
                }
            }

            // --- 2. SAFE REACT FIBER / PROPS WALKER ---
            function walkReactTree(domNode, maxDepth) {
                if (!domNode) return [];
                maxDepth = maxDepth || 18;
                var visited = new Set();
                var results = [];

                function searchProps(obj, depth) {
                    if (!obj || depth > maxDepth || typeof obj !== 'object') return;
                    if (visited.has(obj)) return;
                    visited.add(obj);

                    if (obj.playAddr || obj.downloadAddr || obj.bitrateInfo || obj.play_addr || obj.download_addr || obj.bitrate_info || obj.itemInfo || obj.itemStruct) {
                        results.push(obj);
                    }
                    if (obj.video_versions || obj.playable_url || obj.playable_url_quality_hd || obj.video_url || obj.dash_manifest) {
                        results.push(obj);
                    }
                    if (obj.extended_entities || obj.video_info || (obj.variants && Array.isArray(obj.variants))) {
                        results.push(obj);
                    }

                    try {
                        var keys = Object.keys(obj);
                        for (var i = 0; i < keys.length; i++) {
                            var k = keys[i];
                            if (k === 'stateNode' && obj[k] instanceof HTMLElement) continue;
                            if (k === 'window' || k === 'document' || k === 'current') continue;
                            var val = obj[k];
                            if (val && typeof val === 'object') {
                                searchProps(val, depth + 1);
                            }
                        }
                    } catch(e) {}
                }

                var curr = domNode;
                var levels = 0;
                while (curr && levels < 12) {
                    var keys = Object.keys(curr);
                    for (var i = 0; i < keys.length; i++) {
                        var k = keys[i];
                        if (k.startsWith('__reactFiber$') || k.startsWith('__reactInternalInstance$') || k.startsWith('__reactProps$')) {
                            var fiber = curr[k];
                            var fCurr = fiber;
                            var fDepth = 0;
                            while (fCurr && fDepth < 15) {
                                if (fCurr.memoizedProps) searchProps(fCurr.memoizedProps, 0);
                                if (fCurr.pendingProps) searchProps(fCurr.pendingProps, 0);
                                if (fCurr.memoizedState) searchProps(fCurr.memoizedState, 0);
                                fCurr = fCurr.return || fCurr.child;
                                fDepth++;
                            }
                        }
                    }
                    curr = curr.parentElement;
                    levels++;
                }

                return results;
            }

            // --- 3. PLATFORM RESOLVERS ---

            // A. TikTok
            function resolveTikTok() {
                var videoId = null;
                if (activeContainer) {
                    var links = Array.from(activeContainer.querySelectorAll('a[href]'));
                    for (var i = 0; i < links.length; i++) {
                        var m = links[i].href.match(/\\/video\\/(\\d{15,25})/);
                        if (m) { videoId = m[1]; break; }
                        var mPhoto = links[i].href.match(/\\/photo\\/(\\d{15,25})/);
                        if (mPhoto) { videoId = mPhoto[1]; break; }
                    }
                }
                if (!videoId) {
                    var pageMatch = window.location.href.match(/\\/video\\/(\\d{15,25})/);
                    if (pageMatch) videoId = pageMatch[1];
                }

                var isAudioReq = (quality === "Audio Track");
                var extractedUrls = { best: null, standard: null, audio: null };

                function parseTikTokItem(item) {
                    if (!item) return;
                    var v = item.video || (item.itemInfo && item.itemInfo.video) || (item.itemStruct && item.itemStruct.video) || item;
                    var m = item.music || (item.itemInfo && item.itemInfo.music) || (item.itemStruct && item.itemStruct.music);
                    
                    if (m && (m.playUrl || m.play_url)) {
                        var audioU = cleanUrl(m.playUrl || m.play_url);
                        if (isValidMediaUrl(audioU)) extractedUrls.audio = audioU;
                    }

                    if (v) {
                        var bInfo = v.bitrateInfo || v.bitrate_info || (v.PlayAddr && v.PlayAddr.UrlList);
                        if (Array.isArray(bInfo) && bInfo.length > 0) {
                            var sorted = bInfo.slice().sort(function(a, b) {
                                return (b.Bitrate || b.bitrate || 0) - (a.Bitrate || a.bitrate || 0);
                            });
                            
                            var bestItem = sorted[0];
                            var bestUrlList = (bestItem.PlayAddr && bestItem.PlayAddr.UrlList) || (bestItem.play_addr && bestItem.play_addr.url_list) || bestItem.UrlList || bestItem.url_list;
                            if (Array.isArray(bestUrlList) && bestUrlList.length > 0) {
                                var bU = cleanUrl(bestUrlList[0]);
                                if (isValidMediaUrl(bU)) extractedUrls.best = bU;
                            }

                            var stdIndex = Math.min(1, sorted.length - 1);
                            var stdItem = sorted[stdIndex];
                            var stdUrlList = (stdItem.PlayAddr && stdItem.PlayAddr.UrlList) || (stdItem.play_addr && stdItem.play_addr.url_list) || stdItem.UrlList || stdItem.url_list;
                            if (Array.isArray(stdUrlList) && stdUrlList.length > 0) {
                                var sU = cleanUrl(stdUrlList[0]);
                                if (isValidMediaUrl(sU)) extractedUrls.standard = sU;
                            }
                        }

                        var dlAddr = cleanUrl(v.downloadAddr || v.download_addr);
                        var plAddr = cleanUrl(v.playAddr || v.play_addr);

                        if (isValidMediaUrl(dlAddr) && !extractedUrls.best) extractedUrls.best = dlAddr;
                        if (isValidMediaUrl(plAddr)) {
                            if (!extractedUrls.best) extractedUrls.best = plAddr;
                            if (!extractedUrls.standard) extractedUrls.standard = plAddr;
                        }
                    }
                }

                // 1. React tree search
                var reactObjects = walkReactTree(activeVideo || activeContainer, 18);
                if (reactObjects && reactObjects.length > 0) {
                    for (var i = 0; i < reactObjects.length; i++) {
                        var obj = reactObjects[i];
                        var objId = obj.id || obj.awemeId || (obj.itemInfo && obj.itemInfo.id) || (obj.itemStruct && obj.itemStruct.id);
                        if (!videoId || !objId || String(objId) === String(videoId)) {
                            parseTikTokItem(obj);
                            if (extractedUrls.best) break;
                        }
                    }
                }

                // 2. Global Universal Data search
                if (!extractedUrls.best) {
                    try {
                        var uDataEl = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
                        if (uDataEl && uDataEl.textContent) {
                            var parsed = JSON.parse(uDataEl.textContent);
                            var scope = parsed.__DEFAULT_SCOPE__ || parsed.defaultScope || {};
                            var appContext = scope['webapp.app-context'] || {};
                            var videoDetail = scope['webapp.video-detail'] || {};
                            
                            var itemMod = appContext.itemModule || {};
                            if (videoId && itemMod[videoId]) {
                                parseTikTokItem(itemMod[videoId]);
                            }

                            if (!extractedUrls.best && videoDetail.itemInfo && videoDetail.itemInfo.itemStruct) {
                                parseTikTokItem(videoDetail.itemInfo.itemStruct);
                            }

                            if (!extractedUrls.best) {
                                var stack = [parsed];
                                var visitedJson = new Set();
                                while (stack.length > 0 && !extractedUrls.best) {
                                    var curr = stack.pop();
                                    if (!curr || typeof curr !== 'object' || visitedJson.has(curr)) continue;
                                    visitedJson.add(curr);
                                    
                                    if (curr.playAddr || curr.downloadAddr || curr.bitrateInfo) {
                                        var cId = curr.id || curr.awemeId;
                                        if (!videoId || !cId || String(cId) === String(videoId)) {
                                            parseTikTokItem(curr);
                                        }
                                    }

                                    var keys = Object.keys(curr);
                                    for (var k = 0; k < keys.length; k++) {
                                        if (curr[k] && typeof curr[k] === 'object') {
                                            stack.push(curr[k]);
                                        }
                                    }
                                }
                            }
                        }
                    } catch(e) {}
                }

                // 3. SIGI_STATE (legacy)
                if (!extractedUrls.best && window.SIGI_STATE) {
                    try {
                        if (videoId && window.SIGI_STATE.ItemModule && window.SIGI_STATE.ItemModule[videoId]) {
                            parseTikTokItem(window.SIGI_STATE.ItemModule[videoId]);
                        }
                    } catch(e) {}
                }

                // 4. Network & media history
                if (!extractedUrls.best && window.__menubarHubMediaHistory && window.__menubarHubMediaHistory.length > 0) {
                    for (var h = window.__menubarHubMediaHistory.length - 1; h >= 0; h--) {
                        var entry = window.__menubarHubMediaHistory[h];
                        if (isValidMediaUrl(entry.url)) {
                            if (!videoId || (entry.videoId && entry.videoId === videoId) || (entry.url.indexOf(videoId) !== -1)) {
                                extractedUrls.best = entry.url;
                                break;
                            }
                        }
                    }
                    if (!extractedUrls.best && window.__menubarHubMediaHistory.length > 0) {
                        var lastEntry = window.__menubarHubMediaHistory[window.__menubarHubMediaHistory.length - 1];
                        if (isValidMediaUrl(lastEntry.url)) {
                            extractedUrls.best = lastEntry.url;
                        }
                    }
                }

                if (isAudioReq && extractedUrls.audio) {
                    return { url: extractedUrls.audio, format: "mp3", isAudio: true };
                }
                if (quality === "720p Standard" && extractedUrls.standard) {
                    return { url: extractedUrls.standard, format: "mp4", isAudio: false };
                }
                if (extractedUrls.best) {
                    return { url: extractedUrls.best, format: "mp4", isAudio: false };
                }

                return null;
            }

            // B. Instagram & Threads
            function resolveInstagramOrThreads() {
                var isAudioReq = (quality === "Audio Track");
                var bestUrl = null;
                var stdUrl = null;
                var audioUrl = null;

                if (activeVideo) {
                    var s = activeVideo.currentSrc || activeVideo.src;
                    if (s && s.indexOf('blob:') !== 0 && isValidMediaUrl(s)) {
                        bestUrl = cleanUrl(s);
                    } else {
                        var srcTags = Array.from(activeVideo.querySelectorAll('source'));
                        for (var i = 0; i < srcTags.length; i++) {
                            if (isValidMediaUrl(srcTags[i].src)) {
                                bestUrl = cleanUrl(srcTags[i].src);
                                break;
                            }
                        }
                    }
                }

                var reactObjects = walkReactTree(activeVideo || activeContainer, 18);
                if (reactObjects && reactObjects.length > 0) {
                    for (var i = 0; i < reactObjects.length; i++) {
                        var obj = reactObjects[i];
                        if (Array.isArray(obj.video_versions) && obj.video_versions.length > 0) {
                            var sorted = obj.video_versions.slice().sort(function(a, b) {
                                return (b.width || 0) - (a.width || 0);
                            });
                            if (sorted[0] && sorted[0].url) bestUrl = cleanUrl(sorted[0].url);
                            var std = sorted[Math.min(1, sorted.length - 1)];
                            if (std && std.url) stdUrl = cleanUrl(std.url);
                        }
                        if (obj.playable_url_quality_hd) bestUrl = cleanUrl(obj.playable_url_quality_hd);
                        else if (obj.playable_url && !bestUrl) bestUrl = cleanUrl(obj.playable_url);
                        else if (obj.video_url && !bestUrl) bestUrl = cleanUrl(obj.video_url);

                        if (obj.audio_src || obj.audio_url) audioUrl = cleanUrl(obj.audio_src || obj.audio_url);
                    }
                }

                if (!bestUrl && window.__menubarHubMediaHistory && window.__menubarHubMediaHistory.length > 0) {
                    for (var h = window.__menubarHubMediaHistory.length - 1; h >= 0; h--) {
                        var entry = window.__menubarHubMediaHistory[h];
                        if (isValidMediaUrl(entry.url) && (entry.url.indexOf('cdninstagram.com') !== -1 || entry.url.indexOf('fbcdn.net') !== -1)) {
                            bestUrl = entry.url;
                            break;
                        }
                    }
                }

                if (isAudioReq && audioUrl) return { url: audioUrl, format: "m4a", isAudio: true };
                if (quality === "720p Standard" && stdUrl) return { url: stdUrl, format: "mp4", isAudio: false };
                if (bestUrl) return { url: bestUrl, format: "mp4", isAudio: false };
                return null;
            }

            // C. Facebook
            function resolveFacebook() {
                var bestUrl = null;
                var stdUrl = null;

                if (activeVideo) {
                    var s = activeVideo.currentSrc || activeVideo.src;
                    if (s && s.indexOf('blob:') !== 0 && isValidMediaUrl(s)) {
                        bestUrl = cleanUrl(s);
                    }
                }

                var reactObjects = walkReactTree(activeVideo || activeContainer, 18);
                if (reactObjects && reactObjects.length > 0) {
                    for (var i = 0; i < reactObjects.length; i++) {
                        var obj = reactObjects[i];
                        if (obj.playable_url_quality_hd) bestUrl = cleanUrl(obj.playable_url_quality_hd);
                        if (obj.playable_url) {
                            if (!bestUrl) bestUrl = cleanUrl(obj.playable_url);
                            stdUrl = cleanUrl(obj.playable_url);
                        }
                        if (obj.hd_src) bestUrl = cleanUrl(obj.hd_src);
                        if (obj.sd_src && !stdUrl) stdUrl = cleanUrl(obj.sd_src);
                    }
                }

                if (!bestUrl && window.__menubarHubMediaHistory && window.__menubarHubMediaHistory.length > 0) {
                    for (var h = window.__menubarHubMediaHistory.length - 1; h >= 0; h--) {
                        var entry = window.__menubarHubMediaHistory[h];
                        if (isValidMediaUrl(entry.url) && entry.url.indexOf('fbcdn.net') !== -1) {
                            bestUrl = entry.url;
                            break;
                        }
                    }
                }

                if (quality === "720p Standard" && stdUrl) return { url: stdUrl, format: "mp4", isAudio: false };
                if (bestUrl) return { url: bestUrl, format: "mp4", isAudio: false };
                return null;
            }

            // D. X (Twitter)
            function resolveX() {
                var bestUrl = null;
                var stdUrl = null;

                if (activeVideo) {
                    var s = activeVideo.currentSrc || activeVideo.src;
                    if (s && s.indexOf('blob:') !== 0 && isValidMediaUrl(s)) {
                        bestUrl = cleanUrl(s);
                    }
                }

                var reactObjects = walkReactTree(activeVideo || activeContainer, 18);
                if (reactObjects && reactObjects.length > 0) {
                    for (var i = 0; i < reactObjects.length; i++) {
                        var obj = reactObjects[i];
                        var mediaList = (obj.extended_entities && obj.extended_entities.media) ||
                                        (obj.tweet && obj.tweet.extended_entities && obj.tweet.extended_entities.media) ||
                                        (obj.media && Array.isArray(obj.media) ? obj.media : null);
                        
                        if (Array.isArray(mediaList)) {
                            for (var m = 0; m < mediaList.length; m++) {
                                var vInfo = mediaList[m].video_info;
                                if (vInfo && Array.isArray(vInfo.variants)) {
                                    var mp4s = vInfo.variants.filter(function(v) {
                                        return v.content_type === "video/mp4" && v.url;
                                    }).sort(function(a, b) {
                                        return (b.bitrate || 0) - (a.bitrate || 0);
                                    });

                                    if (mp4s.length > 0) {
                                        bestUrl = cleanUrl(mp4s[0].url);
                                        var std = mp4s[Math.min(1, mp4s.length - 1)];
                                        if (std) stdUrl = cleanUrl(std.url);
                                        break;
                                    }
                                }
                            }
                        }

                        if (Array.isArray(obj.variants)) {
                            var mp4s2 = obj.variants.filter(function(v) {
                                return v.content_type === "video/mp4" && v.url;
                            }).sort(function(a, b) {
                                return (b.bitrate || 0) - (a.bitrate || 0);
                            });
                            if (mp4s2.length > 0) {
                                bestUrl = cleanUrl(mp4s2[0].url);
                                var std2 = mp4s2[Math.min(1, mp4s2.length - 1)];
                                if (std2) stdUrl = cleanUrl(std2.url);
                            }
                        }
                    }
                }

                if (!bestUrl && window.__menubarHubMediaHistory && window.__menubarHubMediaHistory.length > 0) {
                    for (var h = window.__menubarHubMediaHistory.length - 1; h >= 0; h--) {
                        var entry = window.__menubarHubMediaHistory[h];
                        if (isValidMediaUrl(entry.url) && entry.url.indexOf('twimg.com') !== -1) {
                            bestUrl = entry.url;
                            break;
                        }
                    }
                }

                if (quality === "720p Standard" && stdUrl) return { url: stdUrl, format: "mp4", isAudio: false };
                if (bestUrl) return { url: bestUrl, format: "mp4", isAudio: false };
                return null;
            }

            // --- 4. EXECUTE EXTRACTION ---
            var result = null;
            if (serviceId === "tiktok" || service === "TikTok") {
                result = resolveTikTok();
            } else if (serviceId === "instagram" || service === "Instagram" || serviceId === "threads" || service === "Threads") {
                result = resolveInstagramOrThreads();
            } else if (serviceId === "facebook" || service === "Facebook") {
                result = resolveFacebook();
            } else if (serviceId === "x" || service === "X (Twitter)" || service === "X") {
                result = resolveX();
            } else {
                result = resolveTikTok() || resolveInstagramOrThreads() || resolveFacebook() || resolveX();
            }

            if (!result || !result.url) {
                postError("Could not retrieve video stream. Please ensure the video is playing.");
                return;
            }

            if (result.url.indexOf('blob:') === 0) {
                fetch(result.url)
                    .then(function(res) { return res.blob(); })
                    .then(function(blob) {
                        var reader = new FileReader();
                        reader.onloadend = function() {
                            var b64 = (reader.result || '').split(',')[1];
                            if (b64 && b64.length > 1000) {
                                postSuccessData(b64, result.format, result.isAudio);
                            } else {
                                postError("Blob stream conversion failed.");
                            }
                        };
                        reader.readAsDataURL(blob);
                    })
                    .catch(function(err) {
                        postError("Failed to read video blob stream.");
                    });
                return;
            }

            postDirectUrl(result.url, result.format, result.isAudio);
        })();
        """
        
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                NSLog("[VideoDownloader] JavaScript evaluation error: %@", error.localizedDescription)
            }
        }
    }
    
    private func startDownload(url: URL, service: ServiceID, serviceName: String, quality: String, format: String, isAudio: Bool) {
        let cookieStore = activeCookieStores[service.rawValue] ?? WKWebsiteDataStore.default().httpCookieStore
        
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 120.0
            
            let headerFields = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, val) in headerFields {
                request.setValue(val, forHTTPHeaderField: key)
            }
            
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue(service.url.absoluteString, forHTTPHeaderField: "Referer")
            if let host = service.url.host {
                request.setValue("https://\(host)", forHTTPHeaderField: "Origin")
            }
            request.setValue("bytes=0-", forHTTPHeaderField: "Range")
            request.setValue(isAudio ? "audio" : "video", forHTTPHeaderField: "Sec-Fetch-Dest")
            request.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
            
            let task = self.downloadSession.downloadTask(with: request)
            self.activeTasks[task.taskIdentifier] = DownloadTaskMetadata(
                serviceName: serviceName,
                serviceID: service,
                quality: quality,
                format: format,
                isAudio: isAudio
            )
            task.resume()
            
            DispatchQueue.main.async {
                self.delegate?.didUpdateDownloadProgress(percent: 0.0, serviceName: serviceName)
                self.showNotification(
                    title: "Downloading \(serviceName) \(isAudio ? "Audio" : "Video")...",
                    body: "Quality: \(quality). File will be saved to your Downloads folder."
                )
            }
        }
    }
    
    private func validateMediaData(_ data: Data, isAudio: Bool) -> (isValid: Bool, format: String, errorMsg: String?) {
        guard data.count >= 50000 else {
            return (false, "unknown", "Downloaded media file is too small (\(data.count) bytes).")
        }
        
        // JPEG Check: FF D8 FF
        if data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
            return (false, "jpeg", "Captured preview image instead of video.")
        }
        
        // PNG Check: 89 50 4E 47
        if data.count >= 4 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
            return (false, "png", "Captured image preview instead of video.")
        }
        
        // WebP Check: RIFF ... WEBP
        if data.count >= 12 {
            let riff = String(data: data.subdata(in: 0..<4), encoding: .ascii)
            let webp = String(data: data.subdata(in: 8..<12), encoding: .ascii)
            if riff == "RIFF" && webp == "WEBP" {
                return (false, "webp", "Captured image preview instead of video.")
            }
        }
        
        // HTML error check
        let prefixText = String(data: data.prefix(min(data.count, 128)), encoding: .utf8)?.lowercased() ?? ""
        if prefixText.contains("<!doctype") || prefixText.contains("<html") || prefixText.contains("{\"error\"") {
            return (false, "html", "Media stream link expired or access was denied.")
        }
        
        // MP4 / ISO BMFF / QuickTime
        if data.count >= 12 {
            let brand = String(data: data.subdata(in: 4..<8), encoding: .ascii) ?? ""
            if brand == "ftyp" || brand == "moov" || brand == "mdat" || brand == "free" || brand == "wide" {
                return (true, isAudio ? "m4a" : "mp4", nil)
            }
        }
        
        // MP3 Check: ID3 or MPEG sync frame
        if data.count >= 3 && data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33 {
            return (true, "mp3", nil)
        }
        if data.count >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
            return (true, "mp3", nil)
        }
        
        // WebM: 1A 45 DF A3
        if data.count >= 4 && data[0] == 0x1A && data[1] == 0x45 && data[2] == 0xDF && data[3] == 0xA3 {
            return (true, "webm", nil)
        }
        
        return (true, isAudio ? "mp3" : "mp4", nil)
    }
    
    private func saveVideoData(_ data: Data, serviceName: String, format: String, isAudio: Bool) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let ext = format.isEmpty ? (isAudio ? "mp3" : "mp4") : format
        let filename = "\(serviceName)_\(timestamp)\(isAudio ? "_audio" : "").\(ext)"
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationURL = downloadsDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: destinationURL)
            DispatchQueue.main.async {
                self.delegate?.didFinishDownload(filename: filename, serviceName: serviceName)
                self.showNotification(
                    title: "🎬 \(serviceName) \(isAudio ? "Audio" : "Video") Downloaded!",
                    body: "Saved as \(filename) in ~/Downloads"
                )
            }
        } catch {
            NSLog("[VideoDownloader] Failed to write data: %@", error.localizedDescription)
            DispatchQueue.main.async {
                self.delegate?.didFailDownload(error: error.localizedDescription)
                self.showErrorAlert(message: "Failed to save file: \(error.localizedDescription)")
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let percent = min(100.0, max(0.0, progress * 100.0))
            let taskInfo = activeTasks[downloadTask.taskIdentifier]
            let serviceName = taskInfo?.serviceName ?? "Video"
            
            DispatchQueue.main.async {
                self.delegate?.didUpdateDownloadProgress(percent: percent, serviceName: serviceName)
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskInfo = activeTasks[downloadTask.taskIdentifier]
        let serviceName = taskInfo?.serviceName ?? "Video"
        let isAudio = taskInfo?.isAudio ?? false
        let format = taskInfo?.format ?? (isAudio ? "mp3" : "mp4")
        
        if let httpResponse = downloadTask.response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            DispatchQueue.main.async {
                self.delegate?.didFailDownload(error: "Server returned HTTP \(httpResponse.statusCode)")
                self.showErrorAlert(message: "Download failed: Server returned HTTP status \(httpResponse.statusCode).\nPlease try again.")
            }
            activeTasks.removeValue(forKey: downloadTask.taskIdentifier)
            return
        }
        
        do {
            let fileData = try Data(contentsOf: location, options: .mappedIfSafe)
            let validation = validateMediaData(fileData, isAudio: isAudio)
            
            if !validation.isValid {
                DispatchQueue.main.async {
                    self.delegate?.didFailDownload(error: validation.errorMsg ?? "Invalid file format")
                    self.showErrorAlert(message: validation.errorMsg ?? "Downloaded file is not a valid video stream.\nPlease ensure the video is playing and try again.")
                }
                activeTasks.removeValue(forKey: downloadTask.taskIdentifier)
                return
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            
            let finalFormat = validation.format.isEmpty ? format : validation.format
            let filename = "\(serviceName)_\(timestamp)\(isAudio ? "_audio" : "").\(finalFormat)"
            let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let destinationURL = downloadsDirectory.appendingPathComponent(filename)
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                self.delegate?.didFinishDownload(filename: filename, serviceName: serviceName)
                self.showNotification(
                    title: "🎬 \(serviceName) \(isAudio ? "Audio" : "Video") Downloaded!",
                    body: "Saved as \(filename) in ~/Downloads"
                )
            }
        } catch {
            NSLog("[VideoDownloader] Failed to process downloaded video: %@", error.localizedDescription)
            DispatchQueue.main.async {
                self.delegate?.didFailDownload(error: error.localizedDescription)
                self.showErrorAlert(message: "Failed to save downloaded video: \(error.localizedDescription)")
            }
        }
        
        activeTasks.removeValue(forKey: downloadTask.taskIdentifier)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            NSLog("[VideoDownloader] Download task failed: %@", error.localizedDescription)
            DispatchQueue.main.async {
                self.delegate?.didFailDownload(error: error.localizedDescription)
                self.showErrorAlert(message: "Download failed: \(error.localizedDescription)")
            }
        }
        activeTasks.removeValue(forKey: task.taskIdentifier)
    }
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Download Video"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    public func openDownloadsFolder() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        NSWorkspace.shared.open(downloadsURL)
    }
}
