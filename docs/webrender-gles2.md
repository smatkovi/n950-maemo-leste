# WebRender on OpenGL ES 2.0 (PowerVR SGX530): what would have to be rebuilt

Firefox draws only through WebRender. Its GPU backend needs OpenGL ES 3.0;
below that, Firefox uses SWGL, WebRender in software, on the CPU. The N950's
SGX530 has OpenGL ES 2.0 (PowerVR DDK 1.17), so Firefox ESR on the N950
rasterises everything on the one Cortex-A8 core.

This is an inventory of the OpenGL ES 3.0 features WebRender of Firefox ESR
153.6 (tag `FIREFOX_153_6_0esr_RELEASE`, `gfx/wr/webrender`) uses, and what
each one would need under ES 2.0. Counts are from its 47 shader files
(`res/`) and `src/device/gl.rs`.

None of these can simply be left out: they are WebRender's data path. Every
primitive reads its header, transform, render task and GPU buffer data from
textures with integer texel addresses, and every batch is drawn instanced.

Already absent in ESR 153: texture arrays (`sampler2DArray`), `gl_VertexID`,
`gl_InstanceID`, `textureLod`, uniform buffers, multiple render targets.

## Shaders (a GLSL ES 1.00 variant of each)

WebRender builds per-backend shader variants already (GLSL 150 and GLSL ES
3.00 with a prefix); ES 2.0 would be a third one.

| ES 3.0 feature | Uses | Under ES 2.0 |
|---|---|---|
| `texelFetch` / `TEXEL_FETCH` on data textures | 62 in 13 files | `texture2D` at `(texel + 0.5) / size`, nearest filtering; needs float textures (`OES_texture_float`) readable in the vertex shader (vertex texture fetch) |
| `textureSize` | 7 in 4 files | the sizes as uniforms |
| integer textures `isampler2D` (`sPrimitiveHeadersI`, `sGpuBufferI`) | 2 | float textures; every value below 2^24 |
| integer vertex attributes (`aData`, `glVertexAttribIPointer`) | 2 sites | float attributes; values packed into 32 bits split into several |
| bit operations `&`, `<<`, `>>` | 85 in 14 files | `floor`/`mod` arithmetic |
| `uint`/`uvec` | 7 | float or int |
| `flat` varyings | 131 in 27 files | ordinary varyings (all vertices of a quad write the same value) |
| `out vec4` fragment outputs | 30 | `gl_FragColor` |
| dual-source blending (subpixel text) | 22 in 7 files | off: `supports_dual_source_blending = false` (grayscale text antialiasing) |
| `fwidth`/`dFdx`/`dFdy` | 8 | `OES_standard_derivatives` |
| `inverse()`, `transpose()`, `round()` | 4 | own GLSL functions |

## GL device and renderer

| ES 3.0 feature | Sites in gl.rs | Under ES 2.0 |
|---|---|---|
| instanced drawing (`glDrawElementsInstanced`, `glVertexAttribDivisor`) | 3 | the biggest piece: without `GL_EXT_instanced_arrays`, each instance's data repeated for its 4 corners on the CPU, with a quad index buffer (`OES_element_index_uint`, or batches split at 16384 quads) |
| pixel buffer objects (`PIXEL_UNPACK_BUFFER`/`PACK`) | 28 | uploads straight from memory (`glTexSubImage2D`; WebRender has an immediate upload method) |
| `glMapBufferRange` | 5 | `glBufferSubData` |
| `glTexStorage2D` | 1 | `glTexImage2D` (gl.rs falls back already for GLES with BGRA) |
| `R8`/`RED` textures | 9 | `LUMINANCE` or `ALPHA` |
| `RG8` textures | 7 | `LUMINANCE_ALPHA` or RGBA8 |
| `R16` textures (high bit depth video) | 3 | off, or converted to 8 bit |
| `RGBA32F`/`RGBA16F` | 1 | `OES_texture_float` / `OES_texture_half_float` |
| `RGBA32I` | 4 | float textures (see above) |
| `DEPTH_COMPONENT24` | 3 | `OES_depth24` / `OES_packed_depth_stencil` |
| `glBlitFramebuffer` | 1 | a textured quad, or `glCopyTexSubImage2D` |
| `glInvalidateFramebuffer` | 2 | `EXT_discard_framebuffer` |
| `glCopyImageSubData` | 5 | off (`supports_copy_image_sub_data` exists) |
| texture swizzle | 4 | off (`supports_texture_swizzle` exists); BGRA via `EXT_texture_format_BGRA8888` |
| `glGetStringi` | 1 | parse `glGetString(GL_EXTENSIONS)` |
| `glFenceSync`/`glClientWaitSync` | 2 | `EGL_KHR_fence_sync`, or `glFinish` |
| vertex array objects (core in ES 3.0) | – | `OES_vertex_array_object`, or binding attributes per draw |
| `GL_MAJOR_VERSION` query | 1 | parse the version string |

