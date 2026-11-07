import AppKit
import AVFoundation
import CoreAudio

struct InputDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor final class InputDeviceMonitor {
    private let selectors = [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices]
    private var listener: AudioObjectPropertyListenerBlock?
    private var sleepObserver: NSObjectProtocol?

    static var devices: [InputDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func start(changed: @escaping @MainActor () -> Void, sleeping: @escaping @MainActor () -> Void) {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in Task { @MainActor in changed() } }
        listener = block
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { _ in MainActor.assumeIsolated { sleeping() } }
    }

    func stop() {
        guard let listener else { return }
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
}
