Release a new version of SHFTScreenSaver. The user provides the version number as $ARGUMENTS (e.g., `/release 3.5`).

If no version argument is provided, ask the user for the version number.

Steps:
1. Update version in 3 places:
   - `Info.plist`: CFBundleShortVersionString → `$ARGUMENTS`, CFBundleVersion → major number
   - `simplemdm_deploy.sh`: PKG_URL version tag → `v$ARGUMENTS`, echo line version → `v$ARGUMENTS`

2. Build: `bash build.sh`

3. Memory test: `bash test_memory.sh --build` — all 4 tests must PASS. If any test fails, STOP and report.

4. Package: `pkgbuild --root build/SHFTScreenSaver.saver --install-location "/Library/Screen Savers/SHFTScreenSaver.saver" --identifier com.shft.screensaver --version $ARGUMENTS build/SHFTScreenSaver.pkg`

5. Git commit & push:
   - Stage all changed files (do NOT stage build/ directory)
   - Commit with message: `v$ARGUMENTS: <summary of changes since last release>`
   - Push to origin

6. GitHub Release: `gh release create v$ARGUMENTS build/SHFTScreenSaver.pkg --title "v$ARGUMENTS" --notes "<release notes>"`

7. Report the release URL to the user. MDM deploy is ready via `simplemdm_deploy.sh`.