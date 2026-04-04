import Foundation
import MetalKit
import simd

class MetalRenderer {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let particleSystem: ParticleSystem

    var screenSize: CGSize = CGSize(width: 1, height: 1)
    var isEmitting: Bool = false
    var emitterPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)

    private var lastFrameTime: CFAbsoluteTime = 0

    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library")
        }

        self.particleSystem = ParticleSystem(
            device: device,
            library: library,
            colorPixelFormat: colorPixelFormat
        )

        self.lastFrameTime = CFAbsoluteTimeGetCurrent()
    }

    func draw(in view: MTKView) {
        let now = CFAbsoluteTimeGetCurrent()
        var deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now

        // Clamp delta time to avoid large jumps
        deltaTime = min(deltaTime, 1.0 / 30.0)

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        let emitCount: UInt32 = isEmitting ? 2048 : 0

        particleSystem.updateSimParams(
            deltaTime: deltaTime,
            emitterX: emitterPosition.x,
            emitterY: emitterPosition.y,
            emitterZ: emitterPosition.z,
            emitCount: emitCount,
            screenHeight: Float(screenSize.height)
        )

        let viewProjection = buildViewProjectionMatrix()

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        particleSystem.encodeCompute(commandBuffer: commandBuffer)
        particleSystem.encodeRender(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            viewProjection: viewProjection,
            screenHeight: Float(screenSize.height)
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func buildViewProjectionMatrix() -> simd_float4x4 {
        let aspect = Float(screenSize.width / screenSize.height)
        let projection = float4x4.perspective(
            fovYRadians: Float.pi / 3.0,
            aspect: aspect,
            near: 0.1,
            far: 100.0
        )
        let view = float4x4.lookAt(
            eye: SIMD3<Float>(0, 2, -8),
            center: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        return projection * view
    }
}

// MARK: - float4x4 Matrix Utilities

extension float4x4 {

    static func perspective(fovYRadians fovy: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let yScale = 1.0 / tanf(fovy * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near

        return float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, -(far + near) / zRange, -1),
            SIMD4<Float>(0, 0, -2.0 * far * near / zRange, 0)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)

        return float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
        ))
    }
}
