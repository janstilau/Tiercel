import Foundation

public struct SessionConfiguration {
    // 请求超时时间
    public var timeoutIntervalForRequest: TimeInterval = 60.0
    
    private static var MaxConcurrentTasksLimit: Int = {
        if #available(iOS 11.0, *) {
            return 6
        } else {
            return 3
        }
    }()
    
    // 最大并发数
    private var _maxConcurrentTasksLimit: Int = MaxConcurrentTasksLimit
    public var maxConcurrentTasksLimit: Int {
        get { _maxConcurrentTasksLimit }
        set {
            let limit = min(newValue, Self.MaxConcurrentTasksLimit)
            _maxConcurrentTasksLimit = max(limit, 1)
        }
    }
    
    public var allowsExpensiveNetworkAccess: Bool = true
    
    
    public var allowsConstrainedNetworkAccess: Bool = true
    
    // 是否允许蜂窝网络下载
    public var allowsCellularAccess: Bool = false
    
    public init() {
        
    }
}


