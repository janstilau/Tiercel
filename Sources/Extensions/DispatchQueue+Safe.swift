import Foundation

extension DispatchQueue: TiercelCompatible {}

extension TiercelWrapper where Base: DispatchQueue {
    // 这是一个静态方法, 所以在里面使用的是, Thread 进行的判断.
    // 这是一个快捷的, 进行主线程任务提交的方式. 
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
