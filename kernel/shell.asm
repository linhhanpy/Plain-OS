;shell.asm
[bits 32]

[section .data]
; Shell界面
msg db "[root@Plain]-(/)# ", 0
cmd_buffer times 80 db 0

; 命令定义
cmd_echo db "echo", 0
cmd_help db "help", 0
cmd_ls   db "ls", 0
cmd_cat  db "cat", 0
cmd_photo  db "photo", 0
cmd_write db "write", 0
cmd_clear db "clear", 0
cmd_run db "run", 0
cmd_ping db "ping", 0
cmd_sleep db "sleep", 0
cmd_task  db "task", 0
cmd_vim  db "vim", 0
cmd_time db "time", 0
time_str db "HH:MM:SS", 0
; 帮助信息
help_msg1 db "Available commands:", 0
help_msg2 db "  echo <message> - Display message", 0
help_msg3 db "  help          - Show this help", 0
help_msg4 db "  ls            - List files", 0
help_msg5 db "  cat <file>    - Show file content", 0
help_msg6 db "  write <file> > <content> - Write to file", 0
help_msg7 db "  clear         - Clear screen", 0
help_msg8 db "  run <file>    - Execute ELF program", 0
help_msg9 db "  sleep <ms>    - Delay execution", 0
help_msg10 db "  task <cmd>   - Run command in background", 0

; 错误和信息消息
not_msg db "Error: Command not found: ", 0
error_msg db "ERROR: Disk operation failed", 0
dir_entry db "  [DIR] ", 0
write_success db "Write successful", 0
write_fail db "Write failed", 0
invalid_format_msg db "Invalid write format. Use: write filename > content", 0

align 8
idt:
    times 256 dq 0  ; 256个门描述符，每个8字节
idt_ptr:
    dw 256*8 - 1    ; IDT界限 = 大小 - 1
    dd idt          ; IDT线性基地址


[section .text]
extern print_str, put_char, get_key, clear_screen, fs_list_files, fs_files_count, fs_read_file 

extern mem_alloc, mem_free, fs_get_file_size
;extern elf_load, elf_get_entry
extern scroll_screen, do_ping_impl

global shell
shell:
    call shell_scroll
    call init_timer
    call init_task_system
    ;cmp ebx, 25
    ;ja .scroll
    mov ecx, 0
    mov esi, msg
    mov ah, 0x0F
    call print_str
    
    ; 初始化命令缓冲区
    mov edi, cmd_buffer
    mov ecx, 18          ; 从第18列开始输入
    mov byte [edi], 0    ; 清空缓冲区
    
    mov al, ' '
    mov ah, 0xFF
    call put_char
    
.input_loop:
    call get_key
    test al, al
    jz .input_loop

    mov [current_line], ebx
    mov [current_column], ecx

    ; 处理回车
    cmp al, 0x0A
    je .execute

    ; 处理退格
    cmp al, 0x08
    je .backspace

    ; 存储并显示字符
    mov [edi], al
    inc edi
    mov ah, 0x0F
    call put_char
    inc ecx
    
    mov al, ' '
    mov ah, 0xFF
    call put_char
    jmp .input_loop

.backspace:
    ; 退格处理
    cmp edi, cmd_buffer
    je .input_loop       ; 忽略空退格
    mov al, ' '
    mov ah, 0x0F
    call put_char
    dec edi
    dec ecx
    mov al, ' '
    mov ah, 0xFF
    call put_char
    jmp .input_loop
    
.scroll:
    call scroll_screen
    
    mov ebx, 24
    mov ecx, 0
    jmp shell
.execute:
    mov al, ' '
    mov ah, 0x0F
    call put_char
    ; 添加字符串结束符
    mov byte [edi], 0
    
    ; 检查空命令
    mov esi, cmd_buffer
    call is_empty
    je .empty_cmd
    
    ; 跳过前导空格
    call skip_spaces
    test al, al
    jz .empty_cmd
    
    
    mov edi, cmd_task
    call cmd_cmp
    je do_task

    ; 检查help命令
    mov edi, cmd_help
    call cmd_cmp
    je .show_help

    ; 检查echo命令
    mov edi, cmd_echo
    call cmd_cmp
    je .do_echo
    
    ; 检查echo命令
    mov edi, cmd_ls
    call cmd_cmp
    je do_ls
    
    
    mov edi, cmd_time
    call cmd_cmp
    je do_time

    mov edi, cmd_cat
    call cmd_cmp
    je do_cat
    
    mov edi, cmd_photo
    call cmd_cmp
    je do_photo
    
    mov edi, cmd_run
    call cmd_cmp
    je do_run

    
    mov edi, cmd_sleep
    call cmd_cmp
    je do_sleep

    mov edi, cmd_write
    call cmd_cmp
    je do_write

    mov edi, cmd_vim
    call cmd_cmp
    je do_vim

    ; 检查clear命令
    mov edi, cmd_clear
    call cmd_cmp
    je .do_clear

    mov edi, cmd_ping
    call cmd_cmp
    je do_ping

    ; 未知命令处理
    
    jmp .do_run1
