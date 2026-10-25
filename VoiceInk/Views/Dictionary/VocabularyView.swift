import SwiftUI
import SwiftData

enum VocabularySortMode: String {
    case wordAsc = "wordAsc"
    case wordDesc = "wordDesc"
}

struct VocabularyView: View {
    @Query private var vocabularyWords: [VocabularyWord]
    @Environment(\.modelContext) private var modelContext
    @State private var newWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var sortMode: VocabularySortMode = .wordAsc
    @State private var searchText = ""

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "vocabularySortMode"),
           let mode = VocabularySortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedItems: [VocabularyWord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty
            ? Array(vocabularyWords)
            : vocabularyWords.filter { $0.word.localizedCaseInsensitiveContains(query) }

        switch sortMode {
        case .wordAsc:
            return matching.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .wordDesc:
            return matching.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedDescending }
        }
    }

    private var countText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(vocabularyWords.count)"
            : "\(sortedItems.count) / \(vocabularyWords.count)"
    }

    private func toggleSort() {
        sortMode = (sortMode == .wordAsc) ? .wordDesc : .wordAsc
        UserDefaults.standard.set(sortMode.rawValue, forKey: "vocabularySortMode")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("", text: $newWord, prompt: Text("Add word to vocabulary"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addWords() }
                    .labelsHidden()

                AddIconButton(
                    helpText: "Add word",
                    isDisabled: newWord.isEmpty,
                    action: addWords
                )
            }

            Text("Separate several words with commas.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.Text.secondary)

            if !vocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("", text: $searchText, prompt: Text("Search vocabulary"))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .labelsHidden()

                        Button(action: toggleSort) {
                            HStack(spacing: 4) {
                                Text(countText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Image(systemName: sortMode == .wordAsc ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Sort alphabetically")
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(sortedItems) { item in
                            VocabularyWordView(item: item) {
                                removeWord(item)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Vocabulary", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private func addWords() {
        let input = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if let error = DictionaryService.addVocabularyWords(input, existing: Array(vocabularyWords), context: modelContext) {
            alertMessage = error
            showAlert = true
            return
        }
        newWord = ""
    }

    private func removeWord(_ word: VocabularyWord) {
        modelContext.delete(word)

        do {
            try modelContext.save()
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertMessage = String(format: String(localized: "Failed to remove word: %@"), error.localizedDescription)
            showAlert = true
        }
    }
}

struct VocabularyWordView: View {
    let item: VocabularyWord
    let onDelete: () -> Void
    @State private var isDeleteHovered = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(item.word)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(.primary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDeleteHovered ? AppTheme.Status.error : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .help("Remove word")
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDeleteHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.Surface.window.opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.Border.subtle, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
} 
