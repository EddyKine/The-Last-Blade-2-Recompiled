# The Last Blade 2 Recompiled — macOS ARM64

Unofficial Dreamcast static recompilation project, maintained by EddyKine. Original game by SNK. No affiliation with SNK or Sega.

The local v0.26 edition was validated on an Apple M4. v0.27 adds a proposed relocation of shared libraries and a reproducible source-build workflow; local packaging and ad-hoc signing have been completed successfully on Apple M4; a clean-machine build remains unverified. The original motor and CRT presets remain separate. This repository is source-only: no game images, BIOS, extracted game executable, translated game code or compiled game binaries. Supply your own lawful Japanese Final Edition dump (T3107M) and its extracted 1ST_READ.BIN. Other revisions are untested.

## Build (Apple Silicon)

1. Install Xcode Command Line Tools (`xcode-select --install`) and Homebrew from https://brew.sh/.
2. Run `bash scripts/install-build-deps.sh`. This installs CMake, Python, SDL3, Vulkan headers and loader, MoltenVK and shaderc (glslc). Versions are not pinned; upstream commit is pinned in the metadata files generated at export.
3. Extract 1ST_READ.BIN from your own disc using a suitable Dreamcast disc extractor. Keep the GDI and its tracks together.
4. Run `bash scripts/build-public.sh '/path/to/game.gdi' '/path/to/1ST_READ.BIN'`.
5. Open the app under `work/`. If MoltenVK discovery fails, set `TLB2_ICD_JSON` to the actual installed ICD manifest and retry from a fresh work directory.

The build checks out the upstream revision, applies tracked engine modifications, translates the user-supplied binary, builds original and CRT engines, compiles the SwiftUI launcher, and attempts to relocate runtime libraries. Xcode tools are needed to build, not necessarily to run the relocated app. The target deployment of the motors depends on the installed SDK and dylibs; macOS 13 is the launcher target, not a guarantee for the whole app. Ad-hoc signing is not notarization. A clean Mac test is required. Do not bypass Gatekeeper globally.

## Controls

F1 or controller Select: bindings; Esc: quit. CRT Original/Soft/Medium and intensity are selectable. Avoid F10 FPS overlay if performance matters (readback). The artwork is an original generated launcher illustration, not official SNK art.

## Attribution and licensing

See upstream-url.txt, upstream-commit.txt and the upstream license copied during export. Preserve all upstream notices and comply with its terms. Do not publish the patch if upstream licensing does not permit it; audit the diff and dependencies first. No permission is granted for SNK game data. The generated local application containing the user's game must not be committed or uploaded. Third-party dynamic libraries require their own license notices if redistributed. This source repository installs dependencies from their upstream package sources rather than redistributing their binaries.

## v0.28.4 corrections

Adds SH-4 discovery entries `0x0C133056` (fresh VMU startup) and `0x0C077590` (Options menu). The original v0.28.3 motor was tested on Apple M4 in Options, Training, Arcade, Versus and after restarting with saved preferences. Both motors use a dedicated persistent VMU. Clean-machine builds and cross-Mac portability remain unverified.
