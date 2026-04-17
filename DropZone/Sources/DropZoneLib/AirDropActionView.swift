import SwiftUI

@MainActor
public struct AirDropActionView: View {
    public let isEnabled: Bool
    public let onTap: () -> Void

    public init(isEnabled: Bool, onTap: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.forward")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                Text("AirDrop")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 86)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.34, blue: 0.36).opacity(isEnabled ? 0.90 : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}
