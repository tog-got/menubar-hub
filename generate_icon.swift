import Cocoa

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.saveGState()
        
        let cornerRadius = size * 0.224
        let iconRect = CGRect(x: size * 0.05, y: size * 0.05, width: size * 0.90, height: size * 0.90)
        let squircle = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        // 1. Drop Shadow
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.04), blur: size * 0.08, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        
        // 2. Base Dark Indigo Gradient
        ctx.addPath(squircle)
        ctx.clip()
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bgColors = [
            NSColor(srgbRed: 0.05, green: 0.04, blue: 0.15, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.18, green: 0.08, blue: 0.38, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.08, green: 0.12, blue: 0.28, alpha: 1.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.6, 1.0]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        }
        
        // 3. Glowing Ambient Orbs
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        
        // Cyan orb top-left
        let cyanColors = [NSColor(srgbRed: 0.0, green: 0.9, blue: 1.0, alpha: 0.45).cgColor, NSColor.clear.cgColor] as CFArray
        if let g1 = CGGradient(colorsSpace: colorSpace, colors: cyanColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(g1, startCenter: CGPoint(x: size * 0.3, y: size * 0.75), startRadius: 0, endCenter: CGPoint(x: size * 0.3, y: size * 0.75), endRadius: size * 0.45, options: [])
        }
        
        // Magenta orb bottom-right
        let magColors = [NSColor(srgbRed: 1.0, green: 0.15, blue: 0.65, alpha: 0.40).cgColor, NSColor.clear.cgColor] as CFArray
        if let g2 = CGGradient(colorsSpace: colorSpace, colors: magColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(g2, startCenter: CGPoint(x: size * 0.7, y: size * 0.25), startRadius: 0, endCenter: CGPoint(x: size * 0.7, y: size * 0.25), endRadius: size * 0.45, options: [])
        }
        ctx.restoreGState()
        
        // 4. Central Multi-Hub Graphic
        let cx = size * 0.5
        let cy = size * 0.5
        
        // Connecting Ring / Orbit
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(size * 0.022)
        ctx.addEllipse(in: CGRect(x: cx - size * 0.24, y: cy - size * 0.24, width: size * 0.48, height: size * 0.48))
        ctx.strokePath()
        
        // Central Glass Orb
        let centerRect = CGRect(x: cx - size * 0.13, y: cy - size * 0.13, width: size * 0.26, height: size * 0.26)
        ctx.addEllipse(in: centerRect)
        ctx.setFillColor(NSColor(srgbRed: 0.1, green: 0.15, blue: 0.35, alpha: 0.85).cgColor)
        ctx.fillPath()
        
        ctx.setStrokeColor(NSColor(srgbRed: 0.0, green: 0.9, blue: 1.0, alpha: 0.9).cgColor)
        ctx.setLineWidth(size * 0.02)
        ctx.addEllipse(in: centerRect)
        ctx.strokePath()
        
        // Signal glyph in center
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - size * 0.045, y: cy - size * 0.045, width: size * 0.09, height: size * 0.09))
        
        // 3 Orbit Nodes (Green, Blue, Pink)
        let angles: [(CGFloat, NSColor)] = [
            (CGFloat.pi * 0.5, NSColor(srgbRed: 0.15, green: 0.85, blue: 0.45, alpha: 1.0)),   // Top Node (Chat/WA)
            (CGFloat.pi * 1.85, NSColor(srgbRed: 0.15, green: 0.65, blue: 0.95, alpha: 1.0)),  // Bottom-Right Node (TG/X)
            (CGFloat.pi * 1.15, NSColor(srgbRed: 0.98, green: 0.25, blue: 0.55, alpha: 1.0))   // Bottom-Left Node (IG/Media)
        ]
        
        for (angle, color) in angles {
            let nx = cx + cos(angle) * (size * 0.24)
            let ny = cy + sin(angle) * (size * 0.24)
            let nodeRadius = size * 0.055
            
            // Node Glow
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: size * 0.04, color: color.cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: nx - nodeRadius, y: ny - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2))
            ctx.restoreGState()
            
            // Inner white dot
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: nx - nodeRadius * 0.35, y: ny - nodeRadius * 0.35, width: nodeRadius * 0.7, height: nodeRadius * 0.7))
        }
        
        // 5. Border Gloss Rim
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.20).cgColor)
        ctx.setLineWidth(size * 0.015)
        ctx.addPath(squircle)
        ctx.strokePath()
        
        ctx.restoreGState()
        return true
    }
    return image
}

let iconsetPath = "/tmp/MenuBarHub.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true, attributes: nil)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, s) in sizes {
    let img = createIcon(size: s)
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        let dest = "\(iconsetPath)/\(name)"
        try? png.write(to: URL(fileURLWithPath: dest))
    }
}
print("Iconset created successfully at \(iconsetPath)")
