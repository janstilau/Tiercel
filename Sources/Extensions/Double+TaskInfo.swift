import Foundation

extension Double: TiercelCompatible {}

// Double 的 Extension. 因为时间戳也是 Double 类型的, 所以直接将方法, 添加到了这里面. 
extension TiercelWrapper where Base == Double {
    /// 返回 yyyy-MM-dd HH:mm:ss格式的字符串
    ///
    /// - Returns:
    public func convertTimeToDateString() -> String {
        let date = Date(timeIntervalSince1970: base)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
