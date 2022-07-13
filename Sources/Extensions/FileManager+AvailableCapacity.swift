import Foundation

extension FileManager: TiercelCompatible {}
extension TiercelWrapper where Base: FileManager {
    public var freeDiskSpaceInBytes: Int64 {
        if #available(macOS 10.13, iOS 11.0, *) {
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

