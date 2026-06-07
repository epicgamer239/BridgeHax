import Foundation
import os

public final class TelemetryRecorder {
    public static let shared = TelemetryRecorder()
    private let log = OSLog(subsystem: "com.dualsight", category: "lidar")

    private init() {}

    public func record(_ event: String, objectID: String? = nil, className: String? = nil) {
        if let oid = objectID, let cls = className {
            os_log("%{public}@ object=%{public}@ class=%{public}@", log: log, type: .info, event, oid, cls)
        } else if let oid = objectID {
            os_log("%{public}@ object=%{public}@", log: log, type: .info, event, oid)
        } else {
            os_log("%{public}@", log: log, type: .info, event)
        }
    }
}
