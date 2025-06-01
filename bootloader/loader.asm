org 0100h
BaseOfStack equ 0100h
 
jmp LABEL_START
 
%include "load.inc"
 
LABEL_GDT:          Descriptor 0, 0, 0
LABEL_DESC_FLAT_C:  Descriptor 0, 0fffffh, DA_C|DA_32|DA_LIMIT_4K
LABEL_DESC_FLAT_RW: Descriptor 0, 0fffffh, DA_DRW|DA_32|DA_LIMIT_4K
LABEL_DESC_VIDEO:   Descriptor 0B8000h, 0ffffh, DA_DRW|DA_DPL3
 
GdtLen equ $ - LABEL_GDT
GdtPtr dw GdtLen - 1
       dd BaseOfLoaderPhyAddr + LABEL_GDT
 
SelectorFlatC  equ LABEL_DESC_FLAT_C - LABEL_GDT
SelectorFlatRW equ LABEL_DESC_FLAT_RW - LABEL_GDT
SelectorVideo  equ LABEL_DESC_VIDEO - LABEL_GDT + SA_RPL3
 
LABEL_START:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, BaseOfStack
    
    mov si, msg
    call print_string
 
    mov word [wSectorNo], SectorNoOfRootDirectory
    xor ah, ah
    xor dl, dl
    int 13h
 
SearchRootDir:
    cmp word [wRootDirSizeForLoop], 0
    jz NoKernelFound
    dec word [wRootDirSizeForLoop]
    mov ax, BaseOfKernelFile
    mov es, ax
    mov bx, OffsetOfKernelFile
    mov ax, [wSectorNo]
    mov cl, 1
    call ReadSector
 
    mov si, KernelFileName
    mov di, OffsetOfKernelFile
    cld
    mov dx, 10h
 
SearchFile:
    cmp dx, 0
    jz NextSector
    dec dx
    mov cx, 11
CmpFilename:
    cmp cx, 0
    jz FileFound
    dec cx
    lodsb
    cmp al, byte [es:di]
    jz NextChar
    jmp DifferentFile
NextChar:
    inc di
    jmp CmpFilename
 
DifferentFile:
    and di, 0FFE0h
    add di, 20h
    mov si, KernelFileName
    jmp SearchFile
 
NextSector:
    add word [wSectorNo], 1
    jmp SearchRootDir
 
NoKernelFound:
    mov si, Message2
    call print_string
    jmp $
 
FileFound:
    mov ax, RootDirSectors
    and di, 0FFF0h
 
    push eax
    mov eax, [es:di + 01Ch]
    mov dword [dwKernelSize], eax
    pop eax
 
    add di, 01Ah
    mov cx, word [es:di]
    push cx
    add cx, ax
    add cx, DeltaSectorNo
    mov ax, BaseOfKernelFile
    mov es, ax
    mov bx, OffsetOfKernelFile
    mov ax, cx
 
LoadFile:
    mov cl, 1
    call ReadSector
    pop ax
    call GetFATEntry
    cmp ax, 0FFFh
    jz FileLoaded
    push ax
    mov dx, RootDirSectors
    add ax, dx
    add ax, DeltaSectorNo
    add bx, [BPB_BytsPerSec]
    jmp LoadFile
 
FileLoaded:
    call KillMotor
    mov si, Message1
    call print_string
    lgdt [GdtPtr]
    cli
    in al, 92h
    or al, 00000010b
    out 92h, al
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword SelectorFlatC:(BaseOfLoaderPhyAddr+LABEL_PM_START)
 
print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp print_string
 
.done:
    ret
 
 
ReadSector:
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
    and dh, 1
    pop bx
    mov dl, [BS_DrvNum]
ReadLoop:
    mov ah, 2
    mov al, byte [bp-2]
    int 13h
    jc ReadLoop
    add esp, 2
    pop bp
    ret
 
GetFATEntry:
    push es
    push bx
    push ax
    mov ax, BaseOfKernelFile
    sub ax, 0100h
    mov es, ax
    pop ax
    mov byte [bOdd], 0
    mov bx, 3
    mul bx
    mov bx, 2
    div bx
    cmp dx, 0
    jz EvenEntry
    mov byte [bOdd], 1
EvenEntry:
    xor dx, dx
    mov bx, [BPB_BytsPerSec]
    div bx
    push dx
    mov bx, 0
    add ax, SectorNoOfFAT1
    mov cl, 2
    call ReadSector
    pop dx
    add bx, dx
    mov ax, [es:bx]
    cmp byte [bOdd], 1
    jnz EvenEntry2
    shr ax, 4
EvenEntry2:
    and ax, 0FFFh
    pop bx
    pop es
    ret
 
KillMotor:
    push dx
    mov dx, 03F2h
    mov al, 0
    out dx, al
    pop dx
    ret
 
[section .s32]
align 32
[bits 32]
LABEL_PM_START:
    mov ax, SelectorVideo
    mov gs, ax
    mov ax, SelectorFlatRW
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov ss, ax
    mov esp, TopOfStack
    call InitKernel
    jmp SelectorFlatC:KernelEntryPointPhyAddr
 
MemCpy:
    push ebp
    mov ebp, esp
    push esi
    push edi
    push ecx
    mov edi, [ebp + 8]
    mov esi, [ebp + 12]
    mov ecx, [ebp + 16]
CopyLoop:
    cmp ecx, 0
    jz CopyDone
    mov al, [ds:esi]
    inc esi
    mov byte [es:edi], al
    inc edi
    dec ecx
    jmp CopyLoop
CopyDone:
    mov eax, [ebp + 8]
    pop ecx
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret
 
InitKernel:
    xor esi, esi
    mov cx, word [BaseOfKernelFilePhyAddr + 2Ch]
    movzx ecx, cx
    mov esi, [BaseOfKernelFilePhyAddr + 1Ch]
    add esi, BaseOfKernelFilePhyAddr
ProcessHeader:
    mov eax, [esi]
    cmp eax, 0
    jz NextHeader
    push dword [esi + 010h]
    mov eax, [esi + 04h]
    add eax, BaseOfKernelFilePhyAddr
    push eax
    push dword [esi + 08h]
    call MemCpy
    add esp, 12
 
NextHeader:
    add esi, 020h
    dec ecx
    jnz ProcessHeader
    ret
 
[section .data1]
StackSpace: times 1024 db 0
TopOfStack equ $ - StackSpace
 
dwKernelSize        dd 0
wRootDirSizeForLoop dw RootDirSectors
wSectorNo           dw 0
bOdd                db 0
KernelFileName      db "KERNEL  BIN", 0
msg                 db "Loading Kernel...", 0
Message1            db "OK!", 0x0A, 0x0D, 0
Message2            db "Kernel Not Find", 0
