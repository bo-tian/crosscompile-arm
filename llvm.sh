#!/bin/sh

source ./target.conf

CFLAGS=${BOOSTRAP_CFLAGS}
CXXFLAGS=${BOOTSTAP_CFLAGS}

# LLVM suite release tag
ver="origin/release_60"

repo="${REPO}/llvm"
llvm="${repo}/llvm"
clang="${llvm}/tools/clang"
lld="${llvm}/tools/lld"
libcxx="${llvm}/projects/libcxx"
libcxxabi="${llvm}/projects/libcxxabi"
libunwind="${llvm}/projects/libunwind"
rtlib="${llvm}/projects/compiler-rt"

# Obselete, openwrt libstdc++ is version 3, while libcxx requires libstdc++ version above 4.8.
#armv7_a15_openwrt="-v -target armv7-a-linux-gnueabihf -mcpu=cortex-a15 -mfpu=vfpv4 --sysroot=/home/router/lede/staging_dir/toolchain-arm_cortex-a15+neon-vfpv4_gcc-7.3.0_musl_eabi -rtlib=compiler-rt" 

clone_llvm(){
	echo "=============== cloning llvm suite ==============="
	pushd ${repo}
	git clone https://github.com/llvm-mirror/llvm.git
	cd ${llvm}/projects/
	git clone https://github.com/llvm-mirror/compiler-rt.git
	git clone https://github.com/llvm-mirror/libunwind.git
	git clone https://github.com/llvm-mirror/libcxxabi.git
	git clone https://github.com/llvm-mirror/libcxx.git
        cd ${llvm}/tools/
	git clone https://github.com/llvm-mirror/lld.git
	git clone https://github.com/llvm-mirror/clang.git
	popd
}

update_repo(){
	pushd "$1"
	git checkout master
	git pull
	git checkout ${ver}
	popd
}

update_llvm(){
	update_repo "${llvm}"
	update_repo "${clang}"
	update_repo "${lld}"
	update_repo "${libcxx}"
	update_repo "${libcxxabi}"
	update_repo "${libunwind}"
	update_repo "${rtlib}"
}

if [ ! -d ${BUILD} ]; then
	mkdir -p ${BUILD}
fi