.cmd_error:
    inc ebx
    mov ecx, 0
    mov esi, not_msg
    mov ah, 0x0C        ; 红色错误信息
    call print_str
    
    ; 只显示命令部分(第一个空格前的内容)
    mov esi, cmd_buffer
    call print_command_part
    
    inc ebx
    jmp shell

.do_run1:
    
    call skip_spaces
    test al, al
    jz .no_filename1
    ; 读取文件到内存
    call fs_read_file
    jc .cmd_error
    
    inc ebx
    mov ecx, 0
    call shell_scroll
    ; 设置新栈
    ;mov ebp, 0x90000
    ;mov esp, ebp
    
    ; 跳转到二进制文件
    call esi
    inc ebx
    mov ecx, 0
    call shell_scroll
    jmp shell
    
.file_not_found1:
    
    inc ebx
    mov ecx, 0
    mov esi, no_file_msg
    mov ah, 0x0C
    call print_str
    
    ; 显示尝试的文件名
    
    mov ecx, 16
    mov esi, cmd_buffer
    mov ah, 0x0F
    call print_str
    
    inc ebx
    jmp shell
    
.no_filename1:
    inc ebx
    mov ecx, 0
    mov esi, run_usage_msg
    mov ah, 0x0C
    call print_str
    jmp shell

.empty_cmd:
    cmp ebx, 25
    ja .scroll
    inc ebx
    mov ecx, 0
    
    jmp shell

.show_help:
    ; 显示帮助信息
    inc ebx
    mov ecx, 0
    mov esi, help_msg1
    mov ah, 0x0A        ; 绿色帮助信息
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg2
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg3
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg4
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg5
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg6
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg7
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg8
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg9
    call print_str
    
    inc ebx
    mov ecx, 0
    mov esi, help_msg10
    call print_str
    
    inc ebx
    jmp shell

.do_echo:
    ; 跳过"echo"和后续空格
    add esi, 4
    call skip_spaces
    test al, al
    jz .no_args1         ; 无参数情况
    
    ; 显示echo参数
    inc ebx
    mov ecx, 0
    mov ah, 0x0F
    call print_str
    
.no_args1:
    inc ebx             ; 换行
    jmp shell

; === clear命令实现 ===
.do_clear:
    call clear_screen
    mov ebx, 0
    mov ecx, 0
    jmp shell

; === 辅助函数 ===

; 打印命令部分(第一个空格前的内容)
print_command_part:
    pusha
    mov ecx, 26         ; 错误信息后位置
.loop:
    lodsb
    test al, al
    jz .done
    cmp al, ' '
    je .done
    mov ah, 0x0F
    call put_char
    inc ecx
    jmp .loop
.done:
    popa
    ret

; 检查字符串是否为空或只有空格
is_empty:
    push esi
.loop:
    lodsb
    cmp al, ' '
    je .loop
    test al, al
    pop esi
    ret

; 跳过字符串中的空格
skip_spaces:
    lodsb
    cmp al, ' '
    je skip_spaces
    dec esi             ; 回退到第一个非空格字符
    ret

; 命令比较函数
cmd_cmp:
    pusha
.compare:
    mov al, [esi]
    mov bl, [edi]
    
    ; 检查命令是否结束(空格或字符串结束)
    cmp al, ' '
    je .check_cmd_end
    test al, al
    jz .check_cmd_end
    
    ; 转换为小写比较
    cmp al, 'A'
    jb .no_change1
    cmp al, 'Z'
    ja .no_change1
    add al, 0x20
.no_change1:
    cmp bl, 'A'
    jb .no_change2
    cmp bl, 'Z'
    ja .no_change2
    add bl, 0x20
    
.no_change2:
    cmp al, bl
    jne .not_equal
    inc esi
    inc edi
    jmp .compare
    
.check_cmd_end:
    ; 检查命令字符串是否也结束了
    cmp byte [edi], 0
    jne .not_equal
    
.equal:
    popa
    xor eax, eax  ; ZF=1
    ret
    
.not_equal:
    popa
    or eax, 1     ; ZF=0
    ret


shell_scroll:
    cmp ebx, 25
    ja .scroll
    ret
