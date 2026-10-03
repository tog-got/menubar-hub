import Cocoa
import WebKit

// Enum for all 8 resize edge/corner handles
enum ResizeHandleEdge {
    case left
    case right
    case bottom
    case bottomLeft
    case bottomRight
}

// Custom handle view for dragging to resize popover from any border or corner
class ResizeEdgeHandleView: NSView {
    let edge: ResizeHandleEdge
    var onResize: ((NSSize) -> Void)?
    private var initialMouseLocation: NSPoint = .zero
    private var initialSize: NSSize = .zero
    
    init(edge: ResizeHandleEdge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = "Drag to resize window"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func resetCursorRects() {
        let cursor: NSCursor
        switch edge {
        case .left, .right:
            cursor = .resizeLeftRight
        case .bottom:
            cursor = .resizeUpDown
        case .bottomLeft, .bottomRight:
            cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard edge == .bottomLeft || edge == .bottomRight else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        context.saveGState()
        context.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        
        let w = bounds.width
        for i in 0..<3 {
            let offset = CGFloat(i * 4) + 4
            if edge == .bottomRight {
                context.move(to: CGPoint(x: w - 3, y: offset))
                context.addLine(to: CGPoint(x: w - offset, y: 3))
            } else {
                context.move(to: CGPoint(x: 3, y: offset))
                context.addLine(to: CGPoint(x: offset, y: 3))
            }
        }
        context.strokePath()
        context.restoreGState()
    }
    
    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        if let window = window {
            initialSize = window.frame.size
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentLocation = NSEvent.mouseLocation
        let deltaY = initialMouseLocation.y - currentLocation.y
        let deltaXRight = currentLocation.x - initialMouseLocation.x
        let deltaXLeft = initialMouseLocation.x - currentLocation.x
        
        var newWidth = initialSize.width
        var newHeight = initialSize.height
        
        switch edge {
        case .right:
            newWidth = max(380, min(1400, initialSize.width + deltaXRight))
        case .left:
            newWidth = max(380, min(1400, initialSize.width + deltaXLeft))
        case .bottom:
            newHeight = max(480, min(1100, initialSize.height + deltaY))
        case .bottomRight:
            newWidth = max(380, min(1400, initialSize.width + deltaXRight))
            newHeight = max(480, min(1100, initialSize.height + deltaY))
        case .bottomLeft:
            newWidth = max(380, min(1400, initialSize.width + deltaXLeft))
            newHeight = max(480, min(1100, initialSize.height + deltaY))
        }
        
        onResize?(NSSize(width: newWidth, height: newHeight))
    }
}

// Custom Draggable Top Bar (allows dragging window around when pinned)
class DraggableStackView: NSStackView {
    var canDrag: (() -> Bool)?
    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    
    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        if let window = self.window {
            initialWindowOrigin = window.frame.origin
        }
        super.mouseDown(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        if canDrag?() == true, let window = self.window {
            let currentLocation = NSEvent.mouseLocation
            let deltaX = currentLocation.x - initialMouseLocation.x
            let deltaY = currentLocation.y - initialMouseLocation.y
            window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + deltaX, y: initialWindowOrigin.y + deltaY))
        } else {
            super.mouseDragged(with: event)
        }
    }
}

public class MainViewController: NSViewController, VideoDownloaderDelegate {
    private var currentService: ServiceID = .whatsapp
    private var currentAccount: Int = 1
    private var isPinned: Bool = false
    private var isAutoScrollEnabled: Bool = true
    
    // Zoom state tracking
    private var serviceZoomLevels: [String: Double] = [:]
    
    private let topBar = DraggableStackView()
    private let serviceButtonsStack = NSStackView()
    private var serviceButtons: [NSButton] = []
    private let containerView = NSView()
    
    // All Edge & Corner Resize Handles (Full perimeter resizing)
    private let leftEdgeHandle = ResizeEdgeHandleView(edge: .left)
    private let rightEdgeHandle = ResizeEdgeHandleView(edge: .right)
    private let bottomEdgeHandle = ResizeEdgeHandleView(edge: .bottom)
    private let bottomLeftGrip = ResizeEdgeHandleView(edge: .bottomLeft)
    private let bottomRightGrip = ResizeEdgeHandleView(edge: .bottomRight)
    
    // Profile information
    public let profileNames = [
        "Home",
        "Work",
        "Project X",
        "Archive"
    ]
    
