import Foundation
import WebKit
import AppKit

public class TabManager {
    public static let shared = TabManager()
    
    // Key: "service_account" (misal: "whatsapp_1", "telegram_2", "x_1")
    private var webViews: [String: WKWebView] = [:]
    private var purgeTimers: [String: Timer] = [:]
    
    // Grace period 2 menit (120 detik)
    public let gracePeriodSeconds: TimeInterval = 120.0
    
    // User Agent modern agar WhatsApp Web dan Instagram tidak menolak
    public let customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    
    private init() {}
    
    public func key(for service: ServiceID, account: Int) -> String {
        return "\(service.rawValue)_\(account)"
    }
    
    private func dataStoreUUID(for account: Int) -> UUID {
        let base = "A1B2C3D4-0000-4A5B-8C9D-\(String(format: "%012d", account))"
        return UUID(uuidString: base) ?? UUID()
    }
    
    public func getOrCreateWebView(for service: ServiceID, account: Int) -> WKWebView {
        let tabKey = key(for: service, account: account)
        
        // Batalkan timer purge jika tab dibuka kembali sebelum 4 menit
        if let timer = purgeTimers[tabKey] {
            timer.invalidate()
            purgeTimers.removeValue(forKey: tabKey)
            NSLog("[TabManager] Memulihkan tab %@ (timer dibatalkan).", tabKey)
        }
        
        if let existing = webViews[tabKey] {
            return existing
        }
        
        // Buat WKWebView baru dengan konfigurasi terisolasi
        let config = WKWebViewConfiguration()
        
        // Setup Isolated DataStore per Akun
        if account == 1 {
            config.websiteDataStore = WKWebsiteDataStore.default()
        } else {
            if #available(macOS 14.0, *) {
                config.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreUUID(for: account))
            } else {
                config.websiteDataStore = WKWebsiteDataStore.default()
            }
        }
        
        // Inject script bridge untuk notifikasi dan download handler
        let userScript = WKUserScript(
            source: NotificationBridge.injectedJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(NotificationBridge.shared, name: "notificationHandler")
        config.userContentController.add(NotificationBridge.shared, name: "titleHandler")
        config.userContentController.add(VideoDownloader.shared, name: "videoSaveHandler")
        
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = customUserAgent
        webView.allowsBackForwardNavigationGestures = true
        
        // Muat URL
        let request = URLRequest(url: service.url)
        webView.load(request)
        
        webViews[tabKey] = webView
        NSLog("[TabManager] Membuat WKWebView baru untuk %@.", tabKey)
        return webView
    }
    
    public func handleTabDeactivated(service: ServiceID, account: Int) {
        let tabKey = key(for: service, account: account)
        guard let webView = webViews[tabKey] else { return }
        
        // Pause all media on inactive tab to save CPU & GPU memory
        pauseMedia(in: webView)
        
        // Tab chat (WhatsApp & Telegram) TIDAK di-purge agar notifikasi tetap aktif
        guard !service.isChat else { return }
        
        // Hindari membuat timer ganda
        purgeTimers[tabKey]?.invalidate()
        
        NSLog("[TabManager] Memulai grace period (%.0f detik) untuk %@.", gracePeriodSeconds, tabKey)
        
        let timer = Timer.scheduledTimer(withTimeInterval: gracePeriodSeconds, repeats: false) { [weak self] _ in
            self?.purgeTab(key: tabKey)
        }
        purgeTimers[tabKey] = timer
    }
    
    public func handlePopoverClosed(currentService: ServiceID, currentAccount: Int) {
        // Pause media across all open web views to avoid background drain
        for (_, webView) in webViews {
            pauseMedia(in: webView)
        }
        
        if !currentService.isChat {
            handleTabDeactivated(service: currentService, account: currentAccount)
        }
    }
    
    public func handlePopoverOpened(currentService: ServiceID, currentAccount: Int) {
        let tabKey = key(for: currentService, account: currentAccount)
        if let timer = purgeTimers[tabKey] {
            timer.invalidate()
            purgeTimers.removeValue(forKey: tabKey)
            NSLog("[TabManager] Jendela dibuka, timer untuk %@ dibatalkan.", tabKey)
        }
    }
    
    private func pauseMedia(in webView: WKWebView) {
        let pauseScript = "document.querySelectorAll('video, audio').forEach(function(el){ try{ el.pause(); }catch(e){} });"
        webView.evaluateJavaScript(pauseScript, completionHandler: nil)
    }
    
    private func purgeTab(key: String) {
        guard let webView = webViews[key] else { return }
        
        // Hentikan pemuatan dan bersihkan dari memori
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
        
        webViews.removeValue(forKey: key)
        purgeTimers.removeValue(forKey: key)
        
        NSLog("[TabManager] Tab %@ telah di-purge dari RAM (Grace period selesai).", key)
    }
}
