import Foundation

internal class SessionDelegate: NSObject {
    internal weak var manager: SessionManager?
    
}


extension SessionDelegate: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        manager?.didBecomeInvalidation(withError: error)
    }
    
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        manager?.didFinishEvents(forBackgroundURLSession: session)
    }
    
    
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
    
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let manager = manager else { return }
        guard let currentURL = downloadTask.currentRequest?.url else { return }
        guard let task = manager.mapTask(currentURL) else {
            manager.log(.error("urlSession(_:downloadTask:didFinishDownloadingTo:)", error: TiercelError.fetchDownloadTaskFailed(url: currentURL)))
            return
        }
        task.didFinishDownloading(task: downloadTask, to: location)
    }
    
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
