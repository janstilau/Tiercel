//
//  AppDelegate.swift
//  Example
//
//  Created by Daniels on 2018/3/16.
//  Copyright © 2018 Daniels. All rights reserved.
//

import UIKit
import Tiercel

let appDelegate = UIApplication.shared.delegate as! AppDelegate

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    let sessionManager1 = SessionManager("ViewController1", configuration: SessionConfiguration())
    
    var sessionManager2: SessionManager = {
        var configuration = SessionConfiguration()
        configuration.allowsCellularAccess = true
        let path = Cache.defaultDiskCachePathClosure("Test")
        let cacahe = Cache("ViewController2", downloadPath: path)
        let manager = SessionManager("ViewController2", configuration: configuration, cache: cacahe, operationQueue: DispatchQueue(label: "com.Tiercel.SessionManager.operationQueue"))
        return manager
    }()
    
    let sessionManager3 = SessionManager("ViewController3", configuration: SessionConfiguration())
    
    let sessionManager4 = SessionManager("ViewController4", configuration: SessionConfiguration())
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
    
    /*
     The app calls this method after all background transfers associated with an NSURLSession object are done, whether they finished successfully or resulted in an error. The app also calls this method if authentication is required for one or more transfers.
     Use this method to reconnect any URL sessions and to update your app’s user interface. For example, you might use this method to update progress indicators or to incorporate new content into your views. After processing the events, execute the block in the completionHandler parameter so that the app can take a new snapshot of your user interface.
     If a URL session finishes its work when your app is not running, the system launches your app in the background so that it can process the event. In that situation, use the provided identifier to create a new NSURLSessionConfiguration and NSURLSession object. You must configure the other options of your NSURLSessionConfiguration object in the same way that you did when you started the uploads or downloads. Upon creating and configuring the new NSURLSession object, that object calls the appropriate delegate methods to process the events.
     If your app already has a session object with the specified identifier and is running or suspended, you do not need to create a new session object using this method. Suspended apps are moved into the background. As soon as the app is running again, the NSURLSession object with the identifier receives the events and processes them normally.
     At launch time, the app does not call this method if there are uploads or downloads in progress but not yet finished. If you want to display the current progress of those transfers in your app’s user interface, you must recreate the session object yourself. In that situation, cache the identifier value persistently and use it to recreate your session object.
     */
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        let downloadManagers = [sessionManager1, sessionManager2, sessionManager3, sessionManager4]
        for manager in downloadManagers {
            if manager.identifier == identifier {
                manager.completionHandler = completionHandler
                break
            }
        }
    }
}

