import Foundation

// 一个自定义的 Lock 类, 这个 Lock 类, 目前只在该环境下被使用了.
final public class UnfairLock {
    private let unfairLock: os_unfair_lock_t
    
    public init() {
        // 分配内存空间
        unfairLock = .allocate(capacity: 1)
        // 进行初始化操作.
        unfairLock.initialize(to: os_unfair_lock())
    }
    
    deinit {
        // 析构.
        unfairLock.deinitialize(count: 1)
        // 回收内存空间.
        unfairLock.deallocate()
    }
    
    private func lock() {
        os_unfair_lock_lock(unfairLock)
    }
    
    private func unlock() {
        os_unfair_lock_unlock(unfairLock)
    }
    
    // 这种, 使用 Defer 来完成后续逻辑处理的方式, 非常非常普遍.
    // 根据, 闭包的返回值, 来决定整个函数的返回值, 这种写法非常普遍.
    public func around<T>(_ closure: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try closure()
    }
    
    public func around(_ closure: () throws -> Void) rethrows -> Void {
        lock(); defer { unlock() }
        return try closure()
    }
}

/*
 泛型类, 抽象的是一个存储变量, T 类型.
 */
@propertyWrapper
final public class Protected<T> {
    
    private let lock = UnfairLock()
    
    private var value: T
    
    public var wrappedValue: T {
        // 根据, 传入的闭包的返回值, 来调用 around 的不同的函数.
        get { lock.around { value } }
        set { lock.around { value = newValue } }
    }
    
    public var projectedValue: Protected<T> { self }
    
    public init(_ value: T) {
        self.value = value
    }
    
    // PropertyWrapper 真正会去调用的初始化函数.
    public init(wrappedValue: T) {
        value = wrappedValue
    }
    
    // 这是一个最为灵活的, 进行扩展的方式.
    /*
     闭包, 可以抛出错误, 所以在内部使用的时候, 要使用 try.
     返回值的类型, 是由闭包决定的.
     闭包里面, 是一个 transfom 函数, 如果不需要 transfrom, 直接写 $0 就可以了, 就和 Pointer 一样.
     */
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


