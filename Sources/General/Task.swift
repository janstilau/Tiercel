import Foundation

extension Task {
    public enum Validation: Int {
        case unkown
        case correct
        case incorrect
    }
}

public class Task<TaskType>: NSObject, Codable {
    
    public internal(set) weak var manager: SessionManager?
    
    // 这是从 SessionManager 中获取到的.
    internal var cache: Cache
    // 这是从 SessionManager 中获取到的.
    internal var operationQueue: DispatchQueue
    
    public let url: URL
    
    public let progress: Progress = Progress()
    
    internal let protectedState: Protected<State>
    
    internal init(_ url: URL,
                  headers: [String: String]? = nil,
                  cache: Cache,
                  operationQueue:DispatchQueue) {
        self.cache = cache
        self.url = url
        self.operationQueue = operationQueue
        protectedState = Protected(State(currentURL: url, fileName: url.tr.fileName))
        super.init()
        self.headers = headers
    }
    
    // 虽然从数据结构上, 是专门一个 State 包裹住了大部分内的数据.
    // 但是在归档接档的时候, 完全可以将这一层去除掉了.
    // 只要归档, 解档的时候, 能够还原出数据内容就可以了.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(currentURL, forKey: .currentURL)
        try container.encode(fileName, forKey: .fileName)
        try container.encodeIfPresent(headers, forKey: .headers)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(progress.totalUnitCount, forKey: .totalBytes)
        try container.encode(progress.completedUnitCount, forKey: .completedBytes)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(verificationCode, forKey: .verificationCode)
        try container.encode(verificationType.rawValue, forKey: .verificationType)
        try container.encode(validationResult.rawValue, forKey: .validation)
        if let error = error {
            let errorData: Data
            if #available(iOS 11.0, *) {
                errorData = try NSKeyedArchiver.archivedData(withRootObject: (error as NSError), requiringSecureCoding: true)
            } else {
                errorData = NSKeyedArchiver.archivedData(withRootObject: (error as NSError))
            }
            try container.encode(errorData, forKey: .error)
        }
    }
    
    // 解档的时候, 通过 Archive 将所有需要的数据解出, 然后统一使用 write 进行数据的赋值.
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        let currentURL = try container.decode(URL.self, forKey: .currentURL)
        let fileName = try container.decode(String.self, forKey: .fileName)
        protectedState = Protected(State(currentURL: currentURL, fileName: fileName))
        // 通过, 向 decoder 中藏值的方式, 完成了工具类对象的初始化操作.
        cache = decoder.userInfo[.cache] as? Cache ?? Cache("default")
        operationQueue = decoder.userInfo[.operationQueue] as? DispatchQueue ?? DispatchQueue(label: "com.Tiercel.SessionManager.operationQueue")
        super.init()
        
        progress.totalUnitCount = try container.decode(Int64.self, forKey: .totalBytes)
        progress.completedUnitCount = try container.decode(Int64.self, forKey: .completedBytes)
        
        let statusString = try container.decode(String.self, forKey: .status)
        let verificationTypeInt = try container.decode(Int.self, forKey: .verificationType)
        let validationType = try container.decode(Int.self, forKey: .validation)
        
        try protectedState.write {
            $0.headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
            $0.startDate = try container.decode(Double.self, forKey: .startDate)
            $0.endDate = try container.decode(Double.self, forKey: .endDate)
            $0.verificationCode = try container.decodeIfPresent(String.self, forKey: .verificationCode)
            $0.status = Status(rawValue: statusString)!
            $0.verificationType = FileChecksumHelper.VerificationType(rawValue: verificationTypeInt)!
            $0.validation = Validation(rawValue: validationType)!
            if let errorData = try container.decodeIfPresent(Data.self, forKey: .error) {
                if #available(iOS 11.0, *) {
                    $0.error = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: errorData)
                } else {
                    $0.error = NSKeyedUnarchiver.unarchiveObject(with: errorData) as? NSError
                }
            }
        }
    }
    
    internal func execute(_ Executer: Executer<TaskType>?) { }
}

extension Task {
    fileprivate enum CodingKeys: CodingKey {
        case url
        case currentURL
        case fileName
        case headers
        case startDate
        case endDate
        case totalBytes
        case completedBytes
        case verificationCode
        case status
        case verificationType
        case validation
        case error
    }
    
    enum CompletionType {
        case local // 程序所控制的, 逻辑内操作.
        case network(task: URLSessionTask, error: Error?) // 网络请求引起的回调.
    }
    
    enum InterruptType {
        case manual(_ fromRunningTask: Bool)
        case error(_ error: Error)
        case statusCode(_ statusCode: Int)
    }
    
    internal struct State {
        var session: URLSession? //
        var headers: [String: String]?
        var verificationCode: String?
        var verificationType: FileChecksumHelper.VerificationType = .md5
        var isRemoveCompletely: Bool = false
        var status: Status = .waiting
        var validation: Validation = .unkown
        var currentURL: URL
        var startDate: Double = 0
        var endDate: Double = 0
        var speed: Int64 = 0 // 不归档.
        var fileName: String
        var timeRemaining: Int64 = 0 // 不归档
        var error: Error?
        
        // 以下不归档.
        var progressExecuter: Executer<TaskType>?
        var successExecuter: Executer<TaskType>?
        var failureExecuter: Executer<TaskType>?
        var completionExecuter: Executer<TaskType>?
        var validateExecuter: Executer<TaskType>?
        /*
         Suspend, Cancle, Remove 操作的时候, 会给里面赋值.
         */
        var controlExecuter: Executer<TaskType>?
    }
}

