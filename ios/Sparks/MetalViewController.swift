import UIKit
import MetalKit

class MetalViewController: UIViewController, MTKViewDelegate {

    private var renderer: MetalRenderer!
    private var metalView: MTKView!

    override func loadView() {
        metalView = MTKView()
        self.view = metalView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        metalView.device = device
        metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        metalView.preferredFramesPerSecond = 60
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.delegate = self

        renderer = MetalRenderer(device: device, colorPixelFormat: metalView.colorPixelFormat)
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.screenSize = size
    }

    func draw(in view: MTKView) {
        renderer.draw(in: view)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouches(touches)
        renderer.isEmitting = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouches(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        renderer.isEmitting = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        renderer.isEmitting = false
    }

    private func handleTouches(_ touches: Set<UITouch>) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: view)
        let bounds = view.bounds

        // Convert screen coordinates to normalized -1..1 range
        let nx = Float((location.x / bounds.width) * 2.0 - 1.0)
        let ny = Float(1.0 - (location.y / bounds.height) * 2.0)

        // Map to world space: screen center = (0,0,0), edges roughly (-4,-3,0) to (4,3,0)
        let aspect = Float(bounds.width / bounds.height)
        let worldX = nx * 4.0 * aspect / (16.0 / 9.0)
        let worldY = ny * 3.0
        let worldZ: Float = 0.0

        renderer.emitterPosition = SIMD3<Float>(worldX, worldY, worldZ)
    }
}
