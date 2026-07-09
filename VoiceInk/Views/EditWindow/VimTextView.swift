import AppKit
import SwiftUI

// MARK: - Vim mode

enum VimMode: Equatable {
    case normal
    case insert
    case visual
    case visualLine
    case commandLine   // ":" prompt
    case search        // "/" prompt

    var label: String {
        switch self {
        case .normal: return "NORMAL"
        case .insert: return "INSERT"
        case .visual: return "VISUAL"
        case .visualLine: return "V-LINE"
        case .commandLine: return "COMMAND"
        case .search: return "SEARCH"
        }
    }
}

// MARK: - Motion

private enum Motion: Equatable {
    case left, right, up, down
    case wordFwd, wordBack, wordEnd
    case lineStart, firstNonBlank, lineEnd
    case fileStart, fileEnd
}

// MARK: - Vim engine
//
// A compact Vim emulation layer that drives an NSTextView. It is intentionally
// a useful subset — motions (h j k l w b e 0 ^ $ gg G), operators (d c y with
// motions, plus dd cc yy x D C s), insert entries (i a I A o O), paste (p P),
// visual/visual-line selection, "/" search with n/N, undo/redo, and a small
// ":" command line where :w/:wq/:x commit and :q/:q! cancel.
//
// All indices are UTF-16 offsets to stay consistent with NSTextView.selectedRange.

@MainActor
final class VimEngine {
    private unowned let textView: NSTextView

    private(set) var mode: VimMode = .normal {
        didSet { if oldValue != mode { onModeChange?(mode) } }
    }

    var onModeChange: ((VimMode) -> Void)?
    var onCommandBufferChange: ((String) -> Void)?
    /// Called when the user runs :w / :wq / :x — the panel commits the text.
    var onWrite: (() -> Void)?
    /// Called when the user runs :q / :q! — the panel cancels.
    var onQuit: (() -> Void)?

    // Pending state while parsing a normal-mode command.
    private var pendingCount: Int?
    private var pendingOperator: Character?   // 'd', 'c', 'y'
    private var pendingG = false
    private var visualAnchor = 0
    // The moving end of the visual selection. NSTextView only exposes
    // location+length, so deriving the caret from selectedRange().location
    // would snap back to the selection start after every motion — the head
    // must be tracked separately.
    private var visualHead = 0

    // Registers.
    private var register = ""
    private var registerLinewise = false

    // Command / search line buffer.
    private var commandBuffer = ""
    private var lastSearch = ""

    init(textView: NSTextView) {
        self.textView = textView
    }

    private var ns: NSString { textView.string as NSString }
    private var caret: Int {
        isVisual ? visualHead : textView.selectedRange().location
    }

    // MARK: Entry point

    /// Returns true when the event was consumed by the Vim layer.
    func handle(_ event: NSEvent) -> Bool {
        let isEscape = event.keyCode == 53
        let flags = event.modifierFlags
        let ctrl = flags.contains(.control)
        let key = event.charactersIgnoringModifiers ?? ""

        // Arrow keys: hjkl motions in normal/visual, pass through in insert.
        switch event.keyCode {
        case 123: // ←
            if mode == .insert || mode == .commandLine || mode == .search { return mode == .insert ? false : true }
            resolveMotion(.left); return true
        case 124: // →
            if mode == .insert || mode == .commandLine || mode == .search { return mode == .insert ? false : true }
            resolveMotion(.right); return true
        case 125: // ↓
            if mode == .insert || mode == .commandLine || mode == .search { return mode == .insert ? false : true }
            resolveMotion(.down); return true
        case 126: // ↑
            if mode == .insert || mode == .commandLine || mode == .search { return mode == .insert ? false : true }
            resolveMotion(.up); return true
        default: break
        }

        switch mode {
        case .insert:
            if isEscape {
                enterNormal(clampLeft: true)
                return true
            }
            return false // let NSTextView handle normal typing

        case .commandLine, .search:
            return handlePrompt(event: event, key: key, isEscape: isEscape)

        case .normal, .visual, .visualLine:
            if isEscape {
                resetPending()
                if mode != .normal { enterNormal(clampLeft: false) }
                return true
            }
            if ctrl {
                return handleControl(key: key)
            }
            guard let ch = key.first else { return true }
            return handleNormal(ch)
        }
    }

