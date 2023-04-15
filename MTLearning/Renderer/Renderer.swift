//
//  Renderer.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 11.04.2023.
//

import Foundation
import Metal
import MetalKit

let MaxOutstandingFrameCount = 3

class Renderer: NSObject {
    
    private let view: MTKView
    private let device: MTLDevice
    
    private let commandQueue: MTLCommandQueue
    private var renderPipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    
    private var renderingConstants: RenderingConstants
    private var constantsBuffer: MTLBuffer!
    
    private let mesh: SimpleMesh
    
    private var time: TimeInterval = 0.0
    private var frameSemaphore = DispatchSemaphore(value:
        MaxOutstandingFrameCount)
 
    init(view: MTKView, device: MTLDevice) {
        self.view = view
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.renderingConstants = RenderingConstants()
        self.mesh = SimpleMesh(indexedPlanarPolygonSideCount: 8,
                               radius: 250,
                               color: SIMD4<Float>(0.0, 0.5, 0.8, 1.0),
                               device: device)
        super.init()
        view.device = device
        view.delegate = self
        view.clearColor = MTLClearColor(red: 0.95,
                                        green: 0.95,
                                        blue: 0.95,
                                        alpha: 1.0)
        makePipeline()
        makeResources()
    }
    
}

private extension Renderer {
    
    func makePipeline() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to create default Metal library")
        }
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexDescriptor = mesh.vertexDescriptor
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(
            name: "vertex_main"
        )!
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(
            name: "fragment_main"
        )!
        
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError("Error while creating render pipeline state: \(error)")
        }
    }
    
    func makeResources() {
        constantsBuffer = device.makeBuffer(
            length: renderingConstants.constantsStride * MaxOutstandingFrameCount,
            options: .storageModeShared
        )
        constantsBuffer.label = "Dynamic Constant Buffer"
    }
    
}

extension Renderer: MTKViewDelegate{
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
        frameSemaphore.wait()
        updateConstants()
        drawSimpleMesh()
    }
    
}

//MARK: - Graphics Pipeline

private extension Renderer {
    
    func drawSimpleMesh() {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        
        
        
        for (i, vertexBuffer) in mesh.vertexBuffers.enumerated() {
            renderCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: i)
        }
        renderCommandEncoder.setVertexBuffer(constantsBuffer, offset: renderingConstants.currentConstantBufferOffset, index: 2)
        
        renderCommandEncoder.drawIndexedPrimitives(type: mesh.primitiveType,
                                                   indexCount: mesh.indexCount,
                                                   indexType: mesh.indexType,
                                                   indexBuffer: mesh.indexBuffer,
                                                   indexBufferOffset: 0)
        renderCommandEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }
        commandBuffer.commit()
        
        renderingConstants.frameIndex += 1
    }
    
    func updateConstants() {
        var transformMatrix = makeTransformMatrix()
        renderingConstants.calculateCurrentOffset(with: MaxOutstandingFrameCount)
        let constants = constantsBuffer.contents()
            .advanced(by: renderingConstants.currentConstantBufferOffset)
        constants.copyMemory(from: &transformMatrix,
                             byteCount: renderingConstants.constantsSize)
    }
    
    func makeTransformMatrix() -> float4x4 {
        let modelMatrix = makeModelMatrix()
        let projectionMatrix = makeProjectionMatrix()
        let transform = projectionMatrix * modelMatrix
        return transform
    }
    
    func makeProjectionMatrix() -> float4x4 {
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        let canvasWidth: Float = 800
        let canvasHeight = canvasWidth / aspectRatio
        let projectionMatrix = simd_float4x4(
            orthographicProjectionWithLeft: -canvasWidth / 2,
            top: canvasHeight / 2,
            right: canvasWidth / 2,
            bottom: -canvasHeight / 2,
            near: 0.0,
            far: 1.0
        )
        return projectionMatrix
    }
    
    func makeModelMatrix() -> float4x4 {
        let floatTime = Float(time)
        
        let rotationRate: Float = 2.5
        let rotationAngle = rotationRate * floatTime
        let rotationMatrix = simd_float4x4(rotateZ: rotationAngle)
        
        let modelMatrix = rotationMatrix
        return modelMatrix
    }
    
}
