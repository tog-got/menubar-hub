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

            var candidates = [];

            // 1. Check live media sniffer array (Max Video Downloader stream buffer)
            if (window.__menubarHubDetectedVideos && window.__menubarHubDetectedVideos.length > 0) {
                window.__menubarHubDetectedVideos.forEach(function(item) {
                    if (item.url && item.url.indexOf('http') === 0) {
                        candidates.push(item.url);
                    }
                });
            }

            // 2. Scan all video elements on the page (including shadow roots)
            function findVideos(root) {
                var list = [];
                try {
                    var vids = root.querySelectorAll('video');
                    vids.forEach(function(v) { list.push(v); });
                    
                    var allElements = root.querySelectorAll('*');
                    allElements.forEach(function(el) {
                        if (el.shadowRoot) {
                            list = list.concat(findVideos(el.shadowRoot));
                        }
                    });
                } catch(e) {}
                return list;
            }

            var allVideos = findVideos(document);
            allVideos.forEach(function(v) {
                var s = v.currentSrc || v.src;
                if (!s) {
                    var source = v.querySelector('source');
                    if (source) s = source.src;
                }
                if (!s) s = v.getAttribute('src') || v.getAttribute('data-src');
                if (s && s.indexOf('http') === 0) {
                    candidates.unshift(s);
                }
            });

            // 3. Scan performance network resource entries
            try {
                var entries = window.performance.getEntriesByType('resource') || [];
                for (var i = entries.length - 1; i >= 0; i--) {
                    var name = entries[i].name || '';
                    if (name.indexOf('http') === 0) {
                        if (name.indexOf('.mp4') !== -1 ||
                            name.indexOf('mime_type=video_mp4') !== -1 ||
                            name.indexOf('video_id=') !== -1 ||
                            name.indexOf('tiktokcdn') !== -1 ||
                            name.indexOf('byteoversea') !== -1 ||
                            name.indexOf('ibytedtos') !== -1 ||
                            name.indexOf('pstatp') !== -1 ||
                            name.indexOf('cdninstagram') !== -1 ||
                            name.indexOf('fbcdn.net') !== -1 ||
                            name.indexOf('twimg.com') !== -1) {
                            candidates.push(name);
                        }
                    }
                }
            } catch(e) {}

            // 4. Scan in-page hydration state (TikTok / IG / Threads JSON state)
            try {
                var tiktokScript = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__') || document.getElementById('SIGI_STATE');
                if (tiktokScript && tiktokScript.textContent) {
                    var data = JSON.parse(tiktokScript.textContent);
                    var str = JSON.stringify(data);
                    var matches = str.match(/https:\\/\\/[^"\\s]+\\.(?:mp4|byteoversea|ibytedtos|tiktokcdn)[^"\\s]*/g);
                    if (matches) {
                        matches.forEach(function(m) {
                            var cleanUrl = m.replace(/\\\\u0026/g, '&').replace(/\\\\/g, '');
                            candidates.push(cleanUrl);
                        });
                    }
                }
            } catch(e) {}

            try {
                var jsonScripts = document.querySelectorAll('script[type="application/json"]');
                jsonScripts.forEach(function(s) {
                    if (!s.textContent) return;
                    var text = s.textContent;
                    if (text.indexOf('video_versions') !== -1 || text.indexOf('browser_native_hd_url') !== -1 || text.indexOf('cdninstagram') !== -1 || text.indexOf('fbcdn.net') !== -1) {
                        var matches = text.match(/https:\\/\\/[^"\\s]+(?:cdninstagram\\.com|fbcdn\\.net)[^"\\s]+(?:\\.mp4|\\?bytestart=[^"\\s]+)/g);
                        if (matches) {
                            matches.forEach(function(m) {
                                var cleanUrl = m.replace(/\\\\u0026/g, '&').replace(/\\\\/g, '');
                                candidates.push(cleanUrl);
                            });
                        }
                    }
                });
            } catch(e) {}

            // Remove duplicates
            var uniqueCandidates = [];
            candidates.forEach(function(u) {
                if (uniqueCandidates.indexOf(u) === -1) uniqueCandidates.push(u);
            });

            if (uniqueCandidates.length === 0) {
                postError("No downloadable video detected yet.\\nPlay a video on screen for a moment, then click Download.");
                return;
            }

            var bestUrl = uniqueCandidates[0];

            // Attempt in-browser blob fetch first, fallback to native Swift URLSession
            fetch(bestUrl, { credentials: 'include' })
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
                            postDirectUrl(bestUrl);
                        }
                    };
                    reader.readAsDataURL(blob);
                })
                .catch(function(err) {
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
