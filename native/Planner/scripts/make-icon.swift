import AppKit
import ImageIO
import UniformTypeIdentifiers

// Code-native counterpart of the existing orange checkmark identity.
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.88, green: 0.34, blue: 0.16, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(CGColor(gray: 1, alpha: 1)); context.setLineWidth(72)
context.setLineCap(.round); context.setLineJoin(.round)
context.move(to: CGPoint(x: 270, y: 510)); context.addLine(to: CGPoint(x: 440, y: 340))
context.addLine(to: CGPoint(x: 765, y: 705)); context.strokePath()
let url = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("图标写入失败") }
