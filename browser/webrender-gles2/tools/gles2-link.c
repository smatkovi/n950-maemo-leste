/*
 * gles2-link -- compiles and links shader pairs on the device's GPU.
 *
 * For every NAME.vert in a directory with a NAME.frag next to it (the
 * dump of `WRENCH_SHADER_DUMP=DIR wrench --renderer es2 compile_shaders`),
 * compiles both and links them in an OpenGL ES 2.0 context, and prints the
 * driver's log for each that fails. Drivers differ from Mesa in what they
 * accept (the PowerVR SGX530 runs out of varyings and sampler slots where
 * Mesa does not), so this is the check that counts.
 * Uses a pbuffer; no window is mapped.
 *
 * Build:  cc -O2 -o gles2-link gles2-link.c -lEGL -lGLESv2 -lX11
 * Run:    DISPLAY=:0 ./gles2-link DIR   (exit status 1 when one fails)
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <X11/Xlib.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *slurp(const char *path)
{
	FILE *f = fopen(path, "rb");
	if (!f)
		return NULL;
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	char *s = malloc(n + 1);
	if (fread(s, 1, n, f) != (size_t)n) {
		fclose(f);
		free(s);
		return NULL;
	}
	s[n] = 0;
	fclose(f);
	return s;
}

static GLuint compile(GLenum type, const char *src, const char *name)
{
	GLuint sh = glCreateShader(type);
	glShaderSource(sh, 1, &src, NULL);
	glCompileShader(sh);
	GLint ok = 0;
	glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[4096] = "";
		glGetShaderInfoLog(sh, sizeof log, NULL, log);
		printf("FAIL %s: %s shader does not compile\n%s\n", name,
		       type == GL_VERTEX_SHADER ? "vertex" : "fragment", log);
		glDeleteShader(sh);
		return 0;
	}
	return sh;
}

static int cmp(const void *a, const void *b)
{
	return strcmp(*(char *const *)a, *(char *const *)b);
}

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: %s DIR\n", argv[0]);
		return 2;
	}
	Display *x = XOpenDisplay(NULL);
	EGLDisplay d = eglGetDisplay((EGLNativeDisplayType)x);
	if (!eglInitialize(d, NULL, NULL)) {
		fprintf(stderr, "eglInitialize failed\n");
		return 2;
	}
	const EGLint cfg_attrs[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_NONE };
	EGLConfig cfg;
	EGLint n = 0;
	if (!eglChooseConfig(d, cfg_attrs, &cfg, 1, &n) || n < 1) {
		fprintf(stderr, "no ES 2.0 pbuffer config\n");
		return 2;
	}
	const EGLint pb_attrs[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
	EGLSurface s = eglCreatePbufferSurface(d, cfg, pb_attrs);
	const EGLint ctx_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLContext c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, ctx_attrs);
	if (!c || !eglMakeCurrent(d, s, s, c)) {
		fprintf(stderr, "no ES 2.0 context\n");
		return 2;
	}
	printf("%s, %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));

	DIR *dir = opendir(argv[1]);
	if (!dir) {
		perror(argv[1]);
		return 2;
	}
	char *names[1024];
	int count = 0;
	struct dirent *e;
	while ((e = readdir(dir)) && count < 1024) {
		size_t len = strlen(e->d_name);
		if (len > 5 && !strcmp(e->d_name + len - 5, ".vert"))
			names[count++] = strndup(e->d_name, len - 5);
	}
	closedir(dir);
	qsort(names, count, sizeof names[0], cmp);

	int failed = 0, linked = 0;
	for (int i = 0; i < count; i++) {
		char vp[4096], fp[4096];
		snprintf(vp, sizeof vp, "%s/%s.vert", argv[1], names[i]);
		snprintf(fp, sizeof fp, "%s/%s.frag", argv[1], names[i]);
		char *vs = slurp(vp), *fs = slurp(fp);
		if (!vs || !fs) {
			free(vs);
			free(fs);
			continue;
		}
		/* The SGX530 sometimes refuses a pair whose vertex and fragment
		 * shaders both read a sampler ("Uniform variable ... type/precision
		 * does not match"), a different one on each run; linking the same
		 * program again fails again, so each attempt compiles afresh. */
		char log[4096] = "";
		int ok = 0, attempt;
		for (attempt = 1; !ok && attempt <= 4; attempt++) {
			GLuint v = compile(GL_VERTEX_SHADER, vs, names[i]);
			GLuint f = v ? compile(GL_FRAGMENT_SHADER, fs, names[i]) : 0;
			if (!v || !f) {
				if (v)
					glDeleteShader(v);
				break;
			}
			GLuint p = glCreateProgram();
			glAttachShader(p, v);
			glAttachShader(p, f);
			glLinkProgram(p);
			glGetProgramiv(p, GL_LINK_STATUS, &ok);
			if (!ok)
				glGetProgramInfoLog(p, sizeof log, NULL, log);
			else if (getenv("BINARY_LENGTH")) {
				GLint len = -1;
				glGetProgramiv(p, 0x8741 /* GL_PROGRAM_BINARY_LENGTH_OES */, &len);
				printf("%s: binary %d bytes, gl error 0x%x\n", names[i], len, glGetError());
			}
			glDeleteProgram(p);
			glDeleteShader(v);
			glDeleteShader(f);
		}
		free(vs);
		free(fs);
		if (ok) {
			linked++;
			if (attempt > 2)
				printf("%s: linked at attempt %d, before: %s", names[i],
				       attempt - 1, log);
		} else {
			printf("FAIL %s: does not link\n%s\n", names[i], log);
			failed++;
		}
	}
	printf("%d linked, %d failed\n", linked, failed);
	eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglTerminate(d);
	return failed ? 1 : 0;
}
