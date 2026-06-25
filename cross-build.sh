#!/usr/bin/env bash
# cross-build.sh — Automatic cross-compilation to OpenBSD/macppc
#
# Downloads OpenBSD base sets, generates registry data from a vanilla
# Minecraft server, and produces a statically-linked PowerPC binary.
#
# Usage:
#   ./cross-build.sh                    # build for macppc (OpenBSD 7.9)
#   ./cross-build.sh --arch macppc      # same as above
#   ./cross-build.sh --arch powerpc64   # 64-bit PowerPC (experimental)
#   ./cross-build.sh --release 7.8      # use a different OpenBSD release
#   ./cross-build.sh --server server.jar  # path to existing server.jar
#   ./cross-build.sh --clean            # remove downloaded and built files

set -euo pipefail

ARCH="${ARCH:-macppc}"
OPENBSD_RELEASE="${OPENBSD_RELEASE:-7.9}"
MIRROR="${MIRROR:-https://mirror.one.com/openbsd}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSROOT_DIR="$PROJECT_DIR/sysroot-$ARCH"
OUTDIR="$PROJECT_DIR"
SERVER_JAR="${SERVER_JAR:-}"
REGEN_REGISTRIES=false

# ---- Parse args ----
while [ $# -gt 0 ]; do
  case "$1" in
    --arch) ARCH="$2"; shift ;;
    --release) OPENBSD_RELEASE="$2"; shift ;;
    --sysroot) SYSROOT_DIR="$2"; shift ;;
    --server) SERVER_JAR="$2"; REGEN_REGISTRIES=true; shift ;;
    --regen-registries) REGEN_REGISTRIES=true ;;
    --mirror) MIRROR="$2"; shift ;;
    --clean)
      rm -rf "$SYSROOT_DIR" "$PROJECT_DIR/notchian" \
             "$PROJECT_DIR/sysroot-"* "$PROJECT_DIR/bareiron" \
             "$PROJECT_DIR/bareiron.exe"
      echo "Cleaned build artifacts."
      exit 0 ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo ""
      echo "  --arch <arch>          Target architecture (default: macppc)"
      echo "  --release <version>    OpenBSD release (default: 7.9)"
      echo "  --sysroot <path>       Use existing sysroot instead of downloading"
      echo "  --server <path>        Path to Minecraft server.jar for registry gen"
      echo "  --regen-registries     Regenerate registry data (needs server.jar)"
      echo "  --mirror <url>         OpenBSD mirror URL"
      echo "  --clean                Remove all downloaded/built files"
      echo ""
      echo "Environment:"
      echo "  ARCH, OPENBSD_RELEASE, MIRROR (same as -- flags)"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

echo "==> Target:  $ARCH"
echo "==> Release: $OPENBSD_RELEASE"

# ---- Prerequisites ----
MISSING=""
command -v clang      >/dev/null 2>&1 || MISSING="$MISSING clang"
command -v ld.lld     >/dev/null 2>&1 || MISSING="$MISSING lld"
command -v curl       >/dev/null 2>&1 || MISSING="$MISSING curl"
command -v java       >/dev/null 2>&1 || MISSING="$MISSING java (JDK 21+)"
command -v node       >/dev/null 2>&1 || MISSING="$MISSING node"

if [ -n "$MISSING" ]; then
  echo "Error: missing prerequisites:$MISSING"
  exit 1
fi

# ---- Determine triplet from arch ----
case "$ARCH" in
  macppc)    TRIPLET="powerpc-unknown-openbsd"; BITS=32 ;;
  macppc64|powerpc64) TRIPLET="powerpc64-unknown-openbsd"; BITS=64 ;;
  amd64)     TRIPLET="x86_64-unknown-openbsd"; BITS=64 ;;
  i386)      TRIPLET="i686-unknown-openbsd"; BITS=32 ;;
  arm64)     TRIPLET="aarch64-unknown-openbsd"; BITS=64 ;;
  *) echo "Unknown arch: $ARCH (supported: macppc, amd64, i386, arm64)"; exit 1 ;;
esac