    // MARK: Control keys

    private func handleControl(key: String) -> Bool {
        switch key {
        case "r":
            textView.undoManager?.redo()
            return true
        case "u", "d": // half-page scroll — approximate with several lines
            let motion: Motion = key == "u" ? .up : .down
            for _ in 0..<10 { moveCaret(to: motionTarget(motion, from: caret, count: 1)) }
            if isVisual { extendVisualSelection() }
            return true
        default:
            return true
        }
    }

    // MARK: Normal / visual parsing

    private func handleNormal(_ ch: Character) -> Bool {
        // gg second stroke
        if pendingG {
            pendingG = false
            if ch == "g" {
                resolveMotion(.fileStart)
            } else {
                resetPending()
            }
            return true
        }

        // numeric count ("0" is a motion unless a count is already building)
        if ch.isNumber, !(ch == "0" && pendingCount == nil) {
            pendingCount = (pendingCount ?? 0) * 10 + Int(String(ch))!
            return true
        }

        switch ch {
        // Motions
        case "h", "\u{7F}": resolveMotion(.left)
        case "l", " ": resolveMotion(.right)
        case "j": resolveMotion(.down)
        case "k": resolveMotion(.up)
        case "w": resolveMotion(.wordFwd)
        case "b": resolveMotion(.wordBack)
        case "e": resolveMotion(.wordEnd)
        case "0": resolveMotion(.lineStart)
        case "^": resolveMotion(.firstNonBlank)
        case "$": resolveMotion(.lineEnd)
        case "G": resolveMotion(.fileEnd)
        case "g": pendingG = true

        // Operators
        case "d", "c", "y":
            if pendingOperator == ch {
                // doubled operator = linewise on current line(s)
                applyLinewiseOperator(ch, lineCount: max(1, pendingCount ?? 1))
                resetPending()
            } else if let op = pendingOperator {
                // e.g. "dy" is nonsense — cancel and restart
                resetPending()
                pendingOperator = ch
                _ = op
            } else {
                pendingOperator = ch
            }

        // Operator shortcuts
        case "x": deleteCharsUnderCaret(count: max(1, pendingCount ?? 1)); resetPending()
        case "D": operatorRange(from: caret, to: lineContentEnd(at: caret), linewise: false, op: "d"); resetPending()
        case "C": operatorRange(from: caret, to: lineContentEnd(at: caret), linewise: false, op: "c"); resetPending()
        case "s": deleteCharsUnderCaret(count: max(1, pendingCount ?? 1)); mode = .insert; resetPendingKeepMode()

        // Inserts
        case "i": enterInsert(at: caret)
        case "a": enterInsert(at: min(caret + 1, lineContentEnd(at: caret)))
        case "I": enterInsert(at: firstNonBlank(at: caret))
        case "A": enterInsert(at: lineContentEnd(at: caret))
        case "o": openLine(below: true)
        case "O": openLine(below: false)

        // Paste
        case "p", "P":
            if isVisual { pasteOverVisual() }
            else { paste(after: ch == "p") }

        // Visual
        case "v":
            if mode == .visual { enterNormal(clampLeft: false) }
            else {
                visualAnchor = caret
                visualHead = visualAnchor
                mode = .visual
                extendVisualSelection()
            }
            resetPendingKeepMode()
        case "V":
            if mode == .visualLine { enterNormal(clampLeft: false) }
            else {
                visualAnchor = caret
                visualHead = visualAnchor
                mode = .visualLine
                extendVisualSelection()
            }
            resetPendingKeepMode()

        // Undo
        case "u": textView.undoManager?.undo(); resetPending()

        // Search
        case "/": mode = .search; commandBuffer = ""; onCommandBufferChange?("/")
        case "n": performSearch(forward: true)
        case "N": performSearch(forward: false)

        // Command line
        case ":": mode = .commandLine; commandBuffer = ""; onCommandBufferChange?(":")

        default:
            break
        }

        // Visual-mode operators applied via a single key (d/y/c already return
        // above through the operator branch when a selection is active).
        return true
    }

