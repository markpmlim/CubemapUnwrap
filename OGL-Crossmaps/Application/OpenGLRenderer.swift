//
//  AAPLOpenGLRenderer.swift
//  OpenGLToMetal
//
//  Created by mark lim pak mun on 13/11/2021.
//  Copyright © 2021 mark lim pak mun. All rights reserved.
//

#if os(iOS)
import UIKit
import OpenGLES
#else
import AppKit
import OpenGL.GL3
#endif

import simd
import GLKit

class OpenGLRenderer: NSObject {
    var _defaultFBOName: GLuint = 0
    var _viewSize: CGSize = CGSize()
    var skyboxProgram: GLuint = 0
    var glslProgram: GLuint = 0
    // Parameters to be passed to the fragment shader.
    // The origin is at the left hand corner
    var mouseCoords: [GLfloat] = [100.0, 100.0]
    var currentTime: GLfloat = 0.0

    var resolutionLoc: GLint = 0
    var mouseLoc: GLint = 0
    var timeLoc: GLint = 0
    var cubemapLoc: GLint = 0

    var skyboxVAO: GLuint = 0
    var triangleVAO: GLuint = 0
    var textureID: GLuint = 0
    // For cubemaps, this is the common width and height of six 2D textures
    var u_tex0Resolution: [GLfloat] = [0.0, 0.0]

    init(_ defaultFBOName: GLuint) {
        super.init()
        // Build all of your objects and setup initial state here.
        _defaultFBOName = defaultFBOName
        let names = ["px.hdr", "nx.hdr", "py.hdr", "ny.hdr", "pz.hdr", "nz.hdr"]
        textureID = loadCubemapTexture(names,
                                       resolution: &u_tex0Resolution)

        let vertexSourceURL = Bundle.main.url(forResource: "VertexShader",
                                              withExtension: "glsl");
        
        let fragmentSourceURL = Bundle.main.url(forResource: "FragmentShader",
                                                withExtension: "glsl");

        glslProgram = buildProgram(with: vertexSourceURL!,
                                   and: fragmentSourceURL!)

        resolutionLoc = glGetUniformLocation(glslProgram, "u_resolution")
        mouseLoc = glGetUniformLocation(glslProgram, "u_mouse")
        timeLoc = glGetUniformLocation(glslProgram, "u_time")
        cubemapLoc = glGetUniformLocation(glslProgram, "cubemap")
        glUniform1i(cubemapLoc, 0)

        // Required even though no vertex data is uploaded to the GPU.
        glGenVertexArrays(1, &triangleVAO)
   }

    private func updateTime() {
        currentTime += 1.0/60.0
    }