.scroll:
    call scroll_screen
    mov ebx, 24
    mov ecx, 0
    ret

; 显示固定数量的字符
print_nchars:
    pusha
    mov ah, 0x0F
.loop:
    lodsb
    call put_char
    loop .loop
    popa
    ret

print_hex:
    pushad
    mov ecx, 8
.loop:
    rol eax, 4
    mov ebx, eax
    and ebx, 0x0f
    mov bl, [hex_chars + ebx]
    mov ah, 0x0F
    call put_char
    loop .loop
    popad
    ret

do_time:
    call get_time
    inc ebx             ; 换行
    mov ecx, 0
    mov esi, time_str
    mov ah, 0x0F        ; 白色文字
    call print_str
    jmp shell

get_time:
    pushad

    ; 禁用NMI并读取小时
    mov al, 0x04        ; 小时寄存器
    or al, 0x80         ; 禁用NMI
    out 0x70, al
    in al, 0x71
    call bcd_to_ascii
    mov [time_str], dh
    mov [time_str+1], dl

    ; 读取分钟
    mov al, 0x02
    or al, 0x80
    out 0x70, al
    in al, 0x71
    call bcd_to_ascii
    mov [time_str+3], dh
    mov [time_str+4], dl

    ; 读取秒
    mov al, 0x00
    or al, 0x80
    out 0x70, al
    in al, 0x71
    call bcd_to_ascii
    mov [time_str+6], dh
    mov [time_str+7], dl

    popad
    ret

bcd_to_ascii:
    ; 将AL中的BCD码转换为两个ASCII字符，存储在DH和DL中
    mov dh, al
    shr dh, 4
    add dh, '0'
    mov dl, al
    and dl, 0x0F
    add dl, '0'
    ret

; === ls命令实现 ===
do_ls:
    call fs_list_files
    ; 显示文件名
    inc ebx
    mov ecx, 0
    mov ah, 0x0F
    call print_str
    
    ; 换行
    inc ebx
    mov ecx, 0
    
    jmp shell

; === cat命令实现 ===
do_cat:
    ; 跳过"cat"和空格
    add esi, 3
    call skip_spaces
    test al, al
    jz .no_filename
    
    ; 直接调用文件系统
    call fs_read_file
    jc .file_not_found
    
    ; 显示内容 (esi已指向内容字符串)
    inc ebx
    mov ecx, 0          ; 列清零
    call shell_scroll
    mov ah, 0x0F        ; 白色文字
    
.cat_print_loop:
    lodsb               ; 读取字符到 AL
    test al, al         ; 检查字符串结束
    jz .cat_done
    
    cmp al, 0x0A        ; 检查换行符 (\n)
    je .cat_newline
    cmp al, 0x0D        ; 检查换行符 (\n)
    je .cat_print_loop
    
    ; 打印普通字符
    call put_char
    inc ecx             ; 列++
    jmp .cat_print_loop

.cat_newline:
    ; 换行处理
    inc ebx             ; 行++
    mov ecx, 0          ; 列清零
    call shell_scroll
    jmp .cat_print_loop

.cat_done:
    inc ebx             ; 换行
    jmp shell
    
.file_not_found:
    inc ebx
    mov ecx, 0
    call shell_scroll
    mov esi, no_file_msg
    mov ah, 0x0C
    call print_str
    
    ; 显示尝试的文件名
    mov ecx, 16
    mov esi, cmd_buffer+3
    mov ah, 0x0F
    call print_str
    
    inc ebx
    jmp shell
    
.no_filename:
    inc ebx
    mov ecx, 0
    call shell_scroll
    mov esi, cat_usage_msg
    mov ah, 0x0C
    call print_str
    jmp shell

; === photo命令实现 ===
do_photo:
    ; 跳过"cat"和空格
    add esi, 5
    call skip_spaces
    test al, al
    jz .no_filename
    
    ; 直接调用文件系统
    call fs_read_file
    jc .file_not_found
    
    ; 显示内容 (esi已指向内容字符串)
    inc ebx
    mov ecx, 0          ; 列清零
    call shell_scroll
    mov ah, 0x0F        ; 白色文字
    
.cat_print_loop:
    lodsb               ; 读取字符到 AL
    test al, al         ; 检查字符串结束
    jz .cat_done
    
    cmp al, 0x0A        ; 检查换行符 (\n)
    je .cat_newline
    cmp al, 0x0D        ; 检查换行符 (\n)
    je .cat_print_loop
    cmp al, '9'
    je .hex9
    cmp al, 'F'
    je .hexF
    ; 打印普通字符
    sub al, '0'
    mov ah, al
    mov al, ' '
    call put_char
    inc ecx             ; 列++
    jmp .cat_print_loop

