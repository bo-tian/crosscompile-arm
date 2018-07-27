#!/bin/sh

source ./target.conf

# LLVM suite release tag
ver="origin/release_60"

repo="${REPO}/llvm"
llvm="${repo}/llvm"
clang="${llvm}/tools/clang"
lld="${llvm}/tools/lld"
libcxx="${llvm}/projects/libcxx"
libcxxabi="${llvm}/projects/libcxxabi"
libunwind="${llvm}/projects/libunwind"
librt="${llvm}/projects/compiler-rt"

init () {
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

update_module () {
	pushd "$1"
	git checkout master
	git pull
	git checkout ${ver}
	popd
}

update () {
	update_module "${llvm}"
	update_module "${clang}"
	update_module "${lld}"
	update_module "${libcxx}"
	update_module "${libcxxabi}"
	update_module "${libunwind}"
	update_module "${librt}"
}

standalone_compile () {
	export CC
	export CXX
	export AR

	# libunwind is the exception handle library, which is needed by libcxxabi as well as libcxx. The equivalent library in glibc is libgcc_eh/libgcc_s.
	# libcxxabi is the abi definition library, which is needed by libcxx. The equivalent library in glibc is libsup++.
	# Add -Qunused-arguments to mitigate llvm bug which falsely reports compiler tool not supporting -fPIC.
	CFLAGS="${CFLAGS} -Qunused-arguments ${COMPACT_LIB}"
	CXXFLAGS="${CXXFLAGS} -Qunused-arguments ${COMPACT_LIB}"

	compile_rt() {
		if [ -d "${BUILD}/compiler-rt" ]; then
			rm "${BUILD}/compiler-rt" -r
		fi	
		mkdir -p "${BUILD}/compiler-rt"

#		sed -i s/emutls.c// ${librt}/lib/builtins/CMakeLists.txt
#		sed -i s/eprintf.c// ${librt}/lib/builtins/CMakeLists.txt

		pushd "${BUILD}/compiler-rt"
		# http://www.llvm.org/docs/HowToCrossCompileBuiltinsOnArm.html
		# CMAKE_AR: full path llvm-ar. Otherwise building compiler-rt will fail for not finding it.
		# COMPILER_RT_DEFAULT_TARGET_ONLY=True: forcely instruct compiler-rt to use CMAKE_C_COMPILER_TARGET triple to get the arch info(arm, armhf, etc.).
		# -DCMAKE_CXX_COMPILER_WORKS=True -DCMAKE_C_COMPILER_WORKS=True CMAKE_SIZEOF_VOID_P=4 are tricks used to pass cmake compiler check,
		# since at this time all the cross compiled libraries are nonexistent.
		cmake -G "Unix Makefiles" ${librt} -DCMAKE_CXX_COMPILER_WORKS=True -DCMAKE_C_COMPILER_WORKS=True -DCMAKE_SIZEOF_VOID_P=4 -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_CROSSCOMPILING=True -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_BUILD_TYPE=Release -DCOMPILER_RT_STANDALONE_BUILD=True -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF -DCMAKE_C_COMPILER_TARGET=${TRIPLE} -DCMAKE_CXX_COMPILER_TARGET=${TRIPLE} -DCMAKE_ASM_FLAGS="${CFLAGS}" -DCOMPILER_RT_RUNTIME_LIBRARY=builtins -DCMAKE_AR=`which llvm-ar` -DCOMPILER_RT_DEFAULT_TARGET_ONLY=True 
		if [ "$?" != "0" ]; then
			echo ***************** compiler-rt cmake error ************************
			exit 1
		fi
		make
		if [ "$?" != "0" ]; then
			echo ***************** compiler-rt compile error ************************
			exit 1
		fi

		echo ======================= compiler-rt is OK =================================
		lib=`find lib/ -name libclang_rt.builtins\*.a`
		cp -v ${lib} ${SYSROOT}/lib/
		lib=`find ${SYSROOT}/lib -name libclang_rt.builtins\*.a` 
		echo ---- Dont forget to execute: ----
		echo ---- "\"cp -v ${lib} `clang ${CFLAGS} -print-libgcc-file-name`\"." ----
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
		cmake -G "Unix Makefiles" ${libunwind} -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_CROSSCOMPILING=True -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_LIBCXX=ON -DLIBUNWIND_USE_COMPILER_RT=True -DCMAKE_CXX_FLAGS="${CXXFLAGS} -I${libcxxabi}/include/ -I${libcxx}/include/" -DCMAKE_C_FLAGS="${CFLAGS} -I${libcxxabi}/include/" -DLIBUNWIND_TARGET_TRIPLE=${TRIPLE} -DLIBUNWIND_ENABLE_SHARED=OFF
		if [ "$?" != "0" ]; then
			echo ***************** libunwind cmake error ************************
			exit 1
		fi
		make
		if [ "$?" != "0" ]; then
			echo ***************** libunwind compile error ************************
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
		if [ "$?" != "0" ]; then
			echo ***************** libcxx error ************************
			exit 1
		fi
		make
		if [ "$?" != "0" ]; then
			echo libcxx error
			exit 1
		fi
		echo ======================= libcxx is OK =================================
		cp -v lib/libc++.a ${SYSROOT}/lib/
		cp -v lib/libc++.so* ${SYSROOT}/lib/
		cp -v lib/libc++.so* ${TARGET}/lib/
		echo ======================= libcxx is OK =================================
		popd
	}

	case "$1" in
		*"rt")
			compile_rt
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
		*)
			echo ======================= Compile LLVM =================================
			echo "Subcommands are available, please specify compiler-[rt]/lib[un]wind/libcxx[abi]/libc[xx] to build."
			echo ======================= Compile LLVM =================================
			;;
	esac
}

