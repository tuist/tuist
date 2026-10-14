import AVFoundation
import MetalKit
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MediaViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

final class MediaViewController: UIViewController, MTKViewDelegate {
    private let status = UILabel()
    private let ready = UIButton(type: .system)
    private var lines: [String] = []
    private let engine = AVAudioEngine()
    private let session = AVCaptureSession()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var commandQueue: MTLCommandQueue?

    private var mode: String {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-mode"), index + 1 < args.count { return args[index + 1] }
        return "baseline"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        status.numberOfLines = 0
        status.accessibilityIdentifier = "status"
        status.font = .systemFont(ofSize: 10)
        status.frame = CGRect(x: 10, y: 60, width: view.bounds.width - 20, height: 300)
        view.addSubview(status)
        ready.setTitle("Ready", for: .normal)
        ready.frame = CGRect(x: 10, y: view.bounds.height - 120, width: 200, height: 44)
        ready.isHidden = true
        view.addSubview(ready)
        log("mode=\(mode)")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let modes = mode == "all" ? ["capture", "mic", "video", "metal"] : [mode]
        for mode in modes {
            let start = Date()
            switch mode {
            case "mic": startMicrophone()
            case "mic-bg":
                DispatchQueue.global().async { self.startMicrophone() }
            case "capture": startCapture(onMain: true)
            case "capture-bg": startCapture(onMain: false)
            case "video": startVideo()
            case "metal": startMetal()
            default: break
            }
            log("\(mode) setup returned on main after \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        }
        ready.isHidden = false
        log("ready shown")
    }

    private func log(_ line: String) {
        let stamped = "\(String(format: "%.2f", ProcessInfo.processInfo.systemUptime)) \(line)"
        NSLog("MediaRepro: %@", stamped)
        DispatchQueue.main.async {
            self.lines.append(stamped)
            self.status.text = self.lines.joined(separator: "\n")
        }
    }

    private func startMicrophone() {
        log("mic: recordPermission=\(AVAudioApplication.shared.recordPermission.rawValue)")
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            log("mic: category set")
            try audio.setActive(true)
            log("mic: session active, inputAvailable=\(audio.isInputAvailable)")
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            log("mic: input format \(format)")
            var buffers = 0
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { _, _ in
                buffers += 1
                if buffers == 1 { self.log("mic: first input buffer") }
            }
            try engine.start()
            log("mic: engine started")
        } catch {
            log("mic: error \(error)")
        }
    }

    private func startCapture(onMain: Bool) {
        let video = AVCaptureDevice.default(for: .video)
        let audio = AVCaptureDevice.default(for: .audio)
        log("capture: video=\(video?.localizedName ?? "nil") audio=\(audio?.localizedName ?? "nil")")
        session.beginConfiguration()
        for device in [video, audio].compactMap({ $0 }) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input) }
            } catch {
                log("capture: input error \(error)")
            }
        }
        session.commitConfiguration()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = CGRect(x: 10, y: 380, width: 150, height: 150)
        view.layer.addSublayer(preview)
        let run = {
            self.session.startRunning()
            self.log("capture: running=\(self.session.isRunning)")
        }
        if onMain { run() } else { DispatchQueue.global().async(execute: run) }
    }

    private func startVideo() {
        guard let url = Bundle.main.url(forResource: "loop", withExtension: "mp4") else {
            log("video: missing loop.mp4")
            return
        }
        let player = AVQueuePlayer()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        let layer = AVPlayerLayer(player: player)
        layer.frame = CGRect(x: 170, y: 380, width: 150, height: 150)
        view.layer.addSublayer(layer)
        player.play()
        self.player = player
        log("video: playing")
    }

    private func startMetal() {
        let device = MTLCreateSystemDefaultDevice()
        log("metal: device=\(device?.name ?? "nil")")
        guard let device else { return }
        commandQueue = device.makeCommandQueue()
        let metal = MTKView(frame: CGRect(x: 10, y: 540, width: 150, height: 100), device: device)
        metal.delegate = self
        metal.preferredFramesPerSecond = 60
        view.addSubview(metal)
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = commandQueue?.makeCommandBuffer() else { return }
        let t = ProcessInfo.processInfo.systemUptime
        pass.colorAttachments[0].clearColor = MTLClearColor(red: (sin(t) + 1) / 2, green: 0.3, blue: 0.6, alpha: 1)
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
