//
//  ViewController.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 09.04.2023.
//

import Metal
import MetalKit

class ViewController: NSViewController {
    
    @IBOutlet weak var metalView: MTKView!
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        metalView.device = device
        metalView.delegate = self
        
    //    addArrays()
    }
}

extension ViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
       // clearColor(view)
    }
    
    func clearColor(_ view: MTKView) {
        metalView.clearColor = MTLClearColor(
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

extension ViewController {
    
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

//MARK: - Graphics Pipeline

extension ViewController {
    
}
