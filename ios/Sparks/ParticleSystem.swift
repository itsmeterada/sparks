import Foundation
import Metal
import simd

class ParticleSystem {

    static let MAX_PARTICLES: Int = 262144
    private static let PARTICLE_STRIDE: Int = 48  // 3 x float4 = 48 bytes

    private let device: MTLDevice
    private let particleBuffer: MTLBuffer
    private let simParamsBuffer: MTLBuffer
    private let computePipelineState: MTLComputePipelineState
    private let renderPipelineState: MTLRenderPipelineState
    private var frameNumber: UInt32 = 0

    init(device: MTLDevice, library: MTLLibrary, colorPixelFormat: MTLPixelFormat) {
        self.device = device

        // Create particle buffer (zero-initialized, all particles start dead)
        let particleBufferSize = ParticleSystem.MAX_PARTICLES * ParticleSystem.PARTICLE_STRIDE
        guard let pBuffer = device.makeBuffer(length: particleBufferSize, options: .storageModeShared) else {
            fatalError("Failed to create particle buffer")
        }
        self.particleBuffer = pBuffer
        memset(particleBuffer.contents(), 0, particleBufferSize)

        // Create sim params buffer
        let simParamsSize = MemoryLayout<SimParams>.stride
        guard let sBuffer = device.makeBuffer(length: simParamsSize, options: .storageModeShared) else {
            fatalError("Failed to create sim params buffer")
        }
        self.simParamsBuffer = sBuffer

        // Create compute pipeline
        guard let computeFunction = library.makeFunction(name: "particle_simulate") else {
            fatalError("Failed to find particle_simulate function in Metal library")
        }
        do {
            self.computePipelineState = try device.makeComputePipelineState(function: computeFunction)
        } catch {
            fatalError("Failed to create compute pipeline state: \(error)")
        }

        // Create render pipeline
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "particle_vertex")
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "particle_fragment")

        let colorAttachment = renderPipelineDescriptor.colorAttachments[0]!
        colorAttachment.pixelFormat = colorPixelFormat
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .one
        colorAttachment.destinationRGBBlendFactor = .one
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .one

        do {
            self.renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }

    func updateSimParams(
        deltaTime: Float,
        emitterX: Float,
        emitterY: Float,
        emitterZ: Float,
        emitCount: UInt32,
        screenHeight: Float
    ) {
        var params = SimParams(
            deltaTime: deltaTime,
            emitterX: emitterX,
            emitterY: emitterY,
            emitterZ: emitterZ,
            emitCount: emitCount,
            maxParticles: UInt32(ParticleSystem.MAX_PARTICLES),
            gravity: -9.8,
            damping: 0.985,
            baseLifetime: 2.0,
            lifetimeVariance: 0.8,
            sparkBrightness: 1.5,
            frameNumber: frameNumber
        )
        memcpy(simParamsBuffer.contents(), &params, MemoryLayout<SimParams>.stride)
        frameNumber += 1
    }

    func encodeCompute(commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(computePipelineState)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(simParamsBuffer, offset: 0, index: 1)

        let threadGroupSize = MTLSize(width: 256, height: 1, depth: 1)
        let threadGroups = MTLSize(
            width: (ParticleSystem.MAX_PARTICLES + 255) / 256,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
    }

    func encodeRender(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        viewProjection: simd_float4x4,
        screenHeight: Float
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)

        var uniforms = RenderUniforms(
            viewProjection: viewProjection,
            sparkBrightness: 1.5,
            screenHeight: screenHeight
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)

        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: ParticleSystem.MAX_PARTICLES)
        encoder.endEncoding()
    }
}

// MARK: - C-compatible structs matching Metal shader layout

struct SimParams {
    var deltaTime: Float
    var emitterX: Float
    var emitterY: Float
    var emitterZ: Float
    var emitCount: UInt32
    var maxParticles: UInt32
    var gravity: Float
    var damping: Float
    var baseLifetime: Float
    var lifetimeVariance: Float
    var sparkBrightness: Float
    var frameNumber: UInt32
}

struct RenderUniforms {
    var viewProjection: simd_float4x4
    var sparkBrightness: Float
    var screenHeight: Float
}
