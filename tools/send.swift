import Foundation
DistributedNotificationCenter.default().postNotificationName(.init("local.consolemode.test"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
