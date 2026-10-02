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
            
            // 0. If in-browser progress report
            if let progressNum = dict["progress"] as? Double {
                DispatchQueue.main.async {
                    self.delegate?.didUpdateDownloadProgress(percent: progressNum, serviceName: serviceName)
                }
                return
            }
            
            // 1. If Base64 video data received directly from in-browser XHR
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

            // 1. Find the video element actively playing in viewport
            var allVideos = Array.from(document.querySelectorAll('video'));
            var activeVideo = allVideos.find(function(v) { return !v.paused && v.currentTime > 0; });
            if (!activeVideo && allVideos.length > 0) {
                var vpCenterY = window.innerHeight / 2;
                activeVideo = allVideos.sort(function(a, b) {
                    var rA = a.getBoundingClientRect();
                    var rB = b.getBoundingClientRect();
                    return Math.abs((rA.top + rA.height / 2) - vpCenterY) - Math.abs((rB.top + rB.height / 2) - vpCenterY);
                })[0];
            }

            if (!activeVideo) {
                postError("No active video found on screen.\\nPlease start playing the video first.");
                return;
            }

            // 2. Extract the video's stream URL
            var streamUrl = activeVideo.__exactMediaUrl;
            if (!streamUrl && activeVideo.currentSrc && activeVideo.currentSrc.indexOf('http') === 0 && activeVideo.currentSrc.indexOf('blob:') !== 0) {
                streamUrl = activeVideo.currentSrc;
            }
            if (!streamUrl && activeVideo.src && activeVideo.src.indexOf('http') === 0 && activeVideo.src.indexOf('blob:') !== 0) {
                streamUrl = activeVideo.src;
            }

            // If video is loaded via blob, find the matching resource URL from performance entries
            if (!streamUrl) {
                var entries = window.performance.getEntriesByType('resource') || [];
                for (var j = entries.length - 1; j >= 0; j--) {
                    var name = entries[j].name || '';
                    if (isValidVideoUrl(name)) {
                        streamUrl = name;
                        break;
                    }
                }
            }

            if (!streamUrl) {
                postError("Could not locate video stream. Make sure the video is currently playing.");
                return;
            }

            // 3. Download using in-browser XMLHttpRequest with responseType = 'blob'
            var xhr = new XMLHttpRequest();
            xhr.open('GET', streamUrl, true);
            xhr.responseType = 'blob';
            
            xhr.onprogress = function(e) {
                if (e.lengthComputable && e.total > 0) {
                    var pct = (e.loaded / e.total) * 100.0;
                    window.webkit.messageHandlers.videoSaveHandler.postMessage({
                        progress: pct,
                        service: service
                    });
                }
            };
            
            xhr.onload = function() {
                if (xhr.status >= 200 && xhr.status < 300 && xhr.response) {
                    var blob = xhr.response;
                    var reader = new FileReader();
                    reader.onloadend = function() {
                        var base64 = reader.result.split(',')[1];
                        if (base64 && base64.length > 500) {
                            postSuccessData(base64);
                        } else {
                            postDirectUrl(streamUrl);
                        }
                    };
                    reader.readAsDataURL(blob);
                } else {
                    postDirectUrl(streamUrl);
                }
            };
            
            xhr.onerror = function() {
                postDirectUrl(streamUrl);
            };
            
            xhr.send();
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
            request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
            request.setValue("bytes=0-", forHTTPHeaderField: "Range")
            
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
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            if fileSize < 10000 {
                DispatchQueue.main.async {
                    self.delegate?.didFailDownload(error: "Stream expired or protected")
                    self.showErrorAlert(message: "The video stream could not be downloaded.\nPlease try again or switch video quality.")
                }
                activeTasks.removeValue(forKey: downloadTask.taskIdentifier)
                return
            }
            
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