compile_standalone(){
	export CC
	export CXX
	export AR

	# libunwind is the exception handle library, which is needed by libcxxabi as well as libcxx. The equivalent library in glibc is libgcc_eh/libgcc_s.
	# libcxxabi is the abi definition library, which is needed by libcxx. The equivalent library in glibc is libsup++.
	# Add -Qunused-arguments to mitigate llvm bug which falsely reports compiler tool not supporting -fPIC.
	CFLAGS="${CFLAGS} -Qunused-arguments"
	CXXFLAGS="${CXXFLAGS} -Qunused-arguments"

	compile_rtlib() {
		if [ -d "${BUILD}/compiler-rt" ]; then
			rm "${BUILD}/compiler-rt" -r
		fi	

		mkdir "${BUILD}/compiler-rt"
		pushd "${BUILD}/compiler-rt"
		# http://www.llvm.org/docs/HowToCrossCompileBuiltinsOnArm.html
		# COMPILER_RT_RUNTIME_LIBRARY=buildins: telling compiler to use compiler-rt instead of libgcc_s
		# COMPILER_RT_SUPPORTED_ARCH=armhf: specify the compiler-rt arch, arm, armhf, etc.
		# CMAKE_C_COMPILER_TARGET=armv7a-linux-gnueabihf: compiler-rt has flaw in ressolving target triple in the form armv7-a-linux-gnueabihf, which it resolve as armv7 instead of armv7a. armv7 doesn't support hard float fpu, while armv7a does. So revise the triple from armv7-a to armv7a.
		# CMAKE_AR: full path llvm-ar. Otherwize compiler-rt will failed in not finding it.
		# COMPILER_RT_DEFAULT_TARGET_ONLY=True: forcefully have compiler-rt use CMAKE_C_COMPILER_TARGET triple to get the arch info(arm, armhf, etc.).
		cmake -G "Unix Makefiles" ${rtlib} -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_CROSSCOMPILING=True -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_BUILD_TYPE=Release -DCOMPILER_RT_STANDALONE_BUILD=ON -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF -DCLANG_DEFAULT_RTLIB=compiler-rt -DCMAKE_C_COMPILER_TARGET=${TRIPLE} -DCMAKE_CXX_COMPILER_TARGET=${TRIPLE} -DCMAKE_ASM_FLAGS="${CFLAGS}" -DCOMPILER_RT_RUNTIME_LIBRARY=builtins -DCOMPILER_RT_SUPPORTED_ARCH=armhf -DCOMPILER_RT_DEFAULT_TARGET_ONLY=True -DCMAKE_AR=/usr/bin/llvm-ar
		if [ "$?" != 0 ]; then
			echo "compiler-rt configure failed!"
			exit 1
		fi

		make
		if [ "$?" != 0 ]; then
			echo "commpiler-rt building failed!"
			exit 1
		fi

		echo ======================= compiler-rt is OK =================================
		cp -v lib/../linux/libclang_rt.builtins-armhf.a ${SYSROOT}/lib/
		echo ======================= compiler-rt is OK =================================
		popd
	}

	compile_libunwind() {
		if [ -d "${BUILD}/libunwind" ]; then
			rm ${BUILD}/libunwind -r
		fi	

		mkdir ${BUILD}/libunwind
		pushd ${BUILD}/libunwind

		# https://bcain-llvm.readthedocs.io/projects/libunwind/en/latest/BuildingLibunwind/
		# unwind depends on cross compiled libunwind -lunwind
		cmake -G "Unix Makefiles" ${libunwind} -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_CROSSCOMPILING=True -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_LIBCXX=ON -DLIBUNWIND_USE_COMPILER_RT=True -DCMAKE_CXX_FLAGS="${CXXFLAGS} -I${libcxxabi}/include/ -I${libcxx}/include/" -DCMAKE_C_FLAGS="${CFLAGS} -I${libcxxabi}/include/ -lunwind" -DLIBUNWIND_TARGET_TRIPLE=${TRIPLE}
		if [ "$?" != 0 ]; then
			echo libunwind configure failed!
			exit 1
		fi

		make
		if [ "$?" != 0 ]; then
			echo libunwind building failed!
			exit 1
		fi

		echo ======================= libunbind is OK =================================
		cp -v lib/libunwind.a ${SYSROOT}/lib/
		cp -v lib/libunwind.so* ${SYSROOT}/lib/
		cp -v lib/libunwind.so* ${TARGET}/lib/
		echo ======================= libunbind is OK =================================
		popd
	}

	compile_libcxxabi() {
		if [ -d "${BUILD}/libcxxabi" ]; then
			rm ${BUILD}/libcxxabi -r
		fi

		mkdir ${BUILD}/libcxxabi
		pushd ${BUILD}/libcxxabi

		# https://libcxx.llvm.org/docs/BuildingLibcxx.html
		# Add LLVM_EANBLE_LIBCXX=ON to use libc++ library. Othercase libcxxabi will forcefully use nonexisted libstdc++ above 4.8 version.
		# -DHAVE_LIBUNWIND=True: This option is needed to bundle the libunbind and libcxxabi, but LLVM standalone doesn't support this.
		cmake -G "Unix Makefiles" ${libcxxabi} -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_CROSSCOMPILING=True -DLIBCXXABI_LIBCXX_INCLUDES="${libcxx}/include" -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DLLVM_ENABLE_LIBCXX=ON -DLIBCXXABI_USE_COMPILER_RT=True -DLIBCXXABI_TARGET_TRIPLE=armv7-a-linux-gnueabihf -DLIBCXXABI_USE_LLVM_UNWINDER=ON -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON -DLIBCXXABI_LIBUNWIND_INCLUDES="${libunwind}/include" 
		if [ "$?" != 0 ]; then
			echo libcxxabi configure failed!
			exit 1
		fi

		make
		if [ "$?" != 0 ]; then
			echo libcxxabi building failed!
			exit 1
		fi

		echo ======================= libcxxabi is OK =================================
		cp -v lib/libc++abi.a ${SYSROOT}/lib/
		cp -v lib/libc++abi.so* ${SYSROOT}/lib/
		cp -v lib/libc++abi.so* ${TARGET}/lib/
		echo ======================= libcxxabi is OK =================================
		sleep 2
		popd
	}

	compile_libcxx() {
		if [ -d "${BUILD}/libcxx" ]; then
			rm ${BUILD}/libcxx -r
		fi	

		mkdir ${BUILD}/libcxx
		pushd ${BUILD}/libcxx
		# https://libcxx.llvm.org/docs/BuildingLibcxx.html:
		# https://groups.google.com/forum/#!topic/llvm-dev/OHc0637gDr8:
		# Default LIBCXX_ENABLE_EXCEPTIONS=ON: enable exception handle. try...catch directive need this.
		# Default LIBCXX_HAS_MUSL_LIBC=OFF: "base_table not defined" coredump in binary. Since we are using musl, turn it on.
		# -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON: TypeError: 'NoneType' object is not iterable error. Experimental feature, bundle libcxxabi and libcxx. Need setting LIBCXX_CXX_ABI_LIBRARY_PATH.
		cmake -G "Unix Makefiles" ${libcxx} -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_CROSSCOMPILING=True -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS} -nostdinc++ -stdlib=libc++" -DCMAKE_BUILD_TYPE=Release -DLIBCXX_HAS_MUSL_LIBC=ON -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_CXX_ABI_INCLUDE_PATHS=${libcxxabi}/include -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_TARGET_TRIPLE=armv7-a-linux-gnueabihf -DLIBCXXABI_USE_LLVM_UNWINDER=ON -DHAVE_LIBUNWIND=True -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON -DLIBCXX_CXX_ABI_LIBRARY_PATH="${SYSROOT}/lib/" 
		if [ "$?" != 0 ]; then
			echo libcxx configure failed!
			exit 1
		fi

		make
		if [ "$?" != 0 ]; then
			echo libcxx building failed!
			exit 1
		fi

		echo ======================= libcxx is OK =================================
		cp -v lib/libc++.a ${SYSROOT}/lib/
		cp -v lib/libc++.so* ${SYSROOT}/lib/
		cp -v lib/libc++.so* ${TARGET}/lib/
		echo ======================= libcxx is OK =================================
		popd
	}

	all() {
		compile_libunwind
		compile_libcxxabi
		compile_libcxx
	}

	case "$1" in
		"rt"*)
			compile_rtlib
			;;
		*"un"*)
			compile_libunwind
			;;
		*"abi")
			compile_libcxxabi
			;;
		*"xx")
			compile_libcxx
			;;
		"all")
			all
			;;
		*)
			echo "Subcommands are available, please specify [rt]lib/lib[un]wind/libcxx[abi]/libc[xx]/all to build"
			;;
	esac
}

