import Foundation

public typealias Handler<T> = (T) -> ()

public class Executer<T> {
    private let onMainQueue: Bool
    private let handler: Handler<T>?
    
    public init(onMainQueue: Bool = true, handler: Handler<T>?) {
        self.onMainQueue = onMainQueue
        self.handler = handler
    }
    
    
    public func execute(_ object: T) {
        if let handler = handler {
            if onMainQueue {
                DispatchQueue.tr.executeOnMain {
                    handler(object)
                }
            } else {
                handler(object)
            }
        }
    }
}
