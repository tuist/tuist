import Foundation
import SwiftUI

public struct NooraDropdown<Option: Identifiable & CustomStringConvertible>: View {
    private let options: [Option]
    private let currentOption: Option
    private let selectedOption: (Option) -> Void

    public init(
        options: [Option],
        currentOption: Option,
        selectedOption: @escaping (Option) -> Void
    ) {
        self.options = options
        self.currentOption = currentOption
        self.selectedOption = selectedOption
    }

    public var body: some View {
        Menu {
            ForEach(options, id: \.id) { option in
                Button(option.description) {
                    selectedOption(option)
                }
            }
        } label: {
            HStack(spacing: Noora.Spacing.spacing2) {
                Text(currentOption.description)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                NooraIcon(.chevronDown)
                    .frame(width: 20, height: 20)
                    .foregroundColor(Noora.Colors.buttonSecondaryLabel)
            }
            .padding(Noora.Spacing.spacing3)
            .background(Noora.Colors.surfaceBackgroundTertiary)
            .cornerRadius(Noora.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        Color(light: Noora.Colors.neutralGray24Alpha, dark: Color(hex: 0x696C72, alpha: 0.45)),
                        lineWidth: 0.5
                    )
            )
        }
    }
}

#Preview {
    struct PreviewOption: Identifiable, CustomStringConvertible {
        let id = UUID()
        let name: String

        var description: String {
            return name
        }
    }

    let options = [
        PreviewOption(name: "Option 1"),
        PreviewOption(name: "Option 2"),
        PreviewOption(name: "Option 3"),
    ]

    return NooraDropdown<PreviewOption>(
        options: options,
        currentOption: options[0],
        selectedOption: { option in
            print("Selected: \(option.description)")
        }
    )
    .padding()
}