# ---- Sysroot (download or use existing) ----
if [ ! -d "$SYSROOT_DIR/usr/lib" ]; then
  echo ""
  echo "==> Downloading OpenBSD/$ARCH $OPENBSD_RELEASE base sets..."
  mkdir -p "$SYSROOT_DIR" "$PROJECT_DIR/tmp-sets"

  URL="$MIRROR/$OPENBSD_RELEASE/$ARCH"
  for SET in base comp; do
    TGZ="${SET}${OPENBSD_RELEASE//./}.tgz"
    if [ -f "$PROJECT_DIR/tmp-sets/$TGZ" ]; then
      echo "  $TGZ already cached"
    else
      echo "  Downloading $URL/$TGZ ..."
      curl -#SL -o "$PROJECT_DIR/tmp-sets/$TGZ" "$URL/$TGZ"
    fi
    echo "  Extracting $TGZ ..."
    tar xzf "$PROJECT_DIR/tmp-sets/$TGZ" -C "$SYSROOT_DIR" \
      --exclude='./dev/*' --exclude='./tmp/*' 2>/dev/null
  done
  echo "  Sysroot ready at $SYSROOT_DIR"
else
  echo "==> Using existing sysroot at $SYSROOT_DIR"
fi

# ---- Registries (generate if needed) ----
if [ ! -f "$PROJECT_DIR/include/registries.h" ]; then
  REGEN_REGISTRIES=true
fi

if [ "$REGEN_REGISTRIES" = true ]; then
  echo ""
  echo "==> Generating registries..."

  mkdir -p "$PROJECT_DIR/notchian"

  if [ -z "$SERVER_JAR" ]; then
    SERVER_JAR="$PROJECT_DIR/notchian/server.jar"
    if [ ! -f "$SERVER_JAR" ]; then
      echo "  Looking up Minecraft 1.21.8 server.jar URL..."
      MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
      VER_URL=$(curl -sSL "$MANIFEST_URL" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for v in data['versions']:
    if v['id'] == '1.21.8':
        print(v['url'])
        break
")
      JAR_URL=$(curl -sSL "$VER_URL" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['downloads']['server']['url'])
")
      echo "  Downloading server.jar ..."
      curl -#SL -o "$SERVER_JAR" "$JAR_URL"
    fi
  fi

  echo "  Running Minecraft data generator..."
  (cd "$PROJECT_DIR/notchian" && \
    java -DbundlerMainClass="net.minecraft.data.Main" \
         -jar "$SERVER_JAR" --all 2>&1 | tail -3)

  echo "  Running build_registries.js ..."
  node "$PROJECT_DIR/build_registries.js"
  echo "  Registries generated."

  # Move registries.c to src/ if the script put it in the project root
  if [ -f "$PROJECT_DIR/registries.c" ] && [ ! -f "$PROJECT_DIR/src/registries.c" ]; then
    mv "$PROJECT_DIR/registries.c" "$PROJECT_DIR/src/registries.c"
  fi
  if [ -f "$PROJECT_DIR/registries.h" ] && [ ! -f "$PROJECT_DIR/include/registries.h" ]; then
    mv "$PROJECT_DIR/registries.h" "$PROJECT_DIR/include/registries.h"
  fi
fi

# ---- Compile ----
echo ""
echo "==> Compiling for $TRIPLET ..."

OBJ="$ARCH-bareiron"
CC="clang --target=$TRIPLET --sysroot=$SYSROOT_DIR -B$SYSROOT_DIR/usr/lib"
CFLAGS="-O2 -I$PROJECT_DIR/include -nostdlibinc -isystem $SYSROOT_DIR/usr/include"
LDFLAGS="-fuse-ld=lld -L$SYSROOT_DIR/usr/lib -nostartfiles \
  $SYSROOT_DIR/usr/lib/crt0.o $SYSROOT_DIR/usr/lib/crtbegin.o \
  -lc -lcompiler_rt $SYSROOT_DIR/usr/lib/crtend.o -static"

rm -f "$PROJECT_DIR/$OBJ"
$CC $CFLAGS "$PROJECT_DIR"/src/*.c $LDFLAGS -o "$PROJECT_DIR/$OBJ"

echo ""
if [ -f "$PROJECT_DIR/$OBJ" ]; then
  file "$PROJECT_DIR/$OBJ"
  echo ""
  echo "Success: $PROJECT_DIR/$OBJ"
else
  echo "Build failed."
  exit 1
fi
