#!/bin/sh

#export LIBCC=$SYSROOT/../host/lib/libclang_rt.builtins-arm.a
source ./target.conf

repo="${REPO}/musl"
build="${BUILD}/musl"
prefix="${SYSROOT}"
CC="${CC} ${CFLAGS} -ffunction-sections -fdata-sections"
LDFLAGS="-Wl,--gc-sections"
CROSS_COMPILE="llvm-"

init(){
	pushd "${repo}"
	git clone git://git.musl-libc.org/musl
	popd
}

update() {
	pushd ${repo}/musl
	git checkout master
	git pull
	popd
}

compile(){
	if [ -d  "${build}" ]; then
		rm -r ${build}
	fi

	mkdir -pv ${build}

	pushd ${build}
	CC="${CC}" LDFLAGS="${LDFLAGS}" CROSS_COMPILE="${CROSS_COMPILE}" ${repo}/musl/configure --prefix=${prefix} --exec-prefix=${prefix} --syslibdir=${prefix}
	make
	if [ "$?" != "0" ]; then
		echo ***************** libc make error *********************
		exit 1
	fi
	echo =================== libc OK =================
	make install
	echo ---- Now make some fake binaries to pass gcc link script ----
	touch ${SYSROOT}/lib/crtbeginS.o
	touch ${SYSROOT}/lib/crtendS.o
	echo =================== libc OK =================
	popd
}

case "$1" in
	"co"*)
		compile
		;;
	"up"*)
		update
		;;
	"in"*)
		init
		;;
	*)
		echo "Args are availble, please specify [co]mpile/[up]date/[in]it"
		;;
esac
