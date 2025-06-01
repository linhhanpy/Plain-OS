org 0x100000
_start:
    
    ; 测试单个字符输出
    mov eax, 0
    mov dl, 'H'
    mov dh, 0x0F
    int 0x80
    inc ecx
    mov dl, 'e'
    int 0x80
    inc ecx
    mov dl, 'l'
    int 0x80
    inc ecx
    mov dl, 'l'
    int 0x80
    inc ecx
    mov dl, 'o'
    int 0x80
    inc ecx
    mov dl, '!'
    int 0x80
    inc ecx
a:
    mov dl, '!'
    int 0x80
    jmp a
    ret

msg db "Hello, World!", 0
