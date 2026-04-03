# SHFTScreenSaver

macOS screen saver for SHFT. Distributed to employees via SimpleMDM.

## Architecture
- Single file: `SHFTScreenSaverView.m` (Objective-C, ARC, ~300 lines)
- Built with `clang -bundle`, no Xcode project
- All resources are static (shared across instances): background image, cell grid, blink color
- CALayers reused across start/stop cycles — no per-cycle allocation
- `_exit(0)` at 80MB RSS as safety net for Apple's legacyScreenSaver memory leak

## Build & Test
- `bash build.sh` — compile to `build/SHFTScreenSaver.saver`
- `bash test_memory.sh --build` — build + install + memory leak test (5x cycle + 30s steady)

## Deploy
- `simplemdm_deploy.sh` is pushed via MDM to all machines
- Downloads `.pkg` from GitHub Releases, installs, sets as active screen saver
- Sets idle time to 300s (5 min)

## Slash Commands
- `/test` — build + memory leak test
- `/release <version>` — full release pipeline (build, test, pkg, commit, push, gh release)
