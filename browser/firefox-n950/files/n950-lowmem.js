// Firefox ESR on the Nokia N950: one Cortex-A8 core, 1 GB of RAM, an
// OpenGL ES 2.0 GPU (PowerVR SGX530). Defaults (pref, not lockPref), so a
// user can still change them in about:config.

// Memory: one web content process, no site isolation (Fission), no
// preloaded spare process; tabs unloaded when memory runs low.
pref("fission.autostart", false);
pref("dom.ipc.processCount", 1);
pref("dom.ipc.processCount.webIsolated", 1);
pref("dom.ipc.processPrelaunch.enabled", false);
pref("browser.tabs.unloadOnLowMemory", true);
// no pages kept for back/forward, smaller caches and image memory
pref("browser.sessionhistory.max_total_viewers", 0);
pref("browser.cache.memory.capacity", 16384);
pref("media.memory_cache_max_size", 16384);
pref("image.mem.surfacecache.max_size_kb", 32768);
pref("browser.sessionstore.interval", 60000);

// JavaScript: save a page's scripts as compiled bytecode on the first visit
// already (default: after the 4th load), so later visits skip parsing and
// compiling, the slow part on the Cortex-A8. WebAssembly's compiled machine
// code is cached as well (javascript.options.wasm_caching, on by default).
// Both live in the disk cache: a fixed 100 MB instead of the smart size,
// which is small on a nearly full root file system.
pref("dom.script_loader.bytecode_cache.enabled", true);
pref("dom.script_loader.bytecode_cache.strategy", -1);
pref("browser.cache.disk.enable", true);
pref("browser.cache.disk.smart_size.enabled", false);
pref("browser.cache.disk.capacity", 102400);

// Drawing: WebRender on the SGX530 through its OpenGL ES 2.0 path (the
// patches in patches/): text rasterises about 5 times faster than with the
// software renderer. gfx.webrender.software = true in about:config goes
// back to the software renderer.
pref("gfx.webrender.all", true);
pref("gfx.webrender.software", false);
// Compiled shader programs are kept in the profile: the SGX530 needs
// about 1.5 s per program, so each is compiled only once.
pref("gfx.webrender.program-binary-disk", true);
// With the software renderer: its tiles shown through OpenGL ES 2.0
// (RenderCompositorOGLSWGL, Firefox's default on Android, made for GPUs
// without ES 3.0), so scrolling and blending do not cost the CPU
pref("gfx.webrender.software.opengl", true);
// Linux keeps hardware compositing off for drivers it does not know
// ("blocked by platform"), and with it the OpenGL compositor that lets the
// SGX530 composite SWGL's tiles.
pref("layers.acceleration.force-enabled", true);
// The SGX530's driver rejects robust contexts ("Unsupported context flags:
// 0x4"); Gecko falls back after several failed attempts.
pref("gfx.webrender.prefer-robustness", false);
pref("layout.frame_rate", 30);
pref("general.smoothScroll", false);
pref("toolkit.cosmeticAnimations.enabled", false);
pref("ui.prefersReducedMotion", 1);
// no AV1 (too heavy for the Cortex-A8): sites fall back to VP9 or H.264
pref("media.av1.enabled", false);
// 854x480 on 3.9 inches
pref("layout.css.devPixelsPerPx", "1.25");

// Startup and background work: a blank start and new tab page, no Pocket,
// no telemetry, studies or recommendations.
pref("browser.startup.homepage", "about:blank");
pref("browser.newtabpage.enabled", false);
pref("browser.newtabpage.activity-stream.feeds.topsites", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("extensions.pocket.enabled", false);
pref("browser.discovery.enabled", false);
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("toolkit.telemetry.enabled", false);
pref("toolkit.telemetry.unified", false);
pref("app.shield.optoutstudies.enabled", false);
pref("app.normandy.enabled", false);
pref("browser.ml.enable", false);
