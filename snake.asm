; linux x86_64 syscalls
%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_IOCTL       16
%define SYS_NANOSLEEP   35
%define SYS_EXIT        60
%define SYS_TIME        201

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

%define TERMIOS_SZ  60

%define VTIME 5
%define VMIN  6

; field size
%define W 30
%define H 15

; symbols
%define SLASH_N  10
%define SLASH_0  0

%define CELL_W_BORDER   '-'
%define CELL_H_BORDER   '|'
%define CELL_CORNER     '+'
%define CELL_EMPTY      ' '
%define CELL_SNAKE      'O'
%define CELL_FOOD       '@'

; directions
%define DIR_UP    0
%define DIR_RIGHT 1
%define DIR_DOWN  2
%define DIR_LEFT  3

; winning condition - fill entire field
%define WIN_LENGTH   (W * H)

section .data
    ; esc sequences
    esc_hide  db 0x1B, "[?25l", SLASH_0
    esc_show  db 0x1B, "[?25h", SLASH_0
    esc_clear db 0x1B, "[2J", 0x1B, "[H", SLASH_0
    esc_home  db 0x1B, "[H", SLASH_0

    ; timespec
    tick_ts dq 0        ; tv_sec
        dq 150000000    ; tv_nsec = 150 ms

    ; start screen
    splash_line1  db "                   ____     ", SLASH_N, SLASH_0
    splash_line2  db "                  / . .\    ", SLASH_N, SLASH_0
    splash_line3  db "                  \  ---<   ", SLASH_N, SLASH_0
    splash_line4  db "                   \  /     ", SLASH_N, SLASH_0
    splash_line5  db "         __________/ /      ", SLASH_N, SLASH_0
    splash_line6  db "    __-=:___________/       ", SLASH_N, SLASH_0
    splash_line7  db "   / __/__  ___ _/ /____    ", SLASH_N, SLASH_0
    splash_line8  db "  _\ \/ _ \/ _ `/  '_/ -_)  ", SLASH_N, SLASH_0
    splash_line9  db " /___/_//_/\_,_/_/\_\\__/   ", SLASH_N, SLASH_0
    splash_line10 db "                            ", SLASH_N, SLASH_0
    splash_prompt db "Press Any Key to Continue...", SLASH_N, SLASH_0

    ; strings
    msg_keys  db "Move: wasd, Quit: q", SLASH_N, SLASH_0
    msg_score db "Score: ", SLASH_0
    msg_win   db "You win! Score: ", SLASH_0
    msg_lose  db "You lose! Score: ", SLASH_0

section .bss
    ; buffer for termios settings
    t_old resb TERMIOS_SZ   ; old
    t_new resb TERMIOS_SZ   ; new

    ; entered key
    key resb 1

    ; line buffer
    buf resb W + 4
    
    ; number buffer for score
    num_buf resb 12

    ; game state
    snake_x  resw W * H
    snake_y  resw W * H
    len      resd 1
    dir      resb 1     ; 0 - up, 1 - right, 2 - down, 3 - left
    food_x   resw 1
    food_y   resw 1
    score    resd 1
    
    ; random seed
    rand_seed resd 1

section .text
    global _start

_start:
    ; init random seed with time
    mov rax, SYS_TIME
    xor rdi, rdi
    syscall
    mov [rand_seed], eax

    ; save termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCGETS
    lea rdx, [t_old]
    syscall

    ; copy t_old -> t_new
    lea rsi, [t_old]
    lea rdi, [t_new]
    mov rcx, TERMIOS_SZ     
    cld
    rep movsb

    ; raw mode
    mov eax, [t_new + OFF_LFLAG]
    and eax, ~(ICANON | ECHO | ISIG)
    mov [t_new + OFF_LFLAG], eax
    
    mov eax, [t_new + OFF_IFLAG]
    and eax, ~IXON
    mov [t_new + OFF_IFLAG], eax

    mov byte [t_new + OFF_CC + VMIN], 1  ; wait for 1 character
    mov byte [t_new + OFF_CC + VTIME], 0

    ; apply new termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    lea rdx, [t_new]
    syscall

    ; hide cursor
    lea rsi,[esc_hide]
    call write_line

    ; clear terminal
    lea rsi,[esc_clear]
    call write_line

    ; show splash screen
    call show_splash

    ; wait for any key press
    call wait_key_press

    ; set non-blocking mode for game
    mov byte [t_new + OFF_CC + VMIN], 0  ; non-blocking
    mov byte [t_new + OFF_CC + VTIME], 0

    ; apply non-blocking termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    lea rdx, [t_new]
    syscall

    ; init game
    call init_game

    ; start game loop
    jmp .loop

