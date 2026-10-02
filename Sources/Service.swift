import Foundation
import AppKit

public enum ServiceID: String, CaseIterable {
    case whatsapp
    case telegram
    case instagram
    case tiktok
    case facebook
    case x
    case threads
    
    public var name: String {
        switch self {
        case .whatsapp: return "WhatsApp"
        case .telegram: return "Telegram"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .facebook: return "Facebook"
        case .x: return "X (Twitter)"
        case .threads: return "Threads"
        }
    }
    
    public var shortIcon: String {
        switch self {
        case .whatsapp: return "WA"
        case .telegram: return "TG"
        case .instagram: return "IG"
        case .tiktok: return "TT"
        case .facebook: return "FB"
        case .x: return "X"
        case .threads: return "TH"
        }
    }
    
    public var iconImage: NSImage? {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            
            switch self {
            case .whatsapp:
                // WhatsApp: Official Green Circle (#25D366) + Speech Bubble with pointed tail
                let bgPath = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 15, height: 15), transform: nil)
                ctx.setFillColor(NSColor(srgbRed: 0.149, green: 0.827, blue: 0.400, alpha: 1.0).cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                // White Speech Bubble with pointed tail
                let bubble = CGMutablePath()
                bubble.addArc(center: CGPoint(x: 8, y: 8), radius: 4.8, startAngle: 4.15, endAngle: 3.75, clockwise: false)
                bubble.addLine(to: CGPoint(x: 3.6, y: 3.6))
                bubble.closeSubpath()
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.addPath(bubble)
                ctx.fillPath()
                
                // Inside: WhatsApp Green Phone Handset
                ctx.setStrokeColor(NSColor(srgbRed: 0.149, green: 0.827, blue: 0.400, alpha: 1.0).cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineCap(.round)
                let phone = CGMutablePath()
                phone.move(to: CGPoint(x: 6.0, y: 5.8))
                phone.addQuadCurve(to: CGPoint(x: 10.0, y: 9.8), control: CGPoint(x: 6.2, y: 9.8))
                ctx.addPath(phone)
                ctx.strokePath()
                
            case .telegram:
                // Telegram: Official Blue Circle (#24A1DE) + White Paper Plane
                let bgPath = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 15, height: 15), transform: nil)
                ctx.setFillColor(NSColor(srgbRed: 0.141, green: 0.631, blue: 0.871, alpha: 1.0).cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                // White folded paper plane
                ctx.setFillColor(NSColor.white.cgColor)
                let plane = CGMutablePath()
                plane.move(to: CGPoint(x: 3.4, y: 7.8))
                plane.addLine(to: CGPoint(x: 12.5, y: 12.0))
                plane.addLine(to: CGPoint(x: 10.0, y: 4.0))
                plane.addLine(to: CGPoint(x: 7.6, y: 7.0))
                plane.addLine(to: CGPoint(x: 6.6, y: 6.0))
                plane.closeSubpath()
                ctx.addPath(plane)
                ctx.fillPath()
                
            case .instagram:
                // Instagram: Brand Gradient Rounded Square + Camera glyph
                let bgPath = CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: 15, height: 15), cornerWidth: 3.8, cornerHeight: 3.8, transform: nil)
                ctx.addPath(bgPath)
                ctx.clip()
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let colors = [
                    NSColor(srgbRed: 0.98, green: 0.74, blue: 0.23, alpha: 1.0).cgColor,
                    NSColor(srgbRed: 0.88, green: 0.18, blue: 0.42, alpha: 1.0).cgColor,
                    NSColor(srgbRed: 0.51, green: 0.15, blue: 0.73, alpha: 1.0).cgColor
                ] as CFArray
                if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.5, 1.0]) {
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: 1, y: 1), end: CGPoint(x: 15, y: 15), options: [])
                }
                
                // Camera outline
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.2)
                let camRect = CGRect(x: 3.5, y: 3.5, width: 9.0, height: 9.0)
                let camPath = CGPath(roundedRect: camRect, cornerWidth: 2.4, cornerHeight: 2.4, transform: nil)
                ctx.addPath(camPath)
                ctx.strokePath()
                
                // Lens circle
                ctx.addEllipse(in: CGRect(x: 6.0, y: 6.0, width: 4.0, height: 4.0))
                ctx.strokePath()
                
                // Flash dot
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: 9.8, y: 9.8, width: 1.2, height: 1.2))
                
            case .tiktok:
                // TikTok: Official Black Circle + 3-layer Cyan & Magenta overlapping note
                let bgPath = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 15, height: 15), transform: nil)
                ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1.0).cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                let drawTikTokNote = { (offsetX: CGFloat, offsetY: CGFloat, color: NSColor) in
                    ctx.saveGState()
                    ctx.setFillColor(color.cgColor)
                    ctx.setStrokeColor(color.cgColor)
                    ctx.setLineWidth(1.3)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    
                    let cx = 8.0 + offsetX
                    let cy = 8.0 + offsetY
                    
                    // Bottom bowl
                    ctx.fillEllipse(in: CGRect(x: cx - 3.0, y: cy - 3.4, width: 3.2, height: 2.6))
                    
                    // Stem & top hook
                    let stem = CGMutablePath()
                    stem.move(to: CGPoint(x: cx - 0.2, y: cy - 2.0))
                    stem.addLine(to: CGPoint(x: cx - 0.2, y: cy + 3.2))
                    stem.addQuadCurve(to: CGPoint(x: cx + 3.0, y: cy + 1.2), control: CGPoint(x: cx + 2.6, y: cy + 3.4))
                    ctx.addPath(stem)
                    ctx.strokePath()
                    ctx.restoreGState()
                }
                
                drawTikTokNote(-0.5, 0.4, NSColor(srgbRed: 0.00, green: 0.95, blue: 0.99, alpha: 0.95))
                drawTikTokNote(0.5, -0.4, NSColor(srgbRed: 0.99, green: 0.17, blue: 0.33, alpha: 0.95))
                drawTikTokNote(0.0, 0.0, NSColor.white)
                
            case .facebook:
                // Facebook: Official Blue Circle (#1877F2) + White 'f'
                let bgPath = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 15, height: 15), transform: nil)
                ctx.setFillColor(NSColor(srgbRed: 0.09, green: 0.47, blue: 0.95, alpha: 1.0).cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                ctx.setFillColor(NSColor.white.cgColor)
                let fPath = CGMutablePath()
                fPath.move(to: CGPoint(x: 7.6, y: 2.8))
                fPath.addLine(to: CGPoint(x: 9.4, y: 2.8))
                fPath.addLine(to: CGPoint(x: 9.4, y: 6.8))
                fPath.addLine(to: CGPoint(x: 11.0, y: 6.8))
                fPath.addLine(to: CGPoint(x: 10.7, y: 8.5))
                fPath.addLine(to: CGPoint(x: 9.4, y: 8.5))
                fPath.addLine(to: CGPoint(x: 9.4, y: 9.6))
                fPath.addQuadCurve(to: CGPoint(x: 10.7, y: 10.9), control: CGPoint(x: 9.4, y: 10.9))
                fPath.addLine(to: CGPoint(x: 11.0, y: 10.9))
                fPath.addLine(to: CGPoint(x: 11.0, y: 12.8))
                fPath.addLine(to: CGPoint(x: 9.7, y: 12.8))
                fPath.addQuadCurve(to: CGPoint(x: 7.6, y: 10.4), control: CGPoint(x: 7.6, y: 12.8))
                fPath.addLine(to: CGPoint(x: 7.6, y: 8.5))
                fPath.addLine(to: CGPoint(x: 6.4, y: 8.5))
                fPath.addLine(to: CGPoint(x: 6.4, y: 6.8))
                fPath.addLine(to: CGPoint(x: 7.6, y: 6.8))
                fPath.closeSubpath()
                ctx.addPath(fPath)
                ctx.fillPath()
                
            case .x:
                // X (Twitter): Black Circle + Official 𝕏 Glyph
                let bgPath = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 15, height: 15), transform: nil)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.4)
                ctx.setLineCap(.round)
                
                ctx.move(to: CGPoint(x: 4.4, y: 11.6))
                ctx.addLine(to: CGPoint(x: 11.6, y: 4.4))
                ctx.move(to: CGPoint(x: 11.6, y: 11.6))
                ctx.addLine(to: CGPoint(x: 4.4, y: 4.4))
                ctx.strokePath()
                
            case .threads:
                // Threads: Black Circle + White '@' Spiral Glyph
                let bgPath = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 15, height: 15), transform: nil)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.3)
                let atPath = CGMutablePath()
                atPath.addArc(center: CGPoint(x: 8, y: 8), radius: 2.6, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                atPath.addArc(center: CGPoint(x: 8, y: 8), radius: 4.0, startAngle: -0.8, endAngle: .pi * 1.5, clockwise: false)
                ctx.addPath(atPath)
                ctx.strokePath()
            }
            
            ctx.restoreGState()
            return true
        }
        return img
    }
    
    public var url: URL {
        switch self {
        case .whatsapp: return URL(string: "https://web.whatsapp.com")!
        case .telegram: return URL(string: "https://web.telegram.org/k/")! // Lightweight WebK engine
        case .instagram: return URL(string: "https://www.instagram.com")!
        case .tiktok: return URL(string: "https://www.tiktok.com")!
        case .facebook: return URL(string: "https://www.facebook.com")!
        case .x: return URL(string: "https://x.com")!
        case .threads: return URL(string: "https://www.threads.net")!
        }
    }
    
    public var isChat: Bool {
        return self == .whatsapp || self == .telegram
    }
}
