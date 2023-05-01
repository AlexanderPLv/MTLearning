//
//  Node.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 27.04.2023.
//

import MetalKit

final class Node {
    
    var mesh: MTKMesh?
    var texture: MTLTexture?
    var transform: simd_float4x4 = matrix_identity_float4x4
    
    weak var parentNode: Node?
    private(set) var childNodes = [Node]()
    
    var worldTransform: simd_float4x4 {
        if let parent = parentNode {
            return parent.worldTransform * transform
        } else {
            return transform
        }
    }
    
    init(mesh: MTKMesh) {
        self.mesh = mesh
    }
    
    func addChildNode(_ node: Node) {
        childNodes.append(node)
        node.parentNode = self
    }
    func removeFromParent() {
        parentNode?.removeChildNode(self)
    }
    private func removeChildNode(_ node: Node) {
        childNodes.removeAll { $0 === node }
    }
}
