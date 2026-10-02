import Foundation
import AppKit
import WebKit
import UserNotifications

public class VideoDownloader: NSObject, WKScriptMessageHandler, URLSessionDownloadDelegate {
    public static let shared = VideoDownloader()
    
    private var downloadSession: URLSession!
    private var activeTasks: [Int: (service: ServiceID, quality: String)] = [:]
    
    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "videoSaveHandler", let dict = message.body as? [String: Any] {
            if let base64Data = dict["dataBase64"] as? String,
               let serviceName = dict["service"] as? String,
               let data = Data(base64Encoded: base64Data) {
                
                saveVideoData(data, serviceName: serviceName)
            } else if let errorMsg = dict["error"] as? String {
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
            
            // 1. Gather all video elements on the page
            var videos = Array.from(document.querySelectorAll('video'));
            if (videos.length === 0) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({ error: "No video player found on screen." });
                return;
            }
            
            // 2. Select the currently playing or most prominent video
            var target = videos.find(function(v) { return !v.paused && v.currentTime > 0; });
            if (!target) {
                target = videos.sort(function(a, b) {
                    var rA = a.getBoundingClientRect();
                    var rB = b.getBoundingClientRect();
                    return (rB.width * rB.height) - (rA.width * rA.height);
                })[0];
            }
            
            if (!target) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({ error: "No active video stream found." });
                return;
            }
            
            var videoSrc = target.currentSrc || target.src;
            if (!videoSrc) {
                var sourceEl = target.querySelector('source');
                if (sourceEl) videoSrc = sourceEl.src;
            }
            
            if (!videoSrc) {
                window.webkit.messageHandlers.videoSaveHandler.postMessage({ error: "Video source is protected or not yet loaded." });
                return;
            }
            
            // 3. Fetch video blob directly in page context (shares all cookies & session headers)
            fetch(videoSrc, { credentials: 'include', mode: 'cors' })
                .then(function(response) {
                    if (!response.ok) throw new Error("HTTP Status: " + response.status);
                    return response.blob();
                })
                .then(function(blob) {
                    var reader = new FileReader();
                    reader.onloadend = function() {
                        var base64 = reader.result.split(',')[1];
                        window.webkit.messageHandlers.videoSaveHandler.postMessage({
                            dataBase64: base64,
                            service: service,
                            quality: quality
                        });
                    };
                    reader.readAsDataURL(blob);
                })
                .catch(function(err) {
                    // Fallback to direct URL download if fetch is blocked
                    window.webkit.messageHandlers.videoSaveHandler.postMessage({
                        directUrl: videoSrc,
                        service: service,
                        quality: quality
                    });
                });
        })();
        """
        
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                NSLog("[VideoDownloader] JavaScript evaluation error: %@", error.localizedDescription)
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
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskInfo = activeTasks[downloadTask.taskIdentifier]
        let serviceName = taskInfo?.service.name ?? "Video"
        
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
}
