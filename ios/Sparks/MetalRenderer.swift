import Foundation
import MetalKit
import simd

struct Uniforms {
    var iResolution: SIMD2<Float>
    var iTime: Float
    var _pad: Float = 0
    var iMouse: SIMD4<Float> = .zero
    var mode: Int32 = 0
    var iFrame: Int32 = 0
}

class MetalRenderer {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineStates: [MTLRenderPipelineState]
    private let starsTexture: MTLTexture?
    private let noiseMedTexture: MTLTexture?
    private let noiseSmallTexture: MTLTexture?
    private let noise3DTexture: MTLTexture?
    private let samplerState: MTLSamplerState

    // --- Fluid (multipass) ---
    private static let FLUID_SHADER_INDEX = 21
    private static let FLUID_MAX_DIM = 1024
    private static let FLUID_MIP_COUNT = 11
    private let fluidPipelineA: MTLRenderPipelineState
    private let fluidPipelineB: MTLRenderPipelineState
    private let fluidPipelineC: MTLRenderPipelineState
    private let fluidPipelineD: MTLRenderPipelineState
    private var fluidTexA: [MTLTexture] = []
    private var fluidTexB: [MTLTexture] = []
    private var fluidTexC: [MTLTexture] = []
    private var fluidTexD: [MTLTexture] = []
    private var fluidSimWidth: Int = 0
    private var fluidSimHeight: Int = 0
    private var fluidFrameIndex: Int32 = 0
    private var fluidReadIdx: Int = 0

    private let startTime: CFAbsoluteTime
    private var currentShader: Int = 0
    private var currentMode: Int32 = 0
    private var mouseState: SIMD4<Float> = .zero
    private var mousePressed: Bool = false
    private var mouseInitialized: Bool = false
    private var virtualMouseX: Float = 0
    private var virtualMouseY: Float = 0
    private var touchStartX: Float = 0
    private var touchStartY: Float = 0
    private var virtualStartX: Float = 0
    private var virtualStartY: Float = 0

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

        let fragmentNames = ["sparks_fragment", "cosmic_fragment", "starship_fragment", "clouds_fragment", "seascape_fragment", "rainforest_fragment", "plasma_fragment", "grid_fragment", "interstellar_fragment", "mandelbulb_fragment", "cyberspace_fragment", "tunnel_fragment", "fractal_fragment", "mandelbulb2_fragment", "octgrams_fragment", "palette_fragment", "primitives_fragment", "voxellines_fragment", "protean_fragment", "rocaille_fragment", "hudrings_fragment", "fluid_image_fragment"]
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