    // Main draw function. Called by both iOS and macOS modules.
    func draw() {
        updateTime()
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT) | GLbitfield(GL_DEPTH_BUFFER_BIT))
        glViewport(0, 0,
                   (GLsizei)(_viewSize.width),
                   (GLsizei)(_viewSize.height))
        glClearColor(0.5, 0.5, 0.5, 1.0)

        glUseProgram(glslProgram)
        glBindVertexArray(triangleVAO)
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_CUBE_MAP), textureID)
        // We should pass the resolution of the canvas.
        glUniform2f(resolutionLoc,
                    Float(_viewSize.width), Float(_viewSize.height))
        glUniform1f(timeLoc, GLfloat(currentTime))
        glUniform2fv(mouseLoc, 1, mouseCoords)
        glDrawArrays(GLenum(GL_TRIANGLES), 0, 3)
        glUseProgram(0)
        glBindVertexArray(0)
    }

    func resize(_ size: CGSize) {
        _viewSize = size
    }

    // Returns an OpenGL cube texture name (id) & the texture's width and height.
    func loadCubemapTexture(_ names : [String], resolution: inout [GLfloat]) -> GLuint {
        let mainBundle = Bundle.main
        // UnsafePointer<Int8> is a pointer to a null-terminated string.
        let pathNames = UnsafeMutablePointer<UnsafePointer<Int8>?>.allocate(capacity:  6)
        for i in 0..<names.count {
            let subStrings = names[i].components(separatedBy:".")
            guard let filePath = mainBundle.path(forResource: subStrings[0],
                                                 ofType: subStrings[1])
            else {
                Swift.print("File \(names[i]): not found")
                pathNames.deallocate(capacity: 6)
                exit(3)
            }
            let cPtr = (filePath as NSString).utf8String
            pathNames[i] = cPtr
        }
        var width: Int32 = 0
        var height: Int32 = 0
        let textureID = cubemapFromRadianceFiles(pathNames, &width, &height)
        resolution[0] = GLfloat(width)
        resolution[1] = GLfloat(height)
        pathNames.deallocate(capacity: 6)
        return textureID
    }

    // The normals are included here in case lighting is added to this demo.
    func buildGeometry() -> GLuint {
        var cubeVAO = GLuint()
        // Get OpenGL generate Vertex Array Object name.
        glGenVertexArrays(1, &cubeVAO)
        // On first bind, OpenGL allocate and initialise the VAO to its default state
        glBindVertexArray(cubeVAO)
        // total size = 24 bytes; using GLKVectors may not work!
        struct Vertex {
            let position: (GLfloat, GLfloat, GLfloat)   // 12 bytes
            let normal: (GLfloat, GLfloat, GLfloat)     // 12 bytes
        }

        let vertices: [Vertex] = [
            Vertex(position: ( 1, 1, -1), normal: (0.0, 1.0, 0.0)),     // Top
            Vertex(position: (-1, 1, -1), normal: (0.0, 1.0, 0.0)),
            Vertex(position: (-1, 1,  1), normal: (0.0, 1.0, 0.0)),
            Vertex(position: ( 1, 1,  1), normal: (0.0, 1.0, 0.0)),

            Vertex(position: ( 1, -1,  1), normal: (0.0, -1.0, 0.0)),   // Bottom
            Vertex(position: (-1, -1,  1), normal: (0.0, -1.0, 0.0)),
            Vertex(position: (-1, -1, -1), normal: (0.0, -1.0, 0.0)),
            Vertex(position: ( 1, -1, -1), normal: (0.0, -1.0, 0.0)),

            Vertex(position: ( 1,  1,  1), normal: (0.0, 0.0, 1.0)),    // Front
            Vertex(position: (-1,  1,  1), normal: (0.0, 0.0, 1.0)),
            Vertex(position: (-1, -1,  1), normal: (0.0, 0.0, 1.0)),
            Vertex(position: ( 1, -1,  1), normal: (0.0, 0.0, 1.0)),

            Vertex(position: ( 1, -1, -1), normal: (0.0, 0.0, -1.0)),   // Back
            Vertex(position: (-1, -1, -1), normal: (0.0, 0.0, -1.0)),
            Vertex(position: (-1,  1, -1), normal: (0.0, 0.0, -1.0)),
            Vertex(position: ( 1,  1, -1), normal: (0.0, 0.0, -1.0)),

            Vertex(position: (-1,  1,  1), normal: (-1.0, 0.0, 0.0)),   // Left
            Vertex(position: (-1,  1, -1), normal: (-1.0, 0.0, 0.0)),
            Vertex(position: (-1, -1, -1), normal: (-1.0, 0.0, 0.0)),
            Vertex(position: (-1, -1,  1), normal: (-1.0, 0.0, 0.0)),

            Vertex(position: ( 1,  1, -1), normal: (1.0, 0.0, 0.0)),    // Right
            Vertex(position: ( 1,  1,  1), normal: (1.0, 0.0, 0.0)),
            Vertex(position: ( 1, -1,  1), normal: (1.0, 0.0, 0.0)),
            Vertex(position: ( 1, -1, -1), normal: (1.0, 0.0, 0.0)),
            ]

        let indices: [UInt8] = [
            0,  1,  2,    // triangle 1 &
            2,  3,  0,    //  triangle 2 of top face
            4,  5,  6,
            6,  7,  4,
            8,  9,  10,
            10, 11, 8,
            12, 13, 14,
            14, 15, 12,
            16, 17, 18,
            18, 19, 16,
            20, 21, 22,    // triangle 1 &
            22, 23, 20    //  triangle 2 of right face
        ]

        var vboId: GLuint = 0
        glGenBuffers(1, &vboId)                         // Create the buffer ID, this is basically the same as generating texture ID's
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboId)    // Bind the buffer (vertex array data)

        glBufferData(GLenum(GL_ARRAY_BUFFER),
                     MemoryLayout<Vertex>.stride*vertices.count,
                     vertices, GLenum(GL_STATIC_DRAW))
        let positionAttr = UnsafeRawPointer(bitPattern: 0)
        glVertexAttribPointer(0,                                    // attribute
                              3,                                    // size
                              GLenum(GL_FLOAT),                     // type
                              GLboolean(GL_FALSE),                  // don't normalize
                              GLsizei(MemoryLayout<Vertex>.stride), // stride
                              positionAttr)                         // array buffer offset
        glEnableVertexAttribArray(0)
        let normalAttr = UnsafeRawPointer(bitPattern: MemoryLayout<Float>.stride*3)
        glVertexAttribPointer(1,
                              3,
                              GLenum(GL_FLOAT),
                              GLboolean(GL_FALSE),
                              GLsizei(MemoryLayout<Vertex>.stride),
                              normalAttr)
        glEnableVertexAttribArray(1)

        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)

        var eboID: GLuint = 0

        glGenBuffers(1, &eboID)                         // Generate buffer
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER),   // Bind the element array buffer
                     eboID)

        // Upload the index array, this can be done the same way as above (with NULL as the data,
        //  then a glBufferSubData call, but doing it all at once for convenience)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER),
                     36 * MemoryLayout<UInt8>.stride,
                     indices,
                     GLenum(GL_STATIC_DRAW))
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        glBindVertexArray(0)
        return cubeVAO
    }

    /*
     Only expect a pair of vertex and fragment shaders.
     This function should work for both fixed pipeline and modern OpenGL syntax.
     */
    func buildProgram(with vertSrcURL: URL,
                      and fragSrcURL: URL) -> GLuint {
        // Prepend the #version preprocessor directive to the vertex and fragment shaders.
        var  glLanguageVersion: Float = 0.0
        let glslVerstring = String(cString: glGetString(GLenum(GL_SHADING_LANGUAGE_VERSION)))
        #if os(iOS)
            let index = glslVerstring.index(glslVerstring.startIndex, offsetBy: 18)
        #else
            let index = glslVerstring.index(glslVerstring.startIndex, offsetBy: 0)
        #endif
        let range = index..<glslVerstring.endIndex
        let verStr = glslVerstring.substring(with: range)
        
        let scanner = Scanner(string: verStr)
        scanner.scanFloat(&glLanguageVersion)
        // We need to convert the float to an integer and then to a string.
        var shaderVerStr = String(format: "#version %d", Int(glLanguageVersion*100))
        #if os(iOS)
            if EAGLContext.current().api == .openGLES3 {
                shaderVerStr = shaderVerStr.appending(" es")
            }
        #endif
        
        var vertSourceString = String()
        var fragSourceString = String()
        do {
            vertSourceString = try String(contentsOf: vertSrcURL)
        }
        catch _ {
            Swift.print("Error loading vertex shader")
        }
        
        do {
            fragSourceString = try String(contentsOf: fragSrcURL)
        }
        catch _ {
            Swift.print("Error loading fragment shader")
        }
        vertSourceString = shaderVerStr + "\n" + vertSourceString
        //Swift.print(vertSourceString)
        fragSourceString = shaderVerStr + "\n" + fragSourceString
        //Swift.print(fragSourceString)
        
        // Create a GLSL program object.
        let prgName = glCreateProgram()
        
        // We can choose to bind our attribute variable names to specific
        //  numeric attribute locations. Must be done before linking.
        //glBindAttribLocation(prgName, AAPLVertexAttributePosition, "a_Position")
        
        let vertexShader = glCreateShader(GLenum(GL_VERTEX_SHADER))
        var cSource = vertSourceString.cString(using: .utf8)!
        var glcSource: UnsafePointer<GLchar>? = UnsafePointer<GLchar>(cSource)
        glShaderSource(vertexShader, 1, &glcSource, nil)
        glCompileShader(vertexShader)
        
        var compileStatus : GLint = 0
        glGetShaderiv(vertexShader, GLenum(GL_COMPILE_STATUS), &compileStatus)
        if compileStatus == GL_FALSE {
            var infoLength : GLsizei = 0
            glGetShaderiv(vertexShader, GLenum(GL_INFO_LOG_LENGTH), &infoLength)
            if infoLength > 0 {
                // Convert an UnsafeMutableRawPointer to UnsafeMutablePointer<GLchar>
                let log = malloc(Int(infoLength)).assumingMemoryBound(to: GLchar.self)
                glGetShaderInfoLog(vertexShader, infoLength, &infoLength, log)
                let errMsg = NSString(bytes: log,
                                      length: Int(infoLength),
                                      encoding: String.Encoding.ascii.rawValue)
                print(errMsg!)
                glDeleteShader(vertexShader)
                free(log)
            }
        }
        // Attach the vertex shader to the program.
        glAttachShader(prgName, vertexShader);
        
        // Delete the vertex shader because it's now attached to the program,
        //  which retains a reference to it.
        glDeleteShader(vertexShader);
        
        /*
         * Specify and compile a fragment shader.
         */
        let fragmentShader = glCreateShader(GLenum(GL_FRAGMENT_SHADER))
        cSource = fragSourceString.cString(using: .utf8)!
        glcSource = UnsafePointer<GLchar>(cSource)
        glShaderSource(fragmentShader, 1, &glcSource, nil)
        glCompileShader(fragmentShader)

        glGetShaderiv(fragmentShader, GLenum(GL_COMPILE_STATUS), &compileStatus)
        if compileStatus == GL_FALSE {
            var infoLength : GLsizei = 0
            glGetShaderiv(fragmentShader, GLenum(GL_INFO_LOG_LENGTH), &infoLength)
            if infoLength > 0 {
                // Convert an UnsafeMutableRawPointer to UnsafeMutablePointer<GLchar>
                let log = malloc(Int(infoLength)).assumingMemoryBound(to: GLchar.self)
                glGetShaderInfoLog(fragmentShader, infoLength, &infoLength, log)
                let errMsg = NSString(bytes: log,
                                      length: Int(infoLength),
                                      encoding: String.Encoding.ascii.rawValue)
                print(errMsg!)
                glDeleteShader(fragmentShader)
                free(log)
            }
        }

        // Attach the fragment shader to the program.
        glAttachShader(prgName, fragmentShader)

        // Delete the fragment shader because it's now attached to the program,
        //  which retains a reference to it.
        glDeleteShader(fragmentShader)

        /*
         * Link the program.
         */
        var linkStatus: GLint = 0
        glLinkProgram(prgName)
        glGetProgramiv(prgName, GLenum(GL_LINK_STATUS), &linkStatus)

        if (linkStatus == GL_FALSE) {
            var logLength : GLsizei = 0
            glGetProgramiv(prgName, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            if (logLength > 0) {
                let log = malloc(Int(logLength)).assumingMemoryBound(to: GLchar.self)
                glGetProgramInfoLog(prgName, logLength, &logLength, log)
                NSLog("Program link log:\n%s.\n", log)
                free(log)
            }
        }
        
        // We can locate all uniform locations here
        //let samplerLoc = glGetUniformLocation(prgName, "cubemap")
        //Swift.print(samplerLoc)

        //getGLError()
        return prgName
    }
}

