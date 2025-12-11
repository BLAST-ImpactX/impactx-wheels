# Note: see Dockerfile in `dev` branch for recipes, too!
# see also https://github.com/matthew-brett/multibuild/blob/devel/library_builders.sh

set -eu -o pipefail

BUILD_PREFIX="${BUILD_PREFIX:-/usr/local}"

# https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-runners-and-hardware-resources
if [ "$(uname -s)" = "Darwin" ]
then
    CPU_COUNT="${CPU_COUNT:-3}"
    SUDO="sudo"
else
    CPU_COUNT="${CPU_COUNT:-4}"
    SUDO=""
fi

function install_buildessentials {
    if [ -e buildessentials-stamp ]; then return; fi

    if [ "$(uname -s)" = "Darwin" ]
    then
        # Cleanup:
        #   - Travis-CI macOS ships a pre-installed HDF5
        brew unlink hdf5 || true
        brew uninstall --ignore-dependencies hdf5 || true
        rm -rf /usr/local/Cellar/hdf5
    fi

    # musllinux: Alpine Linux
    #   pip, tar tool, cmath
    APK_FOUND=$(which apk >/dev/null && { echo 0; } || { echo 1; })
    if [ $APK_FOUND -eq 0 ]; then
        apk add py3-pip tar

    # manylinux: RHEL/Centos based
    #   static libc, tar tool, CMake dependencies
    elif [ "$(uname -s)" = "Linux" ]
    then
        yum check-update -y || true
        yum -y install    \
            glibc-static  \
            tar

        CMAKE_FOUND=$(which cmake >/dev/null && { echo 0; } || { echo 1; })
        if [ $CMAKE_FOUND -ne 0 ]
        then
          yum -y install openssl-devel
          curl -sLo cmake-3.17.1.tar.gz \
              https://github.com/Kitware/CMake/releases/download/v3.17.1/cmake-3.17.1.tar.gz
          tar -xzf cmake-*.gz
          cd cmake-*
          ./bootstrap                                \
              --parallel=${CPU_COUNT}                \
              --                                     \
              -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX}
          make -j${CPU_COUNT}
          make install
          cd ..
          rm cmake-*.tar.gz
        fi

        # manylinux: avoid picking up a static libpthread in blosc
        # (also: those libs lack -fPIC)
        rm -f /usr/lib/libpthread.a   /usr/lib/libm.a   /usr/lib/librt.a
        rm -f /usr/lib64/libpthread.a /usr/lib64/libm.a /usr/lib64/librt.a
    fi

    python3 -m pip install -U pip setuptools wheel
    python3 -m pip install -U scikit-build
    python3 -m pip install -U "cmake<4"
    python3 -m pip install -U "patch==1.*"

    touch buildessentials-stamp
}

function build_amrex {
    if [ -e amrex-stamp ]; then return; fi

    AMREX_VERSION="25.12"

    curl -sLO https://github.com/AMReX-Codes/amrex/releases/download/${AMREX_VERSION}/amrex-${AMREX_VERSION}.tar.gz
    file amrex*.tar.gz
    tar xzf amrex-${AMREX_VERSION}.tar.gz
    rm amrex*.tar.gz

    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    PATH=${CMAKE_BIN}:${PATH} cmake    \
      -S amrex                         \
      -B build-amrex                   \
      -DAMReX_AMRLEVEL=OFF             \
      -DAMReX_EB=ON                    \
      -DAMReX_ENABLE_TESTS=OFF         \
      -DAMReX_FFT=ON                   \
      -DAMReX_FORTRAN=OFF              \
      -DAMReX_FORTRAN_INTERFACES=OFF   \
      -DAMReX_GPU_BACKEND=NONE         \
      -DAMReX_OMP=OFF                  \
      -DAMReX_LINEAR_SOLVERS_EM=ON     \
      -DAMReX_LINEAR_SOLVERS_INCFLO=ON \
      -DAMReX_MPI=OFF                  \
      -DAMReX_PARTICLES=ON             \
      -DAMReX_PROBINIT=OFF             \
      -DAMReX_PIC=ON                   \
      -DAMReX_SPACEDIM=3               \
      -DAMReX_TINY_PROFILE=ON          \
      -DAMReX_BUILD_SHARED_LIBS=ON     \
      -DBUILD_SHARED_LIBS=OFF          \
      -DCMAKE_BUILD_TYPE=Release       \
      -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX}

    PATH=${CMAKE_BIN}:${PATH} cmake --build build-amrex --parallel ${CPU_COUNT}
    PATH=${CMAKE_BIN}:${PATH} ${SUDO} cmake --build build-amrex --target install

    rm -rf build-amrex

    touch amrex-stamp
}

function build_fftw {
    if [ -e fftw-stamp ]; then return; fi

    FFTW_VERSION="3.3.10"

    curl -sLO https://www.fftw.org/fftw-$FFTW_VERSION.tar.gz
    file fftw*.tar.gz
    tar xzf fftw-$FFTW_VERSION.tar.gz
    rm fftw*.tar.gz

    # DOUBLE
    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    PATH=${CMAKE_BIN}:${PATH} cmake \
      -S fftw-*                  \
      -B build-fftw              \
      -DBUILD_SHARED_LIBS=OFF    \
      -DBUILD_TESTS=OFF          \
      -DDISABLE_FORTRAN=ON       \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX} \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5

    PATH=${CMAKE_BIN}:${PATH} cmake --build build-fftw --parallel ${CPU_COUNT}
    PATH=${CMAKE_BIN}:${PATH} ${SUDO} cmake --build build-fftw --target install

    rm -rf build-fftw

    # SINGLE
    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    PATH=${CMAKE_BIN}:${PATH} cmake \
      -S fftw-*                  \
      -B build-fftw              \
      -DBUILD_SHARED_LIBS=OFF    \
      -DBUILD_TESTS=OFF          \
      -DDISABLE_FORTRAN=ON       \
      -DENABLE_FLOAT=ON          \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX} \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5

    PATH=${CMAKE_BIN}:${PATH} cmake --build build-fftw --parallel ${CPU_COUNT}
    PATH=${CMAKE_BIN}:${PATH} ${SUDO} cmake --build build-fftw --target install

    rm -rf build-fftw

    touch fftw-stamp
}

