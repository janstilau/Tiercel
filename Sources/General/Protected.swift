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
    
    // 根据, 传入的闭包的返回值, 来调用 around 的不同的函数.
    // 取值赋值, 直接就是在锁环境里面.
    public var wrappedValue: T {
        get { lock.around {
            value
        }}
        set { lock.around {
            value = newValue
        } }
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

// Debouncer 的含义是, 原来的取消, 用新的.
final public class Debouncer {
    
    private let lock = UnfairLock()
    
    private let queue: DispatchQueue
    
    @Protected
    private var workItems = [String: DispatchWorkItem]()
    
    public init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    public func execute(label: String, deadline: DispatchTime, execute work: @escaping () -> Void) {
        execute(label: label, time: deadline, execute: work)
    }
    
    
    public func execute(label: String, wallDeadline: DispatchWallTime, execute work: @escaping () -> Void) {
        execute(label: label, time: wallDeadline, execute: work)
    }
    
    // 之所以, 这里需要使用泛型, 主要是为了适配 DispatchTime 这一时间项.
    private func execute<T: Comparable>(label: String, time: T, execute work: @escaping () -> Void) {
        lock.around {
            workItems[label]?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                work()
                // 应该这样做才正确吧. 直接使用 workItems 其实有点问题.
                // 实际上, workItems 本身就是锁环境的, 所以这里其实是两把锁. 在 UnfairLock 的内部, protected 里面的这把锁还是在起作用.
//                lock.around {
//                    self?.workItems.removeValue(forKey: label)
//                }
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