.hex9:
    mov ah, 0xCC
    mov al, ' '
    call put_char
    inc ecx             ; 列++
    jmp .cat_print_loop

.hexF:
    mov ah, 0xFF
    mov al, ' '
    call put_char
    inc ecx             ; 列++
    jmp .cat_print_loop


.cat_newline:
    ; 换行处理
    inc ebx             ; 行++
    mov ecx, 0          ; 列清零
    call shell_scroll
    jmp .cat_print_loop

.cat_done:
    inc ebx             ; 换行
    jmp shell
    
.file_not_found:
    inc ebx
    mov ecx, 0
    call shell_scroll
    mov esi, no_file_msg
    mov ah, 0x0C
    call print_str
    
    ; 显示尝试的文件名
    mov ecx, 16
    mov esi, cmd_buffer+3
    mov ah, 0x0F
    call print_str
    
    inc ebx
    jmp shell
    
.no_filename:
    inc ebx
    mov ecx, 0
    call shell_scroll
    mov esi, cat_usage_msg
    mov ah, 0x0C
    call print_str
    jmp shell

; === write命令实现 ===
do_write:
    ; 跳过"write"和空格
    add esi, 5
    call skip_spaces
    test al, al
    jz .no_filename
    
    ; 直接调用文件系统
    call fs_read_file
    jc .file_not_found
    inc ebx
    mov ecx, 0

.read_key:
    call get_key
    test al, al
    jz .read_key
    cmp al, 0x1B
    je .read_key_end
    cmp al, 0x0A
    je .read_new_line
    mov ah, 0x0F
    call put_char
    inc ecx
    mov [esi], al
    inc esi
    jmp .read_key

.read_key_end:
    mov al, 0
    mov [esi], al
    inc ebx
    mov ecx, 0
    jmp shell

.read_new_line:
    inc ebx
    mov ecx, 0
    mov [esi], al
    inc esi
    call shell_scroll
    jmp .read_key

.file_not_found:
    inc ebx
    mov ecx, 0
    mov esi, no_file_msg
    mov ah, 0x0C
    call print_str
    
    ; 显示尝试的文件名
    mov ecx, 16
    mov esi, cmd_buffer+3
    mov ah, 0x0F
    call print_str
    
    inc ebx
    jmp shell
    
.no_filename:
    inc ebx
    mov ecx, 0
    mov esi, cat_usage_msg
    mov ah, 0x0C
    call print_str
    jmp shell



; === vim命令实现 ===
do_vim:
    ; 跳过"vim"和空格
    add esi, 3
    call skip_spaces
    test al, al
    jz .no_filename
    
    ; 直接调用文件系统
    call fs_read_file
    jc .file_not_found

    call clear_screen
    mov ebx, 0
    mov ecx, 0
    push esi
    mov esi, vim_msg
    mov ah, 0x0A
    call print_str
    mov ah, 0x0F
    pop esi

    inc ebx
    mov ecx, 0

.read_key:
    mov al, ' '
    mov ah, 0xFF
    call put_char
    call get_key
    test al, al
    jz .read_key
    cmp al, 0x1B
    je .read_key_end
    cmp al, 0x0A
    je .read_new_line
    cmp al, 0x0D
    je .read_new_line
    cmp al, 0x08
    je .backspace
    mov ah, 0x0F
    call put_char
    inc ecx
    mov [esi], al
    inc esi
    jmp .read_key

.read_key_end:
    mov al, 0
    mov [esi], al
    inc ebx
    mov ecx, 0
    jmp shell

.read_new_line:
    mov al, ' '
    mov ah, 0x0F
    call put_char
    inc ebx
    mov ecx, 0
    mov [esi], al
    inc esi
    call shell_scroll
    jmp .read_key

.file_not_found:
    inc ebx
    mov ecx, 0
    mov esi, no_file_msg
    mov ah, 0x0C
    call print_str
    
    ; 显示尝试的文件名
    mov ecx, 16
    mov esi, cmd_buffer+3
    mov ah, 0x0F
    call print_str
    
    inc ebx
    jmp shell
    
.no_filename:
    inc ebx
    mov ecx, 0
    mov esi, cat_usage_msg
    mov ah, 0x0C
    call print_str
    jmp shell


.backspace:
    ; 退格处理
    mov al, ' '
    mov ah, 0x0F
    call put_char
    cmp ecx, 0
    jz .backspace2
    dec ecx
    mov al, ' '
    mov ah, 0xFF
    call put_char
    jmp .read_key
    
.backspace2:

    mov ecx, 0
    dec ebx
    mov al, ' '
    mov ah, 0xFF
    call put_char
    jmp .read_key

