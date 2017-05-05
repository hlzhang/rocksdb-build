#!/usr/bin/env bash

SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
export SCRIPT_PATH="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
echo "SCRIPT_PATH: ${SCRIPT_PATH}"

: "${LIB_NAME:=rocksdb-f201a44}"
LIB_VERSION="$(echo ${LIB_NAME} | awk -F- '{print $2}')"
ARCHIVE="${LIB_NAME}.zip"
ARCHIVE_URL="https://github.com/facebook/rocksdb/archive/f201a44b4102308b840b15d9b89122af787476f1.zip"

GFLAGS_ARCHIVE="gflags-2.2.0.tar.gz"
GFLAGS_ARCHIVE_URL="https://github.com/gflags/gflags/archive/v2.2.0.tar.gz"
mkdir -p target
[ -f "target/${GFLAGS_ARCHIVE}" ] || aria2c --file-allocation=none -c -x 10 -s 10 -m 0 --console-log-level=notice --log-level=notice --summary-interval=0 -d "$(pwd)/target" -o "${GFLAGS_ARCHIVE}" "${GFLAGS_ARCHIVE_URL}"

SNAPPY_ARCHIVE="snappy-1.1.4.tar.gz"
SNAPPY_ARCHIVE_URL="https://github.com/google/snappy/releases/download/1.1.4/snappy-1.1.4.tar.gz"
mkdir -p target
[ -f "target/${SNAPPY_ARCHIVE}" ] || aria2c --file-allocation=none -c -x 10 -s 10 -m 0 --console-log-level=notice --log-level=notice --summary-interval=0 -d "$(pwd)/target" -o "${SNAPPY_ARCHIVE}" "${SNAPPY_ARCHIVE_URL}"

LZ4_ARCHIVE="lz4-1.7.5.tar.gz"
LZ4_ARCHIVE_URL="https://github.com/lz4/lz4/archive/v1.7.5.tar.gz"
mkdir -p target
[ -f "target/${LZ4_ARCHIVE}" ] || aria2c --file-allocation=none -c -x 10 -s 10 -m 0 --console-log-level=notice --log-level=notice --summary-interval=0 -d "$(pwd)/target" -o "${LZ4_ARCHIVE}" "${LZ4_ARCHIVE_URL}"

if [[ ! -v AND_ARCHS ]]; then
    : "${AND_ARCHS:=android android-armeabi android-x86 android64 android64-aarch64}"
    #snappy doesn't compile on x86 : "${AND_ARCHS:=android-x86}"
    #: "${AND_ARCHS:=android android-armeabi android64 android64-aarch64}"
fi

if [[ ! -v IOS_ARCHS ]]; then
    : "${IOS_ARCHS:=arm64 armv7 armv7s i386 x86_64}"
    #snappy doesn't compile on simulator i386 : "${IOS_ARCHS:=i386}"
    #: "${IOS_ARCHS:=arm64 armv7 armv7s x86_64}"
fi

FILTER="${SCRIPT_PATH}/filter"

