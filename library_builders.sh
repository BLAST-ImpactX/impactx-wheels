# Note: see Dockerfile in `dev` branch for recipes, too!
# see also https://github.com/matthew-brett/multibuild/blob/devel/library_builders.sh

set -eu -o pipefail

# https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-runners-and-hardware-resources
if [ "$(uname -s)" = "Darwin" ]
then
    CPU_COUNT="${CPU_COUNT:-3}"
    SUDO="sudo"
else
    CPU_COUNT="${CPU_COUNT:-4}"
    SUDO=""
fi

# Common curl options: retry transient network/mirror failures (used everywhere).
CURL_RETRY="--retry 5 --retry-delay 3"

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
          curl ${CURL_RETRY} -fsSL -o cmake-3.17.1.tar.gz \
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

        # manylinux: avoid picking up a static libpthread (also: lacks -fPIC)
        rm -f /usr/lib/libpthread.a   /usr/lib/libm.a   /usr/lib/librt.a
        rm -f /usr/lib64/libpthread.a /usr/lib64/libm.a /usr/lib64/librt.a
    fi

    touch buildessentials-stamp
}

function install_pyessentials {
    if [ -e pyessentials-stamp ]; then return; fi

    python3 -m pip install -U pip setuptools wheel
    python3 -m pip install -U scikit-build
    python3 -m pip install -U "cmake<4"
    python3 -m pip install -U "patch==1.*"

    touch pyessentials-stamp
}

function build_amrex {
    if [ -e amrex-stamp ]; then return; fi

    AMREX_VERSION="26.06"

    curl ${CURL_RETRY} -fsSL -o amrex-${AMREX_VERSION}.tar.gz \
        https://github.com/AMReX-Codes/amrex/releases/download/${AMREX_VERSION}/amrex-${AMREX_VERSION}.tar.gz
    file amrex*.tar.gz
    tar xzf amrex-${AMREX_VERSION}.tar.gz
    rm amrex*.tar.gz

    # WASM: the wasm32 ABI has 4-byte pointers but 8-byte double, so AMReX's
    # parser_number (alignas(parser_node)) underaligns its double.
    # Fixed in AMReX 26.07+ via https://github.com/AMReX-Codes/amrex/pull/5515
    if [ -n "${EMCMAKE}" ]; then
        patch -p1 -d amrex < .github/amrex-parser-alignment.patch
    fi

    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    PATH=${CMAKE_BIN}:${PATH} ${EMCMAKE} cmake \
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
      -DAMReX_SIMD=${AMREX_SIMD:-OFF}  \
      -DAMReX_SPACEDIM=3               \
      -DAMReX_TINY_PROFILE=ON          \
      -DAMReX_BUILD_SHARED_LIBS=${AMREX_SHARED:-ON} \
      -DBUILD_SHARED_LIBS=OFF          \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_BUILD_TYPE=Release       \
      -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX}

    PATH=${CMAKE_BIN}:${PATH} ${EMMAKE} cmake --build build-amrex --parallel ${CPU_COUNT}
    PATH=${CMAKE_BIN}:${PATH} ${SUDO} ${EMMAKE} cmake --build build-amrex --target install

    rm -rf build-amrex

    touch amrex-stamp
}

function build_fftw {
    if [ -e fftw-stamp ]; then return; fi

    FFTW_VERSION="3.3.10"

    curl ${CURL_RETRY} -fsSL -o fftw-$FFTW_VERSION.tar.gz \
        https://www.fftw.org/fftw-$FFTW_VERSION.tar.gz
    file fftw*.tar.gz
    tar xzf fftw-$FFTW_VERSION.tar.gz
    rm fftw*.tar.gz

    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    # double and single precision; ${EMCMAKE}/${EMMAKE} empty for native, set for WASM
    for fftw_float in "" "-DENABLE_FLOAT=ON"; do
        PATH=${CMAKE_BIN}:${PATH} ${EMCMAKE} cmake \
          -S fftw-*                  \
          -B build-fftw              \
          -DBUILD_SHARED_LIBS=OFF    \
          -DBUILD_TESTS=OFF          \
          -DDISABLE_FORTRAN=ON       \
          ${fftw_float}              \
          -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX} \
          -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        PATH=${CMAKE_BIN}:${PATH} ${EMMAKE} cmake --build build-fftw --parallel ${CPU_COUNT}
        PATH=${CMAKE_BIN}:${PATH} ${SUDO} ${EMMAKE} cmake --build build-fftw --target install
        rm -rf build-fftw
    done

    touch fftw-stamp
}

