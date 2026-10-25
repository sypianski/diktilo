import SwiftUI
import SwiftData

enum SortMode: String {
    case originalAsc = "originalAsc"
    case originalDesc = "originalDesc"
    case replacementAsc = "replacementAsc"
    case replacementDesc = "replacementDesc"
}

enum SortColumn {
    case original
    case replacement
}

struct WordReplacementView: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @State private var showAlert = false
    @State private var editingID: PersistentIdentifier?
    @State private var alertMessage = ""
    @State private var sortMode: SortMode = .originalAsc
    @State private var originalWord = ""
    @State private var replacementWord = ""
    @State private var searchText = ""

    /// Room for the row's edit and remove icons; the header and add row keep it too.
    static let actionColumnWidth: CGFloat = 44

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "wordReplacementSortMode"),
           let mode = SortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedReplacements: [WordReplacement] {
        switch sortMode {
        case .originalAsc:
            return wordReplacements.sorted { $0.originalText.localizedCaseInsensitiveCompare($1.originalText) == .orderedAscending }
        case .originalDesc:
            return wordReplacements.sorted { $0.originalText.localizedCaseInsensitiveCompare($1.originalText) == .orderedDescending }
        case .replacementAsc:
            return wordReplacements.sorted { $0.replacementText.localizedCaseInsensitiveCompare($1.replacementText) == .orderedAscending }
        case .replacementDesc:
            return wordReplacements.sorted { $0.replacementText.localizedCaseInsensitiveCompare($1.replacementText) == .orderedDescending }
        }
    }

    private var visibleReplacements: [WordReplacement] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sortedReplacements }
        return sortedReplacements.filter {
            $0.originalText.localizedCaseInsensitiveContains(query) ||
                $0.replacementText.localizedCaseInsensitiveContains(query)
        }
    }

    private func toggleSort(for column: SortColumn) {
        switch column {
        case .original:
            sortMode = (sortMode == .originalAsc) ? .originalDesc : .originalAsc
        case .replacement:
            sortMode = (sortMode == .replacementAsc) ? .replacementDesc : .replacementAsc
        }
        UserDefaults.standard.set(sortMode.rawValue, forKey: "wordReplacementSortMode")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !wordReplacements.isEmpty {
                searchRow
            }

            VStack(spacing: 0) {
                columnHeader
                Divider()
                addRow
                Text("Separate several originals with commas, e.g. Dyktylo, Diktylo.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)

                if !wordReplacements.isEmpty {
                    Divider()
                    LazyVStack(spacing: 0) {
                        ForEach(visibleReplacements, id: \.persistentModelID) { replacement in
                            ReplacementRow(
                                replacement: replacement,
                                isEditing: editingID == replacement.persistentModelID,
                                onEdit: { editingID = replacement.persistentModelID },
                                onCancelEdit: { editingID = nil },
                                onSave: { original, text in save(replacement, original: original, text: text) },
                                onDelete: { removeReplacement(replacement) }
                            )

                            if replacement.persistentModelID != visibleReplacements.last?.persistentModelID {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Word Replacement", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $searchText, prompt: Text("Search replacements"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .labelsHidden()

            Text(countText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppTheme.Text.secondary)
        }
    }

    private var countText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(wordReplacements.count)"
            : "\(visibleReplacements.count) / \(wordReplacements.count)"
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            sortButton("Original", column: .original, ascending: .originalAsc, descending: .originalDesc)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            sortButton("Replacement", column: .replacement, ascending: .replacementAsc, descending: .replacementDesc)

            Color.clear.frame(width: Self.actionColumnWidth, height: 1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func sortButton(
        _ title: LocalizedStringKey,
        column: SortColumn,
        ascending: SortMode,
        descending: SortMode
    ) -> some View {
        Button(action: { toggleSort(for: column) }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                if sortMode == ascending || sortMode == descending {
                    Image(systemName: sortMode == ascending ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// The add fields are the first row of the table, in the same columns as the entries.
    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $originalWord, prompt: Text("Dyktylo, Diktylo"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .labelsHidden()

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            TextField("", text: $replacementWord, prompt: Text("Diktilo"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit { addReplacement() }
                .labelsHidden()

            AddIconButton(
                helpText: "Add word replacement",
                isDisabled: originalWord.isEmpty || replacementWord.isEmpty,
                action: addReplacement
            )
            .frame(width: Self.actionColumnWidth, alignment: .center)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func addReplacement() {
        let original = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = DictionaryService.addWordReplacement(original: original, replacement: replacement, existing: Array(wordReplacements), context: modelContext) {
            alertMessage = error
            showAlert = true
            return
        }
        originalWord = ""
        replacementWord = ""
    }

    private func removeReplacement(_ replacement: WordReplacement) {
        modelContext.delete(replacement)

        do {
            try modelContext.save()
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertMessage = String(format: String(localized: "Failed to remove replacement: %@"), error.localizedDescription)
            showAlert = true
        }
    }

    /// Saves an inline edit, with the same duplicate check the sheet had.
    private func save(_ replacement: WordReplacement, original: String, text: String) {
        let newOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = newOriginal
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty, !text.isEmpty else { return }

        for other in wordReplacements where other.persistentModelID != replacement.persistentModelID {
            let existingTokens = other.originalText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }

            if let clash = tokens.first(where: { existingTokens.contains($0.lowercased()) }) {
                alertMessage = String(format: String(localized: "'%@' already exists in word replacements"), clash)
                showAlert = true
                return
            }
        }

        replacement.originalText = newOriginal
        replacement.replacementText = text

        do {
            try modelContext.save()
            editingID = nil
        } catch {
            modelContext.rollback()
            alertMessage = String(format: String(localized: "Failed to save changes: %@"), error.localizedDescription)
            showAlert = true
        }
    }
}

struct ReplacementRow: View {
    let replacement: WordReplacement
    let isEditing: Bool
    let onEdit: () -> Void
    let onCancelEdit: () -> Void
    let onSave: (_ original: String, _ replacement: String) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var draftOriginal = ""
    @State private var draftReplacement = ""

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                row
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draftOriginal = replacement.originalText
                draftReplacement = replacement.replacementText
            }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Text(replacement.originalText)
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            Text(replacement.replacementText)
                .font(.system(size: 13))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Icons appear on hover but keep their room, so text never reflows.
            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Edit replacement")

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove replacement")
            }
            .opacity(isHovered ? 1 : 0)
            .frame(width: WordReplacementView.actionColumnWidth, alignment: .trailing)
        }
        .onTapGesture(perform: onEdit)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $draftOriginal, prompt: Text("Original text (use commas for multiple)"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .labelsHidden()

            TextEditor(text: $draftReplacement)
                .font(.system(size: 13))
                .frame(height: 70)
                .padding(4)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.Border.control, lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancelEdit)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { onSave(draftOriginal, draftReplacement) }
                    .buttonStyle(.amberProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draftOriginal.isEmpty || draftReplacement.isEmpty)
            }
            .controlSize(.small)
        }
        .onAppear {
            draftOriginal = replacement.originalText
            draftReplacement = replacement.replacementText
        }
    }
}
