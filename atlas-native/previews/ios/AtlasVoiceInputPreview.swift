import SwiftUI

/// Exercises the production voice presentation with fixed local samples, not the microphone.
struct AtlasVoiceInputPreview: View {
    @State private var phase: AtlasVoiceInput.Phase
    @State private var draft = "Existing draft."
    private let transcript = "Compare the latest build timings."
    private let levels: [CGFloat] = [0.1, 0.2, 0.4, 0.8, 0.6, 0.3, 0.2, 0.5, 0.9, 0.8, 0.4, 0.2,
                                     0.1, 0.3, 0.7, 0.5, 0.4, 0.2, 0.6, 0.9, 0.5, 0.3, 0.2, 0.1]

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        _phase = State(initialValue: arguments.contains("--text-composer") ? .idle
            : arguments.contains("--review-transcript") ? .reviewing : .recording)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Voice input").font(.title2.bold())
                    Text("Review the transcript, then use it in your draft. Nothing is sent automatically.")
                    Text("Preview samples only. The microphone and speech recognizer are not active.")
                        .font(.caption).foregroundStyle(.secondary)
                    AtlasThreadActivity(message: ProcessInfo.processInfo.arguments.contains("--typing-preview") ? "Typing…" : "Using account lookup…",
                                        typing: ProcessInfo.processInfo.arguments.contains("--typing-preview"))
                }.padding()
            }
            .navigationTitle("Pip").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack {
                    AtlasThreadComposer(draft: $draft, placeholder: "Ask Pip", saving: false,
                                        phase: phase, transcript: transcript, levels: levels,
                                        start: { phase = .recording }, review: { phase = .reviewing }, cancel: { phase = .idle }, accept: {
                        draft = AtlasVoiceInput.appending(transcript, to: draft)
                        phase = .idle
                    }, send: { draft = "" })
                    if phase == .idle {
                        Button("Transcribe fixture") { phase = .recording }.frame(minHeight: 44)
                    }
                }.padding().background(.background)
            }
        }
    }
}
