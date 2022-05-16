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

    var skyboxDepthStencilState: MTLDepthStencilState!
    var computePipelineState: MTLComputePipelineState!

    init(view: MTKView, device: MTLDevice) {
        self.mtkView = view
        self.device = device
        // Create a new command queue
        self.commandQueue = device.makeCommandQueue()

        super.init()

        buildResources()
        buildPipelineStates()
        // Note: Don't write to the skybox's depth attachment
        skyboxDepthStencilState = buildDepthStencilState(device: device,
                                                         isWriteEnabled: false)
        createCubemapTexture("Cube Texture")
        let point = NSPoint(x: mtkView.frame.width/2,
                            y: mtkView.frame.height/2)
        setMouseCoords(point)
    }


    // The names of radiance files must have the file extension "hdr"
    // All file names are case sensitive when stored in the Resources folder.
    func buildResources() {
        skyboxMesh = BoxMesh(withSize: 2,
                             device: device)

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

        // Load the vertex program into the library
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
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

    // The six 2D images are in the Assets.xcassets folder
    // Can't flipped the images vertically - probably compressed
    func createCubemapTexture(_ name: String) {
        let options: [MTKTextureLoader.Option : Any] = [
            .textureUsage : NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue),
            .origin : MTKTextureLoader.Origin.flippedVertically,
        ]
        let textureLoader = MTKTextureLoader(device: self.device)
        
        do {
            // The order of the faces of the cubemap is correct but
            //  all the images are vertically flipped.
            cubeMapTexture = try textureLoader.newTexture(name: name,
                                                          scaleFactor: 1.0,
                                                          bundle: nil,
                                                          options: options)
        }
        catch {
            fatalError("Can't instantiate the cube map texture ")
        }
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
