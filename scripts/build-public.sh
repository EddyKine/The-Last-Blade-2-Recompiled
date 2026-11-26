#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 2 ]] || { echo 'Usage: bash scripts/build-public.sh /path/disc.gdi /path/1ST_READ.BIN'; exit 1; }
export PATH="/opt/homebrew/bin:$PATH"
GDI="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$1")"
BIN="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$2")"
[[ -f "$GDI" && -f "$BIN" ]] || exit 1
cd "$HERE"
WORK="$HERE/work"; [[ ! -e "$WORK" ]] || { echo 'Move existing work folder before rebuilding'; exit 1; }; mkdir "$WORK"
URL=$(cat upstream-url.txt); REV=$(cat upstream-commit.txt); PREFIX=$(cat upstream-engine-prefix.txt)
git clone "$URL" "$WORK/upstream"
git -C "$WORK/upstream" checkout --detach "$REV"
git -C "$WORK/upstream" submodule update --init --recursive
ENGINE="$WORK/upstream/$PREFIX"
if [[ -s "$HERE/engine.patch" ]]; then (cd "$WORK/upstream" && git apply --check --directory="$PREFIX" "$HERE/engine.patch" && git apply --directory="$PREFIX" "$HERE/engine.patch"); fi
GAME="$ENGINE/games/thelastblade2"; mkdir -p "$GAME"
cp "$HERE/game/CMakeLists.txt" "$HERE/game/thelastblade2.toml" "$GAME/"
APP="$WORK/The Last Blade 2 Recompiled.app"; C="$APP/Contents"; mkdir -p "$C/MacOS" "$C/Resources/Game/Disc"
python3 - "$GDI" "$BIN" "$GAME" "$C/Resources/Game" <<'PY'
import pathlib as P,shutil,shlex,re,sys
from pathlib import Path
G,B,game,dest=map(Path,sys.argv[1:]); lines=G.read_text().splitlines(); tracks=[]
for line in lines[1:]:
 if not line.strip():continue
 f=shlex.split(line); assert len(f)==6; p=Path(f[4]); assert not p.is_absolute() and '..' not in p.parts
 src=G.parent/p; target=dest/'Disc'/p; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,target); tracks.append(p)
assert len(tracks)==int(lines[0]); shutil.copy2(G,dest/'Disc'/G.name); shutil.copy2(B,dest/'1ST_READ.BIN')
# Config is also used by CMake: game paths resolve relative to its directory.
for folder in (game,dest):
 text=(game/'thelastblade2.toml').read_text(); image=G if folder==game else Path('Disc')/G.name; binary=B if folder==game else Path('1ST_READ.BIN')
 # CMake concatenates its game directory with binary path, so use relative paths.
 if folder==game:
  import os
  image=os.path.relpath(G,game); binary=os.path.relpath(B,game)
 text=re.sub(r'^(image\s*=\s*)"[^"\n]+"',lambda m:m[1]+'"'+str(image)+'"',text,count=1,flags=re.M)
 text=re.sub(r'^(path\s*=\s*)"[^"\n]+"',lambda m:m[1]+'"'+str(binary)+'"',text,count=1,flags=re.M)
 (folder/'thelastblade2.toml').write_text(text)
PY
FLAGS=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DDREAM_DEV_INTERPRETER=OFF -DDREAM_BUILD_TESTS=OFF -DDREAM_WERROR=OFF -DDREAM_RENDERER=ON -DCMAKE_PREFIX_PATH=/opt/homebrew -DDREAM_GLSLC=/opt/homebrew/bin/glslc)
cmake -S "$ENGINE" -B "$WORK/build-original" "${FLAGS[@]}"
cmake --build "$WORK/build-original" --target thelastblade2_boot --parallel 6
cp "$WORK/build-original/games/thelastblade2/thelastblade2_boot" "$C/MacOS/"
(cd "$ENGINE" && shasum -a 256 -c "$HERE/launcher/source.sha256")
cp "$HERE/launcher/present.cpp" "$ENGINE/render/src/vk/present.cpp"
cp "$HERE/launcher/present.frag" "$ENGINE/render/shaders/present.frag"
cmake -S "$ENGINE" -B "$WORK/build-crt" "${FLAGS[@]}"
cmake --build "$WORK/build-crt" --target thelastblade2_boot --parallel 6
cp "$WORK/build-crt/games/thelastblade2/thelastblade2_boot" "$C/MacOS/thelastblade2_crt"
cp "$HERE/launcher/Info.plist" "$C/"
cp "$HERE/launcher/TLB2.icns" "$HERE/launcher/TLB2_Launcher_Hero.png" "$C/Resources/"
xcrun swiftc -O -target arm64-apple-macos13.0 -framework SwiftUI -framework AppKit -framework Foundation -parse-as-library "$HERE/launcher/Launcher.swift" -o "$C/MacOS/TLB2Launcher"
python3 "$HERE/scripts/bundle.py" "$APP"
open "$APP"
