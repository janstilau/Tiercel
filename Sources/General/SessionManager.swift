import UIKit

public class SessionManager {
    /*
     添加下载任务, 和添加正在下载的任务是不同的.
     
     添加任务, 是将任务添加到备用下载任务中. 还没有真正的开启.
     添加正在下载的任务, 是真正的开始进行了下载, 这是在 Task 真正开启下载过程的时候, 会触发 appendRunningTasks
     success 是 下载成功了, Task 真正下载成功的时候, 会触发 succeeded
     删除正在下载的任务, 是任务结束下载的时候触发. removeRunningTasks
     删除任务, 是用户主动点击了 cancel, 或者 remove 的时候触发.
     
     在这个类库里面, 下载成功的任务, 还是会保留在 task 列表里面.
     */
    enum MaintainTasksAction {
        case append(DownloadTask)
        case remove(DownloadTask)
        case succeeded(DownloadTask)
        case appendRunningTasks(DownloadTask)
        case removeRunningTasks(DownloadTask)
    }
    
    public let operationQueue: DispatchQueue
    
    public let cache: Cache
    
    public let identifier: String
    
    public var completionHandler: (() -> Void)?
    
    // 因为 Swfit 的语言特性, 其实是在 SessionConfiguration 中任何值被修改之后, 都会触发 set 方法.
    // 配置修改了之后, 会造成任务的停止.
    // 但已经开启的任务, 不会立马进行停止, 而是调用 task 的 suspend 方法, 在 reSchedule 里面, 判断所有的任务停止了之后, 才会调用 session 的 invalidate.
    // 在 Session invalidate 的 delegate 触发了之后, 才会在里面, 重新生成 Session, 然后把之前暂停的任务, 重新触发.
    // 包括在暂停过程中, 新添加的任务, 也是如此.
    // 因为网络相关 API 的延时性, 所以在这个库里面, 有很多的 will 状态, 在这些 will 状态到真正的 状态改变的过程中, 是通过各种回调方法, 来进行了状态维护.
    public var configuration: SessionConfiguration {
        get { protectedState.wrappedValue.configuration }
        set {
            operationQueue.sync {
                protectedState.write {
                    $0.configuration = newValue
                    if $0.status == .running {
                        // 当, 配置发生改变之后, 所有的任务都暂停.
                        totalSuspend()
                    }
                }
            }
        }
    }
    
    // 最为重要的一个数据盒子.
    private struct State {
        var logger: Logable
        var isControlNetworkActivityIndicator: Bool = true
        var configuration: SessionConfiguration {
            // 每当, Config 发生改变了之后, 其实应该触发所使用的 URLSession 的重新生成才对.
            didSet {
                guard !shouldCreatSession else { return }
                shouldCreatSession = true
                if status == .running {
                    if configuration.maxConcurrentTasksLimit
                        <= oldValue.maxConcurrentTasksLimit {
                        needRelaunchingTasks = runningTasks + tasks.filter { $0.status == .waiting }
                    } else {
                        needRelaunchingTasks = tasks.filter { $0.status == .waiting || $0.status == .running }
                    }
                } else {
                    session?.invalidateAndCancel()
                    session = nil
                }
            }
        }
        var session: URLSession?
        var shouldCreatSession: Bool = false
        var timer: DispatchSourceTimer?
        var status: Status = .waiting
        var taskMapper: [String: DownloadTask] = [String: DownloadTask]()
        // Task 的 CurrentRequest 可能改变, 也就是可能会出现重定向的行为.
        // 在 taskMapper, 以及 DownloadTask 里面, 存储的是 originURL.
        // urlMapper 里面, 存储的是 重定向后的 URL, 和 OriginURL 的映射关系.
        var urlMapper: [URL: URL] = [URL: URL]()
        
        // 所有的, 被 DownloadSessionManager 管理的 Task. 包括下载完成, 失败的.
        var tasks: [DownloadTask] = []
        // 正在被下载的 Task
        var runningTasks: [DownloadTask] = []
        // 下载成功的任务.
        var succeededTasks: [DownloadTask] = []
        
        // 之前 Session Invalidate 的时刻, 正在下载的任务, 以及还没有生产新的 URLSession 状态下, 新添加的下载任务.
        var needRelaunchingTasks: [DownloadTask] = []
        
        // 当前的下载速率, 这是通过定时器回调计算出来的.
        var speed: Int64 = 0
        var timeRemaining: Int64 = 0
        
        var progressExecuter: Executer<SessionManager>?
        var successExecuter: Executer<SessionManager>?
        var failureExecuter: Executer<SessionManager>?
        var completionExecuter: Executer<SessionManager>?
        var controlExecuter: Executer<SessionManager>?
    }
    
    
    private let protectedState: Protected<State>
    
