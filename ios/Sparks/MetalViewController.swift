import UIKit
import MetalKit

class MetalViewController: UIViewController, MTKViewDelegate {

    private var renderer: MetalRenderer!
    private var metalView: MTKView!
    private var halfResButton: UIButton!

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

        // Mode toggle button
        let modeButton = UIButton(type: .system)
        modeButton.setTitle("\u{25CE}", for: .normal) // bullseye symbol
        modeButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .light)
        modeButton.setTitleColor(UIColor.white.withAlphaComponent(0.3), for: .normal)
        modeButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        modeButton.layer.cornerRadius = 18
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.addTarget(self, action: #selector(switchMode), for: .touchUpInside)
        view.addSubview(modeButton)
        NSLayoutConstraint.activate([
            modeButton.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 8),
            modeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            modeButton.widthAnchor.constraint(equalToConstant: 36),
            modeButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        // Half-res toggle button
        halfResButton = UIButton(type: .system)
        halfResButton.setTitle("\u{00BD}", for: .normal) // ½
        halfResButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .light)
        halfResButton.setTitleColor(UIColor.white.withAlphaComponent(0.3), for: .normal)
        halfResButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        halfResButton.layer.cornerRadius = 18
        halfResButton.translatesAutoresizingMaskIntoConstraints = false
        halfResButton.addTarget(self, action: #selector(switchHalfRes), for: .touchUpInside)
        view.addSubview(halfResButton)
        NSLayoutConstraint.activate([
            halfResButton.topAnchor.constraint(equalTo: modeButton.bottomAnchor, constant: 8),
            halfResButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            halfResButton.widthAnchor.constraint(equalToConstant: 36),
            halfResButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc private func switchShader() {
        renderer.toggleShader()
    }

    @objc private func switchMode() {
        renderer.toggleMode()
    }

    @objc private func switchHalfRes() {
        renderer.halfRes = !renderer.halfRes
        let scale = UIScreen.main.scale
        metalView.contentScaleFactor = renderer.halfRes ? scale / 2.0 : scale
        halfResButton.setTitleColor(UIColor.white.withAlphaComponent(renderer.halfRes ? 0.9 : 0.3), for: .normal)
        halfResButton.backgroundColor = UIColor.white.withAlphaComponent(renderer.halfRes ? 0.25 : 0.08)
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
