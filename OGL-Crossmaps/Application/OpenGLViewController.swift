//
//  ViewController.swift
//  OpenGLRenderer-macOS
//
//  Created by mark lim pak mun on 12/11/2021.
//  Copyright © 2021 mark lim pak mun. All rights reserved.
//  This is shared by all demos

#if os(iOS)
import UIKit
typealias PlatformViewBase = UIView
typealias PlatformViewController = UIViewController
typealias PlatformGLContext = EAGLContext
#else
import AppKit
typealias PlatformViewBase = NSOpenGLView
typealias PlatformViewController = NSViewController
typealias PlatformGLContext = NSOpenGLContext
#endif

class OpenGLView: PlatformViewBase {
#if os(iOS)
    override public class var layerClass: AnyClass {
        return CAEAGLLayer.self
    }
#endif
}


class OpenGLViewController: PlatformViewController {
    var glView: OpenGLView!
    var _openGLRenderer: OpenGLRenderer!
    var _context: PlatformGLContext!
    var _defaultFBOName: GLuint = 0
#if os(iOS)
    var _colorRenderbuffer: GLuint = 0
    var _depthRenderbuffer: GLuint = 0
    var _displayLink: CADisplayLink!
#else
    var _displayLink: CVDisplayLink?
#endif

    override func viewDidLoad() {
        super.viewDidLoad()
        glView = self.view as! OpenGLView

        self.prepareView()
        makeCurrentContext()
        _openGLRenderer = OpenGLRenderer(_defaultFBOName)
        // Do any additional setup after loading the view.
    }

#if os(macOS)
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


    let displayLinkOutputCallback: CVDisplayLinkOutputCallback = {
        (displayLink: CVDisplayLink, inNow: UnsafePointer<CVTimeStamp>, inOutputTime: UnsafePointer<CVTimeStamp>, flagsIn: CVOptionFlags, flagsOut: UnsafeMutablePointer<CVOptionFlags>, displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn in

        let viewController = unsafeBitCast(displayLinkContext,
                                           to: OpenGLViewController.self)
        viewController.draw()
        return kCVReturnSuccess
    }

   
    func prepareView() {
        let displayMask = CGDisplayIDToOpenGLDisplayMask(CGMainDisplayID())

        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAColorSize), UInt32(32),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFADepthSize), UInt32(24),
            UInt32(NSOpenGLPFAScreenMask), displayMask,
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]
        let pf = NSOpenGLPixelFormat(attributes: attrs)
        if (pf == nil) {
            Swift.print("Couldn't init OpenGL at all, sorry :(")
            abort()
        }

        _context = NSOpenGLContext(format: pf!, share: nil)

        CGLLockContext(_context.cglContextObj!)
        makeCurrentContext()
        CGLUnlockContext(_context.cglContextObj!)

        glEnable(GLenum(GL_FRAMEBUFFER_SRGB))
        glView.pixelFormat = pf
        glView.openGLContext = _context
        glView.wantsBestResolutionOpenGLSurface = true

        // The default framebuffer object (FBO) is 0 on macOS, because it uses
        // a traditional OpenGL pixel format model. Might be different on other OSes.
        _defaultFBOName = 0

        CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);

        CVDisplayLinkSetOutputCallback(_displayLink!,
                                       displayLinkOutputCallback,
                                       UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        CVDisplayLinkStart(_displayLink!)
    }


    func makeCurrentContext() {
        _context.makeCurrentContext()
    }


    override func viewDidLayout() {

        CGLLockContext(_context.cglContextObj!)

        let viewSizePoints = glView.bounds.size
        let viewSizePixels = glView.convertToBacking(viewSizePoints)

        makeCurrentContext()

        _openGLRenderer.resize(viewSizePixels)

        CGLUnlockContext(_context.cglContextObj!);

        if !CVDisplayLinkIsRunning(_displayLink!) {
            CVDisplayLinkStart(_displayLink!)
        }
    }

    override func viewWillDisappear() {
        CVDisplayLinkStop(_displayLink!)
    }

    deinit {
        CVDisplayLinkStop(_displayLink!)
    }

    fileprivate func draw() {
        // The method might be called before the renderer object is instantiated.
        guard let renderer = _openGLRenderer else {
            return
        }
        CGLLockContext(_context.cglContextObj!);

        makeCurrentContext()
        renderer.draw()

        CGLFlushDrawable(_context.cglContextObj!);
        CGLUnlockContext(_context.cglContextObj!);
    }

    override func viewDidAppear() {
        self.glView.window!.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        //Swift.print("keyDown")
    }

    func passMouseCoords(at point: NSPoint) {
        _openGLRenderer.mouseCoords[0] = GLfloat(point.x)
        _openGLRenderer.mouseCoords[1] = GLfloat(point.y)
        //Swift.print("mouse coords:", _openGLRenderer.mouseCoords)
    }

    override func mouseDown(with event: NSEvent) {
        let mousePoint = self.view.convert(event.locationInWindow,
                                           from: nil)
        passMouseCoords(at: mousePoint)
    }

    override func mouseDragged(with event: NSEvent) {
        let mousePoint = self.view.convert(event.locationInWindow,
                                           from: nil)
        passMouseCoords(at: mousePoint)
    }
