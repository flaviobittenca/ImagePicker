import Foundation
import AVFoundation
import PhotosUI

protocol CameraManDelegate: class {
  func cameraManNotAvailable(_ cameraMan: CameraMan)
  func cameraManDidStart(_ cameraMan: CameraMan)
  func cameraMan(_ cameraMan: CameraMan, didChangeInput input: AVCaptureDeviceInput)
  func videoFinished(withFileURL fileURL: URL)
}

class CameraMan : NSObject, AVCaptureFileOutputRecordingDelegate {
  weak var delegate: CameraManDelegate?

  let session = AVCaptureSession()
  let queue = DispatchQueue(label: "no.hyper.ImagePicker.Camera.SessionQueue")

  var backCameraInput: AVCaptureDeviceInput?
  var frontCameraInput: AVCaptureDeviceInput?
  var videoOutput: AVCaptureMovieFileOutput?
  
  fileprivate var isRecording = false
  
  deinit {
    stop()
  }

  // MARK: - Setup

  func setup() {
    checkPermission()
  }

  func setupDevices() {
    // Input
    AVCaptureDevice
    .devices().flatMap {
      return $0 as? AVCaptureDevice
    }.filter {
      return $0.hasMediaType(AVMediaTypeVideo)
    }.forEach {
      switch $0.position {
      case .front:
        self.frontCameraInput = try? AVCaptureDeviceInput(device: $0)
      case .back:
        self.backCameraInput = try? AVCaptureDeviceInput(device: $0)
      default:
        break
      }
    }

    // Output
    videoOutput = AVCaptureMovieFileOutput()
    //    let totalSeconds = 60.0 //Total Seconds of capture time
    //    let timeScale: Int32 = 30 //FPS
    //
    //    let maxDuration = CMTimeMakeWithSeconds(totalSeconds, timeScale)
    
    videoOutput?.maxRecordedDuration = kCMTimeInvalid
    videoOutput?.minFreeDiskSpaceLimit = 1024 * 1024 //SET MIN FREE SPACE IN BYTES FOR RECORDING TO CONTINUE ON A VOLUME
  }

  func addInput(_ input: AVCaptureDeviceInput) {
    configurePreset(input)

    if session.canAddInput(input) {
      session.addInput(input)

      DispatchQueue.main.async {
        self.delegate?.cameraMan(self, didChangeInput: input)
      }
    }
  }

  // MARK: - Permission

  func checkPermission() {
    let status = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)

    switch status {
    case .authorized:
      start()
    case .notDetermined:
      requestPermission()
    default:
      delegate?.cameraManNotAvailable(self)
    }
  }

  func requestPermission() {
    AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) { granted in
      DispatchQueue.main.async {
        if granted {
          self.start()
        } else {
          self.delegate?.cameraManNotAvailable(self)
        }
      }
    }
  }

  // MARK: - Session

  var currentInput: AVCaptureDeviceInput? {
    return session.inputs.first as? AVCaptureDeviceInput
  }

  fileprivate func start() {
    // Devices
    setupDevices()

    guard let input = backCameraInput, let output = videoOutput else { return }

    addInput(input)

    if session.canAddOutput(output) {
      session.addOutput(output)
    }

    queue.async {
      self.session.startRunning()

      DispatchQueue.main.async {
        self.delegate?.cameraManDidStart(self)
      }
    }
  }

  func stop() {
    self.session.stopRunning()
  }

  func switchCamera(_ completion: (() -> Void)? = nil) {
    guard let currentInput = currentInput
      else {
        completion?()
        return
    }

    queue.async {
      guard let input = (currentInput == self.backCameraInput) ? self.frontCameraInput : self.backCameraInput
        else {
          DispatchQueue.main.async {
            completion?()
          }
          return
      }

      self.configure {
        self.session.removeInput(currentInput)
        self.addInput(input)
      }

      DispatchQueue.main.async {
        completion?()
      }
    }
  }

  func takePhoto(_ previewLayer: AVCaptureVideoPreviewLayer, location: CLLocation?, completion: (() -> Void)? = nil) {
    
    self.toggleRecording()
    completion?()
    return
  }
  
  func stopCamera() {
    if self.isRecording {
      self.toggleRecording()
    }
    session.stopRunning()
  }
  
  fileprivate func toggleRecording() {
    guard let videoOutput = videoOutput else {
      return
    }
    
    self.isRecording = !self.isRecording
    
    if self.isRecording {
      let outputPath = "\(NSTemporaryDirectory())output.mov"
      let outputURL = URL(fileURLWithPath: outputPath)
      
      let fileManager = FileManager.default
      if fileManager.fileExists(atPath: outputPath) {
        do {
          try fileManager.removeItem(atPath: outputPath)
        } catch {
          print("error removing item at path: \(outputPath)")
          self.isRecording = false
          return
        }
      }
      videoOutput.startRecording(toOutputFileURL: outputURL, recordingDelegate: self)
    } else {
      videoOutput.stopRecording()
    }
    return
  }

  func flash(_ mode: AVCaptureFlashMode) {
    guard let device = currentInput?.device , device.isFlashModeSupported(mode) else { return }

    queue.async {
      self.lock {
        device.flashMode = mode
      }
    }
  }

  func focus(_ point: CGPoint) {
    guard let device = currentInput?.device , device.isFocusModeSupported(AVCaptureFocusMode.locked) else { return }

    queue.async {
      self.lock {
        device.focusPointOfInterest = point
      }
    }
  }

  // MARK: - Lock

  func lock(_ block: () -> Void) {
    if let device = currentInput?.device , (try? device.lockForConfiguration()) != nil {
      block()
      device.unlockForConfiguration()
    }
  }

  // MARK: - Configure
  func configure(_ block: () -> Void) {
    session.beginConfiguration()
    block()
    session.commitConfiguration()
  }

  // MARK: - Preset

  func configurePreset(_ input: AVCaptureDeviceInput) {
    for asset in preferredPresets() {
      if input.device.supportsAVCaptureSessionPreset(asset) && self.session.canSetSessionPreset(asset) {
        self.session.sessionPreset = asset
        return
      }
    }
  }

  func preferredPresets() -> [String] {
    return [
      AVCaptureSessionPresetHigh,
      AVCaptureSessionPresetMedium,
      AVCaptureSessionPresetLow
    ]
  }
  
  
  // MARK: - VideoCapture
  
  func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
    print("started recording to: \(fileURL)")
  }
  
  func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
    print("finished recording to: \(outputFileURL)")
    self.delegate?.videoFinished(withFileURL: outputFileURL)
  }
  
}

