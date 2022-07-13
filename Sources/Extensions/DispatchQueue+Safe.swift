import Foundation

extension DispatchQueue: TiercelCompatible {}

extension TiercelWrapper where Base: DispatchQueue {
    public static func executeOnMain(_ block: @escaping ()->()) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }
}
