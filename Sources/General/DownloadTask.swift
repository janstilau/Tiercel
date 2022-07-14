import UIKit

public class DownloadTask: Task<DownloadTask> {
    private enum CodingKeys: CodingKey {
        case resumeData
        case response
    }
    
    private var _sessionTask: URLSessionDownloadTask? {
        willSet {
            _sessionTask?.removeObserver(self, forKeyPath: "currentRequest")
        }
        didSet {
            _sessionTask?.addObserver(self, forKeyPath: "currentRequest", options: [.new], context: nil)
        }
    }
    
    private struct DownloadState {
        var resumeData: Data? {
            didSet {
                guard let resumeData = resumeData else { return }
                tmpFileName = ResumeDataHelper.getTmpFileName(resumeData)
            }
        }
        var response: HTTPURLResponse?
        
        // 下面的两个属性, 不进行序列化.
        var tmpFileName: String?
        var shouldValidateFile: Bool = false
    }
    private let protectedDownloadState: Protected<DownloadState> = Protected(DownloadState())
    
    internal init(_ url: URL,
                  headers: [String: String]? = nil,
                  fileName: String? = nil,
                  cache: Cache,
                  operationQueue: DispatchQueue) {
        super.init(url,
                   headers: headers,
                   cache: cache,
                   operationQueue: operationQueue)
        if let fileName = fileName, !fileName.isEmpty {
            self.fileName = fileName
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(fixDelegateMethodError),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }
    
    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // 通过 SuperEncoder 的方式, 其实是使得 Super 的内容, 和 JSON 中的 Super 字段绑定在了一起.
        let superEncoder = container.superEncoder()
        try super.encode(to: superEncoder)
        
        try container.encodeIfPresent(resumeData, forKey: .resumeData)
        if let response = response {
            let responseData: Data
            if #available(iOS 11.0, *) {
                responseData = try NSKeyedArchiver.archivedData(withRootObject: (response as HTTPURLResponse), requiringSecureCoding: true)
            } else {
                responseData = NSKeyedArchiver.archivedData(withRootObject: (response as HTTPURLResponse))
            }
            try container.encode(responseData, forKey: .response)
        }
    }
    
    internal required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let superDecoder = try container.superDecoder()
        try super.init(from: superDecoder)
        resumeData = try container.decodeIfPresent(Data.self, forKey: .resumeData)
        if let responseData = try container.decodeIfPresent(Data.self, forKey: .response) {
            if #available(iOS 11.0, *) {
                response = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HTTPURLResponse.self, from: responseData)
            } else {
                response = NSKeyedUnarchiver.unarchiveObject(with: responseData) as? HTTPURLResponse
            }
        }
    }
    
    deinit {
        sessionTask?.removeObserver(self, forKeyPath: "currentRequest")
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func fixDelegateMethodError() {
        // 理由呢???
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sessionTask?.suspend()
            self.sessionTask?.resume()
        }
    }
    
    internal override func execute(_ executer: Executer<DownloadTask>?) {
        executer?.execute(self)
    }
}

extension DownloadTask {
    private var acceptableStatusCodes: Range<Int> { return 200..<300 }
    
    internal var sessionTask: URLSessionDownloadTask? {
        get { protectedDownloadState.read { _ in _sessionTask }}
        set { protectedDownloadState.write { _ in _sessionTask = newValue }}
    }
    
    public private(set) var response: HTTPURLResponse? {
        get { protectedDownloadState.wrappedValue.response }
        set { protectedDownloadState.write { $0.response = newValue } }
    }
    
    public var filePath: String {
        return cache.filePath(fileName: fileName)!
    }
    
    public var pathExtension: String? {
        let pathExtension = (filePath as NSString).pathExtension
        return pathExtension.isEmpty ? nil : pathExtension
    }
    
    private var resumeData: Data? {
        get { protectedDownloadState.wrappedValue.resumeData }
        set { protectedDownloadState.write { $0.resumeData = newValue } }
    }
    
    internal var tmpFileName: String? {
        protectedDownloadState.wrappedValue.tmpFileName
    }
    
    private var shouldValidateFile: Bool {
        get { protectedDownloadState.wrappedValue.shouldValidateFile }
        set { protectedDownloadState.write { $0.shouldValidateFile = newValue } }
    }
}


// MARK: - control
extension DownloadTask {
    
