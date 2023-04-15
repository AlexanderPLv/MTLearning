//
//  SimpleMesh.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 14.04.2023.
//

import Foundation
import Metal

class SimpleMesh {
    
    let vertexBuffers: [MTLBuffer]
    let vertexDescriptor: MTLVertexDescriptor
    let vertexCount: Int
    let primitiveType: MTLPrimitiveType = .triangle
    
    let indexBuffer: MTLBuffer
    let indexType: MTLIndexType = .uint16
    let indexCount: Int
    
    private init(
        vertexBuffers: [MTLBuffer],
        vertexDescriptor: MTLVertexDescriptor,
        vertexCount: Int,
        indexBuffer: MTLBuffer,
        indexCount: Int
    ) {
        self.vertexBuffers = vertexBuffers
        self.vertexDescriptor = vertexDescriptor
        self.vertexCount = vertexCount
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
    }
    
}

extension SimpleMesh {
    
    convenience init(
        indexedPlanarPolygonSideCount sideCount: Int,
        radius: Float,
        color: SIMD4<Float>,
        device: MTLDevice
    ) {
        let resources = SimpleMeshResources(sideCount: sideCount, radius: radius, color: color)
        
        let positionBuffer = device.makeBuffer(
            bytes: resources.positions,
            length: MemoryLayout<SIMD2<Float>>.stride * resources.positions.count,
            options: .storageModeShared
        )!
        positionBuffer.label = "Vertex Positions"
        
        let colorBuffer = device.makeBuffer(
            bytes: resources.colors,
            length: MemoryLayout<SIMD4<Float>>.stride * resources.colors.count,
            options: .storageModeShared
        )!
        colorBuffer.label = "Vertex Colors"
        
        var indices = [UInt16]()
        let count = UInt16(sideCount)
        for i in 0..<count {
            indices.append(i)
            indices.append(count)
            indices.append((i + 1) % count)
        }
        
        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.size * indices.count,
            options: .storageModeShared)!
        
        self.init(vertexBuffers: [positionBuffer, colorBuffer],
                  vertexDescriptor: SimpleMesh.defaultVertexDescriptor,
                  vertexCount: resources.positions.count,
                  indexBuffer: indexBuffer,
                  indexCount: indices.count)
    }
    
    private static var defaultVertexDescriptor: MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.layouts[1].stride = MemoryLayout<SIMD4<Float>>.stride
        return vertexDescriptor
    }
    
}