#endif

    
#if os(iOS)
    // ===== iOS specific code. =====

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func draw(_ sender: CADisplayLink) {
        EAGLContext.setCurrent(_context)
        _openGLRenderer.draw()

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), _colorRenderbuffer)
        _context.presentRenderbuffer(Int(GL_RENDERBUFFER))
    }

    func makeCurrentContext() {
        EAGLContext.setCurrent(_context)
    }

    func prepareView() {
        let eaglLayer = self.view.layer as! CAEAGLLayer

        eaglLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking : false,
            kEAGLDrawablePropertyColorFormat     : kEAGLColorFormatSRGBA8
        ]
        eaglLayer.isOpaque = true

        // We are testing under iPhone's OpenGLES
        _context = EAGLContext(api: .openGLES3)

        if _context == nil || !EAGLContext.setCurrent(_context) {
            NSLog("Could not create an OpenGL ES context.")
            return
        }

        self.view.contentScaleFactor = UIScreen.main.nativeScale
        // In iOS & tvOS, you must create an FBO and attach a drawable texture
        // allocated by Core Animation to use as the default FBO for a view.
        glGenFramebuffers(1, &_defaultFBOName);
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), _defaultFBOName);

        glGenRenderbuffers(1, &_colorRenderbuffer);

        glGenRenderbuffers(1, &_depthRenderbuffer);

        self.resizeDrawable()

        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER),
                                  GLenum(GL_COLOR_ATTACHMENT0),
                                  GLenum(GL_RENDERBUFFER),
                                  _colorRenderbuffer)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER),
                                  GLenum(GL_DEPTH_ATTACHMENT),
                                  GLenum(GL_RENDERBUFFER),
                                  _depthRenderbuffer)

        // Create the display link so you render at 60 frames per second (FPS).
        _displayLink = CADisplayLink(target: self,
                                     selector: #selector(OpenGLViewController.draw(_:)))

        _displayLink.preferredFramesPerSecond = 60

        // Set the display link to run on the default run loop (and the main thread).
        _displayLink.add(to: RunLoop.main,
                         forMode: RunLoopMode.defaultRunLoopMode)
    }

    func drawableSize() -> CGSize {
        var backingWidth: GLint = 0
        var backingHeight: GLint = 0

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), _colorRenderbuffer);
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER),
                                     GLenum(GL_RENDERBUFFER_WIDTH),
                                     &backingWidth)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER),
                                     GLenum(GL_RENDERBUFFER_HEIGHT),
                                     &backingHeight)
        let drawableSize = CGSize(width: Int(backingWidth),
                                  height: Int(backingHeight))
        return drawableSize
    }

    func resizeDrawable() {
        self.makeCurrentContext()

        // First, ensure that you have a render buffer.
        assert(_colorRenderbuffer != 0)

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER),
                           _colorRenderbuffer)

        // This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
        // allowing us to draw into a buffer that will later be rendered to screen wherever the
        // layer is (which corresponds with our view).
        _context.renderbufferStorage(Int(GL_RENDERBUFFER),
                                     from: glView.layer as! CAEAGLLayer)

        let drawableSize = self.drawableSize()

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER),
                           _depthRenderbuffer)

        glRenderbufferStorage(GLenum(GL_RENDERBUFFER),
                              GLenum(GL_DEPTH_COMPONENT24),
                              GLsizei(drawableSize.width), GLsizei(drawableSize.height))

        // The custom render object is nil on first call to this method.
        guard let renderer = _openGLRenderer else {
            return
        }
        renderer.resize(drawableSize)
    }

    override func viewDidLayoutSubviews() {
        resizeDrawable()
    }

    override func viewDidAppear(_ animated: Bool) {
        resizeDrawable()
    }

#endif

}

