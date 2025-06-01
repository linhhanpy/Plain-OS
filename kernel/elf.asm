; elf.asm - 完整ELF加载器实现

[bits 32]

section .text

extern mem_alloc, mem_free, print_str
global elf_load, elf_get_entry

; ELF相关常量
ELF_MAGIC equ 0x464C457F  ; "\x7FELF"
PT_LOAD   equ 1

; 结构体定义
struc Elf32_Ehdr
    .e_ident     resb 16
    .e_type      resw 1
    .e_machine   resw 1
    .e_version   resd 1
    .e_entry     resd 1
    .e_phoff     resd 1
    .e_shoff     resd 1
    .e_flags     resd 1
    .e_ehsize    resw 1
    .e_phentsize resw 1
    .e_phnum     resw 1
    .e_shentsize resw 1
    .e_shnum     resw 1
endstruc

struc Elf32_Phdr
    .p_type   resd 1
    .p_offset resd 1
    .p_vaddr  resd 1
    .p_paddr  resd 1
    .p_filesz resd 1
    .p_memsz  resd 1
    .p_flags  resd 1
    .p_align  resd 1
endstruc

section .bss
elf_entry_point resd 1

section .data
invalid_elf_msg db "Invalid ELF format", 0
invalid_type_msg db "Not an executable ELF", 0
invalid_arch_msg db "Unsupported architecture", 0
no_segments_msg db "No loadable segments", 0
alloc_failed_msg db "Memory allocation failed", 0

section .text

; elf_load - 加载ELF文件
; 输入: ESI = ELF文件数据指针
; 输出: CF=1表示错误，CF=0表示成功
elf_load:
    pusha
    
    ; 检查ELF魔数
    cmp dword [esi], ELF_MAGIC
    jne .invalid_elf
    
    ; 检查是否是可执行文件
    cmp word [esi + Elf32_Ehdr.e_type], 2  ; ET_EXEC
    jne .invalid_type
    
    ; 检查架构是否是i386
    cmp word [esi + Elf32_Ehdr.e_machine], 3  ; EM_386
    jne .invalid_arch
    
    ; 保存入口点
    mov eax, [esi + Elf32_Ehdr.e_entry]
    mov [elf_entry_point], eax
    
    ; 遍历程序头表
    movzx ecx, word [esi + Elf32_Ehdr.e_phnum]
    test ecx, ecx
    jz .no_segments
    
    mov ebx, [esi + Elf32_Ehdr.e_phoff]
    add ebx, esi  ; EBX = 第一个程序头
    
.load_segments:
    ; 检查段类型
    cmp dword [ebx + Elf32_Phdr.p_type], PT_LOAD
    jne .next_segment
    
    ; 检查内存大小
    mov edx, [ebx + Elf32_Phdr.p_memsz]
    test edx, edx
    jz .next_segment
    
    ; 分配内存
    push esi
    push ecx
    push ebx
    
    mov ecx, edx
    call mem_alloc
    test eax, eax
    jz .alloc_failed
    
    ; 复制段内容
    mov edi, eax  ; EDI = 目标地址
    mov esi, [ebx + Elf32_Phdr.p_offset]
    add esi, [esp + 8]  ; 原始ESI值在栈上
    mov ecx, [ebx + Elf32_Phdr.p_filesz]
    rep movsb
    
    ; 清零.bss部分
    mov ecx, [ebx + Elf32_Phdr.p_memsz]
    sub ecx, [ebx + Elf32_Phdr.p_filesz]
    jz .no_bss
    xor al, al
    rep stosb
    
.no_bss:
    pop ebx
    pop ecx
    pop esi
    
.next_segment:
    movzx eax, word [esi + Elf32_Ehdr.e_phentsize]
    add ebx, eax
    dec ecx
    jnz .load_segments
    
    clc
    popa
    ret
    
.alloc_failed:
    pop ebx
    pop ecx
    pop esi
    mov esi, alloc_failed_msg
    jmp .error
    
.invalid_elf:
    mov esi, invalid_elf_msg
    jmp .error
    
.invalid_type:
    mov esi, invalid_type_msg
    jmp .error
    
.invalid_arch:
    mov esi, invalid_arch_msg
    jmp .error
    
.no_segments:
    mov esi, no_segments_msg
    jmp .error
    
.error:
    mov ah, 0x0C
    call print_str
    stc
    popa
    ret

; elf_get_entry - 获取入口点地址
; 输出: EAX = 入口点地址
elf_get_entry:
    mov eax, [elf_entry_point]
    ret
    