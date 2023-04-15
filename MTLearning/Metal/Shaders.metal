//
//  MTLfile.metal
//  MTLearning
//
//  Created by Alexander Pelevinov on 10.04.2023.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant float4x4 &transform [[buffer(2)]]
    ) {
    VertexOut out;
        out.position = transform * float4(in.position, 0.0, 1.0);
        out.color = in.color;
        return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}

kernel void add_two_values(constant float *inputsA [[buffer(0)]],
                           constant float *inputsB [[buffer(1)]],
                           device float *outputs   [[buffer(2)]],
                           uint index [[thread_position_in_grid]])
{
    outputs[index] = inputsA[index] + inputsB[index];
}
