import CoreMediaIO
import Dispatch

/// Reads and watches the properties of Core Media I/O objects: the system,
/// devices and streams. There's no Swift API for them, so this wraps the C API.
enum CMIOProperty {
    static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func exists(_ selector: Int, on object: CMIOObjectID) -> Bool {
        var address = Self.address(selector)
        return CMIOObjectHasProperty(object, &address)
    }

    static func objectIDs(of object: CMIOObjectID, selector: Int) -> [CMIOObjectID] {
        var address = Self.address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.stride)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.stride))
    }

    static func uint32(of object: CMIOObjectID, selector: Int) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &value) == noErr else { return nil }
        return value
    }

    static func string(of object: CMIOObjectID, selector: Int) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// The selector for a four-character code such as "inus".
    static func selector(_ code: String) -> Int {
        Int(code.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }

    /// Calls a closure whenever one property of an object changes, until it's released.
    final class Listener {
        private let object: CMIOObjectID
        private var address: CMIOObjectPropertyAddress
        private let queue: DispatchQueue
        private let block: CMIOObjectPropertyListenerBlock

        /// Calls `onChange` on `queue` after each change, or returns nil if the property can't be listened to.
        init?(_ selector: Int, on object: CMIOObjectID, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
            self.object = object
            address = CMIOProperty.address(selector)
            self.queue = queue
            block = { _, _ in onChange() }
            guard CMIOObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return nil }
        }

        deinit {
            CMIOObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
    }
}
