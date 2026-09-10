import AppKit
import Foundation

@MainActor enum DemoExport {
    static func save(phase: String) throws -> String {
        guard let window = NSApp.keyWindow, let view = window.contentView else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--demo-output"), arguments.indices.contains(index + 1) else {
            return "启动时传入 --demo-output 目录后可导出"
        }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Render only this checker-owned view; no desktop or other application capture.
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let appearance = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let stem = "capture-\(UUID().uuidString)"
        let destination = directory.appendingPathComponent(stem + ".png")
        try png.write(to: destination, options: .withoutOverwriting)
        let metadata: [String: Any] = [
            "image": destination.lastPathComponent, "window": window.title,
            "phase": phase, "appearance": appearance, "simulation": true,
            "full_keyboard_access": NSApp.isFullKeyboardAccessEnabled,
            "width_points": view.bounds.width, "height_points": view.bounds.height,
            "width_pixels": bitmap.pixelsWide, "height_pixels": bitmap.pixelsHigh,
            "source": "NSView cacheDisplay of checker-owned content; not desktop screenshot"
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(stem + ".json"), options: .withoutOverwriting)
        return "已导出演示图：\(window.title.isEmpty ? "编辑弹窗" : window.title) · \(appearance)"
    }
}
