; linux x86_64 syscalls
%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_IOCTL       16
%define SYS_NANOSLEEP   35
%define SYS_EXIT        60

; file descriptors
%define STDIN   0
%define STDOUT  1

; symbols
%define SLASH_N  10
%define SLASH_0  0

; termios codes
%define TCGETS  0x5401  ; read
%define TCSETS  0x5402  ; write

; termios flags and layout
%define ICANON  0x00000002  ; canonical mode - wait Enter
%define ECHO    0x00000008  ; echo mode - duplicate input
%define ISIG    0x00000001  ; signals - Ctrl+C, Ctrl+Z 
%define IXON    0x00000400  ; software flow control - Ctrl+S, Ctrl+Q

%define OFF_IFLAG   0   ; c_iflag (input flags)
%define OFF_LFLAG   12  ; c_lflag (local flags)
%define OFF_CC      17  ; c_cc[] (control chars)

%define TERMIOS_SZ  60

%define VTIME 5
%define VMIN  6

; field size
%define W 30
%define H 15

; symbols
%define CELL_W_BORDER   '-'
%define CELL_H_BORDER   '|'
%define CELL_CORNER     '+'
%define CELL_EMPTY      '.'
%define CELL_SNAKE      'O'
%define CELL_FOOD       '@'

section .data
    ; esc sequences
    esc_hide  db 0x1B, "[?25l", SLASH_0
    esc_show  db 0x1B, "[?25h", SLASH_0
    esc_clear db 0x1B, "[2J", 0x1B, "[H", SLASH_0
    esc_home  db 0x1B, "[H", SLASH_0

    ; timespec
    tick_ts dq 0        ; tv_sec
        dq 100000000    ; tv_nsec = 100 ms

section .bss
    ; buffer for termios settings
    t_old resb TERMIOS_SZ   ; old
    t_new resb TERMIOS_SZ   ; new

    ; entered key
    key resb 1

    ; line buffer
    buf resb W + 4

    ; game state
    snake_x  resw W * H
    snake_y  resw W * H
    len      resd 1
    dir      resb 1     ; 0 - up, 1 - right, 2 - down, 3 - left
    food_x   resw 1
    food_y   resw 1

section .text
    global _start

_start:
    ; save termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCGETS
    lea rdx, [rel t_old]
    syscall

    ; copy t_old -> t_new
    lea rsi, [rel t_old]
    lea rdi, [rel t_new]
    mov rcx, TERMIOS_SZ     
    cld
    rep movsb

    ; raw mode
    mov eax, [rel t_new + OFF_LFLAG]
    and eax, ~(ICANON | ECHO | ISIG)
    mov [rel t_new + OFF_LFLAG], eax
    
    mov eax, [rel t_new + OFF_IFLAG]
    and eax, ~IXON
    mov [rel t_new + OFF_IFLAG], eax

    mov byte [rel t_new + OFF_CC + VMIN], 0
    mov byte [rel t_new + OFF_CC + VTIME], 0

    ; apply new termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    lea rdx, [rel t_new]
    syscall

    ; hide cursor
    lea rsi,[rel esc_hide]
    call write_line

    ; clear terminal
    lea rsi,[rel esc_clear]
    call write_line

    ; start game loop
    jmp .loop

.loop:
    ; read one byte
    mov rax, SYS_READ
    mov rdi, STDIN
    lea rsi, [rel key]
    mov rdx, 1
    syscall

    ; nothing
    cmp rax, 1
    jne .frame

    ; check key
    mov al, [rel key]

    ; key 'Q'
    cmp al, 'q'
    je .exit
    cmp al, 'Q'
    je .exit

.frame:
    ; cursor go home
    lea rsi, [rel esc_home]
    call write_line

    ; redraw field
    call draw_field

    ; one frame sleep
    call sleep_tick

    jmp .loop

.exit:
    ; show cursor
    lea rsi,[rel esc_show]
    call write_line

    ; restore termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    lea rdx, [rel t_old]
    syscall

    ; exit
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

sleep_tick:
    mov rax, SYS_NANOSLEEP
    lea rdi, [rel tick_ts]
    xor rsi, rsi            ; NULL
    syscall
    ret

; write line from address rsi to '\0'
write_line:
    push rsi
    mov rax, rsi
    xor rcx, rcx
.count:
    cmp byte [rax+rcx], SLASH_0
    je .got_len
    inc rcx
    jmp .count
.got_len:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rdx, rcx
    syscall
    pop rsi
    ret

draw_field:
    cld

    ; top border: '+' + W * '-' + '+' + '\n' + '\0'
    lea rdi, [rel buf]                  ; corner '+'
    mov byte [rdi], CELL_CORNER

    lea rdi, [rel buf + 1]              ; W times '-'
    mov al, CELL_W_BORDER
    mov rcx, W
    rep stosb

    lea rdi, [rel buf]          
    mov byte [rdi + W + 1], CELL_CORNER ; corner '+'

    mov byte [rdi + W + 2], SLASH_N     ; next line
    mov byte [rdi + W + 3], SLASH_0     ; end of line
    lea rsi, [rel buf]
    call write_line

    ; loop by height
    mov r8d, H
.row_loop:
    ; middle row: '|' + W * CELL_EMPTY + '|' + '\n' + '\0'
    lea rdi, [rel buf]                      ; border '|'
    mov byte [rdi], CELL_H_BORDER

    lea rdi, [rel buf + 1]                  ; W times '.'
    mov al, CELL_EMPTY
    mov rcx, W
    rep stosb

    lea rdi, [rel buf]                      ; border '|'
    mov byte [rdi + W + 1], CELL_H_BORDER
    mov byte [rdi + W + 2], SLASH_N         ; next line
    mov byte [rdi + W + 3], SLASH_0         ; end of line
    lea rsi, [rel buf]
    call write_line

    dec r8d
    jnz .row_loop

    ; bottom border: '+' + W * '-' + '+' + '\n' + '\0'
    lea rdi, [rel buf]                  ; corner '+'
    mov byte [rdi], CELL_CORNER

    lea rdi, [rel buf + 1]              ; W times '-'
    mov al, CELL_W_BORDER
    mov rcx, W
    rep stosb

    lea rdi, [rel buf]          
    mov byte [rdi + W + 1], CELL_CORNER ; corner '+'

    mov byte [rdi + W + 2], SLASH_N     ; next line
    mov byte [rdi + W + 3], SLASH_0     ; end of line
    lea rsi, [rel buf]
    call write_line

    ret