    internal func download() {
        cache.createDirectory()
        guard let manager = manager else { return }
        
        switch status {
        case .waiting, .suspended, .failed:
            // 只有下载完成之后, 才会把文件移交过去.
            // 所以, fileExist 一定是下载成功了.
            // 之所以会有这种情况, 是因为可能会有重复的下载任务
            if cache.fileExists(fileName: fileName) {
                prepareForDownload(fileExists: true)
            } else {
                if manager.shouldRun {
                    prepareForDownload(fileExists: false)
                } else {
                    status = .waiting
                    progressExecuter?.execute(self)
                    executeControl()
                }
            }
        case .succeeded:
            executeControl()
            succeeded(fromRunning: false, immediately: false)
        case .running:
            status = .running
            executeControl()
        default: break
        }
    }
    
    private func prepareForDownload(fileExists: Bool) {
        status = .running
        protectedState.write {
            $0.speed = 0
            if $0.startDate == 0 {
                $0.startDate = Date().timeIntervalSince1970
            }
        }
        error = nil
        response = nil
        start(fileExists: fileExists)
    }
    
    private func start(fileExists: Bool) {
        if fileExists {
            manager?.log(.downloadTask("file already exists", task: self))
            if let fileInfo = try? FileManager.default.attributesOfItem(atPath: cache.filePath(fileName: fileName)!),
               let length = fileInfo[.size] as? Int64 {
                progress.totalUnitCount = length
            }
            executeControl()
            // 在, 完成了意向任务之后, 主动调用调度算法.
            operationQueue.async {
                self.didComplete(.local)
            }
        } else {
            if let resumeData = resumeData,
               cache.retrieveTmpFile(tmpFileName) {
                // retrieveTmpFile 中, 会尝试进行已经下载数据的恢复.
                if #available(iOS 10.2, *) {
                    sessionTask = session?.downloadTask(withResumeData: resumeData)
                } else if #available(iOS 10.0, *) {
                    sessionTask = session?.correctedDownloadTask(withResumeData: resumeData)
                } else {
                    sessionTask = session?.downloadTask(withResumeData: resumeData)
                }
            } else {
                // 没有 resume 的数据, 直接重新下.
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 0)
                // header 的作用, 在这里被用到了.
                if let headers = headers {
                    request.allHTTPHeaderFields = headers
                }
                sessionTask = session?.downloadTask(with: request)
                progress.completedUnitCount = 0
                progress.totalUnitCount = 0
            }
            // 真正的, 进行下载任务的开启.
            progress.setUserInfoObject(progress.completedUnitCount, forKey: .fileCompletedCountKey)
            sessionTask?.resume()
            manager?.maintainTasks(with: .appendRunningTasks(self))
            manager?.storeTasks()
            executeControl()
        }
    }
    
    internal func suspend(onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        guard status == .running || status == .waiting else { return }
        controlExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if status == .running {
            status = .willSuspend
            sessionTask?.cancel(byProducingResumeData: { _ in })
        } else {
            status = .willSuspend
            operationQueue.async {
                self.didComplete(.local)
            }
        }
    }
    
    internal func cancel(onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        guard status != .succeeded else { return }
        controlExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if status == .running {
            status = .willCancel
            sessionTask?.cancel()
        } else {
            status = .willCancel
            operationQueue.async {
                self.didComplete(.local)
            }
        }
    }
    
    internal func remove(completely: Bool = false, onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        isRemoveCompletely = completely
        controlExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if status == .running {
            status = .willRemove
            sessionTask?.cancel()
        } else {
            status = .willRemove
            operationQueue.async {
                self.didComplete(.local)
            }
        }
    }
    
    internal func update(_ newHeaders: [String: String]? = nil, newFileName: String? = nil) {
        headers = newHeaders
        if let newFileName = newFileName,
           !newFileName.isEmpty {
            cache.updateFileName(filePath, newFileName)
            fileName = newFileName
        }
    }
    
    private func validateFile() {
        guard let validateHandler = self.validateExecuter else { return }
        
        if !shouldValidateFile {
            validateHandler.execute(self)
            return
        }
        
        guard let verificationCode = verificationCode else { return }
        
        FileChecksumHelper.validateFile(filePath, code: verificationCode, type: verificationType) {
            [weak self] (result) in
            guard let self = self else { return }
            
            self.shouldValidateFile = false
            if case let .failure(error) = result {
                self.validationResult = .incorrect
                self.manager?.log(.error("file validation failed, url: \(self.url)", error: error))
            } else {
                self.validationResult = .correct
                self.manager?.log(.downloadTask("file validation successful", task: self))
            }
            self.manager?.storeTasks()
            validateHandler.execute(self)
        }
    }
}


// MARK: - status handle
extension DownloadTask {
    private func didCancelOrRemove() {
        // 把预操作的状态改成完成操作的状态
        if status == .willCancel {
            status = .canceled
        }
        if status == .willRemove {
            status = .removed
        }
        cache.remove(self, completely: isRemoveCompletely)
        manager?.didCancelOrRemove(self)
    }
    
