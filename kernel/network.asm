; network.asm - 完整网络协议栈实现
[bits 32]
KERNEL_CS equ 0x08
KERNEL_DS equ 0x10
; 网络相关定义
%define ETH_ALEN      6      ; 以太网地址长度
%define IP_ALEN       4      ; IP地址长度
%define ETH_HLEN      14     ; 以太网头部长度
%define IP_HLEN       20     ; IP头部长度
%define ICMP_HLEN     8      ; ICMP头部长度
%define ARP_HLEN      28     ; ARP包长度

; 协议类型
%define ETH_P_IP      0x0800 ; IP协议
%define ETH_P_ARP     0x0806 ; ARP协议
%define IP_PROTO_ICMP 1      ; ICMP协议
%define IP_PROTO_TCP  6      ; TCP协议
%define IP_PROTO_UDP  17     ; UDP协议

; ICMP类型
%define ICMP_ECHO_REPLY   0
%define ICMP_ECHO_REQUEST 8

; 网卡I/O基地址 (假设使用NE2000兼容网卡)
%define NIC_IO_BASE   0x300
%define NIC_IRQ       10

; 数据结构
struc eth_header
    .dest_mac:   resb ETH_ALEN
    .src_mac:    resb ETH_ALEN
    .ethertype:  resw 1
endstruc

struc ip_header
    .ver_ihl:    resb 1
    .tos:        resb 1
    .tot_len:    resw 1
    .id:         resw 1
    .frag_off:   resw 1
    .ttl:        resb 1
    .protocol:   resb 1
    .check:      resw 1
    .saddr:      resb IP_ALEN
    .daddr:      resb IP_ALEN
endstruc

struc icmp_header
    .type:       resb 1
    .code:       resb 1
    .checksum:   resw 1
    .unused:     resw 1
    .unused2:    resw 1
endstruc

struc arp_header
    .htype:      resw 1
    .ptype:      resw 1
    .hlen:       resb 1
    .plen:       resb 1
    .oper:       resw 1
    .sha:        resb ETH_ALEN
    .spa:        resb IP_ALEN
    .tha:        resb ETH_ALEN
    .tpa:        resb IP_ALEN
endstruc

[section .data]
; 网络配置
my_mac     db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56  ; 默认MAC
my_ip      db 192, 168, 1, 2                      ; 默认IP
netmask    db 255, 255, 255, 0                    ; 子网掩码
gateway    db 192, 168, 1, 1                      ; 网关
ttl_msg    db " TTL=", 0
; ARP缓存 (简单实现)
arp_cache:
    times 16 db 0  ; 每个条目20字节(IP+MAC+状态)

; 接收缓冲区
packet_buffer:
    times 2048 db 0

; 发送缓冲区
tx_buffer:
    times 2048 db 0

; 中断描述符表 (IDT)
align 8
idt:
    times 256 dq 0  ; 256个门描述符，每个8字节
idt_ptr:
    dw 256*8 - 1    ; IDT界限 = 大小 - 1
    dd idt          ; IDT线性基地址

ping_timeout    dd 0     ; 超时计数器
ping_seq        dw 0     ; 当前序列号
ping_count      db 0     ; 已接收的ping回复计数
ping_received   db 0     ; 接收到ping回复标志

; 消息文本
ping_timeout_msg db " Request timed out", 0
ping_stats_msg   db "Packets: Sent=%d, Received=%d", 0
net_init_msg   db "Initializing network...", 0
net_ready_msg  db "Network ready", 0
reset_fail_msg db "NIC reset failed!", 0
arp_req_msg    db "ARP request sent", 0
ping_sent_msg  db "Ping sent to ", 0
ping_recv_msg  db "Ping reply from ", 0
net_err_msg    db "Network error", 0
no_nic_msg db "Error: No NIC detected at I/O base 0x300", 0
reset_fail_detail_msg db "Reset failed, status: ", 0
nic_present db "NE2000 is ready",0

[section .text]
extern print_str, put_char
global init_network, send_packet, receive_packet
global do_ping_impl, net_interrupt_handler