    // Handle d/y/c while in visual mode (called from resolveMotion path is not
    // reached; instead intercept here). We special-case by checking mode inside
    // the operator branch of handleNormal is complex, so operate directly:
    private func applyVisualOperator(_ op: Character) {
        let sel = textView.selectedRange()
        guard sel.length > 0 else { enterNormal(clampLeft: false); return }
        let linewise = mode == .visualLine
        yankRange(sel, linewise: linewise)
        if op == "y" {
            enterNormal(clampLeft: false)
            moveCaret(to: sel.location)
            return
        }
        replace(range: sel, with: "")
        if op == "c" {
            mode = .insert
            moveCaret(to: sel.location)
            resetPendingKeepMode()
        } else {
            // Caret lands where the selection began, clamped into the line —
            // the pre-delete visual head is stale by now.
            mode = .normal
            let ls = lineStart(at: sel.location)
            let le = lineContentEnd(at: sel.location)
            moveCaret(to: min(sel.location, max(ls, le - (le > ls ? 1 : 0))))
            resetPendingKeepMode()
        }
    }

    // MARK: Motion resolution

    private func resolveMotion(_ motion: Motion) {
        let count = max(1, pendingCount ?? 1)

        if let op = pendingOperator {
            // j/k under an operator act linewise.
            if motion == .down || motion == .up {
                let lines = motion == .down ? count : -count
                applyLinewiseOperator(op, lineCount: abs(lines) + 1, upward: lines < 0)
            } else {
                // Vim quirk: "cw" on a word acts like "ce" — it must not eat
                // the whitespace after the word.
                let effective: Motion =
                    (op == "c" && motion == .wordFwd && caret < ns.length
                     && classOf(ns.character(at: caret)) != .whitespace)
                    ? .wordEnd : motion
                var target = caret
                for _ in 0..<count { target = motionTarget(effective, from: target, count: 1) }
                let inclusive = (effective == .wordEnd || effective == .lineEnd)
                let end = inclusive ? min(target + 1, ns.length) : target
                operatorRange(from: caret, to: end, linewise: false, op: op)
            }
            resetPending()
            return
        }

        var target = caret
        for _ in 0..<count { target = motionTarget(motion, from: target, count: 1) }
        moveCaret(to: target)

        if mode == .visual || mode == .visualLine { extendVisualSelection() }
        resetPendingKeepMode()
    }

    private func motionTarget(_ motion: Motion, from pos: Int, count: Int) -> Int {
        switch motion {
        case .left:
            let ls = lineStart(at: pos)
            return max(ls, pos - 1)
        case .right:
            let le = lineContentEnd(at: pos)
            // Both normal and visual keep the caret ON the last character.
            let cap = max(le - 1, lineStart(at: pos))
            return min(cap, pos + 1)
        case .down:
            return verticalMove(from: pos, lines: 1)
        case .up:
            return verticalMove(from: pos, lines: -1)
        case .wordFwd:
            return wordForward(from: pos)
        case .wordBack:
            return wordBackward(from: pos)
        case .wordEnd:
            return wordEnd(from: pos)
        case .lineStart:
            return lineStart(at: pos)
        case .firstNonBlank:
            return firstNonBlank(at: pos)
        case .lineEnd:
            let le = lineContentEnd(at: pos)
            return max(le - 1, lineStart(at: pos))
        case .fileStart:
            return firstNonBlank(at: 0)
        case .fileEnd:
            let lastStart = lineStart(at: max(0, ns.length - (ns.length > 0 ? 1 : 0)))
            return firstNonBlank(at: lastStart)
        }
    }

