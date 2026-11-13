# PGO for the N950's EmbedLite engine

The engine (embedlite-n950 153.6.0-n950.2 on) is built with profile-guided
optimization from runs on the N950 itself, and with ThinLTO across C++ and
Rust. On the N950 this halved layout time (bench.html: 6.3–6.5 s → 3.4–3.7 s
in total, layout 4.8 s → 2.3 s); code the JIT generates is unchanged.

1. clang's ARM profile runtime: `build-profile-runtime.sh` (Arch's
   compiler-rt has none for armhf), installed into clang's resource directory.
2. Instrumented build: `N950_PGO=generate bash ../build.sh configure|build`,
   then `install` into a staging directory; pack its
   `usr/lib/arm-linux-gnueabihf/xulrunner-qt5-153.6.0` (without
   `shader-cache`) as `/root/pgogen.tar.xz` on the phone. Profiles cover the
   C++ code only: rustup's thumbv7neon standard library has no profiler
   runtime.
3. Training on the phone: `train-on-phone.sh <md5 of the tarball> <build ID
   compiled into libxul>`, detached, as root (about 25 minutes, the shell is
   visible). The shell's `EMBEDLITE_SHELL_QUIT` ends each page normally; an
   instrumented engine writes its profile only then.
4. `llvm-profdata merge -o merged.profdata *.profraw` on the PC (the
   profiles are in `/home/user/.cache/pgo`).
5. Optimized build: `N950_PGO=use N950_PGO_PROFILE=merged.profdata bash
   ../build.sh configure|build|install`, packed by `../../make-debs.sh`
   (which stamps the shader cache with the build ID compiled into libxul).

`bench.html` measures DOM building, layout, HTML parsing, JSON, regular
expressions, sorting and strings, median of five rounds; read the result
from the screen after about 150 s.
