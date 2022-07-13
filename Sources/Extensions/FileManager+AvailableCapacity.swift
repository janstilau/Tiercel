import Foundation

extension FileManager: TiercelCompatible {}

// 容量的计算. 写到了 FileManager 上.
// 系统提供了, 相关的处理办法. 
extension TiercelWrapper where Base: FileManager {
    public var freeDiskSpaceInBytes: Int64 {
        if #available(macOS 10.13, iOS 11.0, *) {
            // URLResourceKey.volumeAvailableCapacityForImportantUsageKey
            // Key for the volume’s available capacity in bytes for storing important resources (read-only).
            if let space = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [URLResourceKey.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
                return space
            } else {
                return 0
            }
        } else {
            if let systemAttributes = try? base.attributesOfFileSystem(forPath: NSHomeDirectory()),
               let freeSpace = (systemAttributes[FileAttributeKey.systemFreeSize] as? NSNumber)?.int64Value {
                return freeSpace
            } else {
                return 0
            }
        }
    }
}

