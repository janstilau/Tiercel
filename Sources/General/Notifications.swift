import Foundation

public extension DownloadTask {
    static let runningNotification = Notification.Name(rawValue: "com.Tiercel.notification.name.downloadTask.running")
    static let didCompleteNotification = Notification.Name(rawValue: "com.Tiercel.notification.name.downloadTask.didComplete")
    
}

public extension SessionManager {
    static let runningNotification = Notification.Name(rawValue: "com.Tiercel.notification.name.sessionManager.running")
    static let didCompleteNotification = Notification.Name(rawValue: "com.Tiercel.notification.name.sessionManager.didComplete")
    
}

extension Notification: TiercelCompatible { }
// 就是在 UserInfo 里面, 进行相关的数据提取工作.
// 定义方便的方法, 供外界使用, 是类的设计者的责任.
extension TiercelWrapper where Base == Notification {
    public var downloadTask: DownloadTask? {
        return base.userInfo?[String.downloadTaskKey] as? DownloadTask
    }
    
    public var sessionManager: SessionManager? {
        return base.userInfo?[String.sessionManagerKey] as? SessionManager
    }
}

// 提供, 对应的快捷进行 Notification 组装的能力.
extension Notification {
    init(name: Notification.Name, downloadTask: DownloadTask) {
        self.init(name: name, object: nil, userInfo: [String.downloadTaskKey: downloadTask])
    }
    
    init(name: Notification.Name, sessionManager: SessionManager) {
        self.init(name: name, object: nil, userInfo: [String.sessionManagerKey: sessionManager])
    }
}

// Center 专门定义快速进行对应 DownloadTask 组装的能力.
extension NotificationCenter {
    func postNotification(name: Notification.Name, downloadTask: DownloadTask) {
        let notification = Notification(name: name, downloadTask: downloadTask)
        post(notification)
    }
    func postNotification(name: Notification.Name, sessionManager: SessionManager) {
        let notification = Notification(name: name, sessionManager: sessionManager)
        post(notification)
    }
}

extension String {
    fileprivate static let downloadTaskKey = "com.Tiercel.notification.key.downloadTask"
    fileprivate static let sessionManagerKey = "com.Tiercel.notification.key.sessionManagerKey"
}
