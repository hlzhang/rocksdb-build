#!/usr/bin/env bash

ORIGINAL_PATH="${PATH}"

SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
export SCRIPT_PATH="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
echo "SCRIPT_PATH: ${SCRIPT_PATH}"

mkdir -p target

GFLAGS_LIB_NAME="gflags-2.2.0"
GFLAGS_LIB_VERSION="$(echo ${GFLAGS_LIB_NAME} | awk -F- '{print $2}')"
GFLAGS_ARCHIVE="${GFLAGS_LIB_NAME}.tar.gz"
GFLAGS_ARCHIVE_URL="https://github.com/gflags/gflags/archive/v2.2.0.tar.gz"
[ -f "target/${GFLAGS_ARCHIVE}" ] || aria2c --file-allocation=none -c -x 10 -s 10 -m 0 --console-log-level=notice --log-level=notice --summary-interval=0 -d "$(pwd)/target" -o "${GFLAGS_ARCHIVE}" "${GFLAGS_ARCHIVE_URL}"

SNAPPY_LIB_NAME="snappy-1.1.4"
SNAPPY_LIB_VERSION="$(echo ${SNAPPY_LIB_NAME} | awk -F- '{print $2}')"
SNAPPY_ARCHIVE="snappy-1.1.4.tar.gz"
SNAPPY_ARCHIVE_URL="https://github.com/google/snappy/releases/download/1.1.4/snappy-1.1.4.tar.gz"
mkdir -p target
[ -f "target/${SNAPPY_ARCHIVE}" ] || aria2c --file-allocation=none -c -x 10 -s 10 -m 0 --console-log-level=notice --log-level=notice --summary-interval=0 -d "$(pwd)/target" -o "${SNAPPY_ARCHIVE}" "${SNAPPY_ARCHIVE_URL}"

LZ4_LIB_NAME="lz4-1.7.5"
LZ4_LIB_VERSION="$(echo ${LZ4_LIB_NAME} | awk -F- '{print $2}')"
LZ4_ARCHIVE="${LZ4_LIB_NAME}.tar.gz"
LZ4_ARCHIVE_URL="https://github.com/lz4/lz4/archive/v1.7.5.tar.gz"
mkdir -p target
[ -f "target/${LZ4_ARCHIVE}" ] || aria2c --file-allocation=none -c -x 10 -s 10 -m 0 --console-log-level=notice --log-level=notice --summary-interval=0 -d "$(pwd)/target" -o "${LZ4_ARCHIVE}" "${LZ4_ARCHIVE_URL}"

#: "${LIB_NAME:=rocksdb-f201a44}"
: "${LIB_NAME:=rocksdb-5.3.4}"
LIB_VERSION="$(echo ${LIB_NAME} | awk -F- '{print $2}')"
ARCHIVE="${LIB_NAME}.zip"
#ARCHIVE_URL="https://github.com/facebook/rocksdb/archive/f201a44b4102308b840b15d9b89122af787476f1.zip"
ARCHIVE_URL="https://github.com/facebook/rocksdb/archive/v5.3.4.zip"
[ -f "target/${ARCHIVE}" ] || aria2c --file-allocation=none -c -x 10 -s 10 -m 0 --console-log-level=notice --log-level=notice --summary-interval=0 -d "$(pwd)/target" -o "${ARCHIVE}" "${ARCHIVE_URL}"

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

