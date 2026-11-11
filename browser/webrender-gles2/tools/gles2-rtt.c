/*
 * gles2-rtt -- cost of rendering into a texture and reading it back, by
 * the texture's size, with a tiny draw: a driver that converts the whole
 * texture between rendering and sampling (or loads and stores it whole)
 * shows a cost growing with the size, not with the drawn area.
 * Columns: a tiny draw alone; after a clear; then sampled; cleared, drawn
 * and sampled; discarded (GL_EXT_discard_framebuffer), drawn and sampled;
 * drawn once and sampled twice.
 * Renders into framebuffers; the window is never mapped.
 *
 * Build:  cc -O2 -o gles2-rtt gles2-rtt.c -lEGL -lGLESv2 -lX11
 * Run:    DISPLAY=:0 ./gles2-rtt
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static GLuint program(const char *vs, const char *fs)
{
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

int main(void)
{
	static const EGLint cfg_attr[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE,
		EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_NONE
	};
	static const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	static const float small[] = { -1, -1, -0.99f, -1, -1, -0.99f, -0.99f, -0.99f };
	static const float full[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
	Display *x = XOpenDisplay(NULL);
	EGLDisplay d;
	EGLConfig cfg;
	EGLint n;
	EGLContext c;
	EGLSurface surf;
	Window win;
	GLuint solid, tex_prog, out_fbo, out_rb;
	int sizes[] = { 256, 512, 1024, 2048 };
	int si, mode, i;
	PFNGLDISCARDFRAMEBUFFEREXTPROC discard =
		(PFNGLDISCARDFRAMEBUFFEREXTPROC)eglGetProcAddress("glDiscardFramebufferEXT");
	static const GLenum color = GL_COLOR_EXT;

	win = XCreateSimpleWindow(x, DefaultRootWindow(x), 0, 0, 64, 64, 0, 0, 0);
	d = eglGetDisplay((EGLNativeDisplayType)x);
	eglInitialize(d, NULL, NULL);
	eglChooseConfig(d, cfg_attr, &cfg, 1, &n);
	c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, ctx_attr);
	surf = eglCreateWindowSurface(d, cfg, (EGLNativeWindowType)win, NULL);
	eglMakeCurrent(d, surf, surf, c);
	printf("%s\n", glGetString(GL_RENDERER));

	solid = program("attribute vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }",
			"void main() { gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0); }");
	tex_prog = program("attribute vec2 aPos; varying highp vec2 vUv;\n"
			   "void main() { vUv = aPos * 0.5 + 0.5; gl_Position = vec4(aPos, 0.0, 1.0); }",
			   "uniform sampler2D sTex; varying highp vec2 vUv;\n"
			   "void main() { gl_FragColor = texture2D(sTex, vUv * 0.01); }");
	/* a small output target stands in for the window */
	glGenRenderbuffers(1, &out_rb);
	glBindRenderbuffer(GL_RENDERBUFFER, out_rb);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, 64, 64);
	glGenFramebuffers(1, &out_fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, out_fbo);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, out_rb);
	glEnableVertexAttribArray(0);

	printf("ms per round (tiny draw into the texture, then a tiny read of it):\n");
	printf("%6s %10s %10s %10s %10s %10s %10s\n", "size", "draw", "clr+draw",
	       "draw+smp", "clr+d+smp", "disc+d+smp", "d+smp*2");
	for (si = 0; si < 4; si++) {
		int sz = sizes[si];
		GLuint tex, fbo;
		glGenTextures(1, &tex);
		glBindTexture(GL_TEXTURE_2D, tex);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, sz, sz, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
		glGenFramebuffers(1, &fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
		glClear(GL_COLOR_BUFFER_BIT);
		glFinish();
		printf("%6d", sz);
		for (mode = 0; mode < 6; mode++) {
			double t0;
			for (i = 0; i < 6; i++) {
				if (i == 1)
					t0 = now_ms();
				glBindFramebuffer(GL_FRAMEBUFFER, fbo);
				glViewport(0, 0, sz, sz);
				if (mode == 1 || mode == 3)
					glClear(GL_COLOR_BUFFER_BIT);
				if (mode == 4 && discard)
					discard(GL_FRAMEBUFFER, 1, &color);
				glUseProgram(solid);
				glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, small);
				glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				if (mode >= 2) {
					glBindFramebuffer(GL_FRAMEBUFFER, out_fbo);
					glViewport(0, 0, 64, 64);
					glUseProgram(tex_prog);
					glBindTexture(GL_TEXTURE_2D, tex);
					glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, full);
					glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				}
				if (mode == 5) {
					glUseProgram(solid);
					glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, small);
					glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
					glUseProgram(tex_prog);
					glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, full);
					glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				}
				glFinish();
			}
			printf(" %10.1f", (now_ms() - t0) / 5.0);
			fflush(stdout);
		}
		printf("\n");
		glDeleteFramebuffers(1, &fbo);
		glDeleteTextures(1, &tex);
	}
	return 0;
}
