; linux x86_64 syscalls
%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_IOCTL   16
%define SYS_EXIT    60

; file descriptors
%define STDIN   0
%define STDOUT  1

; termios codes to read and write
%define TCGETS  0x5401
%define TCSETS  0x5402

; termios flags and layout
%define ICANON  0x00000002   
%define ECHO    0x00000008
%define ISIG    0x00000001
%define IXON    0x00000400

%define OFF_IFLAG   0
%define OFF_OFLAG   4
%define OFF_CFLAG   8
%define OFF_LFLAG   12
%define OFF_LINE    16
%define OFF_CC      17

%define TERMIOS_SZ 60

%define VTIME 5
%define VMIN  6

section .data

section .bss
    t_old resb TERMIOS_SZ   ; buffer for old termios settings
    t_new resb TERMIOS_SZ   ; buffer for new termios settings
    key resb 1

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
    ;
    ; copy algorithm:
    ;
    ;   rdi - pointer `to`
    ;   rsi - pointer `from`
    ;
    ;   cld (clear direction flag):
    ;       df (direction flag) in register rflags
    ;           if df = 0 -> rsi and rdi increase
    ;           if df = 1 -> rsi and rdi decrease
    ;
    ;   movsb (move string byte) - copy one byte:
    ;       [rdi] = [rsi]
    ;       rsi += 1 (if df = 0)
    ;       rdi += 1
    ;
    ;   rep - repeat command `rcx` times
    ;       => rcx - size
    lea rsi, [rel t_old]
    lea rdi, [rel t_new]
    mov rcx, TERMIOS_SZ     
    cld
    rep movsb

    ; raw mode
    mov eax, [rel t_new + OFF_LFLAG]    ; c_lflag (local flags)
    and eax, ~ICANON                    ; canonical mode - wait Enter
    and eax, ~ECHO                      ; echo mode - duplicate input
    and eax, ~ISIG                      ; signals - Ctrl+C, Ctrl+Z 
    mov [t_new + OFF_LFLAG], eax
    
    mov eax, [rel t_new + OFF_IFLAG]    ; c_iflag (input flags)
    and eax, ~IXON                      ; software flow control - Ctrl+S, Ctrl+Q
    mov [t_new + OFF_IFLAG], eax

    ; c_cc[] (control chars)
    mov byte [t_new + OFF_CC + VMIN], 0     ; not require bytes for read
    mov byte [t_new + OFF_CC + VTIME], 1    ; wait maximum 0.1 seconds

    ; apply new termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    lea rdx, [rel t_new]
    syscall

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
    jne .no_key

    ; check key
    mov al, [key]

    ; key `Q`
    cmp al, 'q'
    je .exit
    cmp al, 'Q'
    je .exit

    jmp .loop

.no_key:
    jmp .loop

.exit:
    ; restore termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    lea rdx, [rel t_old]
    syscall

    ; exit(status)
    mov rax, SYS_EXIT
    xor rdi, rdi        ; make zero byte
    syscall
