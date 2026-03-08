import SwiftUI

struct ModelTrustView: View {
    let model: WhisperModelInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About this download")
                .font(.headline)

            Text(model.trustSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                trustBadge("On-device")
                trustBadge(model.languageSummary)
                trustBadge(model.familyDisplayName)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Download source:")
                        .foregroundStyle(.secondary)
                    Link("argmaxinc/whisperkit-coreml", destination: WhisperModelInfo.downloadRepositoryURL)
                }

                HStack(spacing: 6) {
                    Text("Selected files:")
                        .foregroundStyle(.secondary)
                    Link(model.repoFolderName, destination: model.downloadURL)
                }

                HStack(spacing: 6) {
                    Text("Model family:")
                        .foregroundStyle(.secondary)
                    Link(model.familyDisplayName, destination: model.familyURL)
                }

                HStack(spacing: 6) {
                    Text("Runtime:")
                        .foregroundStyle(.secondary)
                    Link("WhisperKit on GitHub", destination: WhisperModelInfo.whisperKitURL)
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
