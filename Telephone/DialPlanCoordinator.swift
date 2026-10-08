import Cocoa
import UseCases

/// Every new outgoing call enters here. Session-bound transfers retain their
/// original account; callbacks and redials are new calls and resolve anew.
@MainActor
@objc final class DialPlanCoordinator: NSObject {
    @objc static let shared = DialPlanCoordinator()
    @objc var controllers: AccountControllers?
    @objc var errorHandler: ((String) -> Void)?
    @objc var showDiallerHandler: (() -> Void)?
    @objc var startBackendHandler: (() -> Void)?
    @objc var canAcceptCallsHandler: (() -> Bool)?
    @objc let store = DialPlanStore.shared

    @objc func accountSnapshots() -> [DialPlanAccount] {
        (controllers?.all ?? []).map {
            DialPlanAccount(uuid: $0.accountUUID, name: $0.accountDescription,
                            enabled: $0.isEnabled, availability: $0.routingAvailability)
        }
    }

    @objc(routeDestination:phoneLabel:)
    @discardableResult func routeDestination(_ destination: String, phoneLabel: String) -> Bool {
        routeDestination(destination, phoneLabel: phoneLabel, displayName: "")
    }

    @objc(routeDestination:phoneLabel:displayName:)
    @discardableResult func routeDestination(_ destination: String, phoneLabel: String, displayName: String) -> Bool {
        guard canAcceptCallsHandler?() ?? true else { return false }
        let route = store.resolveDestination(destination, accounts: accountSnapshots())
        guard route.canDial, !route.blocked, let uuid = route.accountUUID,
              let account = controllers?.all.first(where: { $0.accountUUID == uuid && $0.isEnabled }) else {
            errorHandler?(route.message)
            return false
        }
        let number = route.destination
        let uri: AKSIPURI?
        if number.canonicalNumber != nil || !number.destination.contains("@") {
            uri = AKSIPURI(user: number.destination, host: "", displayName: "")
        } else {
            let address = number.destination.lowercased().hasPrefix("sip:") ? number.destination : "sip:" + number.destination
            uri = AKSIPURI(string: address)
        }
        guard let uri else { errorHandler?("This call address could not be read."); return false }
        uri.displayName = displayName
        // The account and destination are frozen for this request, including
        // while registration is in flight. No fallback provider is attempted.
        // Literal emergency/short/service codes must not become SIP addresses
        // through a provider host on callback, which would bypass their rules.
        account.makeRoutedCall(to: uri, phoneLabel: phoneLabel, canonicalDestination: number.destination)
        startBackendHandler?()
        return true
    }

    @objc(routeURI:phoneLabel:)
    func routeURI(_ uri: AKSIPURI, phoneLabel: String) {
        let address = uri.copy() as! AKSIPURI
        address.displayName = ""
        routeDestination(address.host.isEmpty ? address.user : address.description, phoneLabel: phoneLabel, displayName: uri.displayName)
    }

    @objc func showDialler() { showDiallerHandler?() }
    @objc func startBackend() { startBackendHandler?() }
    @objc func presentFailure(_ message: String) { errorHandler?(message) }
}
