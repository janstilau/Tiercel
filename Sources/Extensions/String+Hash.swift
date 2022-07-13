import Foundation

extension String: TiercelCompatible { }
extension TiercelWrapper where Base == String {
    public var md5: String {
        guard let data = base.data(using: .utf8) else {
            return base
        }
        return data.tr.md5
    }
    
    public var sha1: String {
        guard let data = base.data(using: .utf8) else {
            return base
        }
        return data.tr.sha1
    }
    
    public var sha256: String {
        guard let data = base.data(using: .utf8) else {
            return base
        }
        return data.tr.sha256
    }
    
    public var sha512: String {
        guard let data = base.data(using: .utf8) else {
            return base
        }
        return data.tr.sha512
    }
}
