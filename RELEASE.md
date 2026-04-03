# SHFT Screen Saver - Release Checklist

Her kod değişikliğinden sonra bu adımları sırayla takip et.
Versiyon numarası 3 yerde güncellenmeli: Info.plist, pkgbuild komutu, simplemdm_deploy.sh (PKG_URL + echo).

## 1. Build
```bash
bash build.sh
```

## 2. Memory Leak Test
```bash
bash test_memory.sh --build
```
- Build + install + 5x start/stop döngüsü + 30s steady-state testi
- Tüm testler PASS olmalı

## 3. Package (.pkg)
```bash
pkgbuild --root build/SHFTScreenSaver.saver \
  --install-location "/Library/Screen Savers/SHFTScreenSaver.saver" \
  --identifier com.shft.screensaver --version <VERSIYON> \
  build/SHFTScreenSaver.pkg
```

## 4. Git Commit & Push
```bash
git add -A
git commit -m "v<VERSIYON>: açıklama"
git push
```

## 5. GitHub Release & Deploy Script Güncelle
```bash
gh release create v<VERSIYON> build/SHFTScreenSaver.pkg --title "v<VERSIYON>" --notes "açıklama"
```
- `simplemdm_deploy.sh` içindeki `PKG_URL` ve son satırdaki echo'yu yeni versiyona güncelle
- Tekrar commit & push
