[bits 32]

; ***********************
; * 硬件端口和常量定义 *
; ***********************
VIDEO_MEMORY         equ 0xB8000
LINE_WIDTH           equ 80
SCREEN_HEIGHT        equ 25
WHITE_ON_BLACK       equ 0x0F

KEYBOARD_PORT        equ 0x60
KEYBOARD_STATUS_PORT equ 0x64
KEYBOARD_BUF_SIZE    equ 256

; 键盘状态标志
CAPS_LOCK    equ 0x01
SHIFT_DOWN   equ 0x02
CTRL_DOWN    equ 0x04
ALT_DOWN     equ 0x08

VGA_CRTC_INDEX  equ 0x3D4
VGA_CRTC_DATA   equ 0x3D5
CURSOR_START    equ 0x0A
CURSOR_END      equ 0x0B

; ***********************
; * 全局数据定义        *
; ***********************
[section .data]
key_flags      db 0     ; 键盘状态标志
cursor_x       dd 0     ; 当前光标列
cursor_y       dd 0     ; 当前光标行
keyboard_buffer times KEYBOARD_BUF_SIZE db 0
keyboard_head  dd 0
keyboard_tail  dd 0

; 扫描码转换表 (小写)
scancode_lower:
    db 0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0x08
    db 0, 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0x0A
    db 0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0
    db '\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, 0, 0, ' '

; 扫描码转换表 (大写/Shift)
scancode_upper:
    db 0, 0, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 0x08
    db 0, 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 0x0A
    db 0, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0
    db '|', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, 0, 0, ' '

; ***********************
; * 显示功能函数        *
; ***********************
[section .text]



; 函数：hide_cursor - 隐藏文本模式光标
global hide_cursor
hide_cursor:
    push eax
    push edx

    ; 设置光标起始寄存器 (索引0x0A)
    mov al, CURSOR_START
    mov dx, VGA_CRTC_INDEX
    out dx, al

    ; 写入值0x20到数据端口（禁用光标）
    mov al, 0x20
    mov dx, VGA_CRTC_DATA
    out dx, al

    ; 可选：为了兼容性，也设置结束寄存器
    mov al, CURSOR_END
    mov dx, VGA_CRTC_INDEX
    out dx, al

    mov al, 0x00        ; 结束扫描线设为0
    mov dx, VGA_CRTC_DATA
    out dx, al

    pop edx
    pop eax
    ret

; 在指定位置输出字符
; 输入: EBX=行, ECX=列, AL=字符, AH=属性
global put_char
put_char:
    push edi
    mov edi, ebx
    imul edi, LINE_WIDTH
    add edi, ecx
    shl edi, 1
    mov [gs:edi], ax
    pop edi
    ret

; 输出字符串 (自动换行)
; 输入: EBX=起始行, ECX=起始列, ESI=字符串, AH=属性
global print_str
print_str:
    cmp ebx, 24
    ja scroll_
    pusha
    cld
.print_loop:
    lodsb
    test al, al
    jz .done
    
    push ebx
    push ecx
    call put_char
    pop ecx
    pop ebx
    
    inc ecx
    cmp ecx, LINE_WIDTH
    jb .same_line
    
    mov ecx, 0
    inc ebx
    cmp ebx, SCREEN_HEIGHT
    jb .same_line
    
    dec ebx
    dec ecx
    call scroll_screen
.same_line:
    jmp .print_loop
.done:
    popa
    ret


scroll_:
    call scroll_screen
    
    mov ebx, 24
    jmp print_str

; 清屏
global clear_screen
clear_screen:
    pusha
    mov edi, VIDEO_MEMORY
    mov ecx, LINE_WIDTH * SCREEN_HEIGHT
    mov ax, (WHITE_ON_BLACK << 8) | ' '
    rep stosw
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    popa
    ret

