; 文件系统实现 - 从root目录构建
section .data
global fs_files_count
fs_files_count dd 3

; 文件系统API
global fs_init, fs_list_files, fs_read_file, fs_get_file_size

section .text

fs_init:
    ret

fs_list_files:
    mov esi, file_names
    ret

fs_read_file:
    ; EDI = 文件名
    ; 返回: ESI = 文件内容
    mov edi, esi

    mov esi, file_qwe_name
    call str_compare
    je .found_1

    mov esi, file_123_name
    call str_compare
    je .found_2

    mov esi, file_a_name
    call str_compare
    je .found_3

    stc
    ret

.found_1:
    mov esi, file_qwe_content_str
    clc
    ret

.found_2:
    mov esi, file_123_content_str
    clc
    ret

.found_3:
    mov esi, file_a_content_str
    clc
    ret

fs_get_file_size:
    ; EDI = 文件名
    ; 返回: ECX = 文件大小
    mov edi, esi

    mov esi, file_qwe_name
    call str_compare
    jne .next_0
    mov ecx, 8
    ret
.next_0:

    mov esi, file_123_name
    call str_compare
    jne .next_1
    mov ecx, 3
    ret
.next_1:

    mov esi, file_a_name
    call str_compare
    jne .next_2
    mov ecx, 66
    ret
.next_2:

    xor ecx, ecx
    ret

str_compare:
    push eax
    push esi
    push edi
.loop:
    mov al, [esi]
    cmp al, [edi]
    jne .not_equal
    test al, al
    jz .equal
    inc esi
    inc edi
    jmp .loop
.equal:
    xor eax, eax
    jmp .done
.not_equal:
    or eax, 1
.done:
    pop edi
    pop esi
    pop eax
    ret

section .data
file_names db 'qwe.txt ', '123.txt ', 'a.bin ',0


; 文件: qwe.txt
file_qwe_name db 'qwe.txt',0
file_qwe_content_str db 0x31,0x0d,0x0a,0x68,0x65,0x6c,0x6c,0x6f,0

; 文件: 123.txt
file_123_name db '123.txt',0
file_123_content_str db 0x36,0x36,0x36,0

; 文件: a.bin
file_a_name db 'a.bin',0
file_a_content_str db 0x66,0xb8,0x00,0x00,0x00,0x00,0xb2,0x48,0xb6,0x0f,0xcd,0x80,0x66,0x41,0xb2,0x65,0xcd,0x80,0x66,0x41,0xb2,0x6c,0xcd,0x80,0x66,0x41,0xb2,0x6c,0xcd,0x80,0x66,0x41,0xb2,0x6f,0xcd,0x80,0x66,0x41,0xb2,0x21,0xcd,0x80,0x66,0x41,0xb2,0x21,0xcd,0x80,0xe9,0xf9,0xff,0xc3,0x48,0x65,0x6c,0x6c,0x6f,0x2c,0x20,0x57,0x6f,0x72,0x6c,0x64,0x21,0x00,0
