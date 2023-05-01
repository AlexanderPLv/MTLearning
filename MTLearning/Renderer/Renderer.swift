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

class Renderer: NSObject {

    private let view: MTKView
    private let device: MTLDevice
    
    private var vertexDescriptor: MTLVertexDescriptor!
    private var textureDescriptor: MTLTextureDescriptor!
    private let depthStencilDescriptor: MTLDepthStencilDescriptor
    
    private let commandQueue: MTLCommandQueue
    private var constantBuffer: ConstantBuffer
    
    private let depthStencilState: MTLDepthStencilState
    private var samplerState: MTLSamplerState!
    private var renderPipelineState: MTLRenderPipelineState!

    var nodes = [Node]()
    var boxNode: Node!
    var sphereNode: Node!

    private var time: TimeInterval = 0.0
    private var frameSemaphore: DispatchSemaphore

    init(view: MTKView, device: MTLDevice) {
        self.view = view
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.constantBuffer = ConstantBuffer()
        self.depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.depthCompareFunction = .less
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        self.frameSemaphore = DispatchSemaphore(value: constantBuffer.maxOutstandingFrameCount)
        super.init()
        
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
        makeResources()
        makePipeline()
    }

}

private extension Renderer {
    
    func makeTexture(device: MTLDevice) -> MTLTexture? {
        let texture = device.makeTexture(descriptor: textureDescriptor)
        return texture
    }
    
    func loadTexture(device: MTLDevice) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option : Any] = [
            .textureUsage : MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode : MTLStorageMode.private.rawValue
        ]
        let texture = try? textureLoader.newTexture(name: "uvGrid",
                                                scaleFactor: 1.0,
                                                bundle: nil,
                                                options: options)
        return texture
    }
    
    func setupSampleDescriptor() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.mipFilter = .nearest
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)!
    }

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

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError("Error while creating render pipeline state: \(error)")
        }
        setupSampleDescriptor()
    }

    func makeResources() {
        allocateMesh()
        constantBuffer.buffer = device.makeBuffer(
            length: constantBuffer.length(),
            options: .storageModeShared
        )
        constantBuffer.buffer.label = "Dynamic Constant Buffer"
    }

    func allocateMesh() {
        var texture = loadTexture(device: device)
        let mdlVertexDescriptor = createMDLVertexDescriptor()
        do {
            let sphere = try createMtkMesh(with: device, vertexDescriptor: mdlVertexDescriptor, mdlSphereMesh)
            let box = try createMtkMesh(with: device, vertexDescriptor: mdlVertexDescriptor, mdlCubeMesh)
            sphereNode = Node(mesh: sphere)
            sphereNode.texture = texture
            boxNode = Node(mesh: box)
            boxNode.texture = texture
            nodes = [boxNode, sphereNode]

            vertexDescriptor = try MTKMetalVertexDescriptorFromModelIOWithError(mdlVertexDescriptor)
        } catch let error {
            fatalError(error.localizedDescription)
        }
    }

    func createMtkMesh(
        with device: MTLDevice,
        vertexDescriptor: MDLVertexDescriptor,
        _ mdlMesh: (MTLDevice, MDLVertexDescriptor) -> MDLMesh
    ) throws -> MTKMesh {
        do {
            let mtkMesh = try MTKMesh(
                mesh: mdlMesh(device, vertexDescriptor),
                device: device
            )
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
            inwardNormals: true,
            geometryType: .triangles,
            allocator: allocator
        )
        mesh.vertexDescriptor = vertexDescriptor
        return mesh
    }

    func mdlCubeMesh(with device: MTLDevice, vertexDescriptor: MDLVertexDescriptor) -> MDLMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let mesh = MDLMesh(
            boxWithExtent: SIMD3<Float>(1.4, 1.4, 1.4),
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
        
        vertexDescriptor.vertexAttributes[2].name =
            MDLVertexAttributeTextureCoordinate
        vertexDescriptor.vertexAttributes[2].format = .float2
        vertexDescriptor.vertexAttributes[2].offset = 24
        vertexDescriptor.vertexAttributes[2].bufferIndex = 0
        
        vertexDescriptor.bufferLayouts[0].stride = 32
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

        time += (1.0 / Double(view.preferredFramesPerSecond))
        let angle = Float(time)
        
        let rotationAxis = normalize(SIMD3<Float>(0.3, 0.7, 0.1))
        let rotation = rotate(about: rotationAxis, by: angle)
        
        boxNode.transform = translate(by: -2) * rotation
        sphereNode.transform = translate(by: 2) * rotation
    
        for (objectIndex, node) in nodes.enumerated() {
            let transformMatrix = makeTransformMatrix(with: node.worldTransform)
            var constants = NodeConstants(modelViewProjectionMatrix: transformMatrix)

            let offset = constantBuffer.calculateBufferOffset(by: objectIndex)
            let constantsPointer = constantBuffer.buffer.contents().advanced(by: offset)
            constantsPointer.copyMemory(from: &constants, byteCount: constantBuffer.size)
        }
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
            guard let mesh = node.mesh else { continue }

            let offset = constantBuffer.calculateBufferOffset(by: objectIndex)
            renderCommandEncoder.setVertexBuffer(constantBuffer.buffer,
                                                 offset: offset,
                                                 index: 2)

            for (i, meshBuffer) in mesh.vertexBuffers.enumerated() {
                renderCommandEncoder.setVertexBuffer(meshBuffer.buffer,
                                                     offset: meshBuffer.offset,
                                                     index: i)
            }
            
            renderCommandEncoder.setFragmentTexture(node.texture, index: 0)
            renderCommandEncoder.setFragmentSamplerState(samplerState, index: 0)

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

private extension Renderer {

    func rotate(about value: SIMD3<Float>, by angle: Float) -> float4x4 {
        simd_float4x4(rotateAbout: value, byAngle: angle)
    }

    func translate(by value: Float) -> float4x4 {
        simd_float4x4(translate: SIMD3<Float>(value, 0, 0))
    }

    func scale(by value: Float) -> float4x4 {
        simd_float4x4(scale: SIMD3<Float>(repeating: value))
    }

    func makeViewMatrix() -> float4x4 {
        let cameraPosition = SIMD3<Float>(0, 0, 5)
        let viewMatrix = simd_float4x4(translate: -cameraPosition)
        return viewMatrix
    }

    func makeTransformMatrix(with worldMatrix: float4x4) -> float4x4 {
        let viewMatrix = makeViewMatrix()
        let projectionMatrix = makeProjectionMatrix()
        let transform = projectionMatrix * viewMatrix * worldMatrix
        return transform
    }

    func makeProjectionMatrix() -> float4x4 {
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        let projectionMatrix = simd_float4x4(
            perspectiveProjectionFoVY: .pi / 3,
            aspectRatio: aspectRatio,
            near: 0.01,
            far: 100
        )
        return projectionMatrix
    }
}
