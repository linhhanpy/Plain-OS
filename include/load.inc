
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




FATSz                   equ 9      ; BPB_FATSz16
RootDirSectors          equ 14     ; 根目录大小
SectorNoOfRootDirectory equ 19     ; 根目录起始扇区
SectorNoOfFAT1          equ 1 ; 第一个FAT表的开始扇区
DeltaSectorNo           equ 17 ; 由于第一个簇不用，所以RootDirSectors要-2再加上根目录区首扇区和偏移才能得到真正的地址，故把RootDirSectors-2封装成一个常量（17）

DA_32       equ 0x4000
DA_LIMIT_4K equ 0x8000

DA_DPL0     equ 0x00
DA_DPL1     equ 0x20
DA_DPL2     equ 0x40
DA_DPL3     equ 0x60

DA_DR       equ 0x90
DA_DRW      equ 0x92
DA_DRWA     equ 0x93
DA_C        equ 0x98
DA_CR       equ 0x9A
DA_CCO      equ 0x9C
DA_CCOR     equ 0x9E

DA_LDT      equ 0x82
DA_TaskGate equ 0x85
DA_386TSS   equ 0x89
DA_386CGate equ 0x8C
DA_386IGate equ 0x8E
DA_386TGate equ 0x8F

SA_RPL0     equ 0
SA_RPL1     equ 1
SA_RPL2     equ 2
SA_RPL3     equ 3

SA_TIG      equ 0
SA_TIL      equ 4

PG_P        equ 1
PG_RWR      equ 0
PG_RWW      equ 2
PG_USS      equ 0
PG_USU      equ 4

%macro Descriptor 3
    dw %2 & 0xFFFF
    dw %1 & 0xFFFF
    db (%1 >> 16) & 0xFF
    dw ((%2 >> 8) & 0xF00) | (%3 & 0xF0FF)
    db (%1 >> 24) & 0xFF
%endmacro

%macro Gate 4
    dw (%2 & 0xFFFF)
    dw %1
    dw (%3 & 0x1F) | ((%4 << 8) & 0xFF00)
    dw ((%2 >> 16) & 0xFFFF)
%endmacro

BaseOfLoader            equ 09000h ; Loader的基址
OffsetOfLoader          equ 0100h  ; Loader的偏移

BaseOfLoaderPhyAddr     equ BaseOfLoader * 10h ; Loader被装载到的物理地址

BaseOfKernelFile            equ 08000h ; Kernel的基址
OffsetOfKernelFile          equ 0h  ; Kernel的偏移

BaseOfKernelFilePhyAddr     equ BaseOfKernelFile * 10h ; Kernel被装载到的物理地址
KernelEntryPointPhyAddr     equ 0x100000 ; Kernel入口点，一定要与编译命令一致！！！

