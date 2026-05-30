set CURRENTDIR="%cd%"

set BUILD_PREFIX="C:\Program Files (x86)"
set CPU_COUNT="4"

echo "CFLAGS: %CFLAGS%"
echo "CXXFLAGS: %CXXFLAGS%"
echo "LDFLAGS: %LDFLAGS%"

goto:main

:install_buildessentials
  python -m pip install --upgrade pip setuptools wheel
  python -m pip install --upgrade "cmake<4"
  python -m pip install --upgrade delvewheel
  python -m pip install --upgrade "patch==1.*"
exit /b 0

:build_amrex
  if exist amrex-stamp exit /b 0

  set "AMREX_VERSION=26.05"

  curl -sLo "amrex-%AMREX_VERSION%.zip" ^
    "https://github.com/AMReX-Codes/amrex/archive/refs/tags/%AMREX_VERSION%.zip"
  powershell Expand-Archive "amrex-%AMREX_VERSION%.zip" -DestinationPath dep-amrex

  dir

  cmake -S dep-amrex\amrex-%AMREX_VERSION%   ^
      -B build-amrex                   ^
      -DAMReX_AMRLEVEL=OFF             ^
      -DAMReX_EB=ON                    ^
      -DAMReX_ENABLE_TESTS=OFF         ^
      -DAMReX_FFT=ON                   ^
      -DAMReX_FORTRAN=OFF              ^
      -DAMReX_FORTRAN_INTERFACES=OFF   ^
      -DAMReX_GPU_BACKEND=NONE         ^
      -DAMReX_OMP=OFF                  ^
      -DAMReX_LINEAR_SOLVERS_EM=ON     ^
      -DAMReX_LINEAR_SOLVERS_INCFLO=ON ^
      -DAMReX_MPI=OFF                  ^
      -DAMReX_PARTICLES=ON             ^
      -DAMReX_PROBINIT=OFF             ^
      -DAMReX_PIC=ON                   ^
      -DAMReX_SPACEDIM=3               ^
      -DAMReX_TINY_PROFILE=ON          ^
      -DAMReX_BUILD_SHARED_LIBS=ON     ^
      -DBUILD_SHARED_LIBS=OFF          ^
      -DCMAKE_BUILD_TYPE=Release       ^
      -DCMAKE_INSTALL_PREFIX=%BUILD_PREFIX%\AMReX
  if errorlevel 1 exit 1

  cmake --build build-amrex --config Release --parallel %CPU_COUNT%
  if errorlevel 1 exit 1

  cmake --build build-amrex --target install --config Release
  if errorlevel 1 exit 1

  rmdir /s /q build-amrex
  if errorlevel 1 exit 1

  break > amrex-stamp
  if errorlevel 1 exit 1
exit /b 0

:build_fftw
  if exist fftw-stamp exit /b 0

  curl -sLo fftw-3.3.10.zip ^
    https://fftw.org/pub/fftw/fftw-3.3.10.zip
  powershell Expand-Archive fftw-3.3.10.zip -DestinationPath dep-fftw

  :: DOUBLE
  cmake -S dep-fftw\fftw-3.3.10 -B build-fftw ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DBUILD_TESTS=OFF       ^
    -DDISABLE_FORTRAN=ON    ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  if errorlevel 1 exit 1

  cmake --build build-fftw --config Release --parallel %CPU_COUNT%
  if errorlevel 1 exit 1

  cmake --build build-fftw --target install --config Release
  if errorlevel 1 exit 1

  rmdir /s /q build-fftw
  if errorlevel 1 exit 1

  :: SINGLE
  cmake -S dep-fftw\fftw-3.3.10 -B build-fftw ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DBUILD_TESTS=OFF       ^
    -DDISABLE_FORTRAN=ON    ^
    -DENABLE_FLOAT=ON       ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  if errorlevel 1 exit 1

  cmake --build build-fftw --config Release --parallel %CPU_COUNT%
  if errorlevel 1 exit 1

  cmake --build build-fftw --target install --config Release
  if errorlevel 1 exit 1

  rmdir /s /q build-fftw
  if errorlevel 1 exit 1

  break > fftw-stamp
  if errorlevel 1 exit 1
exit /b 0

:build_hdf5
  if exist hdf5-stamp exit /b 0

  curl -sLo hdf5-1.14.1-2.zip ^
    https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.14/hdf5-1.14.1/src/hdf5-1.14.1-2.zip
  powershell Expand-Archive hdf5-1.14.1-2.zip -DestinationPath dep-hdf5

  cmake -S dep-hdf5\hdf5-1.14.1-2 -B build-hdf5 ^
    -DCMAKE_BUILD_TYPE=Release  ^
    -DCMAKE_VERBOSE_MAKEFILE=ON ^
    -DBUILD_SHARED_LIBS=OFF     ^
    -DBUILD_TESTING=OFF         ^
    -DTEST_SHELL_SCRIPTS=OFF    ^
    -DHDF5_BUILD_CPP_LIB=OFF    ^
    -DHDF5_BUILD_EXAMPLES=OFF   ^
    -DHDF5_BUILD_FORTRAN=OFF    ^
    -DHDF5_BUILD_HL_LIB=OFF     ^
    -DHDF5_BUILD_TOOLS=OFF      ^
    -DHDF5_ENABLE_PARALLEL=OFF  ^
    -DHDF5_ENABLE_SZIP_SUPPORT=OFF ^
    -DHDF5_ENABLE_Z_LIB_SUPPORT=ON ^
    -DZLIB_USE_STATIC_LIBS=ON   ^
    -DCMAKE_INSTALL_PREFIX=%BUILD_PREFIX%\HDF5 ^
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  if errorlevel 1 exit 1

  cmake --build build-hdf5 --config Release --parallel %CPU_COUNT%
  if errorlevel 1 exit 1

  cmake --build build-hdf5 --target install --config Release
  if errorlevel 1 exit 1

  rmdir /s /q build-hdf5
  if errorlevel 1 exit 1

  break > hdf5-stamp
  if errorlevel 1 exit 1
exit /b 0

:build_zlib
  if exist zlib-stamp exit /b 0

  curl -sLo zlib-1.3.1.zip ^
    https://github.com/madler/zlib/archive/v1.3.1.zip
  powershell Expand-Archive zlib-1.3.1.zip -DestinationPath dep-zlib

  cmake -S dep-zlib\zlib-1.3.1 -B build-zlib ^
    -DBUILD_SHARED_LIBS=ON ^
    -DCMAKE_BUILD_TYPE=Release
  if errorlevel 1 exit 1
:: Manually-specified variables were not used by the project:
::   CMAKE_BUILD_TYPE

  cmake --build build-zlib --config Release --parallel %CPU_COUNT%
  if errorlevel 1 exit 1

  cmake --build build-zlib --target install --config Release
  if errorlevel 1 exit 1

  set "zlib_dll=%BUILD_PREFIX:~1,-1%/zlib/bin/zlib1.dll"
  set "zlib_dll=%zlib_dll:/=\%"
  del "%zlib_dll%"
  if errorlevel 1 exit 1

  rmdir /s /q build-zlib
  if errorlevel 1 exit 1

  break > zlib-stamp
  if errorlevel 1 exit 1
exit /b 0

:main
call :install_buildessentials
call :build_fftw
call :build_zlib
:: build_bzip2
:: build_szip
call :build_hdf5
call :build_amrex
