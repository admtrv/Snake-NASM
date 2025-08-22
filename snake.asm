; linux x86_64 syscalls
%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_IOCTL   16
%define SYS_EXIT    60

; file descriptors
%define STDIN   0
%define STDOUT  1

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

%define TERMIOS_SZ 60

%define VTIME 5
%define VMIN  6

section .data

section .bss
    ; buffer for termios settings
    t_old resb TERMIOS_SZ   ; old
    t_new resb TERMIOS_SZ   ; new

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
    lea rsi, [rel t_old]
    lea rdi, [rel t_new]
    mov rcx, TERMIOS_SZ     
    cld
    rep movsb

    ; raw mode
    mov eax, [rel t_new + OFF_LFLAG]
    and eax, ~(ICANON | ECHO | ISIG)
    and eax, ~ECHO
    and eax, ~ISIG
    mov [t_new + OFF_LFLAG], eax
    
    mov eax, [rel t_new + OFF_IFLAG]
    and eax, ~IXON
    mov [t_new + OFF_IFLAG], eax

    mov byte [t_new + OFF_CC + VMIN], 0
    mov byte [t_new + OFF_CC + VTIME], 1

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

    ; exit
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall
