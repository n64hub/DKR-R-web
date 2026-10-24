# The web page

This fork's `main` branch also builds with [Emscripten](https://emscripten.org) into a page, `DKR-R.html`, that draws
through WebGPU: **https://n64hub.com/diddy-kong-racing/**. The game's code is recompiled from the decomp's ELF of US
v1.0 by DKR-R's own pipeline, and [N64Recomp-browser](https://github.com/n64hub/N64Recomp-browser)
(`lib/N64Recomp-browser`) patches RT64, plume, hlslpp, N64ModernRuntime and N64Recomp with the web support and makes the
game a page. Everything the page needs is behind `__EMSCRIPTEN__` or `if(EMSCRIPTEN)`, so the desktop builds are
unchanged.

## What the page leaves out

- **DKR-R's launcher.** It draws through ImGui on an SDL renderer, which a page hasn't got. The page has a launcher
  of its own (`runtime-recomp/src/game/web_page.cpp`): Load ROM, which opens the browser's file picker, and Start
  Game once a ROM is kept. The ROM stays in the browser (IndexedDB, through N64Recomp-browser's `persistent_home.js`).
  The overlay is there, as on the desktop: Escape, F1 or a controller's Back (the MENU of the on-screen controller
  on a phone) opens it, drawn through RT64's inspector, which on a page draws ImGui through plume (rt64-web), with
  the font atlas its one texture, so CRT filters are off (`runtime_crt_overlay.cpp`). Its sidebar leaves out DKR-R
  ONLINE, RESTART and EXIT (`runtime_ui.cpp`): online play is left out (below), and the browser reloads or closes a
  page. A first run starts in DKR-R's Modern profile (`runtime_ui.cpp`), the one that interpolates, where Accurate,
  the desktop's first profile, holds RT64 at Original and 30, and widescreen, Modern's own default: a first run's
  settings would give it the runtime's starting 4:3. What the player picks in the overlay's Graphics page is kept.
  Modern's Match display is RT64's Display on a page (`rt64_renderer.cpp`), since SDL's Emscripten port reports no
  refresh rate, so RT64 interpolates the game's 30 frames a second to the display's rate. Original water, no
  generated mipmaps.
- **Online play, mods and custom tracks.** Online play needs WebRTC's transport (`DKR_NETPLAY_WEBRTC` off), and mods
  are imported by a worker process, which a page can't start (`legacy_mod_process.cpp`). N64ModernRuntime's live
  recompiler (sljit) emits machine code, so the runtime's mods are off on every page too.
- **DKR-R's updater.** A page is updated by the site that serves it, so it configures no update service
  (`runtime_ui.cpp`), and its `https_get` only refuses (`update_http.cpp`): no curl, no helper process, no install lock.
- **Enhanced water**, whose shaders are Vulkan's (`DKR_ENHANCED_WATER` off), the SDL3 input host (a process of its
  own: the page reads keys and gamepads through Emscripten's SDL2), the tests, and Rev A: the page holds US v1.0's code
  alone, since Rev A's would be a second copy of the game in the wasm.

## How it is built

`scripts/build_web.sh <US v1.0 ROM>` does all of it on Linux with emsdk active, naga
(`cargo install naga-cli`), spirv-opt and, for faster rebuilds, ccache on `PATH`. Its header says each step:

