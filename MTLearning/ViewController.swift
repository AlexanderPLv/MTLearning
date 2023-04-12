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
    private var device: MTLDevice!
    private var renderer: Renderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        device = MTLCreateSystemDefaultDevice()
        renderer = Renderer(view: metalView, device: device)
    }
}