    public var logger: Logable {
        get { protectedState.wrappedValue.logger }
        set { protectedState.write { $0.logger = newValue } }
    }
    
    public var isControlNetworkActivityIndicator: Bool {
        get { protectedState.wrappedValue.isControlNetworkActivityIndicator }
        set { protectedState.write { $0.isControlNetworkActivityIndicator = newValue } }
    }
    
    
    internal var shouldRun: Bool {
        return runningTasks.count < configuration.maxConcurrentTasksLimit
    }
    
    private var session: URLSession? {
        get { protectedState.wrappedValue.session }
        set { protectedState.write { $0.session = newValue } }
    }
    
    private var currentURLSessionIsDirty: Bool {
        get { protectedState.wrappedValue.shouldCreatSession }
        set { protectedState.write { $0.shouldCreatSession = newValue } }
    }
    
    
    private var timer: DispatchSourceTimer? {
        get { protectedState.wrappedValue.timer }
        set { protectedState.write { $0.timer = newValue } }
    }
    
    
    public private(set) var status: Status {
        get { protectedState.wrappedValue.status }
        set {
            protectedState.write { $0.status = newValue }
            if newValue == .willSuspend ||
                newValue == .willCancel ||
                newValue == .willRemove {
                return
            }
            log(.sessionManager(newValue.rawValue, manager: self))
        }
    }
    
    
    public private(set) var tasks: [DownloadTask] {
        get { protectedState.wrappedValue.tasks }
        set { protectedState.write { $0.tasks = newValue } }
    }
    
    private var runningTasks: [DownloadTask] {
        get { protectedState.wrappedValue.runningTasks }
        set { protectedState.write { $0.runningTasks = newValue } }
    }
    
    private var needRelaunchingTasks: [DownloadTask] {
        get { protectedState.wrappedValue.needRelaunchingTasks }
        set { protectedState.write { $0.needRelaunchingTasks = newValue } }
    }
    
    public private(set) var succeededTasks: [DownloadTask] {
        get { protectedState.wrappedValue.succeededTasks }
        set { protectedState.write { $0.succeededTasks = newValue } }
    }
    
    private let _progress = Progress()
    // 每次, 获取 progress 的时候, 都会更新一下 _progress 中的数值.
    public var progress: Progress {
        _progress.completedUnitCount = tasks.reduce(0, { $0 + $1.progress.completedUnitCount })
        _progress.totalUnitCount = tasks.reduce(0, { $0 + $1.progress.totalUnitCount })
        return _progress
    }
    
    public private(set) var speed: Int64 {
        get { protectedState.wrappedValue.speed }
        set { protectedState.write { $0.speed = newValue } }
    }
    
    public var speedString: String {
        speed.tr.convertSpeedToString()
    }
    
    
    public private(set) var timeRemaining: Int64 {
        get { protectedState.wrappedValue.timeRemaining }
        set { protectedState.write { $0.timeRemaining = newValue } }
    }
    
    public var timeRemainingString: String {
        timeRemaining.tr.convertTimeToString()
    }
    
    private var progressExecuter: Executer<SessionManager>? {
        get { protectedState.wrappedValue.progressExecuter }
        set { protectedState.write { $0.progressExecuter = newValue } }
    }
    
    private var successExecuter: Executer<SessionManager>? {
        get { protectedState.wrappedValue.successExecuter }
        set { protectedState.write { $0.successExecuter = newValue } }
    }
    
    private var failureExecuter: Executer<SessionManager>? {
        get { protectedState.wrappedValue.failureExecuter }
        set { protectedState.write { $0.failureExecuter = newValue } }
    }
    
    private var completionExecuter: Executer<SessionManager>? {
        get { protectedState.wrappedValue.completionExecuter }
        set { protectedState.write { $0.completionExecuter = newValue } }
    }
    
    private var controlExecuter: Executer<SessionManager>? {
        get { protectedState.wrappedValue.controlExecuter }
        set { protectedState.write { $0.controlExecuter = newValue } }
    }
    