vim_msg db "                              vim  ver0.0.0", 0

; === run命令实现 ===
; 常量定义
PROG_BASE equ 0x100000  ; 程序加载地址 (1MB)
PROG_STACK equ 0x9F000  ; 程序专用栈空间 (64KB)
MAX_SIZE equ 32768      ; 最大程序大小 (32KB)


do_run:
    ; 跳过"run"和空格
    add esi, 3
    call skip_spaces
    test al, al
    jz .no_filename
    
    ; 读取文件到ESI
    call fs_read_file
    jc .file_not_found
    
    ; 保存所有寄存器状态
    pusha
    
    ; 复制程序到固定地址
    mov edi, PROG_BASE
    mov ecx, MAX_SIZE
    cld                 ; 清除方向标志
    rep movsb           ; 复制程序代码
    
    ; 设置程序专用栈
    mov ebp, PROG_STACK
    mov esp, ebp
    
    ; 准备调用环境
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx
    xor esi, esi
    xor edi, edi
    
    ; 跳转到程序
    push .return_point  ; 返回地址
    push PROG_BASE      ; 调用地址
    ret
    
.return_point:
    ; 恢复寄存器状态
    popa
    jmp shell

.file_not_found:
    mov esi, no_file_msg
    call print_str
    jmp shell

.no_filename:
    mov esi, run_usage_msg
    call print_str
    jmp shell

; === ping命令实现 ===
do_ping:
    ; 跳过"ping"和空格
    add esi, 4
    call skip_spaces
    test al, al
    jz .no_ip
    
    ; 调用网络ping功能
    push esi        ; 压入IP字符串指针
    call do_ping_impl
    add esp, 4      ; 清理栈
    
    jmp shell
    
.no_ip:
    ; 显示用法错误
    inc ebx
    mov ecx, 0
    mov esi, ping_usage_msg
    mov ah, 0x0C
    call print_str
    jmp shell

; === sleep命令实现 ===
do_sleep:
    add esi, 5       ; 跳过"sleep"
    call skip_spaces
    test al, al
    jz .invalid
    
    call atoi        ; 将参数转换为毫秒数
    push eax
    call sleep_ms    ; 调用睡眠函数
    add esp, 4
    
    jmp shell
    
.invalid:
    mov esi, sleep_usage_msg
    call print_str
    jmp shell

sleep_usage_msg db "Usage: sleep <milliseconds>", 0

; === task命令实现 ===
do_task:
    add esi, 4       ; 跳过"task"
    call skip_spaces
    test al, al
    jz .invalid
    
    ; 创建新任务
    call create_task
    
    ; 显示任务启动信息
    mov esi, task_start_msg
    call print_str
    mov eax, [current_pid]
    dec eax
    call print_dec
    call newline
    
    jmp shell
    
.invalid:
    mov esi, task_usage_msg
    call print_str
    jmp shell

task_usage_msg db "Usage: task <command>", 0

; === 数字转换函数 ===
; 输入：ESI=字符串指针
; 输出：EAX=数值
atoi:
    push ebx
    push ecx
    push edx
    xor eax, eax        ; 清零结果
    xor ebx, ebx        ; 临时存储字符
    
.convert:
    lodsb               ; 加载下一个字符
    test al, al         ; 检查字符串结束
    jz .done
    
    cmp al, '0'
    jb .invalid
    cmp al, '9'
    ja .invalid
    
    sub al, '0'         ; 转换为数字
    imul ebx, 10        ; 结果 *= 10
    add ebx, eax        ; 结果 += 当前数字
    jmp .convert
    
.invalid:
    xor ebx, ebx        ; 无效输入返回0
    
.done:
    mov eax, ebx        ; 结果存入EAX
    pop edx
    pop ecx
    pop ebx
    ret

; === 命令解析和执行 ===
; 输入：ESI=命令字符串
parse_and_execute:
    pushad
    ; 保存原始命令指针
    mov edi, esi
    
    ; 跳过前导空格
    call skip_spaces
    test al, al
    jz .empty
    

    mov edi, cmd_task
    call cmd_cmp
    je do_task


    ; 检查echo命令
    mov edi, cmd_echo
    call cmd_cmp
    je .do_echo
    
    ; 检查echo命令
    mov edi, cmd_ls
    call cmd_cmp
    je do_ls
    
    
    mov edi, cmd_time
    call cmd_cmp
    je do_time

    mov edi, cmd_cat
    call cmd_cmp
    je do_cat
    
    mov edi, cmd_run
    call cmd_cmp
    je do_run

    
    mov edi, cmd_sleep
    call cmd_cmp
    je do_sleep

    mov edi, cmd_ping
    call cmd_cmp
    je do_ping

    ; 如果不是内置命令，尝试作为外部程序执行
    jmp do_run
    
