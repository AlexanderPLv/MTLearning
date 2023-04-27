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

struct Node {
    var mesh: MTKMesh
    var modelMatrix: simd_float4x4 = matrix_identity_float4x4
}

class Renderer: NSObject {
    
    private let view: MTKView
    private let device: MTLDevice
    
    private let commandQueue: MTLCommandQueue
    private var renderPipelineState: MTLRenderPipelineState!
    private var vertexDescriptor: MTLVertexDescriptor!
    private var constantBuffer: ConstantBuffer
    
    private let depthStencilDescriptor: MTLDepthStencilDescriptor
    private let depthStencilState: MTLDepthStencilState
    
    private var nodes = [Node]()
    
    private var time: TimeInterval = 0.0
    private var frameSemaphore: DispatchSemaphore
 
    init(view: MTKView, device: MTLDevice) {
        self.view = view
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.constantBuffer = ConstantBuffer()
        self.depthStencilDescriptor = MTLDepthStencilDescriptor()
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        self.frameSemaphore = DispatchSemaphore(value: constantBuffer.maxOutstandingFrameCount)
        super.init()
        
        let mdlVertexDescriptor = createMDLVertexDescriptor()
        do {
            let sphere = try createMtkMesh(with: device, vertexDescriptor: mdlVertexDescriptor, mdlMeshBuilder: mdlSphereMesh)
            let cube = try createMtkMesh(with: device, vertexDescriptor: mdlVertexDescriptor, mdlMeshBuilder: mdlCubeMesh)
            
            nodes.append(Node(mesh: sphere))
            nodes.append(Node(mesh: cube))
            
            vertexDescriptor = try MTKMetalVertexDescriptorFromModelIOWithError(mdlVertexDescriptor)
        } catch let error {
            print(error.localizedDescription)
        }
        
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        
        view.device = device
        view.delegate = self
        view.clearColor = MTLClearColor(
            red: 0.95,
            green: 0.95,
            blue: 0.95,
            alpha: 1.0
        )
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
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(
            name: "vertex_main"
        )!
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(
            name: "fragment_main"
        )!
        
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.depthCompareFunction = .less
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError("Error while creating render pipeline state: \(error)")
        }
    }
    
    func makeResources() {
        constantBuffer.buffer = device.makeBuffer(
            length: constantBuffer.length(),
            options: .storageModeShared
        )
        constantBuffer.buffer.label = "Dynamic Constant Buffer"
    }
    
    func createMtkMesh(
        with device: MTLDevice,
        vertexDescriptor: MDLVertexDescriptor,
        mdlMeshBuilder: (MTLDevice, MDLVertexDescriptor) -> MDLMesh
    ) throws -> MTKMesh {
        do {
            let mdlMesh = mdlMeshBuilder(device, vertexDescriptor)
            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)
            return mtkMesh
        } catch let error {
            throw error
        }
    }
    
    func mdlSphereMesh(with device: MTLDevice, vertexDescriptor: MDLVertexDescriptor) -> MDLMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let mesh = MDLMesh(
            sphereWithExtent: SIMD3<Float>(1, 1, 1),
            segments: SIMD2<UInt32>(24, 24),
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
        mesh.vertexDescriptor = vertexDescriptor
        return mesh
    }
    
    func mdlCubeMesh(with device: MTLDevice, vertexDescriptor: MDLVertexDescriptor) -> MDLMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let mesh = MDLMesh(
            boxWithExtent: SIMD3<Float>(1.3, 1.3, 1.3),
            segments: SIMD3<UInt32>(1, 1, 1),
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
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
        
        let rotationMatrix = makeRotationMatrix()
        
        nodes[0].modelMatrix = simd_float4x4(translate: SIMD3<Float>(-2, 0, 0)) * rotationMatrix
        nodes[1].modelMatrix = simd_float4x4(translate: SIMD3<Float>(2, 0, 0)) * rotationMatrix
        
        for (objectIndex, node) in nodes.enumerated() {
            var transformMatrix = makeTransformMatrix(with: node.modelMatrix)
            
            let offset = constantBuffer.calculateBufferOffset(by: objectIndex)
            let constants = constantBuffer.buffer.contents().advanced(by: offset)
            constants.copyMemory(from: &transformMatrix, byteCount: constantBuffer.size)
        }
    }
    
    func makeViewMatrix() -> float4x4 {
        let cameraPosition = SIMD3<Float>(0, 0, 5)
        let viewMatrix = simd_float4x4(translate: -cameraPosition)
        return viewMatrix
    }
    
    func makeTransformMatrix(with modelMatrix: float4x4) -> float4x4 {
        let viewMatrix = makeViewMatrix()
        let projectionMatrix = makeProjectionMatrix()
        let transform = projectionMatrix * viewMatrix * modelMatrix
        return transform
    }
    
    func makeProjectionMatrix() -> float4x4 {
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        let projectionMatrix = simd_float4x4(perspectiveProjectionFoVY: .pi / 3,
                                                     aspectRatio: aspectRatio,
                                                     near: 0.01,
                                                     far: 100)
        return projectionMatrix
    }
    
    func makeRotationMatrix() -> float4x4 {
        time += (1.0 / Double(view.preferredFramesPerSecond))
        let angle = Float(time)
        let rotationAxis = normalize(SIMD3<Float>(0.3, 0.7, 0.2))
        let rotationMatrix = simd_float4x4(rotateAbout: rotationAxis, byAngle: angle)
        return rotationMatrix
    }
    
    func drawMesh() {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderCommandEncoder.setDepthStencilState(depthStencilState)
        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        
        
        renderCommandEncoder.setFrontFacing(.counterClockwise)
        renderCommandEncoder.setCullMode(.back)
        
        for (objectIndex, node) in nodes.enumerated() {
            let mesh = node.mesh
            
            renderCommandEncoder.setVertexBuffer(constantBuffer.buffer,
                                                 offset: constantBuffer.calculateBufferOffset(by: objectIndex),
                                                 index: 2)
            
            for (i, meshBuffer) in mesh.vertexBuffers.enumerated() {
                renderCommandEncoder.setVertexBuffer(meshBuffer.buffer,
                                                     offset: meshBuffer.offset,
                                                     index: i)
            }
            
            for submesh in mesh.submeshes {
                let indexBuffer = submesh.indexBuffer
                renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                           indexCount: submesh.indexCount,
                                                           indexType: submesh.indexType,
                                                           indexBuffer: indexBuffer.buffer,
                                                           indexBufferOffset: indexBuffer.offset)
            }
        }
        
        renderCommandEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }
        commandBuffer.commit()
        
        constantBuffer.frameIndex += 1
    }
    
}
