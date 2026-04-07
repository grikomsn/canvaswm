#!/usr/bin/swift
import Cocoa

let iconName = "rectangle.3.group"
let assetsDir = "../Assets.xcassets/AppIcon.appiconset"
let iconsetDir = "../AppIcon.iconset"
let icnsPath = "../AppIcon.icns"

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

// Create iconset directory
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, filename) in sizes {
    // Create image with background
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    // Draw gradient background
    let context = NSGraphicsContext.current!.cgContext
    let colors = [
        NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.88, alpha: 1.0).cgColor
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
    
    // Draw rounded rect mask for proper macOS icon shape
    let cornerRadius = CGFloat(size) * 0.22
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()
    
    image.unlockFocus()
    
    // Re-render with clip
    let finalImage = NSImage(size: NSSize(width: size, height: size))
    finalImage.lockFocus()
    
    // Draw gradient background with rounded corners
    let finalContext = NSGraphicsContext.current!.cgContext
    let roundedPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    roundedPath.addClip()
    finalContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
    
    // Get SF Symbol
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.5, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        // Draw white SF Symbol centered
        let iconSize = CGFloat(size) * 0.6
        let iconX = (CGFloat(size) - iconSize) / 2
        let iconY = (CGFloat(size) - iconSize) / 2
        let iconRect = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        
        NSColor.white.setFill()
        symbol.draw(in: iconRect)
    }
    
    finalImage.unlockFocus()
    
    // Save as PNG to Assets
    if let tiff = finalImage.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let data = bitmap.representation(using: .png, properties: [:]) {
        let path = "\(assetsDir)/\(filename)"
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Generated: \(path) (\(size)x\(size))")
        } catch {
            print("Error writing \(path): \(error)")
        }
    } else {
        print("Failed to generate \(filename)")
    }
    
    // Save to iconset for .icns (iconutil format)
    // iconutil expects: icon_<width>x<height>.png or icon_<width>x<height>@2x.png
    let iconsetFilename: String
    switch size {
    case 16: iconsetFilename = "icon_16x16.png"
    case 32 where filename.contains("16"): iconsetFilename = "icon_16x16@2x.png"
    case 32: iconsetFilename = "icon_32x32.png"
    case 64: iconsetFilename = "icon_32x32@2x.png"
    case 128: iconsetFilename = "icon_128x128.png"
    case 256 where filename.contains("128"): iconsetFilename = "icon_128x128@2x.png"
    case 256: iconsetFilename = "icon_256x256.png"
    case 512 where filename.contains("256"): iconsetFilename = "icon_256x256@2x.png"
    case 512: iconsetFilename = "icon_512x512.png"
    case 1024: iconsetFilename = "icon_512x512@2x.png"
    default: iconsetFilename = "icon_\(size)x\(size).png"
    }
    
    if let tiff = finalImage.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let data = bitmap.representation(using: .png, properties: [:]) {
        let path = "\(iconsetDir)/\(iconsetFilename)"
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            print("Error writing iconset \(path): \(error)")
        }
    }
}

// Compile iconset to .icns using iconutil
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["--convert", "icns", "--output", icnsPath, iconsetDir]

do {
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus == 0 {
        print("Generated: \(icnsPath)")
    } else {
        print("Warning: iconutil failed (exit code \(task.terminationStatus))")
    }
} catch {
    print("Error running iconutil: \(error)")
}

// Clean up iconset directory
try? fm.removeItem(atPath: iconsetDir)

print("Icon generation complete!")
