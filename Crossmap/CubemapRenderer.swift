//
//  CubemapRenderer.swift
//  MetalCubemapping
//
//  Created by Mark Lim Pak Mun on 27/08/2020.
//  Copyright © 2020 Mark Lim Pak Mun. All rights reserved.
//

import Foundation
import MetalKit
import SceneKit
import SceneKit.ModelIO
import simd

class CubemapRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let mtkView: MTKView
    let commandQueue: MTLCommandQueue!

    var u_time: Float = 0.0
    var u_timeBuffer: MTLBuffer!
    var u_mouseBuffer: MTLBuffer!

    var vertexDescriptor: MTLVertexDescriptor!
    var skyboxRenderPipelineState: MTLRenderPipelineState!
    var renderToTextureRenderPipelineState: MTLRenderPipelineState!

    var skyboxMesh: Mesh!
    var uniformsBuffers = [MTLBuffer]()

    var skyBoxTextures = [MTLTexture?]()
    var cubeMapTexture: MTLTexture!
    var cubeMapDepthTexture: MTLTexture!
    var depthTexture: MTLTexture!

    var renderToTexturePassDescriptor: MTLRenderPassDescriptor!
    var skyboxDepthStencilState: MTLDepthStencilState!
    var computePipelineState: MTLComputePipelineState!

    init(view: MTKView, device: MTLDevice) {
        self.mtkView = view
        self.device = device
        // Create a new command queue
        self.commandQueue = device.makeCommandQueue()

        super.init()
        // The currentDrawable object's texture will be used for read/write operations.
        self.mtkView.framebufferOnly = false

        //let names = ["px.png", "nx.png", "py.png", "ny.png", "pz.png", "nz.png"]
        let names = ["px.hdr", "nx.hdr", "py.hdr", "ny.hdr", "pz.hdr", "nz.hdr"]
        buildResources(with: names, isHDR: true)
        buildPipelineStates()
        // Note: Don't write to the skybox's depth attachment
        skyboxDepthStencilState = buildDepthStencilState(device: device,
                                                         isWriteEnabled: false)
        createCubemapTexture()
    }


    // The names of radiance files must have the file extension "hdr"
    // All file names are case sensitive when stored in the Resources folder.
    func buildResources(with names: [String], isHDR: Bool) {
        skyboxMesh = BoxMesh(withSize: 2,
                             device: device)
        u_timeBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride,
                                         options: [])
        u_timeBuffer.label = "time uniform"
        u_mouseBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride,
                                          options: [])
        u_mouseBuffer.label = "mouse coords uniform"

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
   }

    func buildPipelineStates() {
        // Load all the shader files with a metal file extension in the project
        guard let library = device.makeDefaultLibrary()
        else {
            fatalError("Could not load default library from main bundle")
        }
       
        // Create the render pipeline state for rendering to the offscreen texture.
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

        // Create the compute pipeline state for the drawable render pass.
        let kernel = library.makeFunction(name: "compute")!
        do {
            computePipelineState = try device.makeComputePipelineState(function: kernel)
        }
        catch {
            fatalError("Could not create compute pipeline state object: \(error)")
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
    }

    // called per frame update
    func draw(in view: MTKView) {
        let commandBuffer = commandQueue.makeCommandBuffer()!

        if  let drawable = view.currentDrawable {
            let drawableSize = drawable.layer.drawableSize
            if (drawableSize.width != CGFloat(depthTexture.width) || drawableSize.height != CGFloat(depthTexture.height)) {
                buildDepthBuffer()
            }

            updateTime()
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()
            
            commandEncoder!.setComputePipelineState(computePipelineState)
            commandEncoder!.setTexture(drawable.texture,
                                       index: 0)
            commandEncoder!.setTexture(cubeMapTexture,
                                       index: 1)
            // We don't have to pass the resolution
            commandEncoder!.setBuffer(u_timeBuffer,
                                      offset: 0,
                                      index: 0)
            commandEncoder!.setBuffer(u_mouseBuffer,
                                      offset: 0,
                                      index: 1)
            
            let width = computePipelineState.threadExecutionWidth
            let height = computePipelineState.maxTotalThreadsPerThreadgroup / width
            let threadsPerThreadgroup = MTLSizeMake(width, height, 1)

            if #available(macOS 10.13, iOS 11.0, *) {
                let threadsPerGrid = MTLSizeMake(drawable.texture.width, drawable.texture.height, 1)
                commandEncoder!.dispatchThreads(threadsPerGrid,
                                                threadsPerThreadgroup: threadsPerThreadgroup)
            }
            else {
                let threadgroupsPerGrid = MTLSizeMake((drawable.texture.width + width - 1) / width,
                                                      (drawable.texture.height + height - 1) / height,
                                                      1)
                commandEncoder!.dispatchThreadgroups(threadgroupsPerGrid,
                                                     threadsPerThreadgroup: threadsPerThreadgroup)
            }
            commandEncoder!.endEncoding()
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
