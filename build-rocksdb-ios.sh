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
    local PLATFORM="iPhoneOS"

    unset HOST_COMPILER
    unset CC
    unset CXX
    unset LD
    unset AR
    unset RANLIB
    unset CFLAGS
    unset LDFLAGS

    CFLAGS=""
    LDFLAGS=""
    local PREFIX="$(pwd)/target"
    if [[ "${ARCH}" == "arm64" ]]; then
        CFLAGS="${CFLAGS} -O2 -arch arm64 -mios-version-min=${IOS_VERSION_MIN}"
        LDFLAGS="${LDFLAGS} -arch arm64 -mios-version-min=${IOS_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-aarch64-apple-ios"
        local CONFIGURE_HOST="arm-apple-darwin10"
        IOS_PLATFORM="OS"
    elif [[ "${ARCH}" == "armv7" ]]; then
        CFLAGS="-O2 -mthumb -arch armv7 -mios-version-min=${IOS_VERSION_MIN}"
        LDFLAGS="-mthumb -arch armv7 -mios-version-min=${IOS_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-armv7-apple-ios"
        local CONFIGURE_HOST="arm-apple-darwin10"
        IOS_PLATFORM="OS"
    elif [[ "${ARCH}" == "armv7s" ]]; then
        CFLAGS="-O2 -mthumb -arch armv7s -mios-version-min=${IOS_VERSION_MIN}"
        LDFLAGS="-mthumb -arch armv7s -mios-version-min=${IOS_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-armv7s-apple-ios"
        local CONFIGURE_HOST="arm-apple-darwin10"
        IOS_PLATFORM="OS"
    elif [[ "${ARCH}" == "i386" ]]; then
        CFLAGS="-O2 -arch i386 -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"
        LDFLAGS="-arch i386 -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-i386-apple-ios"
        local CONFIGURE_HOST="i686-apple-darwin10"

        PLATFORM="iPhoneSimulator"
        IOS_PLATFORM="SIMULATOR"
    elif [[ "${ARCH}" == "x86_64" ]]; then
        CFLAGS="-O2 -arch x86_64 -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"
        LDFLAGS="-arch x86_64 -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"

        PREFIX="${PREFIX}/${LIB_NAME}-x86_64-apple-ios"
        local CONFIGURE_HOST="x86_64-apple-darwin10"

        PLATFORM="iPhoneSimulator"
        IOS_PLATFORM="SIMULATOR64"
    fi

    export BASEDIR="${XCODEDIR}/Platforms/${PLATFORM}.platform/Developer"
    export PATH="${BASEDIR}/usr/bin:$BASEDIR/usr/sbin:$PATH"
    export SDK="${BASEDIR}/SDKs/${PLATFORM}.sdk"

    if [ -d "${PREFIX}" ]; then rm -fr "${PREFIX}"; fi
    mkdir -p ${PREFIX} || exit 1

    rm -rf "target/${LIB_NAME}"
    mkdir -p "target/${LIB_NAME}"
    unzip-strip "target/${ARCHIVE}" "target/${LIB_NAME}"

    echo "IOS_ARCH: ${ARCH} $(pwd)"

    export ARCH="${ARCH}"
    export CFLAGS="${CFLAGS} -isysroot ${SDK}"
    export LDFLAGS="${LDFLAGS} -isysroot ${SDK}"
    export IOS_PLATFORM="${IOS_PLATFORM}"
    install_gflags

    export HOST_COMPILER="${CONFIGURE_HOST}"
    export CC="clang ${CFLAGS}"
    export CXX="clang++ ${CFLAGS}"
    export LD="ld ${LDFLAGS}"
    install_snappy
    install_lz4

    cd "target/${LIB_NAME}"

#    ./configure --disable-shared --enable-static --disable-debug-mode \
#    --host=${CONFIGURE_HOST} \
#    --prefix="${PREFIX}" \
#    LDFLAGS="$LDFLAGS -L${PREFIX}/lib" \
#    CFLAGS="${CFLAGS} -I${PREFIX}/include" \
#    CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include"
#
#    make -j4 && make install && make clean

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

#if [[ $# -eq 0 && ${#IOS_ARCHS_ARRAY[@]} -eq 5 ]]; then
#    # Create universal binary and include folder
#    PREFIX="$(pwd)/target/${LIB_NAME}-universal-apple-ios"
#    rm -fr -- "${PREFIX}/include" "${PREFIX}/librocksdb3.a" 2> /dev/null
#    mkdir -p -- "${PREFIX}/lib"
#    lipo -create \
#      "$(pwd)/target/${LIB_NAME}-aarch64-apple-ios/lib/librocksdb3.a" \
#      "$(pwd)/target/${LIB_NAME}-armv7-apple-ios/lib/librocksdb3.a" \
#      "$(pwd)/target/${LIB_NAME}-armv7s-apple-ios/lib/librocksdb3.a" \
#      "$(pwd)/target/${LIB_NAME}-i386-apple-ios/lib/librocksdb3.a" \
#      "$(pwd)/target/${LIB_NAME}-x86_64-apple-ios/lib/librocksdb3.a" \
#      -output "${PREFIX}/lib/librocksdb3.a"
#    cp -r -- "$(pwd)/target/${LIB_NAME}-armv7-apple-ios/include" "${PREFIX}/"
#
#    echo
#    echo "librocksdb3 has been installed into ${PREFIX}"
#    echo
#    file -- "${PREFIX}/lib/librocksdb3.a"
#
#    # Cleanup
#    rm -rf -- "${PREFIX}/tmp"
#    make distclean > /dev/null || echo No rule to make target
#fi