.empty:
    popad
    ret

.do_echo:
    add esi, 5          ; 跳过"echo "
    call print_str
    popad
    ret

; === 十进制打印函数 ===
; 输入：EAX=要打印的数字
print_dec:
    pushad
    mov ebx, 10         ; 除数
    xor ecx, ecx        ; 数字位数计数器
    
.divide_loop:
    xor edx, edx
    div ebx             ; EDX:EAX / EBX
    push edx            ; 保存余数
    inc ecx
    test eax, eax
    jnz .divide_loop
    
.print_loop:
    pop eax             ; 取出数字
    add al, '0'         ; 转换为ASCII
    mov ah, 0x0F        ; 显示属性
    call put_char
    loop .print_loop
    
    popad
    ret

; === 换行函数 ===
newline:
    xor ecx, ecx
    inc ebx
    ret

; 定义任务结构体
struc task
    .pid:      resd 1      ; 进程ID
    .status:   resd 1      ; 状态 (0=空闲, 1=运行, 2=阻塞)
    .esp:      resd 1      ; 栈指针
    .eip:      resd 1      ; 指令指针
    .cr3:      resd 1      ; 页目录地址
    .cmd:      resb 64     ; 命令字符串
    .regs:     resd 8      ; 保存的寄存器 (EAX, EBX, ECX, EDX, ESI, EDI, EBP, EFLAGS)
endstruc

; 全局变量
[section .data]
current_task dd 0          ; 当前任务指针
task_count dd 0            ; 活动任务数
ticks dd 0                 ; 系统时钟滴答数
task_list times 16*task_size db 0  ; 任务列表(最多16个任务)
current_pid dd 1           ; 下一个PID

; 初始化任务系统
init_task_system:
    pushad
    
    ; 初始化第一个任务(Shell)
    mov edi, task_list
    mov dword [edi + task.pid], 1
    mov dword [edi + task.status], 1
    mov dword [current_task], edi
    inc dword [task_count]
    inc dword [current_pid]
    
    ; 分配栈空间 (16KB)
    push 16384
    call mem_alloc
    add esp, 4
    add eax, 16384 - 32    ; 栈顶
    mov [edi + task.esp], eax
    
    ; 设置初始上下文
    mov dword [eax + 0], 0x202   ; EFLAGS (IF=1)
    mov dword [eax + 4], shell   ; EIP
    mov dword [eax + 8], 0       ; EAX
    mov dword [eax + 12], 0      ; EBX
    mov dword [eax + 16], 0      ; ECX
    mov dword [eax + 20], 0      ; EDX
    mov dword [eax + 24], 0      ; ESI
    mov dword [eax + 28], 0      ; EDI
    mov dword [eax + 32], 0      ; EBP
    
    popad
    ret

; 初始化定时器 (PIT 8254)
init_timer:
    push eax
    
    ; 设置PIT通道0为100Hz
    mov al, 0x36        ; 通道0，模式3，二进制计数
    out 0x43, al
    mov ax, 11932       ; 1193182Hz / 100Hz = 11932
    out 0x40, al        ; 低字节
    mov al, ah
    out 0x40, al        ; 高字节
    
    ; 设置IRQ0处理程序
    mov eax, timer_interrupt
    mov [idt + 8*0x20], word ax         ; 低16位偏移
    mov [idt + 8*0x20 + 2], word 0x08   ; 代码段选择子
    mov [idt + 8*0x20 + 4], byte 0x00   ; 保留
    mov [idt + 8*0x20 + 5], byte 0x8E   ; 类型=中断门, DPL=0
    shr eax, 16
    mov [idt + 8*0x20 + 6], word ax     ; 高16位偏移
    
    pop eax
    ret

; 定时器中断处理 (IRQ0)
timer_interrupt:
    pushad
    
    ; 发送EOI
    mov al, 0x20
    out 0x20, al
    
    ; 更新系统时钟
    inc dword [ticks]
    
    ; 检查是否需要调度
    cmp dword [task_count], 1
    jbe .no_schedule
    
    ; 保存当前任务上下文
    mov edi, [current_task]
    mov [edi + task.esp], esp
    
    ; 保存寄存器状态
    mov eax, [esp + 28]   ; 从pushad中获取EFLAGS
    mov [edi + task.regs + 28], eax
    mov [edi + task.regs + 0], eax
    mov [edi + task.regs + 4], ebx
    mov [edi + task.regs + 8], ecx
    mov [edi + task.regs + 12], edx
    mov [edi + task.regs + 16], esi
    mov [edi + task.regs + 20], edi
    mov [edi + task.regs + 24], ebp
    
    ; 调用调度器
    call schedule
    
