import SwiftUI

/// Exercises the production voice presentation with fixed local samples, not the microphone.
struct AtlasVoiceInputPreview: View {
    @State private var phase = AtlasVoiceInput.Phase.recording
    @State private var draft = "Existing draft."
    private let transcript = "Compare the latest build timings."
    private let levels: [CGFloat] = [0.1, 0.2, 0.4, 0.8, 0.6, 0.3, 0.2, 0.5, 0.9, 0.8, 0.4, 0.2,
                                     0.1, 0.3, 0.7, 0.5, 0.4, 0.2, 0.6, 0.9, 0.5, 0.3, 0.2, 0.1]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Voice input").font(.title2.bold())
                    Text("Review the transcript, then use it in your draft. Nothing is sent automatically.")
                    Text("Preview samples only. The microphone and speech recognizer are not active.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Pip").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack {
                    if phase != .idle {
                        AtlasVoiceInputView(phase: phase, transcript: transcript, levels: levels,
                                            cancel: { phase = .idle }) {
                            draft = AtlasVoiceInput.appending(transcript, to: draft)
                            phase = .idle
                        }
                    }
                    HStack(alignment: .bottom) {
                        TextField("Draft", text: $draft, axis: .vertical)
                            .disabled(phase != .idle)
                            .accessibilityIdentifier("voice-preview-draft")
                        AtlasMicrophoneButton(active: phase == .recording, start: { phase = .recording }, review: { phase = .reviewing })
                            .disabled(phase == .reviewing)
                    }
                    if phase == .idle {
                        Button("Transcribe fixture") { phase = .recording }.frame(minHeight: 44)
                    }
                }.padding().background(.bar)
            }
        }
    }
}
