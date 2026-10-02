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
    
    private var downloadSession: URLSession!
    private var activeTasks: [Int: (serviceName: String, quality: String)] = [:]
    
    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "videoSaveHandler", let dict = message.body as? [String: Any] {
            let serviceName = dict["service"] as? String ?? "Video"
            let quality = dict["quality"] as? String ?? "Best"
            
            // 1. If Base64 video data received directly from JS
            if let base64Data = dict["dataBase64"] as? String,
               let data = Data(base64Encoded: base64Data), !data.isEmpty {
                
                if isJpegData(data) {
                    DispatchQueue.main.async {
                        self.delegate?.didFailDownload(error: "Captured preview image instead of video")
                        self.showErrorAlert(message: "Detected a thumbnail preview instead of video stream.\nPlease ensure the video is currently playing and try again.")
                    }
                    return
                }
                
                saveVideoData(data, serviceName: serviceName)
                return
            }
            
            // 2. If Direct CDN/MP4 URL extracted
            if let directUrlStr = dict["directUrl"] as? String,
               let directUrl = URL(string: directUrlStr) {
                startDownload(url: directUrl, serviceName: serviceName, quality: quality)
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
    
    private func isJpegData(_ data: Data) -> Bool {
        guard data.count > 3 else { return false }
        let prefix = data.subdata(in: 0..<3)
        return prefix == Data([0xFF, 0xD8, 0xFF])
    }
    
    public func downloadVideo(from webView: WKWebView, service: ServiceID, quality: String) {
        let script = """
        (function() {
            var service = "\(service.name)";
            var quality = "\(quality)";

            function postError(msg) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({ error: msg });
            }

            function postSuccessData(base64) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({
                    dataBase64: base64,
                    service: service,
                    quality: quality
                });
            }

            function postDirectUrl(url) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({
                    directUrl: url,
                    service: service,
                    quality: quality
                });
            }

            function isValidVideoUrl(url) {
                if (!url || typeof url !== 'string' || url.indexOf('http') !== 0) return false;
                var lower = url.toLowerCase();
                
                if (lower.indexOf('.jpeg') !== -1 || lower.indexOf('.jpg') !== -1 ||
                    lower.indexOf('.png') !== -1 || lower.indexOf('.webp') !== -1 ||
                    lower.indexOf('~tplv') !== -1 || lower.indexOf('/obj/tos-alisg-p-') !== -1 ||
                    lower.indexOf('/obj/tos-maliva-p-') !== -1 || lower.indexOf('mime=image') !== -1 ||
                    lower.indexOf('format=jpg') !== -1 || lower.indexOf('avatar') !== -1 ||
                    lower.indexOf('/image/') !== -1 || lower.indexOf('cover') !== -1) {
                    return false;
                }
                
                if (lower.indexOf('.mp4') !== -1 || lower.indexOf('mime_type=video_mp4') !== -1 ||
                    lower.indexOf('/video/tos/') !== -1 || lower.indexOf('video_id=') !== -1 ||
                    lower.indexOf('&bytestart=') !== -1 || lower.indexOf('mime=video') !== -1 ||
                    lower.indexOf('/play/') !== -1 || (lower.indexOf('cdninstagram.com') !== -1 && lower.indexOf('&efg=') !== -1) ||
                    (lower.indexOf('tiktokcdn.com') !== -1 && lower.indexOf('/video/') !== -1) ||
                    (lower.indexOf('byteoversea.com') !== -1 && lower.indexOf('/video/') !== -1) ||
                    (lower.indexOf('ibytedtos.com') !== -1 && lower.indexOf('/video/') !== -1)) {
                    return true;
                }
                return false;
            }

            var chosenUrl = null;

            // --- 1. Find the Exact Active Feed Item Container at Screen Center ---
            var vpCenterX = window.innerWidth / 2;
            var vpCenterY = window.innerHeight / 2;
            var centerEl = document.elementFromPoint(vpCenterX, vpCenterY) || document.body;
            
            var container = centerEl.closest('[data-e2e="recommend-list-item-container"], [class*="DivItemContainer"], [class*="DivVideoWrapper"], article, [data-e2e="feed-video"]') || centerEl;

            // --- 2. TikTok Specific: Extract by Unique Video ID ---
            var tiktokLink = container.querySelector('a[href*="/video/"]') || document.querySelector('a[href*="/video/"]');
            var videoIdMatch = (tiktokLink && tiktokLink.href) ? tiktokLink.href.match(/\\/video\\/(\\d+)/) : window.location.pathname.match(/\\/video\\/(\\d+)/);
            var videoId = videoIdMatch ? videoIdMatch[1] : null;

            if (videoId) {
                // Check __UNIVERSAL_DATA_FOR_REHYDRATION__
                try {
                    var scriptEl = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
                    if (scriptEl && scriptEl.textContent) {
                        var parsed = JSON.parse(scriptEl.textContent);
                        var itemModule = (parsed.__DEFAULT_SCOPE__ && parsed.__DEFAULT_SCOPE__['webapp.app-context'] && parsed.__DEFAULT_SCOPE__['webapp.app-context'].itemModule) ||
                                         (parsed.defaultScope && parsed.defaultScope['webapp.app-context'] && parsed.defaultScope['webapp.app-context'].itemModule);
                        if (itemModule && itemModule[videoId] && itemModule[videoId].video) {
                            var vObj = itemModule[videoId].video;
                            var playUrl = vObj.playAddr || vObj.downloadAddr;
                            if (playUrl && isValidVideoUrl(playUrl)) {
                                chosenUrl = playUrl;
                            }
                        }
                    }
                } catch(e) {}
                
                // Check SIGI_STATE
                if (!chosenUrl && window.SIGI_STATE && window.SIGI_STATE.ItemModule && window.SIGI_STATE.ItemModule[videoId]) {
                    var sigiItem = window.SIGI_STATE.ItemModule[videoId];
                    if (sigiItem.video && (sigiItem.video.playAddr || sigiItem.video.downloadAddr)) {
                        var sUrl = sigiItem.video.playAddr || sigiItem.video.downloadAddr;
                        if (isValidVideoUrl(sUrl)) chosenUrl = sUrl;
                    }
                }
            }

            // --- 3. React Fiber Props on the exact active element ---
            if (!chosenUrl && container) {
                var el = container;
                var count = 0;
                while (el && el !== document.body && count < 6 && !chosenUrl) {
                    count++;
                    for (var key in el) {
                        if (key.indexOf('__react') === 0) {
                            try {
                                var val = el[key];
                                function safeScan(obj, depth) {
                                    if (!obj || depth > 4 || typeof obj !== 'object' || chosenUrl) return;
                                    var propKeys = Object.keys(obj);
                                    for (var k = 0; k < propKeys.length; k++) {
                                        var p = propKeys[k];
                                        if (typeof obj[p] === 'string') {
                                            var str = obj[p];
                                            if (isValidVideoUrl(str)) {
                                                chosenUrl = str.replace(/\\\\u0026/g, '&').replace(/\\\\/g, '');
                                                return;
                                            }
                                        } else if (typeof obj[p] === 'object' && obj[p] !== null && !Array.isArray(obj[p])) {
                                            safeScan(obj[p], depth + 1);
                                        }
                                    }
                                }
                                safeScan(val, 0);
                            } catch(e) {}
                        }
                    }
                    el = el.parentElement;
                }
            }

            // --- 4. Instagram / Threads / FB / X Specific: Extract from container's video tag ---
            if (!chosenUrl) {
                var vidInside = container.querySelector('video');
                if (vidInside) {
                    if (vidInside.__exactMediaUrl && isValidVideoUrl(vidInside.__exactMediaUrl)) {
                        chosenUrl = vidInside.__exactMediaUrl;
                    }
                    if (!chosenUrl) {
                        var vSrc = vidInside.currentSrc || vidInside.src;
                        if (!vSrc || vSrc.indexOf('blob:') === 0) {
                            var source = vidInside.querySelector('source');
                            if (source) vSrc = source.src;
                        }
                        if (vSrc && isValidVideoUrl(vSrc)) {
                            chosenUrl = vSrc;
                        }
                    }
                }
            }

            // --- 5. Check globally playing video on screen ---
            if (!chosenUrl) {
                var allVideos = Array.from(document.querySelectorAll('video'));
                var playingVid = allVideos.find(function(v) { return !v.paused && v.currentTime > 0; });
                if (playingVid) {
                    if (playingVid.__exactMediaUrl && isValidVideoUrl(playingVid.__exactMediaUrl)) {
                        chosenUrl = playingVid.__exactMediaUrl;
                    } else {
                        var pSrc = playingVid.currentSrc || playingVid.src;
                        if (pSrc && isValidVideoUrl(pSrc)) chosenUrl = pSrc;
                    }
                }
            }

            if (!chosenUrl) {
                postError("No active video stream detected.\\nPlease play the video on screen, then click Download.");
                return;
            }

            // Clean escaped URL
            chosenUrl = chosenUrl.replace(/\\\\u0026/g, '&').replace(/\\\\/g, '');

            // Dispatch download: attempt in-browser blob fetch first, fallback to native Swift URLSession
            fetch(chosenUrl, { credentials: 'include' })
                .then(function(res) {
                    if (!res.ok) throw new Error("HTTP error " + res.status);
                    return res.blob();
                })
                .then(function(blob) {
                    var reader = new FileReader();
                    reader.onloadend = function() {
                        var base64 = reader.result.split(',')[1];
                        if (base64 && base64.length > 1000) {
                            postSuccessData(base64);
                        } else {
                            postDirectUrl(chosenUrl);
                        }
                    };
                    reader.readAsDataURL(blob);
                })
                .catch(function(err) {
                    postDirectUrl(chosenUrl);
                });
        })();
        """
        
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                NSLog("[VideoDownloader] JavaScript evaluation error: %@", error.localizedDescription)
            }
        }
    }
    
    private func startDownload(url: URL, serviceName: String, quality: String) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            
            var request = URLRequest(url: url)
            let headerFields = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, val) in headerFields {
                request.setValue(val, forHTTPHeaderField: key)
            }
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("https://www.google.com", forHTTPHeaderField: "Referer")
            
            let task = self.downloadSession.downloadTask(with: request)
            self.activeTasks[task.taskIdentifier] = (serviceName: serviceName, quality: quality)
            task.resume()
            
            DispatchQueue.main.async {
                self.delegate?.didUpdateDownloadProgress(percent: 0.0, serviceName: serviceName)
                self.showNotification(
                    title: "Downloading \(serviceName) Video...",
                    body: "Quality: \(quality). File will be saved to your Downloads folder."
                )
            }
        }
    }
    
    private func saveVideoData(_ data: Data, serviceName: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let filename = "\(serviceName)_\(timestamp).mp4"
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationURL = downloadsDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: destinationURL)
            DispatchQueue.main.async {
                self.delegate?.didFinishDownload(filename: filename, serviceName: serviceName)
                self.showNotification(
                    title: "🎬 \(serviceName) Video Downloaded!",
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
            let percent = progress * 100.0
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
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let filename = "\(serviceName)_\(timestamp).mp4"
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationURL = downloadsDirectory.appendingPathComponent(filename)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                self.delegate?.didFinishDownload(filename: filename, serviceName: serviceName)
                self.showNotification(
                    title: "🎬 \(serviceName) Video Downloaded!",
                    body: "Saved as \(filename) in ~/Downloads"
                )
            }
        } catch {
            NSLog("[VideoDownloader] Failed to save downloaded video: %@", error.localizedDescription)
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
