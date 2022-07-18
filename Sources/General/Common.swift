import Foundation

public enum LogOption {
    case `default`
    case none // 选择该值, 可以打断 Logger 的所有 Log 行为. 
}

public enum LogType {
    case sessionManager(_ message: String, manager: SessionManager)
    case downloadTask(_ message: String, task: DownloadTask)
    case error(_ message: String, error: Error)
}

public protocol Logable {
    var identifier: String { get }
    
    var option: LogOption { get set }
    
    func log(_ type: LogType)
}

public struct Logger: Logable {
    
    public let identifier: String
    
    public var option: LogOption
    
    public func log(_ type: LogType) {
        // 如果不需要 Log, 直接这里改动就好了,
        guard option == .default else { return }
        
        var strings = ["************************ TiercelLog ************************"]
        strings.append("identifier    :  \(identifier)")
        switch type {
        case let .sessionManager(message, manager):
            strings.append("Message       :  [SessionManager] \(message), tasks.count: \(manager.tasks.count)")
        case let .downloadTask(message, task):
            strings.append("Message       :  [DownloadTask] \(message)")
            strings.append("Task URL      :  \(task.url.absoluteString)")
            if let error = task.error, task.status == .failed {
                strings.append("Error         :  \(error)")
            }
        case let .error(message, error):
            strings.append("Message       :  [Error] \(message)")
            strings.append("Description   :  \(error)")
        }
        strings.append("")
        print(strings.joined(separator: "\n"))
    }
}

public enum Status: String {
    case waiting
    case running
    case suspended
    case canceled
    case failed
    case removed
    case succeeded
    
    case willSuspend
    case willCancel
    case willRemove
}

/*
    Wrapper 这种模式, 在 Tiercel 库中的使用.
    TiercelCompatible 提供的能力, 是能够调用 yd, tr 这样的一个属性, 进行一次包装.
    各种能力, 都是在 TiercelWrapper 上进行的添加. 使用 base 获取原始数据, 在原始数据上, 添加新的逻辑.
 */
public struct TiercelWrapper<Base> {
    internal let base: Base
    internal init(_ base: Base) {
        self.base = base
    }
}

public protocol TiercelCompatible { }

extension TiercelCompatible {
    public var tr: TiercelWrapper<Self> {
        get { TiercelWrapper(self) }
    }
    public static var tr: TiercelWrapper<Self>.Type {
        get { TiercelWrapper<Self>.self }
    }
}

