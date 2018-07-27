#!/bin/sh

. ./target.conf

repo="${REPO}/zlib"
src="${repo}/zlib"
build="${BUILD}/zlib"

CFLAGS="${CFLAGS} ${COMPACT_LIB}"

init () {
	if [ ! -d "${repo}" ]; then
		mkdir -p "${repo}"
	else
		echo "${repo} already exists, please select another diectory."
		exit 1
	fi

	pushd "${repo}"
	git clone https://github.com/madler/zlib.git 
	popd
}

update () {
	if [ ! -d "${src}" ]; then
		echo "zlib source code is nonexistent, please execute init first."
		exit 1
	fi

	pushd "${src}"
	git checkout master
	git pull
	popd
}

compile () {
	if [ -d "${build}" ]; then
		rm -r "${build}"
	fi

	mkdir "${build}"
	pushd "${build}"
	CC="${CC}" CFLAGS="${CFLAGS}" "${src}"/configure --const --static
	make
	if [ "$?" != "0" ]; then
		echo ********** zlib compile error **********
		exit 1
	fi
	echo ====================== zlib OK ====================
	cp -v zconf.h "${SYSROOT}/usr/include/"
	cp -v "${src}/zlib.h" "${SYSROOT}/usr/include/"
	cp -v *.a "${SYSROOT}/lib/"
	echo ====================== zlib OK ====================
	popd
}

case "$1" in
	"in"*)
		init
		;;
	"up"*)
		update
		;;
	"co"*)
		compile
		;;
	*)
		echo "Subcommands are available, please specify [in]it/[up]date/[co]mpile."
		;;
esac
