#!/bin/bash

set -e

# Global Valuess
readonly TAG_VERSION="v1.1.0"
readonly WEBP_GIT_URL="https://chromium.googlesource.com/webm/libwebp"
readonly WEBP_SRC_DIR="libwebp"
readonly TOPDIR=$(pwd)

# Extract Xcode version.
readonly XCODE=$(xcodebuild -version | grep Xcode | cut -d " " -f2)
if [[ -z "${XCODE}" ]]; then
  echo "Xcode not available"
  exit 1
fi

# Global Static 
readonly DEVELOPER=$(xcode-select --print-path)
readonly PLATFORMSROOT="${DEVELOPER}/Platforms"
readonly OLDPATH=${PATH}
readonly EXTRA_CFLAGS="-fembed-bitcode"
readonly LIPO=$(xcrun -sdk iphoneos${SDK} -find lipo)

usage() {
cat <<EOF
Usage: sh $0 command [argument]

command:
  all:          builds all frameworks
  ios:          builds iOS framework
  tvos:         builds tvOS framework
  macos:        builds macOS framework
  watchos:      builds watchOS framework       
EOF
}

# Clone a fresh copy of the libwep source code
clone_repo() {
    # Clone a copy of the WebP source code
    if [[ ! -d ${WEBP_SRC_DIR} ]]; then
        git clone --depth 1 --branch ${TAG_VERSION} ${WEBP_GIT_URL}
    fi

    # Move to the directory
    cd ${WEBP_SRC_DIR}
}

build_ios() {
  # Query for the SDK version installed
  SDK=$(xcodebuild -showsdks \
    | grep iphoneos | sort | tail -n 1 | awk '{print substr($NF, 9)}'
  )

  # Check to make sure we found the SDK version
  if [[ -z "${SDK}" ]]; then
    echo "iOS SDK not available"
    exit 1
  else 
    echo "iOS SDK Version ${SDK}"
  fi

  BUILDDIR="$(pwd)/iosbuild"

  build_common
  build_slice "arm64" "aarch64-apple-ios" "arm-apple-darwin" "iPhoneOS" "-miphoneos-version-min=11.0"
  build_slice "x86_64" "x86_64-apple-ios13.0-macabi" "x86_64-apple-darwin" "MacOSX" ""
  build_slice "x86_64" "x86_64-apple-ios" "x86_64-apple-darwin" "iPhoneSimulator" "-miphoneos-version-min=11.0"
  make_xcframeworks "iOS"
}

build_tvos() {
  # Query for the SDK version installed
  SDK=$(xcodebuild -showsdks \
    | grep appletvos | sort | tail -n 1 | awk '{print substr($NF, 10)}'
  )

  # Check to make sure we found the SDK version
  if [[ -z "${SDK}" ]]; then
    echo "tvOS SDK not available"
    exit 1
  else 
    echo "tvOS SDK Version ${SDK}"
  fi

  BUILDDIR="$(pwd)/tvosbuild"

  build_common
  build_slice "arm64" "aarch64-apple-tvos" "arm-apple-darwin" "AppleTVOS" "-mtvos-version-min=9.0"
  build_slice "x86_64" "x86_64-apple-tvos" "x86_64-apple-darwin" "AppleTVSimulator" "-mtvos-version-min=9.0"
  make_frameworks "tvOS"
}

build_macos() {
  # Query for the SDK version installed
  SDK=$(xcodebuild -showsdks \
    | grep macosx | sort | tail -n 1 | awk '{print substr($NF, 7)}'
  )

  # Check to make sure we found the SDK version
  if [[ -z "${SDK}" ]]; then
    echo "macOS SDK not available"
    exit 1
  else 
    echo "macOS SDK Version ${SDK}"
  fi

  BUILDDIR="$(pwd)/macosbuild"

  build_common
  # build_slice "arm64" "arm64-apple-macos11" "arm-apple-darwin" "MacOSX" ""
  build_slice "x86_64" "x86_64-apple-macos10.12" "x86_64-apple-darwin" "MacOSX" "-mmacosx-version-min=10.12"
  make_frameworks "macOS"
}

build_watchos() {
  # Query for the SDK version installed
  SDK=$(xcodebuild -showsdks \
    | grep watchos | sort | tail -n 1 | awk '{print substr($NF, 8)}'
  )

  # Check to make sure we found the SDK version
  if [[ -z "${SDK}" ]]; then
    echo "watchOS SDK not available"
    exit 1
  else 
    echo "watchOS SDK Version ${SDK}"
  fi

  BUILDDIR="$(pwd)/watchosbuild"

  build_common
  build_slice "arm64_32" "arm64_32-apple-watchos" "arm-apple-darwin" "WatchOS" "-mwatchos-version-min=2.0"
  build_slice "armv7k" "armv7k-apple-watchos" "arm-apple-darwin" "WatchOS" "-mwatchos-version-min=2.0"
  build_slice "x86_64" "x86_64-apple-watchos" "x86_64-apple-darwin" "WatchSimulator" "-mwatchos-version-min=2.0"
  build_slice "i386" "i386-apple-watchos" "i386-apple-darwin" "WatchSimulator" "-mwatchos-version-min=2.0"
  make_frameworks "watchOS"
}

