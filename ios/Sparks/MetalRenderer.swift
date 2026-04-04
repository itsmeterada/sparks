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
    private let pipelineStates: [MTLRenderPipelineState]
    private let starsTexture: MTLTexture?
    private let samplerState: MTLSamplerState

    private let startTime: CFAbsoluteTime
    private var currentShader: Int = 0

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

        let fragmentNames = ["sparks_fragment", "cosmic_fragment", "starship_fragment"]
        var states: [MTLRenderPipelineState] = []
        for name in fragmentNames {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "sparks_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: name)
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            do {
                states.append(try device.makeRenderPipelineState(descriptor: descriptor))
            } catch {
                fatalError("Failed to create render pipeline state for \(name): \(error)")
            }
        }
        self.pipelineStates = states

        // Load stars texture
        let loader = MTKTextureLoader(device: device)
        if let url = Bundle.main.url(forResource: "stars", withExtension: "jpg") {
            self.starsTexture = try? loader.newTexture(URL: url, options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
            ])
        } else {
            self.starsTexture = nil
        }

        // Create sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)!
    }

    func toggleShader() {
        currentShader = (currentShader + 1) % pipelineStates.count
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

        encoder.setRenderPipelineState(pipelineStates[currentShader])
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        // Bind texture and sampler for starship shader
        if let tex = starsTexture {
            encoder.setFragmentTexture(tex, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
