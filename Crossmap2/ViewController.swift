//
//  ViewController.swift
//  MetalCubemapping
//
//  Created by Mark Lim Pak Mun on 27/08/2020.
//  Copyright © 2020 Mark Lim Pak Mun. All rights reserved.
//

import Cocoa
import MetalKit

class ViewController: NSViewController {
    var mtkView: MTKView!
    
    var renderer: CubemapRenderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        mtkView = (self.view as! MTKView)
        // The view seems to have been instantiated w/o a "device" property.
        let device = MTLCreateSystemDefaultDevice()!
        mtkView.device = device
        // Configure
        mtkView.colorPixelFormat = .rgba16Float
        // A depth buffer maybe required
        mtkView.depthStencilPixelFormat = .depth32Float
        renderer = CubemapRenderer(view: mtkView,
                                   device: device)
        mtkView.delegate = renderer     // this is necessary.

        let size = mtkView.drawableSize
        // Ensure the view and projection matrices are setup
        renderer.mtkView(mtkView,
                         drawableSizeWillChange: size)
   }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    override func viewDidAppear() {
        self.mtkView.window!.makeFirstResponder(self)
    }
    
    override func mouseDown(with event: NSEvent) {
        let mousePoint = view.convert(event.locationInWindow, from: nil)
        renderer.setMouseCoords(mousePoint)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let mousePoint = view.convert(event.locationInWindow, from: nil)
        renderer.setMouseCoords(mousePoint)
    }
}

