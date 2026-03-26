# SHFT Screen Saver - Release Checklist

Her kod değişikliğinden sonra bu adımları sırayla takip et.

## 1. Build
```bash
cd /Users/hcyildirim/Documents/Development/SHFTScreenSaver
bash build.sh
```

## 2. Local Install & Test
```bash
killall legacyScreenSaver 2>/dev/null; killall ScreenSaverEngine 2>/dev/null; sleep 1
rm -rf ~/Library/Screen\ Savers/SHFTScreenSaver.saver
cp -R build/SHFTScreenSaver.saver ~/Library/Screen\ Savers/
open -a ScreenSaverEngine
```
- RAM monitoring: `ps -o rss= -p $(pgrep -x legacyScreenSaver)`
- 3 dakika sabit kalmalı

## 3. Package (.pkg)
```bash
pkgbuild --root build/SHFTScreenSaver.saver \
  --install-location "/Library/Screen Savers/SHFTScreenSaver.saver" \
  --identifier com.shft.screensaver --version 1.0 \
  build/SHFTScreenSaver.pkg
```

## 4. Update Deploy Script
```bash
PKG_B64=$(base64 -i build/SHFTScreenSaver.pkg)
sed -i '' "3s|^PKG_BASE64=.*|PKG_BASE64='${PKG_B64}'|" simplemdm_deploy.sh
```
- Doğrula: `head -3 simplemdm_deploy.sh` → PKG_BASE64='...' (tek tırnak içinde)

## 5. Git Commit & Push
```bash
git add -A
git commit -m "description"
git push
```