function build_hdf5 {
    if [ -e hdf5-stamp ]; then return; fi

    curl ${CURL_RETRY} -fsSL -o hdf5-1.12.2.tar.gz \
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

        curl ${CURL_RETRY} -fsSL -o osx_cross_configure.patch \
            https://raw.githubusercontent.com/h5py/h5py/fcaca1d1b81d25c0d83b11d5bdf497469b5980e9/ci/osx_cross_configure.patch
        python3 -m patch -p 0 -d . osx_cross_configure.patch

        curl ${CURL_RETRY} -fsSL -o osx_cross_src_makefile.patch \
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

# WASM/Emscripten: CMake-configured static build of HDF5 for wasm32-emscripten.
# HDF5 1.14.0+ removed the H5detect/H5make_libsettings native code generators,
# which makes cross-compilation via CMake straightforward. The Emscripten-
# specific cache values (no getpwuid/signal, empty exe suffix, PIC) and the
# FE_INVALID patch are taken from usnistgov/libhdf5-wasm.
function build_hdf5_cmake {
    if [ -e hdf5-stamp ]; then return; fi

    HDF5_VERSION="1.14.6"

    curl ${CURL_RETRY} -fsSL -o hdf5-${HDF5_VERSION}.tar.gz \
        https://github.com/HDFGroup/hdf5/releases/download/hdf5_${HDF5_VERSION}/hdf5-${HDF5_VERSION}.tar.gz
    file hdf5*.tar.gz
    tar -xzf hdf5*.tar.gz
    rm hdf5*.tar.gz

    # Emscripten's <fenv.h> may not define FE_INVALID; guard feclearexcept().
    # Vendored verbatim from usnistgov/libhdf5-wasm @ 2069e0a (patches/1.14.6):
    #   https://github.com/usnistgov/libhdf5-wasm/blob/2069e0a2ab8073a1b7f08a10adae0ce6d73905fe/patches/1.14.6/FE_INVALID.patch
    patch -p1 -d hdf5-${HDF5_VERSION} < .github/hdf5-${HDF5_VERSION}-FE_INVALID.patch

    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    PATH=${CMAKE_BIN}:${PATH} emcmake cmake -S hdf5-${HDF5_VERSION} -B build-hdf5 \
        -DCMAKE_BUILD_TYPE=Release                     \
        -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX}         \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON           \
        -DCMAKE_EXECUTABLE_SUFFIX_C=                   \
        -DBUILD_SHARED_LIBS=OFF                        \
        -DBUILD_STATIC_LIBS=ON                         \
        -DBUILD_TESTING=OFF                            \
        -DHDF5_BUILD_TESTS=OFF                         \
        -DHDF5_BUILD_TOOLS=OFF                         \
        -DHDF5_BUILD_UTILS=OFF                         \
        -DHDF5_BUILD_EXAMPLES=OFF                      \
        -DHDF5_BUILD_CPP_LIB=OFF                       \
        -DHDF5_BUILD_HL_LIB=OFF                        \
        -DHDF5_BUILD_FORTRAN=OFF                       \
        -DHDF5_BUILD_JAVA=OFF                          \
        -DHDF5_ENABLE_PARALLEL=OFF                     \
        -DHDF5_ENABLE_THREADSAFE=OFF                   \
        -DHDF5_ENABLE_Z_LIB_SUPPORT=ON                 \
        -DHDF5_ENABLE_SZIP_SUPPORT=OFF                 \
        -DHDF5_USE_ZLIB_STATIC=ON                      \
        -DZLIB_USE_STATIC_LIBS=ON                      \
        -DH5_HAVE_GETPWUID=OFF                         \
        -DH5_HAVE_SIGNAL=OFF
    emmake cmake --build build-hdf5 --parallel ${CPU_COUNT}
    emmake cmake --build build-hdf5 --target install

    rm -rf build-hdf5

    touch hdf5-stamp
}

function build_zlib {
    if [ -e zlib-stamp ]; then return; fi

    ZLIB_VERSION="1.3.1"

    # GitHub release mirror (zlib.net/fossils is flaky and serves HTML on error)
    curl ${CURL_RETRY} -fsSL -o zlib-$ZLIB_VERSION.tar.gz \
        https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz
    file zlib*.tar.gz
    tar xzf zlib-$ZLIB_VERSION.tar.gz
    rm zlib*.tar.gz

    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    # zlib builds both a shared (zlib) and a static (zlibstatic) target, both
    # named libz. On WASM the shared one is downgraded to a static archive, so
    # both write libz.a and race a parallel build -> serialize it on WASM and
    # skip the unused example/minigzip executables.
    ZLIB_NPROC="${CPU_COUNT}"
    [ -n "${EMMAKE}" ] && ZLIB_NPROC=1
    # ${EMCMAKE}/${EMMAKE} are empty for native builds and emcmake/emmake for WASM
    PATH=${CMAKE_BIN}:${PATH} ${EMCMAKE} cmake \
      -S zlib-*     \
      -B build-zlib \
      -DBUILD_SHARED_LIBS=OFF \
      -DZLIB_BUILD_EXAMPLES=OFF \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX} \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5

    PATH=${CMAKE_BIN}:${PATH} ${EMMAKE} cmake --build build-zlib --parallel ${ZLIB_NPROC}
    PATH=${CMAKE_BIN}:${PATH} ${SUDO} ${EMMAKE} cmake --build build-zlib --target install
    ${SUDO} rm -rf ${BUILD_PREFIX}/lib/libz.*dylib ${BUILD_PREFIX}/lib/libz.*so*

    rm -rf build-zlib

    touch zlib-stamp
}

