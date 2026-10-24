import SwiftUI

/// Exercises the production voice presentation with fixed local samples, not the microphone.
struct AtlasVoiceInputPreview: View {
    @State private var recording = true
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
                    if recording {
                        AtlasVoiceInputView(phase: .recording, transcript: transcript, levels: levels,
                                            cancel: { recording = false }) {
                            draft = AtlasVoiceInput.appending(transcript, to: draft)
                            recording = false
                        }
                    } else {
                        TextField("Draft", text: $draft, axis: .vertical)
                            .accessibilityIdentifier("voice-preview-draft")
                        Button("Transcribe fixture") { recording = true }.frame(minHeight: 44)
                    }
                }.padding().background(.bar)
            }
        }
    }
}
