/*
 * gles2-floattex -- does the driver survive WebRender's data textures?
 *
 * Allocates RGBA float textures 1024 texels wide (OES_texture_float), the
 * way WebRender keeps its per-frame data, and uploads into them again and
 * again with glTexSubImage2D; optionally also re-allocates them each round,
 * and optionally draws with the texture in between (read in the vertex
 * shader, as WebRender does), so that each upload hits a texture the GPU
 * may still be reading. Run with MALLOC_CHECK_=3: a driver that sizes float
 * texels wrongly corrupts the heap here. The window is never mapped.
 *
 * Build:  cc -O2 -o gles2-floattex gles2-floattex.c -lEGL -lGLESv2 -lX11
 * Run:    DISPLAY=:0 ./gles2-floattex [rows] [rounds] [realloc] [type] [draw]
 *         type: f (GL_FLOAT, default), h (GL_HALF_FLOAT_OES), b (GL_UNSIGNED_BYTE)
 *         realloc: 0 sub-image only, 1 re-allocate then sub-image,
 *                  2 glTexImage2D with the data (no sub-image)
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
	static const EGLint cfg_attr[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE,
		EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_NONE
	};
	static const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	int rows = argc > 1 ? atoi(argv[1]) : 64;
	int rounds = argc > 2 ? atoi(argv[2]) : 200;
	int realloc_each = argc > 3 ? atoi(argv[3]) : 0;
	char type = argc > 4 ? argv[4][0] : 'f';
	int draw = argc > 5 ? atoi(argv[5]) : 0;
	static const char *vs_src =
		"attribute float aTexel;\n"
		"uniform highp sampler2D sData;\n"
		"varying lowp vec4 vColor;\n"
		"void main() {\n"
		"  vColor = texture2D(sData, vec2((aTexel + 0.5) / 1024.0, 0.25));\n"
		"  gl_Position = vec4(aTexel / 512.0 - 1.0, 0.0, 0.0, 1.0);\n"
		"  gl_PointSize = 1.0;\n"
		"}\n";
	static const char *fs_src =
		"varying lowp vec4 vColor;\n"
		"void main() { gl_FragColor = vColor; }\n";
	float texels[1024];
	GLuint prog = 0, buf;
	GLenum gltype = type == 'h' ? GL_HALF_FLOAT_OES : type == 'b' ? GL_UNSIGNED_BYTE : GL_FLOAT;
	size_t bpp = type == 'h' ? 8 : type == 'b' ? 4 : 16;
	Display *x = XOpenDisplay(NULL);
	EGLDisplay d;
	EGLConfig cfg;
	EGLint n;
	EGLContext c;
	EGLSurface surf;
	Window win;
	GLuint tex;
	unsigned char *data;
	int i;

	if (!x) {
		printf("no X display\n");
		return 1;
	}
	win = XCreateSimpleWindow(x, DefaultRootWindow(x), 0, 0, 16, 16, 0, 0, 0);
	d = eglGetDisplay((EGLNativeDisplayType)x);
	eglInitialize(d, NULL, NULL);
	eglChooseConfig(d, cfg_attr, &cfg, 1, &n);
	c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, ctx_attr);
	surf = eglCreateWindowSurface(d, cfg, (EGLNativeWindowType)win, NULL);
	eglMakeCurrent(d, surf, surf, c);
	printf("%s, 1024 x %d, type %c, %d rounds, realloc %d\n",
	       glGetString(GL_RENDERER), rows, type, rounds, realloc_each);

	data = calloc(1024 * (size_t)rows, bpp);
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1024, rows, 0, GL_RGBA, gltype, NULL);
	printf("allocate: GL error 0x%x\n", glGetError());
	if (draw) {
		GLuint vs = glCreateShader(GL_VERTEX_SHADER), fs = glCreateShader(GL_FRAGMENT_SHADER);
		glShaderSource(vs, 1, &vs_src, NULL);
		glCompileShader(vs);
		glShaderSource(fs, 1, &fs_src, NULL);
		glCompileShader(fs);
		prog = glCreateProgram();
		glAttachShader(prog, vs);
		glAttachShader(prog, fs);
		glBindAttribLocation(prog, 0, "aTexel");
		glLinkProgram(prog);
		glUseProgram(prog);
		glUniform1i(glGetUniformLocation(prog, "sData"), 0);
		for (i = 0; i < 1024; i++)
			texels[i] = (float)i;
		glGenBuffers(1, &buf);
		glBindBuffer(GL_ARRAY_BUFFER, buf);
		glBufferData(GL_ARRAY_BUFFER, sizeof(texels), texels, GL_STATIC_DRAW);
		glVertexAttribPointer(0, 1, GL_FLOAT, GL_FALSE, 4, (void *)0);
		glEnableVertexAttribArray(0);
		printf("program: GL error 0x%x\n", glGetError());
	}
	for (i = 0; i < rounds; i++) {
		memset(data, i, 1024 * (size_t)rows * bpp);
		if (realloc_each == 2) {
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1024, rows, 0, GL_RGBA, gltype, data);
		} else {
			if (realloc_each)
				glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1024, rows, 0, GL_RGBA, gltype, NULL);
			glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1024, rows, GL_RGBA, gltype, data);
		}
		if (draw) {
			glClear(GL_COLOR_BUFFER_BIT);
			glDrawArrays(GL_POINTS, 0, 1024);
			eglSwapBuffers(d, surf);
		}
		if (i % 50 == 0)
			printf("round %d: GL error 0x%x\n", i, glGetError());
	}
	glFinish();
	printf("done: GL error 0x%x\n", glGetError());
	return 0;
}