    // MARK: Prompt (":" and "/")

    private func handlePrompt(event: NSEvent, key: String, isEscape: Bool) -> Bool {
        if isEscape {
            commandBuffer = ""
            enterNormal(clampLeft: false)
            onCommandBufferChange?("")
            return true
        }
        if event.keyCode == 36 { // Return
            let wasSearch = mode == .search
            let buffer = commandBuffer
            commandBuffer = ""
            onCommandBufferChange?("")
            if wasSearch {
                lastSearch = buffer
                mode = .normal
                performSearch(forward: true)
            } else {
                runExCommand(buffer)
            }
            return true
        }
        if event.keyCode == 51 { // Delete/Backspace
            if commandBuffer.isEmpty {
                enterNormal(clampLeft: false)
                onCommandBufferChange?("")
            } else {
                commandBuffer.removeLast()
                onCommandBufferChange?((mode == .search ? "/" : ":") + commandBuffer)
            }
            return true
        }
        commandBuffer += key
        onCommandBufferChange?((mode == .search ? "/" : ":") + commandBuffer)
        return true
    }

    private func runExCommand(_ raw: String) {
        let cmd = raw.trimmingCharacters(in: .whitespaces)
        switch cmd {
        case "w", "wq", "x", "wq!", "x!":
            mode = .normal
            onWrite?()
        case "q", "q!":
            mode = .normal
            onQuit?()
        default:
            mode = .normal
        }
    }

    // MARK: Search

    private func performSearch(forward: Bool) {
        guard !lastSearch.isEmpty else { return }
        let opts: NSString.CompareOptions = forward ? [] : [.backwards]
        let start = forward ? min(caret + 1, ns.length) : caret
        let searchRange: NSRange
        if forward {
            searchRange = NSRange(location: start, length: ns.length - start)
        } else {
            searchRange = NSRange(location: 0, length: max(0, caret))
        }
        var found = ns.range(of: lastSearch, options: opts, range: searchRange)
        if found.location == NSNotFound {
            // wrap around
            let whole = NSRange(location: 0, length: ns.length)
            found = ns.range(of: lastSearch, options: opts, range: whole)
        }
        if found.location != NSNotFound {
            moveCaret(to: found.location)
            if isVisual { extendVisualSelection() }
        }
    }

    // MARK: Editing primitives

    private func enterInsert(at index: Int) {
        moveCaret(to: min(max(0, index), ns.length))
        mode = .insert
        resetPendingKeepMode()
    }

    private func enterNormal(clampLeft: Bool) {
        let head = caret // visualHead while visual — read before the mode flips
        mode = .normal
        let ls = lineStart(at: head)
        let le = lineContentEnd(at: head)
        // Normal-mode caret sits ON a character, never past the last one.
        let capped = min(head, max(ls, le - (le > ls ? 1 : 0)))
        if clampLeft {
            moveCaret(to: max(ls, min(head, le) - 1))
        } else {
            moveCaret(to: capped)
        }
        resetPendingKeepMode()
    }

    private func deleteCharsUnderCaret(count: Int) {
        let le = lineContentEnd(at: caret)
        let end = min(caret + count, le)
        guard end > caret else { return }
        let range = NSRange(location: caret, length: end - caret)
        yankRange(range, linewise: false)
        replace(range: range, with: "")
        // keep caret valid
        let newLe = lineContentEnd(at: caret)
        if caret > lineStart(at: caret), caret >= newLe {
            moveCaret(to: max(lineStart(at: caret), newLe - 1))
        }
    }