    private let profileLabel = NSTextField(labelWithString: "Logged in as: Home")
    private let switchBtn = NSButton()
    private let pinBtn = NSButton()
    private let autoScrollBtn = NSButton()
    private let downloadBtn = NSButton()
    private let downloadProgressLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    
    // Native Mode Override (allow user to force in-app web if desired)
    private var forceWebForPrimaryChat: [ServiceID: Bool] = [:]
    
    public override func loadView() {
        let savedW = UserDefaults.standard.double(forKey: "popoverWidth")
        let savedH = UserDefaults.standard.double(forKey: "popoverHeight")
        let w = savedW > 300 ? CGFloat(savedW) : 480
        let h = savedH > 400 ? CGFloat(savedH) : 660
        
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        VideoDownloader.shared.delegate = self
        
        setupUI()
        loadCurrentTab()
    }
    
    private func setupUI() {
        topBar.orientation = .vertical
        topBar.alignment = .centerX
        topBar.spacing = 6
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 6, right: 10)
        topBar.canDrag = { [weak self] in
            return self?.isPinned ?? false
        }
        
        // 1. Service Bar: Ultra-Compact Petite Icon Bar (16x16 icon in 22x22 target)
        serviceButtonsStack.orientation = .horizontal
        serviceButtonsStack.distribution = .gravityAreas
        serviceButtonsStack.alignment = .centerY
        serviceButtonsStack.spacing = 8
        serviceButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        
        let services = ServiceID.allCases
        for (index, service) in services.enumerated() {
            let btn = NSButton()
            btn.isBordered = false
            btn.bezelStyle = .regularSquare
            btn.image = service.iconImage
            btn.imageScaling = .scaleProportionallyUpOrDown
            btn.imagePosition = .imageOnly
            btn.toolTip = service.name
            btn.tag = index
            btn.target = self
            btn.action = #selector(serviceButtonClicked(_:))
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 5
            
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 22),
                btn.heightAnchor.constraint(equalToConstant: 22)
            ])
            
            serviceButtons.append(btn)
            serviceButtonsStack.addArrangedSubview(btn)
        }
        updateServiceButtonsUI()
        
        // 2. Navigation Row (Switch Account Pattern + Pin + AutoScroll + Download + Progress + Zoom + Navigation)
        let subRow = NSStackView()
        subRow.orientation = .horizontal
        subRow.alignment = .centerY
        subRow.distribution = .fill
        subRow.spacing = 5
        subRow.translatesAutoresizingMaskIntoConstraints = false
        
        // "Logged in as: Home" Label & Switch Button ("...")
        profileLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        profileLabel.textColor = NSColor.labelColor
        
        switchBtn.title = "..."
        switchBtn.bezelStyle = .recessed
        switchBtn.controlSize = .small
        switchBtn.font = NSFont.boldSystemFont(ofSize: 11)
        switchBtn.toolTip = "Switch Profile"
        switchBtn.target = self
        switchBtn.action = #selector(showProfileMenu(_:))
        
        let profileStack = NSStackView(views: [profileLabel, switchBtn])
        profileStack.orientation = .horizontal
        profileStack.spacing = 3
        profileStack.alignment = .centerY
        
        // Pin Button (Keep open / Always on top)
        pinBtn.isBordered = false
        pinBtn.bezelStyle = .regularSquare
        pinBtn.target = self
        pinBtn.action = #selector(togglePin)
        pinBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pinBtn.widthAnchor.constraint(equalToConstant: 22),
            pinBtn.heightAnchor.constraint(equalToConstant: 22)
        ])
        updatePinButtonUI()
        
        // Auto-Scroll Toggle Button (For TikTok & Instagram Reels)
        autoScrollBtn.isBordered = false
        autoScrollBtn.bezelStyle = .regularSquare
        autoScrollBtn.target = self
        autoScrollBtn.action = #selector(toggleAutoScroll)
        autoScrollBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            autoScrollBtn.widthAnchor.constraint(equalToConstant: 22),
            autoScrollBtn.heightAnchor.constraint(equalToConstant: 22)
        ])
        updateAutoScrollButtonUI()
        
        // Download Video Button (With Quality Selection Menu)
        downloadBtn.isBordered = false
        downloadBtn.bezelStyle = .regularSquare
        downloadBtn.target = self
        downloadBtn.action = #selector(showDownloadMenu(_:))
        downloadBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            downloadBtn.widthAnchor.constraint(equalToConstant: 22),
            downloadBtn.heightAnchor.constraint(equalToConstant: 22)
        ])
        updateDownloadButtonUI()
        
        // Real-time Download Progress Label
        downloadProgressLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        downloadProgressLabel.textColor = NSColor.systemBlue
        downloadProgressLabel.isHidden = true
        
        // Zoom Controls ( - | 100% | + )
        let zoomOutBtn = createIconButton(symbolName: "minus", toolTip: "Zoom Out", action: #selector(zoomOut))
        let zoomInBtn = createIconButton(symbolName: "plus", toolTip: "Zoom In", action: #selector(zoomIn))
        
        zoomLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoomLabel.textColor = NSColor.secondaryLabelColor
        zoomLabel.toolTip = "Click to reset zoom"
        let zoomClick = NSClickGestureRecognizer(target: self, action: #selector(resetZoom))
        zoomLabel.addGestureRecognizer(zoomClick)
        
        let zoomStack = NSStackView(views: [zoomOutBtn, zoomLabel, zoomInBtn])
        zoomStack.orientation = .horizontal
        zoomStack.spacing = 2
        zoomStack.alignment = .centerY
        
        // Web Navigation Buttons (Back, Forward, Reload)
        let backBtn = createIconButton(symbolName: "chevron.backward", toolTip: "Back", action: #selector(goBack))
        let forwardBtn = createIconButton(symbolName: "chevron.forward", toolTip: "Forward", action: #selector(goForward))
        let reloadBtn = createIconButton(symbolName: "arrow.clockwise", toolTip: "Reload", action: #selector(reloadCurrent))
        
        let navStack = NSStackView(views: [backBtn, forwardBtn, reloadBtn])
        navStack.orientation = .horizontal
        navStack.spacing = 2
        navStack.alignment = .centerY
        
        // Quit Button
        let quitBtn = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quitBtn.bezelStyle = .inline
        quitBtn.controlSize = .small
        
        subRow.addArrangedSubview(profileStack)
        subRow.addArrangedSubview(pinBtn)
        subRow.addArrangedSubview(autoScrollBtn)
        subRow.addArrangedSubview(downloadBtn)
        subRow.addArrangedSubview(downloadProgressLabel)
        subRow.addArrangedSubview(zoomStack)
        subRow.addArrangedSubview(navStack)
        subRow.addArrangedSubview(quitBtn)
        
        topBar.addArrangedSubview(serviceButtonsStack)
        topBar.addArrangedSubview(subRow)
        
        // 3. Container View for Content
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        
        // Divider line
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        
        // 4. Configure All Perimeter Resize Handles (Left, Right, Bottom, Corners)
        let resizeCallback: (NSSize) -> Void = { [weak self] newSize in
            self?.handleUserResize(newSize: newSize)
        }
        
        leftEdgeHandle.onResize = resizeCallback
        rightEdgeHandle.onResize = resizeCallback
        bottomEdgeHandle.onResize = resizeCallback
        bottomLeftGrip.onResize = resizeCallback
        bottomRightGrip.onResize = resizeCallback
        
        leftEdgeHandle.translatesAutoresizingMaskIntoConstraints = false
        rightEdgeHandle.translatesAutoresizingMaskIntoConstraints = false
        bottomEdgeHandle.translatesAutoresizingMaskIntoConstraints = false
        bottomLeftGrip.translatesAutoresizingMaskIntoConstraints = false
        bottomRightGrip.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(topBar)
        view.addSubview(divider)
        view.addSubview(containerView)
        view.addSubview(leftEdgeHandle)
        view.addSubview(rightEdgeHandle)
        view.addSubview(bottomEdgeHandle)
        view.addSubview(bottomLeftGrip)
        view.addSubview(bottomRightGrip)
        
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            subRow.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 6),
            subRow.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -6),
            
            divider.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            
            containerView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Left Edge Handle (Full left border)
            leftEdgeHandle.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftEdgeHandle.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            leftEdgeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            leftEdgeHandle.widthAnchor.constraint(equalToConstant: 8),
            
            // Right Edge Handle (Full right border)
            rightEdgeHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightEdgeHandle.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            rightEdgeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            rightEdgeHandle.widthAnchor.constraint(equalToConstant: 8),
            
            // Bottom Edge Handle (Full bottom border between corners)
            bottomEdgeHandle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            bottomEdgeHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            bottomEdgeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomEdgeHandle.heightAnchor.constraint(equalToConstant: 8),
            
            // Bottom Left Corner Handle
            bottomLeftGrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomLeftGrip.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomLeftGrip.widthAnchor.constraint(equalToConstant: 20),
            bottomLeftGrip.heightAnchor.constraint(equalToConstant: 20),
            
            // Bottom Right Corner Handle
            bottomRightGrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomRightGrip.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomRightGrip.widthAnchor.constraint(equalToConstant: 20),
            bottomRightGrip.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        updateProfileUI()
    }
    
    private func updateServiceButtonsUI() {
        let services = ServiceID.allCases
        for (index, btn) in serviceButtons.enumerated() {
            let service = services[index]
            if service == currentService {
                btn.alphaValue = 1.0
                btn.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
                btn.layer?.borderWidth = 0
            } else {
                btn.alphaValue = 0.50
                btn.layer?.backgroundColor = NSColor.clear.cgColor
                btn.layer?.borderWidth = 0
            }
        }
        
        // Contextual buttons: Auto-scroll on TikTok/IG; Video Downloader on all media tabs
        autoScrollBtn.isHidden = (currentService != .tiktok && currentService != .instagram)
        downloadBtn.isHidden = (currentService == .whatsapp || currentService == .telegram)
    }
    
    @objc private func serviceButtonClicked(_ sender: NSButton) {
        let selectedIndex = sender.tag
        let newService = ServiceID.allCases[selectedIndex]
        
        guard newService != currentService else { return }
        
        let oldService = currentService
        let oldAccount = currentAccount
        
        currentService = newService
        updateServiceButtonsUI()
        
        TabManager.shared.handleTabDeactivated(service: oldService, account: oldAccount)
        loadCurrentTab()
    }
    
    private func handleUserResize(newSize: NSSize) {
        self.view.frame.size = newSize
        if let popover = self.view.window?.value(forKey: "_popover") as? NSPopover {
            popover.contentSize = newSize
        }
        UserDefaults.standard.set(Double(newSize.width), forKey: "popoverWidth")
        UserDefaults.standard.set(Double(newSize.height), forKey: "popoverHeight")
    }
    
    private func createIconButton(symbolName: String, toolTip: String, action: Selector) -> NSButton {
        let btn: NSButton
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip) {
            btn = NSButton(image: img, target: self, action: action)
        } else {
            btn = NSButton(title: symbolName, target: self, action: action)
        }
        btn.bezelStyle = .roundRect
        btn.controlSize = .small
        btn.toolTip = toolTip
        return btn
    }
    
    // MARK: - Pin Action
    @objc public func togglePin() {
        isPinned.toggle()
        AppDelegate.shared?.setPinned(isPinned)
        updatePinButtonUI()
    }
    
    private func updatePinButtonUI() {
        if #available(macOS 11.0, *) {
            let color = isPinned ? NSColor.systemBlue : NSColor.secondaryLabelColor
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            let symbolName = isPinned ? "pin.fill" : "pin"
            pinBtn.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pin")?.withSymbolConfiguration(config)
        } else {
            pinBtn.title = isPinned ? "📌" : "📍"
        }
        pinBtn.toolTip = isPinned ? "Pinned (Drag top bar to move window)" : "Unpinned (Click to keep window open)"
    }
    
    // MARK: - Auto-Scroll Action
    @objc private func toggleAutoScroll() {
        isAutoScrollEnabled.toggle()
        updateAutoScrollButtonUI()
        
        let js = "window.__menubarHubAutoScrollEnabled = \(isAutoScrollEnabled ? "true" : "false");"
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func updateAutoScrollButtonUI() {
        if #available(macOS 11.0, *) {
            let color = isAutoScrollEnabled ? NSColor.systemGreen : NSColor.secondaryLabelColor
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            let symbolName = isAutoScrollEnabled ? "arrow.down.circle.fill" : "arrow.down.circle"
            autoScrollBtn.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Auto-Scroll")?.withSymbolConfiguration(config)
        } else {
            autoScrollBtn.title = isAutoScrollEnabled ? "🟢" : "⚪️"
        }
        autoScrollBtn.toolTip = isAutoScrollEnabled ? "Auto-Scroll: ON (Green - Auto plays next video when current ends)" : "Auto-Scroll: OFF (Click to enable)"
    }
    
    // MARK: - Video Downloader Action
    private func updateDownloadButtonUI() {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(paletteColors: [NSColor.systemBlue])
            downloadBtn.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: "Download Video")?.withSymbolConfiguration(config)
        } else {
            downloadBtn.title = "⬇"
        }
        downloadBtn.toolTip = "Download Video (Choose Quality)"
    }
    
    @objc private func showDownloadMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "Download Quality")
        
        let highItem = NSMenuItem(title: "🌟 High Quality (Original HD / Best)", action: #selector(downloadHighQuality), keyEquivalent: "")
        highItem.target = self
        menu.addItem(highItem)
        
        let standardItem = NSMenuItem(title: "📱 Standard Quality (720p / Fast)", action: #selector(downloadStandardQuality), keyEquivalent: "")
        standardItem.target = self
        menu.addItem(standardItem)
        
        let audioItem = NSMenuItem(title: "🎵 Audio Track Only (M4A / MP3)", action: #selector(downloadAudioOnly), keyEquivalent: "")
        audioItem.target = self
        menu.addItem(audioItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let openFolderItem = NSMenuItem(title: "📂 Open Downloads Folder", action: #selector(openDownloadsDirectory), keyEquivalent: "")
        openFolderItem.target = self
        menu.addItem(openFolderItem)
        
        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }
    
    @objc private func downloadHighQuality() {
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        VideoDownloader.shared.downloadVideo(from: webView, service: currentService, quality: "Original HD")
    }
    
    @objc private func downloadStandardQuality() {
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        VideoDownloader.shared.downloadVideo(from: webView, service: currentService, quality: "720p Standard")
    }
    
    @objc private func downloadAudioOnly() {
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        VideoDownloader.shared.downloadVideo(from: webView, service: currentService, quality: "Audio Track")
    }
    
    @objc private func openDownloadsDirectory() {
        VideoDownloader.shared.openDownloadsFolder()
    }
    
    // MARK: - VideoDownloaderDelegate
    public func didUpdateDownloadProgress(percent: Double, serviceName: String) {
        downloadProgressLabel.isHidden = false
        downloadProgressLabel.stringValue = "⬇ \(Int(percent))%"
        downloadProgressLabel.textColor = NSColor.systemBlue
    }
    
    public func didFinishDownload(filename: String, serviceName: String) {
        downloadProgressLabel.isHidden = false
        downloadProgressLabel.stringValue = "✓ Saved!"
        downloadProgressLabel.textColor = NSColor.systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.downloadProgressLabel.stringValue = ""
            self?.downloadProgressLabel.isHidden = true
        }
    }
    
    public func didFailDownload(error: String) {
        downloadProgressLabel.isHidden = false
        downloadProgressLabel.stringValue = "✗ Failed"
        downloadProgressLabel.textColor = NSColor.systemRed
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.downloadProgressLabel.stringValue = ""
            self?.downloadProgressLabel.isHidden = true
        }
    }
    
    @objc private func showProfileMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "Profiles")
        for (index, name) in profileNames.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(selectProfileItem(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index + 1
            if item.tag == currentAccount {
                item.state = .on
            }
            menu.addItem(item)
        }
        
        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: menu.item(withTitle: profileNames[currentAccount - 1]), at: point, in: sender)
    }
    
    @objc private func selectProfileItem(_ sender: NSMenuItem) {
        let newAccount = sender.tag
        switchToAccountIndex(newAccount)
    }
    
    public func getCurrentAccount() -> Int {
        return currentAccount
    }
    
    public func getCurrentService() -> ServiceID {
        return currentService
    }
    
    public func switchToAccountIndex(_ account: Int) {
        guard account != currentAccount else { return }
        
        let oldAccount = currentAccount
        currentAccount = account
        updateProfileUI()
        
        TabManager.shared.handleTabDeactivated(service: currentService, account: oldAccount)
        loadCurrentTab()
    }
    
    public func switchToServiceType(_ service: ServiceID) {
        guard service != currentService else { return }
        
        let oldService = currentService
        let oldAccount = currentAccount
        
        currentService = service
        updateServiceButtonsUI()
        
        TabManager.shared.handleTabDeactivated(service: oldService, account: oldAccount)
        loadCurrentTab()
    }
    
    public func resetWindowToDefault() {
        let defaultSize = NSSize(width: 480, height: 660)
        handleUserResize(newSize: defaultSize)
    }
    
    private func updateProfileUI() {
        let name = profileNames[currentAccount - 1]
        let attrString = NSMutableAttributedString(string: "Logged in as: ", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        attrString.append(NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]))
        profileLabel.attributedStringValue = attrString
    }
    
    private func loadCurrentTab() {
        containerView.subviews.forEach { $0.removeFromSuperview() }
        
        // Hybrid Routing Check: If Home (Primary) and isChat, check if user uses Native Routing
        if currentAccount == 1 && currentService.isChat && forceWebForPrimaryChat[currentService] != true {
            showNativeRoutingView(for: currentService)
            return
        }
        
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        
        // Restore zoom level
        let zoomKey = TabManager.shared.key(for: currentService, account: currentAccount)
        let currentZoom = serviceZoomLevels[zoomKey] ?? 1.0
        webView.pageZoom = currentZoom
        updateZoomLabel(zoom: currentZoom)
        
        // Sync auto-scroll state
        let js = "window.__menubarHubAutoScrollEnabled = \(isAutoScrollEnabled ? "true" : "false");"
        webView.evaluateJavaScript(js, completionHandler: nil)
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    private func showNativeRoutingView(for service: ServiceID) {
        let card = NSStackView()
        card.orientation = .vertical
        card.alignment = .centerX
        card.spacing = 14
        card.translatesAutoresizingMaskIntoConstraints = false
        
        let iconView = NSImageView()
        iconView.image = service.iconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        
        let titleLabel = NSTextField(labelWithString: "\(service.name) (Primary)")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        
        let descLabel = NSTextField(wrappingLabelWithString: "Primary account is routed to the official macOS native app for optimal speed and lowest RAM (~200 MB).")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = NSColor.secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 3
        
        let openBtn = NSButton(title: "Launch Native \(service.name)", target: self, action: #selector(launchNativeApp))
        openBtn.bezelStyle = .rounded
        openBtn.keyEquivalent = "\r"
        openBtn.controlSize = .regular
        
        let switchWebBtn = NSButton(title: "Open in Web View Instead", target: self, action: #selector(switchPrimaryToWeb))
        switchWebBtn.bezelStyle = .recessed
        switchWebBtn.controlSize = .small
        
        card.addArrangedSubview(iconView)
        card.addArrangedSubview(titleLabel)
        card.addArrangedSubview(descLabel)
        card.addArrangedSubview(openBtn)
        card.addArrangedSubview(switchWebBtn)
        
        containerView.addSubview(card)
        
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 30),
            card.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -30)
        ])
    }
    
    @objc private func launchNativeApp() {
        if currentService == .whatsapp {
            if let url = URL(string: "whatsapp://") {
                NSWorkspace.shared.open(url)
            }
        } else if currentService == .telegram {
            if let url = URL(string: "tg://") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func switchPrimaryToWeb() {
        forceWebForPrimaryChat[currentService] = true
        loadCurrentTab()
    }
    
    // MARK: - Zoom Actions
    @objc private func zoomIn() {
        adjustZoom(by: 0.1)
    }
    
    @objc private func zoomOut() {
        adjustZoom(by: -0.1)
    }
    
    @objc private func resetZoom() {
        setZoom(1.0)
    }
    
    private func adjustZoom(by delta: Double) {
        let zoomKey = TabManager.shared.key(for: currentService, account: currentAccount)
        let current = serviceZoomLevels[zoomKey] ?? 1.0
        let newZoom = max(0.5, min(2.5, current + delta))
        setZoom(newZoom)
    }
    
    private func setZoom(_ value: Double) {
        let zoomKey = TabManager.shared.key(for: currentService, account: currentAccount)
        serviceZoomLevels[zoomKey] = value
        
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        webView.pageZoom = value
        updateZoomLabel(zoom: value)
    }
    
    private func updateZoomLabel(zoom: Double) {
        let percent = Int(round(zoom * 100))
        zoomLabel.stringValue = "\(percent)%"
    }
    
    @objc private func goBack() {
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    @objc private func goForward() {
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    @objc private func reloadCurrent() {
        let webView = TabManager.shared.getOrCreateWebView(for: currentService, account: currentAccount)
        webView.reload()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    public func onPopoverClosed() {
        TabManager.shared.handlePopoverClosed(currentService: currentService, currentAccount: currentAccount)
    }
    
    public func onPopoverOpened() {
        TabManager.shared.handlePopoverOpened(currentService: currentService, currentAccount: currentAccount)
    }
}