; 初始化网络
init_network:
    pushad
    
    xor ecx, ecx
    inc ebx
    ; Display initialization message
    mov esi, net_init_msg
    call print_str
    
    ; Initialize NIC
    call nic_init
    test eax, eax
    jz .error
    
    ; Set up network interrupt
    mov al, NIC_IRQ
    mov bl, 0x8E  ; Interrupt gate, DPL=0
    mov esi, net_interrupt_handler
    call set_interrupt_gate
    
    ; Enable IRQ in PIC (Critical!)
    mov dx, 0x21    ; PIC1 data port
    in al, dx
    and al, ~(1 << (NIC_IRQ % 8))  ; Clear bit to enable interrupt
    out dx, al
    
    ; Display ready message
    mov esi, net_ready_msg
    call print_str
    
    popad
    ret
    
.error:
    mov ah, 0x0C    ; Red color
    xor ecx, ecx
    inc ebx
    mov esi, net_err_msg
    call print_str
    popad
    ret

; NIC Initialization
nic_init:
    pushad
    
    ; 1. 验证网卡存在
    mov dx, NIC_IO_BASE + 0x01
    in al, dx
    cmp al, 0xFF
    je .no_nic
    
    ; 2. 发送复位命令（带双重验证）
    mov dx, NIC_IO_BASE + 0x18
    mov al, 0x80
    out dx, al
    
    ; 3. 延长等待时间（约2秒）
    mov ecx, 2000000
.reset_wait:
    in al, dx
    test al, 0x80
    jz .reset_done
    pause
    loop .reset_wait
    
    ; 4. 显示详细错误信息
    mov esi, .reset_fail_msg
    call print_str
    in al, dx
    call print_hex
    
    ; 5. 尝试软件复位
    mov dx, NIC_IO_BASE + 0x1F
    mov al, 0x00
    out dx, al
    jmp .error

.reset_done:
    ; 6. 初始化关键寄存器
    mov dx, NIC_IO_BASE + 0x0E  ; DCR
    mov al, 0x58
    out dx, al
    
    mov dx, NIC_IO_BASE + 0x0C  ; RCR
    mov al, 0x20
    out dx, al
    
    mov esi, .success_msg
    call print_str
    popad
    mov eax, 1
    ret

.no_nic:
    mov esi, .no_nic_msg
    call print_str
.error:
    popad
    xor eax, eax
    ret

.no_nic_msg db "Error: NE2000 compatible NIC not detected at I/O base 0x300", 0
.reset_fail_msg db "NIC reset failed, status: 0x", 0
.success_msg db "NE2000 NIC initialized successfully", 0

; 网络中断处理
net_interrupt_handler:
    pushad
    
    ; 检查中断源
    mov dx, NIC_IO_BASE + 0x0E
    in al, dx
    test al, al
    jz .done
    
    ; 处理接收中断
    test al, 0x01
    jz .no_rx
    call handle_receive
.no_rx:
    
    ; 确认中断
    out dx, al
    
.done:
    popad
    iret

; 接收处理
handle_receive:
    pushad
    
    ; 检查是否有数据包
    mov dx, NIC_IO_BASE + 0x0C
    in al, dx
    test al, 0x01
    jz .done
    
    ; 读取数据包长度
    mov dx, NIC_IO_BASE + 0x0B
    in al, dx
    movzx ecx, al
    
    ; 读取数据包
    mov dx, NIC_IO_BASE + 0x10
    mov edi, packet_buffer
    rep insb
    
    ; 处理数据包
    call process_packet
    
.done:
    popad
    ret

; 处理接收到的数据包
process_packet:
    pushad
    
    ; 检查以太网类型
    mov esi, packet_buffer
    mov ax, [esi + eth_header.ethertype]
    xchg al, ah  ; 转换为网络字节序
    
    cmp ax, ETH_P_IP
    je .ip_packet
    cmp ax, ETH_P_ARP
    je .arp_packet
    
    jmp .done
    
.ip_packet:
    ; 处理IP包
    add esi, ETH_HLEN
    mov al, [esi + ip_header.protocol]
    
    cmp al, IP_PROTO_ICMP
    je .icmp_packet
    
    jmp .done
    
