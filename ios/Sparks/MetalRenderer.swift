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

private struct FluidPingPong {
    var textures: [MTLTexture] = []
    var srcIdx: Int = 0
    var dstIdx: Int { 1 - srcIdx }
}

private struct FluidResources {
    var velocity = FluidPingPong()
    var pressure = FluidPingPong()
    var turbulence: MTLTexture?
    var confinement: MTLTexture?
    var pipelineA: MTLRenderPipelineState?
    var pipelineB: MTLRenderPipelineState?
    var pipelineC: MTLRenderPipelineState?
    var pipelineD: MTLRenderPipelineState?
    var pipelineImage: MTLRenderPipelineState?
    var sampler: MTLSamplerState?
    var width: Int = 0
    var height: Int = 0
    var initialized: Bool = false
}

class MetalRenderer {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private let colorPixelFormat: MTLPixelFormat
    private let pipelineStates: [MTLRenderPipelineState?]
    private let starsTexture: MTLTexture?
    private let noiseMedTexture: MTLTexture?
    private let noiseSmallTexture: MTLTexture?
    private let noise3DTexture: MTLTexture?
    private let noiseSmall64Texture: MTLTexture?
    private let samplerState: MTLSamplerState

    private let startTime: CFAbsoluteTime
    private var currentShader: Int = 0
    var currentShaderIndex: Int { currentShader }
    private var currentMode: Int32 = 0
    private var currentFrame: Int32 = 0
    private var mouseState: SIMD4<Float> = .zero
    private var mousePressed: Bool = false
    private var mouseInitialized: Bool = false
    private var virtualMouseX: Float = 0
    private var virtualMouseY: Float = 0
    private var touchStartX: Float = 0
    private var touchStartY: Float = 0
    private var virtualStartX: Float = 0
    private var virtualStartY: Float = 0

    private var fluid = FluidResources()
    private static let fluidShaderIndex: Int = 26

    // Benchmark
    let benchmark = BenchmarkEngine()
    private var preBenchShader: Int = 0
    private var preBenchMode: Int32 = 0

    // Display names, indexed by shader slot (must match pipelineStates length).
    private static let shaderDisplayNames: [String] = [
        "sparks", "cosmic", "starship", "clouds", "seascape", "rainforest", "plasma",
        "grid", "interstellar", "mandelbulb", "cyberspace", "tunnel", "fractal",
        "mandelbulb2", "octgrams", "palette", "primitives", "voxellines", "protean",
        "rocaille", "hudrings", "flighthud", "metalball", "heart", "jellyfish",
        "hypertunnel", "fluid", "furball"
    ]

    var shaderDisplayName: String {
        (0..<Self.shaderDisplayNames.count).contains(currentShader)
            ? Self.shaderDisplayNames[currentShader] : "?"
    }

    var gpuName: String { device.name }
    var screenSizeInt: (Int, Int) { (Int(screenSize.width), Int(screenSize.height)) }

    var screenSize: CGSize = CGSize(width: 1, height: 1)

    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device
        self.startTime = CFAbsoluteTimeGetCurrent()

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = queue

