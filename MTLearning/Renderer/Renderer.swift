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
    
    private var time: TimeInterval = 0.0
    
    private var frameSemaphore = DispatchSemaphore(value:
        MaxOutstandingFrameCount)
 
    init(view: MTKView, device: MTLDevice) {
        self.view = view
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.renderingConstants = RenderingConstants()
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
        renderPipelineDescriptor.vertexDescriptor = createVertexDescriptor()
        
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
        var vertexData: [Float] = [
        //    x     y       r    g    b    a
            -100,  -20,    1.0, 0.0, 1.0, 1.0,
             100,  -60,    0.0, 1.0, 1.0, 1.0,
              30,  100,    1.0, 1.0, 0.0, 1.0,
        ]
        vertexBuffer = device.makeBuffer(
            bytes: &vertexData,
            length: MemoryLayout<Float>.stride * vertexData.count,
            options: .storageModeShared)
        constantsBuffer = device.makeBuffer(
            length: renderingConstants.constantsStride * MaxOutstandingFrameCount,
            options: .storageModeShared)
    }
    
}

extension Renderer: MTKViewDelegate{
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
        frameSemaphore.wait()
        updateConstants()
        drawTriangle()
    }
    
}

//MARK: - Graphics Pipeline

private extension Renderer {
 
    func drawTriangle() {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        )!
        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        renderCommandEncoder.setVertexBuffer(
            vertexBuffer,
            offset: 0,
            index: 0
        )
        renderCommandEncoder.setVertexBuffer(
            constantsBuffer,
            offset: renderingConstants.currentConstantBufferOffset,
            index: 1
        )
        renderCommandEncoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 3
        )
        renderCommandEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.addCompletedHandler { [weak self] _ in
                self?.frameSemaphore.signal()
            }
        commandBuffer.commit()
        renderingConstants.frameIndex += 1
    }
    
    func createVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 6
        
        return vertexDescriptor
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
        time += 1.0 / Double(view.preferredFramesPerSecond)
        let floatTime = Float(time)
        
        let pulseRate: Float = 1.5
        let scaleFactor = 1.0 + 0.5 * cos(pulseRate * floatTime)
        let scale = SIMD2<Float>(scaleFactor, scaleFactor)
        let scaleMatrix = simd_float4x4(scale2D: scale)
        
        let rotationRate: Float = 2.5
        let rotationAngle = rotationRate * floatTime
        let rotationMatrix = simd_float4x4(rotateZ: rotationAngle)
        
        let orbitalRadius: Float = 200
        let translation = orbitalRadius * SIMD2<Float>(cos(floatTime), sin(floatTime))
        let translationMatrix = simd_float4x4(translate2D: translation)
        
        let modelMatrix = translationMatrix * rotationMatrix * scaleMatrix
        return modelMatrix
    }
    
}

//MARK: - ComputePipeline

private extension Renderer {
    
    func addArrays() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to create default shader library")
        }
        
        for name in library.functionNames {
            let function = library.makeFunction(name: name)!
            print("\(function)")
        }
        
        let kernelFunction = library.makeFunction(name: "add_two_values")!
        let computePipeline = try! device.makeComputePipelineState(function: kernelFunction)
        
        let threadsPerThreadgroup = MTLSize(width: 32, height: 1, depth: 1)
        let threadgroupCount = MTLSize(width: 8, height: 1, depth: 1)
        let elementCount = 256
        let inputBufferA = device.makeBuffer(
            length: MemoryLayout<Float>.stride * elementCount, options: .storageModeShared
        )!
        let inputBufferB = device.makeBuffer(
            length: MemoryLayout<Float>.stride * elementCount, options: .storageModeShared
        )!
        let outputBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * elementCount, options: .storageModeShared
        )!
        
        let inputsA = inputBufferA.contents().assumingMemoryBound(to: Float.self)
        let inputsB = inputBufferB.contents().assumingMemoryBound(to: Float.self)
        for i in 0..<elementCount {
            inputsA[i] = Float(i)
            inputsB[i] = Float(elementCount - i)
        }
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(computePipeline)
        
        commandEncoder.setBuffer(inputBufferA, offset: 0, index: 0)
        commandEncoder.setBuffer(inputBufferB, offset: 0, index: 1)
        commandEncoder.setBuffer(outputBuffer, offset: 0, index: 2)
        
        commandEncoder.dispatchThreadgroups(
            threadgroupCount,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
        commandEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler { _ in
            let outputs = outputBuffer.contents().assumingMemoryBound(to: Float.self)
            for i in 0..<elementCount {
                print("Output element \(i) is \(outputs[i])")
            }
        }
        commandBuffer.commit()
    }
    
}
