# crosscompile-arm

target.conf is the build entry point.

REPO: where source code are placed.
SYSROOT: where include files and the generated libraries,
	such as libc, libc++, etc. are placed.
TARGET: where the runnable binaries and shared libraries,
	such as libc.so, libc++.so, nginx, etc. are placed.
BUILD: where the building are placed. 


1. What's the bootstrap directory for?

Libc header file are needed by compiler-rt and Linux header files.

2. What would a full cross compile be like?

Prepare LLVM suite(llvm, clang, lld, etc.).
For example, in Arch Linux execute "pacman -Sy llvm llvm-libs clang lld".

Download LLVM source code. (llvm, compiler-rt, libunwind, libcxxabi, libcxx, etc.)
For example, execute "sh llvm.sh init".

Build compiler-rt library.
For example, execute "sh llvm.sh standalone_compile compiler-rt"

Build musl(libc) library.
For example, execute "sh musl.sh init; sh musl.sh compile"

Build libcxx(libc++) library.
For example, execute "sh llvm.sh llvm"

From here, compiler-rt/libc/libc++ are ready.
