#!/usr/bin/env bash

# ---- Defaults ----
cc="${CC:-gcc}"
cflags="${CFLAGS:--O2 -Iinclude}"
ldflags="${LDFLAGS:-}"
target=""
sysroot=""
out="bareiron"

# ---- Parse arguments ----
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      target="$2"; shift ;;
    --sysroot)
      sysroot="$2"; shift ;;
    --9x)
      target="i686-w64-mingw32"
      # Windows 9x needs the GUI subsystem flag on modern Windows
      ldflags="$ldflags -Wl,--subsystem,console:4" ;;
    --clean)
      rm -f bareiron bareiron.exe
      exit 0 ;;
    *)
      echo "Usage: $0 [--target triplet] [--sysroot path] [--9x] [--clean]"
      echo ""
      echo "  --target <triplet>   Cross-compile for the given target"
      echo "  --sysroot <path>     Path to target sysroot (for cross-compilation)"
      echo "  --9x                 Build for Windows 9x (legacy alias for --target i686-w64-mingw32)"
      echo "  --clean              Remove built binaries"
      echo ""
      echo "Environment variables:"
      echo "  CC      Cross-compiler command (default: gcc)"
      echo "  CFLAGS  Compiler flags (default: -O2 -Iinclude)"
      echo "  LDFLAGS Linker flags"
      exit 1 ;;
  esac
  shift
done

# ---- Detect target from CC if not explicitly set ----
if [ -z "$target" ]; then
  case "${cc##*/}" in
    *mingw*|*mingw32*|*win32*) target="x86_64-w64-mingw32" ;;
    *openbsd*)                  target="${cc%%-gcc}-openbsd" ;;
  esac
fi

# ---- Determine output suffix based on target OS ----
exe=""
case "$target" in
  *mingw*|*mingw32*|*win32*|*-windows*|*-win32*)
    exe=".exe" ;;
esac
# Fallback to OSTYPE when no target is set (native MSYS/MinGW)
if [ -z "$target" ]; then
  case "$OSTYPE" in
    msys*|cygwin*|win32*) exe=".exe" ;;
  esac
fi

# ---- Target-specific linker flags ----
# Only auto-add windows linker libs when CC doesn't already link them
case "$target" in
  *mingw*|*mingw32*|*win32*|*-windows*|*-win32*)
    case " $ldflags " in *" -lws2_32 "*) ;; *) ldflags="$ldflags -lws2_32" ;; esac
    case " $ldflags " in *" -static "*)     ;; *) ldflags="$ldflags -static" ;; esac
    ;;
esac

# ---- sysroot handling ----
if [ -n "$sysroot" ]; then
  if [ -d "$sysroot" ]; then
    cflags="$cflags --sysroot=$sysroot"
    ldflags="$ldflags --sysroot=$sysroot"
  else
    echo "Warning: sysroot '$sysroot' not found, ignoring"
  fi
fi

# ---- Check registries ----
if [ ! -f "include/registries.h" ]; then
  echo "Error: 'include/registries.h' is missing."
  echo "Please follow the 'Compilation' section of the README to generate it."
  echo "See: https://github.com/niclas321/bareiron?tab=readme-ov-file#compilation"
  exit 1
fi

# ---- Build ----
echo "CC      = $cc"
echo "CFLAGS  = $cflags"
echo "LDFLAGS = $ldflags"
echo "Target  = ${target:-native}"
echo "Output  = $out$exe"
echo ""

rm -f "$out$exe"
$cc src/*.c $cflags $ldflags -o "$out$exe"

if [ -f "$out$exe" ]; then
  echo ""
  echo "Build successful: $out$exe"
  file "$out$exe"
fi