.loop:
    ; read one byte
    mov rax, SYS_READ
    mov rdi, STDIN
    lea rsi, [key]
    mov rdx, 1
    syscall

    ; check if we got input
    cmp rax, 1
    jne .no_input

    ; check key
    mov al, [key]

    ; key 'Q'
    cmp al, 'q'
    je .exit
    cmp al, 'Q'
    je .exit

    ; process movement keys
    cmp al, 'w'
    je .up
    cmp al, 'W'
    je .up
    
    cmp al, 's'
    je .down
    cmp al, 'S'
    je .down
    
    cmp al, 'a'
    je .left
    cmp al, 'A'
    je .left
    
    cmp al, 'd'
    je .right
    cmp al, 'D'
    je .right
    
    jmp .no_input

.up:
    cmp byte [dir], DIR_DOWN
    je .no_input
    mov byte [dir], DIR_UP
    jmp .no_input

.down:
    cmp byte [dir], DIR_UP
    je .no_input
    mov byte [dir], DIR_DOWN
    jmp .no_input

.left:
    cmp byte [dir], DIR_RIGHT
    je .no_input
    mov byte [dir], DIR_LEFT
    jmp .no_input

.right:
    cmp byte [dir], DIR_LEFT
    je .no_input
    mov byte [dir], DIR_RIGHT

.no_input:
    ; move snake
    call move_snake

    ; cursor go home
    lea rsi, [esc_home]
    call write_line

    ; show control
    call print_keys

    ; redraw field
    call draw_field

    ; show score
    call print_score

    ; one frame sleep
    call sleep_tick

    jmp .loop

.exit:
    ; show cursor
    lea rsi,[esc_show]
    call write_line

    ; restore termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    lea rdx, [t_old]
    syscall

    ; exit
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

; show splash screen
show_splash:
    lea rsi, [splash_line1]
    call write_line
    lea rsi, [splash_line2]
    call write_line
    lea rsi, [splash_line3]
    call write_line
    lea rsi, [splash_line4]
    call write_line
    lea rsi, [splash_line5]
    call write_line
    lea rsi, [splash_line6]
    call write_line
    lea rsi, [splash_line7]
    call write_line
    lea rsi, [splash_line8]
    call write_line
    lea rsi, [splash_line9]
    call write_line
    lea rsi, [splash_line10]
    call write_line
    lea rsi, [splash_prompt]
    call write_line
    ret

; wait for any key press (blocking)
wait_key_press:
    mov rax, SYS_READ
    mov rdi, STDIN
    lea rsi, [key]
    mov rdx, 1
    syscall
    ret

; initialize game state
init_game:
    ; clear screen again before starting game
    lea rsi,[esc_clear]
    call write_line

    ; reset score
    mov dword [score], 0

    ; init snake in the middle
    mov dword [len], 3
    
    ; head at center
    mov ax, W / 2
    mov [snake_x], ax
    mov ax, H / 2
    mov [snake_y], ax
    
    ; body segments
    mov ax, W / 2 - 1
    mov [snake_x + 2], ax
    mov ax, H / 2
    mov [snake_y + 2], ax
    
    mov ax, W / 2 - 2
    mov [snake_x + 4], ax
    mov ax, H / 2
    mov [snake_y + 4], ax
    
    ; initial direction
    mov byte [dir], DIR_RIGHT
    
    ; generate first food
    call generate_food
    
    ret

; move snake
move_snake:
    ; save tail position before moving
    mov ecx, [len]
    dec ecx
    movzx r8d, word [snake_x + ecx*2]  ; save tail x
    movzx r9d, word [snake_y + ecx*2]  ; save tail y
    
    ; shift all segments (from tail to head)
    mov ecx, [len]
    dec ecx
    
