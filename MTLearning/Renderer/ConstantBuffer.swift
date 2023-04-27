//
//  ConstantBuffer.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 13.04.2023.
//

import Metal
import simd

final class ConstantBuffer {
    
    var buffer: MTLBuffer!
    
    private let maxObjectCount = 16
    var frameIndex: Int
    let size: Int
    let maxOutstandingFrameCount: Int
    
    lazy var stride: Int = {
        align(size, upTo: 256)
    }()

    init() {
        self.frameIndex = 0
        self.size = MemoryLayout<simd_float4x4>.size
        self.maxOutstandingFrameCount = 3
    }
    
    private func align(_ value: Int, upTo alignment: Int) -> Int {
        return ((value + alignment - 1) / alignment) * alignment
    }
    
    func length() -> Int {
        stride * maxObjectCount * maxOutstandingFrameCount
    }
    
    func calculateBufferOffset(by objectIndex: Int) -> Int {
        let frameConstantsOffset = (frameIndex % maxOutstandingFrameCount) * maxObjectCount * stride
        let objectConstantOffset = frameConstantsOffset + (objectIndex * stride)
        return objectConstantOffset
    }
}
