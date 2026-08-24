/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import AudioToolbox
import AVFoundation
import SwiftUI
import UIKit

struct StationRemoteView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var settings = KdeConnectSettings.shared
    @ObservedObject private var devicesViewModel = connectedDevicesViewModel

    @State private var yesLabel: String = "YES"
    @State private var noLabel: String = "NO"
    @State private var yesEnabled: Bool = true
    @State private var noEnabled: Bool = true
    @State private var pulse: Bool = false
    @State private var showingSettings: Bool = false
    @State private var videoRecorder: SilentVideoRecorder?
    @State private var mqttCoordinator: MqttCoordinator?
    @State private var mqttLog: [String] = []

    @State private var previousHorizontalDragOffset: Float = 0.0
    @State private var previousVerticalDragOffset: Float = 0.0
    @State private var cursorSensitivity: Float = 3.0
    @State private var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .light

    private var targetDeviceId: String? {
        let id = settings.stationTargetDeviceId
        if id != nil
            && ConnectedDevicesViewModel.isDeviceCurrentlyPairedAndConnected(id!)
            && backgroundService._devices[id!]?._pluginsEnableStatus[.mousePadRequest] != nil {
            return id
        }
        return autoSelectDevice()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TwoFingerTapView { _ in
                    sendRightClick()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let dxDrag: Float = Float(gesture.translation.width) - previousHorizontalDragOffset
                            let dyDrag: Float = Float(gesture.translation.height) - previousVerticalDragOffset
                            sendMouseDelta(dx: dxDrag * cursorSensitivity, dy: dyDrag * cursorSensitivity)
                            previousHorizontalDragOffset = Float(gesture.translation.width)
                            previousVerticalDragOffset = Float(gesture.translation.height)
                        }
                        .onEnded { _ in
                            previousHorizontalDragOffset = 0.0
                            previousVerticalDragOffset = 0.0
                        }
                )
                .tapRecognizer(tapSensitivity: 0.2, singleTapAction: sendSingleClick, doubleTapAction: sendDoubleClick)
                .onLongPressGesture {
                    sendSingleHold()
                }

                HStack(spacing: 0) {
                    Button(action: sendYes) {
                        Text(yesLabel)
                            .font(.system(size: 48, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(yesEnabled ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    }
                    .disabled(!yesEnabled)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: pulse)

                    Button(action: sendNo) {
                        Text(noLabel)
                            .font(.system(size: 48, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(noEnabled ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                    }
                    .disabled(!noEnabled)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: pulse)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }

            if settings.stationMqttDebug {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(mqttLog.indices, id: \.self) { index in
                                Text(mqttLog[index])
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 130)
                }
                .allowsHitTesting(false)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { showingSettings = true }, label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .padding(8)
                    })
                }
                .padding(.top, 8)
                Spacer()
            }
        }
        .statusBar(hidden: true)
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingSettings) {
            MainTabView()
        }
        .onAppear {
            let logCallback: (String) -> Void = { entry in
                DispatchQueue.main.async {
                    mqttLog.append(entry)
                    if mqttLog.count > 50 {
                        mqttLog.removeFirst(mqttLog.count - 50)
                    }
                }
            }
            videoRecorder = SilentVideoRecorder(uploadUrl: settings.stationUploadUrl, onLog: logCallback)
            let coordinator = MqttCoordinator(
                brokerUri: settings.stationBrokerUri,
                stationId: settings.stationId,
                onControl: { control in
                    handleControlMessage(control)
                },
                onLog: logCallback
            )
            mqttCoordinator = coordinator
            coordinator.connect()
        }
        .onDisappear {
            mqttCoordinator?.disconnect()
            mqttCoordinator = nil
            videoRecorder?.stop()
            videoRecorder = nil
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                mqttCoordinator?.connect()
            case .background, .inactive:
                mqttCoordinator?.disconnect()
            @unknown default:
                break
            }
        }
    }

    private func sendYes() {
        mqttCoordinator?.publishEvent(.yes)
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendKeyPress("Y")
        remoteInput.sendKeyPress("E")
        remoteInput.sendKeyPress("S")
        remoteInput.sendSpecialKeyPress(.return)
    }

    private func sendNo() {
        mqttCoordinator?.publishEvent(.no)
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendKeyPress("N")
        remoteInput.sendKeyPress("O")
        remoteInput.sendSpecialKeyPress(.return)
    }

    private func sendMouseDelta(dx: Float, dy: Float) {
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendMouseDelta(dx: dx, dy: dy)
    }

    private func sendSingleClick() {
        UIImpactFeedbackGenerator(style: hapticStyle).impactOccurred()
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendSingleClick()
    }

    private func sendDoubleClick() {
        notificationHapticsGenerator.notificationOccurred(.success)
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendDoubleClick()
    }

    private func sendSingleHold() {
        UIImpactFeedbackGenerator(style: hapticStyle).impactOccurred()
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendSingleHold()
    }

    private func sendRightClick() {
        UIImpactFeedbackGenerator(style: hapticStyle).impactOccurred()
        guard let deviceId = targetDeviceId,
              let remoteInput = backgroundService._devices[deviceId]?._plugins[.mousePadRequest] as? RemoteInput
        else { return }
        remoteInput.sendRightClick()
    }

    private func autoSelectDevice() -> String? {
        for (deviceId, _) in devicesViewModel.connectedDevices {
            if backgroundService._devices[deviceId]?._pluginsEnableStatus[.mousePadRequest] != nil {
                settings.stationTargetDeviceId = deviceId
                return deviceId
            }
        }
        return nil
    }

    private func handleControlMessage(_ control: [String: Any]) {
        let action = control["action"] as? String ?? ""

        if action == "reset" {
            DispatchQueue.main.async {
                yesLabel = "YES"
                noLabel = "NO"
                yesEnabled = true
                noEnabled = true
            }
        } else if action == "set_ui" {
            if let yes = control["yes"] as? String, yes.count <= 32 {
                DispatchQueue.main.async { yesLabel = yes }
            }
            // swiftlint:disable:next identifier_name
            if let no = control["no"] as? String, no.count <= 32 {
                DispatchQueue.main.async { noLabel = no }
            }
            if let yesEn = control["yesEnabled"] as? Bool {
                DispatchQueue.main.async { yesEnabled = yesEn }
            }
            if let noEn = control["noEnabled"] as? Bool {
                DispatchQueue.main.async { noEnabled = noEn }
            }
        } else if action == "take_photo" {
            DispatchQueue.main.async {
                videoRecorder?.record(duration: 3.0)
            }
        }

        if let feedback = control["feedback"] as? [String: Any] {
            applyFeedback(feedback)
        }
    }

    private func applyFeedback(_ feedback: [String: Any]) {
        if let vibrateMs = feedback["vibrateMs"] as? Int, vibrateMs > 0 {
            let clamped = min(vibrateMs, 1000)
            DispatchQueue.main.async {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(clamped) / 1000.0) {
                    generator.impactOccurred()
                }
            }
        }

        if feedback["sound"] as? String == "beep" {
            DispatchQueue.main.async {
                AudioServicesPlaySystemSound(1057)
            }
        }

        if feedback["animation"] as? String == "pulse" {
            DispatchQueue.main.async {
                pulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pulse = false
                }
            }
        }
    }
}