        guard let lib = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library")
        }
        self.library = lib
        self.colorPixelFormat = colorPixelFormat
        let library = lib

        // Index 26 reserved for fluid (multi-pass, separate path) -> nil placeholder.
        let fragmentNames: [String?] = ["sparks_fragment", "cosmic_fragment", "starship_fragment", "clouds_fragment", "seascape_fragment", "rainforest_fragment", "plasma_fragment", "grid_fragment", "interstellar_fragment", "mandelbulb_fragment", "cyberspace_fragment", "tunnel_fragment", "fractal_fragment", "mandelbulb2_fragment", "octgrams_fragment", "palette_fragment", "primitives_fragment", "voxellines_fragment", "protean_fragment", "rocaille_fragment", "hudrings_fragment", "flighthud_fragment", "metalball_fragment", "heart_fragment", "jellyfish_fragment", "hypertunnel_fragment", nil, "furball_fragment"]
        var states: [MTLRenderPipelineState?] = []
        for name in fragmentNames {
            guard let n = name else {
                states.append(nil)
                continue
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "sparks_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: n)
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            do {
                states.append(try device.makeRenderPipelineState(descriptor: descriptor))
            } catch {
                fatalError("Failed to create render pipeline state for \(n): \(error)")
            }
        }
        self.pipelineStates = states

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
        self.noiseSmall64Texture = Self.loadTexture(loader: loader, name: "rgba_noise_small", ext: "png", options: texOpts)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
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

    private var totalShaderCount: Int { pipelineStates.count } // includes fluid placeholder slot

    func toggleShader() {
        currentShader = (currentShader + 1) % totalShaderCount
        mouseState = .zero
        mouseInitialized = false
        currentFrame = 0
    }

    func prevShader() {
        currentShader = (currentShader - 1 + totalShaderCount) % totalShaderCount
        mouseState = .zero
        mouseInitialized = false
        currentFrame = 0
    }

    func toggleMode() {
        currentMode = (currentMode + 1) % 2
    }

    var halfRes: Bool = false

    // MARK: - Benchmark control

    func startBenchmark(mode: BenchmarkMode) {
        preBenchShader = currentShader
        preBenchMode = currentMode
        currentMode = 0
        mouseState = .zero
        mouseInitialized = false
        currentFrame = 0
        benchmark.start(
            mode: mode,
            shaderNames: Self.shaderDisplayNames,
            pipelineAvailable: { [weak self] idx in
                guard let self = self else { return false }
                // Fluid uses a separate pipeline path, placeholder in pipelineStates is nil.
                if idx == Self.fluidShaderIndex { return true }
                return idx >= 0 && idx < self.pipelineStates.count && self.pipelineStates[idx] != nil
            }
        )
        if let idx = benchmark.activeShaderIndex {
            currentShader = idx
        }
    }

    func abortBenchmark() {
        benchmark.abort()
        currentShader = preBenchShader
        currentMode = preBenchMode
        currentFrame = 0
        mouseState = .zero
        mouseInitialized = false
    }

    func finishBenchmarkAndRestore() {
        currentShader = preBenchShader
        currentMode = preBenchMode
        currentFrame = 0
        mouseState = .zero
        mouseInitialized = false
    }

    func makeBenchmarkReport() -> BenchmarkReport {
        return benchmark.makeReport(
            resolution: screenSizeInt,
            halfRes: halfRes,
            vsync: true,
            gpuName: gpuName
        )
    }

    func onTouchDown(x: Float, y: Float) {
        // Fluid: absolute touch position (Shadertoy convention)
        if currentShader == Self.fluidShaderIndex {
            mousePressed = true
            mouseState = SIMD4<Float>(x, y, x, y)
            return
        }
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
        if currentShader == Self.fluidShaderIndex {
            if mousePressed { mouseState.x = x; mouseState.y = y }
            return
        }
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

    private func setupFluidResources(width: Int, height: Int) {
        guard width > 0 && height > 0 else { return }
        if fluid.initialized && fluid.width == width && fluid.height == height { return }
        fluid = FluidResources()
        fluid.width = width
        fluid.height = height

        // Mipmap-capable sampler for fluid
        let samp = MTLSamplerDescriptor()
        samp.minFilter = .linear; samp.magFilter = .linear
        samp.mipFilter = .linear
        samp.sAddressMode = .repeat; samp.tAddressMode = .repeat
        samp.maxAnisotropy = 1
        fluid.sampler = device.makeSamplerState(descriptor: samp)

        // Helper to create RGBA16F target
        func makeTex(mipmapped: Bool) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: width, height: height,
                mipmapped: mipmapped)
            desc.usage = [.shaderRead, .renderTarget]
            desc.storageMode = .private
            return device.makeTexture(descriptor: desc)
        }

        // Ping-pong velocity (mipmapped) and pressure (mipmapped)
        guard let v0 = makeTex(mipmapped: true), let v1 = makeTex(mipmapped: true),
              let p0 = makeTex(mipmapped: true), let p1 = makeTex(mipmapped: true),
              let turb = makeTex(mipmapped: true), let conf = makeTex(mipmapped: false) else {
            return
        }
        fluid.velocity.textures = [v0, v1]
        fluid.pressure.textures = [p0, p1]
        fluid.turbulence = turb
        fluid.confinement = conf

        // Pipelines (4 buffer passes use rgba16Float, image uses swap chain format)
        func makePipeline(frag: String, format: MTLPixelFormat) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "sparks_vertex")
            d.fragmentFunction = library.makeFunction(name: frag)
            d.colorAttachments[0].pixelFormat = format
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        fluid.pipelineA = makePipeline(frag: "fluid_a_fragment", format: .rgba16Float)
        fluid.pipelineB = makePipeline(frag: "fluid_b_fragment", format: .rgba16Float)
        fluid.pipelineC = makePipeline(frag: "fluid_c_fragment", format: .rgba16Float)
        fluid.pipelineD = makePipeline(frag: "fluid_d_fragment", format: .rgba16Float)
        fluid.pipelineImage = makePipeline(frag: "fluid_image_fragment", format: colorPixelFormat)

        fluid.initialized = (fluid.pipelineA != nil && fluid.pipelineB != nil &&
                             fluid.pipelineC != nil && fluid.pipelineD != nil &&
                             fluid.pipelineImage != nil)
        fluid.velocity.srcIdx = 0
        fluid.pressure.srcIdx = 0
        currentFrame = 0
    }

    private func renderFluid(commandBuffer: MTLCommandBuffer,
                             swapchainDescriptor: MTLRenderPassDescriptor,
                             uniforms: inout Uniforms) {
        guard fluid.initialized,
              let sampler = fluid.sampler,
              let turb = fluid.turbulence, let conf = fluid.confinement,
              let pipeA = fluid.pipelineA, let pipeB = fluid.pipelineB,
              let pipeC = fluid.pipelineC, let pipeD = fluid.pipelineD,
              let pipeImg = fluid.pipelineImage else { return }

        let velSrc = fluid.velocity.srcIdx, velDst = fluid.velocity.dstIdx
        let prsSrc = fluid.pressure.srcIdx, prsDst = fluid.pressure.dstIdx
        let velSrcTex = fluid.velocity.textures[velSrc]
        let velDstTex = fluid.velocity.textures[velDst]
        let prsSrcTex = fluid.pressure.textures[prsSrc]
        let prsDstTex = fluid.pressure.textures[prsDst]

        // Helper to render one buffer pass to a target's mip 0
        func runPass(target: MTLTexture, pipeline: MTLRenderPipelineState,
                     channels: [MTLTexture]) {
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = target
            rpd.colorAttachments[0].level = 0
            rpd.colorAttachments[0].loadAction = .dontCare
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            for (i, t) in channels.enumerated() {
                enc.setFragmentTexture(t, index: i)
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        func generateMipmaps(_ tex: MTLTexture) {
            guard tex.mipmapLevelCount > 1, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
            blit.generateMipmaps(for: tex)
            blit.endEncoding()
        }

        // Pass A: velocity = f(velocity.src, pressure.src, confinement, turbulence)
        runPass(target: velDstTex, pipeline: pipeA,
                channels: [velSrcTex, prsSrcTex, conf, turb])
        generateMipmaps(velDstTex)

        // Pass B: turbulence = f(velocity)
        runPass(target: turb, pipeline: pipeB, channels: [velDstTex])
        generateMipmaps(turb)

        // Pass C: confinement = f(turbulence)
        runPass(target: conf, pipeline: pipeC, channels: [turb])

        // Pass D: pressure = f(velocity, pressure.src)
        runPass(target: prsDstTex, pipeline: pipeD, channels: [velDstTex, prsSrcTex])
        generateMipmaps(prsDstTex)

        // Image pass to swapchain
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: swapchainDescriptor) else { return }
        enc.setRenderPipelineState(pipeImg)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentTexture(velDstTex, index: 0)
        enc.setFragmentTexture(prsDstTex, index: 1)
        enc.setFragmentTexture(turb, index: 2)
        enc.setFragmentTexture(conf, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        // Swap ping-pong indices
        fluid.velocity.srcIdx = velDst
        fluid.pressure.srcIdx = prsDst
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        let nowCF = CFAbsoluteTimeGetCurrent()

        // Benchmark state machine: record previous frame's present time, then advance phase.
        if benchmark.isRunning {
            benchmark.recordPresentTime(now: nowCF)
            benchmark.advancePhase(now: nowCF)
            if let idx = benchmark.activeShaderIndex, idx != currentShader {
                currentShader = idx
                mouseState = .zero
                mouseInitialized = false
                currentFrame = 0
            }
        }

        let iTime = Float(nowCF - startTime)

        var uniforms = Uniforms(
            iResolution: SIMD2<Float>(Float(screenSize.width), Float(screenSize.height)),
            iTime: iTime,
            iMouse: mouseState,
            mode: currentMode,
            iFrame: currentFrame
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Fluid multi-pass path
        if currentShader == Self.fluidShaderIndex {
            setupFluidResources(width: Int(screenSize.width), height: Int(screenSize.height))
            renderFluid(commandBuffer: commandBuffer, swapchainDescriptor: renderPassDescriptor, uniforms: &uniforms)
            commandBuffer.present(drawable)
            commandBuffer.commit()
            currentFrame &+= 1
            return
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
              let pipeline = pipelineStates[currentShader] else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
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
        case 27: // furball
            if let tex = noiseSmall64Texture {
                encoder.setFragmentTexture(tex, index: 0)
                encoder.setFragmentTexture(tex, index: 1)
            }
        default:
            break
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        currentFrame &+= 1
    }
}
