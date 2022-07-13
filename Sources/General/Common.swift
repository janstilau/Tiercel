import Foundation

public enum LogOption {
    case `default`
    case none
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

public struct TiercelWrapper<Base> {
    internal let base: Base
    internal init(_ base: Base) {
        self.base = base
    }
}


public protocol TiercelCompatible {
    
}

extension TiercelCompatible {
    public var tr: TiercelWrapper<Self> {
        get { TiercelWrapper(self) }
    }
    public static var tr: TiercelWrapper<Self>.Type {
        get { TiercelWrapper<Self>.self }
    }
}

