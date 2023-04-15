//
//  SimpleMeshResources.swift
//  MTLearning
//
//  Created by Alexander Pelevinov on 14.04.2023.
//

import Foundation

struct SimpleMeshResources {
    let positions: [SIMD2<Float>]
    let colors: [SIMD4<Float>]
    
    init(
        sideCount: Int,
        radius: Float,
        color: SIMD4<Float>
    ) {
        var positions = [SIMD2<Float>]()
        var colors = [SIMD4<Float>]()
        var angle: Float = .pi / 2
        let deltaAngle = (2 * .pi) / Float(sideCount)
        for _ in 0..<sideCount {
            positions.append(SIMD2<Float>(radius * cos(angle),
                                          radius * sin(angle)))
            colors.append(color)
            angle += deltaAngle
        }
        positions.append(SIMD2<Float>(0, 0))
        colors.append(color)
        
        self.positions = positions
        self.colors = colors
    }
}
