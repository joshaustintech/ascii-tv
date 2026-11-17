import CoreText
import GlobeCore
import MetalKit
import UIKit

/// Draws two character grids (the globe, and a coarser label layer on top) with a single full-screen triangle.
/// Each pixel costs at most two cell lookups and one glyph lookup, and empty cells exit before the glyph lookup.
final class Renderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private var globeCells: MTLTexture?
    private var globeAtlas: MTLTexture?
    private var labelCells: MTLTexture?
    private var labelAtlas: MTLTexture?
    private var cellSizes: [UInt32] = [1, 1, 1, 1]
    private let palette: [SIMD4<Float>] = Ink.allCases.map { SIMD4($0.rgb.r, $0.rgb.g, $0.rgb.b, 1) }

    init?(view: MTKView) {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vmain")
        descriptor.fragmentFunction = library.makeFunction(name: "fmain")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    /// Call when the screen size changes. Cell sizes are in pixels.
    func configure(globe: GlobeGrid, globeCell: (w: Int, h: Int), labels: TextGrid, labelCell: (w: Int, h: Int)) {
        globeCells = makeCellTexture(globe.cols, globe.rows)
        labelCells = makeCellTexture(labels.cols, labels.rows)
        globeAtlas = makeAtlas(cellW: globeCell.w, cellH: globeCell.h)
        labelAtlas = makeAtlas(cellW: labelCell.w, cellH: labelCell.h)
        cellSizes = [UInt32(globeCell.w), UInt32(globeCell.h), UInt32(labelCell.w), UInt32(labelCell.h)]
    }

    func upload(globe: GlobeGrid, labels: TextGrid) {
        if let t = globeCells { replace(t, globe.cells) }
        if let t = labelCells { replace(t, labels.cells) }
    }

    func draw(in view: MTKView) {
        guard let globeCells, let globeAtlas, let labelCells, let labelAtlas,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer() else { return }
        pass.colorAttachments[0].loadAction = .dontCare   // the triangle writes every pixel
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(globeCells, index: 0)
        encoder.setFragmentTexture(globeAtlas, index: 1)
        encoder.setFragmentTexture(labelCells, index: 2)
        encoder.setFragmentTexture(labelAtlas, index: 3)
        encoder.setFragmentBytes(cellSizes, length: MemoryLayout<UInt32>.stride * 4, index: 0)
        encoder.setFragmentBytes(palette, length: MemoryLayout<SIMD4<Float>>.stride * palette.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    private func makeCellTexture(_ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Uint, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        return device.makeTexture(descriptor: d)
    }

    private func replace(_ texture: MTLTexture, _ bytes: [UInt8]) {
        bytes.withUnsafeBytes {
            guard let base = $0.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0,
                            withBytes: base, bytesPerRow: texture.width * 4)
        }
    }

    /// ASCII 32...126, sixteen to a row. Each slot is exactly one cell in pixels, so the shader reads
    /// glyph pixels one-to-one and never needs a sampler.
    private func makeAtlas(cellW: Int, cellH: Int) -> MTLTexture? {
        let w = cellW * 16, h = cellH * 6
        var pixels = [UInt8](repeating: 0, count: w * h)

        var size = CGFloat(cellH) * 0.84
        var font = UIFont.monospacedSystemFont(ofSize: size, weight: .bold) as CTFont
        var advance = Self.advance(of: font)
        if advance > CGFloat(cellW) {
            size *= CGFloat(cellW) / advance
            font = UIFont.monospacedSystemFont(ofSize: size, weight: .bold) as CTFont
            advance = Self.advance(of: font)
        }
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)

        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ]
            for code in 33...126 {
                let slot = code - 32
                let x = CGFloat((slot % 16) * cellW)
                let bottom = CGFloat(h - (slot / 16 + 1) * cellH)
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: String(UnicodeScalar(UInt8(code))), attributes: attributes))
                context.saveGState()
                context.clip(to: CGRect(x: x, y: bottom, width: CGFloat(cellW), height: CGFloat(cellH)))
                context.textPosition = CGPoint(x: x + (CGFloat(cellW) - advance) / 2,
                                               y: bottom + descent + (CGFloat(cellH) - ascent - descent) / 2)
                CTLineDraw(line, context)
                context.restoreGState()
            }
        }

        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w)
        return texture
    }

    private static func advance(of font: CTFont) -> CGFloat {
        var glyph = CGGlyph(0)
        var character: UniChar = 77 // "M"; the font is monospaced so any glyph will do
        CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        var size = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &size, 1)
        return size.width
    }
}