.shift_loop:
    cmp ecx, 0
    je .move_head
    
    ; copy position from previous segment
    lea rsi, [snake_x + (rcx-1)*2]
    lea rdi, [snake_x + ecx*2]
    mov dx, [rsi]
    mov [rdi], dx
    
    lea rsi, [snake_y + (rcx-1)*2]
    lea rdi, [snake_y + ecx*2]
    mov dx, [rsi]
    mov [rdi], dx
    
    dec ecx
    jmp .shift_loop

.move_head:
    ; get current head position
    movzx eax, word [snake_x]
    movzx ebx, word [snake_y]
    
    ; move based on direction
    movzx ecx, byte [dir]
    
    cmp ecx, DIR_UP
    je .move_up
    cmp ecx, DIR_DOWN
    je .move_down
    cmp ecx, DIR_LEFT
    je .move_left
    ; else move right
    
.move_right:
    inc eax
    cmp eax, W
    jl .check_collision
    xor eax, eax  ; wrap to left side
    jmp .check_collision
    
.move_left:
    dec eax
    cmp eax, 0
    jge .check_collision
    mov eax, W - 1  ; wrap to right side
    jmp .check_collision
    
.move_up:
    dec ebx
    cmp ebx, 0
    jge .check_collision
    mov ebx, H - 1  ; wrap to bottom
    jmp .check_collision
    
.move_down:
    inc ebx
    cmp ebx, H
    jl .check_collision
    xor ebx, ebx  ; wrap to top
    
.check_collision:
    ; update head position
    mov [snake_x], ax
    mov [snake_y], bx
    
    ; check self collision
    push rax
    push rbx
    call check_self_collision
    pop rbx
    pop rax
    cmp edx, 1
    je .lose_game
    
    ; check food
    cmp ax, [food_x]
    jne .done
    cmp bx, [food_y]
    jne .done
    
    ; eat food - grow snake by adding segment at old tail position
    mov ecx, [len]
    mov [snake_x + ecx*2], r8w  ; restore old tail x
    mov [snake_y + ecx*2], r9w  ; restore old tail y
    inc dword [len]
    inc dword [score]
    
    ; check win condition
    mov eax, [len]
    cmp eax, WIN_LENGTH
    jge .win_game
    
    call generate_food
    
.done:
    ret

.lose_game:
    ; show final field one more time
    lea rsi, [esc_home]
    call write_line
    call print_keys
    call draw_field
    
    ; show lose message
    lea rsi, [msg_lose]
    call write_line
    mov eax, [score]
    call print_number
    
    ; print newline
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [buf]
    mov byte [rsi], SLASH_N
    mov byte [rsi+1], SLASH_0
    mov rdx, 1
    syscall
    
    jmp .exit_program

.win_game:
    ; show final field one more time
    lea rsi, [esc_home]
    call write_line
    call print_keys
    call draw_field
    
    ; show win message
    lea rsi, [msg_win]
    call write_line
    mov eax, [score]
    call print_number
    
    ; print newline
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [buf]
    mov byte [rsi], SLASH_N
    mov byte [rsi+1], SLASH_0
    mov rdx, 1
    syscall

.exit_program:
    ; show cursor
    lea rsi,[esc_show]
    call write_line

    ; restore termios
    mov rax, SYS_IOCTL
    mov rdi, STDIN
    mov rsi, TCSETS
    lea rdx, [t_old]
    syscall

    ; exit
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

; check if head collides with snake body
; returns edx = 1 if collision, 0 otherwise
check_self_collision:
    movzx eax, word [snake_x]
    movzx ebx, word [snake_y]
    
    mov ecx, [len]
    dec ecx  ; skip head
    xor edx, edx
    
.check_loop:
    cmp ecx, 1  ; check from segment 1 to end
    jl .done
    
    cmp ax, [snake_x + ecx*2]
    jne .next
    cmp bx, [snake_y + ecx*2]
    jne .next
    
    mov edx, 1
    ret
    
.next:
    dec ecx
    jmp .check_loop
    
.done:
    ret