.icmp_packet:
    ; 处理ICMP包
    add esi, IP_HLEN
    mov al, [esi + icmp_header.type]
    
    cmp al, ICMP_ECHO_REPLY
    je .ping_reply
    
    jmp .done
    
.ping_reply:
    ; 检查是否是我们的ping回复
    ; 比较标识符和序列号(简化处理)
    mov ax, [esi + icmp_header.unused]
    cmp ax, 0x1234      ; 与我们发送的标识符比较
    jne .done
    
    ; 设置接收标志
    mov byte [ping_received], 1
    
    ; 显示回复信息
    push esi
    mov esi, ping_recv_msg
    call print_str
    
    ; 显示源IP
    mov esi, packet_buffer + ETH_HLEN + ip_header.saddr
    call print_ip
    
    ; 显示TTL
    mov esi, ttl_msg    ; " TTL="
    call print_str
    mov al, [packet_buffer + ETH_HLEN + ip_header.ttl]
    call print_dec
    
    call newline
    pop esi
    
    jmp .done
    
.arp_packet:
    ; 处理ARP包
    add esi, ETH_HLEN
    mov ax, [esi + arp_header.oper]
    xchg al, ah
    
    cmp ax, 1  ; ARP请求
    je .arp_request
    cmp ax, 2  ; ARP回复
    je .arp_reply
    
    jmp .done
    
.arp_request:
    ; 处理ARP请求
    call handle_arp_request
    jmp .done
    
.arp_reply:
    ; 处理ARP回复
    call handle_arp_reply
    
.done:
    popad
    ret

; 发送数据包
send_packet:
    pushad
    push es
    
    ; 设置发送缓冲区
    mov esi, [esp + 44]  ; 数据指针
    mov ecx, [esp + 48]  ; 数据长度
    
    ; 检查长度
    cmp ecx, 2048
    ja .error
    
    ; 复制数据到发送缓冲区
    mov edi, tx_buffer
    rep movsb
    
    ; 发送数据包
    mov dx, NIC_IO_BASE + 0x04  ; 发送命令端口
    mov al, 0x01  ; 发送命令
    out dx, al
    
    pop es
    popad
    ret
    
.error:
    pop es
    popad
    xor eax, eax
    ret

; 处理ARP请求
handle_arp_request:
    pushad
    
    ; 检查是否是我们的IP
    mov esi, packet_buffer + ETH_HLEN + arp_header.tpa
    mov edi, my_ip
    mov ecx, IP_ALEN
    repe cmpsb
    jne .done
    
    ; 构造ARP回复
    mov edi, tx_buffer
    
    ; 以太网头部
    mov esi, packet_buffer + eth_header.src_mac
    mov ecx, ETH_ALEN
    rep movsb  ; 目标MAC
    
    mov esi, my_mac
    mov ecx, ETH_ALEN
    rep movsb  ; 源MAC
    
    mov ax, ETH_P_ARP
    xchg al, ah
    stosw      ; 以太网类型
    
    ; ARP头部
    mov ax, 0x0001  ; 硬件类型(以太网)
    stosw
    mov ax, ETH_P_IP ; 协议类型(IP)
    stosw
    mov al, ETH_ALEN ; 硬件地址长度
    stosb
    mov al, IP_ALEN  ; 协议地址长度
    stosb
    mov ax, 0x0200   ; 操作码(回复)
    stosw
    
    ; 发送方MAC和IP
    mov esi, my_mac
    mov ecx, ETH_ALEN
    rep movsb
    
    mov esi, my_ip
    mov ecx, IP_ALEN
    rep movsb
    
    ; 目标MAC和IP
    mov esi, packet_buffer + eth_header.src_mac
    mov ecx, ETH_ALEN
    rep movsb
    
    mov esi, packet_buffer + ETH_HLEN + arp_header.spa
    mov ecx, IP_ALEN
    rep movsb
    
    ; 发送ARP回复
    mov ecx, edi
    sub ecx, tx_buffer
    push ecx
    push tx_buffer
    call send_packet
    
.done:
    popad
    ret

; 处理ARP回复
handle_arp_reply:
    ; 更新ARP缓存 (简化实现)
    ret

