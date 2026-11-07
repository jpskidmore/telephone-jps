//
//  LocalBuildInformationViewController.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//  Local edition © 2026 jps IT ltd
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Cocoa

/// Information about this locally maintained GPL application, not a product or purchase state.
struct LocalBuildInformation {
    let version: String
    let build: String
    let copyright: String

    init(infoDictionary: [String: Any]) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "Unknown"
        build = infoDictionary["CFBundleVersion"] as? String ?? "Unknown"
        copyright = infoDictionary["NSHumanReadableCopyright"] as? String ??
            "Original Telephone copyrights retained. Local modifications © 2026 jps IT ltd."
    }

    static let sourceURL = URL(string: "https://github.com/jpskidmore/telephone-jps")!
    static let licenceName = "GNU General Public License, version 3 or later"
}

@MainActor
final class LocalBuildInformationViewController: NSViewController {
    private let bundle: Bundle
    private let workspace: NSWorkspace

    init(bundle: Bundle, workspace: NSWorkspace) {
        self.bundle = bundle
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(bundle:workspace:)") }

    override func loadView() {
        let details = LocalBuildInformation(infoDictionary: bundle.infoDictionary ?? [:])
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 324))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = label("jps Telephone", size: 19, weight: .semibold)
        let version = label("Version \(details.version) (build \(details.build))", size: 13)
        let features = label(
            "All features are included in this local edition. Full call history and up to 30 simultaneous calls. No purchases or subscriptions.",
            size: 13
        )
        let origin = label(
            "An unofficial GPL fork maintained by jps IT ltd, separate from the original App Store edition.",
            size: 12
        )
        let notice = label(details.copyright, size: 11)
        let licence = label(LocalBuildInformation.licenceName, size: 12)

        [title, version, features, origin, notice, licence].forEach(stack.addArrangedSubview)
        let links = NSStackView()
        links.orientation = .horizontal
        links.spacing = 10
        links.addArrangedSubview(NSButton(title: "Source", target: self, action: #selector(openSource)))
        links.addArrangedSubview(NSButton(title: "GPL Licence", target: self, action: #selector(openLicence)))
        links.addArrangedSubview(NSButton(title: "Credits", target: self, action: #selector(openCredits)))
        stack.addArrangedSubview(links)

        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor, constant: -20)
        ])
        view = host
    }

    private func label(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    @objc private func openSource() { workspace.open(LocalBuildInformation.sourceURL) }

    @objc private func openLicence() {
        if let file = bundle.url(forResource: "LICENSE", withExtension: nil) {
            workspace.open(file)
        }
    }

    @objc private func openCredits() {
        if let file = bundle.url(forResource: "Credits", withExtension: "rtf") {
            workspace.open(file)
        }
    }
}
