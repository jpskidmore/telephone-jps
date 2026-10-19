//
//  CallHistoryTableRowView.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Cocoa

final class CallHistoryTableRowView: NSTableRowView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSeparator(in: dirtyRect)
    }

    override func drawSeparator(in dirtyRect: NSRect) {
        guard !isSelected && !isNextRowSelected else  { return }
        NSColor.gridColor.set()
        fillRectIfNotEmpty(NSIntersectionRect(makeSeparatorRect(bounds: bounds), dirtyRect))
    }
}

private func fillRectIfNotEmpty(_ rect: NSRect) {
    if !NSIsEmptyRect(rect) {
        rect.fill()
    }
}

private func makeSeparatorRect(bounds: NSRect) -> NSRect {
    return NSRect(x: NSMinX(bounds) + 27, y: NSMaxY(bounds) - 1, width: bounds.size.width - 27, height: 1)
}

/// Keeps the origin badge in the existing direction column, without widening the compact dialler.
final class CallHistoryDirectionCellView: NSTableCellView {
    private let accountBadge = CallHistoryAccountBadgeView(frame: .zero)
    private let callStatus = NSView(frame: .zero)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        // NSTableView exposes the children of a view-based cell through its
        // native AX cell. A non-drawing status child retains that hierarchy.
        callStatus.identifier = NSUserInterfaceItemIdentifier("CallHistoryStatus")
        callStatus.translatesAutoresizingMaskIntoConstraints = false
        callStatus.setAccessibilityRole(.staticText)
        addSubview(callStatus)
        accountBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accountBadge)
        NSLayoutConstraint.activate([
            callStatus.centerXAnchor.constraint(equalTo: centerXAnchor),
            callStatus.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            callStatus.widthAnchor.constraint(equalToConstant: 12),
            callStatus.heightAnchor.constraint(equalToConstant: 12),
            accountBadge.centerXAnchor.constraint(equalTo: centerXAnchor),
            accountBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            accountBadge.widthAnchor.constraint(equalToConstant: 18),
            accountBadge.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        // The status child describes direction even when the incoming arrow is
        // hidden. Its visual arrow must not announce the same information again.
        for image in subviews.compactMap({ $0 as? NSImageView }) {
            image.setAccessibilityElement(false)
            image.cell?.setAccessibilityElement(false)
        }
    }

    override var objectValue: Any? {
        didSet {
            let record = objectValue as? PresentationCallHistoryRecord
            accountBadge.name = record?.accountName ?? ""
            accountBadge.glyph = record?.accountBadge ?? ""
            callStatus.isHidden = record == nil
            callStatus.setAccessibilityElement(record != nil)
            callStatus.setAccessibilityLabel(record == nil ? nil : NSLocalizedString("Call status", comment: "Call history status purpose."))
            callStatus.setAccessibilityValue(record?.status.accessibilityValue)
        }
    }
}

final class CallHistoryAccountBadgeView: NSView {
    var name = "" {
        didSet {
            toolTip = name.isEmpty ? nil : name
            setAccessibilityElement(!name.isEmpty)
            setAccessibilityRole(.staticText)
            setAccessibilityLabel(NSLocalizedString("Call account", comment: "Call history origin account badge."))
            setAccessibilityValue(name)
        }
    }
    var glyph = "" { didSet { isHidden = glyph.isEmpty; needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.controlBackgroundColor
        ]
        let text = NSAttributedString(string: glyph, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
