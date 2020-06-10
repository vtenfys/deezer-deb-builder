#!/bin/bash
set -e

ELECTRON_VERSION=6.1.7
DEEZER_VERSION=4.20.0
DEEZER_BINARY=deezer.exe
DEEZER_DMG=deezer.dmg

if [[ $1 != win && $1 != mac ]]; then
  echo Please specify whether you would like to build a DEB package using \
    Windows or macOS sources
  echo Example: ./build.sh win
  exit 1
fi

# Check for Deezer Windows installer
if [ "$1" == win ] && ! [ -f $DEEZER_BINARY ]; then
  echo Deezer installer missing!
  echo Please download Deezer for Windows from \
    'https://www.deezer.com/desktop/download?platform=win32&architecture=x86' \
    and place the installer in this directory as $DEEZER_BINARY
  exit 1
fi

# Check for Deezer macOS installer
if [ "$1" == mac ] && ! [ -f $DEEZER_DMG ]; then
  echo Deezer installer missing!
  echo Please download Deezer for macOS from \
    'https://www.deezer.com/desktop/download?platform=darwin&architecture=x64' \
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
  7z icns2png fakeroot dpkg
)

for command in "${commands[@]}"; do
  check-command "$command"
done

# Setup the build directory
mkdir -p build

if [ "$1" == win ]; then
  # Extract the Deezer executable
  if ! [ -f "build/deezer/\$PLUGINSDIR/app-64.7z" ]; then
    7z x $DEEZER_BINARY -obuild/deezer
  fi

  # Extract the app bundle
  if ! [ -f build/bundle/resources/app.asar ]; then
    7z x "build/deezer/\$PLUGINSDIR/app-32.7z" -obuild/bundle
  fi

  # Extract the app container
  if ! [ -d build/app ]; then
    asar extract build/bundle/resources/app.asar build/app
  fi
elif [ "$1" == mac ]; then
  # Extract the Deezer disk image
  if ! [ -f "build/deezer/Deezer $DEEZER_VERSION/Deezer.app/Contents/Resources/app.asar" ]; then
    7z x $DEEZER_DMG -obuild/deezer
  fi

  if ! [ -d build/app ]; then
    asar extract \
      "build/deezer/Deezer $DEEZER_VERSION/Deezer.app/Contents/Resources/app.asar" \
      build/app
  fi
fi

# Install NPM dependencies
if ! [ -f build/app/package-lock.json ]; then
  # Remove existing node_modules
  rm -rf build/app/node_modules

  # Remove unsupported electron-media-service package
  sed -i '/electron-media-service/d' build/app/package.json

  # Include source platform in version string
  sed -i "s/${DEEZER_VERSION//./\\.}/$DEEZER_VERSION-$1/" build/app/package.json

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

# Convert Deezer.icns to PNG
if ! [ -f build/app/Deezer_512x512x32.png ]; then
  macos_icon="build/deezer/Deezer $DEEZER_VERSION/Deezer.app/Contents/Resources/Deezer.icns"
  #if [ -f "$macos_icon" ]; then
    # Can't find 512x512 only 128x128
    #icns2png -x -s 512x512 "$macos_icon" -o build/app
  #else
    cp Deezer_512x512x32.png build/app
  #fi
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

# Include additional required icon file
if ! [ -f build/dist/app-linux-x64/resources/linux/systray.png ]; then
  mkdir -p build/dist/app-linux-x64/resources/linux
  cp build/app/Deezer_512x512x32.png \
    build/dist/app-linux-x64/resources/linux/systray.png
fi

# Create Debian package
electron-installer-debian \
  --src build/dist/app-linux-x64 \
  --dest out \
  --arch amd64 \
  --options.productName Deezer \
  --options.icon build/dist/app-linux-x64/resources/app/Deezer_512x512x32.png \
  --options.desktopTemplate "$PWD/desktop.ejs"