# Perform common set-up/reset between builds
build_common() {
  SRCDIR=$(dirname $0)

  # Remove previous build folders
  rm -rf ${BUILDDIR}
  mkdir -p ${BUILDDIR}

  # Reset the lists of built binaries
  LIBLIST=''
  DECLIBLIST=''
  MUXLIBLIST=''
  DEMUXLIBLIST=''

  # Configure build settings
    if [[ ! -e ${SRCDIR}/configure ]]; then
      if ! (cd ${SRCDIR} && sh autogen.sh); then
        cat <<EOT
Error creating configure script!
This script requires the autoconf/automake and libtool to build. MacPorts can
be used to obtain these:
http://www.macports.org/install.php
EOT
        exit 1
      fi
    fi
}

build_slice() {
  ARCH=$1
  TARGET=$2
  HOST=$3
  PLATFORM=$4
  VERSION=$5
  
  ROOTDIR="${BUILDDIR}/${PLATFORM}-${ARCH}"
  mkdir -p "${ROOTDIR}"
  
  DEVROOT="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain"
  SDKROOT="${PLATFORMSROOT}/"
  SDKROOT+="${PLATFORM}.platform/Developer/SDKs/${PLATFORM}.sdk/"
  CFLAGS="-arch ${ARCH} -pipe -isysroot ${SDKROOT} -O3 -DNDEBUG -target ${TARGET}"
  CFLAGS+=" ${VERSION} ${EXTRA_CFLAGS}"

  # Add --disable-libwebpdemux \ to disable demux
  set -x
  export PATH="${DEVROOT}/usr/bin:${OLDPATH}"
  ${SRCDIR}/configure --host=${HOST} --prefix=${ROOTDIR} \
    --build=$(${SRCDIR}/config.guess) \
    --disable-shared --enable-static \
    --enable-libwebpdecoder --enable-swap-16bit-csp \
    --enable-libwebpmux \
    CFLAGS="${CFLAGS}"
  set +x

  # Run make only in the src/ directory to create libwebp.a/libwebpdecoder.a
  cd src/
  make V=0
  make install

  # Capture the locations of all of the built binaries
  LIBLIST+=" ${ROOTDIR}/lib/libwebp.a"
  DECLIBLIST+=" ${ROOTDIR}/lib/libwebpdecoder.a"
  MUXLIBLIST+=" ${ROOTDIR}/lib/libwebpmux.a"
  DEMUXLIBLIST+=" ${ROOTDIR}/lib/libwebpdemux.a"

  make clean
  cd ..

  export PATH=${OLDPATH}
}

make_xcframeworks() {
  TARGETDIR=${TOPDIR}/$1

  # Make WebP.xcframework
  echo "LIBLIST = ${LIBLIST}"
  rm -rf ${TARGETDIR}/WebP.xcframework
  mkdir -p ${TARGETDIR}/Headers/
cat <<EOT >> ${TARGETDIR}/Headers/module.modulemap
module WebP {
  header "decode.h"
  header "encode.h"
  header "types.h"
  export *
}
EOT
  LIBRARIES=''
  for LIBRARY in ${LIBLIST}; do
    LIBRARIES+="-library ${LIBRARY}} "
  done
  cp -a ${SRCDIR}/src/webp/{decode,encode,types}.h ${TARGETDIR}/Headers/
  xcodebuild -create-xcframework ${LIBRARIES} \
                -headers ${TARGETDIR}/Headers \
                -output ${TARGETDIR}/WebP.xcframework
  rm -rf ${TARGETDIR}/Headers

  # Make WebPDecoder.xcframework
  echo "DECLIBLIST = ${DECLIBLIST}"
  rm -rf ${TARGETDIR}/WebPDecoder.xcframework
  mkdir -p ${TARGETDIR}/Headers/
cat <<EOT >> ${TARGETDIR}/Headers/module.modulemap
module WebPDecoder {
  header "decode.h"
  header "types.h"
  export *
}
EOT
  LIBRARIES=''
  for LIBRARY in ${DECLIBLIST}; do
    LIBRARIES+="-library ${LIBRARY}} "
  done
  cp -a ${SRCDIR}/src/webp/{decode,types}.h ${TARGETDIR}/Headers/
  xcodebuild -create-xcframework ${LIBRARIES} \
                -headers ${TARGETDIR}/Headers \
                -output ${TARGETDIR}/WebPDecoder.xcframework
  rm -rf ${TARGETDIR}/Headers

  # Make WebPMux.xcframework
  echo "MUXLIBLIST = ${MUXLIBLIST}"
  rm -rf ${TARGETDIR}/WebPMux.xcframework
  mkdir -p ${TARGETDIR}/Headers/
cat <<EOT >> ${TARGETDIR}/Headers/module.modulemap
module WebPDecoder {
  header "mux.h"
  header "mux_types.h"
  header "types.h"
  export *
}
EOT
  LIBRARIES=''
  for LIBRARY in ${MUXLIBLIST}; do
    LIBRARIES+="-library ${LIBRARY}} "
  done
  cp -a ${SRCDIR}/src/webp/{types,mux,mux_types}.h ${TARGETDIR}/Headers/
  xcodebuild -create-xcframework ${LIBRARIES} \
                -headers ${TARGETDIR}/Headers \
                -output ${TARGETDIR}/WebPMux.xcframework
  rm -rf ${TARGETDIR}/Headers

  # Make WebPDemux.xcframework
  echo "DEMUXLIBLIST = ${DEMUXLIBLIST}"
  rm -rf ${TARGETDIR}/WebPDemux.xcframework
  mkdir -p ${TARGETDIR}/Headers/
cat <<EOT >> ${TARGETDIR}/Headers/module.modulemap
module WebPDemux {
  header "decode.h"
  header "mux_types.h"
  header "types.h"
  header "demux.h"
  export *
}
EOT
  LIBRARIES=''
  for LIBRARY in ${DEMUXLIBLIST}; do
    LIBRARIES+="-library ${LIBRARY}} "
  done
  cp -a ${SRCDIR}/src/webp/{decode,types,mux_types,demux}.h ${TARGETDIR}/Headers/
  xcodebuild -create-xcframework ${LIBRARIES} \
                -headers ${TARGETDIR}/Headers \
                -output ${TARGETDIR}/WebPDemux.xcframework
  rm -rf ${TARGETDIR}/Headers
}