function unzip-strip() {
    local zip=$1
    local dest=${2:-.}
    local temp=$(mktemp -d) && unzip -d "$temp" "$zip" > /dev/null && mkdir -p "$dest" &&
    shopt -s dotglob && local f=("$temp"/*) &&
    if (( ${#f[@]} == 1 )) && [[ -d "${f[0]}" ]] ; then
        mv "$temp"/*/* "$dest"
    else
        mv "$temp"/* "$dest"
    fi && rmdir "$temp"/* "$temp"
}

function make_android_toolchain() {
    if [ -z "$NDK_PLATFORM" ]; then
      export NDK_PLATFORM="android-24"
      export NDK_PLATFORM_COMPAT="${NDK_PLATFORM_COMPAT:-android-16}"
    else
      export NDK_PLATFORM_COMPAT="${NDK_PLATFORM_COMPAT:-${NDK_PLATFORM}}"
    fi
    export NDK_API_VERSION=$(echo "$NDK_PLATFORM" | sed 's/^android-//')
    export NDK_API_VERSION_COMPAT=$(echo "$NDK_PLATFORM_COMPAT" | sed 's/^android-//')

    if [ -z "$ANDROID_NDK_HOME" ]; then
      echo "You should probably set ANDROID_NDK_HOME to the directory containing"
      echo "the Android NDK"
      exit
    fi

    export MAKE_TOOLCHAIN="${ANDROID_NDK_HOME}/build/tools/make_standalone_toolchain.py"

    export CC="${HOST_COMPILER}-clang"
    export CXX="${HOST_COMPILER}-clang++"

    rm -rf "${TOOLCHAIN_DIR}" "${PREFIX}"

    echo
    echo "Building for platform [${NDK_PLATFORM}], retaining compatibility with platform [${NDK_PLATFORM_COMPAT}]"
    echo

    env - PATH="$PATH" \
        "$MAKE_TOOLCHAIN" --force --api="$NDK_API_VERSION_COMPAT" \
        --unified-headers --arch="$ARCH" --install-dir="$TOOLCHAIN_DIR" || exit 1
}

function install_gflags() {
    #git clone https://github.com/gflags/gflags.git && cd gflags && git checkout v2.2.0 && cd cmake
    rm -rf target/gflags
    mkdir -p target/gflags
    tar xzf "target/${GFLAGS_ARCHIVE}" --strip-components=1 -C "target/gflags"
    cd target/gflags/cmake

    if [ -z "${PREFIX}" ]; then exit 1; else echo ${PREFIX}/gflags; fi

    # see: https://github.com/gflags/gflags/blob/master/INSTALL.md
    export CMAKE_INSTALL_PREFIX="${PREFIX}/gflags"
    rm -rf ${CMAKE_INSTALL_PREFIX}
    mkdir -p ${CMAKE_INSTALL_PREFIX}

    if [[ -v TARGET_ARCH ]]; then
        if [ -z "${CC}" ]; then exit 1; else echo "CC: '${CC}'"; fi
        if [ -z "${CXX}" ]; then exit 1; else echo "CXX: '${CXX}'"; fi
        if [ -z "${CMAKE_ARCH_ABI}" ]; then exit 1; fi
        if [ -z "${ANDROID_NDK_HOME}" ]; then exit 1; fi
        if [ -z "${TOOLCHAIN_DIR}" ]; then exit 1; fi

        # see: http://stackoverflow.com/questions/40054495/set-cmake-prefix-path-not-working-with-android-toolchain
        cmake -DCMAKE_INSTALL_PREFIX="/" .. \
            -DCMAKE_SYSTEM_NAME=Android \
            -DCMAKE_SYSTEM_VERSION=21 \
            -DCMAKE_ANDROID_ARCH_ABI=${CMAKE_ARCH_ABI} \
            -DCMAKE_ANDROID_NDK="${ANDROID_NDK_HOME}" \
            -DCMAKE_ANDROID_STL_TYPE=gnustl_static \
            -DCMAKE_ANDROID_STANDALONE_TOOLCHAIN="${TOOLCHAIN_DIR}" \
            -DCMAKE_C_COMPILER=${CC} \
            -DCMAKE_CXX_COMPILER=${CXX} \
            -DCMAKE_C_FLAGS_RELEASE=-DNDEBUG \
            -DCMAKE_CXX_FLAGS_RELEASE=-DNDEBUG \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_FIND_FRAMEWORK=LAST \
            -DCMAKE_VERBOSE_MAKEFILE=ON \
            -Wno-dev \
            -DBUILD_STATIC_LIBS=ON \
            -DBUILD_SHARED_LIBS=ON \
            -DBUILD_gflags_LIB=ON \
            -DBUILD_gflags_nothreads_LIB=ON
        export DESTDIR=${CMAKE_INSTALL_PREFIX}
        make install
        mv ${CMAKE_INSTALL_PREFIX}/usr/local/* ${CMAKE_INSTALL_PREFIX}/
        rm -rf ${CMAKE_INSTALL_PREFIX}/usr ${CMAKE_INSTALL_PREFIX}/Users
    else
        if [ -z "${ARCH}" ]; then exit 1; else echo "ARCH: '${ARCH}'"; fi
        if [ -z "${SDK}" ]; then exit 1; else echo "SDK: '${SDK}'"; fi
        if [ -z "${IOS_PLATFORM}" ]; then exit 1; else echo "IOS_PLATFORM: '${IOS_PLATFORM}'"; fi

        #-DCMAKE_C_FLAGS="${CFLAGS}" \
        #-DCMAKE_C_COMPILER=clang \
        #-DCMAKE_CXX_COMPILER="clang++" \
        #-DCMAKE_STATIC_LINKER_FLAGS="${LDFLAGS}" \
        #-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
        #-DCMAKE_MODULE_LINKER_FLAGS="${LDFLAGS}" \
        cmake -DCMAKE_INSTALL_PREFIX="'${CMAKE_INSTALL_PREFIX}'" .. \
            -DCMAKE_TOOLCHAIN_FILE=../../../ios.cmake \
            -DCMAKE_IOS_SDK_ROOT="${SDK}" \
            -DIOS_PLATFORM=${IOS_PLATFORM} \
            -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
            -DCMAKE_CXX_FLAGS="-I${SDK}/usr/include" \
            -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
            -DCMAKE_C_FLAGS_RELEASE=-DNDEBUG \
            -DCMAKE_CXX_FLAGS_RELEASE=-DNDEBUG \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_FIND_FRAMEWORK=LAST \
            -DCMAKE_VERBOSE_MAKEFILE=ON \
            -Wno-dev \
            -DBUILD_STATIC_LIBS=ON \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_gflags_LIB=ON \
            -DBUILD_gflags_nothreads_LIB=ON
        make install
    fi
    unset CMAKE_INSTALL_PREFIX
    unset DESTDIR

    cd ../../../
}

function install_snappy() {
    rm -rf target/snappy
    mkdir -p target/snappy
    tar xzf "target/${SNAPPY_ARCHIVE}" --strip-components=1 -C "target/snappy"
    cd target/snappy

    # snappy 1.1.4 don't compile on i386, 1.1.3 compiled fine see: https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=216553
    if [ "${TARGET_ARCH}" == "i686" ] || [ "${ARCH}" == "i386" ]; then
        patch < ../../snappy_114.patch
    fi

    rm -rf "${PREFIX}/snappy"
    mkdir -p "${PREFIX}/snappy"

    if [[ -v TARGET_ARCH ]]; then
        #./autogen.sh
        ./configure \
            --disable-dependency-tracking \
            --host="${HOST_COMPILER}" \
            --prefix="${PREFIX}/snappy" \
            --with-sysroot="${TOOLCHAIN_DIR}/sysroot" || exit 1
    else
        #./autogen.sh
        ./configure \
            --disable-dependency-tracking \
            --host="${HOST_COMPILER}" \
            --prefix="${PREFIX}/snappy" \
            --with-sysroot="${SDK}" \
            LDFLAGS="${LDFLAGS}" \
            CFLAGS="${CFLAGS}" || exit 1
    fi
    make && make install

    cd ../../
}

function install_lz4() {
    rm -rf target/lz4
    mkdir -p target/lz4
    tar xzf "target/${LZ4_ARCHIVE}" --strip-components=1 -C "target/lz4"
    cd target/lz4/lib

    rm -rf "${PREFIX}/lz4"
    mkdir -p "${PREFIX}/lz4/lib"
    mkdir -p "${PREFIX}/lz4/include"

    # see: https://github.com/OpenVPN/openvpn3/blob/master/deps/lz4/build-lz4
    # see: https://gist.github.com/i36lib/bb27680fc8058c98aa92
    PREFIX="${PREFIX}/lz4"
    if [[ -v TARGET_ARCH ]]; then
        #AR="${HOST_COMPILER}-ar"
        CC="${HOST_COMPILER}-gcc -isysroot ${TOOLCHAIN_DIR}/sysroot"
        LD="${HOST_COMPILER}-ld"
        AR="${HOST_COMPILER}-gcc-ar"
        RANLIB="${HOST_COMPILER}-gcc-ranlib"
    else
        CC="clang ${CFLAGS}"
        LD="ld ${LDFLAGS}"
        AR="ar"
        RANLIB="ranlib"
    fi
    $CC -c lz4.c -o ${PREFIX}/lz4.o
    $CC -c lz4hc.c -o ${PREFIX}/lz4hc.o
    $AR rc ${PREFIX}/lib/liblz4.a ${PREFIX}/lz4.o ${PREFIX}/lz4hc.o
    $RANLIB ${PREFIX}/lib/liblz4.a
    rm -f ${PREFIX}/lz4*.o
    cp lz4.h ${PREFIX}/include/

    cd ../../../
}
