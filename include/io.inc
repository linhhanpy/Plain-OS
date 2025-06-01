
; 常量定义
ATA_BASE         equ 0x1F0
ATA_DRIVE_SELECT equ 0x1F6
ATA_STATUS       equ 0x1F7
ATA_CMD          equ 0x1F7
ATA_DATA         equ 0x1F0

; 全局变量

VIDEO_MEMORY equ 0xB8000
LINE_WIDTH   equ 80
WHITE_ON_BLACK equ 0x0F

KEYBOARD_PORT equ 0x60
KEYBOARD_STATUS_PORT equ 0x64
KEYBOARD_BUFFER_SIZE equ 32

extern put_char
extern print_str
;extern clear_screen
extern get_char
extern get_key
extern read_line
extern scroll_screen
extern init_fs
;extern write_file
extern ata_read
extern ata_wait
extern hide_cursor
extern clear_screen

