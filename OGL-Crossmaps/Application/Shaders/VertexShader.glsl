#if __VERSION__ >= 140
layout (location = 0) in vec3 position;

out vec2 texCoords;

#else
attribute vec3 position;

varying vec2 texCoords;
#endif

/*
 No geometry are passed to this vertex shader; the range of gl_VertexID: [0, 2]
 The position and texture coordinates attributes of 3 vertices are
 generated on the fly.
 position: (-1.0, -1.0), (3.0, -1.0), (-1.0, 3.0)
       uv: ( 0.0,  0.0), (2.0,  0.0), ( 0.0, 2.0)
 The area of the generated triangle covers the entire 2D clip-space.
 Note: any geometry rendered outside this 2D space is clipped.
 Clip-space:
 Range of position: [-1.0, 1.0]
 Range of uv: [ 0.0, 1.0]
 The origin of the uv axes starts at the bottom left corner of the
 2D clip space with u-axis from left to right and
 v-axis from bottom to top
 https://rauwendaal.net/2014/06/14/rendering-a-screen-covering-triangle-in-opengl/
 */
void main(void)
{
    float x = float((gl_VertexID & 1) << 2);
    float y = float((gl_VertexID & 2) << 1);
    texCoords = vec2(x * 0.5, y * 0.5);
    gl_Position = vec4(x - 1.0, y - 1.0, 0, 1);
}
