import SwiftUI

struct AtlasVoiceInputView: View {
    let phase: AtlasVoiceInput.Phase
    let transcript: String
    let levels: [CGFloat]
    let cancel: () -> Void
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: String {
        switch phase {
        case .requesting: return "Waiting for permission…"
        case .finishing: return "Finishing transcription…"
        case .reviewing: return "Review your transcript"
        default: return "Transcribing on this device"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: cancel) {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Cancel voice input")
                .accessibilityIdentifier("thread-voice-cancel")
                VStack(alignment: .leading, spacing: 4) {
                    Text(status)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(levels.indices, id: \.self) { index in
                            Capsule().fill(.tint)
                                .frame(width: 3, height: 3 + levels[index] * 23)
                        }
                    }
                    .frame(height: 28).frame(maxWidth: .infinity, alignment: .leading)
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: levels)
                    .accessibilityHidden(true)
                }
                Button(action: done) {
                    Group {
                        if phase == .finishing { ProgressView() } else { Image(systemName: "checkmark") }
                    }.frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .modifier(AtlasPrimaryAction())
                .disabled(phase != .recording && phase != .reviewing).accessibilityLabel("Use transcript")
                .accessibilityIdentifier("thread-voice-done")
            }
            if !transcript.isEmpty {
                Text(transcript).font(.callout).lineLimit(6).textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread-voice-recording")
    }
}
