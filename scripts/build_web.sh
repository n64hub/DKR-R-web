#!/usr/bin/env bash
# Builds the web page (build-web/bin/Release/DKR-R.html, .js, .wasm, .data) from a clean US v1.0 ROM, on Linux with
# emsdk active (N64Recomp-browser's README, Using it in a recomp, says what else: naga, spirv-opt, ccache):
#
#   bash scripts/build_web.sh <US v1.0 ROM> [--prepare]
#   bash scripts/build_web.sh --patches
#
# 1. The pinned dependencies (dependencies.lock.json) the page needs, fetched by scripts/bootstrap_dependencies.py:
#    not libdatachannel, SDL3 or SDL2 (the page has no online play, no input worker, and Emscripten's own SDL2).
# 2. DKR-R's own patches to them (scripts/apply_dependency_patches.py), then N64Recomp-browser's web patches on top
#    (lib/N64Recomp-browser/patches/apply.cmake, project by project), but for the files where the two make the same
#    change their own way (below), merged from the N64Recomp-browser commit web_merged_from names, with what the web
#    has changed in them since merged in (apply.cmake --since). Patched from clean whenever lib/N64Recomp-browser or
#    patches/ moved since the last time, which build/web-patched records: apply.cmake can't take a checkout from one
#    version of its patches to another.
# 3. N64Recomp, built natively from the patched checkout: the page needs the code the web-patched one writes.
# 4. The decomp's ELF of US v1.0 (extern/dkr-decomp, IDO through ido-recomp, its own make setup), in build/decomp/v77,
#    and the recompiled code from it by DKR-R's Patch Pipeline policy (as scripts/Prepare-DKR-Runtime-macOS.sh does),
#    in build/generated/v77. The page has US v1.0 only: Rev A would be a second copy of the game's code in the wasm.
# 5. The page, with emcmake, in build-web. --prepare stops before it.
#
# --patches needs no ROM: steps 1 and 2 without the decomp, then the page configured with no recompiled code in
# build-web-patches, which stages DKR-R's own configure-time patches (runtime-recomp/cmake/StagedPatch.cmake, every
# stage a page has) over the patched checkouts. It fails where any layer stops applying. N64Recomp-browser's CI runs it
# with its own checkout as lib/N64Recomp-browser, so a change there that breaks this stack fails on its PR.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 1 ]] || { echo "usage: $0 <US v1.0 ROM> [--prepare] | --patches" >&2; exit 2; }
patches_only=0 prepare_only=0
if [[ "$1" == --patches ]]; then
    patches_only=1
else
    rom="$(realpath "$1")"
    [[ "${2:-}" == --prepare ]] && prepare_only=1
fi
cd "$root"
jobs="$(nproc)"
browser=lib/N64Recomp-browser
[[ -f $browser/patches/apply.cmake ]] || git submodule update --init $browser

step() { printf '\n== %s\n' "$*"; }

# --- 1. Dependencies ---
step "Dependencies"
deps="n64-modern-runtime rt64 gekkonet monocypher mbedtls"
[[ $patches_only == 1 ]] || deps="dkr-decomp $deps"
python3 - $deps <<'PY' | while IFS=$'\t' read -r name destination commit; do
import json, sys
wanted = set(sys.argv[1:])
for d in json.load(open("dependencies.lock.json"))["dependencies"]:
    if d["name"] in wanted:
        print(d["name"], d["destination"], d["commit"], sep="\t")
PY
    if [[ -e "$destination/.git" && "$(git -C "$destination" rev-parse HEAD)" == "$commit" ]]; then
        echo "[OK] $name"
    else
        python3 scripts/bootstrap_dependencies.py --only "$name" > /dev/null
    fi
done
[[ $patches_only == 1 ]] || git -C extern/dkr-decomp submodule update -q --init --recursive

