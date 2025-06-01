all:
	make img
	make run

img : boot.bin loader.bin kernel.bin
	#dd if=boot.bin of=a.img bs=512 count=1
	#dd if=loader.bin of=a.img bs=512 seek=1 conv=notrunc
	#python img.py
	edimg   imgin:1.img \
		wbinimg src:boot.bin len:512 from:0 to:0 \
		copy from:loader.bin to:@: \
		copy from:kernel.bin to:@: \
		imgout:a.img
 
 
run : a.img
	qemu-system-i386 \
  -m 16M \
  -device ne2k_isa,iobase=0x300,irq=10,mac=52:54:00:12:34:56 \
  -netdev user,id=net0,hostfwd=tcp::8080-:80 \
  -net nic,netdev=net0 \
  -drive file=a.img,format=raw,if=floppy \
  -boot a \
  -serial stdio \
  -monitor telnet:127.0.0.1:1234,server,nowait
 