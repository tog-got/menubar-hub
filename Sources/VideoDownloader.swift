import Foundation
import AppKit
import WebKit
import UserNotifications

public class VideoDownloader: NSObject, WKScriptMessageHandler, URLSessionDownloadDelegate {
    public static let shared = VideoDownloader()
    
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

            // Step 1: Scan Performance Resource Timings (Highest fidelity direct CDN MP4 streams)
            var candidateUrls = [];
            try {
                var entries = window.performance.getEntriesByType('resource') || [];
                for (var i = entries.length - 1; i >= 0; i--) {
                    var name = entries[i].name || '';
                    if (name.indexOf('http') === 0) {
                        if (name.indexOf('.mp4') !== -1 ||
                            name.indexOf('mime=video') !== -1 ||
                            name.indexOf('video/mp4') !== -1 ||
                            name.indexOf('cdninstagram.com') !== -1 && name.indexOf('.mp4') !== -1 ||
                            name.indexOf('tiktokcdn.com') !== -1 && (name.indexOf('.mp4') !== -1 || name.indexOf('/video/') !== -1) ||
                            name.indexOf('fbcdn.net') !== -1 && name.indexOf('.mp4') !== -1 ||
                            name.indexOf('twimg.com') !== -1 && name.indexOf('.mp4') !== -1) {
                            candidateUrls.push(name);
                        }
                    }
                }
            } catch(e) {}

            // Step 2: Scan DOM Video Elements
            var videos = Array.from(document.querySelectorAll('video'));
            var activeVideo = videos.find(function(v) { return !v.paused && v.currentTime > 0; });
            if (!activeVideo && videos.length > 0) {
                activeVideo = videos.sort(function(a, b) {
                    var rA = a.getBoundingClientRect();
                    var rB = b.getBoundingClientRect();
                    return (rB.width * rB.height) - (rA.width * rA.height);
                })[0];
            }

            if (activeVideo) {
                var vSrc = activeVideo.currentSrc || activeVideo.src;
                if (!vSrc) {
                    var s = activeVideo.querySelector('source');
                    if (s) vSrc = s.src;
                }
                if (vSrc && vSrc.indexOf('http') === 0) {
                    candidateUrls.unshift(vSrc);
                }
            }

            // Step 3: Scan Meta tags
            var metaVideo = document.querySelector('meta[property="og:video"], meta[property="og:video:secure_url"], meta[property="twitter:player:stream"]');
            if (metaVideo && metaVideo.content && metaVideo.content.indexOf('http') === 0) {
                candidateUrls.push(metaVideo.content);
            }

            if (candidateUrls.length === 0) {
                postError("No downloadable video found. Play a video on screen before downloading.");
                return;
            }

            var bestUrl = candidateUrls[0];

            // Step 4: Attempt in-browser Blob Fetch (for best speed and cookie preservation)
            fetch(bestUrl, { credentials: 'include', mode: 'cors' })
                .then(function(res) {
                    if (!res.ok) throw new Error("HTTP error " + res.status);
                    return res.blob();
                })
                .then(function(blob) {
                    var reader = new FileReader();
                    reader.onloadend = function() {
                        var base64 = reader.result.split(',')[1];
                        if (base64 && base64.length > 100) {
                            postSuccessData(base64);
                        } else {
                            postDirectUrl(bestUrl);
                        }
                    };
                    reader.readAsDataURL(blob);
                })
                .catch(function(err) {
                    // Fallback to Native URLSession download with direct URL
                    postDirectUrl(bestUrl);
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
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        let task = downloadSession.downloadTask(with: request)
        activeTasks[task.taskIdentifier] = (serviceName: serviceName, quality: quality)
        task.resume()
        
        DispatchQueue.main.async {
            self.showNotification(
                title: "Downloading \(serviceName) Video...",
                body: "Quality: \(quality). File will be saved to your Downloads folder."
            )
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
                self.showNotification(
                    title: "🎬 \(serviceName) Video Downloaded!",
                    body: "Saved as \(filename) in ~/Downloads"
                )
            }
        } catch {
            NSLog("[VideoDownloader] Failed to write data: %@", error.localizedDescription)
            DispatchQueue.main.async {
                self.showErrorAlert(message: "Failed to save file: \(error.localizedDescription)")
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
