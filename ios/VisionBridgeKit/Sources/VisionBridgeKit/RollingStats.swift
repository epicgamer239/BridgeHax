import Foundation

/// Fixed-capacity window for p95 / mean; `record` does not grow backing storage.
public struct RollingWindowStats: Sendable {
    public let windowSize: Int
    private var values: [Double]
    private var count: Int
    private var head: Int

    public init(windowSize: Int = 30) {
        let n = Swift.max(1, windowSize)
        self.windowSize = n
        self.values = [Double](repeating: 0, count: n)
        self.count = 0
        self.head = 0
    }

    public mutating func record(_ value: Double) {
        if count < windowSize {
            values[count] = value
            count += 1
        } else {
            values[head] = value
            head = (head + 1) % windowSize
        }
    }

    public var mean: Double {
        if count == 0 { return 0 }
        if count < windowSize {
            var s = 0.0
            for i in 0..<count { s += values[i] }
            return s / Double(count)
        }
        return values.reduce(0, +) / Double(windowSize)
    }

    public var p95: Double {
        if count == 0 { return 0 }
        let n = min(count, windowSize)
        var copy = [Double]()
        copy.reserveCapacity(n)
        if count < windowSize {
            for i in 0..<count { copy.append(values[i]) }
        } else {
            for i in 0..<windowSize {
                let idx = (head + i) % windowSize
                copy.append(values[idx])
            }
        }
        copy.sort()
        let last = copy.count - 1
        let p95Index = Int(Double(last) * 0.95)
        let idx = Swift.min(Swift.max(0, p95Index), last)
        return copy[idx]
    }

    public var max: Double {
        if count == 0 { return 0 }
        if count < windowSize {
            return (0..<count).map { values[$0] }.max() ?? 0
        }
        return values.max() ?? 0
    }
}
