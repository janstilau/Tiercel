import Foundation
import CommonCrypto

extension Data: TiercelCompatible { }

/*
 使用 base 来获取数据, 不直接在 String 上定义扩展方法. 
 */
extension TiercelWrapper where Base == Data {
    public var md5: String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = base.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            return CC_MD5(bytes.baseAddress, CC_LONG(base.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    public var sha1: String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        _ = base.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            return CC_SHA1(bytes.baseAddress, CC_LONG(base.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    public var sha256: String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = base.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            return CC_SHA256(bytes.baseAddress, CC_LONG(base.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    public var sha512: String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        _ = base.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            return CC_SHA512(bytes.baseAddress, CC_LONG(base.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
