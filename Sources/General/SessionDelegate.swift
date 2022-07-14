import Foundation

internal class SessionDelegate: NSObject {
    internal weak var manager: SessionManager?
}

// 几个 URLSession 的层级关系是继承的. 所以, 实际上, 这里是最全的 Delegate 的协议了.
extension SessionDelegate: URLSessionDownloadDelegate {
    /*
     If you invalidate a session by calling its finishTasksAndInvalidate method, the session waits until after the final task in the session finishes or fails before calling this delegate method. If you call the invalidateAndCancel method, the session calls this delegate method immediately.
     */
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        manager?.didBecomeInvalidation(withError: error)
    }
    
    /*
     In iOS, when a background transfer completes or requires credentials, if your app is no longer running, your app is automatically relaunched in the background, and the app’s UIApplicationDelegate is sent an application:handleEventsForBackgroundURLSession:completionHandler: message.
     
     This call contains the identifier of the session that caused your app to be launched. You should then store that completion handler before creating a background configuration object with the same identifier, and creating a session with that configuration. The newly created session is automatically reassociated with ongoing background activity.
     
     When your app later receives a URLSessionDidFinishEventsForBackgroundURLSession: message, this indicates that all messages previously enqueued for this session have been delivered, and that it is now safe to invoke the previously stored completion handler or to begin any internal updates that may result in invoking the completion handler.
     */
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        manager?.didFinishEvents(forBackgroundURLSession: session)
    }
    
    // 下载过程的回调.
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let manager = manager else { return }
        guard let currentURL = downloadTask.currentRequest?.url else { return }
        guard let task = manager.mapTask(currentURL) else {
            manager.log(.error("urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)",
                               error: TiercelError.fetchDownloadTaskFailed(url: currentURL))
            )
            return
        }
        task.didWriteData(downloadTask: downloadTask, bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
    }
    
    // 下载完成的回调.
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let manager = manager else { return }
        guard let currentURL = downloadTask.currentRequest?.url else { return }
        guard let task = manager.mapTask(currentURL) else {
            manager.log(.error("urlSession(_:downloadTask:didFinishDownloadingTo:)", error: TiercelError.fetchDownloadTaskFailed(url: currentURL)))
            return
        }
        task.didFinishDownloading(task: downloadTask, to: location)
    }
    
    // 下载失败的回调.
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let manager = manager else { return }
        
        if let currentURL = task.currentRequest?.url {
            guard let downloadTask = manager.mapTask(currentURL) else {
                manager.log(.error("urlSession(_:task:didCompleteWithError:)", error: TiercelError.fetchDownloadTaskFailed(url: currentURL)))
                return
            }
            downloadTask.didComplete(.network(task: task, error: error))
        } else {
            if let error = error {
                if let urlError = error as? URLError,
                   let errorURL = urlError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                    guard let downloadTask = manager.mapTask(errorURL) else {
                        manager.log(.error("urlSession(_:task:didCompleteWithError:)", error: TiercelError.fetchDownloadTaskFailed(url: errorURL)))
                        manager.log(.error("urlSession(_:task:didCompleteWithError:)", error: error))
                        return
                    }
                    downloadTask.didComplete(.network(task: task, error: error))
                } else {
                    manager.log(.error("urlSession(_:task:didCompleteWithError:)", error: error))
                    return
                }
            } else {
                manager.log(.error("urlSession(_:task:didCompleteWithError:)", error: TiercelError.unknown))
            }
        }
    }
}
