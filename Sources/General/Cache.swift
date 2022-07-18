import Foundation

// 使用了一个专门的类, 来做文件读取这回事.
public class Cache {
    
    private let ioQueue: DispatchQueue
    
    // 该功能, 目前仅仅是用到了 StoreTasks 的实现里面. 存储任务的当前状态, 可能会是一个数据类过大的事情, 应该减少对应的频次.
    private var debouncer: Debouncer
    
    public let downloadPath: String
    
    public let downloadTmpPath: String
    
    public let downloadFilePath: String
    
    public let identifier: String
    
    private let fileManager = FileManager.default
    
    private let encoder = JSONEncoder()
    
    private let decoder = JSONDecoder()
    
    // 目前, 该值仅仅用在了 Log 系统里面.
    internal weak var manager: SessionManager?
    
    public static func defaultDiskCachePathClosure(_ cacheName: String) -> String {
        let dstPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        return (dstPath as NSString).appendingPathComponent(cacheName)
    }
    
    
    /// 初始化方法
    /// - Parameters:
    ///   - identifier: 不同的identifier代表不同的下载模块。如果没有自定义下载目录，Cache会提供默认的目录，这些目录跟identifier相关
    /// 下面的几个属性, 都有着默认的实现.
    ///   - downloadPath: 存放用于DownloadTask持久化的数据，默认提供的downloadTmpPath、downloadFilePath也是在里面
    ///   - downloadTmpPath: 存放下载中的临时文件
    ///   - downloadFilePath: 存放下载完成后的文件
    public init(_ identifier: String,
                downloadPath: String? = nil,
                downloadTmpPath: String? = nil,
                downloadFilePath: String? = nil) {
        self.identifier = identifier
        
        // ioQueue 是一个串行队列. 这个队列, 是和 SessionManager 中的队列没有任何关系的.
        let ioQueueName = "com.Tiercel.Cache.ioQueue.\(identifier)"
        ioQueue = DispatchQueue(label: ioQueueName, autoreleaseFrequency: .workItem)
        
        debouncer = Debouncer(queue: ioQueue)
        
        let cacheName = "com.Daniels.Tiercel.Cache.\(identifier)"
        // 这个东西, 就是在外界没有传入下载地址的时候, 当做 Download 的默认值.
        let diskCachePath = Cache.defaultDiskCachePathClosure(cacheName)
        
        // temp, file 是 downloadPath 的下级.
        let downloadPath = downloadPath ?? (diskCachePath as NSString).appendingPathComponent("Downloads")
        self.downloadPath = downloadPath
        self.downloadTmpPath = downloadTmpPath ?? (downloadPath as NSString).appendingPathComponent("Tmp")
        self.downloadFilePath = downloadFilePath ?? (downloadPath as NSString).appendingPathComponent("File")
        
        createDirectory()
        // 第一次看到, userInfo 真正的被使用到了
        decoder.userInfo[.cache] = self
        
        print("The Cache Path is \(downloadPath)")
    }
    
    public func invalidate() {
        decoder.userInfo[.cache] = nil
    }
}


