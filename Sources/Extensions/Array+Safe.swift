import Foundation

// 一个简单的扩展, 用于安全的获取 Array 里面的数据.
extension Array {
    public func safeObject(at index: Int) -> Element? {
        if (0..<count).contains(index) {
            return self[index]
        } else {
            return nil
        }
    }
}
