import Foundation
import WebKit
import UserNotifications
import AppKit

public protocol NotificationBridgeDelegate: AnyObject {
    func didUpdateUnreadCount(service: ServiceID, account: Int, count: Int)
}

public class NotificationBridge: NSObject, WKScriptMessageHandler {
    public static let shared = NotificationBridge()
    public weak var delegate: NotificationBridgeDelegate?
    
    override init() {
        super.init()
        requestNotificationPermission()
    }
    
    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                NSLog("[NotificationBridge] Izin notifikasi macOS diberikan.")
            } else if let error = error {
                NSLog("[NotificationBridge] Gagal meminta izin: %@", error.localizedDescription)
            }
        }
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "notificationHandler", let dict = message.body as? [String: Any] {
            let title = dict["title"] as? String ?? "New Message"
            let body = dict["body"] as? String ?? ""
            showNativeNotification(title: title, body: body)
        } else if message.name == "titleHandler", let dict = message.body as? [String: Any] {
            let title = dict["title"] as? String ?? ""
            parseTitleForBadge(title: title)
        }
    }
    
    private func showNativeNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[NotificationBridge] Gagal menampilkan notifikasi: %@", error.localizedDescription)
            }
        }
    }
    
    private func parseTitleForBadge(title: String) {
        if let match = title.range(of: #"^\((\d+)\)"#, options: .regularExpression) {
            let countStr = title[match].replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            if let count = Int(countStr) {
                DispatchQueue.main.async {
                    self.delegate?.didUpdateUnreadCount(service: .whatsapp, account: 1, count: count)
                }
                return
            }
        }
        
        DispatchQueue.main.async {
            self.delegate?.didUpdateUnreadCount(service: .whatsapp, account: 1, count: 0)
        }
    }
    
    public static var injectedJavaScript: String {
        return """
        (function() {
            if (window.__menubarHubInjected) return;
            window.__menubarHubInjected = true;
            
            // Web Notification Bridge
            var NativeNotification = window.Notification;
            window.Notification = function(title, options) {
                options = options || {};
                var body = options.body || '';
                var icon = options.icon || '';
                var tag = options.tag || '';
                try {
                    window.webkit.messageHandlers.notificationHandler.postMessage({
                        title: title,
                        body: body,
                        icon: icon,
                        tag: tag
                    });
                } catch(e) {}
                this.title = title;
                this.body = body;
                this.icon = icon;
                this.tag = tag;
                this.close = function() {};
            };
            window.Notification.permission = 'granted';
            window.Notification.requestPermission = function(callback) {
                if (callback) callback('granted');
                return Promise.resolve('granted');
            };
            
            // Title Observer for Unread Badges
            var lastTitle = document.title;
            var observer = new MutationObserver(function() {
                if (document.title !== lastTitle) {
                    lastTitle = document.title;
                    try {
                        window.webkit.messageHandlers.titleHandler.postMessage({
                            title: document.title
                        });
                    } catch(e) {}
                }
            });
            var target = document.querySelector('title') || document.documentElement;
            if (target) {
                observer.observe(target, { subtree: true, characterData: true, childList: true });
            }

            // Universal Media Sniffer (Max Video Downloader Engine)
            window.__menubarHubDetectedVideos = window.__menubarHubDetectedVideos || [];

            function registerVideo(url, label) {
                if (!url || typeof url !== 'string' || url.indexOf('http') !== 0) return;
                var cleanUrl = url.replace(/\\\\u0026/g, '&').replace(/\\\\/g, '');
                for (var i = 0; i < window.__menubarHubDetectedVideos.length; i++) {
                    if (window.__menubarHubDetectedVideos[i].url === cleanUrl) return;
                }
                window.__menubarHubDetectedVideos.unshift({
                    url: cleanUrl,
                    title: document.title || "Video",
                    quality: label || "HD 1080p",
                    time: Date.now()
                });
                if (window.__menubarHubDetectedVideos.length > 25) window.__menubarHubDetectedVideos.pop();
            }

            // 1. Hook HTMLMediaElement play & src
            try {
                var origPlay = HTMLMediaElement.prototype.play;
                HTMLMediaElement.prototype.play = function() {
                    var s = this.currentSrc || this.src;
                    if (s && s.indexOf('http') === 0) {
                        var q = (this.videoHeight && this.videoHeight >= 1080) ? "1080p HD" : ((this.videoHeight && this.videoHeight >= 720) ? "720p HD" : "HD Original");
                        registerVideo(s, q);
                    }
                    return origPlay.apply(this, arguments);
                };
            } catch(e) {}

            // 2. Hook Fetch requests for TikTok, Instagram, FB, Threads, X CDN links
            try {
                var origFetch = window.fetch;
                window.fetch = function() {
                    var url = (typeof arguments[0] === 'string') ? arguments[0] : (arguments[0] && arguments[0].url);
                    if (url && typeof url === 'string') {
                        if (url.includes('.mp4') || url.includes('mime_type=video_mp4') || url.includes('video_id=') ||
                            url.includes('tiktokcdn.com') || url.includes('cdninstagram.com') || url.includes('fbcdn.net') ||
                            url.includes('byteoversea.com') || url.includes('ibytedtos.com') || url.includes('twimg.com')) {
                            registerVideo(url, "1080p HD");
                        }
                    }
                    return origFetch.apply(this, arguments);
                };
            } catch(e) {}

            // 3. Hook XMLHttpRequest
            try {
                var origOpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                    if (url && typeof url === 'string') {
                        if (url.includes('.mp4') || url.includes('mime_type=video_mp4') || url.includes('tiktokcdn.com') || url.includes('cdninstagram.com') || url.includes('fbcdn.net')) {
                            registerVideo(url, "1080p HD");
                        }
                    }
                    return origOpen.apply(this, arguments);
                };
            } catch(e) {}

            // Auto-Scroll Engine for TikTok & Instagram Reels
            window.__menubarHubAutoScrollEnabled = true;
            var lastScrollTimestamp = 0;

            function advanceToNextVideo() {
                if (!window.__menubarHubAutoScrollEnabled) return;
                var now = Date.now();
                if (now - lastScrollTimestamp < 2200) return;
                lastScrollTimestamp = now;

                var selectors = [
                    'button[data-e2e="arrow-right"]',
                    '[data-e2e="arrow-right"]',
                    'button[data-e2e="feed-arrow-down"]',
                    '[data-e2e="feed-arrow-down"]',
                    'button[aria-label="Go to next video"]',
                    'button[aria-label="Next video"]',
                    'button[aria-label="Next"]',
                    'button[aria-label="Berikutnya"]',
                    'button[aria-label="Next Post"]',
                    'div[role="button"][aria-label="Next"]',
                    'div[role="button"][aria-label="Berikutnya"]'
                ];
                
                for (var i = 0; i < selectors.length; i++) {
                    var el = document.querySelector(selectors[i]);
                    if (el) {
                        try {
                            el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
                            el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
                            el.click();
                            break;
                        } catch(e) {}
                    }
                }

                var targets = [document.activeElement, document.body, document.documentElement, window];
                targets.forEach(function(t) {
                    if (!t) return;
                    try {
                        t.dispatchEvent(new KeyboardEvent('keydown', {
                            key: 'ArrowDown',
                            code: 'ArrowDown',
                            keyCode: 40,
                            which: 40,
                            bubbles: true,
                            cancelable: true,
                            composed: true
                        }));
                        t.dispatchEvent(new KeyboardEvent('keyup', {
                            key: 'ArrowDown',
                            code: 'ArrowDown',
                            keyCode: 40,
                            which: 40,
                            bubbles: true,
                            cancelable: true,
                            composed: true
                        }));
                    } catch(e) {}
                });

                try {
                    var wheelEv = new WheelEvent('wheel', {
                        deltaY: 800,
                        deltaMode: 0,
                        bubbles: true,
                        cancelable: true
                    });
                    (document.activeElement || document.body).dispatchEvent(wheelEv);
                    window.dispatchEvent(wheelEv);
                } catch(e) {}

                var containers = [
                    document.querySelector('[data-e2e="recommend-list-item-container"]'),
                    document.querySelector('[data-e2e="feed-container"]'),
                    document.querySelector('main'),
                    document.documentElement,
                    document.body,
                    window
                ];
                containers.forEach(function(c) {
                    if (c && c.scrollBy) {
                        try { c.scrollBy({ top: window.innerHeight * 0.9, behavior: 'smooth' }); } catch(e) {}
                    }
                });
            }

            function setupVideoListeners() {
                var videos = document.querySelectorAll('video');
                videos.forEach(function(video) {
                    var s = video.currentSrc || video.src;
                    if (s && s.indexOf('http') === 0) {
                        registerVideo(s, (video.videoHeight && video.videoHeight >= 1080) ? "1080p HD" : "720p HD");
                    }

                    if (video.__menubarHubAttached) return;
                    video.__menubarHubAttached = true;

                    var lastTime = 0;

                    video.addEventListener('ended', function() {
                        advanceToNextVideo();
                    });

                    video.addEventListener('timeupdate', function() {
                        if (!window.__menubarHubAutoScrollEnabled) return;
                        var cur = video.currentTime;
                        var dur = video.duration;
                        
                        if (dur && dur > 1.2) {
                            if (cur >= dur - 0.35 && cur > 1.0) {
                                advanceToNextVideo();
                            }
                            if (lastTime > dur - 1.2 && cur < 0.6) {
                                advanceToNextVideo();
                            }
                        }
                        lastTime = cur;
                    });
                });
            }

            setInterval(setupVideoListeners, 700);
        })();
        """
    }
}
