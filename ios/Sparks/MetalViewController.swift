import UIKit
import MetalKit

class MetalViewController: UIViewController, MTKViewDelegate {

    private var renderer: MetalRenderer!
    private var metalView: MTKView!
    private var halfResButton: UIButton!
    private var benchButton: UIButton!
    private var shaderControlButtons: [UIButton] = []
    private var benchOverlay: UILabel!
    private var benchDisplayLink: CADisplayLink?

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

        func makeIconButton(title: String, action: Selector) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .light)
            b.setTitleColor(UIColor.white.withAlphaComponent(0.3), for: .normal)
            b.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            b.layer.cornerRadius = 18
            b.translatesAutoresizingMaskIntoConstraints = false
            b.addTarget(self, action: action, for: .touchUpInside)
            return b
        }

        // Next shader (right arrow, top)
        let nextButton = makeIconButton(title: "\u{25B7}", action: #selector(switchShader))
        view.addSubview(nextButton)
        NSLayoutConstraint.activate([
            nextButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            nextButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            nextButton.widthAnchor.constraint(equalToConstant: 36),
            nextButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        // Previous shader (left arrow)
        let prevButton = makeIconButton(title: "\u{25C1}", action: #selector(switchPrevShader))
        view.addSubview(prevButton)
        NSLayoutConstraint.activate([
            prevButton.topAnchor.constraint(equalTo: nextButton.bottomAnchor, constant: 8),
            prevButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            prevButton.widthAnchor.constraint(equalToConstant: 36),
            prevButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        // Mode toggle button
        let modeButton = makeIconButton(title: "\u{25CE}", action: #selector(switchMode))
        view.addSubview(modeButton)
        NSLayoutConstraint.activate([
            modeButton.topAnchor.constraint(equalTo: prevButton.bottomAnchor, constant: 8),
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

        // Benchmark button
        benchButton = UIButton(type: .system)
        benchButton.setTitle("BM", for: .normal)
        benchButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        benchButton.setTitleColor(UIColor.white.withAlphaComponent(0.3), for: .normal)
        benchButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        benchButton.layer.cornerRadius = 18
        benchButton.translatesAutoresizingMaskIntoConstraints = false
        benchButton.addTarget(self, action: #selector(showBenchmarkMenu), for: .touchUpInside)
        view.addSubview(benchButton)
        NSLayoutConstraint.activate([
            benchButton.topAnchor.constraint(equalTo: halfResButton.bottomAnchor, constant: 8),
            benchButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            benchButton.widthAnchor.constraint(equalToConstant: 36),
            benchButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        shaderControlButtons = [nextButton, prevButton, modeButton, halfResButton]

        // Benchmark progress overlay (hidden until bench runs)
        benchOverlay = UILabel()
        benchOverlay.translatesAutoresizingMaskIntoConstraints = false
        benchOverlay.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        benchOverlay.textColor = .white
        benchOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        benchOverlay.textAlignment = .center
        benchOverlay.layer.cornerRadius = 10
        benchOverlay.layer.masksToBounds = true
        benchOverlay.isHidden = true
        view.addSubview(benchOverlay)
        NSLayoutConstraint.activate([
            benchOverlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            benchOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            benchOverlay.heightAnchor.constraint(equalToConstant: 28),
            benchOverlay.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
    }

    @objc private func switchShader() {
        renderer.toggleShader()
    }

    @objc private func switchPrevShader() {
        renderer.prevShader()
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

    // MARK: - Benchmark

    @objc private func showBenchmarkMenu() {
        if renderer.benchmark.isRunning {
            let alert = UIAlertController(title: "Benchmark running",
                                          message: "Stop the current benchmark?",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Stop", style: .destructive) { [weak self] _ in
                self?.abortBenchmark()
            })
            alert.addAction(UIAlertAction(title: "Continue", style: .cancel))
            present(alert, animated: true)
            return
        }
        let sheet = UIAlertController(title: "Benchmark", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Current shader", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.startBenchmark(mode: .singleShader(self.renderer.currentShaderIndex))
        })
        sheet.addAction(UIAlertAction(title: "All shaders", style: .default) { [weak self] _ in
            self?.startBenchmark(mode: .allShaders)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = benchButton
            pop.sourceRect = benchButton.bounds
        }
        present(sheet, animated: true)
    }

    private func startBenchmark(mode: BenchmarkMode) {
        renderer.startBenchmark(mode: mode)
        benchOverlay.isHidden = false
        setShaderControlsEnabled(false)
        benchDisplayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(onBenchTick))
        link.add(to: .main, forMode: .common)
        benchDisplayLink = link
        onBenchTick()
    }

    private func abortBenchmark() {
        renderer.abortBenchmark()
        stopBenchmarkUI()
    }

    private func stopBenchmarkUI() {
        benchDisplayLink?.invalidate()
        benchDisplayLink = nil
        benchOverlay.isHidden = true
        setShaderControlsEnabled(true)
    }

    private func setShaderControlsEnabled(_ enabled: Bool) {
        for b in shaderControlButtons {
            b.isEnabled = enabled
            b.alpha = enabled ? 1.0 : 0.3
        }
    }

    @objc private func onBenchTick() {
        benchOverlay.text = "  " + renderer.benchmark.statusText + "  "
        if renderer.benchmark.isDone {
            let report = renderer.makeBenchmarkReport()
            renderer.finishBenchmarkAndRestore()
            stopBenchmarkUI()
            showBenchmarkResult(report)
        }
    }

    private func showBenchmarkResult(_ report: BenchmarkReport) {
        var body = String(format: "Overall score: %.0f\n\n", report.overallScore)
        body += String(format: "Thermal: %@ → %@\n", report.thermalStateStart, report.thermalStateEnd)
        body += String(format: "Resolution: %dx%d  vsync:%@  halfRes:%@\n\n",
                       report.config.resolution[0], report.config.resolution[1],
                       report.config.vsync ? "on" : "off",
                       report.config.halfRes ? "on" : "off")
        for s in report.shaders {
            if s.skipped {
                body += String(format: "• %@: skipped\n", s.name)
            } else {
                body += String(format: "• %@: %.1f fps (1%% low %.1f, p99 %.1fms)\n",
                               s.name, s.avgFps, s.onePctLowFps, s.p99FrameMs)
            }
        }
        let alert = UIAlertController(title: "Benchmark complete", message: body, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Save JSON", style: .default) { [weak self] _ in
            self?.saveBenchmarkReport(report)
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    private func saveBenchmarkReport(_ report: BenchmarkReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let name = "benchmark-\(fmt.string(from: Date())).json"
        let url = docs.appendingPathComponent(name)
        do {
            try data.write(to: url)
            let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = ac.popoverPresentationController {
                pop.sourceView = benchButton
                pop.sourceRect = benchButton.bounds
            }
            present(ac, animated: true)
        } catch {
            let a = UIAlertController(title: "Save failed", message: error.localizedDescription, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
        }
    }

    // MARK: - Touch → iMouse

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if renderer.benchmark.isRunning { return }
        guard let touch = touches.first else { return }
        let pt = touch.location(in: metalView)
        let scale = metalView.contentScaleFactor
        let x = Float(pt.x * scale)
        let y = Float((metalView.bounds.height - pt.y) * scale) // flip Y for Shadertoy
        renderer.onTouchDown(x: x, y: y)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if renderer.benchmark.isRunning { return }
        guard let touch = touches.first else { return }
        let pt = touch.location(in: metalView)
        let scale = metalView.contentScaleFactor
        let x = Float(pt.x * scale)
        let y = Float((metalView.bounds.height - pt.y) * scale)
        renderer.onTouchMove(x: x, y: y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if renderer.benchmark.isRunning { return }
        renderer.onTouchUp()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if renderer.benchmark.isRunning { return }
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