; 屏幕向上滚动一行
global scroll_screen
scroll_screen:
    pusha
    
    ; 1. 将第2行到最后行的内容复制到第1行到倒数第2行
    mov esi, VIDEO_MEMORY + LINE_WIDTH * 2    ; 源地址 = 第2行开始
    mov edi, VIDEO_MEMORY                     ; 目标地址 = 第1行开始
    mov ecx, LINE_WIDTH * (SCREEN_HEIGHT-1)   ; 复制 (高度-1) 行
    
    ; 使用DWORD移动提高效率
    shr ecx, 1                                ; 双字计数 = 字数/2
    rep movsd
    
    ; 如果字符数为奇数，复制最后一个字
    ;test ecx, 1
    ;jz .clear_last_line
    ;movsw
    
.clear_last_line:
    ; 2. 清空最后一行
    mov edi, VIDEO_MEMORY + LINE_WIDTH * (SCREEN_HEIGHT-1) * 2
    mov ecx, LINE_WIDTH
    mov ax, (WHITE_ON_BLACK << 8) | ' '       ; 空格字符+属性
    rep stosw
    
    ; 3. 更新光标位置（保持在最后一行开头）
    mov dword [cursor_x], 0
    mov dword [cursor_y], SCREEN_HEIGHT
    
    popa
    ret

; ***********************
; * 键盘功能函数        *
; ***********************

; 键盘中断处理程序 (IRQ1)
global get_key
get_key:
    push edx
    push ebx

.wait_key:
    ; 等待键盘缓冲区有数据
    in al, KEYBOARD_STATUS_PORT
    test al, 1
    jz .wait_key

    ; 读取键盘扫描码
    in al, KEYBOARD_PORT
    mov ah, al           ; 保存扫描码

    ; ESC键 (扫描码0x01)
    cmp al, 0x01
    je .esc_key
    ; 处理特殊键 (Shift/Ctrl/Alt/CapsLock)
    cmp al, 0x2A         ; 左Shift按下
    je .shift_press
    cmp al, 0xAA         ; 左Shift释放
    je .shift_release
    cmp al, 0x36         ; 右Shift按下
    je .shift_press
    cmp al, 0xB6         ; 右Shift释放
    je .shift_release
    cmp al, 0x3A         ; CapsLock
    je .caps_toggle
    cmp al, 0x1D         ; Ctrl
    je .ctrl_press
    cmp al, 0x9D         ; Ctrl释放
    je .ctrl_release
    cmp al, 0x38         ; Alt
    je .alt_press
    cmp al, 0xB8         ; Alt释放
    je .alt_release

    ; 检查是否是释放事件
    test al, 0x80
    jnz .key_release

    ; 转换为ASCII
    movzx ebx, al
    cmp ebx, 58          ; 检查是否在转换表范围内
    ja .special_key

    ; 选择转换表 (根据Shift/Caps状态)
    test byte [key_flags], SHIFT_DOWN
    jnz .use_upper
    test byte [key_flags], CAPS_LOCK
    jz .use_lower
.use_upper:
    mov al, [scancode_upper + ebx]
    jmp .check_valid
.use_lower:
    mov al, [scancode_lower + ebx]
.check_valid:
    test al, al
    jz .special_key
    stc                  ; CF=1表示按下事件
    jmp .done

.key_release:
    ;clc                  ; CF=0表示释放事件
    xor al, al
    jmp .done

.special_key:
    xor al, al           ; AL=0表示特殊键
    stc
    jmp .done

.shift_press:
    or byte [key_flags], SHIFT_DOWN
    xor al, al
    stc
    jmp .done

.shift_release:
    and byte [key_flags], ~SHIFT_DOWN
    xor al, al
    stc
    jmp .done

.caps_toggle:
    xor byte [key_flags], CAPS_LOCK
    ; 更新CapsLock LED
    call update_leds
    xor al, al
    stc
    jmp .done