# --- 2. Patches ---
step "Patches"
# <name> <checkout> [files left to patches/web/<name>.patch] [- files left to DKR-R's own patch alone]:
# N64Recomp-browser's patches by project. Where DKR-R's patch and the web's change the same lines, the web's change to
# that file is left out here and made by patches/web/<name>.patch instead, written on top of DKR-R's and merged from
# N64Recomp-browser's web_merged_from. What the web has changed in those files since is merged in after it
# (apply.cmake --since), so a later web change reaches the page by itself; one that meets DKR-R's lines stops the
# build, the file left with conflict markers: then merge it into patches/web/<name>.patch by hand and move
# web_merged_from to the commit merged from.
#   rt64: game_frame.cpp and workload_queue.cpp take both; shader_library.cpp, rt64_raster_params.h, RasterPS.hlsl and
#   TextureSampler.hlsli keep DKR-R's settings (mip LOD bias, generated mipmaps) on the CPU side, which the page's
#   shaders don't read: the page has neither (no launcher to set them, and generated mipmaps stay off on WebGPU).
#   N64ModernRuntime: DKR-R's runtime is from before upstream's deprecated mods, which the web patch's context has, so
#   mods.hpp, mods.cpp and recomp.cpp take DKR-R's with the web's register_precompiled_mod. mesgqueue.cpp takes DKR-R's
#   alone, so nothing the web changes there later is merged in: the web's change there is the list a blocked external message waits in (ULTRAMODERN_HOLD_BLOCKED_MESSAGES), so
#   the idle thread doesn't spin on it, and DKR-R does the same its own way (patches/performance/
#   runtime-deferred-events.patch, the DeferredEventQueue's blocked list, moved back when a receive frees its queue).
#   librecomp/src/config.cpp isn't in DKR-R's runtime, so the web's change there (only the settings a player changed
#   are saved) has nothing to patch.
#   That patch is staged at configure time over this file (runtime-recomp/cmake/PerformancePatches.cmake), so it has to
#   find DKR-R's lines here.
web_merged_from=4c49375fb7a614dbcd8ed6fb4f510377db02b6fd # its PR 325
rt64_shared="src/hle/rt64_game_frame.cpp src/hle/rt64_workload_queue.cpp src/render/rt64_shader_library.cpp
src/shaders/RasterPS.hlsl src/shaders/TextureSampler.hlsli src/shared/rt64_raster_params.h"
web_patches="rt64 extern/rt64 $(echo $rt64_shared)
plume extern/rt64/src/contrib/plume
hlslpp extern/rt64/src/contrib/hlslpp
N64ModernRuntime extern/n64-modern-runtime librecomp/include/librecomp/mods.hpp librecomp/src/mods.cpp librecomp/src/recomp.cpp - ultramodern/src/mesgqueue.cpp librecomp/src/config.cpp
N64Recomp extern/n64-modern-runtime/N64Recomp"
stamp="$(git -C $browser rev-parse HEAD) $( (cat patches/manifest.json $(ls patches/web/*.patch 2> /dev/null); echo "$web_merged_from $web_patches") | sha1sum | cut -c1-40)"
if [[ "$(cat build/web-patched 2> /dev/null)" != "$stamp" ]]; then
    for s in extern/rt64 extern/n64-modern-runtime; do
        git -C $s submodule foreach --recursive -q 'git reset -q --hard && git clean -fdq'
        git -C $s reset -q --hard && git -C $s clean -fdq
    done
    python3 scripts/apply_dependency_patches.py
    while read -r name checkout skip; do
        merged="${skip%%- *}"
        cmake -P $browser/patches/apply.cmake "$name" "$checkout" ${skip/- /}
        [[ ! -f patches/web/$name.patch ]] || git -C "$checkout" apply --whitespace=nowarn "$root/patches/web/$name.patch"
        [[ -z "${merged// /}" ]] ||
            cmake -P $browser/patches/apply.cmake "$name" "$checkout" --since $web_merged_from $merged
    done <<< "$web_patches"
    mkdir -p build && echo "$stamp" > build/web-patched
fi
if [[ $patches_only == 1 ]]; then
    rm -rf build-web-patches
    emcmake cmake -S runtime-recomp -B build-web-patches -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DDKR_RUNTIME_BUILD_GENERATED=OFF -DRT64_NAGA_EXECUTABLE="$(command -v naga)"
    exit 0
fi

# --- 3. N64Recomp ---
step "N64Recomp"
tools=build/web-tools
[[ -f $tools/n64recomp/build.ninja ]] || cmake -S extern/n64-modern-runtime/N64Recomp -B $tools/n64recomp -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ > /dev/null
ninja -C $tools/n64recomp N64RecompCLI > /dev/null
recompiler="$root/$tools/n64recomp/N64Recomp"

