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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        device = MTLCreateSystemDefaultDevice()
        metalView.device = device
        metalView.delegate = self
    }
}

extension ViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
        metalView.clearColor = MTLClearColor(
            red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0
        )
        
        let commandQueue = device.makeCommandQueue()!
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