    public init(_ identifier: String,
                configuration: SessionConfiguration,
                logger: Logable? = nil,
                cache: Cache? = nil,
                operationQueue: DispatchQueue = DispatchQueue(label: "com.Tiercel.SessionManager.operationQueue",
                                                              autoreleaseFrequency: .workItem)) {
        
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.Daniels.Tiercel"
        self.identifier = "\(bundleIdentifier).\(identifier)"
        protectedState = Protected(
            // 这个 Logger 可以自定义话, 这也是面向抽象编程的好处.
            State(logger: logger ?? Logger(identifier: "\(bundleIdentifier).\(identifier)", option: .default),
                  configuration: configuration)
        )
        self.operationQueue = operationQueue
        self.cache = cache ?? Cache(identifier)
        self.cache.manager = self
        /*
         在 SessionManager 的初始化过程中, 会到对应的文件位置, 读取文件, 恢复对于下载任务的管理.
         任务的状态也在文件系统里面, 所以, tasks 里面会有所有的任务信息.
         */
        self.cache.retrieveAllTasks().forEach { maintainTasks(with: .append($0)) }
        succeededTasks = tasks.filter { $0.status == .succeeded }
        
        protectedState.write { state in
            state.tasks.forEach {
                $0.manager = self
                // 这里, Task 的 Queue 和 Session 的 Queue 是一个 Queue 了.
                $0.operationQueue = operationQueue
                state.urlMapper[$0.currentURL] = $0.url
            }
            state.shouldCreatSession = true
        }
        
        operationQueue.sync {
            createSession()
            retriveRuningTaskInBGDownloading()
        }
    }
    
    deinit {
        invalidate()
    }
    
    public func invalidate() {
        session?.invalidateAndCancel()
        session = nil
        cache.invalidate()
        invalidateTimer()
    }
    
    private func createSession(_ completion: (() -> ())? = nil) {
        guard currentURLSessionIsDirty else { return }
        
        // 最为重要的部分, 使用 background 进行了下载的动作.
        /*
         Use this method to initialize a configuration object suitable for transferring data files while the app runs in the background.
         A session configured with this object hands control of the transfers over to the system, which handles the transfers in a separate process. In iOS, this configuration makes it possible for transfers to continue even when the app itself is suspended or terminated.
         If an iOS app is terminated by the system and relaunched, the app can use the same identifier to create a new configuration object and session and to retrieve the status of transfers that were in progress at the time of termination. This behavior applies only for normal termination of the app by the system. If the user terminates the app from the multitasking screen, the system cancels all of the session’s background transfers. In addition, the system does not automatically relaunch apps that were force quit by the user. The user must explicitly relaunch the app before transfers can begin again.
         You can configure an background session to schedule transfers at the discretion of the system for optimal performance using the isDiscretionary property. When transferring large amounts of data, you are encouraged to set the value of this property to true. For an example of using the background configuration, see Downloading Files in the Background.
         */
        let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: identifier)
        /*
         This property determines the request timeout interval for all tasks within sessions based on this configuration. The request timeout interval controls how long (in seconds) a task should wait for additional data to arrive before giving up. The timer associated with this value is reset whenever new data arrives. When the request timer reaches the specified interval without receiving any new data, it triggers a timeout.
         The default value is 60.
         Important
         Any upload or download tasks created by a background session are automatically retried if the original request fails due to a timeout. To configure how long an upload or download task should be allowed to be retried or transferred, use the timeoutIntervalForResource property.
         */
        // 这个值控制的是, URL Loading 的过程中, 不断的接收到网络数据中的间隔事件. 而不是整体的 Loading 时间.
        // 有一个 TimeoutForResource 是固定的, 整体的 Loading 时间.
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeoutIntervalForRequest
        sessionConfiguration.httpMaximumConnectionsPerHost = 100000
        sessionConfiguration.allowsCellularAccess = configuration.allowsCellularAccess
        if #available(iOS 13, macOS 10.15, *) {
            sessionConfiguration.allowsConstrainedNetworkAccess = configuration.allowsConstrainedNetworkAccess
            sessionConfiguration.allowsExpensiveNetworkAccess = configuration.allowsExpensiveNetworkAccess
        }
        let sessionDelegate = SessionDelegate()
        sessionDelegate.manager = self
        // 网络请求的事件, 都是使用的串行队列. 因为本身这就是一个有着时间先后的事件处理机制.
        // 如果使用并发队列, data 来临后, 后续的 data 事件在前面的闭包事件中被处理了, 那么拼接数据的时候, 就出错了.
        
        // 所有的网络回调, 都在一个队列中完成.
        let delegateQueue = OperationQueue(maxConcurrentOperationCount: 1,
                                           underlyingQueue: operationQueue,
                                           name: "com.Tiercel.SessionManager.delegateQueue")
        protectedState.write {
            let session = URLSession(configuration: sessionConfiguration,
                                     delegate: sessionDelegate,
                                     delegateQueue: delegateQueue)
            $0.session = session
            $0.tasks.forEach { $0.session = session }
            $0.shouldCreatSession = false
        }
        completion?()
    }
}