; 发送ping请求
do_ping_impl:
    pushad
    push es
    push ds
    
    ; 设置内核数据段
    mov ax, KERNEL_DS
    mov ds, ax
    mov es, ax
    
    ; 初始化计数器
    mov word [ping_seq], 0
    mov byte [ping_count], 0
    
    ; 解析目标IP
    mov esi, [esp + 44]  ; 获取IP字符串指针
    call parse_ip
    test eax, eax
    jz .error
    
    ; 保存目标IP指针
    mov edx, eax
    
    ; 发送4个ping请求(标准ping行为)
    mov ecx, 4
.send_loop:
    ; 构造ICMP包
    call build_icmp_packet
    
    ; 发送数据包
    push ecx
    push edx
    
    mov ecx, edi
    sub ecx, tx_buffer ; 计算包长度
    push ecx
    push tx_buffer
    call send_packet
    add esp, 8
    
    ; 显示发送消息
    mov ah, 0x0F
    inc ebx
    mov ecx, 0
    push esi
    mov esi, ping_sent_msg
    call print_str
    pop esi
    ;mov esi, [esp + 44] ; 获取IP字符串指针
    call print_str
    
    ; 等待回复(约1秒)
    mov dword [ping_timeout], 0
.wait_reply:
    inc dword [ping_timeout]
    cmp dword [ping_timeout], 1000000  ; 超时值，根据CPU速度调整
    jae .timeout
    
    ; 检查是否有接收到的包
    cmp byte [ping_received], 0
    jne .got_reply
    
    ; 短暂延迟
    push ecx
    mov ecx, 1000
.delay:
    nop
    loop .delay
    pop ecx
    
    jmp .wait_reply
    
.timeout:
    ; 显示超时信息
    inc ebx
    mov ecx, 0
    mov esi, 0
    mov esi, ping_timeout_msg
    call print_str
    jmp .next_ping
    
.got_reply:
    ; 已收到回复，计数器递增
    inc byte [ping_count]
    mov byte [ping_received], 0
    
.next_ping:
    call newline
    pop edx
    pop ecx
    dec ecx            ; 递减计数器
    jnz .send_loop     ; 如果ecx≠0则继续循环
    
    ; 显示统计信息
    mov esi, ping_stats_msg
    call print_str
    movzx eax, byte [ping_count]
    push eax
    push 4
    call print_dec  ; 实现打印十进制数的函数
    add esp, 8
    
    jmp .done
    
.error:
    mov esi, net_err_msg
    call print_str
    
.done:
    pop ds
    pop es
    popad
    ret

; 构建ICMP包
build_icmp_packet:
    mov edi, tx_buffer
    
    ; 1. 以太网头部
    ; 源MAC
    mov esi, my_mac
    mov ecx, ETH_ALEN
    rep movsb
    
    ; 目标MAC (广播)
    mov al, 0xFF
    mov ecx, ETH_ALEN
    rep stosb
    
    ; 以太网类型(IP)
    mov ax, ETH_P_IP
    xchg al, ah
    stosw
    
    ; 2. IP头部
    mov al, 0x45       ; 版本4 + 头部长度5字
    stosb
    xor al, al         ; 服务类型
    stosb
    mov ax, (IP_HLEN + ICMP_HLEN + 32) ; 总长度
    xchg al, ah
    stosw
    mov ax, [ping_seq] ; 使用序列号作为标识
    stosw
    xor ax, ax         ; 分片偏移
    stosw
    mov al, 64         ; TTL
    stosb
    mov al, IP_PROTO_ICMP ; 协议
    stosb
    xor ax, ax         ; 校验和(先置0)
    stosw
    
    ; 源IP
    mov esi, my_ip
    mov ecx, IP_ALEN
    rep movsb
    
    ; 目标IP
    mov esi, edx       ; 之前保存的目标IP指针
    mov ecx, IP_ALEN
    rep movsb
    
    ; 计算IP校验和
    push edi
    mov esi, tx_buffer + ETH_HLEN
    mov ecx, IP_HLEN
    call checksum
    mov [esi + ip_header.check], ax
    pop edi
    
    ; 3. ICMP头部
    mov al, ICMP_ECHO_REQUEST ; 类型
    stosb
    xor al, al         ; 代码
    stosb
    xor ax, ax         ; 校验和(先置0)
    stosw
    mov ax, 0x1234     ; 标识符(可以固定)
    stosw
    mov ax, [ping_seq] ; 序列号
    stosw
    inc word [ping_seq] ; 递增序列号
    
    ; ICMP数据 (32字节测试数据)
    mov ecx, 32
    mov al, 'A'
