//
//  Renderer.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 11.04.2023.
//

import Foundation
import Metal
import MetalKit
import ModelIO

let MaxOutstandingFrameCount = 3

class Renderer: NSObject {
    
    private let view: MTKView
    private let device: MTLDevice
    
    private let commandQueue: MTLCommandQueue
    private var renderPipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    
    private var renderingConstants: RenderingConstants
    private var constantsBuffer: MTLBuffer!
    
    private var mesh: MTKMesh!
    
    private var time: TimeInterval = 0.0
    private var frameSemaphore = DispatchSemaphore(value:
        MaxOutstandingFrameCount)
 
    init(view: MTKView, device: MTLDevice) {
        self.view = view
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.renderingConstants = RenderingConstants()
        super.init()
        
        let mdlMesh = createMDLMesh(with: device)
        do {
            mesh = try MTKMesh(mesh: mdlMesh, device: device)
        } catch let error {
            print(error.localizedDescription)
        }
        
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
        let vertexDescriptor =
        MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)!
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        
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
    
    func createMDLMesh(with device: MTLDevice) -> MDLMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let mesh = MDLMesh(
            sphereWithExtent: SIMD3<Float>(1, 1, 1),
            segments: SIMD2<UInt32>(24, 24),
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
        let vertexDescriptor = createMDLVertexDescriptor()
        mesh.vertexDescriptor = vertexDescriptor
        
        return mesh
    }
    
    func createMDLVertexDescriptor() -> MDLVertexDescriptor {
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.vertexAttributes[0].name =
            MDLVertexAttributePosition
        vertexDescriptor.vertexAttributes[0].format = .float3
        vertexDescriptor.vertexAttributes[0].offset = 0
        vertexDescriptor.vertexAttributes[0].bufferIndex = 0
        vertexDescriptor.vertexAttributes[1].name =
            MDLVertexAttributeNormal
        vertexDescriptor.vertexAttributes[1].format = .float3
        vertexDescriptor.vertexAttributes[1].offset = 12
        vertexDescriptor.vertexAttributes[1].bufferIndex = 0
        vertexDescriptor.bufferLayouts[0].stride = 24
        return vertexDescriptor
    }
    
}

extension Renderer: MTKViewDelegate{
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
        frameSemaphore.wait()
        updateConstants()
        drawMesh()
    }
    
}

//MARK: - Graphics Pipeline

private extension Renderer {
    
    
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
        let canvasWidth: Float = 5.0
        let canvasHeight = canvasWidth / aspectRatio
        let projectionMatrix =
        simd_float4x4(orthographicProjectionWithLeft: -canvasWidth / 2,
                      top: canvasHeight / 2,
                      right: canvasWidth / 2,
                      bottom: -canvasHeight / 2,
                      near: -1,
                      far: 1)
        return projectionMatrix
    }
    
    func makeModelMatrix() -> float4x4 {
        return matrix_identity_float4x4
    }
    
    func drawMesh() {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        
        renderCommandEncoder.setFrontFacing(.counterClockwise)
        renderCommandEncoder.setCullMode(.back)
        
        for (i, meshBuffer) in mesh.vertexBuffers.enumerated() {
            renderCommandEncoder.setVertexBuffer(
                meshBuffer.buffer,
                offset: meshBuffer.offset,
                index: i)
        }
        renderCommandEncoder.setVertexBuffer(
            constantsBuffer,
            offset: renderingConstants.currentConstantBufferOffset,
            index: 2
        )
        for submesh in mesh.submeshes {
            let indexBuffer = submesh.indexBuffer
            renderCommandEncoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: indexBuffer.buffer,
                indexBufferOffset: indexBuffer.offset)
        }
        
        renderCommandEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }
        commandBuffer.commit()
        
        renderingConstants.frameIndex += 1
    }
    
}
