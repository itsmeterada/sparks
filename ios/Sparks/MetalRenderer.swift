import Foundation
import MetalKit
import simd

struct Uniforms {
    var iResolution: SIMD2<Float>
    var iTime: Float
}

class MetalRenderer {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderPipelineState: MTLRenderPipelineState

    private let startTime: CFAbsoluteTime

    var screenSize: CGSize = CGSize(width: 1, height: 1)

    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device
        self.startTime = CFAbsoluteTimeGetCurrent()

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "sparks_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "sparks_fragment")
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        do {
            self.renderPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        let iTime = Float(CFAbsoluteTimeGetCurrent() - startTime)

        var uniforms = Uniforms(
            iResolution: SIMD2<Float>(Float(screenSize.width), Float(screenSize.height)),
            iTime: iTime
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        // Draw fullscreen triangle (3 vertices, no vertex buffer)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