compile () {
	export CXX
	export CC

	# libunwind is the exception handle library, which is needed by libcxxabi as well as libcxx. The equivolent library used by glibc is libgcc_eh/libgcc_s.
	# libcxxabi is the abi definition library, which is needed by libcxx. The equivolent library used by glibc is libsup++.
	# Add -Qunused-arguments to mitigate llvm bug which false reports compiler tool not supporting -fPIC.
	CFLAGS="${CFLAGS} -Qunused-arguments -ffunction-sections -fdata-sections -Wl,--gc-sections"
	CXXFLAGS="${CXXFLAGS} -Qunused-arguments -I${libcxx}/include -I${libunwind}/include -Wl,--gc-sections"

	compile_llvm() {

		if [ -d "${SYSROOT}/usr/include/c++" ]; then
			echo *** c++ header files already exist, this will hinder the recompile ***
			echo *** Please delete that directory if you want to continue. ***
			exit 1
		fi

		if [ -d "${BUILD}/llvm" ]; then
			rm -r ${BUILD}/llvm
		fi	

		mkdir -p ${BUILD}/llvm
		pushd ${BUILD}/llvm

		# llvm bug, to bundle libunwind/libcxxabi/libcxx in one, we need to explicitly build libcxxabi and specify libcxxabi library location in LIBCXX_CXX_ABI_LIBRARY_PATH.
		cmake -G "Unix Makefiles" ${llvm} -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_CROSSCOMPILING=True -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_BUILD_TYPE=Release -DLIBCXX_HAS_MUSL_LIBC=ON -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_CXX_ABI_INCLUDE_PATHS=${libcxxabi}/include -DLIBCXX_USE_COMPILER_RT=True -DLIBCXX_TARGET_TRIPLE=${TRIPLE} -DLLVM_ENABLE_LIBCXX=True -DLLVM_TARGETS_TO_BUILD=ARM -DLLVM_ENABLE_LIBCXX=True  -DLIBCXX_CXX_ABI_LIBRARY_PATH="lib/" -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON -DLIBCXXABI_ENABLE_STATIC_UNWINDER=True -DLIBCXXABI_USE_LLVM_UNWINDER=ON -DLIBUNWIND_USE_COMPILER_RT=True -DLIBCXXABI_USE_COMPILER_RT=True -DLIBUNWIND_TARGET_TRIPLE=${TRIPLE} -DLIBCXXABI_TARGET_TRIPLE=${TRIPLE} -DCMAKE_ASM_FLAGS="${CFLAGS}" -DCMAKE_C_COMPILER_TARGET=${TRIPLE} -DCMAKE_CXX_COMPILER_TARGET=${TRIPLE} -DCOMPILER_RT_DEFAULT_TARGET_ONLY=True -DCOMPILER_RT_RUNTIME_LIBRARY=buildins -DCMAKE_AR=/usr/bin/llvm-ar -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF -DLIBUNWIND_ENABLE_SHARED=OFF
		if [ "$?" != 0 ]; then
			echo *** llvm cmake error, abort. ***
			exit 1
		fi

		if [ -z "$1" -o "$1" = "libcxx" ]; then
			make cxxabi
			make cxx
			if [ "$?" != 0 ]; then
				echo *** libcxx compile error, abort. ***
				exit 1
			fi
			echo ======================= libcxx is OK =================================
			cp -v lib/libc++.a ${SYSROOT}/lib/
			cp -v lib/libc++.so* ${SYSROOT}/lib/
			# Some c application still needs libunwind library
			cp -v lib/libunwind.a ${SYSROOT}/lib/
			mkdir -pv ${SYSROOT}/usr/include/c++ 
			cp -rv ${libcxx}/include/* ${SYSROOT}/usr/include/c++/
			cp -rv ${libcxxabi}/include/* ${SYSROOT}/usr/include/c++/
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
			rt=`find lib/ -name libclang_rt.builtins\*.a`
			cp -v ${rt} ${SYSROOT}/lib/
			echo ======================= compiler-rt is OK =================================
		fi
		popd
	}

	compile_llvm "libcxx"
}

case "$1" in
	"co"*)
		shift
		compile "$1"
		;;
	"st"*)
		shift
		standalone_compile "$1"
		;;
	"up"*)
		update
		;;
	"in"*)
		init
		;;
	*)
		echo ======================= Compile LLVM =================================
		echo "Subcommands are alvailable, please specify [in]it/[up]date/[st]andalone_compile/[co]mpile."
		echo ======================= Compile LLVM =================================
esac