.ctrl_press:
    or byte [key_flags], CTRL_DOWN
    xor al, al
    stc
    jmp .done

.ctrl_release:
    and byte [key_flags], ~CTRL_DOWN
    xor al, al
    stc
    jmp .done

.alt_press:
    or byte [key_flags], ALT_DOWN
    xor al, al
    stc
    jmp .done

.alt_release:
    and byte [key_flags], ~ALT_DOWN
    xor al, al
    stc
    jmp .done

.esc_key:
    mov al, 0x1B         ; ESC键ASCII码
    stc
    jmp .done

.done:
    pop ebx
    pop edx
    ret

; 更新键盘LED状态 (CapsLock/NumLock/ScrollLock)
update_leds:
    pushad
    ; 等待键盘可接受命令
    mov ecx, 1000
.wait_ready:
    in al, KEYBOARD_STATUS_PORT
    test al, 0x02
    loopnz .wait_ready

    ; 发送LED更新命令
    mov al, 0xED         ; LED命令
    out KEYBOARD_PORT, al

    ; 等待应答
    mov ecx, 1000
.wait_ack:
    in al, KEYBOARD_PORT
    cmp al, 0xFA         ; ACK
    loopne .wait_ack

    ; 发送LED状态
    mov al, [key_flags]
    and al, CAPS_LOCK    ; 只设置CapsLock
    out KEYBOARD_PORT, al
    popad
    ret

; 获取一个按键 (非阻塞)
; 输出: AL=ASCII字符 (0表示无输入)
global get_char
get_char:
    mov eax, [keyboard_head]
    cmp eax, [keyboard_tail]
    je .no_input
    
    mov al, [keyboard_buffer + eax]
    inc eax
    cmp eax, KEYBOARD_BUF_SIZE
    jne .no_wrap
    xor eax, eax
.no_wrap:
    mov [keyboard_head], eax
    ret
.no_input:
    xor al, al
    ret

; 读取一行输入 (带回显)
; 输入: EDI=缓冲区, ECX=最大长度
; 输出: EAX=读取字符数
global read_line
read_line:
    push ebx
    push ecx
    push edx
    push edi
    
    xor ebx, ebx         ; 字符计数
    mov edx, [cursor_y]
    shl edx, 16
    or edx, [cursor_x]   ; EDX高16位=行, 低16位=列
    
.read_loop:
    call get_char
    test al, al
    jz .read_loop
    
    cmp al, 0x0A         ; 回车
    je .line_end
    cmp al, 0x08         ; 退格
    je .backspace
    
    ; 检查缓冲区是否满
    cmp ebx, ecx
    jae .read_loop
    
    ; 存储并显示字符
    mov [edi + ebx], al
    inc ebx
    
    push ebx
    push ecx
    movzx ebx, dx        ; 当前列
    movzx ecx, dh        ; 当前行
    mov ah, WHITE_ON_BLACK
    call put_char
    pop ecx
    pop ebx
    
    inc dl               ; 列位置+1
    cmp dl, LINE_WIDTH
    jb .read_loop
    
    mov dl, 0            ; 换行处理
    inc dh
    cmp dh, SCREEN_HEIGHT
    jb .read_loop
    
    dec dh
    call scroll_screen
    jmp .read_loop

.backspace:
    test ebx, ebx
    jz .read_loop
    dec ebx
    
    push ebx
    push ecx
    movzx ebx, dx
    movzx ecx, dh
    mov al, ' '
    mov ah, WHITE_ON_BLACK
    call put_char
    pop ecx
    pop ebx
    
    dec dl
    jns .read_loop
    mov dl, LINE_WIDTH-1
    dec dh
    jns .read_loop
    xor dh, dh
    jmp .read_loop

.line_end:
    mov byte [edi + ebx], 0
    mov eax, ebx
    
    ; 更新光标位置
    mov [cursor_x], edx
    shr edx, 16
    mov [cursor_y], edx
    
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret
