//
//  CubemapRenderer.swift
//  Crossmap
//
//  Created by Mark Lim Pak Mun on 11/05/2022.
//  Copyright © 2022 Mark Lim Pak Mun. All rights reserved.
//
// https://www.shadertoy.com/view/tdjXDt

import Foundation
import MetalKit
import SceneKit
import SceneKit.ModelIO
import simd

struct Uniforms {
    var modelMatrix = matrix_identity_float4x4
    var viewMatrix = matrix_identity_float4x4
    var projectionMatrix = matrix_identity_float4x4
    var normalMatrix = matrix_identity_float4x4
    var worldCameraPosition = float4(0)
}

class CubemapRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let mtkView: MTKView
    let commandQueue: MTLCommandQueue!
    var defaultLibrary: MTLLibrary!

    var viewMatrix: float4x4!
    var projectionMatrix: float4x4!
    var u_time: Float = 0.0
    var u_timeBuffer: MTLBuffer!
    var u_resolutionBuffer: MTLBuffer!
    var u_mouse =  float2(0,0)
    var u_mouseBuffer: MTLBuffer!

    var renderToTextureRenderPipelineState: MTLRenderPipelineState!
    var renderPipelineState: MTLRenderPipelineState!

    var skyboxMesh: Mesh!
    var uniformsBuffers = [MTLBuffer]()

    var skyBoxTextures = [MTLTexture?]()
    var cubeMapTexture: MTLTexture!
    var cubeMapDepthTexture: MTLTexture!
    var depthTexture: MTLTexture!

    var renderToTexturePassDescriptor: MTLRenderPassDescriptor!
    var skyboxDepthStencilState: MTLDepthStencilState!

    init(view: MTKView, device: MTLDevice) {
        self.mtkView = view
        self.device = device
        // Create a new command queue
        self.commandQueue = device.makeCommandQueue()

        super.init()

        //let names = ["px.png", "nx.png", "py.png", "ny.png", "pz.png", "nz.png"]
        let names = ["px.hdr", "nx.hdr", "py.hdr", "ny.hdr", "pz.hdr", "nz.hdr"]
        buildResources(with: names, isHDR: true)
        buildPipelineStates()
        // Note: Don't write to the skybox's depth attachment
        skyboxDepthStencilState = buildDepthStencilState(device: device,
                                                         isWriteEnabled: false)
        createCubemapTexture()
        let point = NSPoint(x: mtkView.frame.width/2,
                            y: mtkView.frame.height/2)
        setMouseCoords(point)
    }


    // The names of radiance files must have the file extension "hdr"
    // All file names are case sensitive when stored in the Resources folder.
    func buildResources(with names: [String], isHDR: Bool) {
        skyboxMesh = BoxMesh(withSize: 2,
                             device: device)

        if isHDR {
            // The following images cannot be stored in an Asset.xcassets because their filetype is hdr.
            // These can obtained by running an OpenGL program and their bitmaps written out
            // in RGBE format. Currently macOS (10.15) does not support writing hdr files natively.
            skyBoxTextures = [MTLTexture?]()
            let textureLoader = MTKTextureLoader(device: self.device)
            var hdrTexture: MTLTexture?
            for name in names {
                do {
                    hdrTexture = try textureLoader.newTexture(fromRadianceFile: name)
                }
                catch let error as NSError {
                    Swift.print("Can't load hdr file:\(error)")
                    exit(1)
                }
                skyBoxTextures.append(hdrTexture)
            }
        }
        else {
            // Load the individual graphic that will be used as a cubemap texture.
            // Assumes the graphic images have the same dimensions.
            // The images are in the folder Resources folder
            let mainBundle = Bundle.main
            var urls = [URL]()
            for name in names {
                let url = mainBundle.urlForImageResource(NSImage.Name(name))
                urls.append(url!)
            }
            // Array of 2D MTLTextures which will be used to setup the cube map texture.
            skyBoxTextures = [MTLTexture?]()
            let textureLoader = MTKTextureLoader(device: device)
            let options = [
                convertFromMTKTextureLoaderOption(MTKTextureLoader.Option.SRGB) : NSNumber(value: false),
                convertFromMTKTextureLoaderOrigin(MTKTextureLoader.Origin.bottomLeft): NSNumber(value: false),
            ]
            var nsError: NSError?
            skyBoxTextures = textureLoader.newTextures(URLs: urls,
                                                       options: convertToOptionalMTKTextureLoaderOptionDictionary(options),
                                                       error: &nsError)
            if nsError != nil {
                Swift.print("Can't load image files:\(nsError!)")
                exit(2)
            }
                
        }
        // We expect the cube's width, height and length of equal.
        let colorPixelFormat = skyBoxTextures[0]?.pixelFormat
        //Swift.print(colorPixelFormat?.rawValue)
        let imageWidth = skyBoxTextures[0]?.width
        //let imageHeight = skyBoxTextures[0]?.height
        // Set up a cubemap texture for rendering to and sampling from
        // using the concept of layer rendering.
        // mtkView.colorPixelFormat can be used.
        let cubeMapDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: colorPixelFormat!,
                                                                     size: Int(imageWidth!),
                                                                     mipmapped: false)
        cubeMapDesc.storageMode = MTLStorageMode.private
        cubeMapDesc.usage = [MTLTextureUsage.renderTarget, MTLTextureUsage.shaderRead]
        cubeMapTexture = device.makeTexture(descriptor: cubeMapDesc)

    /*
        let cubeMapDepthDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: MTLPixelFormat.depth32Float,
                                                                          size: Int(cubemapResolution),
                                                                          mipmapped: false)
        cubeMapDepthDesc.storageMode = MTLStorageMode.private
        cubeMapDepthDesc.usage = MTLTextureUsage.renderTarget
        cubeMapDepthTexture = device.makeTexture(descriptor: cubeMapDepthDesc)
    */
        // Set up a render pass descriptor for the render pass to output the cubemap texture.
        renderToTexturePassDescriptor = MTLRenderPassDescriptor()
        renderToTexturePassDescriptor.colorAttachments[0].clearColor  = MTLClearColorMake(1, 1, 1, 1)
        renderToTexturePassDescriptor.colorAttachments[0].loadAction  = MTLLoadAction.clear
        renderToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreAction.store
        renderToTexturePassDescriptor.depthAttachment.clearDepth      = 1.0
        renderToTexturePassDescriptor.depthAttachment.loadAction      = MTLLoadAction.clear

        renderToTexturePassDescriptor.colorAttachments[0].texture     = cubeMapTexture
        // No depth textures are needed.
        renderToTexturePassDescriptor.depthAttachment.texture         = nil
        // A value other than 0 indicates layer rendering is enabled.
        renderToTexturePassDescriptor.renderTargetArrayLength         = 6

        u_resolutionBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride,
                                               options: [])
        u_timeBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride,
                                         options: [])
        u_timeBuffer.label = "time uniform"
        u_mouseBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride,
                                          options: [])
        u_mouseBuffer.label = "mouse coords uniform"
                                           
    }

    func buildPipelineStates() {
        // Load all the shader files with a metal file extension in the project
        guard let library = device.makeDefaultLibrary()
        else {
            fatalError("Could not load default library from main bundle")
        }
       
        // Create the render pipeline for rendering to the offscreen texture.
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Offscreen Render Pipeline"
        pipelineDescriptor.sampleCount = mtkView.sampleCount
        pipelineDescriptor.colorAttachments[0].pixelFormat = cubeMapTexture.pixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.invalid
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "projectTexture")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "outputCubeMapTexture")
        // The following assignment is necessary when layered rendering is enabled.
        pipelineDescriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClass.triangle
        // The geometry of the shape (a triangle strip) is embedded within the vertex function.
        pipelineDescriptor.vertexDescriptor = nil
        do {
            renderToTextureRenderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            fatalError("Could not create offscreen render pipeline state object: \(error)")
        }

        // Load the vertex program into the library
        let quadVertexProgram = library.makeFunction(name: "vertexShader")
        // Load the fragment program into the library
        let quadFragmentProgram = library.makeFunction(name: "fragmentShader")
        pipelineDescriptor.sampleCount = mtkView.sampleCount
        pipelineDescriptor.vertexFunction = quadVertexProgram
        pipelineDescriptor.fragmentFunction = quadFragmentProgram
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.depth32Float
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            fatalError("Could not create  render pipeline state object: \(error)")
        }

    }

    func buildDepthStencilState(device: MTLDevice,
                                isWriteEnabled: Bool) -> MTLDepthStencilState? {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = isWriteEnabled
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }

    func buildDepthBuffer() {
        let drawableSize = mtkView.drawableSize
        let depthTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                    width: Int(drawableSize.width),
                                                                    height: Int(drawableSize.height),
                                                                    mipmapped: false)
        depthTexDesc.resourceOptions = .storageModePrivate
        depthTexDesc.usage = [.renderTarget, .shaderRead]
        self.depthTexture = self.device.makeTexture(descriptor: depthTexDesc)
    }

    // Render to an offscreen cube map texture.
    func createCubemapTexture() {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.addCompletedHandler {
            cb in
            if commandBuffer.status == .completed {
                print("The Cube Map Texture was created successfully.")
            }
            else {
                if commandBuffer.status == .error {
                    print("The Cube Map Texture could be not created")
                    print("Command Buffer Status Error")
                }
                else {
                    print("Command Buffer Status Code: ", commandBuffer.status)
                }
            }
        }

        let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderToTexturePassDescriptor)!
        commandEncoder.label = "Offscreen Render Pass"
        commandEncoder.setRenderPipelineState(renderToTextureRenderPipelineState)
        let range: Range<Int> = Range(0..<6)
        //let range = 0..<6
        commandEncoder.setFragmentTextures(skyBoxTextures, range: range)
        commandEncoder.drawPrimitives(type: MTLPrimitiveType.triangleStrip,
                                      vertexStart: 0,
                                      vertexCount: 4,
                                      instanceCount: 6)
        // End encoding commands for this render pass.
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func updateTime() {
        u_time += 1 / Float(mtkView.preferredFramesPerSecond)
        let bufferPointer = u_timeBuffer.contents()
        memcpy(bufferPointer, &u_time, MemoryLayout<Float>.stride)
    }

    // Called by view controller whenever there is a mouse down or mouse dragged.
    func setMouseCoords(_ point: NSPoint) {
        var mouseLocation = float2(Float(point.x), Float(point.y))
        let bufferPointer = u_mouseBuffer.contents()
        memcpy(bufferPointer, &mouseLocation, MemoryLayout<float2>.stride)
    }

    // Called whenever the view size changes
    func mtkView(_ view: MTKView,
                 drawableSizeWillChange size: CGSize) {
        buildDepthBuffer()
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        projectionMatrix = matrix_perspective_right_hand(Float.pi / 3,
                                                         aspectRatio,
                                                         0.1, 1000)
    }

    // called per frame update
    func draw(in view: MTKView) {
        let commandBuffer = commandQueue.makeCommandBuffer()!

        if  let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable {
            let drawableSize = drawable.layer.drawableSize
            if (drawableSize.width != CGFloat(depthTexture.width) || drawableSize.height != CGFloat(depthTexture.height)) {
                buildDepthBuffer()
            }

            updateTime()
            guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor:renderPassDescriptor) else {
                return
            }
            var resolution: float2 = float2(Float(drawable.texture.width),
                                            Float(drawable.texture.height))
            let bufferPointer = u_resolutionBuffer.contents()
            memcpy(bufferPointer, &resolution, MemoryLayout<float2>.stride)

            commandEncoder.setRenderPipelineState(renderPipelineState)
            commandEncoder.setFragmentTexture(cubeMapTexture,
                                              index: 0)
            commandEncoder.setFragmentBuffer(u_resolutionBuffer,
                                             offset: 0,
                                             index: 0)
            commandEncoder.setFragmentBuffer(u_timeBuffer,
                                             offset: 0,
                                             index: 1)
            commandEncoder.setFragmentBuffer(u_mouseBuffer,
                                             offset: 0,
                                             index: 2)
            commandEncoder.drawPrimitives(type: .triangleStrip,
                                          vertexStart: 0,
                                          vertexCount: 4)

            commandEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromMTKTextureLoaderOption(_ input: MTKTextureLoader.Option) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromMTKTextureLoaderOrigin(_ input: MTKTextureLoader.Origin) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalMTKTextureLoaderOptionDictionary(_ input: [String: Any]?) -> [MTKTextureLoader.Option: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (MTKTextureLoader.Option(rawValue: key), value)})
}