    private func openLine(below: Bool) {
        if below {
            let insertAt = min(lineFullEnd(at: caret), ns.length)
            replace(range: NSRange(location: insertAt, length: 0), with: "\n")
            enterInsert(at: insertAt + 1)
        } else {
            let ls = lineStart(at: caret)
            replace(range: NSRange(location: ls, length: 0), with: "\n")
            enterInsert(at: ls)
        }
    }

    private func applyLinewiseOperator(_ op: Character, lineCount: Int, upward: Bool = false) {
        var startLine = lineStart(at: caret)
        var endExclusive = lineFullEnd(at: caret)

        if upward {
            for _ in 1..<lineCount {
                if startLine == 0 { break }
                startLine = lineStart(at: startLine - 1)
            }
        } else {
            for _ in 1..<lineCount {
                if endExclusive >= ns.length { break }
                endExclusive = lineFullEnd(at: endExclusive)
            }
        }

        let range = NSRange(location: startLine, length: endExclusive - startLine)
        yankRange(range, linewise: true)

        if op == "y" {
            moveCaret(to: startLine)
            return
        }

        if op == "c" {
            // change keeps the line, clears its content, enters insert
            let content = NSRange(location: startLine, length: max(0, lineContentEnd(at: startLine) - startLine))
            replace(range: content, with: "")
            enterInsert(at: startLine)
            return
        }

        // delete whole line(s); when the range reaches EOF without a trailing
        // newline, consume the preceding newline instead so no empty line is
        // left behind (matches Vim's dd on the last line)
        var delRange = range
        if endExclusive >= ns.length, startLine > 0,
           ns.character(at: startLine - 1) == 10 {
            delRange = NSRange(location: startLine - 1, length: endExclusive - (startLine - 1))
        }
        replace(range: delRange, with: "")
        let newCaret = min(delRange.location, max(0, ns.length - 1))
        moveCaret(to: firstNonBlank(at: newCaret))
    }

    private func operatorRange(from: Int, to: Int, linewise: Bool, op: Character) {
        let lo = min(from, to)
        let hi = max(from, to)
        guard hi > lo else {
            if op == "c" { mode = .insert; resetPendingKeepMode() }
            return
        }
        let range = NSRange(location: lo, length: hi - lo)
        yankRange(range, linewise: linewise)
        if op == "y" {
            moveCaret(to: lo)
            return
        }
        replace(range: range, with: "")
        if op == "c" {
            enterInsert(at: lo)
        } else {
            moveCaret(to: min(lo, max(0, lineContentEnd(at: lo) - 0)))
        }
    }

    private func paste(after: Bool) {
        guard !register.isEmpty else { return }
        if registerLinewise {
            var insertAt = after ? lineFullEnd(at: caret) : lineStart(at: caret)
            var payload = register.hasSuffix("\n") ? register : register + "\n"
            var pastedLineStart = insertAt
            if after, insertAt >= ns.length, ns.length > 0,
               ns.character(at: ns.length - 1) != 10 {
                // Pasting below a last line that has no trailing newline:
                // lead with \n instead of appending one, or the register
                // glues onto the current line.
                payload = "\n" + String(payload.dropLast())
                insertAt = ns.length
                pastedLineStart = insertAt + 1
            }
            replace(range: NSRange(location: insertAt, length: 0), with: payload)
            moveCaret(to: firstNonBlank(at: pastedLineStart))
        } else {
            let insertAt = after ? min(caret + (isEmptyLine(at: caret) ? 0 : 1), lineContentEnd(at: caret) + 1) : caret
            replace(range: NSRange(location: insertAt, length: 0), with: register)
            moveCaret(to: insertAt + (register as NSString).length - 1)
        }
    }

    /// Visual-mode p: replace the selection with the register contents.
    private func pasteOverVisual() {
        let sel = textView.selectedRange()
        guard sel.length > 0, !register.isEmpty else {
            enterNormal(clampLeft: false)
            return
        }
        let payload = registerLinewise
            ? register.trimmingCharacters(in: .newlines)
            : register
        replace(range: sel, with: payload)
        mode = .normal
        moveCaret(to: max(sel.location, sel.location + (payload as NSString).length - 1))
        resetPendingKeepMode()
    }