.icmp_data:
    stosb
    inc al
    loop .icmp_data
    
    ; 计算ICMP校验和
    mov esi, tx_buffer + ETH_HLEN + IP_HLEN
    mov ecx, ICMP_HLEN + 32
    call checksum
    mov [esi + icmp_header.checksum], ax
    
    ret

; 计算校验和
checksum:
    xor eax, eax
    xor edx, edx
.loop:
    lodsw
    add eax, edx
    mov edx, eax
    shr edx, 16
    and eax, 0xFFFF
    loop .loop
    add eax, edx
    mov edx, eax
    shr edx, 16
    add eax, edx
    not ax
    ret

; 解析IP地址
parse_ip:
    pushad
    mov edi, .ip_buffer
    mov ecx, 4
.parse_loop:
    call atoi
    stosb
    cmp byte [esi], '.'
    jne .parse_done
    inc esi
    loop .parse_loop
.parse_done:
    popad
    mov eax, .ip_buffer
    ret

.ip_buffer:
    db 0, 0, 0, 0

; 辅助函数
print_ip:
    pushad
    mov ecx, 4
.print_loop:
    lodsb
    call print_dec
    cmp ecx, 1
    je .no_dot
    mov al, '.'
    call put_char
.no_dot:
    loop .print_loop
    popad
    ret

print_dec:
    pushad
    xor ah, ah
    mov bl, 100
    div bl
    test al, al
    jz .no_hundreds
    add al, '0'
    call put_char
.no_hundreds:
    mov al, ah
    xor ah, ah
    mov bl, 10
    div bl
    test al, al
    jnz .has_tens
    test ah, ah
    jz .done
.has_tens:
    add al, '0'
    call put_char
    mov al, ah
    add al, '0'
    call put_char
.done:
    popad
    ret

newline:
    push eax
    mov al, 0x0A
    call put_char
    pop eax
    ret

; 设置中断门
; 输入: AL=中断号, BL=属性, ESI=处理程序地址
set_interrupt_gate:
    pushad
    
    ; 计算IDT中的偏移量 (中断号*8)
    xor ah, ah
    shl eax, 3      ; 每个门描述符8字节
    add eax, idt    ; 加上IDT基地址
    
    ; 设置偏移量低16位
    mov [eax], si
    mov word [eax+2], KERNEL_CS ; 选择子
    
    ; 设置属性
    mov byte [eax+4], 0     ; 保留
    mov byte [eax+5], bl    ; 属性
    
    ; 设置偏移量高16位
    shr esi, 16
    mov [eax+6], si
    
    popad
    ret

; 字符串转整数 (简单实现)
; 输入: ESI=字符串指针
; 输出: EAX=数值
atoi:
    push ebx
    push ecx
    push edx
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    
.convert:
    lodsb
    test al, al
    jz .done
    cmp al, '0'
    jb .invalid
    cmp al, '9'
    ja .invalid
    
    ; 数字字符，转换为数值
    sub al, '0'
    imul ebx, 10
    add ebx, eax
    jmp .convert
    
.invalid:
    xor ebx, ebx
    
.done:
    mov eax, ebx
    pop edx
    pop ecx
    pop ebx
    ret

; 打印十六进制数的函数
print_hex:
    pushad
    mov ecx, 8       ; 处理8个十六进制字符(32位)
.hex_loop:
    rol eax, 4       ; 循环左移4位
    mov ebx, eax
    and ebx, 0x0F    ; 取最低4位
    mov bl, [hex_chars + ebx]  ; 转换为ASCII字符
    mov ah, 0x0F     ; 设置显示属性
    call put_char    ; 确保put_char已定义
    loop .hex_loop
    popad
    ret

hex_chars db '0123456789ABCDEF'
