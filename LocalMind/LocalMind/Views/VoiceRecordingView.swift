import AVFoundation
import Combine
import SwiftUI

// 회의 요약에 사용할 음성을 녹음하고, 녹음 데이터를 상위 화면으로 전달합니다.
struct VoiceRecordingView: View {
    let finish: (URL) -> Void
    let cancel: () -> Void

    @StateObject private var recorder = VoiceRecorderController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 132, height: 132)
                        .overlay(
                            Circle()
                                .stroke(NoteFlowDesign.hairlineSoft, lineWidth: 1)
                        )

                    Image(systemName: recorder.isRecording ? "waveform" : "mic")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(NoteFlowDesign.ink)
                }

                VStack(spacing: 10) {
                    Text(recorder.isRecording ? "녹음 중" : "회의 녹음")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(NoteFlowDesign.ink)

                    Text(recorder.elapsedText)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NoteFlowDesign.mute)
                }

                if let errorMessage = recorder.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        if recorder.isRecording {
                            if let url = recorder.stopRecording() {
                                finish(url)
                            }
                        } else {
                            recorder.startRecording()
                        }
                    } label: {
                        Text(recorder.isRecording ? "녹음 완료" : "녹음 시작")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(NoteFlowDesign.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button("취소") {
                        recorder.cancelRecording()
                        cancel()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.mute)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .background(NoteFlowDesign.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        recorder.cancelRecording()
                        cancel()
                    }
                }
            }
        }
        .tint(NoteFlowDesign.ink)
    }
}

@MainActor
private final class VoiceRecorderController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsedText = "00:00"
    @Published var errorMessage: String?

    // AVAudioRecorder는 delegate 기반 객체라 컨트롤러가 생명주기를 직접 관리합니다.
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startDate: Date?
    private var outputURL: URL?

    func startRecording() {
        errorMessage = nil

        // iOS 마이크 권한 요청은 callback으로 돌아오므로 MainActor Task로 UI 상태를 갱신합니다.
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard granted else {
                    // 권한이 없으면 녹음 시작 대신 화면에 안내 문구를 보여줍니다.
                    self.errorMessage = "마이크 권한이 필요합니다."
                    return
                }

                self.beginRecording()
            }
        }
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        return outputURL
    }

    func cancelRecording() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        outputURL = nil
        isRecording = false
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("noteflow-meeting-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record()

            self.recorder = recorder
            outputURL = url
            startDate = Date()
            elapsedText = "00:00"
            isRecording = true
            startTimer()
        } catch {
            errorMessage = "녹음을 시작하지 못했습니다."
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateElapsedTime()
            }
        }
    }

    private func updateElapsedTime() {
        guard let startDate else {
            elapsedText = "00:00"
            return
        }

        let seconds = max(0, Int(Date().timeIntervalSince(startDate)))
        elapsedText = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