compile_llvm() {
	export CXX
	export CC

	# libunwind is the exception handle library, which is needed by libcxxabi as well as libcxx. The equivolent library used by glibc is libgcc_eh/libgcc_s.
	# libcxxabi is the abi definition library, which is needed by libcxx. The equivolent library used by glibc is libsup++.
	# Add -Qunused-arguments to mitigate llvm bug which false reports compiler tool not supporting -fPIC.
	CFLAGS="${CFLAGS} -Qunused-arguments -lunwind"
	CXXFLAGS="${CXXFLAGS} -Qunused-arguments -I${libcxx}/include -I${libunwind}/include"

	compile_llvm() {
		if [ -d "${BUILD}/llvm" ]; then
			rm -r ${BUILD}/llvm
		fi	

		mkdir ${BUILD}/llvm
		pushd ${BUILD}/llvm

		# llvm bug, to bundle libunwind/libcxxabi/libcxx in one, we need to explicitly build libcxxabi and specify libcxxabi library location in LIBCXX_CXX_ABI_LIBRARY_PATH.
		cmake -G "Unix Makefiles" ${llvm} -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_CROSSCOMPILING=True -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_BUILD_TYPE=Release -DLIBCXX_HAS_MUSL_LIBC=ON -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_CXX_ABI_INCLUDE_PATHS=${libcxxabi}/include -DLIBCXX_USE_COMPILER_RT=True -DLIBCXX_TARGET_TRIPLE=${TRIPLE} -DLLVM_ENABLE_LIBCXX=True -DLLVM_TARGETS_TO_BUILD=ARM -DLLVM_ENABLE_LIBCXX=True  -DLIBCXX_CXX_ABI_LIBRARY_PATH="lib/" -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON -DLIBCXXABI_ENABLE_STATIC_UNWINDER=True -DLIBCXXABI_USE_LLVM_UNWINDER=ON -DLIBUNWIND_USE_COMPILER_RT=True -DLIBCXXABI_USE_COMPILER_RT=True -DLIBUNWIND_TARGET_TRIPLE=${TRIPLE} -DLIBCXXABI_TARGET_TRIPLE=${TRIPLE} -DCMAKE_ASM_FLAGS="${CFLAGS}" -DCMAKE_C_COMPILER_TARGET=${TRIPLE} -DCMAKE_CXX_COMPILER_TARGET=${TRIPLE} -DCOMPILER_RT_DEFAULT_TARGET_ONLY=True -DCOMPILER_RT_RUNTIME_LIBRARY=buildins -DCMAKE_AR=/usr/bin/llvm-ar -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF 
		if [ "$?" != 0 ]; then
			echo llvm configure failed!
			exit 1
		fi

		if [ -z "$1" -o "$1" = "libcxx" ]; then
			make cxxabi
			make cxx
			if [ "$?" != 0 ]; then
				echo libcxx building failed!
				exit 1
			fi
			echo ======================= libcxx is OK =================================
			cp -v lib/libc++.a ${SYSROOT}/lib/
			cp -v lib/libc++.so* ${SYSROOT}/lib/
			# Some c application still needs libunwind library
			cp -v lib/libunwind.a ${SYSROOT}/lib/
			mkdir -vp ${SYSROOT}/usr/include/c++ 
			cp -rv ${libcxx}/include/* ${SYSROOT}/usr/include/c++/
			cp -rv ${libabicxx}/include/* ${SYSROOT}/usr/include/c++/
			cp -rv ${libunwind}/include/* ${SYSROOT}/usr/include/c++/

			cp -v lib/libc++.so* ${TARGET}/lib/
			echo ======================= libcxx is OK =================================
		fi

		if [ -z "$1" -o "$1" = "compiler-rt" ]; then
			make "compiler-rt"
			if [ "$?" != 0 ]; then
				echo "compiler-rt building failed!"
				exit 1
			fi
			echo ======================= compiler-rt is OK =================================
			rtlib=`find lib/ -name libclang_rt.builtins\*.a`
			cp -v ${rtlib} ${SYSROOT}/lib/
			echo ======================= compiler-rt is OK =================================
		fi
		popd
	}
	case "$1" in
		*"xx")
			compile_llvm "libcxx"
			;;
		"rt"*)
			compile_llvm "compiler-rt"
			;;
		"all")
			compile_llvm
			;;
		*)
			echo "Subccommands are available, please specify  libc[xx]/[rt]lib/all to build."
			;;
	esac
}

case "$1" in
	"ll"*)
		shift
		compile_llvm "$1"
		;;
	"st"*)
		shift
		compile_standalone "$1"
		;;
	"up"*)
		update_llvm
		;;
	"in"*)
		clone_llvm
		;;
	*)
		echo "Subcommands are alvailable, please specify [in]it/[up]date/[st]andalone/[ll]vm."
esac
