import AppKit
import MetalKit
import QuartzCore
import CoreImage

/// A click-through, borderless window pinned to one display that renders EDR content.
///
/// In `.overlay` mode it covers the whole screen and multiplies the desktop by `factor`
/// (values above 1.0 in extended linear Display P3 push pixels into the HDR headroom).
/// In `.gamma` mode it shrinks to a single pixel whose bright value just keeps the
/// display pipeline in EDR mode, while the gamma table does the actual brightening.
final class OverlayWindow: NSWindow {
    enum Mode { case overlay, gamma }

    let displayID: CGDirectDisplayID
    private let renderer: EDRRenderer?
    private let metalView: MTKView

    init?(screen: NSScreen, displayID: CGDirectDisplayID, mode: Mode) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.displayID = displayID
        let frame = mode == .overlay
            ? screen.frame
            : NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
        metalView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        renderer = EDRRenderer(device: device)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        metalView.colorPixelFormat = .rgba16Float
        metalView.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        metalView.layer?.isOpaque = false
        if let layer = metalView.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.pixelFormat = .rgba16Float
        }
        if mode == .overlay {
            metalView.layer?.compositingFilter = CIFilter(name: "CIMultiplyBlendMode")
        }
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.delegate = renderer
        contentView = metalView
        setFrame(frame, display: false)
    }

    /// Updates the brightness multiplier and redraws.
    func apply(factor: Double) {
        renderer?.value = factor
        metalView.needsDisplay = true
        metalView.draw()
    }
}

/// Clears the drawable to a uniform extended-range grey; that is all the overlay needs to render.
final class EDRRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue?
    var value: Double = 1.0

    init(device: MTLDevice) {
        queue = device.makeCommandQueue()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        view.clearColor = MTLClearColor(red: value, green: value, blue: value, alpha: 1)
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