final class MqttCoordinator: StationMqttListener {
    private var client: StationMqttClient?
    private let brokerUri: String
    private let stationId: String
    private let onControl: ([String: Any]) -> Void
    private var onLog: ((String) -> Void)?

    init(
        brokerUri: String,
        stationId: String,
        onControl: @escaping ([String: Any]) -> Void,
        onLog: ((String) -> Void)? = nil
    ) {
        self.brokerUri = brokerUri
        self.stationId = stationId
        self.onControl = onControl
        self.onLog = onLog
    }

    func connect() {
        guard client == nil else { return }
        let client = StationMqttClient(brokerUri: brokerUri, stationId: stationId, listener: self)
        self.client = client
        client.connect()
        onLog?("CONNECT \(brokerUri) station=\(stationId)")
    }

    func disconnect() {
        client?.disconnect()
        client = nil
        onLog?("DISCONNECT")
    }

    func publishEvent(_ event: StationEvent) {
        let payload = event.payload()
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            onLog?("→ \(json)")
        }
        client?.publishEvent(event)
    }

    func onControlMessage(_ control: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: control),
           let json = String(data: data, encoding: .utf8) {
            onLog?("← \(json)")
        }
        onControl(control)
    }
}

final class SilentVideoRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "station.video.recorder")
    private var isConfigured = false
    private let uploadUrl: String
    private var onLog: ((String) -> Void)?

    init(uploadUrl: String, onLog: ((String) -> Void)? = nil) {
        self.uploadUrl = uploadUrl
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
            return
        }
        session.addInput(cameraInput)

        if let audio = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        isConfigured = true
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
                self?.stop()
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

    // MARK: - AVCaptureFileOutputRecordingDelegate

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
        onLog?("UPLOAD → \(uploadUrl)")
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
