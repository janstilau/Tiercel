import Foundation

extension URLSession {
    
    /// 把有bug的resumeData修复，然后创建task
    ///
    /// - Parameter resumeData:
    /// - Returns:
    internal func correctedDownloadTask(withResumeData resumeData: Data) -> URLSessionDownloadTask {
        
        let task = downloadTask(withResumeData: resumeData)
        
        if let resumeDictionary = ResumeDataHelper.getResumeDictionary(resumeData) {
            if task.originalRequest == nil, let originalReqData = resumeDictionary[ResumeDataHelper.originalRequestKey] as? Data, let originalRequest = NSKeyedUnarchiver.unarchiveObject(with: originalReqData) as? NSURLRequest {
                task.setValue(originalRequest, forKey: "originalRequest")
            }
            if task.currentRequest == nil, let currentReqData = resumeDictionary[ResumeDataHelper.currentRequestKey] as? Data, let currentRequest = NSKeyedUnarchiver.unarchiveObject(with: currentReqData) as? NSURLRequest {
                task.setValue(currentRequest, forKey: "currentRequest")
            }
        }
        
        return task
    }
}
