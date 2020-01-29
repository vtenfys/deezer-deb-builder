#!/bin/bash
set -e

ELECTRON_VERSION=6.1.7
DEEZER_BINARY=deezer.exe
DEEZER_DMG=deezer.dmg

if [[ $1 != windows && $1 != mac ]]; then
  echo Please specify whether you would like to build a DEB package using \
    Windows or macOS sources
  echo Example: ./build.sh windows
  exit 1
fi

# Check for Deezer Windows installer
if [ "$1" == windows ] && ! [ -f $DEEZER_BINARY ]; then
  echo Deezer installer missing!
  echo Please download Deezer for Windows from https://www.deezer.com/en/download \
    and place the installer in this directory as $DEEZER_BINARY
  exit 1
fi

# Check for Deezer macOS installer
if [ "$1" == mac ] && ! [ -f $DEEZER_DMG ]; then
  echo Deezer installer missing!
  echo Please download Deezer for macOS from https://www.deezer.com/en/download \
    and place the installer in this directory as $DEEZER_DMG
  exit 1
fi

# Check for required commands
check-command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo Missing command: "$1"
    exit 1
  fi
}

commands=(
  node npm asar electron-packager electron-installer-debian
  7z convert fakeroot dpkg
)

for command in "${commands[@]}"; do
  check-command "$command"
done

# Setup the build directory
mkdir -p build

if [ "$1" == windows ]; then
  # Extract the Deezer executable
  if ! [ -f "build/deezer/\$PLUGINSDIR/app-64.7z" ]; then
    7z x $DEEZER_BINARY -obuild/deezer
  fi

  # Extract the app bundle
  if ! [ -f build/bundle/resources/app.asar ]; then
    7z x "build/deezer/\$PLUGINSDIR/app-64.7z" -obuild/bundle
  fi

  # Extract the app container
  if ! [ -d build/app ]; then
    asar extract build/bundle/resources/app.asar build/app
  fi
elif [ "$1" == mac ]; then
  # Extract the Deezer disk image
  if ! [ -f 'build/deezer/Deezer Installer/Deezer.app/Contents/Resources/app.asar' ]; then
    7z x $DEEZER_DMG -obuild/deezer
  fi

  if ! [ -d build/app ]; then
    asar extract \
      'build/deezer/Deezer Installer/Deezer.app/Contents/Resources/app.asar' \
      build/app
  fi
fi

# Install NPM dependencies
if ! [ -f build/app/package-lock.json ]; then
  # Remove existing node_modules
  rm -rf build/app/node_modules

  # Configure build settings
  # See https://www.electronjs.org/docs/tutorial/using-native-node-modules
  export npm_config_target=$ELECTRON_VERSION
  export npm_config_arch=x64
  export npm_config_target_arch=x64
  export npm_config_disturl=https://electronjs.org/headers
  export npm_config_runtime=electron
  export npm_config_build_from_source=true

  HOME=~/.electron-gyp npm install --prefix build/app
fi

# Convert icon.ico to PNG
if ! [ -f build/app/icon.png ]; then
  convert 'build/app/icon.ico[0]' build/app/icon.png
fi

# Create Electron distribution
if ! [ -d build/dist ]; then
  electron-packager build/app app \
    --platform linux \
    --arch x64 \
    --out build/dist \
    --electron-version $ELECTRON_VERSION \
    --executable-name deezer-desktop
fi

# Create Debian package
electron-installer-debian \
  --src build/dist/app-linux-x64 \
  --dest out \
  --arch amd64 \
  --options.productName Deezer \
  --options.icon build/dist/app-linux-x64/resources/app/icon.png