// MARK: - download
extension SessionManager {
    /// 开启一个下载任务
    ///
    /// - Parameters:
    ///   - url: URLConvertible
    ///   - headers: headers
    ///   - fileName: 下载文件的文件名，如果传nil，则默认为url的md5加上文件扩展名
    /// - Returns: 如果url有效，则返回对应的task；如果url无效，则返回nil
    @discardableResult
    public func download(_ url: URLConvertible,
                         headers: [String: String]? = nil,
                         fileName: String? = nil,
                         onMainQueue: Bool = true,
                         handler: Handler<DownloadTask>? = nil) -> DownloadTask? {
        // 处理 Throw 是一个应该习以为常的事情.
        do {
            let validURL = try url.asURL()
            var task: DownloadTask!
            
            operationQueue.sync {
                task = fetchTask(validURL)
                if let task = task {
                    // 仅仅是做, 对应数据的替换而已.
                    // 因为这个 Filename 仅仅是最后进行文件拷贝的时候才会触发, 所以不会造成太大的问题.
                    task.update(headers, newFileName: fileName)
                } else {
                    task = DownloadTask(validURL,
                                        headers: headers,
                                        fileName: fileName,
                                        // 新创建的 cache, 也是 Session 的 Cache.
                                        cache: cache,
                                        // 新创建的 Queue, 也是 Session 的 queue
                                        operationQueue: operationQueue)
                    task.manager = self
                    task.session = session
                    maintainTasks(with: .append(task))
                }
                // 在对应的地方, 进行维护任务的序列化处理.
                storeTasks()
                start(task, onMainQueue: onMainQueue, handler: handler)
            }
            return task
        } catch {
            // 在内层函数的设计的时候, 使用 throw 的机制, 然后在对外的接口里面, 使用 optional 的设计.
            log(.error("create dowloadTask failed", error: error))
            return nil
        }
    }
    
    
    /// 批量开启多个下载任务, 所有任务都会并发下载
    ///
    /// - Parameters:
    ///   - urls: [URLConvertible]
    ///   - headers: headers
    ///   - fileNames: 下载文件的文件名，如果传nil，则默认为url的md5加上文件扩展名
    /// - Returns: 返回url数组中有效url对应的task数组
    @discardableResult
    public func multiDownload(_ urls: [URLConvertible],
                              headersArray: [[String: String]]? = nil,
                              fileNames: [String]? = nil,
                              onMainQueue: Bool = true,
                              handler: Handler<SessionManager>? = nil) -> [DownloadTask] {
        if let headersArray = headersArray,
           headersArray.count != 0 && headersArray.count != urls.count {
            log(.error("create multiple dowloadTasks failed", error: TiercelError.headersMatchFailed))
            return [DownloadTask]()
        }
        
        if let fileNames = fileNames,
           fileNames.count != 0 && fileNames.count != urls.count {
            log(.error("create multiple dowloadTasks failed", error: TiercelError.fileNamesMatchFailed))
            return [DownloadTask]()
        }
        
        var urlSet = Set<URL>()
        var uniqueTasks = [DownloadTask]()
        
        // 批量的, 将任务添加到自己的管理中.
        operationQueue.sync {
            for (index, url) in urls.enumerated() {
                let fileName = fileNames?.safeObject(at: index)
                let headers = headersArray?.safeObject(at: index)
                
                guard let validURL = try? url.asURL() else {
                    log(.error("create dowloadTask failed", error: TiercelError.invalidURL(url: url)))
                    continue
                }
                guard urlSet.insert(validURL).inserted else {
                    log(.error("create dowloadTask failed", error: TiercelError.duplicateURL(url: url)))
                    continue
                }
                
                var task: DownloadTask!
                task = fetchTask(validURL)
                if let task = task {
                    task.update(headers, newFileName: fileName)
                } else {
                    task = DownloadTask(validURL,
                                        headers: headers,
                                        fileName: fileName,
                                        cache: cache,
                                        operationQueue: operationQueue)
                    task.manager = self
                    task.session = session
                    maintainTasks(with: .append(task))
                }
                uniqueTasks.append(task)
            }
            storeTasks()
            Executer(onMainQueue: onMainQueue, handler: handler).execute(self)
            // 将, 刚刚添加进入的所有的任务, 一次性开启下载操作.
            // 但是不会真正的全部开启, 内部会有对于最大可开启量的限制的.
            operationQueue.async {
                uniqueTasks.forEach {
                    if $0.status != .succeeded {
                        self._start($0)
                    }
                }
            }
        }
        return uniqueTasks
    }
}

// MARK: - single task control
extension SessionManager {
    
    public func fetchTask(_ url: URLConvertible) -> DownloadTask? {
        do {
            let validURL = try url.asURL()
            return protectedState.read { $0.taskMapper[validURL.absoluteString] }
        } catch {
            log(.error("fetch task failed", error: TiercelError.invalidURL(url: url)))
            return nil
        }
    }
    
    internal func mapTask(_ currentURL: URL) -> DownloadTask? {
        protectedState.read {
            // URLSessionTask 的 URL 可能会变, 应该是有着重定向的原因.
            let url = $0.urlMapper[currentURL] ?? currentURL
            return $0.taskMapper[url.absoluteString]
        }
    }
    
