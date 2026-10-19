#!/bin/bash
# Build the all-in-one Samsung SCX-3405 installer (printing + scanning).
#
#   dist/SCX3405-Full-Installer.dmg
#     └── Install SCX3405.pkg   +   Read Me First.txt
#
# The scanner half is a self-contained, relocatable copy of Homebrew's
# sane-backends (scanimage + libsane + the xerox_mfp backend + its leaf
# dependencies), so target Macs need no Homebrew at all.
#
# Requirements: Xcode command line tools, Python 3, and — only as the source
# of the SANE files — Homebrew with sane-backends installed:
#     brew install sane-backends
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
DIST="$PROJ/dist"
STAGE="$HERE/payload"
SPLIX_OPT="$PROJ/third_party/splix/optimized"

# The SANE binaries are patched with this absolute path at build time, so it
# must be the real install location (and shorter than the Homebrew original).
INSTALL_SANE=/Library/Printers/SCX3405/sane
SANEROOT="$STAGE$INSTALL_SANE"

PKGID=com.samsung-scx3405.pkg
APP="$STAGE/Applications/Scan SCX3405.app"

# Version: from an explicit VERSION, else the nearest git tag ("v1.2.3" -> 1.2.3).
VERSION="${VERSION:-$(git -C "$PROJ" describe --tags --abbrev=0 2>/dev/null || true)}"
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || VERSION=1.0

echo "== 0. clean  (version $VERSION)"
rm -rf "$DIST" "$STAGE"
mkdir -p "$DIST"

echo "== 1. print filters"
if [ ! -x "$SPLIX_OPT/rastertoqpdl" ] || [ ! -x "$SPLIX_OPT/pstoqpdl" ]; then
  echo "   filters missing, building them first…"
  "$PROJ/build-filters.sh"
fi

echo "== 2. print payload (filters + PPD)"
mkdir -p "$STAGE/Library/Printers/Splix" "$STAGE/Library/Printers/SCX3405"
install -m 755 "$SPLIX_OPT/rastertoqpdl" "$STAGE/Library/Printers/Splix/rastertoqpdl"
install -m 755 "$SPLIX_OPT/pstoqpdl"     "$STAGE/Library/Printers/Splix/pstoqpdl"
install -m 644 "$PROJ/install/SCX-3400 (SpliX).ppd" \
               "$STAGE/Library/Printers/SCX3405/SCX-3400 (SpliX).ppd"

echo "== 3. scanner payload (relocatable SANE)"
SB="$(brew --prefix sane-backends 2>/dev/null || true)"
[ -n "$SB" ] || { echo "error: sane-backends not found; run: brew install sane-backends" >&2; exit 1; }
mkdir -p "$SANEROOT/bin" "$SANEROOT/lib/sane" "$SANEROOT/etc/sane.d"
cp "$SB/bin/scanimage"                   "$SANEROOT/bin/"
cp "$SB/lib/libsane.1.dylib"             "$SANEROOT/lib/"
cp "$SB/lib/sane/libsane-xerox_mfp.1.so" "$SANEROOT/lib/sane/"
chmod -R u+w "$SANEROOT"

BINS=("$SANEROOT/bin/scanimage" "$SANEROOT/lib/libsane.1.dylib" \
      "$SANEROOT/lib/sane/libsane-xerox_mfp.1.so")

# Copy every non-system dylib the three binaries reference, by the exact paths
# in their load commands — robust to Homebrew version/soname changes. The two
# sane libraries are already in place, so skip them by name.
echo "== 3a. copy dependencies"
for dep in $(for bin in "${BINS[@]}"; do otool -L "$bin" | awk 'NR>1 {print $1}'; done \
             | grep '^/opt/homebrew' \
             | grep -Ev '/(libsane\.1\.dylib|libsane-xerox_mfp\.1\.so)$' \
             | sort -u || true); do
  echo "   $(basename "$dep")"
  cp -f "$dep" "$SANEROOT/lib/"     # -f: Homebrew ships dylibs read-only
done
chmod -R u+w "$SANEROOT"

echo "== 3b. rewrite dylib install names"
rewrite () { # $1 = binary, $2 = @prefix for its Homebrew deps
  local bin="$1" pre="$2" dep
  for dep in $(otool -L "$bin" | awk 'NR>1 {print $1}' | grep '^/opt/homebrew' || true); do
    install_name_tool -change "$dep" "$pre/$(basename "$dep")" "$bin"
  done
}
rewrite "$SANEROOT/bin/scanimage"                   '@executable_path/../lib'
rewrite "$SANEROOT/lib/libsane.1.dylib"             '@loader_path'
rewrite "$SANEROOT/lib/sane/libsane-xerox_mfp.1.so" '@loader_path/..'

