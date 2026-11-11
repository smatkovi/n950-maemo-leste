/*
 * gles2-checks -- GLSL ES 1.00 behaviour WebRender depends on, per driver.
 *
 * 1. fwidth() of a varying that grows by one per pixel (expected 1.0),
 *    as WebRender's anti-aliasing uses it (OES_standard_derivatives).
 * 2. A vertex shader reading an RGBA float texture whose height is not a
 *    power of two (1024 x 3), at texel centres, as WebRender's data
 *    textures are read.
 * Renders into a framebuffer; the window is never mapped.
 *
 * Build:  cc -O2 -o gles2-checks gles2-checks.c -lEGL -lGLESv2 -lX11
 * Run:    DISPLAY=:0 ./gles2-checks
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

static GLuint program(const char *vs, const char *fs)
{
	GLuint p = glCreateProgram(), s[2];
	const char *src[2] = { vs, fs };
	GLenum type[2] = { GL_VERTEX_SHADER, GL_FRAGMENT_SHADER };
	GLint ok;
	char log[1024];
	int i;

	for (i = 0; i < 2; i++) {
		s[i] = glCreateShader(type[i]);
		glShaderSource(s[i], 1, &src[i], NULL);
		glCompileShader(s[i]);
		glGetShaderiv(s[i], GL_COMPILE_STATUS, &ok);
		if (!ok) {
			glGetShaderInfoLog(s[i], sizeof(log), NULL, log);
			printf("compile: %s\n", log);
			exit(1);
		}
		glAttachShader(p, s[i]);
	}
	glBindAttribLocation(p, 0, "aPos");
	glLinkProgram(p);
	glGetProgramiv(p, GL_LINK_STATUS, &ok);
	if (!ok) {
		glGetProgramInfoLog(p, sizeof(log), NULL, log);
		printf("link: %s\n", log);
		exit(1);
	}
	glUseProgram(p);
	return p;
}

int main(void)
{
	static const EGLint cfg_attr[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE,
		EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_NONE
	};
	static const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	Display *x = XOpenDisplay(NULL);
	EGLDisplay d;
	EGLConfig cfg;
	EGLint n;
	EGLContext c;
	EGLSurface surf;
	Window win;
	GLuint fbo, rb, tex, p;
	unsigned char px[64 * 4 * 4];
	float quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
	float data[1024 * 3 * 4];
	int i, bad;

	win = XCreateSimpleWindow(x, DefaultRootWindow(x), 0, 0, 16, 16, 0, 0, 0);
	d = eglGetDisplay((EGLNativeDisplayType)x);
	eglInitialize(d, NULL, NULL);
	eglChooseConfig(d, cfg_attr, &cfg, 1, &n);
	c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, ctx_attr);
	surf = eglCreateWindowSurface(d, cfg, (EGLNativeWindowType)win, NULL);
	eglMakeCurrent(d, surf, surf, c);
	printf("%s\n", glGetString(GL_RENDERER));

	glGenRenderbuffers(1, &rb);
	glBindRenderbuffer(GL_RENDERBUFFER, rb);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, 64, 4);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
	glViewport(0, 0, 64, 4);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
	glEnableVertexAttribArray(0);

	/* 1: fwidth of a varying growing by 1 per pixel, as highp and mediump */
	{
		const char *prec[2] = { "highp", "mediump" };
		int k;
		for (k = 0; k < 2; k++) {
			char fs[512];
			snprintf(fs, sizeof(fs),
				"#extension GL_OES_standard_derivatives : enable\n"
				"precision %s float;\n"
				"varying vec2 vPix;\n"
				"void main() { vec2 w = fwidth(vPix);\n"
				"  gl_FragColor = vec4(w.x * 0.25, w.y * 0.25, 0.0, 1.0); }\n", prec[k]);
			p = program("attribute vec2 aPos; varying highp vec2 vPix;\n"
				    "void main() { vPix = (aPos * 0.5 + 0.5) * vec2(64.0, 4.0);\n"
				    "  gl_Position = vec4(aPos, 0.0, 1.0); }\n", fs);
			glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
			glReadPixels(0, 0, 64, 4, GL_RGBA, GL_UNSIGNED_BYTE, px);
			bad = 0;
			for (i = 0; i < 64 * 4; i++)
				if (abs(px[i * 4] - 64) > 2 || abs(px[i * 4 + 1] - 64) > 2)
					bad++;
			printf("fwidth (%s): %d of 256 pixels wrong (pixel 10: %d %d, expected 64 64)\n",
			       prec[k], bad, px[40], px[41]);
			glDeleteProgram(p);
		}
	}

	/* 2: vertex texture fetch from a 1024 x 3 float texture */
	for (i = 0; i < 1024 * 3; i++) {
		data[i * 4 + 0] = (float)i;
		data[i * 4 + 1] = (float)(i % 1024);
		data[i * 4 + 2] = (float)(i / 1024);
		data[i * 4 + 3] = 1.0f;
	}
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1024, 3, 0, GL_RGBA, GL_FLOAT, data);
	p = program("attribute vec2 aPos; uniform highp sampler2D sData; varying lowp vec4 vOk;\n"
		    "void main() {\n"
		    "  highp vec2 cell = floor((aPos * 0.5 + 0.5) * vec2(64.0, 4.0) - 0.5 + 0.5);\n"
		    "  highp float col = mod(cell.x * 37.0 + 5.0, 1024.0); highp float row = mod(cell.y, 3.0);\n"
		    "  highp vec4 v = texture2D(sData, (vec2(col, row) + 0.5) / vec2(1024.0, 3.0));\n"
		    "  vOk = vec4(v.x == row * 1024.0 + col ? 1.0 : 0.0, v.y == col ? 1.0 : 0.0, v.z == row ? 1.0 : 0.0, 1.0);\n"
		    "  gl_Position = vec4((cell + 0.5) / vec2(32.0, 2.0) - 1.0, 0.0, 1.0); gl_PointSize = 1.0;\n"
		    "}\n",
		    "varying lowp vec4 vOk; void main() { gl_FragColor = vOk; }\n");
	{
		float pts[64 * 4 * 2];
		int k = 0, xx, yy;
		for (yy = 0; yy < 4; yy++)
			for (xx = 0; xx < 64; xx++) {
				pts[k++] = (xx + 0.5f) / 32.0f - 1.0f;
				pts[k++] = (yy + 0.5f) / 2.0f - 1.0f;
			}
		glClearColor(0.5, 0.5, 0.5, 0.5);
		glClear(GL_COLOR_BUFFER_BIT);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, pts);
		glDrawArrays(GL_POINTS, 0, 64 * 4);
		glReadPixels(0, 0, 64, 4, GL_RGBA, GL_UNSIGNED_BYTE, px);
		bad = 0;
		for (i = 0; i < 64 * 4; i++)
			if (px[i * 4] < 200 || px[i * 4 + 1] < 200 || px[i * 4 + 2] < 200)
				bad++;
		printf("vertex fetch 1024x3 float: %d of 256 points wrong\n", bad);
	}
	printf("GL error 0x%x\n", glGetError());
	return 0;
}