function package() {
    local target_dir="${1}"
    local lib_name="${2}"
    local artifact_dirs=($(find ${target_dir} -mindepth 1 -maxdepth 1 -type d | awk -F "${target_dir}/" '{print $2}' | grep "${lib_name}-"))
    for artifact_dir in "${artifact_dirs[@]}"; do
        echo "package: ${artifact_dir} into ${artifact_dir}.tar.gz"
        tar czf "${artifact_dir}.tar.gz" "${artifact_dir}"
    done
}

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
    local UNIFIED_HEADERS="$1"
    # --unified-headers by default
    if [ -z "${UNIFIED_HEADERS}" ]; then UNIFIED_HEADERS="--unified-headers"; elif [ "${UNIFIED_HEADERS}" != "true" ]; then UNIFIED_HEADERS=""; fi
    #ls -l /usr/local/opt/android-ndk/android-ndk-r14b/platforms/android-21/arch-arm/usr/include/machine
    #ls -l ../android-toolchain-armv6/sysroot/usr/include/machine

    if [ -z "$NDK_PLATFORM" ]; then
      export NDK_PLATFORM="android-24"
      export NDK_PLATFORM_COMPAT="${NDK_PLATFORM_COMPAT:-android-21}"
    else
      export NDK_PLATFORM_COMPAT="${NDK_PLATFORM_COMPAT:-${NDK_PLATFORM}}"
    fi
    export NDK_API_VERSION=$(echo "$NDK_PLATFORM" | sed 's/^android-//')
    export NDK_API_VERSION_COMPAT=$(echo "$NDK_PLATFORM_COMPAT" | sed 's/^android-//')

    if [ -z "${ANDROID_NDK_HOME}" ]; then
      echo "You should probably set ANDROID_NDK_HOME to the directory containing"
      echo "the Android NDK"
      exit
    fi

    export MAKE_TOOLCHAIN="${ANDROID_NDK_HOME}/build/tools/make_standalone_toolchain.py"

    #export CC="${HOST_COMPILER}-gcc"
    #export CXX="${HOST_COMPILER}-g++"
    export CC="${HOST_COMPILER}-clang"
    export CXX="${HOST_COMPILER}-clang++"

    rm -rf "${TOOLCHAIN_DIR}" "${PREFIX}"

    echo
    echo "Building for platform [${NDK_PLATFORM}], retaining compatibility with platform [${NDK_PLATFORM_COMPAT}]"
    echo

    # error: ‘to_string’ is not a member of ‘std’
    # see: http://zengrong.net/post/2451.htm
    # see: http://stackoverflow.com/questions/42051279/android-ndk-stoi-stof-stod-to-string-is-not-a-member-of-std
    # --stl=libc++
    env - PATH="$PATH" \
        "$MAKE_TOOLCHAIN" --force --api="$NDK_API_VERSION_COMPAT" \
         ${UNIFIED_HEADERS} --stl=libc++ --arch="$ARCH" --install-dir="$TOOLCHAIN_DIR" || exit 1
}

