
VIDEO_MEMORY         equ 0xB8000
LINE_WIDTH           equ 80
SCREEN_HEIGHT        equ 25
WHITE_ON_BLACK       equ 0x0F

; DL为输出的字符,EBX行号,ECX列号
_put_char:
    int 0x80
    ret

; ============ printf 实现 ============
; 输入：ESI=字符串指针
; 使用：EBX=行号, ECX=列号
printf:
    cld
.print_loop:
    lodsb               ; AL = 当前字符
    test al, al
    jz .done           ; 字符串结束

    mov dl, al         ; 要打印的字符
    mov dh, 0x0F       ; 白字黑底
    call _put_char
    inc ecx            ; 列号+1
    jmp .print_loop

.done:
    ret

