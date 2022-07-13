import Foundation

final public class UnfairLock {
    private let unfairLock: os_unfair_lock_t
    
    public init() {
        
        unfairLock = .allocate(capacity: 1)
        unfairLock.initialize(to: os_unfair_lock())
    }
    
    deinit {
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }
    
    private func lock() {
        os_unfair_lock_lock(unfairLock)
    }
    
    private func unlock() {
        os_unfair_lock_unlock(unfairLock)
    }
    
    
    public func around<T>(_ closure: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try closure()
    }
    
    public func around(_ closure: () throws -> Void) rethrows -> Void {
        lock(); defer { unlock() }
        return try closure()
    }
}

@propertyWrapper
final public class Protected<T> {
    
    private let lock = UnfairLock()
    
    private var value: T
    
    public var wrappedValue: T {
        get { lock.around { value } }
        set { lock.around { value = newValue } }
    }
    
    public var projectedValue: Protected<T> { self }
    
    
    public init(_ value: T) {
        self.value = value
    }
    
    public init(wrappedValue: T) {
        value = wrappedValue
    }
    
    public func read<U>(_ closure: (T) throws -> U) rethrows -> U {
        return try lock.around { try closure(self.value) }
    }
    
    
    @discardableResult
    public func write<U>(_ closure: (inout T) throws -> U) rethrows -> U {
        return try lock.around { try closure(&self.value) }
    }
}

final public class Debouncer {
    
    private let lock = UnfairLock()
    
    private let queue: DispatchQueue
    
    @Protected
    private var workItems = [String: DispatchWorkItem]()
    
    public init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    
    public func execute(label: String, deadline: DispatchTime, execute work: @escaping @convention(block) () -> Void) {
        execute(label: label, time: deadline, execute: work)
    }
    
    
    public func execute(label: String, wallDeadline: DispatchWallTime, execute work: @escaping @convention(block) () -> Void) {
        execute(label: label, time: wallDeadline, execute: work)
    }
    
    
    private func execute<T: Comparable>(label: String, time: T, execute work: @escaping @convention(block) () -> Void) {
        lock.around {
            workItems[label]?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                work()
                self?.workItems.removeValue(forKey: label)
            }
            workItems[label] = workItem
            if let time = time as? DispatchTime {
                queue.asyncAfter(deadline: time, execute: workItem)
            } else if let time = time as? DispatchWallTime {
                queue.asyncAfter(wallDeadline: time, execute: workItem)
            }
        }
    }
}

final public class Throttler {
    
    private let lock = UnfairLock()
    
    private let queue: DispatchQueue
    
    private var workItems = [String: DispatchWorkItem]()
    
    private let latest: Bool
    
    public init(queue: DispatchQueue, latest: Bool) {
        self.queue = queue
        self.latest = latest
    }
    
    
    public func execute(label: String, deadline: DispatchTime, execute work: @escaping @convention(block) () -> Void) {
        execute(label: label, time: deadline, execute: work)
    }
    
    
    public func execute(label: String, wallDeadline: DispatchWallTime, execute work: @escaping @convention(block) () -> Void) {
        execute(label: label, time: wallDeadline, execute: work)
    }
    
    private func execute<T: Comparable>(label: String, time: T, execute work: @escaping @convention(block) () -> Void) {
        lock.around {
            let workItem = workItems[label]
            
            guard workItem == nil || latest else { return }
            workItem?.cancel()
            workItems[label] = DispatchWorkItem { [weak self] in
                self?.workItems.removeValue(forKey: label)
                work()
            }
            
            guard workItem == nil else { return }
            if let time = time as? DispatchTime {
                queue.asyncAfter(deadline: time) { [weak self] in
                    self?.workItems[label]?.perform()
                }
            } else if let time = time as? DispatchWallTime {
                queue.asyncAfter(wallDeadline: time) { [weak self] in
                    self?.workItems[label]?.perform()
                }
            }
        }
    }
}


