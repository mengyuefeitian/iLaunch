import Foundation

struct PinchContact {
    let id: Int32
    let x: Double
    let y: Double
}

/// Tracks five-contact pinches without relying on thumb shape.
enum PinchDirection {
    case inward
    case outward
}

struct MultiFingerPinchDetector {
    private var initialContacts: [PinchContact] = []
    private var gestureConsumed = false

    mutating func update(_ contacts: [PinchContact]) -> PinchDirection? {
        guard contacts.count == 5 else {
            initialContacts = []
            if contacts.isEmpty { gestureConsumed = false }
            return nil
        }
        guard !gestureConsumed, contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let shared = initialContacts.compactMap { start in
            contacts.first(where: { $0.id == start.id }).map { (start, $0) }
        }
        guard shared.count == 5 else {
            initialContacts = contacts
            return nil
        }
        let initialRadius = radius(of: shared.map { $0.0 })
        let change = radius(of: shared.map { $0.1 }) - initialRadius
        guard abs(change) >= max(0.009, initialRadius * 0.12) else { return nil }
        gestureConsumed = true
        return change < 0 ? .inward : .outward
    }

    private func radius(of contacts: [PinchContact]) -> Double {
        let count = Double(contacts.count)
        let centerX = contacts.reduce(0.0) { $0 + $1.x } / count
        let centerY = contacts.reduce(0.0) { $0 + $1.y } / count
        return contacts.reduce(0.0) {
            $0 + hypot($1.x - centerX, $1.y - centerY)
        } / count
    }
}
