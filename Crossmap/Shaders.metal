//  Created by Mark Lim Pak Mun on 11/05/2022.
//  Copyright © 2022 Mark Lim Pak Mun. All rights reserved.
//  Credit:
//      https://www.shadertoy.com/view/tdjXDt

#include <metal_stdlib>
using namespace metal;

typedef struct
{
    float4 renderedCoordinate [[position]]; // clip space
    float2 textureCoordinate;
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
    // The s-axis is +ve right and the t-axis is +ve down
    float4x2 textureCoordinates = float4x2(float2(0.0, 1.0),
                                           float2(1.0, 1.0),
                                           float2(0.0, 0.0),
                                           float2(1.0, 0.0));
    TextureMappingVertex outVertex;
    outVertex.renderedCoordinate = renderedCoordinates[vertex_id];
    outVertex.textureCoordinate = textureCoordinates[vertex_id];
    outVertex.layer = instanceId;
    return outVertex;
}

// Outputs the texture of a face of the cubemap.
fragment half4
outputCubeMapTexture(TextureMappingVertex                       mappingVertex [[stage_in]],
                     array<texture2d<float, access::sample>, 6> colorTextures [[texture(0)]])
{
    constexpr sampler texSampler(address::clamp_to_edge,
                                 filter::linear,
                                 coord::normalized);

    uint whichLayer = mappingVertex.layer;
    float4 colorFrag = colorTextures[whichLayer].sample(texSampler,
                                                        mappingVertex.textureCoordinate);
    return half4(colorFrag);
}

constant float epsilon = 1e-30;

/*
 The six faces of the cubemap texture are displayed as right side up
 in the debug shader of XCode.

 KIV: A thin line (background colour) is displayed. Need to find out why.
 For a 2D grid of threads, the thread coordinates (which are a pair of integers)
 has its origin at the top left.
 See the article "Creating Threads and Threadgroups"
 The range of values for the 2D grid is as follows:
    gid.x: [0,  width-1]
    gid.y: [0, height-1]
 where (width-1) is the last row and (height-1) the last column of threads.
 The thread coordinates of the last thread in the grid is (width-1, height-1).
 The thread coordinates of the last row starts at (0, height-1) which is
 the bottom left corner of the grid.
 */
kernel void
compute(texture2d<float, access::write> output      [[texture(0)]],
        texturecube<float>              input       [[texture(1)]],
        constant float                  &u_time     [[buffer(0)]],
        constant float2                 &u_mouse    [[buffer(1)]],
        uint2                           gid         [[thread_position_in_grid]]) {

    constexpr sampler texSampler(mip_filter::linear,
                                 mag_filter::linear,
                                 min_filter::linear);

    uint width = output.get_width();
    uint height = output.get_height();
    uint col = gid.x;       // [0, height-1]
    uint row = gid.y;       // [0,  width-1]
    if ((col >= width) || (row >= height)) {
        // In case the size of the texture does not match the size of the grid.
        // Return early if the pixel is out of bounds
        return;
    }
    // We don't have to pass the resolution as a parameter.
    float2 u_resolution = float2(width, height);
    // Starts output at the lower left corner.
    //float2 fragCoord = float2(gid.x, height-gid.y-1);
    // Starts output at the upper left corner.
    float2 fragCoord = float2(gid.x, gid.y);

    // Normalized pixel coordinates (from 0 to 1)
    float2 inUV = fragCoord/u_resolution.xy;
    // default colour
    float4 fragColor = float4(1.0, 1.0, 1.0, 1.0);
    
    // The samplePos is a 3D vector so the texture must be a cubemap.
    float3 samplePos = float3(0.0f);

    // Crude statement to visualize different cube map faces based on UV coordinates
    int x = int(floor(inUV.x / (1.0 / 4.0)));   // 0, 1, 2, 3
    int y = int(floor(inUV.y / (1.0 / 3.0)));   // 0, 1, 2

    if (y == 1) {
        // middle row of 4 squares of 4:3 crossmap
        // Compute the texture coords to a face (+X, -X, +Z, -Z) of the cubemap
        float2 uv = float2(inUV.x * 4.0f,
                           (inUV.y - 1.0/3.0) * 3.0);

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
        fragColor = input.sample(texSampler, samplePos);
    }
    else {
        // Compute the texture coords to a face (+Y, -Y) of the cubemap
        if (x == 1) {
            //  y = 0 or y = 2 --> 2nd vertical row of 4:3 crossmap
            float2 uv = float2((inUV.x - 1.0/4.0) * 4.0,
                               (inUV.y - float(y) / 3.0) * 3.0);

            // Convert [0.0, 1.0] ---> [-1.0, 1.0]
            uv = 2.0 * uv - 1.0;
            switch (y) {
                case 0: // POSITIVE_Y
                    samplePos = float3(uv.x,   1.0f,  uv.y);
                    break;
                case 2: // NEGATIVE_Y
                    samplePos = float3(uv.x,  -1.0f, -uv.y);
                    break;
            }
           fragColor = input.sample(texSampler, samplePos);
        }
    }
/*
    // problem with this statement - probably due to rounding errors.
    // A thin (background colour) line intersects
    //  the 2nd vertical column of 3 squares
    if ((samplePos.x != 0.0f) && (samplePos.y != 0.0f)) {
        fragColor = input.sample(texSampler, samplePos);
    }
 */
    // Output to the current drawable's texture
    output.write(fragColor, gid);
}
