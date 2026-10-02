import Carbon.HIToolbox
import FreeShotCore
import Foundation

/// Global hotkeys via Carbon RegisterEventHotKey. Needs no Accessibility permission.
final class HotkeyManager {
    struct Failure {
        let action: FreeShotAction
        let spec: HotkeySpec
        let status: OSStatus

        /// Menu text, e.g. "⌘⇧4 is held by another app".
        var message: String {
            status == OSStatus(eventHotKeyExistsErr)
                ? "\(spec.displayString) is held by another app"
                : "\(spec.displayString) failed to register (\(status))"
        }
    }

    static let signature = fourCC("FSHT")

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: FreeShotAction] = [:]
    private var handlerRef: EventHandlerRef?
    private let onPress: (FreeShotAction) -> Void
    private(set) var failures: [Failure] = []

    init(onPress: @escaping (FreeShotAction) -> Void) {
        self.onPress = onPress
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr, hkID.signature == HotkeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.fire(id: hkID.id)
            return noErr
        }, 1, &spec, userData, &handlerRef)
        if status != noErr { log("InstallEventHandler failed: \(status)") }
    }

    private func fire(id: UInt32) {
        guard let action = actions[id] else { return }
        DispatchQueue.main.async { self.onPress(action) }
    }

    /// Replaces all registrations. Returns the failures (also kept in `failures`).
    @discardableResult
    func register(_ map: [FreeShotAction: HotkeySpec]) -> [Failure] {
        unregisterAll()
        failures = []
        // Stable order so ids and logs do not shuffle between runs.
        for (index, action) in FreeShotAction.allCases.enumerated() {
            guard let spec = map[action] else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(spec.carbonKey, spec.carbonModifiers,
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[id] = ref
                actions[id] = action
            } else {
                let f = Failure(action: action, spec: spec, status: status)
                failures.append(f)
                log("\(action.title): \(f.message)")
            }
        }
        return failures
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs = [:]
        actions = [:]
    }

    var registeredActions: [FreeShotAction] { Array(actions.values) }

    private func log(_ s: String) {
        FileHandle.standardError.write("FreeShot hotkeys: \(s)\n".data(using: .utf8)!)
    }
}
