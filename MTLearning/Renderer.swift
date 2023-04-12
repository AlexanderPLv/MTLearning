//
//  Renderer.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 11.04.2023.
//

import Foundation
import Metal
import MetalKit

class Renderer: NSObject {
    
    private let view: MTKView
    private let device: MTLDevice
    
    private let commandQueue: MTLCommandQueue
    private var renderPipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
 
    init(view: MTKView, device: MTLDevice) {
        self.view = view
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
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
        var positions = [
                SIMD2<Float>(-0.8,  0.4),
                SIMD2<Float>( 0.4, -0.8),
                SIMD2<Float>( 0.8,  0.8)
        ]
        vertexBuffer = device.makeBuffer(
            bytes: &positions,
            length: MemoryLayout<SIMD2<Float>>.stride * positions.count,
            options: .storageModeShared
        )
    }
    
}

extension Renderer: MTKViewDelegate{
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
        //clearColor(view)
        drawTriangle()
        
    }
    
}

//MARK: - Graphics Pipeline

extension Renderer {
 
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
        renderCommandEncoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 3
        )
        renderCommandEncoder.endEncoding()
            commandBuffer.present(view.currentDrawable!)
            commandBuffer.commit()
    }
    
}

//MARK: - Clear View Color
extension Renderer {
    func clearColor(_ view: MTKView) {
        view.clearColor = MTLClearColor(
            red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0
        )
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
            print("Didn't get a render pass descriptor from MTKView; dropping frame...")
            return
        }
        let renderPassEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        )!
        renderPassEncoder.endEncoding()
        
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
}

//MARK: - ComputePipeline

extension Renderer {
    
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
