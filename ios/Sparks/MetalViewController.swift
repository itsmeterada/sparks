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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        metalView.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        renderer.toggleShader()
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
}