function build_hdf5 {
    if [ -e hdf5-stamp ]; then return; fi

    curl -sLo hdf5-1.12.2.tar.gz \
        https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.12/hdf5-1.12.2/src/hdf5-1.12.2.tar.gz
    file hdf5*.tar.gz
    tar -xzf hdf5*.tar.gz
    rm hdf5*.tar.gz
    cd hdf5-*

    # macOS cross-compile
    HOST_ARG=""
    #   heavily based on conda-forge hdf5-feedstock and h5py's cibuildwheel instructions
    #   https://github.com/conda-forge/hdf5-feedstock/blob/cbbd57d58f7f5350ca679eaad49354c11dd32b95/recipe/build.sh#L53-L80
    if [[ "${CMAKE_OSX_ARCHITECTURES-}" == "arm64" ]]; then
        # https://github.com/h5py/h5py/blob/fcaca1d1b81d25c0d83b11d5bdf497469b5980e9/ci/configure_hdf5_mac.sh
        # from https://github.com/conda-forge/hdf5-feedstock/commit/2cb83b63965985fa8795b0a13150bf0fd2525ebd
        export ac_cv_sizeof_long_double=8
        export hdf5_cv_ldouble_to_long_special=no
        export hdf5_cv_long_to_ldouble_special=no
        export hdf5_cv_ldouble_to_llong_accurate=yes
        export hdf5_cv_llong_to_ldouble_correct=yes
        export hdf5_cv_disable_some_ldouble_conv=no
        export hdf5_cv_system_scope_threads=yes
        export hdf5_cv_printf_ll="l"

        HOST_ARG="--host=aarch64-apple-darwin"

        curl -sLo osx_cross_configure.patch \
            https://raw.githubusercontent.com/h5py/h5py/fcaca1d1b81d25c0d83b11d5bdf497469b5980e9/ci/osx_cross_configure.patch
        python3 -m patch -p 0 -d . osx_cross_configure.patch

        curl -sLo osx_cross_src_makefile.patch \
            https://raw.githubusercontent.com/h5py/h5py/fcaca1d1b81d25c0d83b11d5bdf497469b5980e9/ci/osx_cross_src_makefile.patch
        #python3 -m patch -p 0 -d . osx_cross_src_makefile.patch
        patch -p 0 < osx_cross_src_makefile.patch
    fi

    ./configure \
        --disable-parallel \
        --disable-shared   \
        --enable-static    \
        --enable-tests=no  \
        --with-zlib=${BUILD_PREFIX} \
        ${HOST_ARG}        \
        --prefix=${BUILD_PREFIX}

    if [[ "${CMAKE_OSX_ARCHITECTURES-}" == "arm64" ]]; then
        (
        # https://github.com/h5py/h5py/blob/fcaca1d1b81d25c0d83b11d5bdf497469b5980e9/ci/configure_hdf5_mac.sh - build_h5detect
        mkdir -p native-build/bin
        pushd native-build/bin

        # MACOSX_DEPLOYMENT_TARGET is for the target_platform and not for build_platform
        unset MACOSX_DEPLOYMENT_TARGET

        CFLAGS="" $CC ../../src/H5detect.c -I ../../src/ -o H5detect
        CFLAGS="" $CC ../../src/H5make_libsettings.c -I ../../src/ -o H5make_libsettings
        popd
        )
        export PATH="$(pwd)/native-build/bin:$PATH"
    fi

    make -j${CPU_COUNT}
    ${SUDO} make install
    cd ..

    touch hdf5-stamp
}

function build_zlib {
    if [ -e zlib-stamp ]; then return; fi

    ZLIB_VERSION="1.2.13"

    curl -sLO https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz
    file zlib*.tar.gz
    tar xzf zlib-$ZLIB_VERSION.tar.gz
    rm zlib*.tar.gz

    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    PATH=${CMAKE_BIN}:${PATH} cmake \
      -S zlib-*     \
      -B build-zlib \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX} \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5

    PATH=${CMAKE_BIN}:${PATH} cmake --build build-zlib --parallel ${CPU_COUNT}
    PATH=${CMAKE_BIN}:${PATH} ${SUDO} cmake --build build-zlib --target install
    ${SUDO} rm -rf ${BUILD_PREFIX}/lib/libz.*dylib ${BUILD_PREFIX}/lib/libz.*so

    rm -rf build-zlib

    touch zlib-stamp
}

# static libs need relocatable symbols for linking to shared python lib
export CFLAGS+=" -fPIC"
export CXXFLAGS+=" -fPIC"

# compiler hints for macOS cross-compiles
#   https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary
if [[ "${CMAKE_OSX_ARCHITECTURES-}" == "arm64" ]]; then
    export CC="/usr/bin/clang"
    export CXX="/usr/bin/clang++"
    export CFLAGS+=" -arch arm64"
    export CPPFLAGS+=" -arch arm64"
    export CXXFLAGS+=" -arch arm64"
fi

install_buildessentials
build_fftw
build_zlib
build_hdf5
build_amrex