make_frameworks() {

  # Make WebP.xcframework
  echo "LIBLIST = ${LIBLIST}"
  TARGETDIR=${TOPDIR}/$1/WebP.framework
  rm -rf ${TARGETDIR}
  mkdir -p ${TARGETDIR}/Headers/
  mkdir -p ${TARGETDIR}/Modules/
  cp -a ${SRCDIR}/src/webp/{decode,encode,types}.h ${TARGETDIR}/Headers/
cat <<EOT >> ${TARGETDIR}/Modules/module.modulemap
framework module WebP [system] {
  header "decode.h"
  header "encode.h"
  header "types.h"
  export *
}
EOT
  ${LIPO} -create ${LIBLIST} -output ${TARGETDIR}/WebP

  # Make WebPDecoder.xcframework
  echo "DECLIBLIST = ${DECLIBLIST}"
  TARGETDIR=${TOPDIR}/$1/WebPDecoder.framework
  rm -rf ${TARGETDIR}
  mkdir -p ${TARGETDIR}/Headers/
  mkdir -p ${TARGETDIR}/Modules/
  cp -a ${SRCDIR}/src/webp/{decode,types}.h ${TARGETDIR}/Headers/
cat <<EOT >> ${TARGETDIR}/Modules/module.modulemap
framework module WebPDecoder [system] {
  header "decode.h"
  header "types.h"
  export *
}
EOT
  ${LIPO} -create ${LIBLIST} -output ${TARGETDIR}/WebPDecoder

  # Make WebPMux.xcframework
  echo "MUXLIBLIST = ${MUXLIBLIST}"
  TARGETDIR=${TOPDIR}/$1/WebPMux.framework
  mkdir -p ${TARGETDIR}/Headers/
  mkdir -p ${TARGETDIR}/Modules/
  cp -a ${SRCDIR}/src/webp/{types,mux,mux_types}.h ${TARGETDIR}/Headers/
cat <<EOT >> ${TARGETDIR}/Modules/module.modulemap
framework module WebPMux [system] {
  header "mux.h"
  header "mux_types.h"
  header "types.h"
  export *
}
EOT
  ${LIPO} -create ${MUXLIBLIST} -output ${TARGETDIR}/WebPMux

  # Make WebPDemux.xcframework
  echo "DEMUXLIBLIST = ${DEMUXLIBLIST}"
  TARGETDIR=${TOPDIR}/$1/WebPDemux.framework
  mkdir -p ${TARGETDIR}/Headers/
  mkdir -p ${TARGETDIR}/Modules/
  cp -a ${SRCDIR}/src/webp/{decode,types,mux_types,demux}.h ${TARGETDIR}/Headers/
cat <<EOT >> ${TARGETDIR}/Modules/module.modulemap
framework module WebPDemux [system] {
  header "decode.h"
  header "mux_types.h"
  header "types.h"
  header "demux.h"
  export *
}
EOT
  ${LIPO} -create ${DEMUXLIBLIST} -output ${TARGETDIR}/WebPDemux
}

# Commands
COMMAND="$1"
case "$COMMAND" in

      "all")
        clone_repo
        build_ios
        build_tvos
        build_macos
        build_watchos
        exit 0
        ;;

    "ios")
        clone_repo
        build_ios
        exit 0
        ;;
    
    "tvos")
        clone_repo
        build_tvos
        exit 0
        ;;

    "macos")
        clone_repo
        build_macos
        exit 0
        ;;

    "watchos")
        clone_repo
        build_watchos
        exit 0
        ;;
esac

# Print usage instructions if no arguments were set
if [ "$#" -eq 0 -o "$#" -gt 3 ]; then
    usage
    exit 1
fi