    /// 开启任务
    /// 会检查存放下载完成的文件中是否存在跟fileName一样的文件
    /// 如果存在则不会开启下载，直接调用task的successHandler
    public func start(_ url: URLConvertible, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        operationQueue.async {
            self._start(url, onMainQueue: onMainQueue, handler: handler)
        }
    }
    
    public func start(_ task: DownloadTask, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        operationQueue.async {
            guard let _ = self.fetchTask(task.url) else {
                self.log(.error("can't start downloadTask", error: TiercelError.fetchDownloadTaskFailed(url: task.url)))
                return
            }
            self._start(task, onMainQueue: onMainQueue, handler: handler)
        }
    }
    
    private func _start(_ url: URLConvertible, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        guard let task = self.fetchTask(url) else {
            log(.error("can't start downloadTask", error: TiercelError.fetchDownloadTaskFailed(url: url)))
            return
        }
        _start(task, onMainQueue: onMainQueue, handler: handler)
    }
    
    private func _start(_ task: DownloadTask,
                        onMainQueue: Bool = true,
                        handler: Handler<DownloadTask>? = nil) {
        task.controlExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        didStart()
        if !currentURLSessionIsDirty {
            task.download()
        } else {
            task.status = .suspended
            if !needRelaunchingTasks.contains(task) {
                needRelaunchingTasks.append(task)
            }
        }
    }
    
    
    /// 暂停任务，会触发sessionDelegate的完成回调
    public func suspend(_ url: URLConvertible, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        operationQueue.async {
            guard let task = self.fetchTask(url) else {
                self.log(.error("can't suspend downloadTask", error: TiercelError.fetchDownloadTaskFailed(url: url)))
                return
            }
            task.suspend(onMainQueue: onMainQueue, handler: handler)
        }
    }
    
    public func suspend(_ task: DownloadTask, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        operationQueue.async {
            guard let _ = self.fetchTask(task.url) else {
                self.log(.error("can't suspend downloadTask", error: TiercelError.fetchDownloadTaskFailed(url: task.url)))
                return
            }
            task.suspend(onMainQueue: onMainQueue, handler: handler)
        }
    }
    
    /// 取消任务
    /// 不会对已经完成的任务造成影响
    /// 其他状态的任务都可以被取消，被取消的任务会被移除
    /// 会删除还没有下载完成的缓存文件
    /// 会触发sessionDelegate的完成回调
    public func cancel(_ url: URLConvertible, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        operationQueue.async {
            guard let task = self.fetchTask(url) else {
                self.log(.error("can't cancel downloadTask", error: TiercelError.fetchDownloadTaskFailed(url: url)))
                return
            }
            task.cancel(onMainQueue: onMainQueue, handler: handler)
        }
    }
    
    public func cancel(_ task: DownloadTask, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        operationQueue.async {
            guard let _ = self.fetchTask(task.url) else {
                self.log(.error("can't cancel downloadTask", error: TiercelError.fetchDownloadTaskFailed(url: task.url)))
                return
            }
            task.cancel(onMainQueue: onMainQueue, handler: handler)
        }
    }
    
    
    /// 移除任务
    /// 所有状态的任务都可以被移除
    /// 会删除还没有下载完成的缓存文件
    /// 可以选择是否删除下载完成的文件
    /// 会触发sessionDelegate的完成回调
    ///
    /// - Parameters:
    ///   - url: URLConvertible
    ///   - completely: 是否删除下载完成的文件
    public func remove(_ url: URLConvertible, completely: Bool = false, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        operationQueue.async {
            guard let task = self.fetchTask(url) else {
                self.log(.error("can't remove downloadTask", error: TiercelError.fetchDownloadTaskFailed(url: url)))
                return
            }
            task.remove(completely: completely, onMainQueue: onMainQueue, handler: handler)
        }
    }
    
    public func remove(_ task: DownloadTask, completely: Bool = false, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        operationQueue.async {
            guard let _ = self.fetchTask(task.url) else {
                self.log(.error("can't remove downloadTask", error: TiercelError.fetchDownloadTaskFailed(url: task.url)))
                return
            }
            task.remove(completely: completely, onMainQueue: onMainQueue, handler: handler)
        }
    }
    
    public func moveTask(at sourceIndex: Int, to destinationIndex: Int) {
        operationQueue.sync {
            let range = (0..<tasks.count)
            guard range.contains(sourceIndex) && range.contains(destinationIndex) else {
                log(.error("move task failed, sourceIndex: \(sourceIndex), destinationIndex: \(destinationIndex)",
                           error: TiercelError.indexOutOfRange))
                return
            }
            if sourceIndex == destinationIndex {
                return
            }
            protectedState.write {
                let task = $0.tasks[sourceIndex]
                $0.tasks.remove(at: sourceIndex)
                $0.tasks.insert(task, at: destinationIndex)
            }
        }
    }
    
}

