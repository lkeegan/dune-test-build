#!/bin/bash

set -e -x

DEPSDIR=${INSTALL_PREFIX}

echo "SME_DEPS_COMMON_VERSION: ${SME_DEPS_COMMON_VERSION}"
echo "DUNE_COPASI_VERSION: ${DUNE_COPASI_VERSION}"
echo "PATH: $PATH"
echo "MSYSTEM: $MSYSTEM"

which g++
which cmake
g++ --version
gcc --version
cmake --version

echo "Downloading static libs for OS_TARGET: $OS_TARGET"
wget "https://github.com/spatial-model-editor/sme_deps_common/releases/download/${SME_DEPS_COMMON_VERSION}/sme_deps_common_${OS_TARGET}.tgz"
tar xf sme_deps_common_${OS_TARGET}.tgz
# copy libs to desired location: workaround for tar -C / not working on windows
if [[ "$OS_TARGET" == *"win"* ]]; then
    mv c/smelibs /c/
    # ls /c/smelibs
else
    $SUDOCMD mv opt/* /opt/
    # ls /opt/smelibs
fi

# add dpl
git clone -b cmake_linux_check_exclude_mac --depth 1 https://github.com/lkeegan/oneDPL
cd oneDPL
mkdir build
cd build
cmake -G "Unix Makefiles" .. \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_C_FLAGS="-fpic -fvisibility=hidden ${TBB_EXTRA_FLAGS}" \
    -DCMAKE_CXX_FLAGS="-fpic -fvisibility=hidden ${TBB_EXTRA_FLAGS}" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DONEDPL_BACKEND="tbb"
make
$SUDOCMD make install
cd ../../


# export vars for duneopts script to read
export DUNE_COPASI_USE_STATIC_DEPS=ON
export CMAKE_INSTALL_PREFIX=$DEPSDIR
export MAKE_OPTIONS="-j2 VERBOSE=1"
export CMAKE_CXX_FLAGS='-fvisibility=hidden'
export BUILD_SHARED_LIBS=OFF
export CMAKE_DISABLE_FIND_PACKAGE_MPI=ON
export DUNE_ENABLE_PYTHONBINDINGS=OFF
export DUNE_PDELAB_ENABLE_TRACING=OFF
export DUNE_COPASI_DISABLE_FETCH_PACKAGE_ExprTk=ON
export DUNE_COPASI_DISABLE_FETCH_PACKAGE_parafields=ON
export DUNE_COPASI_USE_PARAFIELDS=OFF
if [[ $MSYSTEM ]]; then
    # on windows add flags to support large object files
    # https://stackoverflow.com/questions/16596876/object-file-has-too-many-sections
    export CMAKE_CXX_FLAGS='-fvisibility=hidden -Wa,-mbig-obj'
fi

# clone dune-copasi
git clone -b ${DUNE_COPASI_VERSION} --depth 1 https://gitlab.dune-project.org/copasi/dune-copasi.git
cd dune-copasi

# check opts
bash dune-copasi.opts

# build & install dune (excluding dune-copasi)
bash .ci/setup_dune $PWD/dune-copasi.opts

# build & install dune-copasi
bash .ci/install $PWD/dune-copasi.opts

cd ..

# patch DUNE to skip deprecated FindPythonLibs/FindPythonInterp cmake that breaks subsequent FindPython cmake
sed -i.bak 's|find_package(Python|#find_package(Python|' ${INSTALL_PREFIX}/share/dune/cmake/modules/DunePythonCommonMacros.cmake
# also patch out any dune_python_find_package() calls as this can crash on windows
sed -i.bak 's|dune_python_find_package(|#dune_python_find_package(|' ${INSTALL_PREFIX}/share/dune/cmake/modules/DunePythonCommonMacros.cmake
cat ${INSTALL_PREFIX}/share/dune/cmake/modules/DunePythonCommonMacros.cmake

# ls $DEPSDIR
mkdir artefacts
cd artefacts
tar -zcf sme_deps_${OS_TARGET}.tgz $DEPSDIR/*
