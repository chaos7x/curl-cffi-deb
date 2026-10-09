#!/usr/bin/env bash
# Baut ein python3-curl-cffi .deb aus dem offiziellen abi3-Wheel von PyPI.
#
# Aufruf: ./build-deb.sh <version> <debian-arch> [revision] [outdir]
#   debian-arch: amd64 | arm64 | armhf
#
# Es wird nichts kompiliert: das manylinux-Wheel enthält libcurl-impersonate
# bereits statisch gelinkt. Abhängigkeiten (cffi, certifi) kommen aus den
# Distro-Paketen.
set -euo pipefail

VERSION="${1:?Version fehlt (z.B. 0.16.3)}"
ARCH="${2:?Debian-Architektur fehlt (amd64|arm64|armhf)}"
REVISION="${3:-1}"
OUTDIR="${4:-dist}"

PKG="python3-curl-cffi"
MAINTAINER="${DEB_MAINTAINER:-chaos7x <chaos7x@users.noreply.github.com>}"
SITE="usr/lib/python3/dist-packages"

case "$ARCH" in
  amd64) PLATFORMS=(manylinux2014_x86_64 manylinux_2_17_x86_64) ;;
  arm64) PLATFORMS=(manylinux2014_aarch64 manylinux_2_17_aarch64) ;;
  armhf) PLATFORMS=(manylinux_2_31_armv7l manylinux_2_28_armv7l) ;;
  *) echo "Unbekannte Architektur: $ARCH" >&2; exit 1 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Wheel holen ------------------------------------------------------------
PLAT_ARGS=()
for p in "${PLATFORMS[@]}"; do PLAT_ARGS+=(--platform "$p"); done

python3 -m pip download --quiet --no-deps --only-binary=:all: \
  --implementation cp --python-version 3.10 --abi abi3 \
  "${PLAT_ARGS[@]}" -d "$WORK/wheel" "curl_cffi==${VERSION}"

WHEEL="$(ls "$WORK"/wheel/*.whl)"
echo "Wheel: $(basename "$WHEEL")"

# --- Paketbaum aufbauen ------------------------------------------------------
ROOT="$WORK/root"
mkdir -p "$ROOT/$SITE" "$ROOT/DEBIAN" "$ROOT/usr/share/doc/$PKG"
python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
  "$WHEEL" "$ROOT/$SITE"

DISTINFO="$(ls -d "$ROOT/$SITE"/curl_cffi-*.dist-info)"
# Ohne RECORD fasst pip das Paket nicht an ("installed by debian").
rm -f "$DISTINFO/RECORD"
echo "debian" > "$DISTINFO/INSTALLER"
# Upstream fordert cffi>=2.0, läuft aber mit cffi 1.x aus Debian/Ubuntu.
# Metadaten anpassen, damit "pip check" nicht meckert.
sed -i 's/^Requires-Dist: cffi>=2\.0\.0$/Requires-Dist: cffi>=1.15/' "$DISTINFO/METADATA"
if [ -f "$DISTINFO/licenses/LICENSE" ]; then
  cp "$DISTINFO/licenses/LICENSE" "$ROOT/usr/share/doc/$PKG/copyright"
elif [ -f "$DISTINFO/LICENSE" ]; then
  cp "$DISTINFO/LICENSE" "$ROOT/usr/share/doc/$PKG/copyright"
fi

# console_scripts aus entry_points.txt nach /usr/bin (z.B. curl-cffi)
if [ -f "$DISTINFO/entry_points.txt" ]; then
  python3 - "$DISTINFO/entry_points.txt" "$ROOT/usr/bin" <<'PY'
import configparser, os, sys
cp = configparser.ConfigParser()
cp.read(sys.argv[1])
if cp.has_section("console_scripts"):
    os.makedirs(sys.argv[2], exist_ok=True)
    for name, target in cp.items("console_scripts"):
        mod, func = [s.strip() for s in target.split(":")]
        path = os.path.join(sys.argv[2], name)
        with open(path, "w") as f:
            f.write(f"#!/usr/bin/python3\nimport sys\nfrom {mod} import {func}\n"
                    f"if __name__ == '__main__':\n    sys.exit({func}())\n")
        print("Script:", name)
PY
fi

find "$ROOT/usr" -type d -exec chmod 755 {} +
find "$ROOT/usr" -type f -exec chmod 644 {} +
find "$ROOT/$SITE" -name '*.so' -exec chmod 755 {} +
[ -d "$ROOT/usr/bin" ] && chmod 755 "$ROOT"/usr/bin/*

SIZE_KB="$(du -sk "$ROOT/usr" | cut -f1)"

cat > "$ROOT/DEBIAN/control" <<EOF
Package: ${PKG}
Version: ${VERSION}-${REVISION}
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Installed-Size: ${SIZE_KB}
Depends: python3 (>= 3.10), python3-cffi-backend (>= 1.15), python3-certifi
Suggests: python3-rich
Section: python
Priority: optional
Homepage: https://github.com/lexiforest/curl_cffi
Description: Python binding for curl-impersonate (browser TLS fingerprints)
 curl_cffi is a Python HTTP client based on curl-impersonate. It can
 impersonate the TLS/JA3 and HTTP/2 fingerprints of real browsers such as
 Chrome, Safari and Firefox, and offers a requests-like API plus asyncio
 and WebSocket support.
 .
 This package is repacked from the official manylinux abi3 wheel on PyPI.
EOF

# Bytecode beim Installieren erzeugen, beim Entfernen aufräumen.
cat > "$ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ] && command -v python3 >/dev/null 2>&1; then
  python3 -m compileall -q /usr/lib/python3/dist-packages/curl_cffi >/dev/null 2>&1 || true
fi
EOF
cat > "$ROOT/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
find /usr/lib/python3/dist-packages/curl_cffi -type d -name __pycache__ \
  -exec rm -rf {} + 2>/dev/null || true
EOF
chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/prerm"

mkdir -p "$OUTDIR"
OUT="$OUTDIR/${PKG}_${VERSION}-${REVISION}_${ARCH}.deb"
dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$OUT" >/dev/null
echo "Gebaut: $OUT"
