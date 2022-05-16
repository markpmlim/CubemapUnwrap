//
//  LoadSTB.m
//  ShaderToyGL
//
//  Created by Mark Lim Pak Mun on 25/04/2022.
//  Copyright © 2022 mark lim pak mun. All rights reserved.
//

#import "LoadHDR.h"

GLuint textureFromRadianceFile(const char *pathName, int *width, int *height) {
    int nrComponents = 0;

    stbi_set_flip_vertically_on_load(true);
    float *data = stbi_loadf(pathName,
                             width, height,
                             &nrComponents,     // 3
                             0);                // required # of components
    
    GLuint hdrTextureID;
    if (data) {
        glGenTextures(1, &hdrTextureID);
        glBindTexture(GL_TEXTURE_2D, hdrTextureID);
        glTexImage2D(GL_TEXTURE_2D, // target
                     0,             // level
                     GL_RGB16F,     // internal format
                     *width, *height,
                     0,             // border
                     GL_RGB,        // format (3 components)
                     GL_FLOAT,      // note how we specify the texture's data value to be float
                     data);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        stbi_image_free(data);
        return hdrTextureID;
    }
    return 0;
}

GLuint cubemapFromRadianceFiles(const char *pathNames[], int *width, int *height) {
    GLuint hdrTextureID;
    glGenTextures(1, &hdrTextureID);
    glBindTexture(GL_TEXTURE_CUBE_MAP, hdrTextureID);
#if !TARGET_OS_IOS
    glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS);
#endif
    int nrChannels;
    for(unsigned int i = 0; i < 6; i++) {
        // To prevent flipping of the cubemap faces
        stbi_set_flip_vertically_on_load(false);
        float *data = nil;
        data = stbi_loadf(pathNames[i], width, height,
                          &nrChannels, 0);
        glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i,    // target
                     0,                                     // level
                     GL_RGB16F,                             // internal format
                     *width, *height,
                     0,                                     // border
                     GL_RGB,                                // format (3 components)
                     GL_FLOAT,  // note how we specify the texture's data value to be float
                     data);
        stbi_image_free(data);
    }

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
    return hdrTextureID;

}
