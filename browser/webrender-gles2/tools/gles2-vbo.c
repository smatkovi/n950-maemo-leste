/*
 * gles2-vbo -- does a draw keep the vertex data it was issued with when the
 * same buffer gets new data (glBufferData) before the frame is rendered?
 *
 * WebRender on OpenGL ES 2.0 uploads each batch's instance data into one
 * vertex buffer with glBufferData and draws; a tile-based GPU (PowerVR
 * SGX530) only renders at the end of the frame. Draw 1 puts N quads into the
 * left half in red, the buffer is respecified, draw 2 puts N quads into the
 * right half in green; both halves are read back. Repeated for several N.
 * Then with vertex array objects (OES_vertex_array_object): VAO A owns the
 * big index buffer, VAO B a 6-index one; after binding B and then A again,
 * A's draw of 2 quads must cover both of them.
 * Uses a pbuffer; no window is mapped.
 *
 * Build:  cc -O2 -o gles2-vbo gles2-vbo.c -lEGL -lGLESv2 -lX11
 * Run:    DISPLAY=:0 ./gles2-vbo
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>

/* x, y, r, g per vertex; 4 vertices per quad */
static float *quads(int n, float x0, float r, float g)
{
	float *v = malloc(sizeof(float) * 16 * n);
	int i;
	for (i = 0; i < n; i++) {
		/* n thin quads side by side covering [x0, x0 + 1] x [-1, 1] */
		float a = x0 + (float)i / n, b = x0 + (float)(i + 1) / n;
		float q[16] = { a, -1, r, g,  b, -1, r, g,  a, 1, r, g,  b, 1, r, g };
		int k;
		for (k = 0; k < 16; k++)
			v[16 * i + k] = q[k];
	}
	return v;
}

