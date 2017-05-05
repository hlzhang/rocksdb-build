#!/usr/bin/env bash

set -e

source common.sh

function package() {
    local target_dir="${1}"
    local lib_name="${2}"
    local artifact_dirs=($(find ${target_dir} -mindepth 1 -maxdepth 1 -type d | awk -F "${target_dir}/" '{print $2}' | grep "${lib_name}-"))
    for artifact_dir in "${artifact_dirs[@]}"; do
        echo "package: ${artifact_dir} into ${artifact_dir}.tar.gz"
        tar czf "${artifact_dir}.tar.gz" "${artifact_dir}"
    done
}

mkdir -p target
[ -f "target/${ARCHIVE}" ] || aria2c --file-allocation=none -c -x 10 -s 10 -m 0 --console-log-level=notice --log-level=notice --summary-interval=0 -d "$(pwd)/target" -o "${ARCHIVE}" "${ARCHIVE_URL}"

#brew install libtool autoconf automake

# build-${LIB_NAME}-darwin.sh
if [ -z "${AND_ARCHS}" ] && [ -z "${IOS_ARCHS}" ]; then
    brew tap chshawkn/homebrew-brew-tap
    brew install chshawkn/brew-tap/$(echo ${LIB_NAME} | awk -F- '{print $1}')_${LIB_VERSION}

    if [ -d target/${LIB_NAME}-x86_64-apple-darwin ]; then rm -rf target/${LIB_NAME}-x86_64-apple-darwin; fi
    mkdir -p target/${LIB_NAME}-x86_64-apple-darwin
    cp -r /usr/local/Cellar/$(echo ${LIB_NAME} | awk -F- '{print $1}')_${LIB_VERSION}/${LIB_VERSION}/*target/${LIB_NAME}-x86_64-apple-darwin/

    rm -f "target/${LIB_NAME}-x86_64-apple-darwin.tar.gz"
    # create archive by package function
    tar czf "target/${LIB_NAME}-x86_64-apple-darwin.tar.gz" -C "target" "${LIB_NAME}-x86_64-apple-darwin"
fi

unset CXX
unset CC
ORIGINAL_PATH="${PATH}"

AND_ARCHS_ARRAY=(${AND_ARCHS})
for ((i=0; i < ${#AND_ARCHS_ARRAY[@]}; i++))
do
    rm -rf "target/${LIB_NAME}"
    mkdir -p "target/${LIB_NAME}"
    unzip-strip "target/${ARCHIVE}" "target/${LIB_NAME}"

    unset TARGET_ARCH
    unset CFLAGS
    unset NDK_PLATFORM_COMPAT
    unset ARCH
    unset HOST_COMPILER

    AND_ARCH="${AND_ARCHS_ARRAY[i]}"
    echo "AND_ARCH: ${AND_ARCH} $(pwd)"
    if [ "${AND_ARCH}" == "android" ]; then
        RUST_AND_ARCH="arm-linux-androideabi"

        export TARGET_ARCH="armv6"
        export CMAKE_ARCH_ABI="armeabi"
        export CFLAGS="-Os -mthumb -marm -march=${TARGET_ARCH}"
        export ARCH=arm
        export HOST_COMPILER=arm-linux-androideabi
    elif [ "${AND_ARCH}" == "android-armeabi" ]; then
        RUST_AND_ARCH="armv7-linux-androideabi"

        export TARGET_ARCH="armv7-a"
        export CMAKE_ARCH_ABI="armeabi-v7a"
        export CFLAGS="-Os -mfloat-abi=softfp -mfpu=vfpv3-d16 -mthumb -marm -march=${TARGET_ARCH}"
        export ARCH=arm
        export HOST_COMPILER=arm-linux-androideabi
    elif [ "${AND_ARCH}" == "android-mips" ]; then
        RUST_AND_ARCH="mips-linux-android"

        export TARGET_ARCH="mips32"
        export CMAKE_ARCH_ABI="mips"
        export CFLAGS="-Os"
        export ARCH=mips
        export HOST_COMPILER=mips32el-linux-android
    elif [ "${AND_ARCH}" == "android-x86" ]; then
        RUST_AND_ARCH="i686-linux-android"

        export TARGET_ARCH="i686"
        export CMAKE_ARCH_ABI="x86"
        export CFLAGS="-Os -march=${TARGET_ARCH}"
        export ARCH=x86
        export HOST_COMPILER=i686-linux-android
    elif [ "${AND_ARCH}" == "android64" ]; then
        RUST_AND_ARCH="x86_64-linux-android"

        export TARGET_ARCH="westmere"
        export CMAKE_ARCH_ABI="x86_64"
        export CFLAGS="-Os -march=${TARGET_ARCH}"
        export NDK_PLATFORM_COMPAT=android-21
        export ARCH=x86_64
        export HOST_COMPILER=x86_64-linux-android
    elif [ "${AND_ARCH}" == "android64-aarch64" ]; then
        RUST_AND_ARCH="aarch64-linux-android"

        export TARGET_ARCH="armv8-a"
        export CMAKE_ARCH_ABI="arm64-v8a"
        export CFLAGS="-Os -march=${TARGET_ARCH}"
        export NDK_PLATFORM_COMPAT=android-21
        export ARCH=arm64
        export HOST_COMPILER=aarch64-linux-android
    else
        RUST_AND_ARCH="unknown"

        export TARGET_ARCH="unknown"
        export CMAKE_ARCH_ABI="unknown"
        export CFLAGS=""
        export ARCH=""
        export HOST_COMPILER=""
    fi

    if [ -z "${NDK_PLATFORM}" ]; then
        export NDK_PLATFORM="android-22"
    fi
    if [ -z "${ANDROID_NDK_HOME}" ]; then
        export ANDROID_NDK_HOME="/usr/local/opt/android-ndk/android-ndk-r14b"
    fi

    export TOOLCHAIN_DIR="$(pwd)/target/android-toolchain-${TARGET_ARCH}"
    export PATH="${TOOLCHAIN_DIR}/bin:${TOOLCHAIN_DIR}/libexec:${ORIGINAL_PATH}"
    export PREFIX="$(pwd)/target/${LIB_NAME}-android-${TARGET_ARCH}"

    make_android_toolchain
    install_gflags
    install_snappy
    install_lz4

    cd target/${LIB_NAME}
    #(${SCRIPT_PATH}/android-build.sh | ${FILTER} || cat config.log)

    unset TOOLCHAIN_DIR
    export PATH="${ORIGINAL_PATH}"

    cd ../
    #rm -rf ${LIB_NAME}-${RUST_AND_ARCH}
    #mkdir -p ${LIB_NAME}-${RUST_AND_ARCH}
    #cp -r ${LIB_NAME}/$(echo ${LIB_NAME} | awk -F- '{print $1}')-android-${TARGET_ARCH}/* ${LIB_NAME}-${RUST_AND_ARCH}/
    cd ../
done

unset TARGET_ARCH
unset CMAKE_ARCH_ABI
unset CFLAGS
unset NDK_PLATFORM_COMPAT
unset ARCH
unset HOST_COMPILER

source build-$(echo ${LIB_NAME} | awk -F- '{print $1}')-ios.sh

#(cd target; package "." "${LIB_NAME}"; ls -l .;)