On the Gecko side, the GPU backend is only chosen with ES 3.0
(`gfxInfo`/`gfxPlatform`); that gate would have to accept the ES 2.0 path.

## The N950's GPU, measured

`browser/webrender-gles2/tools/gles2-probe.c` on the phone (PowerVR SGX 530,
OpenGL ES 2.0 build 1.17@4948957, 2026-11-11):

- Vertex texture fetch works: 8 texture units in the vertex shader (8 in the
  fragment shader, 8 combined). An RGBA32F texture read with `texture2D` at
  texel centres returned every test value exactly: integers up to 2^24
  (16777216) and down to -16777215, fractions, 1e-6 and ±3e38. That is the
  replacement for `texelFetch` on WebRender's data textures.
- highp is IEEE single precision in both stages (2^-23); highp int covers
  ±2^24. Integers in floats are exact up to 2^24, as WebRender's data needs.
- 16 vertex attributes, 128 vertex and 64 fragment uniform vectors,
  textures and render buffers up to 2048 x 2048.
- Only 8 varying vectors. Counting WebRender's varyings per shader (with its
  includes, all feature variants, every float or vec2 as a whole vector, so
  an upper bound): cs_svg_filter_node 17, composite 16, cs_border_segment
  14, cs_clip_rectangle 13, cs_border_solid 11, cs_blur 9, ps_text_run 8,
  the rest 6 or fewer. Those over 8 need their per-primitive constants
  (WebRender's `flat` varyings) read in the fragment shader from the data
  textures by one primitive index instead, or packed.

Extensions present (relevant ones): OES_texture_float, OES_texture_half_float,
EXT_texture_rg (R8, RG8), EXT_texture_storage, OES_element_index_uint (no
16384-quad split), OES_vertex_array_object, OES_mapbuffer,
OES_standard_derivatives, OES_fragment_precision_high, EXT_discard_framebuffer,
OES_egl_sync, OES_depth24, OES_packed_depth_stencil, OES_depth_texture,
EXT_texture_format_BGRA8888, EXT_shader_texture_lod, OES_EGL_image_external,
KHR_debug, EXT_multisampled_render_to_texture.

Missing, to be rebuilt: instanced drawing (no instanced-arrays extension of
any kind), pixel buffer objects, framebuffer blit, integer textures and
attributes, `texelFetch`, bit operations, `flat`.

## Assessment

About 25 items. Most shader work is mechanical; the real work is replacing
instancing, carrying the integer data in float textures and attributes, and
testing every primitive and clip type against SWGL's output. That is weeks,
not days, and needs an own Firefox build (the slim one). Whether the SGX530
(two USSE pipes) then beats SWGL on the 1 GHz Cortex-A8 is open; text
rasterisation stays on the CPU either way.

Before starting: the SGX530's actual extension list (float textures, vertex
texture units, `EXT_instanced_arrays`, `OES_element_index_uint`,
`OES_vertex_array_object`), and a measurement of SWGL with the GL compositor
(`gfx.webrender.software.opengl`), which already moves compositing to the GPU.

## Progress (2026-11-11)

Work tree: branch `n950-esr153.6` of github smatkovi/gecko-dev,
`n950/gecko-patches` (Gecko 153.6.0esr with EmbedLite).

Test bed on the PC: wrench with `--renderer es2` under Mesa with
`MESA_GLES_VERSION_OVERRIDE=2.0` and the instancing extensions hidden
(`MESA_EXTENSION_OVERRIDE=-GL_EXT_instanced_arrays ...`), a real ES 2.0
context. `wrench compile_shaders` compiles and links every shader variant
(`WRENCH_SHADERS` reads them from the source tree, `WRENCH_SHADER_DUMP`
writes them out, `WRENCH_REPORT_SAMPLERS` lists the active samplers).

Done:

- ES 2.0 contexts are detected (GL_VERSION, glGetString(GL_EXTENSIONS)),
  `ShaderVersion::Gles2` gives `#version 100` with `WR_GLES2`.