int main(void)
{
	Display *x = XOpenDisplay(NULL);
	EGLDisplay d = eglGetDisplay((EGLNativeDisplayType)x);
	const EGLint ca[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_NONE };
	const EGLint pa[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
	const EGLint xa[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	static const char *vs = "attribute vec2 aPos; attribute vec2 aCol; varying vec2 vCol;\n"
		"void main() { vCol = aCol; gl_Position = vec4(aPos, 0.0, 1.0); }";
	static const char *fs = "precision mediump float; varying vec2 vCol;\n"
		"void main() { gl_FragColor = vec4(vCol, 0.0, 1.0); }";
	int counts[] = { 1, 2, 16, 64, 1024 }, ci, same;
	EGLConfig cfg;
	EGLint n;
	GLuint p, s, vbo, ibo;
	unsigned short *idx;

	eglInitialize(d, NULL, NULL);
	eglChooseConfig(d, ca, &cfg, 1, &n);
	EGLSurface surf = eglCreatePbufferSurface(d, cfg, pa);
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLContext c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, xa);
	eglMakeCurrent(d, surf, surf, c);
	printf("%s\n", glGetString(GL_RENDERER));

	p = glCreateProgram();
	s = glCreateShader(GL_VERTEX_SHADER); glShaderSource(s, 1, &vs, NULL); glCompileShader(s); glAttachShader(p, s);
	s = glCreateShader(GL_FRAGMENT_SHADER); glShaderSource(s, 1, &fs, NULL); glCompileShader(s); glAttachShader(p, s);
	glBindAttribLocation(p, 0, "aPos");
	glBindAttribLocation(p, 1, "aCol");
	glLinkProgram(p);
	glUseProgram(p);

	idx = malloc(sizeof(unsigned short) * 6 * 1024);
	for (n = 0; n < 1024; n++) {
		static const unsigned short q[6] = { 0, 1, 2, 2, 1, 3 };
		int k;
		for (k = 0; k < 6; k++)
			idx[6 * n + k] = 4 * n + q[k];
	}
	glGenBuffers(1, &ibo);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
	glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(unsigned short) * 6 * 1024, idx, GL_STATIC_DRAW);
	glGenBuffers(1, &vbo);
	glBindBuffer(GL_ARRAY_BUFFER, vbo);
	glEnableVertexAttribArray(0);
	glEnableVertexAttribArray(1);
	glViewport(0, 0, 64, 64);

	for (same = 0; same < 2; same++)
		for (ci = 0; ci < 5; ci++) {
			int count = counts[ci];
			/* same: both draws have the same size; else draw 2 has twice the quads */
			int count2 = same ? count : 2 * count;
			float *left = quads(count, -1, 1, 0), *right = quads(count2 > 1024 ? 1024 : count2, 0, 0, 1);
			unsigned char px[4], q[4];
			if (count2 > 1024)
				count2 = 1024;
			glClearColor(0, 0, 0, 1);
			glClear(GL_COLOR_BUFFER_BIT);
			glBufferData(GL_ARRAY_BUFFER, sizeof(float) * 16 * count, left, GL_STREAM_DRAW);
			glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (void *)0);
			glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (void *)8);
			glDrawElements(GL_TRIANGLES, 6 * count, GL_UNSIGNED_SHORT, 0);
			glBufferData(GL_ARRAY_BUFFER, sizeof(float) * 16 * count2, right, GL_STREAM_DRAW);
			glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (void *)0);
			glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (void *)8);
			glDrawElements(GL_TRIANGLES, 6 * count2, GL_UNSIGNED_SHORT, 0);
			glFinish();
			glReadPixels(16, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
			glReadPixels(48, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, q);
			printf("%4d then %4d quads: left %s  right %s\n", count, count2,
			       px[0] > 128 ? "red (ok)" : px[1] > 128 ? "GREEN" : "empty",
			       q[1] > 128 ? "green (ok)" : q[0] > 128 ? "RED" : "empty");
			free(left);
			free(right);
		}
	{
		PFNGLGENVERTEXARRAYSOESPROC gen = (PFNGLGENVERTEXARRAYSOESPROC)eglGetProcAddress("glGenVertexArraysOES");
		PFNGLBINDVERTEXARRAYOESPROC bind = (PFNGLBINDVERTEXARRAYOESPROC)eglGetProcAddress("glBindVertexArrayOES");
		GLuint vao[2], small_ibo, vbo_a, vbo_b;
		static const unsigned short six[6] = { 0, 1, 2, 2, 1, 3 };
		float *two = quads(2, -1, 1, 0), *one = quads(1, 0, 0, 1);
		unsigned char px[4], q[4];
		int round;
		if (!gen || !bind) {
			printf("no OES_vertex_array_object\n");
			return 0;
		}
		gen(2, vao);
		/* A: two red quads over the left half, the big index buffer */
		bind(vao[0]);
		glGenBuffers(1, &vbo_a);
		glBindBuffer(GL_ARRAY_BUFFER, vbo_a);
		glBufferData(GL_ARRAY_BUFFER, sizeof(float) * 32, two, GL_STATIC_DRAW);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (void *)0);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (void *)8);
		/* B: one green quad over the right half, a 6-index buffer */
		bind(vao[1]);
		glGenBuffers(1, &vbo_b);
		glBindBuffer(GL_ARRAY_BUFFER, vbo_b);
		glBufferData(GL_ARRAY_BUFFER, sizeof(float) * 16, one, GL_STATIC_DRAW);
		glGenBuffers(1, &small_ibo);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, small_ibo);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof six, six, GL_STATIC_DRAW);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (void *)0);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (void *)8);
		for (round = 0; round < 3; round++) {
			glClearColor(0, 0, 0, 1);
			glClear(GL_COLOR_BUFFER_BIT);
			bind(vao[1]);
			glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0);
			bind(vao[0]);
			if (round == 2)	/* respecify A's vertex data while A is bound */
				glBufferData(GL_ARRAY_BUFFER, sizeof(float) * 32, two, GL_STREAM_DRAW);
			glDrawElements(GL_TRIANGLES, 12, GL_UNSIGNED_SHORT, 0);
			glFinish();
			glReadPixels(4, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);	/* A's first quad */
			glReadPixels(28, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, q);	/* A's second quad */
			printf("VAO round %d: A first quad %s, A second quad %s\n", round,
			       px[0] > 128 ? "red (ok)" : "MISSING", q[0] > 128 ? "red (ok)" : "MISSING");
		}
	}
	return 0;
}
