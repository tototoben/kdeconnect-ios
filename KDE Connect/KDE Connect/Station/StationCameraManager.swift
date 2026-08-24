/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import AVFoundation
import Foundation
import Vision

protocol StationCameraListener: AnyObject {
    func onVisitorEntered(side: String, distance: StationDistance)
    func onVisitorDistanceChanged(distance: StationDistance)
    func onVisitorApproached()
    func onVisitorLeft()
}

final class StationCameraManager: NSObject {
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "station.camera")
    private let visionQueue = DispatchQueue(label: "station.vision")

    private var isConfigured = false
    private let uploadUrl: String
    private var onLog: ((String) -> Void)?
    private weak var listener: StationCameraListener?

    // VisitorTracker state machine (ported from Android)
    private static let enterStableMs: Int64 = 500
    private static let leaveStableMs: Int64 = 1000
    private static let distanceStableMs: Int64 = 300
    private static let emaAlpha: Float = 0.32
    private static let minFrameIntervalMs: Int64 = 100

    private var present = false
    private var approached = false
    private var firstSeenAt: Int64 = 0
    private var lastSeenAt: Int64 = 0
    private var distanceCandidateAt: Int64 = 0
    private var distance: StationDistance = .far
    private var candidateDistance: StationDistance = .far
    private var smoothedX: Float = 0
    private var smoothedY: Float = 0
    private var hasSmoothedPosition = false
    private var lastSubmittedAt: Int64 = 0
    private var frameInFlight = false

    init(uploadUrl: String, listener: StationCameraListener, onLog: ((String) -> Void)? = nil) {
        self.uploadUrl = uploadUrl
        self.listener = listener
        self.onLog = onLog
        super.init()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let cameraInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(cameraInput) else {
            session.commitConfiguration()
            onLog?("CAMERA config failed: no front camera")
            return
        }
        session.addInput(cameraInput)

        if let audio = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        isConfigured = true
        session.startRunning()
        onLog?("CAMERA started, tracking active")
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func record(duration: TimeInterval) {
        onLog?("REC start \(duration)s")
        sessionQueue.async { [weak self] in
            guard let self = self, self.isConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            guard let connection = self.movieOutput.connection(with: .video) else { return }
            connection.videoOrientation = .portrait

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("station_\(Int(Date().timeIntervalSince1970)).mov")

            self.movieOutput.startRecording(to: url, recordingDelegate: self)

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.sessionQueue.async {
                    if self?.movieOutput.isRecording == true {
                        self?.movieOutput.stopRecording()
                    }
                }
            }
        }
    }

    // MARK: - VisitorTracker state machine

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func handleFaces(_ faces: [VNFaceObservation], imageWidth: Int, imageHeight: Int) {
        let now = nowMs()
        var primary: VNFaceObservation?
        var largestArea: Float = 0

        for face in faces {
            let w = Float(face.boundingBox.width)
            let h = Float(face.boundingBox.height)
            let area = w * h
            if area > largestArea {
                primary = face
                largestArea = area
            }
        }

        guard let primary = primary else {
            if present && now - lastSeenAt >= Self.leaveStableMs {
                present = false
                approached = false
                hasSmoothedPosition = false
                onLog?("VISITOR left")
                listener?.onVisitorLeft()
            }
            if !present { firstSeenAt = 0 }
            return
        }

        // Vision returns normalized coordinates [0,1] with origin bottom-left.
        // Front camera is mirrored, so mirror X to match what the visitor sees.
        let rawX = 1.0 - Float(primary.boundingBox.origin.x + primary.boundingBox.width / 2)
        let rawY = 1.0 - Float(primary.boundingBox.origin.y + primary.boundingBox.height / 2)
        let clampedX = max(0, min(1, rawX))
        let clampedY = max(0, min(1, rawY))

        if !hasSmoothedPosition {
            smoothedX = clampedX
            smoothedY = clampedY
            hasSmoothedPosition = true
        } else {
            smoothedX += Self.emaAlpha * (clampedX - smoothedX)
            smoothedY += Self.emaAlpha * (clampedY - smoothedY)
        }

        let observedDistance = distanceFor(primary)
        lastSeenAt = now

        if !present {
            if firstSeenAt == 0 { firstSeenAt = now }
            if now - firstSeenAt < Self.enterStableMs { return }
            present = true
            distance = observedDistance
            candidateDistance = observedDistance
            approached = (distance == .near)
            let side = smoothedX < 0.5 ? "left" : "right"
            onLog?("VISITOR entered \(side) \(distance.rawValue)")
            listener?.onVisitorEntered(side: side, distance: distance)
            if approached {
                onLog?("VISITOR approached")
                listener?.onVisitorApproached()
            }
            return
        }

        if observedDistance == distance {
            candidateDistance = distance
            return
        }
        if observedDistance != candidateDistance {
            candidateDistance = observedDistance
            distanceCandidateAt = now
        } else if now - distanceCandidateAt >= Self.distanceStableMs {
            distance = observedDistance
            onLog?("VISITOR distance \(distance.rawValue)")
            listener?.onVisitorDistanceChanged(distance: distance)
            if distance == .near && !approached {
                approached = true
                onLog?("VISITOR approached")
                listener?.onVisitorApproached()
            }
        }
    }

    private func distanceFor(_ face: VNFaceObservation) -> StationDistance {
        let faceFraction = max(Float(face.boundingBox.width), Float(face.boundingBox.height))
        if faceFraction >= 0.45 { return .near }
        if faceFraction >= 0.22 { return .mid }
        return .far
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension StationCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = nowMs()
        if now - lastSubmittedAt < Self.minFrameIntervalMs || frameInFlight {
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastSubmittedAt = now
        frameInFlight = true

        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            defer { self?.frameInFlight = false }
            guard let self = self else { return }
            let faces = request.results as? [VNFaceObservation] ?? []
            self.handleFaces(faces, imageWidth: 320, imageHeight: 240)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            frameInFlight = false
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension StationCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error = error {
            onLog?("REC error: \(error.localizedDescription)")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int) ?? 0
        onLog?("REC done \(outputFileURL.lastPathComponent) \(size) bytes")
        UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
        uploadVideo(at: outputFileURL)
    }

    private func uploadVideo(at fileURL: URL) {
        guard let url = URL(string: uploadUrl) else {
            onLog?("UPLOAD invalid URL: \(uploadUrl)")
            return
        }
        onLog?("UPLOAD -> \(uploadUrl)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "station-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let filename = fileURL.lastPathComponent
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        if let fileData = try? Data(contentsOf: fileURL) {
            body.append(fileData)
        }
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        URLSession.shared.uploadTask(with: request, from: body) { [weak self] _, response, error in
            if let error = error {
                self?.onLog?("UPLOAD error: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                self?.onLog?("UPLOAD \(http.statusCode) \(filename)")
            }
            try? FileManager.default.removeItem(at: fileURL)
        }.resume()
    }
}
