//
//  AppDelegate.swift
//  OpenGLRenderer-macOS
//
//  Created by mark lim pak mun on 12/11/2021.
//  Copyright © 2021 mark lim pak mun. All rights reserved.
//

import Cocoa

// Swift need an instance of NSApplicationDelegate
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {



    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

