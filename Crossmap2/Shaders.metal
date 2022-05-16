//  Created by Mark Lim Pak Mun on 11/05/2022.
//  Copyright © 2022 Mark Lim Pak Mun. All rights reserved.
//
//  Credit:
//      https://www.shadertoy.com/view/tdjXDt

#include <metal_stdlib>
using namespace metal;

typedef struct
{
    float4 renderedCoordinates [[position]]; // clip space
    float2 textureCoordinates;
    uint layer[[render_target_array_index]];
} TextureMappingVertex;

// Projects provided vertices to corners of the offscreen texture.
vertex TextureMappingVertex
projectTexture(unsigned int vertex_id  [[ vertex_id ]],
               unsigned int instanceId [[ instance_id ]])
{
    // Triangle strip in NDC (normalized device coords).
    // The vertices' coord system has (-1, -1) at the bottom left.
    float4x4 renderedCoordinates = float4x4(float4(-1.0, -1.0, 0.0, 1.0),
                                            float4( 1.0, -1.0, 0.0, 1.0),
                                            float4(-1.0,  1.0, 0.0, 1.0),
                                            float4( 1.0,  1.0, 0.0, 1.0));
    // The texture coord system has (0, 0) at the upper left
    // The u-axis is +ve right and the v-axis is +ve down
    float4x2 textureCoordinates = float4x2(float2(0.0, 1.0),
                                           float2(1.0, 1.0),
                                           float2(0.0, 0.0),
                                           float2(1.0, 0.0));
    TextureMappingVertex outVertex;
    outVertex.renderedCoordinates = renderedCoordinates[vertex_id];
    outVertex.textureCoordinates = textureCoordinates[vertex_id];
    outVertex.layer = instanceId;
    return outVertex;
}

// Outputs the texture of a face of the cubemap.
fragment half4
outputCubeMapTexture(TextureMappingVertex                       mappingVertex [[stage_in]],
                     array<texture2d<float, access::sample>, 6> colorTextures [[texture(0)]])
{
    constexpr sampler sampler(address::clamp_to_edge,
                              filter::linear,
                              coord::normalized);

    uint whichLayer = mappingVertex.layer;
    float4 colorFrag = colorTextures[whichLayer].sample(sampler,
                                                        mappingVertex.textureCoordinates);
    return half4(colorFrag);
}

////////
constexpr sampler texSampler(mip_filter::linear,
                             mag_filter::linear,
                             min_filter::linear);
typedef struct
{
    float4 renderedCoordinates [[position]]; // clip space
    float2 textureCoordinates;
} MappingVertex;


// Projects provided vertices to corners of offscreen texture.
vertex MappingVertex
vertexShader(unsigned int vertex_id  [[ vertex_id ]])
{
    // Triangle strip in NDC (normalized device coords).
    // The vertices' coord system has (0, 0) at the bottom left.
    float4x4 renderedCoordinates = float4x4(float4(-1.0, -1.0, 0.0, 1.0),   /// (x, y, z, w)
                                            float4( 1.0, -1.0, 0.0, 1.0),
                                            float4(-1.0,  1.0, 0.0, 1.0),
                                            float4( 1.0,  1.0, 0.0, 1.0));
    // The texture coord system has (0, 0) at the upper left
    // The s-axis is +ve right and the t-axis is +ve down
    float4x2 textureCoordinates = float4x2(float2(0.0, 1.0),                /// (s, t)
                                           float2(1.0, 1.0),
                                           float2(0.0, 0.0),
                                           float2(1.0, 0.0));
    MappingVertex outVertex;
    outVertex.renderedCoordinates = renderedCoordinates[vertex_id];
    outVertex.textureCoordinates = textureCoordinates[vertex_id];
    return outVertex;
}


/*
 The six faces of the cubemap texture are displayed as right side up
 in the Debug Shader of XCode.
 */
fragment half4
fragmentShader(MappingVertex        mappingVertex   [[stage_in]],
               texturecube<float>   input           [[texture(0)]],
               constant float2      &u_resolution   [[buffer(0)]],
               constant float       &u_time         [[buffer(1)]],
               constant float2      &u_mouse        [[buffer(2)]])
{
    float4 fragColor = float4(0.0, 0.0, 0.2, 1.0);
    float2 inUV = mappingVertex.textureCoordinates.xy;

    // The samplePos is a 3D vector so the texture must be a cubemap.
    float3 samplePos = float3(0.0f);
    
    // Crude statement to visualize different cube map faces based on UV coordinates
    int x = int(floor(inUV.x / (1.0 / 4.0)));   // 0, 1, 2, 3
    int y = int(floor(inUV.y / (1.0 / 3.0)));   // 0, 1, 2
    
    if (y == 1) {
        // Middle row of 4 squares (-X, +Z, +X, -Z)
        // inUV.x: [0.0, 1.0] ---> uv.x: [0.0, 4.0]
        // inUV.y: [0.333, 0.667] ---> uv.y: [0.0, 1.0]
        float2 uv = float2(inUV.x * 4.0f,
                           (inUV.y - 1.0/3.0) * 3.0);
        // uv.x: [0.0, 4.0] ---> [-1.0, 1.0]
        // uv.y: [0.0, 1.0] ---> [-1.0, 1.0]
        uv = 2.0 * float2(uv.x - float(x), uv.y) - 1.0;
        // Now convert the uv coords into a 3D vector which will be
        //  used to access the correct face of the cube map.
        switch (x) {
            case 0: // NEGATIVE_X
                samplePos = float3(-1.0f, -uv.y,  uv.x);
                break;
            case 1: // POSITIVE_Z
                samplePos = float3( uv.x, -uv.y,  1.0f);
                break;
            case 2: // POSITIVE_X
                samplePos = float3( 1.0,  -uv.y, -uv.x);
                break;
            case 3: // NEGATIVE_Z
                samplePos = float3(-uv.x, -uv.y, -1.0f);
                break;
        }
    }
    else {
        // 2nd vertical row of 3 squares (+Y, -Y)
        if (x == 1) {
            // y = 0 (+Y)
            // inUV.x: [0.250, 0.500] ---> uv.x: [0.0, 1.0]
            // inUV.y: [0.000, 0.333] ---> uv.y: [0.0, 1.0]
            // y = 2 (-Y)
            // inUV.x: [0.250, 0.500] ---> uv.x: [0.0, 1.0]
            // inUV.y: [0.667, 1.000] ---> uv.y: [0.0, 1.0]
            float2 uv = float2((inUV.x - 1.0/4.0) * 4.0,
                               (inUV.y - float(y) / 3.0) * 3.0);
            // Convert [0.0, 1.0] ---> [-1.0, 1.0]
            uv = 2.0 * uv - 1.0;
            switch (y) {
                case 0: // POSITIVE_Y
                    samplePos = float3(uv.x, 1.0f,  uv.y);
                    break;
                case 2: // NEGATIVE_Y
                    samplePos = float3(uv.x,  -1.0f, -uv.y);
                    break;
            }
        }
    }
    if ((samplePos.x != 0.0f) && (samplePos.y != 0.0f)) {
        fragColor = input.sample(texSampler, samplePos);
    }
    return half4(fragColor);
}
