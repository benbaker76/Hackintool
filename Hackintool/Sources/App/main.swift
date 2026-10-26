//
//  main.swift
//  Hackintool
//
//  Created by Ben Baker on 6/19/18.
//  Copyright (c) 2018 Ben Baker. All rights reserved.
//

import Cocoa

// The app has no main nib: the menu and window are built in code.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