function build_virsimd {
    if [ -e virsimd-stamp ]; then return; fi

    VIRSIMD_VERSION="0.4.4"

    curl ${CURL_RETRY} -fsSL -o vir-simd-$VIRSIMD_VERSION.tar.gz \
        https://github.com/mattkretz/vir-simd/archive/refs/tags/v${VIRSIMD_VERSION}.tar.gz
    file vir-simd*.tar.gz
    tar xzf vir-simd-$VIRSIMD_VERSION.tar.gz
    rm vir-simd*.tar.gz

    # header-only: configure + install only (no compilation)
    PY_BIN=$(which python3)
    CMAKE_BIN="$(${PY_BIN} -m pip show cmake 2>/dev/null | grep Location | cut -d' ' -f2)/cmake/data/bin/"
    PATH=${CMAKE_BIN}:${PATH} cmake \
      -S vir-simd-${VIRSIMD_VERSION} \
      -B build-virsimd \
      -DCMAKE_INSTALL_PREFIX=${BUILD_PREFIX} \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    ${SUDO} cmake --build build-virsimd --target install

    rm -rf build-virsimd

    touch virsimd-stamp
}

if [ "${1:-}" = "wasm" ]; then
    # Cross-compile every C/C++ dependency for wasm32-emscripten into the
    # Emscripten sysroot, where the Pyodide wheel build's find_package() picks
    # them up. The emsdk toolchain is only on PATH after cibuildwheel sets up
    # the pyodide xbuildenv, so this runs in BEFORE_BUILD (not BEFORE_ALL).
    export BUILD_PREFIX="$(em-config CACHE)/sysroot"

    # CMake cross-compile wrappers for Emscripten
    export EMCMAKE="emcmake"
    export EMMAKE="emmake"

    # AMReX is linked statically into both the `amrex` and `impactx` modules. On
    # WASM this still yields ONE AMReX runtime: Pyodide loads the extensions as
    # Emscripten side modules into a global (RTLD_GLOBAL-style) namespace, so the
    # duplicated AMReX symbols are interposed to a single definition at load
    # (verified in CI: amrex.initialized() is True after impactx init). Fully
    # static => no wheel-repair step.
    export AMREX_SHARED="OFF"

    install_pyessentials
    build_zlib
    build_hdf5_cmake
    build_fftw
    build_amrex

    # Static HDF5's CMake config exposes its zlib dependency (ZLIB::ZLIB) but
    # omits find_dependency(ZLIB), so the final wheel link would drop libz. Define
    # ZLIB::ZLIB and force it onto every target; ImpactX setup.py picks this up via
    # IMPACTX_CMAKE_CMAKE_PROJECT_TOP_LEVEL_INCLUDES. Fixed upstream in
    # openPMD-api#1894 (>0.17.1).
    cat > /tmp/impactx-zlibfix.cmake <<EOF
find_package(ZLIB QUIET)
if(NOT TARGET ZLIB::ZLIB)
    add_library(ZLIB::ZLIB STATIC IMPORTED)
    set_target_properties(ZLIB::ZLIB PROPERTIES
        IMPORTED_LOCATION "${BUILD_PREFIX}/lib/libz.a"
        INTERFACE_INCLUDE_DIRECTORIES "${BUILD_PREFIX}/include")
endif()
link_libraries(ZLIB::ZLIB)
EOF

else
    # Installation base path of all deps
    export BUILD_PREFIX="${BUILD_PREFIX:-/usr/local}"

    # CMake cross-compile wrappers for Emscripten are empty for native builds
    export EMCMAKE=""
    export EMMAKE=""

    # native: build a shared AMReX runtime the wheel links against
    export AMREX_SHARED="ON"

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
    install_pyessentials
    build_fftw
    build_zlib
    build_hdf5
    # explicit SIMD (vir-simd) is requested per-arch via AMREX_SIMD
    if [ "${AMREX_SIMD:-OFF}" = "ON" ]; then
        build_virsimd
    fi
    build_amrex
fi
