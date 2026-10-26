// CandidateWindow.swift
// Glassmorphic floating candidate window for TechuAvro.
// Uses NSVisualEffectView (.dark) + custom drawing.
// Level: .popUpMenu so it floats above all app windows.
// Non-activating: never steals focus from the text field.

import AppKit
import Foundation

final class CandidateWindow {

    // MARK: - UI Components
    private let panel: NSPanel
    private let stackView: NSStackView
    private let effectView: NSVisualEffectView
    private var candidateLabels: [NSTextField] = []

    // MARK: - Constants
    private let windowWidth: CGFloat = 280
    private let rowHeight: CGFloat = 36
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 10
    private let cornerRadius: CGFloat = 14
    private let maxCandidates = 9

    // MARK: - Colors
    private let normalBg = NSColor.clear
    private let highlightBg = NSColor.controlAccentColor
    private let normalFg = NSColor.labelColor
    private let highlightFg = NSColor.white
    private let indexFg = NSColor.secondaryLabelColor

    // MARK: - Init
    init() {
        // Create the panel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 100),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true // key: never interfere with typing

        // Visual effect (vibrant dark blur)
        effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true

        // Stack view for rows
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.alignment = .leading
        stackView.distribution = .fillEqually
        stackView.edgeInsets = NSEdgeInsets(top: verticalPadding, left: 0, bottom: verticalPadding, right: 0)

        effectView.addSubview(stackView)
        panel.contentView = effectView

        // Constraints
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: effectView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
    }

    // MARK: - Show
    func show(candidates: [String], highlightedIndex: Int, near caretRect: NSRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuild(candidates: candidates, highlighted: highlightedIndex)
            self.position(near: caretRect, count: candidates.count)
            if !self.panel.isVisible {
                self.panel.orderFront(nil)
            }
        }
    }

    // MARK: - Highlight
    func highlight(index: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for (i, label) in self.candidateLabels.enumerated() {
                let isHighlighted = i == index
                label.superview?.layer?.backgroundColor = isHighlighted
                    ? self.highlightBg.cgColor : NSColor.clear.cgColor
                label.textColor = isHighlighted ? self.highlightFg : self.normalFg
            }
        }
    }

    // MARK: - Hide
    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    // MARK: - Private: Rebuild rows
    private func rebuild(candidates: [String], highlighted: Int) {
        // Remove old rows
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        candidateLabels.removeAll()

        let count = min(candidates.count, maxCandidates)
        for idx in 0..<count {
            let row = makeRow(index: idx + 1, text: candidates[idx], highlighted: idx == highlighted)
            stackView.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: windowWidth).isActive = true
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }
    }

    private func makeRow(index: Int, text: String, highlighted: Bool) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = highlighted ? highlightBg.cgColor : NSColor.clear.cgColor

        // Index badge
        let indexLabel = NSTextField(labelWithString: "\(index)")
        indexLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        indexLabel.textColor = highlighted ? highlightFg.withAlphaComponent(0.7) : indexFg
        indexLabel.alignment = .center

        // Candidate text
        let textLabel = NSTextField(labelWithString: text)
        textLabel.font = NSFont.systemFont(ofSize: 18, weight: highlighted ? .semibold : .regular)
        textLabel.textColor = highlighted ? highlightFg : normalFg
        textLabel.lineBreakMode = .byTruncatingTail

        candidateLabels.append(textLabel)

        container.addSubview(indexLabel)
        container.addSubview(textLabel)

        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            indexLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            indexLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 20),

            textLabel.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            textLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    // MARK: - Private: Position
    private func position(near caretRect: NSRect, count: Int) {
        let height = CGFloat(count) * rowHeight + verticalPadding * 2
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(
            x: caretRect.minX,
            y: caretRect.minY - height - 4
        )

        // Keep inside screen
        if origin.x + windowWidth > screenFrame.maxX {
            origin.x = screenFrame.maxX - windowWidth - 4
        }
        if origin.y < screenFrame.minY {
            // Show above the caret instead
            origin.y = caretRect.maxY + 4
        }

        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: windowWidth, height: height), display: true)
    }
}
