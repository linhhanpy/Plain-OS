; ============ kernel.asm ============
[bits 32]

; 段选择子定义
KERNEL_CS equ 0x08  ; 内核代码段选择子
KERNEL_DS equ 0x10  ; 内核数据段选择子

; 系统调用中断号
SYSCALL_INT equ 0x80

; 系统调用号定义
SYS_PRINT  equ 0
SYS_GETKEY equ 1
SYS_CLEAR  equ 2
SYS_RUN    equ 3

[section .text]
%include "io.inc"

; 全局函数声明
global _start
extern shell
extern init_mouse, init_network
extern print_str, put_char, get_key, clear_screen

[section .bss]
align 32
kernel_stack:
    resb 4096        ; 4KB内核栈
stack_top:
; 数据段定义
[section .data]
; 中断描述符表 (IDT)
align 8
idt:
    times 256 dq 0  ; 256个门描述符，每个8字节
idt_ptr:
    dw 256*8 - 1    ; IDT界限 = 大小 - 1
    dd idt          ; IDT线性基地址

; 欢迎消息
hello_msg db "Welcome to Plain - OS !", 0
net_init_failed_msg db "Network Error!", 0
; 系统调用表
sys_call_table:
    dd sys_print_str    ; 0
    dd sys_get_key      ; 1
    dd sys_clear_screen ; 2
    dd sys_run_program  ; 3
SYS_CALL_MAX equ ($ - sys_call_table)/4

[section .text]
; 内核入口点
_start:
    ; 设置内核段寄存器
    mov ax, KERNEL_DS
    mov ds, ax
    mov es, ax
    mov fs, ax
    
    ; 设置内核栈
    mov esp, stack_top
    ; 初始化IDT
    call init_idt
    
    ; 初始化硬件
    call hide_cursor
    call clear_screen
    
    ; 显示欢迎消息
    mov ebx, 0          ; 行号
    mov ecx, 0          ; 列号
    mov esi, hello_msg  ; 字符串地址
    mov ah, 0x0F
    call print_str
    
    xor ecx, ecx
    inc ebx
    call init_network
    test eax, eax
    jz .init_failed   ; 如果返回0表示初始化失败
    
    ; 启动shell
    xor ecx, ecx
    mov ebx, 5
    call shell
    jmp $
    
.init_failed:
    ; 处理初始化失败
    mov esi, net_init_failed_msg
    call print_str
    jmp $

; ============ IDT初始化 ============
init_idt:
    ; 1. 先清零IDT
    mov edi, idt
    mov ecx, 256
    xor eax, eax
    rep stosd
    
    ; 2. 设置系统调用中断门 (DPL=3允许用户程序调用)
    mov eax, syscall_handler
    mov word [idt + 8*SYSCALL_INT], ax        ; 偏移低16位
    mov word [idt + 8*SYSCALL_INT + 2], KERNEL_CS ; 选择子
    mov byte [idt + 8*SYSCALL_INT + 4], 0     ; 保留
    mov byte [idt + 8*SYSCALL_INT + 5], 0xEE  ; P=1, DPL=3, 32位中断门
    shr eax, 16
    mov word [idt + 8*SYSCALL_INT + 6], ax    ; 偏移高16位
    
    ; 3. 加载IDT
    lidt [idt_ptr]
    ret

; ============ 系统调用处理程序 ============
syscall_handler:
    pushad
    
    ; 验证系统调用号范围
    cmp eax, SYS_CALL_MAX
    jae .invalid_call
    
    ; 调用相应处理函数
    call [sys_call_table + eax*4]
    jmp .done
    
.invalid_call:
    mov eax, -1 ; 无效调用号返回-1
    
.done:
    mov [esp+28], eax ; 将返回值存入栈中的EAX位置
    popad
    iret

; ============ 系统调用实现 ============
sys_print_str:
    call sys_print_char
    ret

sys_print_char:
    push edi
    push eax
    
    ; 计算显存位置: (行*80 + 列)*2
    mov edi, ebx
    imul edi, LINE_WIDTH
    add edi, ecx
    shl edi, 1
    
    ; 写入显存
    mov ax, dx         ; 组合字符和属性
    mov [gs:edi], ax
    
    ; 更新列号
    inc ecx
    cmp ecx, LINE_WIDTH
    jb .no_newline
    
    ; 处理换行
    xor ecx, ecx       ; 列号清零
    inc ebx            ; 行号增加
    
.no_newline:
    pop eax
    pop edi
    ret

sys_get_key:
    call get_key
    ret

sys_clear_screen:
    call clear_screen
    xor eax, eax
    ret

sys_run_program:
    ; EBX=文件名指针
    push esi
    mov esi, ebx
    ; 这里需要实现文件加载和执行逻辑
    ; call do_run
    pop esi
    xor eax, eax
    ret
