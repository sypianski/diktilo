import SwiftUI

/// On a downloaded local model's card: where it stands in the model order
/// ("1 in order" for the main model) and a way to make it the main one.
/// The chain is the single source of truth; the card only reads and promotes.
struct ModelOrderControl: View {
    let modelName: String

    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var order = ModelFallbackChain.transcriptionOrder

    private var rank: Int? {
        order.firstIndex(of: modelName).map { $0 + 1 }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let rank {
                orderBadge(rank: rank)
            }

            if rank != 1 {
                Button {
                    useAsMain()
                } label: {
                    Text("Use as Main")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Text.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(AppTheme.Palette.ink, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelFallbackChain.didChange)) { _ in
            order = ModelFallbackChain.transcriptionOrder
        }
    }

    private func orderBadge(rank: Int) -> some View {
        Text("\(rank) in order")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(rank == 1 ? AppTheme.Palette.onAmber : AppTheme.Text.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(rank == 1 ? AppTheme.Palette.amber : AppTheme.Palette.chip))
    }

    private func useAsMain() {
        guard let model = transcriptionModelManager.usableModels.first(where: { $0.name == modelName }) else { return }
        transcriptionModelManager.setDefaultTranscriptionModel(model)
    }
}