// MARK: - total tasks control
// Total 的行为, 就是将 tasks 相关的任务, 进行遍历.
extension SessionManager {
    // 全部开始下载任务.
    public func totalStart(onMainQueue: Bool = true, handler: Handler<SessionManager>? = nil) {
        operationQueue.async {
            self.tasks.forEach { task in
                if task.status != .succeeded {
                    self._start(task)
                }
            }
            Executer(onMainQueue: onMainQueue, handler: handler).execute(self)
        }
    }
    
    public func totalSuspend(onMainQueue: Bool = true, handler: Handler<SessionManager>? = nil) {
        operationQueue.async {
            guard self.status == .running || self.status == .waiting else { return }
            self.status = .willSuspend
            self.controlExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
            self.tasks.forEach { $0.suspend() }
        }
    }
    
    public func totalCancel(onMainQueue: Bool = true, handler: Handler<SessionManager>? = nil) {
        operationQueue.async {
            guard self.status != .succeeded && self.status != .canceled else { return }
            self.status = .willCancel
            self.controlExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
            self.tasks.forEach { $0.cancel() }
        }
    }
    
    public func totalRemove(completely: Bool = false, onMainQueue: Bool = true, handler: Handler<SessionManager>? = nil) {
        operationQueue.async {
            guard self.status != .removed else { return }
            self.status = .willRemove
            self.controlExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
            self.tasks.forEach { $0.remove(completely: completely) }
        }
    }
    
    public func tasksSort(by areInIncreasingOrder: (DownloadTask, DownloadTask) throws -> Bool) rethrows {
        try operationQueue.sync {
            try protectedState.write {
                try $0.tasks.sort(by: areInIncreasingOrder)
            }
        }
    }
}


// MARK: - status handle
extension SessionManager {
    
    internal func maintainTasks(with action: MaintainTasksAction) {
        switch action {
        case let .append(task):
            // 这是任务归到 Session Manager 下载的最初起点.
            protectedState.write { state in
                state.tasks.append(task)
                state.taskMapper[task.url.absoluteString] = task
                state.urlMapper[task.currentURL] = task.url
            }
        case let .remove(task):
            protectedState.write { state in
                if state.status == .willRemove {
                    state.taskMapper.removeValue(forKey: task.url.absoluteString)
                    state.urlMapper.removeValue(forKey: task.currentURL)
                    if state.taskMapper.values.isEmpty {
                        state.tasks.removeAll()
                        state.succeededTasks.removeAll()
                    }
                } else if state.status == .willCancel {
                    state.taskMapper.removeValue(forKey: task.url.absoluteString)
                    state.urlMapper.removeValue(forKey: task.currentURL)
                    if state.taskMapper.values.count == state.succeededTasks.count {
                        state.tasks = state.succeededTasks
                    }
                } else {
                    state.taskMapper.removeValue(forKey: task.url.absoluteString)
                    state.urlMapper.removeValue(forKey: task.currentURL)
                    state.tasks.removeAll {
                        $0.url.absoluteString == task.url.absoluteString
                    }
                    if task.status == .removed {
                        state.succeededTasks.removeAll {
                            $0.url.absoluteString == task.url.absoluteString
                        }
                    }
                }
            }
        case let .succeeded(task):
            succeededTasks.append(task)
        case let .appendRunningTasks(task):
            protectedState.write { state in
                state.runningTasks.append(task)
            }
        case let .removeRunningTasks(task):
            protectedState.write { state in
                state.runningTasks.removeAll {
                    $0.url.absoluteString == task.url.absoluteString
                }
            }
        }
    }
    
    internal func updateUrlMapper(with task: DownloadTask) {
        // 如果 DataTask 的 URL 发生了改变, 那么这里会进行一次映射.
        // Task.url 永远是最初的 url.
        protectedState.write { $0.urlMapper[task.currentURL] = task.url }
    }
    
    private func retriveRuningTaskInBGDownloading() {
        if self.tasks.isEmpty {
            return
        }
        /*
         之所以会出现这样一个奇怪的调用, 是因为真正的下载任务, 是在另外的一个线程里面.
         当 App 重启之后, 同名的 Session 可以通过 getTasksWithCompletionHandler 获取到当前正在下载的任务.
         所以, 在 App 重启之后, 可以第一时间, 根据当前的状态, 进行当前正在下载的任务的管理.
         */
        session?.getTasksWithCompletionHandler { [weak self] (dataTasks, uploadTasks, downloadTasks) in
            guard let self = self else { return }
            downloadTasks.forEach { sessionDownloadTask in
                if sessionDownloadTask.state == .running,
                   let currentURL = sessionDownloadTask.currentRequest?.url,
                   let task = self.mapTask(currentURL) {
                    // didStart 是触发 Manager 开始下载的回调.
                    self.didStart()
                    self.maintainTasks(with: .appendRunningTasks(task))
                    task.status = .running
                    task.sessionTask = sessionDownloadTask
                }
            }
            self.storeTasks()
            //  处理mananger状态
            if !self.isAllCompleted() {
                self.suspendIfNeed()
            }
        }
    }
    
