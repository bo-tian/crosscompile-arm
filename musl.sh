#!/bin/sh

#export LIBCC=$SYSROOT/../host/lib/libclang_rt.builtins-arm.a
source ./target.conf

build="${BUILD}/musl"
repo="${REPO}/musl"
prefix="${SYSROOT}"
CC="${CC} ${CFLAGS}"
#LDFLAGS="-Wl,--gc-sections"
CROSS_COMPILE="llvm-"

init(){
	if [ -d "${repo}" ]; then
		rm -r "${repo}"
	fi
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
	CC="${CC}" LDFLAGS="" CROSS_COMPILE="${CROSS_COMPILE}" ${repo}/musl/configure --prefix=${prefix} --exec-prefix=${prefix} --syslibdir=${prefix}
	make clean; make; make install
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
