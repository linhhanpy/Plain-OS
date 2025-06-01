#
#                       _oo0oo_
#                      o8888888o
#                      88' . '88
#                      (| -_- |)
#                      0\  =  /0
#                    ___/`---'\___
#                  .' \|      |// '.
#                 / \|||   :  |||// "
#                / _||||| -:- |||||- "
#               |   | \\  -  /// |   |
#               | \_|  ''\---/''  |_/ |
#               \  .-\__  '-'  ___/-. /
#             ___'. .'  /--.--\  `. .'___
#          .''' '<  `.___\_<|>_/___.' >' '''.
#          | | :  `- \`.;`\ _ /`;.`/ - ` : | |
#          \  \ `_.   \_ __\ /__ _/   .-` /  /
#      =====`-.____`.___ \_____/___.-`___.-'=====
#                        `=---='
#
#      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#                   佛祖保佑   永无bug
#                   阿弥陀佛   功德无量
#      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  Copyright (c) lhhasm & resfz
#  Plain Makefile
all:
	make out
	cd bin && make

out:
	nasm bootloader/boot.asm -o bin/boot.bin
	nasm -I include/ bootloader/loader.asm -o bin/loader.bin
	#gcc -c -O0 -fno-builtin -m32 -fno-stack-protector -o main.o main.c
	nasm -I include/ -o root/a.bin apps/a.asm
	python fs.py
	nasm -f elf -I include/ -o bin/kernel.o kernel/kernel.asm
	nasm -f elf -o bin/io.o kernel/io.asm
	nasm -f elf -o bin/shell.o kernel/shell.asm
	nasm -f elf -o bin/elf.o kernel/elf.asm
	nasm -f elf -o bin/memory.o kernel/memory.asm
	nasm -f elf -o bin/font.o kernel/font.asm
	nasm -f elf -o bin/network.o kernel/network.asm
	nasm -f elf -o bin/fs.o bin/fs.asm
	i686-elf-ld -s -Ttext 0x100000 -o bin/kernel.bin bin/kernel.o bin/io.o bin/shell.o bin/elf.o bin/memory.o bin/font.o bin/network.o bin/fs.o