    // get 函数内, 有了太多的副作用.
    private func isAllCompleted() -> Bool {
        let isSucceeded = self.tasks.allSatisfy { $0.status == .succeeded }
        let isCompleted = isSucceeded ? isSucceeded :
        self.tasks.allSatisfy { $0.status == .succeeded || $0.status == .failed }
        guard isCompleted else { return false }
        
        if status == .succeeded || status == .failed {
            return true
        }
        timeRemaining = 0
        progressExecuter?.execute(self)
        status = isSucceeded ? .succeeded : .failed
        executeCompletion(isSucceeded)
        return true
    }
    
    
    
    private func suspendIfNeed() {
        let isSuspended = tasks.allSatisfy { $0.status == .suspended || $0.status == .succeeded || $0.status == .failed }
        
        if isSuspended {
            if status == .suspended {
                return
            }
            status = .suspended
            executeControl()
            executeCompletion(false)
            if currentURLSessionIsDirty {
                session?.invalidateAndCancel()
                session = nil
            }
        }
    }
    
    internal func didStart() {
        if status != .running {
            createTimer()
            status = .running
            progressExecuter?.execute(self)
        }
    }
    
    internal func updateProgress() {
        if isControlNetworkActivityIndicator {
            DispatchQueue.tr.executeOnMain {
                UIApplication.shared.isNetworkActivityIndicatorVisible = true
            }
        }
        progressExecuter?.execute(self)
        NotificationCenter.default.postNotification(name: SessionManager.runningNotification, sessionManager: self)
    }
    
    internal func didCancelOrRemove(_ task: DownloadTask) {
        maintainTasks(with: .remove(task))
        
        // 没太明白这里的逻辑. ???
        if tasks.isEmpty {
            if task.status == .canceled {
                status = .willCancel
            }
            if task.status == .removed {
                status = .willRemove
            }
        }
    }
    
    internal func storeTasks() {
        cache.storeTasks(tasks)
    }
    
    // DownloadTask 里面, 会触发 Manager 的 Schedule 的操作.
    internal func reScheduleWhenTaskComplete(fromDownloading: Bool) {
        if isControlNetworkActivityIndicator {
            DispatchQueue.tr.executeOnMain {
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            }
        }
        
        // removed
        if status == .willRemove {
            // 当, 调用 totalRemove 的时候, 会将当前的状态, 设置为 willRemove
            // 然后会不断的调用 Task 的 Remove 方法.
            // 当 Task 完成了 Remove 操作之后, 会回到该方法. 完成镇针对各 Remvoed 状态的改变.
            if tasks.isEmpty {
                status = .removed
                executeControl()
                markAllTaskEnding(false)
            }
            return
        }
        
        // canceled
        if status == .willCancel {
            let succeededTasksCount = protectedState.wrappedValue.taskMapper.values.count
            // 这个时候, 只会存留 success, 或者 failed 的任务了.
            if tasks.count == succeededTasksCount {
                status = .canceled
                executeControl()
                markAllTaskEnding(false)
                return
            }
            return
        }
        
        // completed
        let isCompleted = tasks.allSatisfy { $0.status == .succeeded || $0.status == .failed }
        
        if isCompleted {
            if status == .succeeded || status == .failed {
                storeTasks()
                return
            }
            timeRemaining = 0
            progressExecuter?.execute(self)
            let isSucceeded = tasks.allSatisfy { $0.status == .succeeded }
            status = isSucceeded ? .succeeded : .failed
            markAllTaskEnding(isSucceeded)
            return
        }
        
        // suspended
        // 当, Config 变化了之后, 会停止所有的任务.
        let isSuspended = tasks.allSatisfy { $0.status == .suspended ||
            $0.status == .succeeded ||
            $0.status == .failed }
        
        if isSuspended {
            if status == .suspended {
                storeTasks()
                return
            }
            status = .suspended
            // 如果, 所有的任务都停止了, 并且 shouldCreatSession
            // 那么就是 config 变化导致的停止. 废弃当前的 Session, 新创建 urlSession, 重新开启由于 Config 变化导致suspend 的任务
            if currentURLSessionIsDirty {
                session?.invalidateAndCancel()
                session = nil
            } else {
                // 否则, 就是任务都结束了, 执行结束的状态改变就可以了.
                executeControl()
                markAllTaskEnding(false)
            }
            return
        }
        
        if status == .willSuspend {
            return
        }
        
        storeTasks()
        
        // 如果是 fromRunningTask, 就是下载过程中, 而不是用户主动行为触发的. 这种时候, 要进行任务调度, 进行新的任务.
        // 否则, 是用户点击触发的, 那么上面的状态修改了之后, 不应该触发后续的行为.
        if fromDownloading {
            // next task
            operationQueue.async {
                self.startNextTask()
            }
        }
    }
    
