#if os(Linux) || os(Windows)
import Foundation
import CCairoRuntime

/// Only the drawing operations used by OverlayRenderer are adapted here. Component logic stays shared.
enum PortableGraphics {
    static let initializationError: String? = dls_graphics_initialize().map { String(cString: $0) }
    static let textLock = NSLock()
    static var textFailure: String?
    static func check() throws {
        if let error = initializationError { throw OverlayVideoError.invalidConfiguration(error) }
        textLock.lock(); let failure = textFailure; textLock.unlock()
        if let failure { throw OverlayVideoError.invalidConfiguration(failure) }
    }
}

typealias CFString = String
public final class CGColorSpace { let name: String? = "DeviceRGB" }
func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }
public struct CGColor {
    let red, green, blue, alpha: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    var components: [CGFloat]? { [red, green, blue, alpha] }
    var colorSpace: CGColorSpace? { CGColorSpace() }
    func copy(alpha: CGFloat) -> CGColor? { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
}

public final class CVPixelBuffer {
    let width, height, bytesPerRow: Int
    let pixels: UnsafeMutableRawPointer
    init(width: Int, height: Int) {
        self.width = width; self.height = height; bytesPerRow = width * 4
        pixels = .allocate(byteCount: bytesPerRow * height, alignment: 16)
        pixels.initializeMemory(as: UInt8.self, repeating: 0, count: bytesPerRow * height)
    }
    deinit { pixels.deallocate() }
    func clear() { pixels.initializeMemory(as: UInt8.self, repeating: 0, count: bytesPerRow * height) }
    func composite(over destination: CVPixelBuffer) {
        dls_graphics_composite(destination.pixels.assumingMemoryBound(to: UInt8.self), pixels.assumingMemoryBound(to: UInt8.self), Int32(width), Int32(height), Int32(bytesPerRow))
    }
    func straightAlphaData() -> Data {
        var data = Data(bytes: pixels, count: bytesPerRow * height)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let alpha = Int(bytes[offset + 3])
                for channel in 0..<3 {
                    bytes[offset + channel] = alpha == 0 ? 0 : UInt8(min(255, (Int(bytes[offset + channel]) * 255 + alpha / 2) / alpha))
                }
            }
        }
        return data
    }
}
struct CVPixelBufferLockFlags: OptionSet { let rawValue: Int; static let readOnly = Self(rawValue: 1) }
func CVPixelBufferLockBaseAddress(_ buffer: CVPixelBuffer, _ flags: CVPixelBufferLockFlags) {}
func CVPixelBufferUnlockBaseAddress(_ buffer: CVPixelBuffer, _ flags: CVPixelBufferLockFlags) {}
func CVPixelBufferGetBaseAddress(_ buffer: CVPixelBuffer) -> UnsafeMutableRawPointer? { buffer.pixels }
func CVPixelBufferGetWidth(_ buffer: CVPixelBuffer) -> Int { buffer.width }
func CVPixelBufferGetHeight(_ buffer: CVPixelBuffer) -> Int { buffer.height }
func CVPixelBufferGetBytesPerRow(_ buffer: CVPixelBuffer) -> Int { buffer.bytesPerRow }
enum CGImageAlphaInfo: UInt32 { case premultipliedFirst = 2 }
enum CGBitmapInfo: UInt32 { case byteOrder32Little = 8192 }