    // FromRunning 指的是, 从正在运行的网络任务中成功了.
    // 如果是本地缓存中, 则是 false.
    internal func succeeded(fromRunning: Bool, immediately: Bool) {
        if endDate == 0 {
            protectedState.write {
                // 成功了, 进行完成事件的赋值.
                $0.endDate = Date().timeIntervalSince1970
                $0.timeRemaining = 0
            }
        }
        // 进行状态的改变.
        status = .succeeded
        // 进行完成进度的改变.
        progress.completedUnitCount = progress.totalUnitCount
        // 完成进度回调. 使用 Executer 来执行, 因为里面有线程回调.
        progressExecuter?.execute(self)
        if immediately {
            executeCompletion(true)
        }
        validateFile()
        manager?.maintainTasks(with: .succeeded(self))
        manager?.determineStatus(fromRunningTask: fromRunning)
    }
    
    // 触发时机, 一般都在子线程中. 因为, 一般都是在 Session 的 Delegate 方法中, 触发相关的操作.
    private func determineStatus(with interruptType: InterruptType) {
        var fromRunning = true
        switch interruptType {
        case let .error(error):
            self.error = error
            var tempStatus = status
            if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                // 在这里, 进行了 ResumeData 的存储动作.
                self.resumeData = ResumeDataHelper.handleResumeData(resumeData)
                cache.storeTmpFile(tmpFileName)
            }
            if let _ = (error as NSError).userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? Int {
                tempStatus = .suspended
            }
            if let urlError = error as? URLError, urlError.code != URLError.cancelled {
                tempStatus = .failed
            }
            status = tempStatus
        case let .statusCode(statusCode):
            self.error = TiercelError.unacceptableStatusCode(code: statusCode)
            status = .failed
        case let .manual(fromRunningTask):
            fromRunning = fromRunningTask
        }
        
        switch status {
        case .willSuspend:
            status = .suspended
            progressExecuter?.execute(self)
            executeControl()
            executeCompletion(false)
        case .willCancel, .willRemove:
            didCancelOrRemove()
            executeControl()
            executeCompletion(false)
        case .suspended, .failed:
            progressExecuter?.execute(self)
            executeCompletion(false)
        default:
            status = .failed
            progressExecuter?.execute(self)
            executeCompletion(false)
        }
        manager?.determineStatus(fromRunningTask: fromRunning)
    }
}

// MARK: - closure
extension DownloadTask {
    @discardableResult
    public func validateFile(code: String,
                             type: FileChecksumHelper.VerificationType,
                             onMainQueue: Bool = true,
                             handler: @escaping Handler<DownloadTask>) -> Self {
        operationQueue.async {
            let (verificationCode, verificationType) = self.protectedState.read {
                ($0.verificationCode, $0.verificationType)
            }
            if verificationCode == code &&
                verificationType == type &&
                self.validationResult != .unkown {
                // 这代表的是, 已经验证过了.
                self.shouldValidateFile = false
            } else {
                // 更换了验证的方式, 对验证的方式进行存储.
                self.shouldValidateFile = true
                self.protectedState.write {
                    $0.verificationCode = code
                    $0.verificationType = type
                }
                // 这种, 原子操作到一个文件列表中, 一个文件信息的更改, 就是整体的一个操作.
                self.manager?.storeTasks()
            }
            // ValidateFile 这段代码, 最终还是添加逻辑到对应的时间节点中, 然后在对应的时候, 取出相应的节点, 进行逻辑回调的触发.
            self.validateExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
            if self.status == .succeeded {
                // 如果, 当前的状态已经成功了, 直接触发.
                self.validateFile()
            }
        }
        return self
    }
    
    private func executeCompletion(_ isSucceeded: Bool) {
        // Complete 的优先级最高.
        if let completionExecuter = completionExecuter {
            completionExecuter.execute(self)
        } else if isSucceeded {
            successExecuter?.execute(self)
        } else {
            failureExecuter?.execute(self)
        }
        NotificationCenter.default.postNotification(name: DownloadTask.didCompleteNotification, downloadTask: self)
    }
    
    private func executeControl() {
        controlExecuter?.execute(self)
        controlExecuter = nil
    }
}


// MARK: - KVO
extension DownloadTask {
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let change = change, let newRequest = change[NSKeyValueChangeKey.newKey] as? URLRequest, let url = newRequest.url {
            currentURL = url
            manager?.updateUrlMapper(with: self)
        }
    }
}

// MARK: - info
extension DownloadTask {
    
