#if os(macOS)
import SwiftUI
import MacmojiCore

@MainActor
final class PickerModel: ObservableObject {
    @Published var query = ""
    @Published var results: [EmojiSearch.Result] = []
    @Published var selection = 0
    @Published var tone: SkinTone = .none
    var onChoose: (@MainActor (Int) -> Void)?

    var selected: EmojiSearch.Result? { results.indices.contains(selection) ? results[selection] : nil }

    func set(query: String, results: [EmojiSearch.Result], tone: SkinTone) {
        self.query = query
        self.results = results
        self.tone = tone
        selection = 0
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.results.enumerated()), id: \.element.emoji.id) { index, result in
                PickerRow(result: result, tone: model.tone, isSelected: index == model.selection)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onChoose?(index) }
            }
        }
        .padding(6)
        .frame(width: PickerPanel.width, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.25)))
    }
}

private struct PickerRow: View {
    let result: EmojiSearch.Result
    let tone: SkinTone
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(result.emoji.rendered(tone: tone)).font(.system(size: 18))
                .frame(width: 24)
            Text(":\(displayName):")
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: PickerPanel.rowHeight)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }

    /// Show the matched alias when it differs from the primary name, else the primary name.
    private var displayName: String {
        result.tier == .keyword ? result.emoji.primaryName : result.matchedName
    }
}
#endif