echo "== 3c. patch compiled-in SANE paths"
OLD_LIBDIR="$(strings "$SB/lib/libsane.1.dylib" | grep -E '^/.*/lib/sane$' | head -1)"
OLD_CONFDIR="$(strings "$SB/lib/libsane.1.dylib" | grep -E '^\.:/.*/etc/sane\.d$' | head -1)"
[ -n "$OLD_LIBDIR" ]  || { echo "could not find compiled-in lib dir" >&2; exit 1; }
[ -n "$OLD_CONFDIR" ] || { echo "could not find compiled-in config dir" >&2; exit 1; }
echo "  old libdir : $OLD_LIBDIR"
echo "  old confdir: $OLD_CONFDIR"
python3 "$HERE/patchpath.py" "$SANEROOT/lib/libsane.1.dylib" "$OLD_LIBDIR" "$INSTALL_SANE/lib/sane"
python3 "$HERE/patchpath.py" "$SANEROOT/lib/libsane.1.dylib" "$OLD_CONFDIR" ".:$INSTALL_SANE/etc/sane.d"
python3 "$HERE/patchpath.py" "$SANEROOT/lib/sane/libsane-xerox_mfp.1.so" "$OLD_CONFDIR" ".:$INSTALL_SANE/etc/sane.d"

echo "== 3d. SANE config + ad-hoc signatures"
cp "$HERE/sane/dll.conf"       "$SANEROOT/etc/sane.d/dll.conf"
cp "$HERE/sane/xerox_mfp.conf" "$SANEROOT/etc/sane.d/xerox_mfp.conf"

# Neutral, self-describing identities for the copied libraries.
for f in "$SANEROOT"/lib/*.dylib "$SANEROOT/lib/sane/"*.so; do
  [ -f "$f" ] && install_name_tool -id "@rpath/$(basename "$f")" "$f"
done

# Apple Silicon refuses code whose signature was invalidated by install_name_tool.
while IFS= read -r -d '' f; do
  codesign --force --sign - "$f" >/dev/null 2>&1 || true
done < <(find "$SANEROOT" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0)

echo "== 4. CLI helper + uninstaller"
mkdir -p "$STAGE/usr/local/bin"
install -m 755 "$HERE/bin/scan-photo"       "$STAGE/usr/local/bin/scan-photo"
install -m 755 "$HERE/uninstall-scx3405.sh" "$STAGE/Library/Printers/SCX3405/uninstall-scx3405.sh"

echo "== 5. scan app"
"$HERE/scanapp/build-app.sh" "$APP"

echo "== 6. verify: no Homebrew references remain"
fail=0
while IFS= read -r f; do
  if otool -L "$f" 2>/dev/null | tail -n +2 | grep -q '/opt/homebrew'; then
    echo "  UNRESOLVED dylib ref in $f:" >&2
    otool -L "$f" 2>/dev/null | tail -n +2 | grep '/opt/homebrew' >&2
    fail=1
  fi
done < <(find "$SANEROOT" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0 \
         | xargs -0 -n1 printf '%s\n'; printf '%s\n' "$APP/Contents/MacOS/Scan SCX3405")
[ "$fail" = 0 ] || { echo "payload still references Homebrew" >&2; exit 1; }
echo "  ok"

echo "== 7. component package"
chmod 755 "$HERE/scripts/preinstall" "$HERE/scripts/postinstall"
pkgbuild --root "$STAGE" --identifier "$PKGID" --version "$VERSION" \
         --scripts "$HERE/scripts" --ownership recommended \
         "$DIST/SCX3405-component.pkg"

echo "== 8. product archive"
sed "s/version=\"[0-9.]*\"/version=\"$VERSION\"/g" "$HERE/Distribution.xml" > "$DIST/Distribution.xml"
productbuild --distribution "$DIST/Distribution.xml" --package-path "$DIST" \
             "$DIST/Install SCX3405.pkg"

echo "== 9. dmg"
DMGROOT="$DIST/dmgroot"
mkdir -p "$DMGROOT"
cp "$DIST/Install SCX3405.pkg"  "$DMGROOT/"
cp "$HERE/resources/ReadMe.txt" "$DMGROOT/Read Me First.txt"
hdiutil create -volname "SCX-3405 Installer" -srcfolder "$DMGROOT" \
        -ov -format UDZO "$DIST/SCX3405-Full-Installer.dmg" >/dev/null

echo
echo "== done"
ls -lh "$DIST/SCX3405-Full-Installer.dmg"
