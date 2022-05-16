// Credits:
// https://www.shadertoy.com/view/tdjXDt
//
// Combine 6 separate 2D images ---> 1 horizontal cubic crossmap

#ifdef GL_ES
precision highp float;
#endif

#if __VERSION__ >= 140

in vec3 uvCoords;

out vec4 FragColor;

#else

varying vec3 uvCoords;

#endif


uniform samplerCube cubemap;
uniform vec2 u_resolution;  // Canvas size (width,height) - 2D dimensions of view port
uniform vec2 u_mouse;       // mouse position in screen pixels
uniform float u_time;

#define iResolution u_resolution
#define iMouse      u_mouse
#define iTime       u_time

void main(void) {
    // Normalized pixel coordinates (from 0 to 1)
    vec2 inUV = gl_FragCoord.xy/iResolution.xy;
    // default to this blue color
    FragColor.rgb = vec3(0.0, 0.0, 0.2);

    vec3 samplePos = vec3(0.0f);

    // Crude statement to visualize different cube map faces
    //  based on UV coordinates
    int x = int(floor(inUV.x / 0.25f));         // 0, 1, 2, 3
    int y = int(floor(inUV.y / (1.0 / 3.0)));   // 0, 1, 2

    if (y == 1) {
        // Middle row of 4 squares (-X, +Z, +X, -Z)
        vec2 uv = vec2(inUV.x * 4.0f,
                       (inUV.y - 1.0/3.0) * 3.0);
        uv = 2.0 * vec2(uv.x - float(x) * 1.0, uv.y) - 1.0;
        // Now convert the uv coords into a 3D vector which will be
        //  used to access the correct face of the cube map.
        switch (x) {
            case 0: // NEGATIVE_X
                samplePos = vec3(-1.0f, uv.y, uv.x);
                break;
            case 1: // POSITIVE_Z
                samplePos = vec3( uv.x, uv.y, 1.0f);
                break;
            case 2: // POSITIVE_X
                samplePos = vec3( 1.0, uv.y,  -uv.x);
                break;
            case 3: // NEGATIVE_Z
                samplePos = vec3(-uv.x, uv.y, -1.0f);
                break;
        }
    }
    else {
        // y = 0 or y = 2
        // 2nd vertical row of 3 squares (+Y, +Z, -Y)
        if (x == 1) {
            vec2 uv = vec2((inUV.x - 0.25) * 4.0,
                           (inUV.y - float(y) / 3.0) * 3.0);
            uv = 2.0 * uv - 1.0;
            switch (y) {
                case 0: // NEGATIVE_Y
                    samplePos = vec3(uv.x, -1.0f,  uv.y);
                    break;
                case 2: // POSITIVE_Y
                    samplePos = vec3(uv.x,  1.0f, -uv.y);
                    break;
            }
        }
    }

#if __VERSION__ >= 140
    if ((samplePos.x != 0.0f) && (samplePos.y != 0.0f)) {
        FragColor = vec4(texture(cubemap, samplePos).rgb, 1.0);
    }
#else
    if ((samplePos.x != 0.0f) && (samplePos.y != 0.0f)) {
        gl_FragColor = vec4(texture(cubemap, samplePos).rgb, 1.0);
    }
#endif
}
