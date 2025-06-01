; Plain Kernel
; boot.asm
 
 
    org 0x07C00
StackBase             equ 0x07C00 ; 栈基址
LoaderBase            equ 0x09000 ; Loader基址
OffsetLoader          equ 0x0100  ; Loader偏移
RootDirSectors        equ 14      ; 根目录大小
SectorNoRootDirectory equ 19      ; 根目录起始扇区
SectorNoFAT1          equ 1       ; 第一个FAT表开始扇区
DeltaSectorNo         equ 17 
 
    jmp short start
    nop
 
    ; 下面的...咱也不知道,咱也不敢问,厂家说啥就是啥
 
    BS_OEMName     db 'Plain   '    ; 8个字节
    BPB_BytsPerSec dw 512           ; 每扇区512个字节
    BPB_SecPerClus db 1             ; 每簇固定1个扇区
    BPB_RsvdSecCnt dw 1             ; MBR固定占用1个扇区
    BPB_NumFATs    db 2             ; FAT12文件系统固定2个FAT表
    BPB_RootEntCnt dw 224           ; FAT12文件系统中根目录最大224个文件
    BPB_TotSec16   dw 2880          ; 1.44MB磁盘固定2880个扇区
    BPB_Media      db 0xF0          ; 介质描述符，固定为0xF0
    BPB_FATSz16    dw 9             ; 一个FAT表所占的扇区数FAT12文件系统固定为9个扇区
    BPB_SecPerTrk  dw 18            ; 每磁道扇区数，固定为18
    BPB_NumHeads   dw 2             ; 磁头数
    BPB_HiddSec    dd 0             ; 隐藏扇区数，没有
    BPB_TotSec32   dd 0             ; 直接置0即可
    BS_DrvNum      db 0             ; int 13h 调用时所读取的驱动器号，由于只有一个软盘所以是0 
    BS_Reserved1   db 0             ; 未使用，预留
    BS_BootSig     db 0x29          ; 扩展引导标记，固定为0x29
    BS_VolID       dd 0             ; 卷序列号，由于只挂载一个软盘所以为0
    BS_VolLab      db 'Plain - OS ' ; 卷标，11个字节
    BS_FileSysType db 'FAT12   '    ; 由于是 FAT12 文件系统，所以写入 FAT12 后补齐8个字节
 
start:
 
 
    
	mov ax, 0x0600
	mov bx, 0x0700
	mov cx, 0
	mov dx, 0x184F
	int 0x10
	mov ah, 0x02
	xor bh, bh
	mov dh, 0
	mov dl, 0
	int 0x10
    xor ax, ax ; 相当于 mov ax, 0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, StackBase
    
    
    mov dh, 0
    mov si, msg
    call print_string
 
read_main:
 
    mov word [wSectorNo], SectorNoRootDirectory
    cmp word [wRootDirLoopSize], 0
    jz no_loader
    dec word [wRootDirLoopSize] ; 减一个扇区
    mov ax, StackBase
    mov es, ax
    mov bx, OffsetLoader
    mov ax, [wSectorNo] ; now
    mov cl, 1
    call read_sector
 
    mov si, LoaderFileName
    mov di, OffsetLoader
    cld
    mov dx, 0x10
 
loader_search:
    cmp dx, 0
    jz next_sector
    dec dx
    mov cx, 11
 
cmp_name:
    cmp cx, 0
    jz loader_found
    dec cx
    lodsb
    cmp al, byte [es:di]
    jz next_str
    jmp different
 
next_str:
    inc di
    jmp cmp_name
 
different:
    and di, 0xFFE0
    add di, 0x20
    mov si, LoaderFileName
    jmp loader_search
 
next_sector:
    add word [wSectorNo], 1
    jmp read_main
 
no_loader:
    mov si, Message2
    call print_string
    jmp $
 
loader_found:
    mov ax, RootDirSectors
    and di, 0xFFE0
    add di, 0x1A
    mov cx, word [es:di]
    push cx
    add cx,ax
    add cx, DeltaSectorNo
    mov ax, LoaderBase
    mov es, ax
    mov bx, OffsetLoader
    mov ax, cx
 
load_file:
    mov cl, 1
    call read_sector
    pop ax
    call FAT_entry
    cmp ax, 0x0FFF
    jz loader_file
    push ax
    mov dx, RootDirSectors
    add ax, dx
    add ax, DeltaSectorNo
    add bx, [BPB_BytsPerSec]
    jmp load_file
 
loader_file:
    mov dh, 1
    mov si, Message1
    call print_string
    jmp LoaderBase:OffsetLoader ; Loader!
 
print_string:
    lodsb
    or al, al ; 检查是否为0
    jz .done
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp print_string
 
.done:
    ret
 
read_sector:
    push bp
    mov bp, sp
    sub esp, 2
    mov byte [bp-2], cl
    push bx
    mov bl, [BPB_SecPerTrk]
    div bl
    inc ah
    mov cl, ah
    mov dh, al
    shr al, 1
    mov ch, al
    and dh, 1 ; 磁头
    pop bx
    mov dl, [BS_DrvNum]
 
.read_start:
    mov ah, 2
    mov al, byte [bp-2]
    int 0x13
    jc .read_start
    add esp, 2
    pop bp
    ret
 
FAT_entry:
    push es
    push bx
    push ax
    mov ax, LoaderBase
    sub ax, 0x0100
    mov es, ax ; 缓冲区的基址
    pop ax
    mov byte [bOdd], 0
    mov bx, 3
    mul bx
    mov bx, 2
    div bx
    cmp dx, 0
    jz FAT_next
    mov byte [bOdd], 1
 
FAT_next:
    xor dx, dx
    mov bx, [BPB_BytsPerSec]
    div bx
    push dx
    xor bx, bx
    add ax, SectorNoFAT1
    mov cl, 2
    call read_sector
    pop dx
    add bx, dx
    mov ax, [es:bx]
    cmp byte [bOdd], 1
    jnz FAT_next2
    shr ax, 4
 
FAT_next2:
    and ax, 0x0FFF
 
all_OK:
    pop bx
    pop es
    ret
 
msg              db "Loading Loader...", 0
 
wRootDirLoopSize dw RootDirSectors
wSectorNo        dw 0              ; 当前扇区数
bOdd             db 0              
 
LoaderFileName   db "LOADER  BIN", 0 ; loader的文件名
 
Message1         db "OK!", 0x0A, 0x0D, 0
Message2         db "Loader Not Find", 0
 
 
times 510-($-$$) db 0
db 0x55, 0xAA
