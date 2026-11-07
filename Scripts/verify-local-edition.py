#!/usr/bin/env python3
"""Portable, source-only guard against reintroducing obsolete purchase infrastructure.

Does not compile the macOS app or substitute for native Xcode and real-world tests.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
project_file = root / "Telephone.xcodeproj/project.pbxproj"
project = project_file.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("Local-edition source gate failed: " + message)


for removed in (
    "StoreKit.framework", "ReceiptValidation", "com.apple.InAppPurchase",
    "PresentationProduct.swift", "SKPaymentQueue", "PurchaseCheckUseCase",
    "StoreViewController.xib", "ObjCStoreEventTarget",
):
    require(removed not in project, f"retired project entry remains: {removed}")

for required in (
    "LocalBuildInformationViewController.swift in Sources",
    "LocalBuildInformationViewControllerTests.swift in Sources",
    "LocalBuildInformationWindowController.swift in Sources",
    "LocalBuildInformationWindowPresenter.swift in Sources",
    "LocalBuildInformationWindowController.xib in Resources",
    "LICENSE in Resources", "Credits.rtf in Resources",
    "CallHistoryViewEventTarget.swift in Sources",
):
    require(required in project, f"missing app/test resource: {required}")

# This also catches dangling source-phase file references after project edits.
source_names = set(re.findall(r"/\* ([^*\n]+?\.(?:swift|m|mm|c|cpp)) in Sources \*/", project))
# Scan only the eight project source trees, not vendor archives, build outputs
# or a possibly enormous .git directory. These trees contain all project Sources.
source_roots = (
    "Telephone", "TelephoneTests", "UseCases", "UseCasesTests",
    "UseCasesTestDoubles", "Domain", "DomainTests", "DomainTestDoubles",
)
source_paths = [
    p for folder in source_roots
    for p in (root / folder).rglob("*")
    if p.is_file()
]
repository_names = {p.name for p in source_paths}
missing_sources = sorted(source_names - repository_names)
require(not missing_sources, "missing source files: " + ", ".join(missing_sources))

# Inspect surviving production code, not just its application composition root.
# Historical upstream comments are not active SDK dependencies.
retired_production_symbol = re.compile(
    r"\b(?:SKPaymentQueue|SKProductsRequest|ReceiptXPCGateway|"
    r"PurchaseCheckUseCase|PurchaseCheckUseCaseFactory|"
    r"ReceiptValidatingContactCallHistoryRecordGetAllUseCaseOutput|"
    r"DefaultStoreViewEventTarget|StoreViewController|PresentationProduct|"
    r"LocalProReceipt|BundleReceipt|StoreEventTargets|ObjCStoreEventTarget|"
    r"UserDefaultsPurchaseReminderSettings)\b"
)
production_paths = (
    p for p in source_paths
    if p.parts[len(root.parts)] in {"Telephone", "UseCases", "Domain"}
    and p.suffix in {".swift", ".m", ".mm", ".h", ".c", ".cpp"}
)
for path in production_paths:
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith(("//", "/*", "*")):
            continue
        match = retired_production_symbol.search(line)
        require(match is None,
                f"retired production symbol {match.group()} in "
                f"{path.relative_to(root)}:{lineno}" if match else "")

# These 24-character keys are Xcode object identifiers, not SDK/build metadata.
object_ids = re.findall(r"^\t\t([0-9A-F]{24}) /\*[^\n]*\*/ = \{", project, re.M)
require(len(object_ids) == len(set(object_ids)), "duplicate Xcode project object IDs")
require(len(object_ids) >= 100, "Xcode project source inventory is unexpectedly small")

composition = (root / "Telephone/CompositionRoot.swift").read_text(encoding="utf-8")
startup = (root / "UseCases/UserAgentStartUseCase.swift").read_text(encoding="utf-8")
history = (root / "Telephone/CallHistoryViewEventTargetFactory.swift").read_text(encoding="utf-8")
information = (root / "Telephone/LocalBuildInformationViewController.swift").read_text(encoding="utf-8")
app_controller = (root / "Telephone/AppController.m").read_text(encoding="utf-8")
main_menu = (root / "Telephone/Base.lproj/MainMenu.xib").read_text(encoding="utf-8")

require("agent.maxCalls = 30" in startup and "PurchaseCheck" not in startup,
        "30-call engine startup is not independent of purchasing")
require("SKPaymentQueue" not in composition and "Receipt" not in composition
        and "Purchase" not in composition, "payment or receipt objects still constructed on startup")
require("ReceiptValidatingContactCallHistoryRecordGetAllUseCaseOutput" not in history
        and "CallHistoryViewPresenter" in history and "dayChangeEventTargets.add" in history,
        "history presentation is purchase-gated or its day-change wiring is absent")
require("LocalBuildInformation.licenceName" in information
        and "openLicence" in information and "openCredits" in information,
        "local information has lost licence or credit links")
require("showLocalBuildInformation:(id)sender" in app_controller
        and 'selector="showLocalBuildInformation:"' in main_menu,
        "Local Build Information menu action is disconnected")
require((root / "LICENSE").is_file() and (root / "Telephone/Credits.rtf").is_file(),
        "GPL licence or original credits missing from source")

for script in ("Scripts/run-macos-validation.sh", "Scripts/build-test-release.sh"):
    contents = (root / script).read_text(encoding="utf-8")
    require("for scheme in Domain UseCasesTests; do" in contents,
            f"old receipt test scheme still used by {script}")

print(f"Local-edition source gate passed ({len(source_names)} source filenames checked).")
print("This is static validation only; native Xcode suites, Release, signing and installed checks remain separate.")
