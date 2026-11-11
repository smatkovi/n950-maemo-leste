/*
 * gles2-probe -- what an OpenGL ES 2.0 GPU offers WebRender's data path.
 *
 * Prints the limits that matter for WebRender on ES 2.0 and tests the one
 * thing everything rests on: a vertex shader reading a float texture
 * (vertex texture fetch with OES_texture_float), with integers up to 2^24
 * arriving exactly, read at texel centres like texelFetch() would.
 *
 * Build:  cc -O2 -o gles2-probe gles2-probe.c -lEGL -lGLESv2 -lX11
 * Run:    DISPLAY=:0 ./gles2-probe
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 8	/* data texture: 8 x 1 texels, RGBA32F */

static const float values[W][4] = {
	{ 0, 1, 2, 3 },
	{ 255, 256, 65535, 65536 },
	{ 1048575, 1048576, 4194303, 4194304 },
	{ 8388607, 8388608, 16777215, 16777216 },
	{ -1, -255, -65536, -16777215 },
	{ 0.5f, 0.25f, 0.125f, 1.0f / 3.0f },
	{ 1e-6f, 1e6f, 3e38f, -3e38f },
	{ 4095, 4096, 2047, 2048 },
};

static const char *vs_src =
	"attribute vec2 aPos;\n"
	"attribute float aTexel;\n"
	"uniform highp sampler2D sData;\n"
	"uniform highp vec4 uExpect[8];\n"
	"varying lowp vec4 vOk;\n"
	"void main() {\n"
	"  highp vec2 uv = vec2((aTexel + 0.5) / 8.0, 0.5);\n"
	"  highp vec4 v = texture2D(sData, uv);\n"
	"  highp vec4 e = uExpect[int(aTexel)];\n"
	"  vOk = vec4(equal(v, e));\n"
	"  gl_Position = vec4(aPos, 0.0, 1.0);\n"
	"  gl_PointSize = 1.0;\n"
	"}\n";

static const char *fs_src =
	"varying lowp vec4 vOk;\n"
	"void main() { gl_FragColor = vOk; }\n";

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	GLint ok;
	char log[1024];

	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		glGetShaderInfoLog(s, sizeof(log), NULL, log);
		printf("shader compile failed: %s\n", log);
		exit(1);
	}
	return s;
}

static void precision(const char *name, GLenum stage, GLenum type)
{
	GLint range[2], prec;

	glGetShaderPrecisionFormat(stage, type, range, &prec);
	printf("  %-22s range 2^%d..2^%d, precision 2^-%d\n", name,
	       -range[0], range[1], prec);
}

int main(void)
{
	static const EGLint cfg_attr[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE,
		EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_NONE
	};
	static const EGLint ctx_attr[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE
	};
	Display *x = XOpenDisplay(NULL);
	EGLDisplay d;
	EGLConfig cfg;
	EGLint n;
	EGLContext c;
	EGLSurface surf;
	Window win;
	GLint iv;
	GLuint tex, fbo, rb, prog, buf;
	unsigned char px[W][4];
	float verts[W * 3];
	int i, j, bad = 0;

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
	if (!eglMakeCurrent(d, surf, surf, c)) {
		printf("eglMakeCurrent failed\n");
		return 1;
	}

	printf("%s / %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
#define LIMIT(e) do { glGetIntegerv(e, &iv); printf("  %-38s %d\n", #e, iv); } while (0)
	LIMIT(GL_MAX_TEXTURE_SIZE);
	LIMIT(GL_MAX_RENDERBUFFER_SIZE);
	LIMIT(GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS);
	LIMIT(GL_MAX_TEXTURE_IMAGE_UNITS);
	LIMIT(GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS);
	LIMIT(GL_MAX_VERTEX_ATTRIBS);
	LIMIT(GL_MAX_VERTEX_UNIFORM_VECTORS);
	LIMIT(GL_MAX_FRAGMENT_UNIFORM_VECTORS);
	LIMIT(GL_MAX_VARYING_VECTORS);
	glGetIntegerv(GL_MAX_VIEWPORT_DIMS, &iv);
	printf("precision:\n");
	precision("vertex highp float", GL_VERTEX_SHADER, GL_HIGH_FLOAT);
	precision("vertex highp int", GL_VERTEX_SHADER, GL_HIGH_INT);
	precision("fragment highp float", GL_FRAGMENT_SHADER, GL_HIGH_FLOAT);
	precision("fragment mediump float", GL_FRAGMENT_SHADER, GL_MEDIUM_FLOAT);
	precision("fragment highp int", GL_FRAGMENT_SHADER, GL_HIGH_INT);

	/* the data texture */
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, 1, 0, GL_RGBA, GL_FLOAT, values);
	printf("float texture upload: GL error 0x%x\n", glGetError());

	/* render target: W x 1 RGBA8, one point per texel */
	glGenRenderbuffers(1, &rb);
	glBindRenderbuffer(GL_RENDERBUFFER, rb);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, W, 1);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
				  GL_RENDERBUFFER, rb);
	printf("framebuffer: 0x%x\n", glCheckFramebufferStatus(GL_FRAMEBUFFER));

	prog = glCreateProgram();
	glAttachShader(prog, shader(GL_VERTEX_SHADER, vs_src));
	glAttachShader(prog, shader(GL_FRAGMENT_SHADER, fs_src));
	glBindAttribLocation(prog, 0, "aPos");
	glBindAttribLocation(prog, 1, "aTexel");
	glLinkProgram(prog);
	glGetProgramiv(prog, GL_LINK_STATUS, &iv);
	if (!iv) {
		char log[1024];
		glGetProgramInfoLog(prog, sizeof(log), NULL, log);
		printf("link failed: %s\n", log);
		return 1;
	}
	glUseProgram(prog);
	glUniform1i(glGetUniformLocation(prog, "sData"), 0);
	glUniform4fv(glGetUniformLocation(prog, "uExpect"), W, &values[0][0]);

	for (i = 0; i < W; i++) {
		verts[i * 3 + 0] = -1.0f + (2.0f * i + 1.0f) / W;
		verts[i * 3 + 1] = 0.0f;
		verts[i * 3 + 2] = (float)i;
	}
	glGenBuffers(1, &buf);
	glBindBuffer(GL_ARRAY_BUFFER, buf);
	glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 12, (void *)0);
	glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, 12, (void *)8);
	glEnableVertexAttribArray(0);
	glEnableVertexAttribArray(1);

	glViewport(0, 0, W, 1);
	glClearColor(0.5f, 0.5f, 0.5f, 0.5f);
	glClear(GL_COLOR_BUFFER_BIT);
	glDrawArrays(GL_POINTS, 0, W);
	memset(px, 0, sizeof(px));
	glReadPixels(0, 0, W, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	printf("draw: GL error 0x%x\n", glGetError());

	printf("vertex texture fetch of RGBA32F, exact at texel centres:\n");
	for (i = 0; i < W; i++) {
		printf("  texel %d:", i);
		for (j = 0; j < 4; j++) {
			int ok = px[i][j] > 200;
			printf(" %s(%.8g)", ok ? "ok" : "WRONG", values[i][j]);
			bad += !ok;
		}
		printf("\n");
	}
	printf("%s\n", bad ? "RESULT: some values wrong" : "RESULT: all exact");
	return 0;
}
