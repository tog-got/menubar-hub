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

            // --- STEP 1: Pinpoint the EXACT Container in Viewport Center ---
            var vpCenterY = window.innerHeight / 2;
            
            // Candidate containers per platform
            var containerSelectors = [
                '[data-e2e="recommend-list-item-container"]',
                '[class*="DivItemContainerV2"]',
                '[class*="DivVideoWrapper"]',
                'article',
                'div[role="dialog"]',
                'div[data-e2e="feed-video"]',
                'div[data-e2e="search-card-video"]',
                'div[tabindex="-1"]'
            ];
            
            var containers = Array.from(document.querySelectorAll(containerSelectors.join(',')));
            var activeContainer = null;
            
            if (containers.length > 0) {
                // Find container spanning across viewport center
                activeContainer = containers.find(function(c) {
                    var r = c.getBoundingClientRect();
                    return r.top <= vpCenterY && r.bottom >= vpCenterY;
                });
                
                // Fallback: pick the one with largest visible area
                if (!activeContainer) {
                    activeContainer = containers.sort(function(a, b) {
                        var rA = a.getBoundingClientRect();
                        var rB = b.getBoundingClientRect();
                        var hA = Math.max(0, Math.min(rA.bottom, window.innerHeight) - Math.max(rA.top, 0));
                        var hB = Math.max(0, Math.min(rB.bottom, window.innerHeight) - Math.max(rB.top, 0));
                        return hB - hA;
                    })[0];
                }
            }

            // Find the video element strictly inside the active container first
            var targetVideo = activeContainer ? activeContainer.querySelector('video') : null;
            
            // Fallback: check globally playing video
            if (!targetVideo) {
                var allVideos = Array.from(document.querySelectorAll('video'));
                targetVideo = allVideos.find(function(v) { return !v.paused && v.currentTime > 0; });
                if (!targetVideo && allVideos.length > 0) {
                    targetVideo = allVideos.sort(function(a, b) {
                        var rA = a.getBoundingClientRect();
                        var rB = b.getBoundingClientRect();
                        return Math.abs((rA.top + rA.height / 2) - vpCenterY) - Math.abs((rB.top + rB.height / 2) - vpCenterY);
                    })[0];
                }
            }

            if (!targetVideo && !activeContainer) {
                postError("No active video found on screen.\\nPlease play the video first.");
                return;
            }

            var exactUrl = null;

            // --- STEP 2: Extract from React Props of the Active Element (TikTok & Meta) ---
            function extractUrlFromReact(el) {
                if (!el) return null;
                var keys = Object.keys(el);
                for (var i = 0; i < keys.length; i++) {
                    if (keys[i].startsWith('__reactProps') || keys[i].startsWith('__reactFiber')) {
                        try {
                            var json = JSON.stringify(el[keys[i]]);
                            if (json) {
                                // Match direct MP4 / CDN video URLs
                                var matches = json.match(/https:\\/\\/[^"\\s]+\\.(?:mp4|byteoversea|ibytedtos|tiktokcdn|cdninstagram|fbcdn)[^"\\s]*/g);
                                if (matches && matches.length > 0) {
                                    return matches[0].replace(/\\\\u0026/g, '&').replace(/\\\\/g, '');
                                }
                            }
                        } catch(e) {}
                    }
                }
                return null;
            }

            if (targetVideo) exactUrl = extractUrlFromReact(targetVideo);
            if (!exactUrl && activeContainer) exactUrl = extractUrlFromReact(activeContainer);

            // --- STEP 3: Extract from Video Element DOM Attributes ---
            if (!exactUrl && targetVideo) {
                var vSrc = targetVideo.currentSrc || targetVideo.src;
                if (!vSrc || vSrc.indexOf('blob:') === 0) {
                    var source = targetVideo.querySelector('source');
                    if (source) vSrc = source.src;
                }
                if (!vSrc || vSrc.indexOf('blob:') === 0) {
                    vSrc = targetVideo.getAttribute('src') || targetVideo.getAttribute('data-src');
                }
                if (vSrc && vSrc.indexOf('http') === 0) {
                    exactUrl = vSrc;
                }
            }

            // --- STEP 4: Fallback to Container Links ---
            if (!exactUrl && activeContainer) {
                var sources = activeContainer.querySelectorAll('source, a[href*=".mp4"]');
                for (var k = 0; k < sources.length; k++) {
                    var h = sources[k].src || sources[k].href;
                    if (h && h.indexOf('http') === 0) {
                        exactUrl = h;
                        break;
                    }
                }
            }

            if (!exactUrl) {
                postError("Could not retrieve video stream URL.\\nPlease ensure the video is currently playing.");
                return;
            }

            // --- STEP 5: Dispatch Download ---
            // Attempt in-browser blob fetch first, fallback to native Swift URLSession
            fetch(exactUrl, { credentials: 'include' })
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
                            postDirectUrl(exactUrl);
                        }
                    };
                    reader.readAsDataURL(blob);
                })
                .catch(function(err) {
                    postDirectUrl(exactUrl);
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