function install_gflags() {
    #git clone https://github.com/gflags/gflags.git && cd gflags && git checkout v2.2.0 && cd cmake
    rm -rf "target/${GFLAGS_LIB_NAME}"
    mkdir -p "target/${GFLAGS_LIB_NAME}"
    tar xzf "target/${GFLAGS_ARCHIVE}" --strip-components=1 -C "target/${GFLAGS_LIB_NAME}"
    cd target/${GFLAGS_LIB_NAME}/cmake

    if [ -z "${PREFIX}" ]; then exit 1; else echo "${PREFIX}/${GFLAGS_LIB_NAME}"; fi

    # see: https://github.com/gflags/gflags/blob/master/INSTALL.md
    export CMAKE_INSTALL_PREFIX="${PREFIX}/${GFLAGS_LIB_NAME}"
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
        if [ -z "${CMAKE_IOS_PLATFORM}" ]; then exit 1; else echo "CMAKE_IOS_PLATFORM: '${CMAKE_IOS_PLATFORM}'"; fi

        #-DCMAKE_C_FLAGS="${CFLAGS}" \
        #-DCMAKE_C_COMPILER=clang \
        #-DCMAKE_CXX_COMPILER="clang++" \
        #-DCMAKE_STATIC_LINKER_FLAGS="${LDFLAGS}" \
        #-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
        #-DCMAKE_MODULE_LINKER_FLAGS="${LDFLAGS}" \
        cmake -DCMAKE_INSTALL_PREFIX="'${CMAKE_INSTALL_PREFIX}'" .. \
            -DCMAKE_TOOLCHAIN_FILE=../../../ios.cmake \
            -DCMAKE_IOS_SDK_ROOT="${SDK}" \
            -DCMAKE_IOS_PLATFORM=${CMAKE_IOS_PLATFORM} \
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
    rm -rf "target/${SNAPPY_LIB_NAME}"
    mkdir -p "target/${SNAPPY_LIB_NAME}"
    tar xzf "target/${SNAPPY_ARCHIVE}" --strip-components=1 -C "target/${SNAPPY_LIB_NAME}"
    cd "target/${SNAPPY_LIB_NAME}"

    # snappy 1.1.4 don't compile on i386, 1.1.3 compiled fine see: https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=216553
    if [ "${TARGET_ARCH}" == "i686" ] || [ "${ARCH}" == "i386" ]; then
        patch < ../../snappy_114.patch
    fi

    rm -rf "${PREFIX}/${SNAPPY_LIB_NAME}"
    mkdir -p "${PREFIX}/${SNAPPY_LIB_NAME}"

    if [[ -v TARGET_ARCH ]]; then
        #./autogen.sh
        ./configure \
            --disable-dependency-tracking \
            --host="${HOST_COMPILER}" \
            --prefix="${PREFIX}/${SNAPPY_LIB_NAME}" \
            --with-sysroot="${TOOLCHAIN_DIR}/sysroot" || exit 1
    else
        #./autogen.sh
        ./configure \
            --disable-dependency-tracking \
            --host="${HOST_COMPILER}" \
            --prefix="${PREFIX}/${SNAPPY_LIB_NAME}" \
            --with-sysroot="${SDK}" \
            LDFLAGS="${LDFLAGS}" \
            CFLAGS="${CFLAGS}" || exit 1
    fi
    make && make install

    cd ../../
}

function install_lz4() {
    rm -rf "target/${LZ4_LIB_NAME}"
    mkdir -p "target/${LZ4_LIB_NAME}"
    tar xzf "target/${LZ4_ARCHIVE}" --strip-components=1 -C "target/${LZ4_LIB_NAME}"
    cd target/${LZ4_LIB_NAME}/lib

    LZ4_PREFIX="${PREFIX}/${LZ4_LIB_NAME}"
    rm -rf "${LZ4_PREFIX}"
    mkdir -p "${LZ4_PREFIX}/lib"
    mkdir -p "${LZ4_PREFIX}/include"

    # see: https://github.com/OpenVPN/openvpn3/blob/master/deps/lz4/build-lz4
    # see: https://gist.github.com/i36lib/bb27680fc8058c98aa92
    if [[ -v TARGET_ARCH ]]; then
        #local CC="${HOST_COMPILER}-gcc --sysroot ${TOOLCHAIN_DIR}/sysroot"
        #local LD="${HOST_COMPILER}-ld"
        #local AR="${HOST_COMPILER}-gcc-ar"
        #local RANLIB="${HOST_COMPILER}-gcc-ranlib"
        local CC="${HOST_COMPILER}-clang --sysroot ${TOOLCHAIN_DIR}/sysroot"
        local LD="${HOST_COMPILER}-ld"
        local AR="${HOST_COMPILER}-ar"
        local RANLIB="${HOST_COMPILER}-ranlib"
    else
        local CC="clang ${CFLAGS}"
        local LD="ld ${LDFLAGS}"
        local AR="ar"
        local RANLIB="ranlib"
    fi
    $CC -c lz4.c -o ${LZ4_PREFIX}/lz4.o
    $CC -c lz4hc.c -o ${LZ4_PREFIX}/lz4hc.o
    $AR rc ${LZ4_PREFIX}/lib/liblz4.a ${LZ4_PREFIX}/lz4.o ${LZ4_PREFIX}/lz4hc.o
    $RANLIB ${LZ4_PREFIX}/lib/liblz4.a
    rm -f ${LZ4_PREFIX}/lz4*.o
    cp lz4.h ${LZ4_PREFIX}/include/

    cd ../../../
}
