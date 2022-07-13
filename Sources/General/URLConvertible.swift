import Foundation

// 这里应该是抄的 Alamofire
public protocol URLConvertible {
    // throw 的设计, 是 Swfit 里面, 非常非常常见的一种设计思路.
    func asURL() throws -> URL
}

extension String: URLConvertible {
    public func asURL() throws -> URL {
        guard let url = URL(string: self) else { throw TiercelError.invalidURL(url: self) }
        return url
    }
}

extension URL: URLConvertible {
    public func asURL() throws -> URL { return self }
}

extension URLComponents: URLConvertible {
    public func asURL() throws -> URL {
        guard let url = url else { throw TiercelError.invalidURL(url: self) }
        return url
    }
}
