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
extension TiercelWrapper where Base == Notification {
    public var downloadTask: DownloadTask? {
        return base.userInfo?[String.downloadTaskKey] as? DownloadTask
    }
    
    public var sessionManager: SessionManager? {
        return base.userInfo?[String.sessionManagerKey] as? SessionManager
    }
}

extension Notification {
    init(name: Notification.Name, downloadTask: DownloadTask) {
        self.init(name: name, object: nil, userInfo: [String.downloadTaskKey: downloadTask])
    }
    
    init(name: Notification.Name, sessionManager: SessionManager) {
        self.init(name: name, object: nil, userInfo: [String.sessionManagerKey: sessionManager])
    }
}

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