public class CGPath {
    enum Command { case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close }
    var commands: [Command] = []
}
public final class CGMutablePath: CGPath {
    func move(to point: CGPoint) { commands.append(.move(point)) }
    func addLine(to point: CGPoint) { commands.append(.line(point)) }
    func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first); for point in points.dropFirst() { addLine(to: point) }
    }
    func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) {
        let rx = min(rect.width / 2, max(0, cornerWidth)), ry = min(rect.height / 2, max(0, cornerHeight)), k = 0.5522847498307936
        move(to: CGPoint(x: rect.minX + rx, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - rx, y: rect.minY))
        commands.append(.curve(CGPoint(x: rect.maxX-rx+k*rx,y: rect.minY), CGPoint(x: rect.maxX,y: rect.minY+ry-k*ry), CGPoint(x: rect.maxX,y: rect.minY+ry)))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY-ry))
        commands.append(.curve(CGPoint(x: rect.maxX,y: rect.maxY-ry+k*ry), CGPoint(x: rect.maxX-rx+k*rx,y: rect.maxY), CGPoint(x: rect.maxX-rx,y: rect.maxY)))
        addLine(to: CGPoint(x: rect.minX+rx, y: rect.maxY))
        commands.append(.curve(CGPoint(x: rect.minX+rx-k*rx,y: rect.maxY), CGPoint(x: rect.minX,y: rect.maxY-ry+k*ry), CGPoint(x: rect.minX,y: rect.maxY-ry)))
        addLine(to: CGPoint(x: rect.minX, y: rect.minY+ry))
        commands.append(.curve(CGPoint(x: rect.minX,y: rect.minY+ry-k*ry), CGPoint(x: rect.minX+rx-k*rx,y: rect.minY), CGPoint(x: rect.minX+rx,y: rect.minY)))
        commands.append(.close)
    }
}

public final class CGContext {
    enum LineCap: Int32 { case butt = 0, round = 1, square = 2 }
    enum LineJoin: Int32 { case miter = 0, round = 1, bevel = 2 }
    private struct State {
        var fill = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        var stroke = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        var shadow: CGColor?, offset = CGSize.zero, blur: CGFloat = 0
    }
    private var state = State(), stack: [State] = []
    let handle: UnsafeMutableRawPointer
    var textPosition = CGPoint.zero
    init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) {
        guard PortableGraphics.initializationError == nil, let data,
              let handle = dls_graphics_create(data.assumingMemoryBound(to: UInt8.self), Int32(width), Int32(height), Int32(bytesPerRow)) else { return nil }
        self.handle = handle
    }
    deinit { dls_graphics_destroy(handle) }
    func setShouldAntialias(_ value: Bool) {}
    func setAllowsAntialiasing(_ value: Bool) {}
    func saveGState() { stack.append(state); dls_graphics_save(handle) }
    func restoreGState() { if let saved = stack.popLast() { state = saved; dls_graphics_restore(handle) } }
    func setFillColor(_ color: CGColor) { state.fill = color }
    func setStrokeColor(_ color: CGColor) { state.stroke = color }
    func setLineWidth(_ value: CGFloat) { dls_graphics_width(handle, value) }
    func setLineCap(_ value: LineCap) { dls_graphics_cap(handle, value.rawValue) }
    func setLineJoin(_ value: LineJoin) { dls_graphics_join(handle, value.rawValue) }
    func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) { state.shadow = color; state.offset = offset; state.blur = blur }
    func beginPath() { dls_graphics_new_path(handle) }
    func move(to point: CGPoint) { dls_graphics_move(handle, point.x, point.y) }
    func addLine(to point: CGPoint) { dls_graphics_line(handle, point.x, point.y) }
    func closePath() { dls_graphics_close(handle) }
    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        dls_graphics_arc(handle, center.x, center.y, radius, startAngle, endAngle, clockwise ? 1 : 0)
    }
    func addPath(_ path: CGPath) {
        for command in path.commands {
            switch command {
            case let .move(p): move(to: p)
            case let .line(p): addLine(to: p)
            case let .curve(a,b,c): dls_graphics_curve(handle,a.x,a.y,b.x,b.y,c.x,c.y)
            case .close: closePath()
            }
        }
    }
    func fillPath() { paint(stroke: false) }
    func strokePath() { paint(stroke: true) }
    func fill(_ rect: CGRect) { rectangle(rect); fillPath() }
    func fill(_ rects: [CGRect]) { for rect in rects { fill(rect) } }
    private func rectangle(_ rect: CGRect) {
        beginPath(); move(to: CGPoint(x: rect.minX,y: rect.minY)); addLine(to: CGPoint(x: rect.maxX,y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX,y: rect.maxY)); addLine(to: CGPoint(x: rect.minX,y: rect.maxY)); closePath()
    }
    private func ellipse(_ rect: CGRect) {
        let path = CGMutablePath(); path.addRoundedRect(in: rect, cornerWidth: rect.width/2, cornerHeight: rect.height/2)
        beginPath(); addPath(path)
    }
    func fillEllipse(in rect: CGRect) { ellipse(rect); fillPath() }
    func strokeEllipse(in rect: CGRect) { ellipse(rect); strokePath() }
    private func paint(stroke: Bool) {
        let c = stroke ? state.stroke : state.fill
        let shadow = state.shadow.map { [Double($0.red), Double($0.green), Double($0.blue), Double($0.alpha)] }
        dls_graphics_paint(handle,stroke ? 1 : 0,c.red,c.green,c.blue,c.alpha,state.offset.width,state.offset.height,state.blur,shadow)
    }
}

