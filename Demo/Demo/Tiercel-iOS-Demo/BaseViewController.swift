//
//  BaseViewController.swift
//  Example
//
//  Created by Daniels on 2018/3/20.
//  Copyright © 2018 Daniels. All rights reserved.
//

import UIKit
import Tiercel

class BaseViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var totalTasksLabel: UILabel!
    @IBOutlet weak var totalSpeedLabel: UILabel!
    @IBOutlet weak var timeRemainingLabel: UILabel!
    @IBOutlet weak var totalProgressLabel: UILabel!
    
    
    @IBOutlet weak var taskLimitSwitch: UISwitch!
    @IBOutlet weak var cellularAccessSwitch: UISwitch!
    
    var sessionManager: SessionManager!
    
    var URLStrings: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 检查磁盘空间
        let free = FileManager.default.tr.freeDiskSpaceInBytes / 1024 / 1024
        print("手机剩余储存空间为： \(free)MB")
        
        // 可以直接修改 logger 的值, 修改 looger 的行为.
        sessionManager.logger.option = .default
        
        updateSwicth()
        setupUI()
    }
    
    func setupUI() {
        // tableView的设置
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        tableView.register(UINib(nibName: "\(DownloadTaskCell.self)", bundle: nil),
                           forCellReuseIdentifier: DownloadTaskCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 164
        configureNavigationItem()
    }
    
    func configureNavigationItem() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "编辑",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(toggleEditing))
    }
    
    
    @objc func toggleEditing() {
        tableView.setEditing(!tableView.isEditing, animated: true)
        let button = navigationItem.rightBarButtonItem!
        button.title = tableView.isEditing ? "完成" : "编辑"
    }
    
    // 当, 应用退到后台的时候, 是不会触发这里的.
    func updateViews() {
        totalTasksLabel.text = "成功任务：\(sessionManager.succeededTasks.count)/ 总任务: \(sessionManager.tasks.count)"
        totalSpeedLabel.text = "总速度：\(sessionManager.speedString)"
        timeRemainingLabel.text = "剩余时间： \(sessionManager.timeRemainingString)"
        let per = String(format: "%.2f", sessionManager.progress.fractionCompleted)
        totalProgressLabel.text = "总进度： \(per)"
    }
    
    func updateSwicth() {
        taskLimitSwitch.isOn = sessionManager.configuration.maxConcurrentTasksLimit < 3
        cellularAccessSwitch.isOn = sessionManager.configuration.allowsCellularAccess
    }
    
    func setupManager() {
        
        // 这些都仅仅是在收集回调而已.
        sessionManager.progress { [weak self] (manager) in
            self?.updateViews()
        }.completion { [weak self] manager in
            self?.updateViews()
            if manager.status == .succeeded {
                // 下载成功
            } else {
                // 其他状态
            }
        }
    }
}

extension BaseViewController {
    @IBAction func totalStart(_ sender: Any) {
        sessionManager.totalStart { [weak self] _ in
            self?.tableView.reloadData()
        }
    }
    
    @IBAction func totalSuspend(_ sender: Any) {
        sessionManager.totalSuspend() { [weak self] _ in
            self?.tableView.reloadData()
            
        }
    }
    
    @IBAction func totalCancel(_ sender: Any) {
        sessionManager.totalCancel() { [weak self] _ in
            self?.tableView.reloadData()
        }
    }
    
    @IBAction func totalDelete(_ sender: Any) {
        sessionManager.totalRemove(completely: false) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }
    
    @IBAction func clearDisk(_ sender: Any) {
        sessionManager.cache.clearDiskCache()
        updateViews()
    }
    
    
    @IBAction func taskLimit(_ sender: UISwitch) {
        if sender.isOn {
            sessionManager.configuration.maxConcurrentTasksLimit = 2
        } else {
            sessionManager.configuration.maxConcurrentTasksLimit = Int.max
        }
    }
    
    @IBAction func cellularAccess(_ sender: UISwitch) {
        sessionManager.configuration.allowsCellularAccess = sender.isOn
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate
extension BaseViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sessionManager.tasks.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DownloadTaskCell.reuseIdentifier, for: indexPath) as! DownloadTaskCell
        return cell
    }
    
    // 每个 cell 中的状态更新，应该在 willDisplay 中执行
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let task = sessionManager.tasks.safeObject(at: indexPath.row),
              let cell = cell as? DownloadTaskCell
        else { return }
        
        cell.task?.progress { _ in }.success { _ in }.failure { _ in }
        
        cell.task = task
        
        cell.titleLabel.text = task.fileName
        
        cell.updateProgress(task)
        
        cell.tapClosure = { [weak self] cell in
            guard let task = self?.sessionManager.tasks.safeObject(at: indexPath.row) else { return }
            switch task.status {
            case .waiting, .running:
                self?.sessionManager.suspend(task)
            case .suspended, .failed:
                self?.sessionManager.start(task)
            default:
                break
            }
        }
        
        task.progress { [weak cell] task in
            cell?.updateProgress(task)
        }
        .success { [weak cell] (task) in
            cell?.updateProgress(task)
            // 下载任务成功了
        }
        .failure { [weak cell] task in
            cell?.updateProgress(task)
            if task.status == .suspended {
                // 下载任务暂停了
            }
            
            if task.status == .failed {
                // 下载任务失败了
            }
            if task.status == .canceled {
                // 下载任务取消了
            }
            if task.status == .removed {
                // 下载任务移除了
            }
        }
    }
    
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let task = sessionManager.tasks.safeObject(at: indexPath.row) else { return }
            sessionManager.remove(task, completely: false) { [weak self] _ in
                self?.tableView.deleteRows(at: [indexPath], with: .automatic)
                self?.updateViews()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        sessionManager.moveTask(at: sourceIndexPath.row, to: destinationIndexPath.row)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
