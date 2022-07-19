import UIKit

// 目前位置, Task 的唯一子类, 就是 DownloadTask.
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
        // 对于一个下载任务, 应该要存储一下当前的下载状态.
        var resumeData: Data? {
            didSet {
                guard let resumeData = resumeData else { return }
                // 可以从 ResumeData 里面, 获取之前下载的文件的文件名信息.
                // 当, 有 ResumeData 的时候, 会自动进行文件名的获取操作.
                tmpFileName = ResumeDataHelper.getTmpFileName(resumeData)
            }
        }
        // 对于一个下载任务, 应该要存储一下当前的响应状态.
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
    
    // 对于下载任务来说, 除了 dataTask 的那些状态之外, 还要存储一下下载相关的任务.
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
    
    // 使用 protectedDownloadState 里面的锁, 进行 DownloadTask 相关的状态管理.
    internal var sessionTask: URLSessionDownloadTask? {
        get { protectedDownloadState.read { _ in _sessionTask }}
        set { protectedDownloadState.write { _ in _sessionTask = newValue }}
    }
    
    // 使用 protectedDownloadState 里面的锁, 进行 DownloadTask 相关的状态管理.
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
                reset()
                didFileExisted()
            } else {
                if manager.shouldRun {
                    // 当前还没有触发最大下载数
                    // 真正的触发下载网络请求的部分.
                    reset()
                    startDownloadFile()
                } else {
                    // 当前已经到达了最大下载数
                    // 在 Task 完成的代码里面, 会触发 manager 的 reSchedule. 在那里会触发 waiting 状态的任务重新开启.
                    status = .waiting
                    progressExecuter?.execute(self)
                    executeControl()
                }
            }
        case .succeeded:
            executeControl()
            didTaskSuccessed(fromDownloading: false, triggerCompletion: false)
        case .running:
            status = .running
            executeControl()
        default: break
        }
    }
    
    private func reset() {
        status = .running
        protectedState.write {
            $0.speed = 0
            if $0.startDate == 0 {
                $0.startDate = Date().timeIntervalSince1970
            }
        }
        error = nil
        response = nil
    }
    
    private func startDownloadFile() {
        // 真正的开启一个下载任务的启动方法在这里.
        // 如果, 有resumeData这个值, 那么
        if let resumeData = resumeData,
           // 如果有 ResumeData, 首先要恢复原来的下载环境, 具体来说, 就是将原本的下载到 Tmp 目录下的文件数据恢复.
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
        // 在这里, 真正的进行了下载的任务启动.
        sessionTask?.resume()
        manager?.maintainTasks(with: .appendRunningTasks(self))
        manager?.storeTasks()
        executeControl()
    }
    
    private func didFileExisted() {
        if let fileInfo = try? FileManager.default.attributesOfItem(atPath: cache.filePath(fileName: fileName)!),
           let length = fileInfo[.size] as? Int64 {
            progress.totalUnitCount = length
        }
        executeControl()
        operationQueue.async {
            // 开启下载任务的时候, 发现该文件已经下载过了.
            // 直接本地完成该任务.
            self.didTaskCompleted(.local)
        }
    }
    
    /*
     实际上, DataTask 本身会有 Suspend 的相关逻辑, 但是这里是 Download. 对于 Download 来说, suspend 就是取消原来的下载, 然后保存 ResumeData 就可以了.
     这样, 重新 start 的时候, 使用 ResumeData 来重新创建一个下载任务就可以了.
     */
    internal func suspend(onMainQueue: Bool = true, handler: Handler<DownloadTask>? = nil) {
        guard status == .running || status == .waiting else { return }
        
        controlExecuter = Executer(onMainQueue: onMainQueue, handler: handler)
        if status == .running {
            status = .willSuspend
            // 之所以, 这里不使用 Resume, 是以为在 DidComplete 中, Error 信息中会带有 ResumeData 的相关内容.
            /*
             Summary
             
             Cancels a download and calls a callback with resume data for later use.
             
             Discussion
             A download can be resumed only if the following conditions are met:
             The resource has not changed since you first requested it
             The task is an HTTP or HTTPS GET request // Get 请求
             The server provides either the ETag or Last-Modified header (or both) in its response
             The server supports byte-range requests // 支持作用域范围下载.
             The temporary file hasn’t been deleted by the system in response to disk space pressure // 原有的下载文件没有被删除.
             Parameters
             
             completionHandler
             A completion handler that is called when the download has been successfully canceled.
             If the download is resumable, the completion handler is provided with a resumeData object. Your app can later pass this object to a session’s downloadTask(withResumeData:) or downloadTask(withResumeData:completionHandler:) method to create a new task that resumes the download where it left off.
             This block is not guaranteed to execute in a particular thread context. As such, you may want specify an appropriate dispatch queue in which to perform any work.
             */
            sessionTask?.cancel(byProducingResumeData: { _ in })
        } else {
            status = .willSuspend
            // 如果, 当前任务还没有开启, 直接本地完成.
            operationQueue.async {
                self.didTaskCompleted(.local)
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
                self.didTaskCompleted(.local)
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
                self.didTaskCompleted(.local)
            }
        }
    }
    
    internal func update(_ newHeaders: [String: String]? = nil,
                         newFileName: String? = nil) {
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
            } else {
                self.validationResult = .correct
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
    internal func didTaskSuccessed(fromDownloading: Bool, triggerCompletion: Bool) {
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
        if triggerCompletion {
            executeCompletion(true)
        }
        validateFile()
        manager?.maintainTasks(with: .succeeded(self))
        manager?.reScheduleWhenTaskComplete(fromDownloading: fromDownloading)
    }
    
    private func didTaskFailed(with interruptType: InterruptType) {
        var fromRunning = true
        switch interruptType {
        case let .error(error):
            self.error = error
            var tempStatus = status
            /*
             When a transfer error occurs or when you call the cancel(byProducingResumeData:) method, the delegate object or completion handler gets an NSError object. If the transfer is resumable, that error object’s userInfo dictionary contains a value for this key. To resume the transfer, your app can pass that value to the downloadTask(withResumeData:) or downloadTask(withResumeData:completionHandler:) method.
             */
            if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                // 在这里, 进行了 ResumeData 的存储动作.
                self.resumeData = ResumeDataHelper.handleResumeData(resumeData)
                cache.storeTmpFile(tmpFileName)
            }
            // A key in the error dictionary that provides the reason for canceling a background task.
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
        
        manager?.reScheduleWhenTaskComplete(fromDownloading: fromRunning)
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
                //                self.manager?.storeTasks()
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
    
    /*
     executeControl 的设计思路是, 我要去完成一件事, 并且提供这件事完成的回调.
     但是我要完成的这件事, 其实是一个异步操作.
     所以, 作者在这里设计了 controlExecuter 这样的一个存储闭包的方式, 统一在 Task 完成逻辑里面进行 executeControl 的触发.
     */
    // executeControl 就是触发用户设置的业务回调. 如果需要异步操作, 那么就在异步操作中触发, 如果不需要, 直接触发.
    private func executeControl() {
        controlExecuter?.execute(self)
        controlExecuter = nil
    }
}


// MARK: - KVO
extension DownloadTask {
    // 对于 DataTask 来说, 来下载的过程中, CurrentRequest 可能会变化.
    // 在这里, 专门监听这个变化, 将 Task 和新的 URL 进行匹配.
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
        let lastCompleteCount: Int64 = progress.userInfo[.fileCompletedCountKey] as? Int64 ?? 0
        
        if dataCount > lastCompleteCount {
            let speed = dataCount - lastCompleteCount
            updateTimeRemaining(speed)
        }
        // 可以通过 setUserInfoObject 这种方式, 藏一些值到 Progress 实例中.
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
    // SessionDelegate 会触发到这里, 在这里, 触发一下自己的下载总进度.
    internal func didWriteData(downloadTask: URLSessionDownloadTask, bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // 更新一下自己的进度信息.
        progress.completedUnitCount = totalBytesWritten
        progress.totalUnitCount = totalBytesExpectedToWrite
        response = downloadTask.response as? HTTPURLResponse
        progressExecuter?.execute(self)
        // 更新一下, 总的进度信息.
        // Data Task 的进度变化了, 会主动的触发 Manager 来更新自己的进度.
        manager?.updateProgress()
        NotificationCenter.default.postNotification(name: DownloadTask.runningNotification, downloadTask: self)
    }
    
    // 在下载完成的回调里面, 是完成了文件的移动工作.
    internal func didFinishDownloading(task: URLSessionDownloadTask, to location: URL) {
        guard let statusCode = (task.response as? HTTPURLResponse)?.statusCode,
              acceptableStatusCodes.contains(statusCode)
        else { return }
        // 将, 下载过程中, Tmp 目录下的文件, 转移到真正的存储目录下.
        // 然后, 清理一下下载过程中的临时文件.
        cache.storeFile(at: location, to: URL(fileURLWithPath: filePath))
        cache.removeTmpFile(tmpFileName)
    }
    
    internal func didTaskCompleted(_ type: CompletionType) {
        switch type {
        case .local: // 有程序逻辑, 引起了 Complete 的逻辑触发.
            switch status {
            case .willSuspend, .willCancel, .willRemove:
                didTaskFailed(with: .manual(false))
            case .running:
                didTaskSuccessed(fromDownloading: false, triggerCompletion: true)
            default:
                return
            }
            // 这种场景, 仅仅会在 Session 的 Delegate 中出现.
            // ResumeData 的数据, 也是从 Error 中获取出来的.
        case let .network(task, error):
            // 在这里, 就已经把网络下载完的任务从  runing 中删除了.
            manager?.maintainTasks(with: .removeRunningTasks(self))
            sessionTask = nil
            
            switch status {
            case .willCancel, .willRemove:
                // 当 Cancel, Remove 主动调用的时候, 不会直接触发, 而是使用 DataTask 的 cancel 方法, 等待 URLSession 的 Delegate 触发到这里.
                // 如果当前的状态, 是以上两种, 就是用户主动行为.
                didTaskFailed(with: .manual(true))
                return
            case .willSuspend, .running:
                progress.totalUnitCount = task.countOfBytesExpectedToReceive
                progress.completedUnitCount = task.countOfBytesReceived
                progress.setUserInfoObject(task.countOfBytesReceived, forKey: .fileCompletedCountKey)
                
                let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? -1
                let isAcceptable = acceptableStatusCodes.contains(statusCode)
                
                if error != nil {
                    response = task.response as? HTTPURLResponse
                    didTaskFailed(with: .error(error!))
                } else if !isAcceptable {
                    response = task.response as? HTTPURLResponse
                    didTaskFailed(with: .statusCode(statusCode))
                } else {
                    resumeData = nil
                    didTaskSuccessed(fromDownloading: true, triggerCompletion: true)
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
