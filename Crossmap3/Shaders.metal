//  Created by Mark Lim Pak Mun on 11/05/2022.
//  Copyright © 2022 Mark Lim Pak Mun. All rights reserved.
//
//  Credit:
//      https://www.shadertoy.com/view/tdjXDt

#include <metal_stdlib>
using namespace metal;

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
    // This is not necessary since we can compute its value.
    outVertex.textureCoordinates = textureCoordinates[vertex_id];
    return outVertex;
}


/*
 The 2D images of the six faces of the cubemap texture are displayed as
  vertically flipped in the Debug Shader of XCode.
 Metal's view coordinate system has its origin at the left top corner.
 The renderedCoordinates passed is equivalent to OpenGL's gl_FragCoord;
  its range for the x-coordinate is [0, width) from left to right
  and for the y-coordinate [0, height) from top to bottom where
  width = width and height = height of the view port respectively.
 The z-coordinate (not used here) has a range of [0, 1.0) and its
 positive direction is into the screen.

 We don't have to use the textureCoordinates passed by the vertex function.
 We can compute the texture coordinate of a fragment from the value of
  renderedCoordinates and the u_resolution parameter.
 
 */
fragment half4
fragmentShader(MappingVertex        mappingVertex   [[stage_in]],
               texturecube<float>   input           [[texture(0)]],
               constant float2      &u_resolution   [[buffer(0)]],
               constant float       &u_time         [[buffer(1)]],
               constant float2      &u_mouse        [[buffer(2)]])
{
    float4 fragColor = float4(0.0, 0.0, 0.2, 1.0);
    //float2 inUV = mappingVertex.textureCoordinates.xy;
    float2 inUV = mappingVertex.renderedCoordinates.xy/u_resolution;

    // The samplePos is a 3D vector so the texture must be a cubemap.
    float3 samplePos = float3(0.0f);

    // Crude statement to visualize different cube map faces based on UV coordinates
    int x = int(floor(inUV.x / (1.0 / 4.0)));   // 0, 1, 2, 3
    int y = int(floor(inUV.y / (1.0 / 3.0)));   // 0, 1, 2

    if (y == 1) {
        // middle row of 4 squares
        float2 uv = float2(inUV.x * 4.0f,
                           (inUV.y - 1.0/3.0) * 3.0);

        uv = 2.0 * float2(uv.x - float(x), uv.y) - 1.0;
        uv.y = -uv.y;       // flip
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
        // 2nd vertical row; y = 0 or y = 2
        if (x == 1) {
            float2 uv = float2((inUV.x - 1.0/4.0) * 4.0,
                               (inUV.y - float(y) / 3.0) * 3.0);
    
            // Convert [0.0, 1.0] ---> [-1.0, 1.0]
            uv = 2.0 * uv - 1.0;
            uv.y = -uv.y;           // flip
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
