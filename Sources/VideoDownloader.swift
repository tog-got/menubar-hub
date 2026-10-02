import Foundation
import AppKit
import WebKit
import UserNotifications

public class VideoDownloader: NSObject, URLSessionDownloadDelegate {
    public static let shared = VideoDownloader()
    
    private var downloadSession: URLSession!
    private var activeTasks: [Int: (service: ServiceID, quality: String)] = [:]
    
    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    public static var videoExtractorScript: String {
        return """
        (function() {
            var videos = Array.from(document.querySelectorAll('video'));
            if (videos.length === 0) return { error: "No video elements found on page." };
            
            // Priority 1: Find currently playing video
            var target = videos.find(function(v) { return !v.paused && v.currentTime > 0; });
            
            // Priority 2: Find video in center of screen / largest visible
            if (!target) {
                target = videos.sort(function(a, b) {
                    var rA = a.getBoundingClientRect();
                    var rB = b.getBoundingClientRect();
                    return (rB.width * rB.height) - (rA.width * rA.height);
                })[0];
            }
            
            if (!target) return { error: "No active video found." };
            
            var src = target.currentSrc || target.src;
            if (!src || src.indexOf('http') !== 0) {
                var source = target.querySelector('source');
                if (source) src = source.src;
            }
            
            // Fallback: Check preload links or video attributes
            if (!src || src.indexOf('http') !== 0) {
                src = target.getAttribute('src') || target.getAttribute('data-src');
            }
            
            if (!src) return { error: "Video source is encrypted or streaming via segmented blob." };
            
            return {
                url: src,
                title: document.title || "Video",
                duration: target.duration || 0
            };
        })();
        """
    }
    
    public func downloadVideo(from webView: WKWebView, service: ServiceID, quality: String) {
        webView.evaluateJavaScript(VideoDownloader.videoExtractorScript) { [weak self] result, error in
            guard let self = self else { return }
            
            if let dict = result as? [String: Any], let videoUrlStr = dict["url"] as? String, let videoUrl = URL(string: videoUrlStr) {
                self.startDownload(url: videoUrl, service: service, quality: quality)
            } else {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Download Video"
                    alert.informativeText = "Could not detect a direct video stream on screen.\nMake sure the video is playing before downloading."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    private func startDownload(url: URL, service: ServiceID, quality: String) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(service.url.absoluteString, forHTTPHeaderField: "Referer")
        
        let task = downloadSession.downloadTask(with: request)
        activeTasks[task.taskIdentifier] = (service: service, quality: quality)
        task.resume()
        
        DispatchQueue.main.async {
            self.showNotification(
                title: "Downloading \(service.name) Video...",
                body: "Quality: \(quality). File will be saved to your Downloads folder."
            )
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskInfo = activeTasks[downloadTask.taskIdentifier]
        let serviceName = taskInfo?.service.name ?? "SocialMedia"
        
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
                    title: "🎬 \(serviceName) Video Saved!",
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
        }
        activeTasks.removeValue(forKey: task.taskIdentifier)
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