.no_schedule:
    popad
    iret

; 任务调度器
schedule:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    
    ; 查找下一个就绪任务
    mov edi, [current_task]
    mov ecx, 16                 ; 最大任务数
    
.next_task:
    add edi, task_size
    cmp edi, task_list + (16 * task_size)
    jb .check_task
    mov edi, task_list
    
.check_task:
    cmp dword [edi + task.status], 1  ; 检查是否运行中
    je .found_task
    loop .next_task
    
    ; 没有找到其他任务，继续运行当前任务
    mov edi, [current_task]
    jmp .switch_done
    
.found_task:
    ; 更新当前任务指针
    mov [current_task], edi
    
    ; 加载新任务的页目录
    mov eax, [edi + task.cr3]
    test eax, eax
    jz .no_paging
    mov cr3, eax
    
.no_paging:
    ; 恢复栈指针
    mov esp, [edi + task.esp]
    
    ; 恢复寄存器状态
    mov eax, [edi + task.regs + 0]
    mov ebx, [edi + task.regs + 4]
    mov ecx, [edi + task.regs + 8]
    mov edx, [edi + task.regs + 12]
    mov esi, [edi + task.regs + 16]
    mov edi, [edi + task.regs + 20]
    mov ebp, [edi + task.regs + 24]
    push dword [edi + task.regs + 28]  ; EFLAGS
    popfd
    
.switch_done:
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret

; 创建新任务
; 输入: ESI=命令字符串
create_task:
    pushad
    
    ; 查找空闲任务槽
    mov edi, task_list
    mov ecx, 16
.find_slot:
    cmp dword [edi + task.status], 0
    je .found_slot
    add edi, task_size
    loop .find_slot
    
    ; 无可用槽位
    mov esi, task_full_msg
    call print_str
    jmp .exit
    
.found_slot:
    ; 设置任务信息
    mov eax, [current_pid]
    mov [edi + task.pid], eax
    inc dword [current_pid]
    mov dword [edi + task.status], 1  ; 运行中
    
    ; 复制命令
    push esi
    push edi
    add edi, task.cmd
    mov ecx, 64
.copy_cmd:
    lodsb
    test al, al
    jz .copy_done
    stosb
    loop .copy_cmd
.copy_done:
    pop edi
    pop esi
    
    ; 分配栈空间 (16KB)
    push 16384
    call mem_alloc
    add esp, 4
    mov [edi + task.esp], eax
    add eax, 16384 - 32  ; 栈顶
    
    ; 设置初始上下文
    mov dword [eax + 0], 0x202   ; EFLAGS (IF=1)
    mov dword [eax + 4], task_entry  ; EIP
    mov dword [eax + 8], 0       ; EAX
    mov dword [eax + 12], 0      ; EBX
    mov dword [eax + 16], 0      ; ECX
    mov dword [eax + 20], 0      ; EDX
    mov dword [eax + 24], 0      ; ESI
    mov dword [eax + 28], 0      ; EDI
    mov dword [eax + 32], 0      ; EBP
    
    ; 设置页目录 (如果启用分页)
    mov dword [edi + task.cr3], 0  ; 暂时不使用分页
    
    inc dword [task_count]
    
.exit:
    popad
    ret

; 任务入口点
task_entry:
    ; 解析并执行命令
    mov esi, [current_task]
    add esi, task.cmd
    call parse_and_execute
    
    ; 任务退出
    call task_exit

; 任务退出处理
task_exit:
    pushad
    
    ; 标记任务为结束
    mov edi, [current_task]
    mov dword [edi + task.status], 0
    
    ; 释放栈空间
    push dword [edi + task.esp]
    call mem_free
    add esp, 4
    
    dec dword [task_count]
    
    ; 切换到下一个任务
    call schedule
    
    ; 这里不会执行，因为已经切换到其他任务
    popad
    ret

; 睡眠函数 (毫秒)
; 输入: 毫秒数 (栈上)
sleep_ms:
    push ebx
    mov ebx, [esp+8]  ; 获取毫秒数
    
    ; 简单延时实现（实际OS中应使用定时器中断）
    mov eax, 10000    ; 根据CPU速度调整
    mul ebx
    mov ecx, eax
.delay_loop:
    pause
    loop .delay_loop
    
    pop ebx
    ret 4

; 任务列表显示
do_tasks:
    pushad
    
    mov esi, task_list
    mov ecx, 16
    
