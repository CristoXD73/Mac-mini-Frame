// Logs raw HID button/hat changes from Microsoft (and Sony/Valve) controllers
// for 60 s. Used to find the home button's usage (page 0x09, usage 0x0D on
// the Xbox Wireless Controller 0x0B13).
//   swiftc tools/hidprobe.swift -o /tmp/hidprobe && /tmp/hidprobe
import Foundation
import IOKit.hid

let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatchingMultiple(m, [0x045E, 0x054C, 0x28DE].map { [kIOHIDVendorIDKey: $0] } as CFArray)
let start = Date()
IOHIDManagerRegisterInputValueCallback(m, { _, _, _, value in
    let e = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(e), usage = IOHIDElementGetUsage(e)
    guard page == 0x09 || (page == 0x01 && usage == 0x39) else { return }
    print(String(format: "%7.3f  page 0x%02X usage 0x%02X (%d)  value %d  [logical %d...%d]",
                 Date().timeIntervalSince(start), page, usage, usage, IOHIDValueGetIntegerValue(value),
                 IOHIDElementGetLogicalMin(e), IOHIDElementGetLogicalMax(e)))
}, nil)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
print("open: 0x" + String(IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)), radix: 16), "— press buttons (60 s)")
RunLoop.main.run(until: Date().addingTimeInterval(60))
