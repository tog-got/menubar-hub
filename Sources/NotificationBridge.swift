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

            // Auto-Scroll Engine for TikTok & Instagram Reels
            window.__menubarHubAutoScrollEnabled = true;
            window.__menubarHubMediaHistory = window.__menubarHubMediaHistory || [];
            var lastScrollTimestamp = 0;

            // Media & Network Sniffer for Video Downloader
            try {
                var origPlay = HTMLMediaElement.prototype.play;
                HTMLMediaElement.prototype.play = function() {
                    this.__menubarHubLastPlayed = Date.now();
                    var s = this.currentSrc || this.src;
                    if (s && s.indexOf('blob:') !== 0 && s.indexOf('data:') !== 0) {
                        window.__menubarHubMediaHistory.push({
                            url: s,
                            time: Date.now(),
                            type: 'play'
                        });
                        if (window.__menubarHubMediaHistory.length > 60) {
                            window.__menubarHubMediaHistory.shift();
                        }
                    }
                    return origPlay.apply(this, arguments);
                };
            } catch(e) {}

            try {
                var origFetch = window.fetch;
                window.fetch = function(input, init) {
                    try {
                        var url = (typeof input === 'string') ? input : (input && input.url);
                        if (url && typeof url === 'string') {
                            var low = url.toLowerCase();
                            if ((low.indexOf('.mp4') !== -1 || low.indexOf('video_id=') !== -1 || low.indexOf('mime_type=video_mp4') !== -1 ||
                                 low.indexOf('/video/tos/') !== -1 || low.indexOf('tiktokcdn.com') !== -1 || low.indexOf('byteoversea.com') !== -1 ||
                                 low.indexOf('ibytedtos.com') !== -1 || low.indexOf('cdninstagram.com') !== -1 || low.indexOf('twimg.com/ext_tw_video') !== -1 ||
                                 low.indexOf('fbcdn.net') !== -1) &&
                                low.indexOf('.jpg') === -1 && low.indexOf('.jpeg') === -1 && low.indexOf('.png') === -1 && low.indexOf('.webp') === -1) {
                                
                                var vId = null;
                                var m = url.match(/\\/video\\/(\\d{15,25})/);
                                if (m) vId = m[1];
                                
                                window.__menubarHubMediaHistory.push({
                                    url: url,
                                    videoId: vId,
                                    time: Date.now(),
                                    type: 'fetch'
                                });
                                if (window.__menubarHubMediaHistory.length > 60) {
                                    window.__menubarHubMediaHistory.shift();
                                }
                            }
                        }
                    } catch(e) {}
                    return origFetch.apply(this, arguments);
                };
            } catch(e) {}

            try {
                var origXhrOpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                    try {
                        if (url && typeof url === 'string') {
                            var low = url.toLowerCase();
                            if ((low.indexOf('.mp4') !== -1 || low.indexOf('video_id=') !== -1 || low.indexOf('mime_type=video_mp4') !== -1 ||
                                 low.indexOf('/video/tos/') !== -1 || low.indexOf('tiktokcdn.com') !== -1 || low.indexOf('byteoversea.com') !== -1 ||
                                 low.indexOf('ibytedtos.com') !== -1 || low.indexOf('cdninstagram.com') !== -1 || low.indexOf('twimg.com/ext_tw_video') !== -1 ||
                                 low.indexOf('fbcdn.net') !== -1) &&
                                low.indexOf('.jpg') === -1 && low.indexOf('.jpeg') === -1 && low.indexOf('.png') === -1 && low.indexOf('.webp') === -1) {
                                
                                var vId = null;
                                var m = url.match(/\\/video\\/(\\d{15,25})/);
                                if (m) vId = m[1];
                                
                                window.__menubarHubMediaHistory.push({
                                    url: url,
                                    videoId: vId,
                                    time: Date.now(),
                                    type: 'xhr'
                                });
                                if (window.__menubarHubMediaHistory.length > 60) {
                                    window.__menubarHubMediaHistory.shift();
                                }
                            }
                        }
                    } catch(e) {}
                    return origXhrOpen.apply(this, arguments);
                };
            } catch(e) {}

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

            var setupTimer = null;
            function scheduleVideoListeners() {
                if (setupTimer) return;
                setupTimer = setTimeout(function() {
                    setupTimer = null;
                    setupVideoListeners();
                }, 2000);
            }

            var domObserver = new MutationObserver(function() {
                scheduleVideoListeners();
            });
            if (document.body) {
                domObserver.observe(document.body, { childList: true, subtree: true });
            }
            scheduleVideoListeners();
        })();
        """
    }
}