    private func yankRange(_ range: NSRange, linewise: Bool) {
        guard range.location != NSNotFound, range.length > 0,
              range.location + range.length <= ns.length else { return }
        register = ns.substring(with: range)
        registerLinewise = linewise
    }

    // MARK: Undo-aware replace

    private func replace(range: NSRange, with string: String) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
    }

    private func moveCaret(to index: Int) {
        let clamped = min(max(0, index), ns.length)
        visualHead = clamped
        // In visual modes the selection is owned by extendVisualSelection();
        // collapsing it here would flicker and lose the anchor.
        guard !isVisual else { return }
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
    }

    private func extendVisualSelection() {
        if mode == .visualLine {
            let a = lineStart(at: min(visualAnchor, caret))
            let b = lineFullEnd(at: max(visualAnchor, caret))
            textView.setSelectedRange(NSRange(location: a, length: b - a))
        } else {
            let lo = min(visualAnchor, caret)
            let hi = max(visualAnchor, caret) + 1
            textView.setSelectedRange(NSRange(location: lo, length: min(hi, ns.length) - lo))
        }
    }

    // MARK: Reset helpers

    private func resetPending() {
        pendingCount = nil
        pendingOperator = nil
        pendingG = false
    }

    private func resetPendingKeepMode() {
        pendingCount = nil
        pendingOperator = nil
        pendingG = false
    }

    // MARK: Line / word geometry (UTF-16 offsets)

    private func lineStart(at pos: Int) -> Int {
        let p = clampIndex(pos)
        return ns.lineRange(for: NSRange(location: p, length: 0)).location
    }

    /// End of line excluding the trailing newline.
    private func lineContentEnd(at pos: Int) -> Int {
        let p = clampIndex(pos)
        let r = ns.lineRange(for: NSRange(location: p, length: 0))
        var end = r.location + r.length
        if end > r.location, ns.character(at: end - 1) == 10 { end -= 1 } // \n
        return end
    }

    /// End of line including the trailing newline (exclusive next-line start).
    private func lineFullEnd(at pos: Int) -> Int {
        let p = clampIndex(pos)
        let r = ns.lineRange(for: NSRange(location: p, length: 0))
        return r.location + r.length
    }

    private func firstNonBlank(at pos: Int) -> Int {
        let ls = lineStart(at: pos)
        let le = lineContentEnd(at: pos)
        var i = ls
        while i < le, isWhitespace(ns.character(at: i)) { i += 1 }
        return min(i, max(ls, le - (le > ls ? 1 : 0)))
    }

    private func isEmptyLine(at pos: Int) -> Bool {
        lineContentEnd(at: pos) == lineStart(at: pos)
    }

    private func verticalMove(from pos: Int, lines: Int) -> Int {
        let ls = lineStart(at: pos)
        let col = pos - ls
        if lines > 0 {
            let nextStart = lineFullEnd(at: pos)
            guard nextStart < ns.length else { return pos }
            let nextEnd = lineContentEnd(at: nextStart)
            let cap = max(nextStart, nextEnd - 1)
            return min(nextStart + col, cap)
        } else {
            guard ls > 0 else { return pos }
            let prevStart = lineStart(at: ls - 1)
            let prevEnd = lineContentEnd(at: prevStart)
            let cap = max(prevStart, prevEnd - 1)
            return min(prevStart + col, cap)
        }
    }

    // Word motions using character classes.

    private enum CharClass { case whitespace, word, punct }

    private func classOf(_ c: unichar) -> CharClass {
        if isWhitespace(c) { return .whitespace }
        guard let scalar = UnicodeScalar(c) else { return .word }
        if CharacterSet.alphanumerics.contains(scalar) || c == 95 /* _ */ { return .word }
        return .punct
    }

    private func isWhitespace(_ c: unichar) -> Bool {
        c == 32 || c == 9 || c == 10 || c == 13
    }

    private func wordForward(from pos: Int) -> Int {
        var i = pos
        let n = ns.length
        guard i < n else { return pos }
        let startClass = classOf(ns.character(at: i))
        if startClass != .whitespace {
            while i < n, classOf(ns.character(at: i)) == startClass { i += 1 }
        }
        while i < n, classOf(ns.character(at: i)) == .whitespace { i += 1 }
        return min(i, max(0, n - 1))
    }

    private func wordBackward(from pos: Int) -> Int {
        var i = pos
        guard i > 0 else { return 0 }
        i -= 1
        while i > 0, classOf(ns.character(at: i)) == .whitespace { i -= 1 }
        guard i >= 0 else { return 0 }
        let cls = classOf(ns.character(at: i))
        while i > 0, classOf(ns.character(at: i - 1)) == cls { i -= 1 }
        return i
    }

    private func wordEnd(from pos: Int) -> Int {
        var i = pos
        let n = ns.length
        guard i < n - 1 else { return pos }
        i += 1
        while i < n, classOf(ns.character(at: i)) == .whitespace { i += 1 }
        guard i < n else { return n - 1 }
        let cls = classOf(ns.character(at: i))
        while i < n - 1, classOf(ns.character(at: i + 1)) == cls { i += 1 }
        return i
    }

    private func clampIndex(_ i: Int) -> Int {
        min(max(0, i), max(0, ns.length))
    }

    // Called by the text view when a printable insertion happens in visual mode
    // via d/y/c is handled through handleNormal; visual operators route here.
    func applyOperatorInVisual(_ ch: Character) {
        applyVisualOperator(ch)
    }

    var isVisual: Bool { mode == .visual || mode == .visualLine }
}

