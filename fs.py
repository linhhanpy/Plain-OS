import os
import sys

def create_fs_asm():
    """从root目录构建文件系统"""
    root_dir = os.path.join(os.getcwd(), 'root')
    
    # 获取root目录下所有文件
    files = []
    for entry in os.listdir(root_dir):
        full_path = os.path.join(root_dir, entry)
        if os.path.isfile(full_path):
            files.append(full_path)
    
    asm_content = f"""; 文件系统实现 - 从root目录构建
section .data
global fs_files_count
fs_files_count dd {len(files)}

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
"""

    # 文件查找逻辑
    for i, filename in enumerate(files):
        base = os.path.splitext(os.path.basename(filename))[0].replace('.', '_').replace(' ', '_')
        asm_content += f"""
    mov esi, file_{base}_name
    call str_compare
    je .found_{i+1}
"""

    asm_content += """
    stc
    ret
"""

    # 文件找到处理
    for i, filename in enumerate(files):
        base = os.path.splitext(os.path.basename(filename))[0].replace('.', '_').replace(' ', '_')
        asm_content += f"""
.found_{i+1}:
    mov esi, file_{base}_content_str
    clc
    ret
"""

    # 获取文件大小函数
    asm_content += """
fs_get_file_size:
    ; EDI = 文件名
    ; 返回: ECX = 文件大小
    mov edi, esi
"""
    for i, filename in enumerate(files):
        size = os.path.getsize(filename)
        base = os.path.splitext(os.path.basename(filename))[0].replace('.', '_').replace(' ', '_')
        asm_content += f"""
    mov esi, file_{base}_name
    call str_compare
    jne .next_{i}
    mov ecx, {size}
    ret
.next_{i}:
"""

    asm_content += """
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
file_names db """

    # 文件名列表(只存储文件名，不含路径)
    name_list = [f"'{os.path.basename(f)} '" for f in files]
    asm_content += ', '.join(name_list) + ',0\n\n'

    # 文件内容
    for filename in files:
        base = os.path.splitext(os.path.basename(filename))[0].replace('.', '_').replace(' ', '_')
        with open(filename, 'rb') as f:
            content = f.read()
        hex_bytes = ','.join([f"0x{b:02x}" for b in content])
        asm_content += f"""
; 文件: {os.path.basename(filename)}
file_{base}_name db '{os.path.basename(filename)}',0
file_{base}_content_str db {hex_bytes},0
"""

    # 确保bin目录存在
    os.makedirs("bin", exist_ok=True)
    
    with open("bin/fs.asm", "w") as f:
        f.write(asm_content)
    print(f"Created filesystem with {len(files)} files from root directory")

if __name__ == "__main__":
    # 检查root目录是否存在
    if not os.path.exists(os.path.join(os.getcwd(), 'root')):
        print("Error: 'root' directory not found in current path")
        sys.exit(1)
    
    create_fs_asm()
    
    