    private func markAllTaskEnding(_ isSucceeded: Bool) {
        executeCompletion(isSucceeded)
        storeTasks()
        invalidateTimer()
    }
    
    // 在做完上面所有的操作之后, 进行新的任务的下载.
    private func startNextTask() {
        guard let waitingTask = tasks.first (where: { $0.status == .waiting }) else { return }
        waitingTask.download()
    }
}

// MARK: - info
extension SessionManager {
    
    static let refreshInterval: Double = 1
    
    // 这个 Timer, 感觉没有太大的作用啊.
    private func createTimer() {
        if timer == nil {
            timer = DispatchSource.makeTimerSource(flags: .strict, queue: operationQueue)
            timer?.schedule(deadline: .now(), repeating: Self.refreshInterval)
            timer?.setEventHandler(handler: { [weak self] in
                guard let self = self else { return }
                self.updateSpeedAndTimeRemaining()
            })
            timer?.resume()
        }
    }
    
    private func invalidateTimer() {
        timer?.cancel()
        timer = nil
    }
    
    internal func updateSpeedAndTimeRemaining() {
        let speed = runningTasks.reduce(Int64(0), {
            $1.updateSpeedAndTimeRemaining()
            return $0 + $1.speed
        })
        updateTimeRemaining(speed)
    }
    
    private func updateTimeRemaining(_ speed: Int64) {
        var timeRemaining: Double
        if speed != 0 {
            timeRemaining = (Double(progress.totalUnitCount) - Double(progress.completedUnitCount)) / Double(speed)
            if timeRemaining >= 0.8 && timeRemaining < 1 {
                timeRemaining += 1
            }
        } else {
            timeRemaining = 0
        }
        
        protectedState.write {
            $0.speed = speed
            $0.timeRemaining = Int64(timeRemaining)
        }
    }
    
    internal func log(_ type: LogType) {
        logger.log(type)
    }
}

// MARK: - closure
// 动作的收集过程. 
extension SessionManager {
    @discardableResult
    public func progress(onMainQueue: Bool = true, handler: @escaping Handler<SessionManager>) -> Self {
        progressExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        return self
    }
    
    @discardableResult
    public func success(onMainQueue: Bool = true, handler: @escaping Handler<SessionManager>) -> Self {
        successExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if status == .succeeded  && completionExecuter == nil{
            operationQueue.async {
                self.successExecuter?.execute(self)
            }
        }
        return self
    }
    
    @discardableResult
    public func failure(onMainQueue: Bool = true, handler: @escaping Handler<SessionManager>) -> Self {
        failureExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if completionExecuter == nil &&
            (status == .suspended ||
             status == .canceled ||
             status == .removed ||
             status == .failed) {
            operationQueue.async {
                self.failureExecuter?.execute(self)
            }
        }
        return self
    }
    
    @discardableResult
    public func completion(onMainQueue: Bool = true, handler: @escaping Handler<SessionManager>) -> Self {
        completionExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if status == .suspended ||
            status == .canceled ||
            status == .removed ||
            status == .succeeded ||
            status == .failed  {
            operationQueue.async {
                self.completionExecuter?.execute(self)
            }
        }
        return self
    }
    
    private func executeCompletion(_ isSucceeded: Bool) {
        if let completionExecuter = completionExecuter {
            completionExecuter.execute(self)
        } else if isSucceeded {
            successExecuter?.execute(self)
        } else {
            failureExecuter?.execute(self)
        }
        NotificationCenter.default.postNotification(name: SessionManager.didCompleteNotification, sessionManager: self)
    }
    
    private func executeControl() {
        controlExecuter?.execute(self)
        controlExecuter = nil
    }
}


// MARK: - call back
extension SessionManager {
    // 没太明白这里在干什么.
    internal func didBecomeInvalidation(withError error: Error?) {
        createSession { [weak self] in
            guard let self = self else { return }
            self.needRelaunchingTasks.forEach { self._start($0) }
            self.needRelaunchingTasks.removeAll()
        }
    }
    
    // 这个就是
    internal func didFinishEvents(forBackgroundURLSession session: URLSession) {
        // 必须在主线程调用. 文档里面明确进行了说明.
        DispatchQueue.tr.executeOnMain {
            self.completionHandler?()
            self.completionHandler = nil
        }
    }
}


