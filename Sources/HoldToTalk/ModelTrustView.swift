import SwiftUI

struct ModelTrustView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About this download")
                .font(.headline)

            Text(SpeechModelInfo.trustSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                trustBadge("On-device")
                trustBadge(SpeechModelInfo.languageSummary)
                trustBadge("Parakeet TDT")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Model:")
                        .foregroundStyle(.secondary)
                    Link("nvidia/parakeet-tdt-0.6b-v2", destination: SpeechModelInfo.parakeetURL)
                }

                HStack(spacing: 6) {
                    Text("Runtime:")
                        .foregroundStyle(.secondary)
                    Link("sherpa-onnx on GitHub", destination: SpeechModelInfo.sherpaOnnxURL)
                }

                HStack(spacing: 6) {
                    Text("License:")
                        .foregroundStyle(.secondary)
                    Text("Apache 2.0")
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator)
        )
    }

    private func trustBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}
