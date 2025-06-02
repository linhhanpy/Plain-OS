org 0x100000
_start:
    
    ; 测试单个字符输出
    mov eax, 0
    mov dh, 0x00
    mov dl, ' '
    int 0x80
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    add dh, 0x0F
    int 0x80
    inc ecx
    ret

