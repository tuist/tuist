import Foundation
import SwiftUI

public struct NooraDropdown<Option: Identifiable & CustomStringConvertible>: View {
    private let options: [Option]
    private let currentOption: Option
    private let cornerRadius: CGFloat
    private let selectedOption: (Option) -> Void

    public init(
        options: [Option],
        currentOption: Option,
        cornerRadius: CGFloat = Noora.CornerRadius.medium,
        selectedOption: @escaping (Option) -> Void
    ) {
        self.options = options
        self.currentOption = currentOption
        self.cornerRadius = cornerRadius
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
            NooraDropdownLabel(text: currentOption.description, cornerRadius: cornerRadius)
        }
    }
}

public struct NooraDropdownLabel: View {
    private let text: String
    private let cornerRadius: CGFloat

    public init(text: String, cornerRadius: CGFloat = Noora.CornerRadius.medium) {
        self.text = text
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        HStack(spacing: Noora.Spacing.spacing2) {
            Text(text)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            NooraIcon(.chevronDown)
                .frame(width: 20, height: 20)
                .foregroundColor(Noora.Colors.buttonSecondaryLabel)
        }
        .padding(Noora.Spacing.spacing3)
        .frame(minHeight: 44)
        .background(Noora.Colors.surfaceBackgroundTertiary)
        .cornerRadius(cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    Color(light: Noora.Colors.neutralGray24Alpha, dark: Color(hex: 0x696C72, alpha: 0.45)),
                    lineWidth: 0.5
                )
        )
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
