# GLES Cubemap-Array IBL Fallback Plan (Option A)

**Date:** 2026-05-30  
**Branch:** `glad-gles` → modawan/reone  
**Issue:** #162 (GLES migration), #111 (cubemap array disable rationale)

## Problem

PBR IBL stores derived environment probes for up to 16 scene cubemaps. The fast path uses `GL_TEXTURE_CUBE_MAP_ARRAY` / `samplerCubeArray`, which requires `OES_texture_cube_map_array` (ES 3.1+) or ES 3.2 core — not ES 3.0 core and not WebGL 2.0.

| API | Cubemap array |
|-----|----------------|
| OpenGL ES 3.0 core | No |
| `OES_texture_cube_map_array` | Yes (requires ES 3.1 + ESSL 3.10 driver support) |
| OpenGL ES 3.2 core | Yes (mandatory) |
| WebGL 2.0 | No (ES 3.0 baseline; no ratified extension in Khronos registry) |
| WebGPU | Yes (`texture_cube_array`) — Tier 2 |

## Decision (Option A)

**Dual-backend IBL** with runtime probe:

1. **Fast path:** When `GLAD_GL_OES_texture_cube_map_array` is loaded, keep `TextureType::CubeMapArray` + `samplerCubeArray` in `f_pbr_combine.glsl` (`REONE_CUBE_MAP_ARRAY`), 16 layers.
2. **Fallback path (Option A):** Store each derived probe as a real `GL_TEXTURE_CUBE_MAP` (irradiance + prefilter pair). Sample in `f_pbr_combine.glsl` via `switch(envMapDerivedLayer)` over `samplerCube` uniforms — **not** `GL_TEXTURE_2D_ARRAY`.
3. **Layer cap on fallback:** The deferred combine pass already binds G-buffer, shadows, and BRDF samplers. ES 3.0 fragment shaders typically expose ~16 texture units. Fallback caps active derived layers at **4** (`REONE_ENVMAP_CUBEMAP_LAYERS`) so IBL uses 8 cubemap samplers without exceeding the budget. Layer index wraps at 4 on this path.
4. **Rejected:** `GL_TEXTURE_2D_ARRAY` pseudo-cubemap packing (visual quality regression vs real cubemaps).

Geometry shaders remain replaced by multi-pass shadow rendering (`uShadowLayer` + FBO layer loop) — already on branch.

## Files

| File | Change |
|------|--------|
| `include/reone/graphics/types.h` | Cubemap-pool texture unit constants |
| `include/reone/graphics/pbrtextures.h` | Cubemap pool storage + `bindEnvMapDerived()` |
| `src/libs/graphics/pbrtextures.cpp` | Branch init/bake; per-cubemap FBO attach |
| `glsl/i_envmap_cubemap_pool.glsl` | Switch-based `samplerCube` sampling |
| `glsl/f_pbr_combine.glsl` | `#ifdef REONE_CUBE_MAP_ARRAY` vs cubemap pool |
| `src/libs/resource/provider/shaders.cpp` | `REONE_ENVMAP_CUBEMAP_LAYERS`, pool uniforms |
| `src/libs/scene/render/pipeline/pbr.cpp` | Call `bindEnvMapDerived()` |
| `glsl/i_envmap_sample.glsl` | **Delete** (2D-array path removed) |

## Test scenarios

1. Native GLES build (`build-gles/`): engine links and reaches menu without GL errors.
2. `cubeMapArraySupported()==false`: four cubemap pairs init; combine compiles without `samplerCubeArray` or `sampler2DArray` IBL samplers.
3. When OES present: 16-layer cube map array path unchanged.
4. Irradiance/prefilter bake writes all six faces per cubemap layer.

## Out of scope (Tier 2)

- WebGPU renderer backend
- Expanding fallback beyond 4 layers without multi-pass combine or bindless textures
- Rebasing unrelated branch commits

## Status (2026-06-03)

### Landed

- Option A cubemap pool (separate `GL_TEXTURE_CUBE_MAP` pairs, 4-layer fallback cap)
- OES cube map array fast path retained when `GLAD_GL_OES_texture_cube_map_array` loads
- Shadow geometry-shader workaround (`uShadowLayer` multi-pass)
- Native GLES build verified (`build-gles/` → `engine` links)
- Main menu + cursor rendering fixed on Mesa (BGR/BGRA upload + GLSL compile fixes)
- PR opened: https://github.com/modawan/reone/pull/163
- GLES CI workflow added (`.github/workflows/build-gles.yml`)

### Partial / uncertain

- In-game IBL visual check (skybox/reflections on fallback path in a module) not run yet
- OES 16-layer fast path not validated on hardware with the extension
- Fork PR workflow may require manual approval on modawan before checks run
- WebGL/WASM combine-shader compile not exercised

### Recommended next steps

1. Confirm `Build GLES engine` CI is green on PR #163
2. Run `./tools/gles/smoke_menu_validate.sh` after CI passes (already validated locally)
3. Optional: `./tools/gles/smoke_warp_validate.sh` for in-module IBL spot-check
4. WASM vertical slice when `build-web/` profile is ready
