import Foundation

// 将, 库中所有的错误, 统一使用了一个 Error 类型进行了管理.
public enum TiercelError: Error {
    
    public enum CacheErrorReason {
        case cannotCreateDirectory(path: String, error: Error)
        case cannotRemoveItem(path: String, error: Error)
        case cannotCopyItem(atPath: String, toPath: String, error: Error)
        case cannotMoveItem(atPath: String, toPath: String, error: Error)
        case cannotRetrieveAllTasks(path: String, error: Error)
        case cannotEncodeTasks(path: String, error: Error)
        case fileDoesnotExist(path: String)
        case readDataFailed(path: String)
    }
    
    case unknown
    case invalidURL(url: URLConvertible)
    case duplicateURL(url: URLConvertible)
    case indexOutOfRange
    case fetchDownloadTaskFailed(url: URLConvertible)
    case headersMatchFailed
    case fileNamesMatchFailed
    case unacceptableStatusCode(code: Int)
    case cacheError(reason: CacheErrorReason)
}

extension TiercelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknown:
            return "unkown error"
        case let .invalidURL(url):
            return "URL is not valid: \(url)"
        case let .duplicateURL(url):
            return "URL is duplicate: \(url)"
        case .indexOutOfRange:
            return "index out of range"
        case let .fetchDownloadTaskFailed(url):
            return "did not find downloadTask in sessionManager: \(url)"
        case .headersMatchFailed:
            return "HeaderArray.count != urls.count"
        case .fileNamesMatchFailed:
            return "FileNames.count != urls.count"
        case let .unacceptableStatusCode(code):
            return "Response status code was unacceptable: \(code)"
        case let .cacheError(reason):
            return reason.errorDescription
        }
    }
}

extension TiercelError: CustomNSError {
    
    public static let errorDomain: String = "com.Daniels.Tiercel.Error"
    
    public var errorCode: Int {
        if case .unacceptableStatusCode = self {
            return 1001
        } else {
            return -1
        }
    }
    
    public var errorUserInfo: [String: Any] {
        if let errorDescription = errorDescription {
            return [NSLocalizedDescriptionKey: errorDescription]
        } else {
            return [String: Any]()
        }
        
    }
}

extension TiercelError.CacheErrorReason {
    
    public var errorDescription: String? {
        switch self {
        case let .cannotCreateDirectory(path, error):
            return "can not create directory, path: \(path), underlying: \(error)"
        case let .cannotRemoveItem(path, error):
            return "can not remove item, path: \(path), underlying: \(error)"
        case let .cannotCopyItem(atPath, toPath, error):
            return "can not copy item, atPath: \(atPath), toPath: \(toPath), underlying: \(error)"
        case let .cannotMoveItem(atPath, toPath, error):
            return "can not move item atPath: \(atPath), toPath: \(toPath), underlying: \(error)"
        case let .cannotRetrieveAllTasks(path, error):
            return "can not retrieve all tasks, path: \(path), underlying: \(error)"
        case let .cannotEncodeTasks(path, error):
            return "can not encode tasks, path: \(path), underlying: \(error)"
        case let .fileDoesnotExist(path):
            return "file does not exist, path: \(path)"
        case let .readDataFailed(path):
            return "read data failed, path: \(path)"
        }
    }
    
    
}