// convert a tuple into array - iterating a tuple
func arrayForTuple<T,E>(_ tuple: T) -> [E] {
    let reflection = Mirror(reflecting: tuple)
    var arr : [E] = []
    for i in 0..<reflection.children.count {
        let idx = AnyIndex(Int(i))
        if let value = reflection.children[idx].1 as? E {
            arr.append(value)
        }
    }
    return arr
}

extension vector_float2 {
    func toArray() -> [Float] {
        return [Float](arrayLiteral:
            self.x, self.y)
    }
}
extension vector_float3 {
    func toArray() -> [Float] {
        return [Float](arrayLiteral:
            self.x, self.y, self.z)
    }
}
extension vector_float4 {
    func toArray() -> [Float] {
        return [Float](arrayLiteral:
            self.x, self.y, self.z, self.w)
    }
}


extension matrix_float3x3 {
    func toArray() -> [Float] {
        return [Float](arrayLiteral:
            self.columns.0.x, self.columns.0.y, self.columns.0.z,
            self.columns.1.x, self.columns.1.y, self.columns.1.z,
            self.columns.2.x, self.columns.2.y, self.columns.2.z
        )
    }
}


extension matrix_float4x4 {
    func toArray() -> [Float] {
        return [Float](arrayLiteral:
            self.columns.0.x, self.columns.0.y, self.columns.0.z, self.columns.0.w,
            self.columns.1.x, self.columns.1.y, self.columns.1.z, self.columns.1.w,
            self.columns.2.x, self.columns.2.y, self.columns.2.z, self.columns.2.w,
            self.columns.3.x, self.columns.3.y, self.columns.3.z, self.columns.3.w
        )
    }
}
