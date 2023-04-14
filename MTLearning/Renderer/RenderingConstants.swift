//
//  RenderingConstants.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 13.04.2023.
//

import Foundation
import simd

func align(_ value: Int, upTo alignment: Int) -> Int {
    return ((value + alignment - 1) / alignment) * alignment
}

final class RenderingConstants {
    var frameIndex: Int
    var currentConstantBufferOffset: Int
    let constantsSize: Int
    let constantsStride: Int

    init() {
        self.frameIndex = 0
        self.constantsSize = MemoryLayout<simd_float4x4>.size
        self.constantsStride = align(constantsSize, upTo: 256)
        self.currentConstantBufferOffset = 0
    }
    
    func calculateCurrentOffset(with maxOutstandingFrameCount: Int) {
        currentConstantBufferOffset = (frameIndex % maxOutstandingFrameCount) * constantsStride
    }
}