- All 49 GLES shader variants compile and link as GLSL ES 1.00. Shared
  changes for every version (bit fields through WR_BITS/WR_HAS_FLAG/...,
  switch as if/else, no array returns or constructors) leave the 1471
  wrench reftests under GL 3 exactly as with the original shaders. The
  ES 1.00-only differences are a line rewrite in webrender_build
  (texelFetch, textureSize, integer samplers, attributes and varyings,
  texture(), mix with booleans, transpose, inverse, round).

Measured against the SGX530's limits:

- Samplers: one variant uses 9 of 8 (brush_yuv_image with ALPHA_PASS);
  merging the integer data textures into the float ones fixes it.
- Varyings, packed by the GLSL ES 1.00 rules: 15 of 49 variants need 9 to
  13 rows of 8: ps_quad_mask, ps_quad_box_shadow, ps_quad_gradient,
  cs_border_segment, cs_border_solid, cs_clip_rectangle, brush_blend,
  cs_svg_filter_node, the YUV ones. Common on web pages (rounded clips,
  borders, shadows, gradients): their per-primitive constants have to move
  out of varyings.
- Integers: SGX highp int is ±2^24, so packed 32-bit fields in instance
  attributes (aData, aFlags) and in the primitive headers' user data have
  to reach ES 2.0 shaders as 16-bit halves.

Next, the device side: instancing emulation, integer attributes as float
halves, float data textures with the `sX_Size` uniforms, no pixel buffer
objects, a blit fallback; then the varying reduction, then a first frame
on the phone against SWGL.

## On the phone (2026-11-11)

WebRender runs on the SGX530 (Gecko patches 0158 to 0169): one
framebuffer binding, drawing without instancing (each instance repeated
for the four corners), integer attributes as 16-bit halves, ES 2.0
texture formats and uploads, copies instead of blits, per-program
texture units (8 on the SGX), quad, gradient and clip shaders packed into
8 varying vectors, and the samplers' size uniforms that the texelFetch
emulation needs.

The SGX530's driver (DDK 1.17) corrupts its heap when a float texture the
GPU may still read gets a sub-image (`tools/gles2-floattex.c` shows it);
WebRender's float data textures are therefore allocated anew at their
first upload of each frame.

Measured with wrench on the N950 (854 x 480, hidden window, no vsync,
render() up to glFinish, against SWGL on the same phone), milliseconds
per frame:

| scene | SGX raster | SWGL raster | SGX composite | SWGL composite |
|---|---|---|---|---|
| simple-batching | 152.9 | 32.8 | 6.3 | 9.6 |
| unaligned-gradient | 524.6 | 26.0 | 6.0 | 12.7 |
| aligned-gradient | 529.2 | 785.3 | 6.3 | 12.3 |
| transforms-simple | 2642.3 | 988.6 | 6.3 | 12.2 |
| text-rendering | 55.8 | 229.5 | 12.3 | 23.9 |

Compositing on the GPU is twice as fast as SWGL's, and text is four times
faster. Rasterising with WebRender's general shaders is slower than SWGL
for everything else. Per frame the SGX spends most of its time in
glDrawElements (about 37 ms per call in simple-batching: every vertex
fetches its instance's data from float textures, four times per
instance without instancing) and in clears (18 ms each, render targets
up to 2048 x 2048 on a tile-based GPU). Reftests under a strict ES 2.0
context on the PC: gradient 99/99, clip 25/30, scrolling 27/29, split
20/21, text 42/71, transforms 28/55; blend modes, borders, box shadows
and filters are still mostly wrong.

### Later on 2026-11-11

- Packed 32-bit instance fields (quad flags in `aData.z`, glyph index
  with flags and resource address with a byte above in the brush
  instances) exceed what a float holds exactly; on ES 2.0 they are now
  decoded from the attribute's 16-bit halves (Gecko patches 0169, 0172).
  Text drew every glyph of a run at one spot before.
- GLSL ES leaves unwritten globals undefined: Mesa reads zero, the SGX530
  garbage. The integer globals that stand in for varyings in the vertex
  shader start at zero (0170).
- The quad fragment shader unpacks its flags once per fragment: simple
  quads rasterise in 84 ms instead of 156 ms on the SGX530 (still 33 ms
  with SWGL); text in 40 ms against 230 ms with SWGL.
