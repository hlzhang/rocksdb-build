#! /bin/sh

./configure \
    --disable-soname-versions \
    --enable-minimal \
    --host="${HOST_COMPILER}" \
    --prefix="${PREFIX}" \
    --with-sysroot="${TOOLCHAIN_DIR}/sysroot" || exit 1

if [ "$NDK_PLATFORM" != "$NDK_PLATFORM_COMPAT" ]; then
  egrep '^#define ' config.log | sort -u > config-def-compat.log
  echo
  echo "Configuring again for platform [${NDK_PLATFORM}]"
  echo
  env - PATH="$PATH" \
      "$MAKE_TOOLCHAIN" --force --api="$NDK_API_VERSION" \
      --unified-headers --arch="$ARCH" --install-dir="$TOOLCHAIN_DIR" || exit 1

  ./configure \
      --disable-soname-versions \
      --enable-minimal \
      --host="${HOST_COMPILER}" \
      --prefix="${PREFIX}" \
      --with-sysroot="${TOOLCHAIN_DIR}/sysroot" || exit 1

  egrep '^#define ' config.log | sort -u > config-def.log
  if ! cmp config-def.log config-def-compat.log; then
    echo "Platform [${NDK_PLATFORM}] is not backwards-compatible with [${NDK_PLATFORM_COMPAT}]" >&2
    diff -u config-def.log config-def-compat.log >&2
    exit 1
  fi
  rm -f config-def.log config-def-compat.log
fi

make clean && \
make -j3 install && \
echo "rocksdb has been installed into ${PREFIX}"
