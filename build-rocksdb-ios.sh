#!/usr/bin/env bash

# see: http://blog.csdn.net/Sozell/article/details/12451565
# see: https://github.com/swiftlyfalling/SQLiteLib

set -e

source common.sh

export XCODEDIR=$(xcode-select -p)

xcode_major=$(xcodebuild -version|egrep '^Xcode '|cut -d' ' -f2|cut -d. -f1)
if [ $xcode_major -ge 8 ]; then
  export IOS_SIMULATOR_VERSION_MIN=${IOS_SIMULATOR_VERSION_MIN-"6.0.0"}
  export IOS_VERSION_MIN=${IOS_VERSION_MIN-"6.0.0"}
else
  export IOS_SIMULATOR_VERSION_MIN=${IOS_SIMULATOR_VERSION_MIN-"5.1.1"}
  export IOS_VERSION_MIN=${IOS_VERSION_MIN-"5.1.1"}
fi

function  configure_make() {
    local ARCH=$1
    local SDK_VERSION=$2

    local CONFIGURE_HOST=""
    local IOS_SDK_PLATFORM="iPhoneOS"

    unset HOST_COMPILER
    unset CC
    unset CXX
    unset LD
    unset AR
    unset RANLIB
    unset CFLAGS
    unset CXXFLAGS
    unset LDFLAGS

    IOS_CFLAGS=""
    IOS_LDFLAGS=""
    local PREFIX="$(pwd)/target"
    if [[ "${ARCH}" == "arm64" ]]; then
        IOS_CFLAGS="-O2 -arch arm64 -mios-version-min=${IOS_VERSION_MIN}"
        IOS_LDFLAGS="-arch arm64 -mios-version-min=${IOS_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-aarch64-apple-ios"
        local CONFIGURE_HOST="arm-apple-darwin10"
        CMAKE_IOS_PLATFORM="OS"
    elif [[ "${ARCH}" == "armv7" ]]; then
        IOS_CFLAGS="-O2 -mthumb -arch armv7 -mios-version-min=${IOS_VERSION_MIN}"
        IOS_LDFLAGS="-mthumb -arch armv7 -mios-version-min=${IOS_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-armv7-apple-ios"
        local CONFIGURE_HOST="arm-apple-darwin10"
        CMAKE_IOS_PLATFORM="OS"
    elif [[ "${ARCH}" == "armv7s" ]]; then
        IOS_CFLAGS="-O2 -mthumb -arch armv7s -mios-version-min=${IOS_VERSION_MIN}"
        IOS_LDFLAGS="-mthumb -arch armv7s -mios-version-min=${IOS_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-armv7s-apple-ios"
        local CONFIGURE_HOST="arm-apple-darwin10"
        CMAKE_IOS_PLATFORM="OS"
    elif [[ "${ARCH}" == "i386" ]]; then
        IOS_CFLAGS="-O2 -arch i386 -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"
        IOS_LDFLAGS="-arch i386 -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-i386-apple-ios"
        local CONFIGURE_HOST="i686-apple-darwin10"

        IOS_SDK_PLATFORM="iPhoneSimulator"
        CMAKE_IOS_PLATFORM="SIMULATOR"
    elif [[ "${ARCH}" == "x86_64" ]]; then
        IOS_CFLAGS="-O2 -arch x86_64 -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"
        IOS_LDFLAGS="-arch x86_64 -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-x86_64-apple-ios"
        local CONFIGURE_HOST="x86_64-apple-darwin10"

        IOS_SDK_PLATFORM="iPhoneSimulator"
        CMAKE_IOS_PLATFORM="SIMULATOR64"
    fi

    export BASEDIR="${XCODEDIR}/Platforms/${IOS_SDK_PLATFORM}.platform/Developer"
    export PATH="${BASEDIR}/usr/bin:${BASEDIR}/usr/sbin:${PATH}"
    export SDK="${BASEDIR}/SDKs/${IOS_SDK_PLATFORM}.sdk"

    if [ -d "${PREFIX}" ]; then rm -fr "${PREFIX}"; fi
    mkdir -p ${PREFIX} || exit 1

    rm -rf "target/${LIB_NAME}"
    mkdir -p "target/${LIB_NAME}"
    unzip-strip "target/${ARCHIVE}" "target/${LIB_NAME}"

    echo "IOS_ARCH: ${ARCH} $(pwd)"

    export ARCH="${ARCH}"
    export CFLAGS="${IOS_CFLAGS} -isysroot ${SDK}"
    export LDFLAGS="${IOS_LDFLAGS} -isysroot ${SDK}"
    export CMAKE_IOS_PLATFORM="${CMAKE_IOS_PLATFORM}"
    install_gflags

    export CC="clang ${CFLAGS}"
    export CXX="clang++ ${CFLAGS}"
    export LD="ld ${LDFLAGS}"
    export HOST_COMPILER="${CONFIGURE_HOST}"
    install_snappy
    install_lz4

    unset HOST_COMPILER
    unset LD

    cd "target/${LIB_NAME}"

    export CC="clang"
    export CXX="clang++"
    # rocksdb's Makefile control -arch
    export CFLAGS="-DROCKSDB_LITE=1 -DIOS_CROSS_COMPILE"
    #-std=c++11 -stdlib=libc++
    export CXXFLAGS="${CFLAGS}"
    export LDFLAGS=""

    echo "CXX: ${CXX}"
    echo "CFLAGS: ${CFLAGS}"

    export LIBNAME="librocksdb_lite"
    export PORTABLE=1
    export TARGET_OS="IOS"
    echo "make clean"
    make clean
    echo "make static_lib"
    make -j4 static_lib
    echo "make install"
    INSTALL_PATH="${PREFIX}" make install

    cd ../../
}