- On the SGX530, transforms-simple renders with stripes when fragment
  shaders run in highp and correctly in mediump; under Mesa it is right
  in both. Not yet understood (a derivative of a computed expression in
  highp is the suspect).
- PC reftests under strict ES 2.0: 427 of 560 pass (349 before these
  fixes): gradient 99/99, scrolling 29/29, split 21/21, clip 27/30,
  filters 65/83, text 53/71, mask 14/18, transforms 31/55, blend 10/24.

### Where the SGX530's raster time goes (2026-11-11 evening)

Measured with wrench on the phone (854×480, hidden window, every frame
rasterised, render time to glFinish, ms per frame):

- Render target size is not it. Rendering into a texture and sampling it
  afterwards costs by the texture's size on the SGX530 (`tools/gles2-rtt.c`:
  1024² about 10 ms, 2048² about 44 ms), but shrinking WebRender's shared
  targets and atlases to 512 or 1024 and the picture tiles to 512×256
  changed nothing. Discarding framebuffers (GL_EXT_discard_framebuffer)
  and RGBA instead of BGRA targets changed nothing either.
- Per-draw timing fenced with glFinish is misleading on this driver: the
  first clear of a frame took the whole previous raster time. Only
  totals are reliable.
- The cost is the fragment shaders, including code a fragment never
  executes. With the quad fragment shader reduced to a constant colour,
  rectangles took 16 ms and gradients 24 ms. Removing only the edge
  anti-aliasing branch, which no rectangle in the scene enters, took
  rectangles from 84 to 30 ms; removing the gradient-kind switch and the
  stop-tree path took gradients from 454 to 234 ms, with the flag
  unpacking gone as well 111 ms.
- Gecko patch 0176 adds ES 2.0-only fast variants, chosen per batch:
  ps_quad_textured without edge anti-aliasing or mask output, and a
  ps_quad_gradient for clamped linear gradients with two stops whose
  vertex shader computes the stop factor.

| benchmark          | before | 0176 | SWGL | image vs SWGL |
|--------------------|-------:|-----:|-----:|---------------|
| simple-batching    |   83.7 | 31.2 | 28.6 | same          |
| unaligned-gradient |    454 | 73.0 | 30.7 | same          |
| aligned-gradient   |      – | 69.0 |    – | same          |
| text-rendering     |     41 | 40.9 |  207 | grey vs subpixel AA |
| transforms-simple  |   1583 | 1583 |  701 | 0.1 %         |

Text differs from SWGL only by anti-aliasing: ES 2.0 has no dual-source
blending, so glyphs are grey-scale anti-aliased. transforms-simple needs
edge anti-aliasing on most of its area and keeps the general shader.

### Every shader on the SGX530 (2026-11-11 night)

On the phone, 17 of the 51 ES 2.0 shader variants failed at first, which
the PC under Mesa had hidden (it has 32 varying vectors and accepts an
integer `min()`). All 51 now compile and link on the SGX530 (Gecko patches
0179–0186, firefox-n950 patches 29–36). What the SGX530 needs, measured:

- At most 7 rows of varyings as GLSL ES 1.00 packs them, or 8 when every
  varying is a vec4; it packs less tightly than the specification allows.
  `tools/check_varyings.py` applies this to the vertex shaders wrench
  dumps (`WRENCH_SHADER_DUMP`), so a PC finds what the phone would reject.
- No integer `min()`, and loops bounded by a constant (cs_blur).
- A program's two stages may not sample 8 textures between them: the link
  fails with "Uniform variable sGpuBufferF type/precision does not match".
  On ES 2.0 the primitive headers' integer half now sits in the float
  header texture, so brush and text shaders sample one texture fewer.

The varyings came down by passing less: values affine in the position are
computed per vertex and interpolated (a gradient's stop factor, distances
to a border's color and dash lines), what the fragment shader can derive
is derived there (box shadow bounds and corners, a rounded mask's corner
ellipses and planes, the YUV color matrix from bit depth, color space and
format, brush_blend's color matrix from the filter op and amount), border
colors travel as 8-bit pairs, small integers share one float, and the SVG
filter shader drops the clip mask varyings it never used. Reftests under
strict ES 2.0 on the PC are unchanged by all of this (transforms 32/55,
one more than before).

`WR_NO_EDGE_AA` leaves quads without edge anti-aliasing: transforms-simple
then rasterises in 510 ms instead of 1583 (SWGL: 701), with jagged edges
on rotated content only.
