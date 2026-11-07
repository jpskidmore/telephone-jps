//
//  LocalBuildInformationViewControllerTests.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  This program is free software under GNU GPL version 3 or later.
//

import Cocoa
import XCTest
@testable import Telephone

@MainActor
final class LocalBuildInformationViewControllerTests: XCTestCase {
    func testVersionBuildAndCopyrightUseBundleMetadata() {
        let details = LocalBuildInformation(infoDictionary: [
            "CFBundleShortVersionString": "3.8.2",
            "CFBundleVersion": "169",
            "NSHumanReadableCopyright": "Test copyright"
        ])
        XCTAssertEqual(details.version, "3.8.2")
        XCTAssertEqual(details.build, "169")
        XCTAssertEqual(details.copyright, "Test copyright")
        XCTAssertTrue(LocalBuildInformation.licenceName.contains("version 3"))
        XCTAssertEqual(LocalBuildInformation.sourceURL.host, "github.com")
    }

    func testApplicationBundleIncludesLicenceAndCredits() {
        let bundle = Bundle.main
        XCTAssertNotNil(bundle.url(forResource: "LICENSE", withExtension: nil),
                        "The GPL licence must be included in the built app")
        XCTAssertNotNil(bundle.url(forResource: "Credits", withExtension: "rtf"),
                        "Original author and third-party credits must remain available")
    }

    func testInformationButtonsAreConnectedToTheViewController() {
        let sut = LocalBuildInformationViewController(bundle: .main, workspace: .shared)
        sut.loadViewIfNeeded()
        guard let stack = sut.view.subviews.compactMap({ $0 as? NSStackView }).first else {
            return XCTFail("Missing information stack")
        }
        let buttons = stack.arrangedSubviews.compactMap { $0 as? NSStackView }
            .flatMap { $0.arrangedSubviews.compactMap { $0 as? NSButton } }
        XCTAssertEqual(buttons.count, 3)
        for button in buttons {
            XCTAssertTrue(button.target === sut, "Information button has an unexpected target")
            XCTAssertNotNil(button.action, "Information button is not wired")
        }
    }

    func testInformationScreenHasNoStoreOrPaymentActions() {
        let sut = LocalBuildInformationViewController(bundle: .main, workspace: .shared)
        sut.loadViewIfNeeded()
        guard let stack = sut.view.subviews.compactMap({ $0 as? NSStackView }).first else {
            return XCTFail("Missing information stack")
        }
        let buttons = stack.arrangedSubviews.compactMap { $0 as? NSStackView }
            .flatMap { $0.arrangedSubviews.compactMap { $0 as? NSButton }.map(\.title) }
        XCTAssertEqual(buttons, ["Source", "GPL Licence", "Credits"])
        XCTAssertFalse(buttons.contains { $0.localizedCaseInsensitiveContains("Purchase") })
        XCTAssertFalse(buttons.contains { $0.localizedCaseInsensitiveContains("Restore") })
        let text = stack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " ")
        XCTAssertTrue(text.contains("30 simultaneous calls"))
        XCTAssertTrue(text.contains("Full call history"))
        XCTAssertTrue(text.contains("GNU General Public License"))
    }
}
