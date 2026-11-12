/*
 * gles2-subimage -- does a texture keep its contents across glTexSubImage2D
 * calls while it is still in use by a draw?
 *
 * Uploads a block A into a texture, draws with the texture (not waiting for
 * the draw), uploads a block B elsewhere into it, then reads the texture
 * back through a framebuffer: A must still be there. Repeated with a
 * glFinish between the draw and the second upload, and for RGBA and the
 * single-channel format WebRender uses for glyphs. Then a block C is drawn
 * into the texture through a framebuffer (as WebRender's texture cache
 * moves entries between pages) before the second upload: C must survive too.
 * Uses a pbuffer; no window is mapped.
 *
 * Build:  cc -O2 -o gles2-subimage gles2-subimage.c -lEGL -lGLESv2 -lX11
 * Run:    DISPLAY=:0 ./gles2-subimage
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <string.h>

#ifndef GL_RED_EXT
#define GL_RED_EXT 0x1903
#endif

static GLuint program(void)
{
	static const char *vs = "attribute vec2 aPos; varying vec2 vUv;\n"
		"void main() { vUv = aPos * 0.5 + 0.5; gl_Position = vec4(aPos, 0.0, 1.0); }";
	static const char *fs = "precision mediump float; uniform sampler2D sTex; varying vec2 vUv;\n"
		"void main() { gl_FragColor = texture2D(sTex, vUv); }";
	GLuint p = glCreateProgram(), s;
	s = glCreateShader(GL_VERTEX_SHADER);
	glShaderSource(s, 1, &vs, NULL);
	glCompileShader(s);
	glAttachShader(p, s);
	s = glCreateShader(GL_FRAGMENT_SHADER);
	glShaderSource(s, 1, &fs, NULL);
	glCompileShader(s);
	glAttachShader(p, s);
	glBindAttribLocation(p, 0, "aPos");
	glLinkProgram(p);
	return p;
}

/* value of texel (x, y) of a size x size texture, read through a framebuffer */
static unsigned char texel(GLuint tex, int size, int x, int y)
{
	GLuint fb;
	unsigned char px[4] = { 0 };
	glGenFramebuffers(1, &fb);
	glBindFramebuffer(GL_FRAMEBUFFER, fb);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE)
		glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	glDeleteFramebuffers(1, &fb);
	(void)size;
	return px[0];
}

static GLuint solid_program(void)
{
	static const char *vs = "attribute vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }";
	static const char *fs = "precision mediump float; void main() { gl_FragColor = vec4(50.0 / 255.0); }";
	GLuint p = glCreateProgram(), s;
	s = glCreateShader(GL_VERTEX_SHADER);
	glShaderSource(s, 1, &vs, NULL);
	glCompileShader(s);
	glAttachShader(p, s);
	s = glCreateShader(GL_FRAGMENT_SHADER);
	glShaderSource(s, 1, &fs, NULL);
	glCompileShader(s);
	glAttachShader(p, s);
	glBindAttribLocation(p, 0, "aPos");
	glLinkProgram(p);
	return p;
}

static void run(GLuint prog, GLuint out_fb, GLenum format, int bpp, int size, int finish, int draw_c)
{
	static const float quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
	unsigned char block[16 * 16 * 4];
	GLuint tex;
	int i;

	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	glTexImage2D(GL_TEXTURE_2D, 0, format, size, size, 0, format, GL_UNSIGNED_BYTE, NULL);

	memset(block, 200, sizeof block);
	glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 16, 16, format, GL_UNSIGNED_BYTE, block);

	glBindFramebuffer(GL_FRAMEBUFFER, out_fb);
	glViewport(0, 0, 64, 64);
	glUseProgram(prog);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
	glEnableVertexAttribArray(0);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	if (draw_c) {
		/* block C at (16..32, 0..16), drawn into the texture */
		static GLuint solid;
		GLuint fb;
		float x0 = 16.0f * 2 / size - 1, x1 = 32.0f * 2 / size - 1, y1 = 16.0f * 2 / size - 1;
		const float c[] = { x0, -1, x1, -1, x0, y1, x1, y1 };
		if (!solid)
			solid = solid_program();
		glGenFramebuffers(1, &fb);
		glBindFramebuffer(GL_FRAMEBUFFER, fb);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
		glViewport(0, 0, size, size);
		glUseProgram(solid);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, c);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glBindFramebuffer(GL_FRAMEBUFFER, out_fb);
		glDeleteFramebuffers(1, &fb);
		glViewport(0, 0, 64, 64);
		glUseProgram(prog);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	}
	if (finish)
		glFinish();

	memset(block, 100, sizeof block);
	for (i = 0; i < 8; i++)
		glTexSubImage2D(GL_TEXTURE_2D, 0, 32 + 16 * i, 32, 16, 16, format, GL_UNSIGNED_BYTE, block);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glFinish();

	printf("%-5s %4dx%-4d %-9s %-7s A=%3d (200)  B=%3d (100)  C=%3d (%s)\n",
	       bpp == 4 ? "RGBA" : "RED", size, size, finish ? "finish" : "no finish",
	       draw_c ? "drawn C" : "", texel(tex, size, 8, 8), texel(tex, size, 40, 40),
	       texel(tex, size, 24, 8), draw_c ? "50" : "0");
	glDeleteTextures(1, &tex);
}