1. The pinned dependencies the page needs, fetched by `scripts/bootstrap_dependencies.py`.
2. DKR-R's own patches to them (`scripts/apply_dependency_patches.py`), then N64Recomp-browser's web patches on top
   (`lib/N64Recomp-browser/patches/apply.cmake`, project by project). Where the two change the same lines,
   `apply.cmake` leaves those files out and `patches/web/<project>.patch` makes the web's change on top of DKR-R's,
   merged from the N64Recomp-browser commit the script's `web_merged_from` names, and `apply.cmake --since` merges in
   what the web has changed in them since (a change that meets DKR-R's lines stops the build, for a merge by hand);
   where a stage of DKR-R's own (`runtime-recomp/cmake/StagedPatch.cmake`) meets the web's lines,
   `patches/web/stage/<stage>.patch` is that stage written on top of them.
3. N64Recomp built natively from the patched checkout: its `funcs.h` declares every function the recompiled code
   calls, which a WebAssembly link needs.
4. The decomp's ELF of US v1.0 and the recompiled code from it.
5. The page, with `emcmake cmake -S runtime-recomp -B build-web`, then `ninja -C build-web DKRPortGame`.

`scripts/build_web.sh --patches` needs no ROM: steps 1 and 2, then a configure with no recompiled code, which stages
every patch of DKR-R's a page has. N64Recomp-browser's CI runs it with its own checkout, so a change there that stops
applying over DKR-R's patches fails on its pull request.

`build-web/bin/Release` then holds `DKR-R.html`, `.js`, `.wasm`, `.data` and `coi_serviceworker.js`. Serve that folder
with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`, or as is on a host
that can't set headers, where `coi_serviceworker.js` sets them after one reload. It needs a browser with WebGPU (Chrome
or Edge 113 and up, or Firefox 141 and up). On the page the keyboard is the desktop's (WASD the stick, Space A, Shift
B, Z, Enter Start, Q and E the shoulders, IJKL the C buttons).

## What the page does differently

- **Sound** goes to N64Recomp-browser's `audio_output.h`, an AudioWorklet on the browser's audio thread reading a ring
  in the program's memory, through an SDL audio stream from the game's rate to the page's: Emscripten's SDL2 plays its
  queue from the page's thread, where WebGPU's work runs, and breaks up whenever that thread is busy
  (`runtime_platform.cpp`).
- **Input** is read whatever SDL's window focus says: SDL's focus on a page follows the window's focus events, which
  a page opened behind another window never gets, though its tab gets keys.
- **Render to RAM is off** (`rt64_renderer.cpp`): in Chrome RT64's readback of every frame holds each display list
  for the GPU process. The game's CPU reads a frame only to hold the last one on screen while a level unloads, which
  doesn't need it (`rt64_renderer.cpp` says why).
- **The heap is the frontend's fixed 1536 MB**, without memory growth, which with threads slows the page's JavaScript:
  with growth on, it never grew past that through the shader list's recording and 27 maps in one visit.

## Prebuilt shaders

The page builds the shaders the game uses before it draws with them, so it never draws with RT64's slow ubershader in
the middle of a race: `web/rt64_shaders.txt` lists them in sections (its header says what each holds), and the build
specializes each one (`RT64_PREBUILT_SHADER_LIST` in `runtime-recomp/CMakeLists.txt`). In Chrome the whole list is
built in the background, and the game waits only when a frame wants 4 or more of a section's
shaders that aren't built yet, under a small "Preparing graphics" indicator in a corner. Firefox builds a pipeline in
line with the rest of its GPU work, so there those above the first section (the logos and the title) are built before
the game starts, and a section when the game first draws it, the game waiting. A shader the list misses is built
behind the game, and the page remembers it and builds it with the rest on the next visit.

The list holds 113 descriptions in 12 sections (the 107 first recorded made 134 different shader stages, 1.5 MB of
WGSL): the logos and the title first, then the menus, Timber's Island, each of the five worlds (its hub, races, battle,
boss race and trophy race; Wizpig's also the party and the two endings), the trophy podium and a race's results. A
world's section holds every description its maps draw, those another world shares too; each is built once.

`web/record_shaders.sh` records the list (its header says how): N64Recomp-browser's recorder drives the page in
headless Chrome through `web/shader_plan.json`, a page load per map, in which `web/shader_survey.js` takes the game to
the map through its own teleport and drives the player's kart toward each checkpoint. The game's AI can't drive the
player's kart instead: DKR-R's display list check then rejects every frame. A recording takes about 50 minutes.

`web/play_plan.json` is the page's regular play, 2-3 minutes with every timeout counted, which N64Recomp-browser's
`tools/play_page.mjs` plays to measure the page: the menus to a new Adventure and Timber's Island, then a race in Dino Domain by the
survey's teleport. `web/play_plan_extended.json`, at most 5 minutes, goes on to races in Snowflake Mountain and Sherbet
Island, for when a longer play is needed, and the shaders it misses go into the list. Each plan's header
says what it plays.

## Played

How the page plays in Chrome and Firefox, run by run, is recorded in N64Recomp-browser's
[plays.jsonl](https://github.com/n64hub/N64Recomp-browser/blob/main/plays.jsonl) and its
[games table](https://github.com/n64hub/N64Recomp-browser#games).