let kCTFontAttributeName = "DLSFont"
let kCTForegroundColorAttributeName = "DLSColor"
final class CTFont {
    let family: String, size: CGFloat, weight: Int32, italic: Bool
    init(name: String, size: CGFloat) {
        let parts = name.split(separator: "-", maxSplits: 1).map(String.init)
        let style = parts.last?.lowercased() ?? ""
        // The project names Apple fonts; use explicit, reproducible open-font substitutes.
        switch parts[0] {
        case "Menlo": family = "DejaVu Sans Mono"
        case "AvenirNextCondensed", "Futura": family = "DejaVu Sans Condensed"
        case "HelveticaNeue": family = "DejaVu Sans"
        default: family = parts[0]
        }
        self.size = size; italic = style.contains("italic") || style.contains("oblique")
        weight = style.contains("heavy") || style.contains("extrabold") ? 800 : style.contains("bold") ? 700 : style.contains("medium") ? 500 : style.contains("light") ? 300 : 400
    }
}
final class CTLine {
    let handle: UnsafeMutableRawPointer?, color: CGColor
    init(_ attributed: NSAttributedString) {
        let attributes = attributed.length == 0 ? [:] : attributed.attributes(at: 0, effectiveRange: nil)
        let font = attributes[NSAttributedString.Key(kCTFontAttributeName)] as? CTFont ?? CTFont(name: "Sans", size: 12)
        color = attributes[NSAttributedString.Key(kCTForegroundColorAttributeName)] as? CGColor ?? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        // elementBounds() can measure text before the first bitmap is created.
        guard PortableGraphics.initializationError == nil else { handle = nil; return }
        PortableGraphics.textLock.lock(); defer { PortableGraphics.textLock.unlock() }
        handle = dls_text_create(attributed.string, font.family, font.size, font.weight, font.italic ? 1 : 0)
        if handle == nil { PortableGraphics.textFailure = "Pango could not create a text layout." }
    }
    deinit {
        if let handle {
            PortableGraphics.textLock.lock(); defer { PortableGraphics.textLock.unlock() }
            dls_text_destroy(handle)
        }
    }
}
func CTFontCreateWithName(_ name: String, _ size: CGFloat, _ matrix: UnsafeRawPointer?) -> CTFont { CTFont(name: name, size: size) }
func CTLineCreateWithAttributedString(_ text: NSAttributedString) -> CTLine { CTLine(text) }
func CTLineDraw(_ line: CTLine, _ context: CGContext) {
    guard let handle = line.handle else { return }
    let c = line.color, p = context.textPosition
    PortableGraphics.textLock.lock(); defer { PortableGraphics.textLock.unlock() }
    dls_text_draw(context.handle, handle, p.x, p.y, c.red, c.green, c.blue, c.alpha)
}
struct CTLineBoundsOptions: OptionSet { let rawValue: Int; static let useGlyphPathBounds = Self(rawValue: 1) }
func CTLineGetBoundsWithOptions(_ line: CTLine, _ options: CTLineBoundsOptions) -> CGRect {
    guard let handle = line.handle else { return .zero }
    PortableGraphics.textLock.lock(); defer { PortableGraphics.textLock.unlock() }
    let m = dls_text_metrics(handle); return CGRect(x: m.x, y: m.y, width: m.width, height: m.height)
}
func CTLineGetTypographicBounds(_ line: CTLine, _ ascent: UnsafeMutablePointer<Double>?, _ descent: UnsafeMutablePointer<Double>?, _ leading: UnsafeMutablePointer<Double>?) -> Double {
    guard let handle = line.handle else { return 0 }
    PortableGraphics.textLock.lock(); defer { PortableGraphics.textLock.unlock() }
    return dls_text_metrics(handle).advance
}
#endif
