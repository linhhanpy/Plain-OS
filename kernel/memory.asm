; memory.asm - 完整内存管理实现
[bits 32]

section .data
mem_start      dd 0x1000000   ; 起始地址 (16MB)
mem_current    dd 0x1000000   ; 当前分配指针
mem_top        dd 0x2000000   ; 最大内存地址 (32MB)
free_list_head dd 0           ; 空闲链表头指针

; 内存块结构
struc mem_block
    .size   resd 1  ; 块大小（包括头部）
    .next   resd 1  ; 下一个空闲块
endstruc

section .text

; 初始化内存管理
global mem_init
mem_init:
    ; 建立初始空闲块（整个可用空间）
    mov eax, [mem_start]
    mov [eax + mem_block.size], dword 0x1000000  ; 16MB
    mov [eax + mem_block.next], dword 0          ; 无下一个块
    mov [free_list_head], eax
    ret

; mem_alloc - 分配内存（首次适应算法）
; 输入: ECX = 请求的字节数
; 输出: EAX = 分配的内存地址 (0表示失败)
global mem_alloc
mem_alloc:
    push ebx
    push esi
    push edi
    
    ; 计算需要的大小（加上头部，对齐到8字节）
    add ecx, mem_block_size + 7
    and ecx, 0xFFFFFFF8
    
    ; 遍历空闲链表
    mov esi, [free_list_head]
    mov edi, 0           ; 指向前一个块的指针
    
.search_loop:
    test esi, esi
    jz .no_memory
    
    ; 检查当前块是否足够大
    mov eax, [esi + mem_block.size]
    cmp eax, ecx
    jb .next_block
    
    ; 找到合适块 - 分割或直接使用
    mov ebx, eax         ; 原始大小
    sub eax, ecx         ; 剩余大小
    cmp eax, 16          ; 剩余块最小大小
    jb .use_whole_block
    
    ; 分割块
    mov [esi + mem_block.size], ecx  ; 设置分配块大小
    lea edx, [esi + ecx]             ; 新空闲块地址
    mov [edx + mem_block.size], eax  ; 设置剩余块大小
    mov eax, [esi + mem_block.next]
    mov [edx + mem_block.next], eax  ; 继承next指针
    
    ; 更新链表
    test edi, edi
    jz .update_head
    mov [edi + mem_block.next], edx
    jmp .return_block
    
.update_head:
    mov [free_list_head], edx
    jmp .return_block
    
.use_whole_block:
    ; 使用整个块
    mov eax, [esi + mem_block.next]
    test edi, edi
    jz .update_head_whole
    mov [edi + mem_block.next], eax
    jmp .return_block
    
.update_head_whole:
    mov [free_list_head], eax
    
.return_block:
    ; 返回分配的内存（跳过头部）
    lea eax, [esi + mem_block_size]
    jmp .done
    
.next_block:
    mov edi, esi
    mov esi, [esi + mem_block.next]
    jmp .search_loop
    
.no_memory:
    xor eax, eax
    
.done:
    pop edi
    pop esi
    pop ebx
    ret

; mem_free - 释放内存（带合并功能）
; 输入: EAX = 内存地址
global mem_free
mem_free:
    push ebx
    push esi
    push edi
    
    ; 获取块头部
    sub eax, mem_block_size
    mov esi, eax
    
    ; 遍历空闲链表寻找插入位置
    mov edi, [free_list_head]
    mov ebx, 0           ; 前一个块指针
    
.search_loop:
    test edi, edi
    jz .insert_end
    cmp edi, esi
    ja .found_position
    mov ebx, edi
    mov edi, [edi + mem_block.next]
    jmp .search_loop
    
.found_position:
    ; 检查是否可以与前一个块合并
    test ebx, ebx
    jz .check_next
    
    ; 计算前一个块的结束地址
    mov edx, ebx
    add edx, [ebx + mem_block.size]
    cmp edx, esi
    jne .check_next
    
    ; 合并到前一个块
    mov edx, [esi + mem_block.size]
    add [ebx + mem_block.size], edx
    
    ; 检查是否可以与后一个块合并
    mov esi, ebx        ; esi现在指向合并后的块
    mov edi, [ebx + mem_block.next]
    
.check_next:
    ; 检查是否可以与后一个块合并
    test edi, edi
    jz .insert_block
    
    mov edx, esi
    add edx, [esi + mem_block.size]
    cmp edx, edi
    jne .insert_block
    
    ; 合并到当前块
    mov edx, [edi + mem_block.size]
    add [esi + mem_block.size], edx
    mov edx, [edi + mem_block.next]
    mov [esi + mem_block.next], edx
    jmp .update_list
    
.insert_block:
    ; 不能合并，直接插入
    mov [esi + mem_block.next], edi
    
.update_list:
    test ebx, ebx
    jz .update_head
    mov [ebx + mem_block.next], esi
    jmp .done
    
.insert_end:
    ; 插入到链表末尾
    test ebx, ebx
    jz .update_head
    mov [ebx + mem_block.next], esi
    mov [esi + mem_block.next], dword 0
    jmp .done
    
.update_head:
    mov [free_list_head], esi
    
.done:
    pop edi
    pop esi
    pop ebx
    ret

; mem_get_stats - 获取内存统计信息
; 输出: EAX = 总内存大小
;       EBX = 已用内存
;       ECX = 空闲内存
global mem_get_stats
mem_get_stats:
    push edx
    push esi
    
    ; 计算总内存
    mov eax, [mem_top]
    sub eax, [mem_start]
    
    ; 计算空闲内存
    xor ecx, ecx
    mov esi, [free_list_head]
    
.free_loop:
    test esi, esi
    jz .calc_used
    add ecx, [esi + mem_block.size]
    mov esi, [esi + mem_block.next]
    jmp .free_loop
    
.calc_used:
    ; 已用内存 = 总内存 - 空闲内存
    mov ebx, eax
    sub ebx, ecx
    
    pop esi
    pop edx
    ret
    