    internal func updateSpeedAndTimeRemaining() {
        
        let dataCount = progress.completedUnitCount
        let lastData: Int64 = progress.userInfo[.fileCompletedCountKey] as? Int64 ?? 0
        
        if dataCount > lastData {
            let speed = dataCount - lastData
            updateTimeRemaining(speed)
        }
        progress.setUserInfoObject(dataCount, forKey: .fileCompletedCountKey)
        
    }
    
    // timeRemaining 的多少, 是根据 Speed 以及剩余量来完成的.
    // 明确的写出一个 Update 的函数来, 使得某个属性的修改, 有了一个可以追踪的点. 
    private func updateTimeRemaining(_ speed: Int64) {
        var timeRemaining: Double
        if speed != 0 {
            timeRemaining = (Double(progress.totalUnitCount) - Double(progress.completedUnitCount)) / Double(speed)
            if 0.8 <= timeRemaining && timeRemaining < 1 {
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
}

// MARK: - callback
extension DownloadTask {
    internal func didWriteData(downloadTask: URLSessionDownloadTask, bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress.completedUnitCount = totalBytesWritten
        progress.totalUnitCount = totalBytesExpectedToWrite
        response = downloadTask.response as? HTTPURLResponse
        progressExecuter?.execute(self)
        manager?.updateProgress()
        NotificationCenter.default.postNotification(name: DownloadTask.runningNotification, downloadTask: self)
    }
    
    
    internal func didFinishDownloading(task: URLSessionDownloadTask, to location: URL) {
        guard let statusCode = (task.response as? HTTPURLResponse)?.statusCode,
              acceptableStatusCodes.contains(statusCode)
        else { return }
        cache.storeFile(at: location, to: URL(fileURLWithPath: filePath))
        cache.removeTmpFile(tmpFileName)
    }
    
    internal func didComplete(_ type: CompletionType) {
        switch type {
        case .local:
            // 本地就已经有了下载的文件了.
            switch status {
            case .willSuspend, .willCancel, .willRemove:
                // 在修改为以上的状态之后, 会触发 didComplete 方法.
                determineStatus(with: .manual(false))
            case .running:
                succeeded(fromRunning: false, immediately: true)
            default:
                return
            }
            
            // 这种场景, 仅仅会在 Session 的 Delegate 中出现.
            // ResumeData 的数据, 也是从 Error 中获取出来的.
        case let .network(task, error):
            manager?.maintainTasks(with: .removeRunningTasks(self))
            sessionTask = nil
            
            switch status {
            case .willCancel, .willRemove:
                // cancel, remove, 不会直接进行数据的操作, 而是等待 delegate 方法, 在 delegate 方法的回调中, 统一进行数据的修改. s
                determineStatus(with: .manual(true))
                return
            case .willSuspend, .running:
                progress.totalUnitCount = task.countOfBytesExpectedToReceive
                progress.completedUnitCount = task.countOfBytesReceived
                progress.setUserInfoObject(task.countOfBytesReceived, forKey: .fileCompletedCountKey)
                
                let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? -1
                let isAcceptable = acceptableStatusCodes.contains(statusCode)
                
                if error != nil {
                    response = task.response as? HTTPURLResponse
                    determineStatus(with: .error(error!))
                } else if !isAcceptable {
                    response = task.response as? HTTPURLResponse
                    determineStatus(with: .statusCode(statusCode))
                } else {
                    resumeData = nil
                    succeeded(fromRunning: true, immediately: true)
                }
            default:
                return
            }
        }
    }
    
}

extension Array where Element == DownloadTask {
    @discardableResult
    public func progress(onMainQueue: Bool = true, handler: @escaping Handler<DownloadTask>) -> [Element] {
        self.forEach { $0.progress(onMainQueue: onMainQueue, handler: handler) }
        return self
    }
    
    @discardableResult
    public func success(onMainQueue: Bool = true, handler: @escaping Handler<DownloadTask>) -> [Element] {
        self.forEach { $0.success(onMainQueue: onMainQueue, handler: handler) }
        return self
    }
    
    @discardableResult
    public func failure(onMainQueue: Bool = true, handler: @escaping Handler<DownloadTask>) -> [Element] {
        self.forEach { $0.failure(onMainQueue: onMainQueue, handler: handler) }
        return self
    }
    
    public func validateFile(codes: [String],
                             type: FileChecksumHelper.VerificationType,
                             onMainQueue: Bool = true,
                             handler: @escaping Handler<DownloadTask>) -> [Element] {
        for (index, task) in self.enumerated() {
            guard let code = codes.safeObject(at: index) else { continue }
            task.validateFile(code: code, type: type, onMainQueue: onMainQueue, handler: handler)
        }
        return self
    }
}
