import Cocoa
import UserNotifications

public class AppDelegate: NSObject, NSApplicationDelegate, NotificationBridgeDelegate, NSMenuDelegate {
    public static var shared: AppDelegate?
    
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var mainVC: MainViewController!
    private var unreadCount: Int = 0
    public private(set) var isPinned: Bool = false
    
    public override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Konfigurasi Status Item Menubar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemTitle()
        
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Load saved size or use default
        let savedW = UserDefaults.standard.double(forKey: "popoverWidth")
        let savedH = UserDefaults.standard.double(forKey: "popoverHeight")
        let w = savedW > 300 ? CGFloat(savedW) : 480
        let h = savedH > 400 ? CGFloat(savedH) : 660
        
        // Konfigurasi Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: w, height: h)
        popover.behavior = .transient
        popover.animates = true
        
        mainVC = MainViewController()
        popover.contentViewController = mainVC
        
        // Daftarkan listener notifikasi badge
        NotificationBridge.shared.delegate = self
        NotificationBridge.shared.requestNotificationPermission()
    }
    
    public func setPinned(_ pinned: Bool) {
        self.isPinned = pinned
        if pinned {
            popover.behavior = .applicationDefined
        } else {
            popover.behavior = .transient
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu(title: "MenuBarHub Context Menu")
        menu.delegate = self
        
        // 1. Open / Close Popover
        let openTitle = popover.isShown ? "Close Window" : "Open MenuBarHub"
        let openItem = NSMenuItem(title: openTitle, action: #selector(togglePopoverFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Submenu: Switch Profile
        let profileSubmenu = NSMenu(title: "Switch Profile")
        let currentAccount = mainVC.getCurrentAccount()
        for (index, name) in mainVC.profileNames.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(contextMenuSelectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index + 1
            if item.tag == currentAccount {
                item.state = .on
            }
            profileSubmenu.addItem(item)
        }
        let profileMenuItem = NSMenuItem(title: "Profile: \(mainVC.profileNames[currentAccount - 1])", action: nil, keyEquivalent: "")
        profileMenuItem.submenu = profileSubmenu
        menu.addItem(profileMenuItem)
        
        // 3. Submenu: Switch Service
        let serviceSubmenu = NSMenu(title: "Switch Service")
        let currentService = mainVC.getCurrentService()
        for service in ServiceID.allCases {
            let item = NSMenuItem(title: service.name, action: #selector(contextMenuSelectService(_:)), keyEquivalent: "")
            item.target = self
            item.image = service.iconImage
            item.representedObject = service
            if service == currentService {
                item.state = .on
            }
            serviceSubmenu.addItem(item)
        }
        let serviceMenuItem = NSMenuItem(title: "Service: \(currentService.name)", action: nil, keyEquivalent: "")
        serviceMenuItem.submenu = serviceSubmenu
        menu.addItem(serviceMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Pin Window Toggle
        let pinItem = NSMenuItem(title: isPinned ? "✓ Pinned (Stay On Top)" : "Pin Window (Stay On Top)", action: #selector(contextMenuTogglePin), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)
        
        // 5. Reset Size
        let resetSizeItem = NSMenuItem(title: "Reset Window Size", action: #selector(contextMenuResetSize), keyEquivalent: "")
        resetSizeItem.target = self
        menu.addItem(resetSizeItem)
        
        // 6. Free Inactive RAM
        let freeRamItem = NSMenuItem(title: "Free Inactive RAM / Pause Media", action: #selector(contextMenuFreeRam), keyEquivalent: "")
        freeRamItem.target = self
        menu.addItem(freeRamItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 7. About
        let aboutItem = NSMenuItem(title: "About MenuBarHub", action: #selector(contextMenuAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        // 8. Quit
        let quitItem = NSMenuItem(title: "Quit MenuBarHub", action: #selector(contextMenuQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }
    
    public func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
    
    @objc private func togglePopoverFromMenu() {
        guard let button = statusItem.button else { return }
        togglePopover(button)
    }
    
    @objc private func contextMenuSelectProfile(_ sender: NSMenuItem) {
        mainVC.switchToAccountIndex(sender.tag)
        if !popover.isShown, let button = statusItem.button {
            togglePopover(button)
        }
    }
    
    @objc private func contextMenuSelectService(_ sender: NSMenuItem) {
        if let service = sender.representedObject as? ServiceID {
            mainVC.switchToServiceType(service)
            if !popover.isShown, let button = statusItem.button {
                togglePopover(button)
            }
        }
    }
    
    @objc private func contextMenuTogglePin() {
        mainVC.togglePin()
    }
    
    @objc private func contextMenuResetSize() {
        mainVC.resetWindowToDefault()
    }
    
    @objc private func contextMenuFreeRam() {
        mainVC.onPopoverClosed()
    }
    
    @objc private func contextMenuAbout() {
        let alert = NSAlert()
        alert.messageText = "MenuBarHub v1.0"
        alert.informativeText = "Lightweight Native macOS Hub for WhatsApp, Telegram, and Social Media with multi-account isolation and intelligent RAM management.\n\nOptimized for Apple Silicon M1 (8GB)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func contextMenuQuit() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
            mainVC.onPopoverClosed()
        } else {
            let savedW = UserDefaults.standard.double(forKey: "popoverWidth")
            let savedH = UserDefaults.standard.double(forKey: "popoverHeight")
            let w = savedW > 300 ? CGFloat(savedW) : 480
            let h = savedH > 400 ? CGFloat(savedH) : 660
            popover.contentSize = NSSize(width: w, height: h)
            
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            mainVC.onPopoverOpened()
        }
    }
    
    public func didUpdateUnreadCount(service: ServiceID, account: Int, count: Int) {
        self.unreadCount = count
        updateStatusItemTitle()
    }
    
    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        
        let iconSize = NSSize(width: 20, height: 18)
        let icon = NSImage(size: iconSize, flipped: false) { [weak self] rect in
            guard let self = self, let ctx = NSGraphicsContext.current?.cgContext else { return false }
            
            // Draw base message bubble icon
            if #available(macOS 11.0, *), let baseImg = NSImage(systemSymbolName: "message.fill", accessibilityDescription: "Hub") {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                if let configured = baseImg.withSymbolConfiguration(config) {
                    configured.draw(in: CGRect(x: 1, y: 1, width: 16, height: 16))
                }
            }
            
            // Draw small dot indicator on top-right when unread
            if self.unreadCount > 0 {
                ctx.setFillColor(NSColor.systemRed.cgColor)
                ctx.fillEllipse(in: CGRect(x: 13.5, y: 11.5, width: 5.5, height: 5.5))
            }
            return true
        }
        icon.isTemplate = (unreadCount == 0)
        button.image = icon
    }
}
