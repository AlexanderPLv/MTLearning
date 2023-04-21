//
//  MDLVertexDescriptor+Ext.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 21.04.2023.
//

import ModelIO

extension MDLVertexDescriptor {
    var vertexAttributes: [MDLVertexAttribute] {
        return attributes as! [MDLVertexAttribute]
    }
    var bufferLayouts: [MDLVertexBufferLayout] {
        return layouts as! [MDLVertexBufferLayout]
    }
}