extension Task {
    internal var session: URLSession? {
        get { protectedState.wrappedValue.session }
        set { protectedState.write { $0.session = newValue } }
    }
    
    internal var headers: [String: String]? {
        get { protectedState.wrappedValue.headers }
        set { protectedState.write { $0.headers = newValue } }
    }
    
    internal var verificationCode: String? {
        get { protectedState.wrappedValue.verificationCode }
        set { protectedState.write { $0.verificationCode = newValue } }
    }
    
    internal var verificationType: FileChecksumHelper.VerificationType {
        get { protectedState.wrappedValue.verificationType }
        set { protectedState.write { $0.verificationType = newValue } }
    }
    
    internal var isRemoveCompletely: Bool {
        get { protectedState.wrappedValue.isRemoveCompletely }
        set { protectedState.write { $0.isRemoveCompletely = newValue } }
    }
    
    public internal(set) var status: Status {
        get { protectedState.wrappedValue.status }
        set {
            protectedState.write { $0.status = newValue }
            if newValue == .willSuspend || newValue == .willCancel || newValue == .willRemove {
                return
            }
            if self is DownloadTask {
                manager?.log(.downloadTask(newValue.rawValue, task: self as! DownloadTask))
            }
        }
    }
    
    public internal(set) var validationResult: Validation {
        get { protectedState.wrappedValue.validation }
        set { protectedState.write { $0.validation = newValue } }
    }
    
    internal var currentURL: URL {
        get { protectedState.wrappedValue.currentURL }
        set { protectedState.write { $0.currentURL = newValue } }
    }
    
    
    public internal(set) var startDate: Double {
        get { protectedState.wrappedValue.startDate }
        set { protectedState.write { $0.startDate = newValue } }
    }
    
    public var startDateString: String {
        startDate.tr.convertTimeToDateString()
    }
    
    public internal(set) var endDate: Double {
        get { protectedState.wrappedValue.endDate }
        set { protectedState.write { $0.endDate = newValue } }
    }
    
    public var endDateString: String {
        endDate.tr.convertTimeToDateString()
    }
    
    
    public internal(set) var speed: Int64 {
        get { protectedState.wrappedValue.speed }
        set { protectedState.write { $0.speed = newValue } }
    }
    
    public var speedString: String {
        speed.tr.convertSpeedToString()
    }
    
    /// 默认为url的md5加上文件扩展名
    public internal(set) var fileName: String {
        get { protectedState.wrappedValue.fileName }
        set { protectedState.write { $0.fileName = newValue } }
    }
    
    public internal(set) var timeRemaining: Int64 {
        get { protectedState.wrappedValue.timeRemaining }
        set { protectedState.write { $0.timeRemaining = newValue } }
    }
    
    public var timeRemainingString: String {
        timeRemaining.tr.convertTimeToString()
    }
    
    public internal(set) var error: Error? {
        get { protectedState.wrappedValue.error }
        set { protectedState.write { $0.error = newValue } }
    }
    
    
    internal var progressExecuter: Executer<TaskType>? {
        get { protectedState.wrappedValue.progressExecuter }
        set { protectedState.write { $0.progressExecuter = newValue } }
    }
    
    internal var successExecuter: Executer<TaskType>? {
        get { protectedState.wrappedValue.successExecuter }
        set { protectedState.write { $0.successExecuter = newValue } }
    }
    
    internal var failureExecuter: Executer<TaskType>? {
        get { protectedState.wrappedValue.failureExecuter }
        set { protectedState.write { $0.failureExecuter = newValue } }
    }
    
    internal var completionExecuter: Executer<TaskType>? {
        get { protectedState.wrappedValue.completionExecuter }
        set { protectedState.write { $0.completionExecuter = newValue } }
    }
    
    internal var controlExecuter: Executer<TaskType>? {
        get { protectedState.wrappedValue.controlExecuter }
        set { protectedState.write { $0.controlExecuter = newValue } }
    }
    
    internal var validateExecuter: Executer<TaskType>? {
        get { protectedState.wrappedValue.validateExecuter }
        set { protectedState.write { $0.validateExecuter = newValue } }
    }
}

extension Task {
    // 延续 Alamofire 里面的设计思路, 所有的这些, 都是进行回调的存储.
    @discardableResult
    public func progress(onMainQueue: Bool = true, handler: @escaping Handler<TaskType>) -> Self {
        progressExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        return self
    }
    
    @discardableResult
    public func success(onMainQueue: Bool = true, handler: @escaping Handler<TaskType>) -> Self {
        successExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if status == .succeeded  && completionExecuter == nil{
            operationQueue.async {
                self.execute(self.successExecuter)
            }
        }
        return self
        
    }
    
    @discardableResult
    public func failure(onMainQueue: Bool = true, handler: @escaping Handler<TaskType>) -> Self {
        failureExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if completionExecuter == nil &&
            (status == .suspended ||
             status == .canceled ||
             status == .removed ||
             status == .failed) {
            operationQueue.async {
                self.execute(self.failureExecuter)
            }
        }
        return self
    }
    
    @discardableResult
    public func completion(onMainQueue: Bool = true, handler: @escaping Handler<TaskType>) -> Self {
        completionExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if status == .suspended ||
            status == .canceled ||
            status == .removed ||
            status == .succeeded ||
            status == .failed  {
            operationQueue.async {
                self.execute(self.completionExecuter)
            }
        }
        return self
    }
}


