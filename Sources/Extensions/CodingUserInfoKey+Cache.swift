import Foundation

extension CodingUserInfoKey {
    // Coder 的 UserInfo 里面, 是需要使用专门的 Key 来当做 Key 值的.
    // 专门定义一个类型, 来做这件事情.
    internal static let cache = CodingUserInfoKey(rawValue: "com.Tiercel.CodingUserInfoKey.cache")!
    
    // 这个 Key, 在 App 内部, 没有被使用到. 
    internal static let operationQueue = CodingUserInfoKey(rawValue: "com.Tiercel.CodingUserInfoKey.operationQueue")!
}
