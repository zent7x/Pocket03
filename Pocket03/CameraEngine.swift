import AVFoundation
import Combine
import UIKit

final class CameraEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var preview: UIImage?
    @Published private(set) var cameraMessage: String?
    @Published private(set) var isDemo = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var torchOn = false
    @Published private(set) var zoom: Double = 1
    @Published var error: String?
    @Published private(set) var recordingSeconds = 0
    var onMovie: ((URL, UIImage, Film) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "studio.pocket03.camera", qos: .userInitiated)
    private let processor = RetroProcessor()
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var film: Film = .daydream
    private var strength = 0.8
    private var latest: CGImage?
    private var finishing = false
    private var writer: SilentVideoWriter?
    private var recordingFilm: Film = .daydream
    private var lastFrame = -Double.infinity
    private var startTime: Double?
    private var demoTimer: DispatchSourceTimer?
    private var configured = false

    func start() {
        #if targetEnvironment(simulator)
        startDemo()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                if allowed { self?.configureAndStart() }
                else { DispatchQueue.main.async { self?.cameraMessage = "Camera access is off. Enable it in Settings, or import a photo." } }
            }
        default: cameraMessage = "Camera access is off. Enable it in Settings, or import a photo."
        }
        #endif
    }
    func stop() {
        queue.async { [self] in
            demoTimer?.cancel(); demoTimer = nil
            if writer != nil { finishRecording() }
            if session.isRunning { session.stopRunning() }
            setTorch(false)
        }
    }
    private func configureAndStart() {
        queue.async { [self] in
            do {
                if !configured {
                    session.beginConfiguration()
                    do {
                        session.sessionPreset = .vga640x480
                        try setInput(position: .back)
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(self, queue: queue)
                        guard session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
                        session.addOutput(output)
                    } catch {
                        session.commitConfiguration()
                        throw error
                    }
                    session.commitConfiguration()
                    orientConnection()
                    configured = true
                }
                session.startRunning()
                DispatchQueue.main.async { self.cameraMessage = nil }
            } catch { fail(error) }
        }
    }
    private func setInput(position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw NSError(domain: "Pocket03", code: 3, userInfo: [NSLocalizedDescriptionKey: "This camera is unavailable. You can still import photos."])
        }
        let replacement = try AVCaptureDeviceInput(device: device)
        let old = input
        if let old { session.removeInput(old) }
        guard session.canAddInput(replacement) else {
            if let old, session.canAddInput(old) { session.addInput(old) }
            throw CocoaError(.featureUnsupported)
        }
        session.addInput(replacement); input = replacement
    }
    private func orientConnection() {
        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = input?.device.position == .front
        }
    }
    func flip() {
        queue.async { [self] in
            guard writer == nil, configured else { return }
            do {
                setTorch(false)
                session.beginConfiguration()
                do { try setInput(position: input?.device.position == .front ? .back : .front) }
                catch { session.commitConfiguration(); throw error }
                session.commitConfiguration()
                orientConnection()
                DispatchQueue.main.async { self.zoom = 1 }
            } catch { fail(error) }
        }
    }
    func toggleTorch() { queue.async { [self] in setTorch(!(input?.device.isTorchActive ?? false)) } }
    private func setTorch(_ enabled: Bool) {
        guard let device = input?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.torchOn = enabled }
        } catch { fail(error) }
    }
    func setZoom(_ value: Double) {
        queue.async { [self] in
            guard let device = input?.device else { return }
            do {
                try device.lockForConfiguration()
                let value = min(CGFloat(value), min(4, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = max(1, value)
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoom = Double(value) }
            } catch { fail(error) }
        }
    }
    func update(film: Film, strength: Double) { queue.async { self.film = film; self.strength = strength } }
    func capture(_ completion: @escaping (UIImage?) -> Void) {
        queue.async { [self] in
            let image = latest.map { UIImage(cgImage: $0) }
            DispatchQueue.main.async { completion(image) }
        }
    }
    func importPhoto(_ image: UIImage, completion: @escaping (UIImage?) -> Void) {
        queue.async { [self] in
            let cg = RetroProcessor.oriented(image).flatMap { processor.process($0, film: film, strength: strength) }
            DispatchQueue.main.async { completion(cg.map { UIImage(cgImage: $0) }) }
        }
    }
    func toggleRecording() {
        queue.async { [self] in
            guard !finishing else { return }
            if writer != nil { finishRecording(); return }
            guard latest != nil else { return }
            do {
                writer = try SilentVideoWriter(); recordingFilm = film; startTime = nil
                DispatchQueue.main.async { self.recordingSeconds = 0; self.isRecording = true }
            } catch { fail(error) }
        }
    }
    private func finishRecording() {
        guard let current = writer, let thumbnail = latest else { return }
        writer = nil
        finishing = true
        let usedFilm = recordingFilm
        DispatchQueue.main.async { self.isRecording = false; self.isFinishing = true }
        current.finish { [weak self] result in
            self?.queue.async { self?.finishing = false }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFinishing = false
                switch result {
                case .success(let url): self.onMovie?(url, UIImage(cgImage: thumbnail), usedFilm)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        render(CIImage(cvPixelBuffer: buffer), time: time)
    }
    private func render(_ image: CIImage, time: CMTime) {
        let seconds = time.seconds
        guard seconds - lastFrame >= 1.0 / 15.0 else { return }
        lastFrame = seconds
        guard let cg = processor.process(image, film: film, strength: strength) else { return }
        latest = cg
        if let writer {
            do {
                try writer.append(cg, at: time)
                if startTime == nil { startTime = seconds }
                let elapsed = Int(seconds - (startTime ?? seconds))
                DispatchQueue.main.async { self.recordingSeconds = elapsed }
            } catch { self.writer = nil; fail(error); DispatchQueue.main.async { self.isRecording = false } }
        }
        let ui = UIImage(cgImage: cg)
        DispatchQueue.main.async { self.preview = ui }
    }
    private func startDemo() {
        isDemo = true
        queue.async { [self] in
            guard demoTimer == nil else { return }
            let scene = RetroProcessor.demoScene()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 15)
            timer.setEventHandler { [weak self] in
                self?.render(scene, time: CMTime(seconds: ProcessInfo.processInfo.systemUptime, preferredTimescale: 600))
            }
            demoTimer = timer; timer.resume()
        }
    }
    private func fail(_ error: Error) { DispatchQueue.main.async { self.error = error.localizedDescription } }
}