// MARK: - file
extension Cache {
    // 预先创建所需要的目录结构.
    internal func createDirectory() {
        if !fileManager.fileExists(atPath: downloadPath) {
            do {
                try fileManager.createDirectory(atPath: downloadPath, withIntermediateDirectories: true, attributes: nil)
            } catch  {
                manager?.log(.error("create directory failed",
                                    error: TiercelError.cacheError(reason: .cannotCreateDirectory(path: downloadPath,
                                                                                                  error: error))))
            }
        }
        
        if !fileManager.fileExists(atPath: downloadTmpPath) {
            do {
                try fileManager.createDirectory(atPath: downloadTmpPath, withIntermediateDirectories: true, attributes: nil)
            } catch  {
                manager?.log(.error("create directory failed",
                                    error: TiercelError.cacheError(reason: .cannotCreateDirectory(path: downloadTmpPath,
                                                                                                  error: error))))
            }
        }
        
        if !fileManager.fileExists(atPath: downloadFilePath) {
            do {
                try fileManager.createDirectory(atPath: downloadFilePath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                manager?.log(.error("create directory failed",
                                    error: TiercelError.cacheError(reason: .cannotCreateDirectory(path: downloadFilePath,
                                                                                                  error: error))))
            }
        }
    }
    
    
    public func filePath(fileName: String) -> String? {
        if fileName.isEmpty {
            return nil
        }
        let path = (downloadFilePath as NSString).appendingPathComponent(fileName)
        return path
    }
    
    public func fileURL(fileName: String) -> URL? {
        guard let path = filePath(fileName: fileName) else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    public func fileExists(fileName: String) -> Bool {
        guard let path = filePath(fileName: fileName) else { return false }
        return fileManager.fileExists(atPath: path)
    }
    
    public func filePath(url: URLConvertible) -> String? {
        do {
            let validURL = try url.asURL()
            let fileName = validURL.tr.fileName
            return filePath(fileName: fileName)
        } catch {
            return nil
        }
    }
    
    public func fileURL(url: URLConvertible) -> URL? {
        guard let path = filePath(url: url) else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    public func fileExists(url: URLConvertible) -> Bool {
        guard let path = filePath(url: url) else { return false }
        return fileManager.fileExists(atPath: path)
    }
    
    public func clearDiskCache(onMainQueue: Bool = true, handler: Handler<Cache>? = nil) {
        ioQueue.async {
            guard self.fileManager.fileExists(atPath: self.downloadPath) else { return }
            do {
                try self.fileManager.removeItem(atPath: self.downloadPath)
            } catch {
                self.manager?.log(.error("clear disk cache failed",
                                         error: TiercelError.cacheError(reason: .cannotRemoveItem(path: self.downloadPath,
                                                                                                  error: error))))
            }
            self.createDirectory()
            if let handler = handler {
                // 这里, 专门定义一个 Executer, 其实是为了线程调度.
                Executer(onMainQueue: onMainQueue, handler: handler).execute(self)
            }
        }
    }
}


// MARK: - retrieve
extension Cache {
    // 恢复, 所有存储起来的下载任务.
    // 这是在 Session 初始化的时候需要进行的. 要把所有的下载任务, 添加到 Session 的队列中去.
    internal func retrieveAllTasks() -> [DownloadTask] {
        // 因为这是一个同步函数, 所以这里选择了 sync.
        return ioQueue.sync {
            let path = (downloadPath as NSString).appendingPathComponent("\(identifier)_Tasks.json")
            if fileManager.fileExists(atPath: path) {
                do {
                    let url = URL(fileURLWithPath: path)
                    let data = try Data(contentsOf: url)
                    let tasks = try decoder.decode([DownloadTask].self, from: data)
                    tasks.forEach { (task) in
                        // 既然这里, 又进行了赋值操作, 那么 Task 里面的 cache 根本就不应该参与到归档解档的流程里面.
                        task.cache = self
                        if task.status == .waiting  {
                            // 不太明白, 为什么将解档会生成的 Task 的状态进行改变.
                            // Queue 和 model 的状态所并不冲突. 不会有死锁问题.
                            // 在各自的领域, 完成对于数据的保护.
                            task.protectedState.write { $0.status = .suspended }
                        }
                    }
                    return tasks
                } catch {
                    manager?.log(.error("retrieve all tasks failed", error: TiercelError.cacheError(reason: .cannotRetrieveAllTasks(path: path, error: error))))
                    return [DownloadTask]()
                }
            } else {
                return  [DownloadTask]()
            }
        }
    }
    
    /*
     下载, 系统默认的是下载到了 Tmp 目录下, 而这个目录, 会被系统清理的.
     这件事在 iOS 15 里感觉发生了变化, 路径变为了 /Library/Caches/com.apple.nsurlsessiond/Downloads/bundlename 了
     
     所以, 在 storeTmpFile 中, 会将 Tmp 目录下的数据, 转存一份到沙盒环境里面.
     这里, 当使用 ResumeData 恢复下载的时候, 会尝试检查 Temp 下有没有下载文件.
     如果没有, 会使用沙盒中缓存的文件, 移动到 Temp 中. 因为 ResumeData 的数据是定死的, 所以一定是要移动到 Temp 目录下.
     */
    internal func retrieveTmpFile(_ tmpFileName: String?) -> Bool {
        return ioQueue.sync {
            guard let tmpFileName = tmpFileName, !tmpFileName.isEmpty else { return false }
            
            let backupFilePath = (downloadTmpPath as NSString).appendingPathComponent(tmpFileName)
            let originFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(tmpFileName)
            let backupFileExists = fileManager.fileExists(atPath: backupFilePath)
            let originFileExists = fileManager.fileExists(atPath: originFilePath)
            guard backupFileExists || originFileExists else { return false }
            
            if originFileExists {
                do {
                    try fileManager.removeItem(atPath: backupFilePath)
                } catch {
                    self.manager?.log(.error("retrieve tmpFile failed",
                                             error: TiercelError.cacheError(reason: .cannotRemoveItem(path: backupFilePath,
                                                                                                      error: error))))
                }
            } else {
                do {
                    try fileManager.moveItem(atPath: backupFilePath, toPath: originFilePath)
                } catch {
                    self.manager?.log(.error("retrieve tmpFile failed",
                                             error: TiercelError.cacheError(reason: .cannotMoveItem(atPath: backupFilePath,
                                                                                                    toPath: originFilePath,
                                                                                                    error: error))))
                }
            }
            return true
        }
    }
}

/*
 // 在里面, 是将当前的状态也存储到了文件系统里面.
 "super": {
 "url": "https:\/\/officecdn-microsoft-com.akamaized.net\/pr\/C1297A47-86C4-4C1F-97FA-950631F94777\/MacAutoupdate\/Microsoft_Office_16.24.19041401_Installer.pkg",
 "status": "running",
 "endDate": 0,
 "fileName": "66ad306db5e053544041f8b64cdfbaac.pkg",
 "startDate": 1658079710.3194971,
 "verificationType": 0,
 "totalBytes": 1761188833,
 "completedBytes": 3069533,
 "validation": 0,
 "currentURL": "https:\/\/officecdn-microsoft-com.akamaized.net\/pr\/C1297A47-86C4-4C1F-97FA-950631F94777\/MacAutoupdate\/Microsoft_Office_16.24.19041401_Installer.pkg"
 },
 */
// MARK: - store
extension Cache {
    // 把所有的下载任务, 当做了文件进行了存储.
    internal func storeTasks(_ tasks: [DownloadTask]) {
        // 把, 所有的任务, 都使用文件进行了存储.
        debouncer.execute(label: "storeTasks", wallDeadline: .now() + 0.2) {
            var path = (self.downloadPath as NSString).appendingPathComponent("\(self.identifier)_Tasks.json")
            do {
                let data = try self.encoder.encode(tasks)
                let url = URL(fileURLWithPath: path)
                try data.write(to: url)
            } catch {
                self.manager?.log(.error("store tasks failed",
                                         error: TiercelError.cacheError(reason: .cannotEncodeTasks(path: path,
                                                                                                   error: error))))
            }
            path = (self.downloadPath as NSString).appendingPathComponent("\(self.identifier)Tasks.json")
            try? self.fileManager.removeItem(atPath: path)
        }
    }
    
    // 这里应该叫做 move.
    internal func storeFile(at srcURL: URL, to dstURL: URL) {
        ioQueue.sync {
            do {
                try fileManager.moveItem(at: srcURL, to: dstURL)
            } catch {
                self.manager?.log(.error("store file failed",
                                         error: TiercelError.cacheError(reason: .cannotMoveItem(atPath: srcURL.absoluteString,
                                                                                                toPath: dstURL.absoluteString,
                                                                                                error: error))))
            }
        }
    }
    
    internal func storeTmpFile(_ tmpFileName: String?) {
        // 将, Temp 目录下的下载文件, 转移到 Session 的管理目录/Tmp 下.
        ioQueue.sync {
            guard let tmpFileName = tmpFileName, !tmpFileName.isEmpty else { return }
            let tmpPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(tmpFileName)
            let destination = (downloadTmpPath as NSString).appendingPathComponent(tmpFileName)
            if fileManager.fileExists(atPath: destination) {
                do {
                    try fileManager.removeItem(atPath: destination)
                } catch {
                    self.manager?.log(.error("store tmpFile failed",
                                             error: TiercelError.cacheError(reason: .cannotRemoveItem(path: destination,
                                                                                                      error: error))))
                }
            }
            if fileManager.fileExists(atPath: tmpPath) {
                do {
                    try fileManager.copyItem(atPath: tmpPath, toPath: destination)
                } catch {
                    self.manager?.log(.error("store tmpFile failed",
                                             error: TiercelError.cacheError(reason: .cannotCopyItem(atPath: tmpPath,
                                                                                                    toPath: destination,
                                                                                                    error: error))))
                }
            }
        }
    }
    
    // 如果已经下载完了, 那么就会做一个文件的搬移动作.
    // 没有的话, 下载完成之后, 搬移 temp 文件的时候, 会使用新的名称来当做文件的名称. 
    internal func updateFileName(_ filePath: String, _ newFileName: String) {
        ioQueue.sync {
            if fileManager.fileExists(atPath: filePath) {
                let newFilePath = self.filePath(fileName: newFileName)!
                do {
                    try fileManager.moveItem(atPath: filePath, toPath: newFilePath)
                } catch {
                    self.manager?.log(.error("update fileName failed",
                                             error: TiercelError.cacheError(reason: .cannotMoveItem(atPath: filePath,
                                                                                                    toPath: newFilePath,
                                                                                                    error: error))))
                }
            }
        }
    }
}


// MARK: - remove
extension Cache {
    internal func remove(_ task: DownloadTask, completely: Bool) {
        removeTmpFile(task.tmpFileName)
        
        if completely {
            removeFile(task.filePath)
        }
    }
    
    internal func removeFile(_ filePath: String) {
        ioQueue.async {
            if self.fileManager.fileExists(atPath: filePath) {
                do {
                    try self.fileManager.removeItem(atPath: filePath)
                } catch {
                    self.manager?.log(.error("remove file failed",
                                             error: TiercelError.cacheError(reason: .cannotRemoveItem(path: filePath,
                                                                                                      error: error))))
                }
            }
        }
    }
    
    
    
    /// 删除保留在本地的缓存文件
    ///
    /// - Parameter task:
    internal func removeTmpFile(_ tmpFileName: String?) {
        ioQueue.async {
            guard let tmpFileName = tmpFileName, !tmpFileName.isEmpty else { return }
            let path1 = (self.downloadTmpPath as NSString).appendingPathComponent(tmpFileName)
            let path2 = (NSTemporaryDirectory() as NSString).appendingPathComponent(tmpFileName)
            [path1, path2].forEach { (path) in
                if self.fileManager.fileExists(atPath: path) {
                    do {
                        try self.fileManager.removeItem(atPath: path)
                    } catch {
                        self.manager?.log(.error("remove tmpFile failed",
                                                 error: TiercelError.cacheError(reason: .cannotRemoveItem(path: path,
                                                                                                          error: error))))
                    }
                }
            }
            
        }
    }
}

extension URL: TiercelCompatible { }

// 使用, 地址的 MD5, 当做文件名, 并且在后面添加原有的文件扩展名. 
extension TiercelWrapper where Base == URL {
    public var fileName: String {
        var fileName = base.absoluteString.tr.md5
        if !base.pathExtension.isEmpty {
            fileName += ".\(base.pathExtension)"
        }
        return fileName
    }
}
