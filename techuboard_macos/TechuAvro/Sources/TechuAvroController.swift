// TechuAvroController.swift
// Subclass of IMKInputController — the heart of TechuAvro.
// Intercepts keystrokes, runs the Avro engine, manages composing buffer,
// shows/hides the candidate window, and commits text to the client app.

import Foundation
import InputMethodKit
import AppKit

final class TechuAvroController: IMKInputController {

    // MARK: - State
    private var composingBuffer: String = ""
    private var candidateWindow: CandidateWindow?
    private var activeCandidateIndex: Int = 0

    // MARK: - Lifecycle
    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        candidateWindow = CandidateWindow()
    }

    // MARK: - Key Handling
    /// Return true if the event was consumed; false to let it pass through.
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown else { return false }

        let keyCode = event.keyCode
        let chars = event.characters ?? ""
        let modifiers = event.modifierFlags

        // Ignore events with Command or Control modifiers
        let ignoredModifiers: NSEvent.ModifierFlags = [.command, .control]
        if !modifiers.intersection(ignoredModifiers).isEmpty {
            return false
        }

        // --- Commit keys ---
        if keyCode == 36 || keyCode == 76 { // Return / Enter
            return commitAndReset(client: sender)
        }
        if keyCode == 49 { // Space
            return handleSpace(client: sender)
        }
        if keyCode == 53 { // Escape
            return cancelComposing(client: sender)
        }

        // --- Candidate navigation ---
        if !composingBuffer.isEmpty {
            if keyCode == 125 || keyCode == 124 { // Down / Right arrow
                moveCandidateDown()
                return true
            }
            if keyCode == 126 || keyCode == 123 { // Up / Left arrow
                moveCandidateUp()
                return true
            }
            // Number key 1–9 selects candidate directly
            if let numChar = chars.first, numChar >= "1" && numChar <= "9",
               modifiers.intersection([.shift, .option]).isEmpty {
                let idx = Int(String(numChar))! - 1
                return selectCandidate(at: idx, client: sender)
            }
        }

        // --- Backspace ---
        if keyCode == 51 { // Delete
            return handleBackspace(client: sender)
        }

        // --- Printable ASCII (a-z A-Z) → Avro input ---
        if let char = chars.first, char.isLetter || char.isNumber || char == "." || char == "," {
            return handleCharacter(String(char), client: sender)
        }

        // Punctuation / other: commit current buffer first, then pass through
        if !composingBuffer.isEmpty {
            _ = commitAndReset(client: sender)
        }
        return false
    }

    // MARK: - Character Input
    private func handleCharacter(_ char: String, client sender: Any!) -> Bool {
        composingBuffer.append(contentsOf: char)
        activeCandidateIndex = 0
        updateComposingText(client: sender)
        updateCandidateWindow(client: sender)
        return true
    }

    // MARK: - Space Key
    private func handleSpace(client sender: Any!) -> Bool {
        if composingBuffer.isEmpty {
            // No buffer — pass space through
            (sender as? IMKTextInput)?.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
            return true
        }
        let word = currentCandidate()
        insert(text: word + " ", client: sender)
        resetState(client: sender)
        return true
    }

    // MARK: - Backspace
    private func handleBackspace(client sender: Any!) -> Bool {
        if composingBuffer.isEmpty { return false }
        composingBuffer.removeLast()
        activeCandidateIndex = 0
        if composingBuffer.isEmpty {
            (sender as? IMKTextInput)?.setMarkedText(
                "", selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0))
            candidateWindow?.hide()
        } else {
            updateComposingText(client: sender)
            updateCandidateWindow(client: sender)
        }
        return true
    }

    // MARK: - Commit
    @discardableResult
    private func commitAndReset(client sender: Any!) -> Bool {
        if composingBuffer.isEmpty { return false }
        let word = currentCandidate()
        insert(text: word, client: sender)
        resetState(client: sender)
        return true
    }

    private func cancelComposing(client sender: Any!) -> Bool {
        if composingBuffer.isEmpty { return false }
        // Clear marked text without inserting anything
        (sender as? IMKTextInput)?.setMarkedText(
            "", selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        resetState(client: sender)
        return true
    }

    // MARK: - Candidate Selection
    private func moveCandidateDown() {
        let candidates = TechuAvroEngine.candidates(for: composingBuffer)
        activeCandidateIndex = min(activeCandidateIndex + 1, candidates.count - 1)
        candidateWindow?.highlight(index: activeCandidateIndex)
    }

    private func moveCandidateUp() {
        activeCandidateIndex = max(activeCandidateIndex - 1, 0)
        candidateWindow?.highlight(index: activeCandidateIndex)
    }

    private func selectCandidate(at index: Int, client sender: Any!) -> Bool {
        let candidates = TechuAvroEngine.candidates(for: composingBuffer)
        guard index < candidates.count else { return false }
        insert(text: candidates[index] + " ", client: sender)
        resetState(client: sender)
        return true
    }

    private func currentCandidate() -> String {
        let candidates = TechuAvroEngine.candidates(for: composingBuffer)
        guard !candidates.isEmpty else { return composingBuffer }
        return candidates[min(activeCandidateIndex, candidates.count - 1)]
    }

    // MARK: - Marked Text (Composing Preview)
    private func updateComposingText(client sender: Any!) {
        let preview = TechuAvroEngine.parse(composingBuffer)
        let attrs = mark(forStyle: kTSMHiliteSelectedConvertedText, at: NSRange(location: 0, length: preview.utf16.count))
        let attributed = NSAttributedString(string: preview, attributes: attrs as? [NSAttributedString.Key: Any] ?? [:])
        (sender as? IMKTextInput)?.setMarkedText(
            attributed,
            selectionRange: NSRange(location: preview.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - Candidate Window
    private func updateCandidateWindow(client sender: Any!) {
        let candidates = TechuAvroEngine.candidates(for: composingBuffer)
        guard !candidates.isEmpty else {
            candidateWindow?.hide()
            return
        }

        // Position window near the cursor
        var caretRect = NSRect.zero
        if let textClient = sender as? IMKTextInput {
            _ = textClient.attributes(forCharacterIndex: 0, lineHeightRectangle: &caretRect)
        }

        candidateWindow?.show(candidates: candidates, highlightedIndex: activeCandidateIndex, near: caretRect)
    }

    // MARK: - Insert committed text
    private func insert(text: String, client sender: Any!) {
        (sender as? IMKTextInput)?.insertText(
            text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - Reset
    private func resetState(client sender: Any!) {
        composingBuffer = ""
        activeCandidateIndex = 0
        candidateWindow?.hide()
    }

    // MARK: - IMKInputController overrides
    override func inputControllerWillClose() {
        candidateWindow?.hide()
        super.inputControllerWillClose()
    }

    override func activateServer(_ sender: Any!) {
        // Called when user switches to this input method — nothing special needed
    }

    override func deactivateServer(_ sender: Any!) {
        // Commit pending buffer when switching away from this input method
        if !composingBuffer.isEmpty {
            commitAndReset(client: sender)
        }
    }
}
