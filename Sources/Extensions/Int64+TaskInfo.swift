import Foundation

extension Int64: TiercelCompatible {}
extension TiercelWrapper where Base == Int64 {
    
    /// 返回下载速度的字符串，如：1MB/s
    ///
    /// - Returns:
    public func convertSpeedToString() -> String {
        let size = convertBytesToString()
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
        return ByteCountFormatter.string(fromByteCount: base, countStyle: .file)
    }
    
    
}
