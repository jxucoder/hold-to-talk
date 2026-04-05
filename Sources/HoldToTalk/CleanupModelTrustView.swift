import SwiftUI

struct CleanupModelTrustView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About this download")
                .font(.headline)

            Text(CleanupModelInfo.trustSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                trustBadge("On-device")
                trustBadge("Grammar cleanup")
                trustBadge("Gemma 3 1B")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Model:")
                        .foregroundStyle(.secondary)
                    Link("google/gemma-3-1b-it (Q4_K_M)", destination: CleanupModelInfo.huggingFaceURL)
                }

                HStack(spacing: 6) {
                    Text("Runtime:")
                        .foregroundStyle(.secondary)
                    Text("llama.cpp (via SwiftLlama)")
                }

                HStack(spacing: 6) {
                    Text("License:")
                        .foregroundStyle(.secondary)
                    Link("Gemma License", destination: CleanupModelInfo.gemmaURL)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.12))
        )
    }

    private func trustBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
    }
}
