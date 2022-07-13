import Foundation

extension Int64: TiercelCompatible {}

extension TiercelWrapper where Base == Int64 {
    
    /// 返回下载速度的字符串，如：1MB/s
    ///
    /// - Returns:
    public func convertSpeedToString() -> String {
        let size = convertBytesToString()
        // 用字符串拼接的方式, 不应该更好一点吗.
        return [size, "s"].joined(separator: "/")
    }
    
    /// 返回 00：00格式的字符串
    ///
    /// - Returns:
    public func convertTimeToString() -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        return formatter.string(from: TimeInterval(base)) ?? ""
    }
    
    /// 返回字节大小的字符串
    ///
    /// - Returns:
    public func convertBytesToString() -> String {
        /*
         A formatter that converts a byte count value into a localized description that is formatted with the appropriate byte modifier (KB, MB, GB and so on).
         原来, 一直有着这样的一个进行单位换算的 Formatter 类.
         */
        return ByteCountFormatter.string(fromByteCount: base, countStyle: .file)
    }
}
