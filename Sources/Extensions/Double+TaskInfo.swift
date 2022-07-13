import Foundation

extension Double: TiercelCompatible {}
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