; generate random food position
generate_food:
.retry:
    ; random x (0 to W-1)
    call random
    xor edx, edx
    mov ecx, W
    div ecx
    mov [food_x], dx
    
    ; random y (0 to H-1)
    call random
    xor edx, edx
    mov ecx, H
    div ecx
    mov [food_y], dx
    
    ; check if food is on snake
    movzx eax, word [food_x]
    movzx ebx, word [food_y]
    
    mov ecx, [len]
.check_loop:
    cmp ecx, 0
    je .done
    
    dec ecx
    cmp ax, [snake_x + ecx*2]
    jne .check_loop
    cmp bx, [snake_y + ecx*2]
    jne .check_loop
    
    ; food on snake, retry
    jmp .retry
    
.done:
    ret

; simple linear congruential generator
random:
    mov eax, [rand_seed]
    imul eax, eax, 1103515245
    add eax, 12345
    mov [rand_seed], eax
    ret

; 150 ms sleep interval
sleep_tick:
    mov rax, SYS_NANOSLEEP
    lea rdi, [tick_ts]
    xor rsi, rsi
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

    ; top border
    lea rdi, [buf]
    mov byte [rdi], CELL_CORNER

    lea rdi, [buf + 1]
    mov al, CELL_W_BORDER
    mov rcx, W
    rep stosb

    lea rdi, [buf]
    mov byte [rdi + W + 1], CELL_CORNER
    mov byte [rdi + W + 2], SLASH_N
    mov byte [rdi + W + 3], SLASH_0
    lea rsi, [buf]
    call write_line

    ; loop by height
    xor r8d, r8d  ; row counter
.row_loop:
    ; start row
    lea rdi, [buf]
    mov byte [rdi], CELL_H_BORDER

    ; fill row with empty cells
    lea rdi, [buf + 1]
    mov al, CELL_EMPTY
    mov rcx, W
    rep stosb

    ; place snake segments
    mov ecx, [len]
.snake_loop:
    cmp ecx, 0
    je .check_food
    
    dec ecx
    movzx eax, word [snake_y + ecx*2]
    cmp eax, r8d
    jne .snake_loop
    
    movzx eax, word [snake_x + ecx*2]
    lea rdi, [buf + 1 + eax]
    mov byte [rdi], CELL_SNAKE
    jmp .snake_loop

.check_food:
    ; place food if on this row
    movzx eax, word [food_y]
    cmp eax, r8d
    jne .end_row
    
    movzx eax, word [food_x]
    lea rdi, [buf + 1 + eax]
    mov byte [rdi], CELL_FOOD

.end_row:
    ; end border
    lea rdi, [buf]
    mov byte [rdi + W + 1], CELL_H_BORDER
    mov byte [rdi + W + 2], SLASH_N
    mov byte [rdi + W + 3], SLASH_0
    lea rsi, [buf]
    call write_line

    inc r8d
    cmp r8d, H
    jl .row_loop

    ; bottom border
    lea rdi, [buf]
    mov byte [rdi], CELL_CORNER

    lea rdi, [buf + 1]
    mov al, CELL_W_BORDER
    mov rcx, W
    rep stosb

    lea rdi, [buf]
    mov byte [rdi + W + 1], CELL_CORNER
    mov byte [rdi + W + 2], SLASH_N
    mov byte [rdi + W + 3], SLASH_0
    lea rsi, [buf]
    call write_line

    ret

; print use keys
print_keys:
    lea rsi, [msg_keys]
    call write_line
    
    ret

; print score
print_score:
    lea rsi, [msg_score]
    call write_line
    
    mov eax, [score]
    call print_number
    
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [buf]
    mov byte [rsi], SLASH_N
    mov byte [rsi+1], SLASH_0
    mov rdx, 1
    syscall
    
    ret

; print number in eax
print_number:
    lea rdi, [num_buf + 11]
    mov byte [rdi], SLASH_0
    dec rdi
    
    test eax, eax
    jnz .convert
    
    ; special case for 0
    mov byte [rdi], '0'
    jmp .print
    
.convert:
    xor edx, edx
    mov ecx, 10
    div ecx
    
    add dl, '0'
    mov [rdi], dl
    dec rdi
    
    test eax, eax
    jnz .convert
    
    inc rdi
    
.print:
    mov rsi, rdi
    call write_line
    ret