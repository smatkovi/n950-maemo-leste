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
