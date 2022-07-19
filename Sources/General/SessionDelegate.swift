import Foundation

internal class SessionDelegate: NSObject {
    internal weak var manager: SessionManager?
}

// 其实, 应该是 Session Manager 来充当 URLSessionDownloadDelegate.
// 因为这里, 也是调用对应的方法, 将事件分发到 manager 中去了.
extension SessionDelegate: URLSessionDownloadDelegate {
    /*
     If you invalidate a session by calling its finishTasksAndInvalidate method, the session waits until after the final task in the session finishes or fails before calling this delegate method. If you call the invalidateAndCancel method, the session calls this delegate method immediately.
     */
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        manager?.didBecomeInvalidation(withError: error)
        print(#function)
    }
    
    /*
     In iOS, when a background transfer completes or requires credentials, if your app is no longer running, your app is automatically relaunched in the background, and the app’s UIApplicationDelegate is sent an application:handleEventsForBackgroundURLSession:completionHandler: message.
     
     This call contains the identifier of the session that caused your app to be launched. You should then store that completion handler before creating a background configuration object with the same identifier, and creating a session with that configuration. The newly created session is automatically reassociated with ongoing background activity.
     
     When your app later receives a URLSessionDidFinishEventsForBackgroundURLSession: message, this indicates that all messages previously enqueued for this session have been delivered, and that it is now safe to invoke the previously stored completion handler or to begin any internal updates that may result in invoking the completion handler.
     */
    
    /*
     当, 在后台下载成功之后, 会触发 App Delegate 的方法, 然后依次触发了.
     urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
     urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
     urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession
     
     也就是说, 只会触发这几个结束节点的事件给 Delegate.
     */
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        manager?.didFinishEvents(forBackgroundURLSession: session)
        print(#function)
    }
    
    // 下载过程的回调.
    /*
     当下载过程中, App 退到后台, 这个时候 Delegate 方法不会继续被调用.
     如果不是用户手动杀死 App, 那么真正的下载任务, 还是在不断的触发的, 是在单独的进程中. 当 App 重新启动, 或者切换到前台之后, 还是可以接收到, Delegate 方法对应的回调的. 
     */
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        guard let manager = manager else { return }
        guard let currentURL = downloadTask.currentRequest?.url else { return }
        guard let task = manager.mapTask(currentURL) else {
            manager.log(.error("urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)",
                               error: TiercelError.fetchDownloadTaskFailed(url: currentURL))
            )
            return
        }
        task.didWriteData(downloadTask: downloadTask, bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        print(String(downloadTask.taskIdentifier) + " " + #function)
    }
    
    // 下载完成的回调.
    // Tells the delegate that a download task has finished downloading.
    // 这个方法, 会在 didCompleteWithError 之前进行调用, 但是后续的方法, 还是会继续进行调用的.
    // 所以在这个方法里面, 只做了文件相关的处理.
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let manager = manager else { return }
        guard let currentURL = downloadTask.currentRequest?.url else { return }
        guard let task = manager.mapTask(currentURL) else {
            manager.log(.error("urlSession(_:downloadTask:didFinishDownloadingTo:)", error: TiercelError.fetchDownloadTaskFailed(url: currentURL)))
            return
        }
        task.didFinishDownloading(task: downloadTask, to: location)
        print(String(downloadTask.taskIdentifier) + " " + #function)
    }
    
    // 下载结束的回调.
    // 如果下载过程中, 强杀 App, 再次启动之后, 会触发到这里. 也就是说, 现有的下载任务是被当做了失败进行了处理.
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let manager = manager else { return }
        
        if let currentURL = task.currentRequest?.url {
            guard let downloadTask = manager.mapTask(currentURL) else {
                return
            }
            downloadTask.didTaskCompleted(.network(task: task, error: error))
        } else {
            if let error = error {
                if let urlError = error as? URLError,
                   let errorURL = urlError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                    guard let downloadTask = manager.mapTask(errorURL) else {
                        return
                    }
                    downloadTask.didTaskCompleted(.network(task: task, error: error))
                }
            }
        }
        // downloadTask.didComplete(.network(task: task, error: error))
        // 最终都是触发该方法, 不过是 URL 的获取方式不同而已.
        print(String(task.taskIdentifier) + " " + #function)
    }
}
