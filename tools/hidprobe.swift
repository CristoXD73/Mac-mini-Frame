import Foundation
import IOKit.hid
// Log every button-like HID change from Microsoft controllers (vendor 0x045E) for 60 seconds.
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: 0x045E] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(mgr, { _, _, _, value in
    let e = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(e), usage = IOHIDElementGetUsage(e), v = IOHIDValueGetIntegerValue(value)
    // Skip sticks/triggers (generic desktop axes) to keep the log readable.
    if page == 0x01 && (0x30...0x35).contains(usage) { return }
    if page == 0x02 { return }
    print(String(format: "%.2f page=0x%02X usage=0x%03X value=%d", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000), page, usage, v))
    fflush(stdout)
}, nil)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
print("open result: \(r == kIOReturnSuccess ? "ok" : String(format: "0x%08X", r))"); fflush(stdout)
RunLoop.current.run(until: Date().addingTimeInterval(60))