        // --- Fluid buffer pipelines (render into rgba16Float offscreen targets) ---
        func makeFluidPipeline(_ name: String) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "sparks_vertex")
            d.fragmentFunction = library.makeFunction(name: name)
            d.colorAttachments[0].pixelFormat = .rgba16Float
            do {
                return try device.makeRenderPipelineState(descriptor: d)
            } catch {
                fatalError("Failed to create fluid pipeline \(name): \(error)")
            }
        }
        self.fluidPipelineA = makeFluidPipeline("fluid_bufferA_fragment")
        self.fluidPipelineB = makeFluidPipeline("fluid_bufferB_fragment")
        self.fluidPipelineC = makeFluidPipeline("fluid_bufferC_fragment")
        self.fluidPipelineD = makeFluidPipeline("fluid_bufferD_fragment")

        // Load textures
        let loader = MTKTextureLoader(device: device)
        let texOpts: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .SRGB: NSNumber(value: false)
        ]
        self.starsTexture = Self.loadTexture(loader: loader, name: "stars", ext: "jpg", options: texOpts)
        self.noiseMedTexture = Self.loadTexture(loader: loader, name: "rgba_noise_medium", ext: "png", options: texOpts)
        self.noiseSmallTexture = Self.loadTexture(loader: loader, name: "rgba_noise_large", ext: "png", options: texOpts) // iChannel1: 1024x1024 for texelFetch dithering
        self.noise3DTexture = Self.load3DTexture(device: device, name: "grey_noise_3d", ext: "bin", width: 32, height: 32, depth: 32)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerDescriptor.rAddressMode = .repeat
        self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)!
    }

    private static func loadTexture(loader: MTKTextureLoader, name: String, ext: String, options: [MTKTextureLoader.Option: Any]) -> MTLTexture? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? loader.newTexture(URL: url, options: options)
    }

    private static func load3DTexture(device: MTLDevice, name: String, ext: String, width: Int, height: Int, depth: Int) -> MTLTexture? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let raw = try? Data(contentsOf: url),
              raw.count == width * height * depth else { return nil }
        let desc = MTLTextureDescriptor()
        desc.textureType = .type3D
        desc.pixelFormat = .r8Unorm
        desc.width = width; desc.height = height; desc.depth = depth
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        raw.withUnsafeBytes { ptr in
            tex.replace(region: MTLRegionMake3D(0, 0, 0, width, height, depth),
                        mipmapLevel: 0, slice: 0,
                        withBytes: ptr.baseAddress!,
                        bytesPerRow: width, bytesPerImage: width * height)
        }
        return tex
    }

    func toggleShader() {
        currentShader = (currentShader + 1) % pipelineStates.count
    }

    func toggleMode() {
        currentMode = (currentMode + 1) % 2
    }

    var halfRes: Bool = false

    func onTouchDown(x: Float, y: Float) {
        if !mouseInitialized {
            virtualMouseX = Float(screenSize.width) * 0.5
            virtualMouseY = Float(screenSize.height) * 0.4
            mouseInitialized = true
        }
        mousePressed = true
        touchStartX = x
        touchStartY = y
        virtualStartX = virtualMouseX
        virtualStartY = virtualMouseY
        mouseState = SIMD4<Float>(virtualMouseX, virtualMouseY, virtualMouseX, virtualMouseY)
    }

    func onTouchMove(x: Float, y: Float) {
        if mousePressed {
            virtualMouseX = virtualStartX + (x - touchStartX)
            virtualMouseY = virtualStartY + (y - touchStartY)
            mouseState.x = virtualMouseX
            mouseState.y = virtualMouseY
        }
    }

    func onTouchUp() {
        mousePressed = false
        // Keep z positive so shader holds camera position
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }

        let iTime = Float(CFAbsoluteTimeGetCurrent() - startTime)

        var uniforms = Uniforms(
            iResolution: SIMD2<Float>(Float(screenSize.width), Float(screenSize.height)),
            iTime: iTime,
            iMouse: mouseState,
            mode: currentMode
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if currentShader == MetalRenderer.FLUID_SHADER_INDEX {
            drawFluid(in: view, commandBuffer: commandBuffer, baseUniforms: uniforms)
        } else {
            guard let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }

            encoder.setRenderPipelineState(pipelineStates[currentShader])
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)

            switch currentShader {
            case 2: // starship
                if let tex = starsTexture { encoder.setFragmentTexture(tex, index: 0) }
            case 3: // clouds
                if let tex = noiseMedTexture { encoder.setFragmentTexture(tex, index: 0) }
                if let tex = noiseSmallTexture { encoder.setFragmentTexture(tex, index: 1) }
                if let tex = noise3DTexture { encoder.setFragmentTexture(tex, index: 2) }
            case 6: // plasma
                if let tex = noiseMedTexture { encoder.setFragmentTexture(tex, index: 0) }
            case 7: // grid
                if let tex = noiseMedTexture { encoder.setFragmentTexture(tex, index: 0) }
            case 8: // interstellar
                if let tex = noiseMedTexture { encoder.setFragmentTexture(tex, index: 0) }
            case 17: // voxellines
                if let tex = noiseMedTexture { encoder.setFragmentTexture(tex, index: 0) }
            default:
                break
            }

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // --- Fluid (multipass) helpers ---

    private func ensureFluidResources() {
        let screenW = Float(screenSize.width)
        let screenH = Float(screenSize.height)
        let aspect = max(0.1, screenW / max(1.0, screenH))
        var simW: Int
        var simH: Int
        if aspect >= 1.0 {
            simW = MetalRenderer.FLUID_MAX_DIM
            simH = max(128, Int(Float(MetalRenderer.FLUID_MAX_DIM) / aspect))
        } else {
            simH = MetalRenderer.FLUID_MAX_DIM
            simW = max(128, Int(Float(MetalRenderer.FLUID_MAX_DIM) * aspect))
        }
        if fluidSimWidth == simW && fluidSimHeight == simH && fluidTexA.count == 2 {
            return
        }
        fluidSimWidth = simW
        fluidSimHeight = simH
        fluidFrameIndex = 0
        fluidReadIdx = 0

        let desc = MTLTextureDescriptor()
        desc.textureType = .type2D
        desc.pixelFormat = .rgba16Float
        desc.width = simW
        desc.height = simH
        desc.mipmapLevelCount = MetalRenderer.FLUID_MIP_COUNT
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        func makePair() -> [MTLTexture] {
            return [device.makeTexture(descriptor: desc)!, device.makeTexture(descriptor: desc)!]
        }
        fluidTexA = makePair()
        fluidTexB = makePair()
        fluidTexC = makePair()
        fluidTexD = makePair()
    }

    private func runFluidBufferPass(commandBuffer: MTLCommandBuffer,
                                    target: MTLTexture,
                                    pipeline: MTLRenderPipelineState,
                                    textures: [MTLTexture],
                                    uniforms: inout Uniforms) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].level = 0
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rp) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        for (i, tex) in textures.enumerated() {
            encoder.setFragmentTexture(tex, index: i)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(texture: target)
            blit.endEncoding()
        }
    }

    private func drawFluid(in view: MTKView, commandBuffer: MTLCommandBuffer, baseUniforms: Uniforms) {
        ensureFluidResources()
        let simW = fluidSimWidth
        let simH = fluidSimHeight

        var fluidUniforms = baseUniforms
        fluidUniforms.iResolution = SIMD2<Float>(Float(simW), Float(simH))
        fluidUniforms.iFrame = fluidFrameIndex
        // Scale mouse coords from screen pixel space to sim pixel space
        let sx = Float(simW) / max(1.0, Float(screenSize.width))
        let sy = Float(simH) / max(1.0, Float(screenSize.height))
        fluidUniforms.iMouse = SIMD4<Float>(
            baseUniforms.iMouse.x * sx,
            baseUniforms.iMouse.y * sy,
            baseUniforms.iMouse.z * sx,
            baseUniforms.iMouse.w * sy
        )

        let readIdx = fluidReadIdx
        let writeIdx = 1 - readIdx

        runFluidBufferPass(commandBuffer: commandBuffer,
                           target: fluidTexA[writeIdx],
                           pipeline: fluidPipelineA,
                           textures: [fluidTexA[readIdx], fluidTexD[readIdx], fluidTexC[readIdx], fluidTexB[readIdx]],
                           uniforms: &fluidUniforms)
        runFluidBufferPass(commandBuffer: commandBuffer,
                           target: fluidTexB[writeIdx],
                           pipeline: fluidPipelineB,
                           textures: [fluidTexA[writeIdx]],
                           uniforms: &fluidUniforms)
        runFluidBufferPass(commandBuffer: commandBuffer,
                           target: fluidTexC[writeIdx],
                           pipeline: fluidPipelineC,
                           textures: [fluidTexB[writeIdx]],
                           uniforms: &fluidUniforms)
        runFluidBufferPass(commandBuffer: commandBuffer,
                           target: fluidTexD[writeIdx],
                           pipeline: fluidPipelineD,
                           textures: [fluidTexB[writeIdx], fluidTexD[readIdx]],
                           uniforms: &fluidUniforms)

        // Final image pass into the drawable
        if let renderPassDescriptor = view.currentRenderPassDescriptor,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.setRenderPipelineState(pipelineStates[currentShader])
            encoder.setFragmentBytes(&fluidUniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.setFragmentTexture(fluidTexA[writeIdx], index: 0)
            encoder.setFragmentTexture(fluidTexB[writeIdx], index: 1)
            encoder.setFragmentTexture(fluidTexD[writeIdx], index: 2)
            encoder.setFragmentTexture(fluidTexC[writeIdx], index: 3)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        fluidReadIdx = writeIdx
        fluidFrameIndex += 1
    }
}