.task_loop:
    cmp dword [esi + task.status], 0
    je .next_task
    
    ; 显示PID
    mov eax, [esi + task.pid]
    call print_dec
    mov al, ' '
    call put_char
    
    ; 显示状态
    mov eax, [esi + task.status]
    cmp eax, 1
    je .running
    cmp eax, 2
    je .blocked
    mov al, '?'
    jmp .print_status
.running:
    mov al, 'R'
    jmp .print_status
.blocked:
    mov al, 'B'
.print_status:
    call put_char
    mov al, ' '
    call put_char
    
    ; 显示命令
    push esi
    add esi, task.cmd
    call print_str
    pop esi
    
    call newline
    
.next_task:
    add esi, task_size
    loop .task_loop
    
    popad
    jmp shell

; 任务管理相关消息
task_full_msg db "Error: No available task slots", 0
task_start_msg db "Started task PID: ", 0

; === 光标闪烁任务 ===
; 在系统初始化时添加这个任务
init_cursor_task:
    push esi
    push edi
    
    ; 查找空闲任务槽
    mov edi, task_list
    mov ecx, 16
.find_slot:
    cmp dword [edi + task.status], 0
    je .found_slot
    add edi, task_size
    loop .find_slot
    jmp .exit  ; 没有可用槽位
    
.found_slot:
    ; 设置任务信息
    mov eax, [current_pid]
    mov [edi + task.pid], eax
    inc dword [current_pid]
    mov dword [edi + task.status], 1  ; 运行中
    
    ; 设置任务命令
    mov byte [edi + task.cmd], 0  ; 空命令
    
    ; 分配栈空间 (4KB)
    push 4096
    call mem_alloc
    add esp, 4
    mov [edi + task.esp], eax
    add eax, 4096 - 32  ; 栈顶
    
    ; 设置初始上下文
    mov dword [eax + 0], 0x202   ; EFLAGS (IF=1)
    mov dword [eax + 4], cursor_task_entry  ; EIP
    mov dword [eax + 8], 0       ; EAX
    mov dword [eax + 12], 0      ; EBX
    mov dword [eax + 16], 0      ; ECX
    mov dword [eax + 20], 0      ; EDX
    mov dword [eax + 24], 0      ; ESI
    mov dword [eax + 28], 0      ; EDI
    mov dword [eax + 32], 0      ; EBP
    
    inc dword [task_count]
    
.exit:
    pop edi
    pop esi
    ret

; 光标任务入口点
cursor_task_entry:
    ; 获取当前光标位置 (需要根据你的系统实现)
    ; 这里假设ebx=行, ecx=列
    mov ebx, [current_line]
    mov ecx, [current_column]
    
    ; 无限循环实现闪烁
.cursor_loop:
    ; 显示白色光标(0xFF空格)
    mov al, ' '
    mov ah, 0xFF
    call put_char_at
    
    ; 延时约300ms
    push 300
    call sleep_ms
    add esp, 4
    
    ; 显示黑色光标(0x00空格)
    mov al, ' '
    mov ah, 0x00
    call put_char_at
    
    ; 延时约300ms
    push 300
    call sleep_ms
    add esp, 4
    
    jmp .cursor_loop

; 在指定位置显示字符
; 输入: ebx=行, ecx=列, al=字符, ah=属性
put_char_at:
    push edi
    push eax
    
    ; 计算显存位置 (假设80x25文本模式)
    mov eax, ebx
    mov edi, 80
    mul edi
    add eax, ecx
    shl eax, 1  ; 每个字符占2字节
    
    ; 写入显存
    add eax, 0xB8000  ; 文本模式显存地址
    mov edi, eax
    pop eax
    mov [edi], ax
    
    pop edi
    ret



; 全局变量
[section .data]
current_line dd 0
current_column dd 0
cursor_state db 0  ; 0=关闭, 1=打开

[section .bss]
filename_buffer resb 32  ; 存储临时文件名

; === 数据区 ===
[section .data]
ping_usage_msg db "Usage: ping <ip>", 0
no_file_msg db "File not found: ", 0
cat_usage_msg db "Usage: cat <filename>", 0
hex_chars db '0123456789ABCDEF'
invalid_type_msg db "Not an executable ELF", 0
invalid_arch_msg db "Unsupported architecture", 0
no_segments_msg db "No loadable segments", 0
alloc_failed_msg db "Memory allocation failed", 0
run_error_msg db "Error: Cannot execute file: ", 0
invalid_elf_msg db "Error: Not a valid ELF file", 0
run_usage_msg db "Usage: run <filename>", 0
exec_success_msg db "Program exited with code: ", 0