// MARK: - Custom NSTextView

final class VimNSTextView: NSTextView {
    var engine: VimEngine?
    var vimEnabled = false
    /// Cmd+Return / Ctrl+Return commit handler (works in every mode).
    var onCommit: (() -> Void)?
    /// Opt+Return save-to-bag handler (works in every mode).
    var onSaveToWorek: (() -> Void)?
    /// Escape-with-no-Vim cancel handler.
    var onCancelPlain: (() -> Void)?

    // Local event monitor — catches ⌘↵/⌃↵ regardless of how AppKit routes
    // the event. Karabiner-generated Enter events may arrive without the
    // expected modifier flags in keyDown/performKeyEquivalent, so we inspect
    // both event.modifierFlags and NSEvent.modifierFlags (live keyboard state).
    private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitor()
        } else {
            removeMonitor()
        }
    }

    private func installMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 36,
                  self.window?.isKeyWindow == true else { return event }
            let ev   = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let live = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let cmd  = ev.contains(.command)  || live.contains(.command)
            let ctrl = ev.contains(.control)  || live.contains(.control)
            let opt  = ev.contains(.option)   || live.contains(.option)
            if (cmd || ctrl) && !opt { self.onCommit?(); return nil }
            if opt && !cmd && !ctrl  { self.onSaveToWorek?(); return nil }
            return event
        }
    }

    private func removeMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    deinit { removeMonitor() }

    // Block cursor in normal mode using the system-supplied rect (correct position).
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn: Bool) {
        guard vimEnabled, let engine, engine.mode == .normal else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: turnedOn)
            return
        }
        // Solid block — always on, no blink, width = one character.
        let w = glyphWidth(at: selectedRange().location)
        NSColor.controlTextColor.withAlphaComponent(0.55).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: w, height: rect.height).fill()
    }

    private func glyphWidth(at loc: Int) -> CGFloat {
        if let lm = layoutManager, let tc = textContainer, loc < string.utf16.count {
            let glyph = lm.glyphIndexForCharacter(at: loc)
            let r = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
            if r.width > 0 { return r.width }
        }
        if let f = font {
            let w = (" " as NSString).size(withAttributes: [.font: f]).width
            if w > 0 { return w }
        }
        return 8
    }

    // Hide/show NSTextInsertionIndicator — the macOS 14+ view-based cursor
    // that renders independently of drawInsertionPoint.
    override func updateInsertionPointStateAndRestartTimer(_ flag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(flag)
        applyIndicatorVisibility()
    }

    private func applyIndicatorVisibility() {
        let hide = vimEnabled && engine?.mode == .normal
        for v in subviews where String(describing: type(of: v)) == "NSTextInsertionIndicator" {
            v.isHidden = hide
        }
    }

    // Trigger redraw on mode change so cursor shape updates immediately.
    func updateCursorDisplay() {
        applyIndicatorVisibility()
        needsDisplay = true
        setNeedsDisplay(visibleRect)
        updateInsertionPointStateAndRestartTimer(true)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘Enter commits — intercepted here because AppKit routes ⌘+key
        // through performKeyEquivalent, not keyDown.
        if event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            onCommit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            // Use NSEvent.modifierFlags (live keyboard state) alongside
            // event.modifierFlags — Karabiner may strip modifiers from
            // synthesised Enter events.
            let liveCmd = NSEvent.modifierFlags.contains(.command)
            let liveCtrl = NSEvent.modifierFlags.contains(.control)
            let evtCmd  = event.modifierFlags.contains(.command)
            let evtCtrl = event.modifierFlags.contains(.control)
            let liveOpt = NSEvent.modifierFlags.contains(.option)
            let evtOpt  = event.modifierFlags.contains(.option)
            // ⌘↵ or ⌃↵ → commit
            if evtCmd || evtCtrl || (liveCmd && !liveOpt) || (liveCtrl && !liveOpt) {
                onCommit?()
                return
            }
            // ⌥↵ → Worek
            if (evtOpt || liveOpt), !evtCmd, !liveCmd, !evtCtrl, !liveCtrl {
                onSaveToWorek?()
                return
            }
        }

        guard vimEnabled, let engine else {
            // Plain editor: Escape cancels the window.
            if event.keyCode == 53 {
                onCancelPlain?()
                return
            }
            super.keyDown(with: event)
            return
        }

        // In visual mode, d/y/c operate on the live selection.
        if engine.isVisual,
           !event.modifierFlags.contains(.command),
           let ch = event.charactersIgnoringModifiers?.first,
           ch == "d" || ch == "y" || ch == "c" || ch == "x" {
            engine.applyOperatorInVisual(ch == "x" ? "d" : ch)
            return
        }

        if engine.handle(event) {
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - SwiftUI wrapper

struct VimTextView: NSViewRepresentable {
    @Binding var text: String
    let vimEnabled: Bool
    let onModeChange: (VimMode) -> Void
    let onCommandBufferChange: (String) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    var onSaveToWorek: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        // Build the TextKit 1 stack explicitly.
        // NSTextView.scrollableTextView() uses TextKit 2 on macOS 12+, which
        // bypasses drawInsertionPoint entirely. Explicit NSLayoutManager forces
        // TextKit 1, restoring the drawInsertionPoint block-cursor override.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: 1_000_000))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = VimNSTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        scrollView.drawsBackground = false

        textView.vimEnabled = vimEnabled
        textView.onCommit = onCommit
        textView.onSaveToWorek = onSaveToWorek
        textView.onCancelPlain = onCancel

        if vimEnabled {
            let engine = VimEngine(textView: textView)
            engine.onModeChange = { [weak textView] newMode in
                onModeChange(newMode)
                textView?.updateCursorDisplay()
            }
            engine.onCommandBufferChange = onCommandBufferChange
            engine.onWrite = onCommit
            engine.onQuit = onCancel
            textView.engine = engine
            onModeChange(.normal)
        }

        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? VimNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: VimTextView
        weak var textView: NSTextView?

        init(_ parent: VimTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
