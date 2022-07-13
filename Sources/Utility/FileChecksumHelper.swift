import Foundation

// 这是一个工具类, 提供了类似下载文件的签名验证的功能 .
public enum FileChecksumHelper {
    public enum VerificationType : Int {
        case md5
        case sha1
        case sha256
        case sha512
    }
    
    // 在运转的流程过程中, 出现的任何错误, 都使用 Error 进行了定义. 这让外界的使用者, 有了更好地使用策略.
    public enum FileVerificationError: Error {
        case codeEmpty
        case codeMismatch(code: String)
        case fileDoesnotExist(path: String)
        case readDataFailed(path: String)
    }
    
    private static let ioQueue: DispatchQueue = DispatchQueue(label: "com.Tiercel.FileChecksumHelper.ioQueue",
                                                              attributes: .concurrent)
    
    public static func validateFile(_ filePath: String,
                                    code: String,
                                    type: VerificationType,
                                    completion: @escaping (Result<Bool, FileVerificationError>) -> ()) {
        if code.isEmpty {
            completion(.failure(FileVerificationError.codeEmpty))
            return
        }
        ioQueue.async {
            guard FileManager.default.fileExists(atPath: filePath) else {
                completion(.failure(FileVerificationError.fileDoesnotExist(path: filePath)))
                return
            }
            let url = URL(fileURLWithPath: filePath)
            
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                var string: String
                switch type {
                case .md5:
                    string = data.tr.md5
                case .sha1:
                    string = data.tr.sha1
                case .sha256:
                    string = data.tr.sha256
                case .sha512:
                    string = data.tr.sha512
                }
                // 根据, 不同的 Type, 来获取不同的签名值, 然后进行字符串的比较. 
                let isCorrect = string.lowercased() == code.lowercased()
                if isCorrect {
                    completion(.success(true))
                } else {
                    completion(.failure(FileVerificationError.codeMismatch(code: code)))
                }
            } catch {
                completion(.failure(FileVerificationError.readDataFailed(path: filePath)))
            }
        }
    }
}



extension FileChecksumHelper.FileVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .codeEmpty:
            return "verification code is empty"
        case let .codeMismatch(code):
            return "verification code mismatch, code: \(code)"
        case let .fileDoesnotExist(path):
            return "file does not exist, path: \(path)"
        case let .readDataFailed(path):
            return "read data failed, path: \(path)"
        }
    }
    
}


