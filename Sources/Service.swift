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
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            
            switch self {
            case .whatsapp:
                // WhatsApp: Official Green Circle (#25D366) + Speech Bubble with pointed tail + Phone receiver
                let bgPath = CGPath(ellipseIn: CGRect(x: 1.0, y: 1.0, width: 18, height: 18), transform: nil)
                ctx.setFillColor(NSColor(srgbRed: 0.149, green: 0.827, blue: 0.400, alpha: 1.0).cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                // White Speech Bubble with pointed tail
                let bubble = CGMutablePath()
                bubble.addArc(center: CGPoint(x: 10, y: 10), radius: 5.6, startAngle: 4.15, endAngle: 3.75, clockwise: false)
                bubble.addLine(to: CGPoint(x: 4.5, y: 4.5))
                bubble.closeSubpath()
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.addPath(bubble)
                ctx.fillPath()
                
                // Inside: WhatsApp Green Phone Handset
                ctx.setStrokeColor(NSColor(srgbRed: 0.149, green: 0.827, blue: 0.400, alpha: 1.0).cgColor)
                ctx.setLineWidth(1.8)
                ctx.setLineCap(.round)
                let phone = CGMutablePath()
                phone.move(to: CGPoint(x: 7.5, y: 7.2))
                phone.addQuadCurve(to: CGPoint(x: 12.5, y: 12.4), control: CGPoint(x: 7.7, y: 12.4))
                ctx.addPath(phone)
                ctx.strokePath()
                
            case .telegram:
                // Telegram: Official Blue Circle (#24A1DE) + White Paper Plane
                let bgPath = CGPath(ellipseIn: CGRect(x: 1.0, y: 1.0, width: 18, height: 18), transform: nil)
                ctx.setFillColor(NSColor(srgbRed: 0.141, green: 0.631, blue: 0.871, alpha: 1.0).cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                // White folded paper plane
                ctx.setFillColor(NSColor.white.cgColor)
                let plane = CGMutablePath()
                plane.move(to: CGPoint(x: 4.2, y: 9.8))
                plane.addLine(to: CGPoint(x: 15.6, y: 15.0))
                plane.addLine(to: CGPoint(x: 12.5, y: 5.0))
                plane.addLine(to: CGPoint(x: 9.5, y: 8.8))
                plane.addLine(to: CGPoint(x: 8.3, y: 7.6))
                plane.closeSubpath()
                ctx.addPath(plane)
                ctx.fillPath()
                
            case .instagram:
                // Instagram: Brand Gradient Rounded Square + Camera glyph
                let bgPath = CGPath(roundedRect: CGRect(x: 1.0, y: 1.0, width: 18, height: 18), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)
                ctx.addPath(bgPath)
                ctx.clip()
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let colors = [
                    NSColor(srgbRed: 0.98, green: 0.74, blue: 0.23, alpha: 1.0).cgColor,
                    NSColor(srgbRed: 0.88, green: 0.18, blue: 0.42, alpha: 1.0).cgColor,
                    NSColor(srgbRed: 0.51, green: 0.15, blue: 0.73, alpha: 1.0).cgColor
                ] as CFArray
                if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.5, 1.0]) {
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: 2, y: 2), end: CGPoint(x: 18, y: 18), options: [])
                }
                
                // Camera outline
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.4)
                let camRect = CGRect(x: 4.5, y: 4.5, width: 11, height: 11)
                let camPath = CGPath(roundedRect: camRect, cornerWidth: 3.0, cornerHeight: 3.0, transform: nil)
                ctx.addPath(camPath)
                ctx.strokePath()
                
                // Lens circle
                ctx.addEllipse(in: CGRect(x: 7.5, y: 7.5, width: 5.0, height: 5.0))
                ctx.strokePath()
                
                // Flash dot
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: 12.4, y: 12.4, width: 1.4, height: 1.4))
                
            case .tiktok:
                // TikTok: Official Black Circle + 3-layer Cyan & Magenta overlapping note
                let bgPath = CGPath(ellipseIn: CGRect(x: 1.0, y: 1.0, width: 18, height: 18), transform: nil)
                ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1.0).cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                let drawTikTokNote = { (offsetX: CGFloat, offsetY: CGFloat, color: NSColor) in
                    ctx.saveGState()
                    ctx.setFillColor(color.cgColor)
                    ctx.setStrokeColor(color.cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    
                    let cx = 10.0 + offsetX
                    let cy = 10.0 + offsetY
                    
                    // Bottom bowl
                    ctx.fillEllipse(in: CGRect(x: cx - 3.8, y: cy - 4.2, width: 4.0, height: 3.2))
                    
                    // Stem & top hook
                    let stem = CGMutablePath()
                    stem.move(to: CGPoint(x: cx - 0.2, y: cy - 2.6))
                    stem.addLine(to: CGPoint(x: cx - 0.2, y: cy + 4.0))
                    stem.addQuadCurve(to: CGPoint(x: cx + 3.8, y: cy + 1.5), control: CGPoint(x: cx + 3.4, y: cy + 4.2))
                    ctx.addPath(stem)
                    ctx.strokePath()
                    ctx.restoreGState()
                }
                
                drawTikTokNote(-0.6, 0.5, NSColor(srgbRed: 0.00, green: 0.95, blue: 0.99, alpha: 0.95))
                drawTikTokNote(0.6, -0.5, NSColor(srgbRed: 0.99, green: 0.17, blue: 0.33, alpha: 0.95))
                drawTikTokNote(0.0, 0.0, NSColor.white)
                
            case .facebook:
                // Facebook: Official Blue Circle (#1877F2) + White 'f'
                let bgPath = CGPath(ellipseIn: CGRect(x: 1.0, y: 1.0, width: 18, height: 18), transform: nil)
                ctx.setFillColor(NSColor(srgbRed: 0.09, green: 0.47, blue: 0.95, alpha: 1.0).cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                ctx.setFillColor(NSColor.white.cgColor)
                let fPath = CGMutablePath()
                fPath.move(to: CGPoint(x: 9.5, y: 3.5))
                fPath.addLine(to: CGPoint(x: 11.8, y: 3.5))
                fPath.addLine(to: CGPoint(x: 11.8, y: 8.5))
                fPath.addLine(to: CGPoint(x: 13.8, y: 8.5))
                fPath.addLine(to: CGPoint(x: 13.4, y: 10.6))
                fPath.addLine(to: CGPoint(x: 11.8, y: 10.6))
                fPath.addLine(to: CGPoint(x: 11.8, y: 12.0))
                fPath.addQuadCurve(to: CGPoint(x: 13.4, y: 13.6), control: CGPoint(x: 11.8, y: 13.6))
                fPath.addLine(to: CGPoint(x: 13.8, y: 13.6))
                fPath.addLine(to: CGPoint(x: 13.8, y: 16.0))
                fPath.addLine(to: CGPoint(x: 12.2, y: 16.0))
                fPath.addQuadCurve(to: CGPoint(x: 9.5, y: 13.0), control: CGPoint(x: 9.5, y: 16.0))
                fPath.addLine(to: CGPoint(x: 9.5, y: 10.6))
                fPath.addLine(to: CGPoint(x: 8.0, y: 10.6))
                fPath.addLine(to: CGPoint(x: 8.0, y: 8.5))
                fPath.addLine(to: CGPoint(x: 9.5, y: 8.5))
                fPath.closeSubpath()
                ctx.addPath(fPath)
                ctx.fillPath()
                
            case .x:
                // X (Twitter): Black Circle + Official 𝕏 Glyph
                let bgPath = CGPath(ellipseIn: CGRect(x: 1.0, y: 1.0, width: 18, height: 18), transform: nil)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.6)
                ctx.setLineCap(.round)
                
                ctx.move(to: CGPoint(x: 5.5, y: 14.5))
                ctx.addLine(to: CGPoint(x: 14.5, y: 5.5))
                ctx.move(to: CGPoint(x: 14.5, y: 14.5))
                ctx.addLine(to: CGPoint(x: 5.5, y: 5.5))
                ctx.strokePath()
                
            case .threads:
                // Threads: Black Circle + White '@' Spiral Glyph
                let bgPath = CGPath(ellipseIn: CGRect(x: 1.0, y: 1.0, width: 18, height: 18), transform: nil)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.5)
                let atPath = CGMutablePath()
                atPath.addArc(center: CGPoint(x: 10, y: 10), radius: 3.2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                atPath.addArc(center: CGPoint(x: 10, y: 10), radius: 5.0, startAngle: -0.8, endAngle: .pi * 1.5, clockwise: false)
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