int main(void)
{
	Display *x = XOpenDisplay(NULL);
	EGLDisplay d = eglGetDisplay((EGLNativeDisplayType)x);
	const EGLint cfg_attrs[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_NONE };
	const EGLint pb_attrs[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
	const EGLint ctx_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLConfig cfg;
	EGLint n;
	GLuint prog, out_fb, out_rb;
	int size, finish;
	(void)0;

	eglInitialize(d, NULL, NULL);
	eglChooseConfig(d, cfg_attrs, &cfg, 1, &n);
	EGLSurface s = eglCreatePbufferSurface(d, cfg, pb_attrs);
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLContext c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, ctx_attrs);
	eglMakeCurrent(d, s, s, c);
	printf("%s\n", glGetString(GL_RENDERER));

	prog = program();
	glGenRenderbuffers(1, &out_rb);
	glBindRenderbuffer(GL_RENDERBUFFER, out_rb);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, 64, 64);
	glGenFramebuffers(1, &out_fb);
	glBindFramebuffer(GL_FRAMEBUFFER, out_fb);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, out_rb);

	{
		/* the draws sample into a texture (as WebRender draws into picture
		   cache tiles) instead of a renderbuffer */
		GLuint tile, tile_fb;
		glGenTextures(1, &tile);
		glBindTexture(GL_TEXTURE_2D, tile);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
		glGenFramebuffers(1, &tile_fb);
		glBindFramebuffer(GL_FRAMEBUFFER, tile_fb);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tile, 0);
		printf("-- drawing into a texture:\n");
		for (finish = 0; finish < 2; finish++) {
			run(prog, tile_fb, GL_RGBA, 4, 512, finish, 0);
			run(prog, tile_fb, GL_RED_EXT, 1, 512, finish, 0);
		}
		printf("-- drawing into a renderbuffer:\n");
	}
	{
		/* 20 frames, each uploading one 12x14 block into an R8 texture,
		   switching its filter as WebRender's binds do, drawing with it into
		   a texture and finishing: does the first block survive? */
		static const float quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
		unsigned char glyph[12 * 14];
		GLuint tex, tile, tile_fb;
		int f, filt;
		for (filt = 0; filt < 2; filt++) {
			glGenTextures(1, &tile);
			glBindTexture(GL_TEXTURE_2D, tile);
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
			glGenFramebuffers(1, &tile_fb);
			glBindFramebuffer(GL_FRAMEBUFFER, tile_fb);
			glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tile, 0);
			glGenTextures(1, &tex);
			glBindTexture(GL_TEXTURE_2D, tex);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
			glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, 512, 512, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, NULL);
			for (f = 0; f < 20; f++) {
				memset(glyph, 10 + f * 10, sizeof glyph);
				glBindTexture(GL_TEXTURE_2D, tex);
				glTexSubImage2D(GL_TEXTURE_2D, 0, 16 * f, 0, 12, 14, GL_RED_EXT, GL_UNSIGNED_BYTE, glyph);
				if (filt) {
					GLint m = f & 1 ? GL_NEAREST : GL_LINEAR;
					glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, m);
					glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, m);
				}
				glBindFramebuffer(GL_FRAMEBUFFER, tile_fb);
				glViewport(0, 0, 64, 64);
				glUseProgram(prog);
				glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
				glEnableVertexAttribArray(0);
				glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				glFinish();
			}
			printf("R8 20 frames %-16s first=%3d (10)  tenth=%3d (100)  last=%3d (200)\n",
			       filt ? "switching filter" : "fixed filter",
			       texel(tex, 512, 4, 4), texel(tex, 512, 16 * 9 + 4, 4), texel(tex, 512, 16 * 19 + 4, 4));
		}
	}
	for (size = 256; size <= 512; size *= 2)
		for (finish = 0; finish < 2; finish++) {
			int draw_c;
			for (draw_c = 0; draw_c < 2; draw_c++) {
				run(prog, out_fb, GL_RGBA, 4, size, finish, draw_c);
				run(prog, out_fb, GL_RED_EXT, 1, size, finish, draw_c);
			}
		}
	return 0;
}
