//
//  ViewController1.swift
//  Example
//
//  Created by Daniels on 2018/3/16.
//  Copyright © 2018 Daniels. All rights reserved.
//

import UIKit
import Tiercel

// VC 里面的逻辑很简单, 因为, 所有的逻辑, 都藏到了 Tiercel 的内部中了.
class ViewController1: UIViewController {
    
    @IBOutlet weak var speedLabel: UILabel!
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var timeRemainingLabel: UILabel!
    @IBOutlet weak var startDateLabel: UILabel!
    @IBOutlet weak var endDateLabel: UILabel!
    @IBOutlet weak var validationLabel: UILabel!
    
    //    lazy var URLString = "https://officecdn-microsoft-com.akamaized.net/pr/C1297A47-86C4-4C1F-97FA-950631F94777/OfficeMac/Microsoft_Office_2016_16.10.18021001_Installer.pkg"
    lazy var URLString = "http://dldir1.qq.com/qqfile/QQforMac/QQ_V4.2.4.dmg"
    var sessionManager = appDelegate.sessionManager1
    
    @Protected
    private var workItems = [String: String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /*
         public var wrappedValue: T {
             get { lock.around {
                 value
             }}
             set { lock.around {
                 value = newValue
             } }
         }
         */
        // 下面的操作, 其实会触发上面的 Get, Set 两种操作的.
        // 所以, 这种操作实际山, 会引起 lock 触发. 
        workItems["1"] = "one"
        workItems["2"] = "two"
        
        sessionManager.tasks.safeObject(at: 0)?.progress { [weak self] (task) in
            self?.updateViews(task)
        }.completion { [weak self] task in
            self?.updateViews(task)
            if task.status == .succeeded {
                // 下载成功
            } else {
                // 其他状态
            }
        }.validateFile(code: "9e2a3650530b563da297c9246acaad5c", type: .md5) { [weak self] task in
            self?.updateViews(task)
            if task.validation == .correct {
                // 文件正确
            } else {
                // 文件错误
            }
        }
    }
    
    private func updateViews(_ task: DownloadTask) {
        let per = task.progress.fractionCompleted
        progressLabel.text = "progress： \(String(format: "%.2f", per * 100))%"
        progressView.observedProgress = task.progress
        speedLabel.text = "speed： \(task.speedString)"
        timeRemainingLabel.text = "剩余时间： \(task.timeRemainingString)"
        startDateLabel.text = "开始时间： \(task.startDateString)"
        endDateLabel.text = "结束时间： \(task.endDateString)"
        var validation: String
        switch task.validation {
        case .unkown:
            validationLabel.textColor = UIColor.blue
            validation = "未知"
        case .correct:
            validationLabel.textColor = UIColor.green
            validation = "正确"
        case .incorrect:
            validationLabel.textColor = UIColor.red
            validation = "错误"
        }
        validationLabel.text = "文件验证： \(validation)"
    }
    
    @IBAction func start(_ sender: UIButton) {
        // 这种, 链式调用的结果, 应该是和其他的项目中学习过来的.
        sessionManager.download(URLString)?.progress { [weak self] (task) in
            self?.updateViews(task)
        }.completion { [weak self] task in
            self?.updateViews(task)
            if task.status == .succeeded {
                // 下载成功
            } else {
                // 其他状态
            }
        }.validateFile(code: "9e2a3650530b563da297c9246acaad5c", type: .md5) { [weak self] (task) in
            self?.updateViews(task)
            if task.validation == .correct {
                // 文件正确
            } else {
                // 文件错误
            }
        }
    }
    
    @IBAction func suspend(_ sender: UIButton) {
        sessionManager.suspend(URLString)
    }
    
    
    @IBAction func cancel(_ sender: UIButton) {
        sessionManager.cancel(URLString)
    }
    
    @IBAction func deleteTask(_ sender: UIButton) {
        sessionManager.remove(URLString, completely: false)
    }
    
    @IBAction func clearDisk(_ sender: Any) {
        sessionManager.cache.clearDiskCache()
    }
}

