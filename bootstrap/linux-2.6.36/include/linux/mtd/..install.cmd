cmd_/home/repo/linux/usr/include/mtd/.install := perl scripts/headers_install.pl /home/repo/linux/include/mtd /home/repo/linux/usr/include/mtd arm inftl-user.h mtd-abi.h mtd-user.h nftl-user.h ubi-user.h; perl scripts/headers_install.pl /home/repo/linux/include/mtd /home/repo/linux/usr/include/mtd arm ; touch /home/repo/linux/usr/include/mtd/.install