# --- 4. The decomp's ELF and the recompiled code ---
step "US v1.0 ELF"
tree=build/decomp/v77
elf="$tree/build/dkr.us.v77.elf"
built_rom="$tree/build/dkr.us.v77.z64"
mkdir -p $tree/baseroms
python3 - "$rom" $tree/baseroms/baserom.us.v77.z64 <<'PY'
import hashlib, pathlib, sys
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = bytearray(source.read_bytes())
magic = bytes(data[:4]).hex()
if magic == "37804012":
    data[0::2], data[1::2] = data[1::2], data[0::2]
elif magic == "40123780":
    for i in range(0, len(data) - 3, 4):
        data[i:i + 4] = data[i:i + 4][::-1]
if hashlib.sha1(data).hexdigest() != "0cb115d8716dbbc2922fda38e533b9fe63bb9670":
    raise SystemExit(f"{source}: not Diddy Kong Racing US v1.0 (SHA-1 {hashlib.sha1(data).hexdigest()})")
if not target.exists() or target.read_bytes() != data:
    target.write_bytes(data)
PY
decomp_commit="$(git -C extern/dkr-decomp rev-parse HEAD)"
if [[ "$(cat $tree/.dkr-elf-stamp 2> /dev/null)" != "$decomp_commit" || ! -f "$elf" ]]; then
    rsync -a --delete --exclude /.git --exclude /build --exclude /asm --exclude /assets --exclude /baseroms \
        --exclude /.venv --exclude /.dkr-elf-stamp extern/dkr-decomp/ $tree/
    [[ -x $tree/.venv/bin/python3 ]] || (cd $tree && make setup)
    (cd $tree && make VERSION=v77 extract && make VERSION=v77 -j"$jobs")
    echo "$decomp_commit" > $tree/.dkr-elf-stamp
fi

step "US v1.0 recompiled code"
work=build/generated/v77
inputs="$(cat runtime-recomp/*.v77.*.json scripts/*.py "$elf" "$recompiler" | sha1sum | cut -c1-40)"
if [[ "$(cat $work/.dkr-payload-stamp 2> /dev/null)" != "$inputs" || ! -f $work/RecompiledFuncs/funcs.h ]]; then
    rm -rf $work && mkdir -p $work/RecompiledFuncs
    python3 scripts/compose_legacy_mod_policy.py \
        --policy runtime-recomp/dkr.us.v77.recomp-policy.json \
        --fragment runtime-recomp/legacy-mods.v77.recomp-fragment.json \
        --track-menu runtime-recomp/legacy-track-menu.v77.recomp-fragment.json \
        --characters runtime-recomp/legacy-characters.v77.recomp-fragment.json \
        --character-menu runtime-recomp/legacy-character-menu.v77.recomp-fragment.json \
        --scene-runtime --elf "$elf" --output $work/policy.json
    python3 scripts/generate_recomp_config.py --policy $work/policy.json --elf "$elf" --rom "$built_rom" \
        --output-functions $work/RecompiledFuncs --entrypoint 0x80065D40 --output $work/dkr.us.v77.toml
    (cd runtime-recomp && "$recompiler" "$root/$work/dkr.us.v77.toml") > $work/n64recomp.log 2>&1 ||
        { tail -20 $work/n64recomp.log; exit 1; }
    echo "$inputs" > $work/.dkr-payload-stamp
fi
[[ $prepare_only == 1 ]] && exit 0

# --- 5. The page ---
step "Page"
embuilder build sdl2-mt freetype-legacysjlj > /dev/null
# runtime-recomp/CMakeLists.txt turns off what a page can't have when it configures with Emscripten. Custom Magic Codes
# stage their dispatch from the config the recompiled code came from (DKR_CODE_POLICY_V77, CustomMagicCodes.cmake), so a
# build-web configured before they came (its cache without this DKR_CODE_POLICY_V77, or with the default a failed
# regeneration left) is configured again to get it.
[[ -f build-web/build.ninja ]] &&
    grep -qxF "DKR_CODE_POLICY_V77:FILEPATH=$root/$work/dkr.us.v77.toml" build-web/CMakeCache.txt ||
    emcmake cmake -S runtime-recomp -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DDKR_RELEASE_VERSION="$(cat VERSION)" -DDKR_RUNTIME_BUILD_GENERATED=ON \
    -DDKR_GENERATED_SOURCE_V77="$root/$work/RecompiledFuncs" -DDKR_CODE_POLICY_V77="$root/$work/dkr.us.v77.toml" \
    -DRT64_NAGA_EXECUTABLE="$(command -v naga)"
ninja -C build-web DKRPortGame