IOS_ARCHS_ARRAY=(${IOS_ARCHS})
: "${IOS_SDK_VERSION:=10.3}"
for ((i=0; i < ${#IOS_ARCHS_ARRAY[@]}; i++))
do
    if [[ $# -eq 0 || "$1" == "${IOS_ARCHS_ARRAY[i]}" ]]; then
        configure_make "${IOS_ARCHS_ARRAY[i]}" "${IOS_SDK_VERSION}"
    fi
done

if [[ $# -eq 0 && ${#IOS_ARCHS_ARRAY[@]} -eq 5 ]]; then
    # Create universal binary and include folder
    PREFIX="$(pwd)/target/${LIB_NAME}-universal-apple-ios"
    rm -fr -- "${PREFIX}/include" "${PREFIX}/librocksdb_lite.a" 2> /dev/null
    mkdir -p -- "${PREFIX}/lib"
    lipo -create \
      "$(pwd)/target/${LIB_NAME}-aarch64-apple-ios/lib/librocksdb_lite.a" \
      "$(pwd)/target/${LIB_NAME}-armv7-apple-ios/lib/librocksdb_lite.a" \
      "$(pwd)/target/${LIB_NAME}-armv7s-apple-ios/lib/librocksdb_lite.a" \
      "$(pwd)/target/${LIB_NAME}-i386-apple-ios/lib/librocksdb_lite.a" \
      "$(pwd)/target/${LIB_NAME}-x86_64-apple-ios/lib/librocksdb_lite.a" \
      -output "${PREFIX}/lib/librocksdb_lite.a"
    cp -r -- "$(pwd)/target/${LIB_NAME}-armv7-apple-ios/include" "${PREFIX}/"

    echo
    echo "librocksdb_lite has been installed into ${PREFIX}"
    echo
    file -- "${PREFIX}/lib/librocksdb_lite.a"

    # Cleanup
    rm -rf -- "${PREFIX}/tmp"
    make distclean > /dev/null || echo No rule to make target
fi
