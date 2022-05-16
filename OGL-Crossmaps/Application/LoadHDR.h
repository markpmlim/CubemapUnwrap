/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for common utility functions.
*/


#import <simd/simd.h>
#import <Foundation/Foundation.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/gl.h>
#else
#import <AppKit/AppKit.h>
#import <OpenGL/gl3.h>
#endif

/// As a source of HDR output, renderer leverages radiance (.hdr) files.
///  This helper method output a radiance file
/// Supposed to throw when called from Swift.

GLuint textureFromRadianceFile(const char *pathName, int *width, int *height);

GLuint cubemapFromRadianceFiles(const char *pathNames[], int *width, int *height);

