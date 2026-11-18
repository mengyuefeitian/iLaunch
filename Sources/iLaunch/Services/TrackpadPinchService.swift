// Multitouch ABI adapted from okruts/macos-gesture-launcher.
// Copyright (c) 2026 Oleg Kruts. MIT license in Resources/GestureLauncher-LICENSE.txt.
import CoreFoundation
import Darwin
import Foundation

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTReadout {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout
    var zero2: (Int32, Int32)
    var density: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallbackFunction = @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) -> Int32
typealias MTDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFArray>?
typealias MTRegisterContactFrameCallbackFunc = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
typealias MTUnregisterContactFrameCallbackFunc = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Void
typealias MTDeviceStartFunc = @convention(c) (MTDeviceRef, Int32) -> Void
typealias MTDeviceStopFunc = @convention(c) (MTDeviceRef, Int32) -> Void


final class TrackpadPinchService: @unchecked Sendable {
    private static let callbackLock = NSLock()
    nonisolated(unsafe) private static var active: TrackpadPinchService?
    private var observedCounts: Set<Int> = []
    private var detectors: [UInt: MultiFingerPinchDetector] = [:]
    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray?
    private var framework: UnsafeMutableRawPointer?
    private var unregister: MTUnregisterContactFrameCallbackFunc?
    private var stopDevice: MTDeviceStopFunc?
    private let onPinch: @MainActor @Sendable (PinchDirection) -> Void

    init(onPinch: @escaping @MainActor @Sendable (PinchDirection) -> Void) {
        self.onPinch = onPinch
    }

    func start() {
        guard devices.isEmpty else { return }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = framework ?? dlopen(path, RTLD_NOW) else {
            DiagLog.write("pinch: MultitouchSupport unavailable")
            return
        }
        framework = handle
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            guard let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        guard let create = symbol("MTDeviceCreateList", MTDeviceCreateListFunc.self),
              let register = symbol("MTRegisterContactFrameCallback", MTRegisterContactFrameCallbackFunc.self),
              let unregister = symbol("MTUnregisterContactFrameCallback", MTUnregisterContactFrameCallbackFunc.self),
              let startDevice = symbol("MTDeviceStart", MTDeviceStartFunc.self),
              let stopDevice = symbol("MTDeviceStop", MTDeviceStopFunc.self),
              let list = create()?.takeRetainedValue() else {
            DiagLog.write("pinch: required symbols or device list unavailable")
            return
        }
        self.unregister = unregister
        self.stopDevice = stopDevice
        deviceList = list
        devices = (0..<CFArrayGetCount(list)).compactMap {
            CFArrayGetValueAtIndex(list, $0).map { UnsafeMutableRawPointer(mutating: $0) }
        }
        Self.callbackLock.lock()
        for device in devices { detectors[UInt(bitPattern: device)] = MultiFingerPinchDetector() }
        Self.active = self
        Self.callbackLock.unlock()
        for device in devices {
            register(device, trackpadPinchCallback)
            startDevice(device, 0)
        }
        DiagLog.write("pinch: listening on \(devices.count) multitouch device(s)")
    }

    func stop() {
        Self.callbackLock.lock()
        if Self.active === self { Self.active = nil }
        detectors.removeAll()
        Self.callbackLock.unlock()
        for device in devices {
            unregister?(device, trackpadPinchCallback)
            stopDevice?(device, 0)
        }
        devices.removeAll()
        deviceList = nil
    }

    fileprivate static func receive(device: MTDeviceRef, touches: UnsafeMutableRawPointer?, count: Int32) {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        guard let service = active, count >= 0, count <= 32 else { return }
        var contacts: [PinchContact] = []
        if count > 0, let touches {
            let buffer = UnsafeBufferPointer(start: touches.assumingMemoryBound(to: MTTouch.self), count: Int(count))
            contacts = buffer.filter { (1...4).contains($0.state) }.map {
                PinchContact(id: $0.identifier, x: Double($0.normalized.position.x), y: Double($0.normalized.position.y))
            }
        }
        if service.observedCounts.insert(contacts.count).inserted {
            let count = contacts.count
            DispatchQueue.main.async { DiagLog.write("pinch: received \(count) active contacts") }
        }
        let key = UInt(bitPattern: device)
        guard var detector = service.detectors[key] else { return }
        let matched = detector.update(contacts)
        service.detectors[key] = detector
        if let direction = matched {
            let action = service.onPinch
            let contactCount = contacts.count
            DispatchQueue.main.async {
                DiagLog.write("pinch: \(contactCount)-finger \(direction) gesture recognized")
                action(direction)
            }
        }
    }
}

private func trackpadPinchCallback(
    _ device: MTDeviceRef, _ touches: UnsafeMutableRawPointer, _ count: Int32,
    _ timestamp: Double, _ frame: Int32
) -> Int32 {
    TrackpadPinchService.receive(device: device, touches: touches, count: count)
    return 0
}
