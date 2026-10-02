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

            var results = [];
            var vpCenterY = window.innerHeight / 2;
            var allVideos = Array.from(document.querySelectorAll('video'));

            // 1. Sort video elements: playing first, then closest to center of screen
            var sortedVideos = allVideos.sort(function(a, b) {
                var aPlaying = (!a.paused && a.currentTime > 0) ? 1 : 0;
                var bPlaying = (!b.paused && b.currentTime > 0) ? 1 : 0;
                if (aPlaying !== bPlaying) return bPlaying - aPlaying;

                var rA = a.getBoundingClientRect();
                var rB = b.getBoundingClientRect();
                var distA = Math.abs((rA.top + rA.height / 2) - vpCenterY);
                var distB = Math.abs((rB.top + rB.height / 2) - vpCenterY);
                return distA - distB;
            });

            // 2. Extract directly from sorted video elements
            for (var i = 0; i < sortedVideos.length; i++) {
                var v = sortedVideos[i];
                var s = v.currentSrc || v.src;
                if (!s || s.indexOf('blob:') === 0) {
                    var srcEl = v.querySelector('source');
                    if (srcEl) s = srcEl.src;
                }
                if (!s || s.indexOf('blob:') === 0) {
                    s = v.getAttribute('src') || v.getAttribute('data-src');
                }
                if (s && s.indexOf('http') === 0 && s.indexOf('blob:') !== 0) {
                    results.push(s);
                }
            }

            // 3. Safe non-circular search in React Fiber props of active video & parent elements
            if (sortedVideos.length > 0) {
                var el = sortedVideos[0];
                var count = 0;
                while (el && el !== document.body && count < 8) {
                    count++;
                    for (var key in el) {
                        if (key.indexOf('__react') === 0) {
                            try {
                                var val = el[key];
                                function safeScan(obj, depth) {
                                    if (!obj || depth > 3 || typeof obj !== 'object') return;
                                    var propKeys = Object.keys(obj);
                                    for (var k = 0; k < propKeys.length; k++) {
                                        var p = propKeys[k];
                                        if (typeof obj[p] === 'string') {
                                            var str = obj[p];
                                            if (str.indexOf('http') === 0 && (str.indexOf('.mp4') !== -1 || str.indexOf('byteoversea') !== -1 || str.indexOf('tiktokcdn') !== -1 || str.indexOf('cdninstagram') !== -1 || str.indexOf('fbcdn') !== -1 || str.indexOf('ibytedtos') !== -1)) {
                                                results.push(str.replace(/\\\\u0026/g, '&').replace(/\\\\/g, ''));
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

            // 4. Performance resource entries (most recent network requests)
            try {
                var entries = window.performance.getEntriesByType('resource') || [];
                for (var j = entries.length - 1; j >= 0; j--) {
                    var name = entries[j].name || '';
                    if (name.indexOf('http') === 0 && (name.indexOf('.mp4') !== -1 || name.indexOf('mime_type=video_mp4') !== -1 || name.indexOf('tiktokcdn') !== -1 || name.indexOf('byteoversea') !== -1 || name.indexOf('cdninstagram') !== -1 || name.indexOf('fbcdn.net') !== -1 || name.indexOf('twimg.com') !== -1)) {
                        results.push(name);
                    }
                }
            } catch(e) {}

            // 5. Meta tags
            try {
                var meta = document.querySelector('meta[property="og:video"], meta[property="og:video:secure_url"]');
                if (meta && meta.content && meta.content.indexOf('http') === 0) results.push(meta.content);
            } catch(e) {}

            // Deduplicate candidates
            var uniqueList = results.filter(function(item, pos, self) {
                return self.indexOf(item) === pos;
            });

            if (uniqueList.length === 0) {
                postError("No active video stream detected.\\nPlease start playing the video on screen, then try again.");
                return;
            }

            var chosenUrl = uniqueList[0];

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
                        if (base64 && base64.length > 500) {
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
