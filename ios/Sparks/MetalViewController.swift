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
        metalView.isMultipleTouchEnabled = false

        renderer = MetalRenderer(device: device, colorPixelFormat: metalView.colorPixelFormat)

        // Shader switch button (top-right, subtle)
        let button = UIButton(type: .system)
        button.setTitle("\u{25C7}", for: .normal) // diamond symbol
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .light)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.3), for: .normal)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(switchShader), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc private func switchShader() {
        renderer.toggleShader()
    }

    // MARK: - Touch → iMouse

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pt = touch.location(in: metalView)
        let scale = metalView.contentScaleFactor
        let x = Float(pt.x * scale)
        let y = Float((metalView.bounds.height - pt.y) * scale) // flip Y for Shadertoy
        renderer.onTouchDown(x: x, y: y)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pt = touch.location(in: metalView)
        let scale = metalView.contentScaleFactor
        let x = Float(pt.x * scale)
        let y = Float((metalView.bounds.height - pt.y) * scale)
        renderer.onTouchMove(x: x, y: y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        renderer.onTouchUp()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        renderer.onTouchUp()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.screenSize = size
    }

    func draw(in view: MTKView) {
        renderer.draw(in: view)
    }
}
