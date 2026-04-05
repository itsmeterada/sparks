import Foundation
import MetalKit
import simd

struct Uniforms {
    var iResolution: SIMD2<Float>
    var iTime: Float
    var _pad: Float = 0
    var iMouse: SIMD4<Float> = .zero
    var mode: Int32 = 0
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

        let fragmentNames = ["sparks_fragment", "cosmic_fragment", "starship_fragment", "clouds_fragment", "seascape_fragment"]
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
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        let iTime = Float(CFAbsoluteTimeGetCurrent() - startTime)

        var uniforms = Uniforms(
            iResolution: SIMD2<Float>(Float(screenSize.width), Float(screenSize.height)),
            iTime: iTime,
            iMouse: mouseState,
            mode: currentMode
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
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
        default:
            break
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
