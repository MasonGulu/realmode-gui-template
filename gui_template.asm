use16
org 0
cpu 8086
;;;;;;;;;; About this file. ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; I'm going to attempt to stick to a little bit of a convention
; STRING_ will prefix string constants
; SUB_ will prefix subroutine entry points
; _[SUBNAME]_ will prefix subroutine internal labels
; CONST_ will prefix constant values
; DATA_ will prefix data structures
;;;;;;;;;; Boot sector ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    mov ax, cs 
    cmp ax, 0x0000      ; Is this zero?
    je _booting 
    _compaq_check:
    cmp ax, 0x07C0      ; The compaq for some reason boots at 07C0:0000 instead of 0000:7C00
    jne _not_booting    ; We are definitely not booting
    _booting:
    cli
    mov ax, 0x07C0
    mov ds, ax
    push ax             ; Code segment
    mov ax, _resume_booting 
    push ax 
    retf                ; Move execution to 07C0:xxxx instead of 0000:07C0+xxxx
    _resume_booting:
    lea si, [STRING_booting]
    call SUB_print
    mov ax, 0x0208      ; Read 8 sectors from the disk (4096 bytes)
    mov cx, 0x0001      ; Track 0, sector 1
    mov dx, 0x0000      ; Head 0, drive 0
    mov bx, 0x0500
    mov es, bx
    mov bx, 0x0000      ; 0500:0000
    int 0x13            ; Okay read done.
    mov ax, 0x0208      ; Read 8 sectors from the disk (4096 bytes)
    mov cx, 0x0101      ; Track 1, sector 1
    mov bx, 0x1000      ; 0500:1000
    int 0x13            ; Read next track, total of 8kb
    _booting_call:
    mov ax, 0x0500
    push ax 
    mov ax, _booting_call
    push ax             ; Get this on the stack, so when it returns instead of crashing it gets into a loop
    mov ax, 0x0500
    push ax             ; Code segment
    mov ax, 0x0000
    push ax             ; Instruction pointer
    sti
    retf                ; Hand off execution
    _not_booting:
    jmp word SUB_entry
    ;;;;;;;;;; Credit for this code goes to J. Bogin ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    SUB_print:			; Print a 0-terminated ASCII string in DS:SI
        push ax 
        push bx 
        _print_loop:
        mov ax,0E00h
        lodsb		    ; byte[DS:SI] => AL
        cmp al,00	    ; Terminating character
        je _print_finished
        push bp			; I had an ancient machine that destroyed these two!!!
        push si
        int 10h			; Blurp it out
        pop si
        pop bp
        jmp _print_loop
        _print_finished:
            pop bx 
            pop ax 
            ret
    ;;;;;;;;;; End of code "borrowed" from J. Bogin ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    STRING_booting:
        db 'Booting from disk!',0
    times (510 - ($-$$)) nop 
                    ; Pad the boot sector with nop bytes
    db 0x55, 0xAA   ; Boot sector signiture
;;;;;;;;;; Begin Menu Related code ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SUB_entry:
    push ds 
    push es
    mov ax, cs
    mov ds, ax 
    mov es, ax      ; ensure all segments are the same

    mov ax, 0x0003
    int 0x10        ; Set video mode to 80x25 text, clearing the screen

    mov ah, 0x02
    mov bh, 0
    mov dh, 22
    mov dl, 0
    int 0x10        ; Set cursor position to bottom left, 3 rows from the bottom

    lea si, [STRING_copyright]
    call SUB_print  ; print out copyright information at the bottom of the screen

    mov dl, 0       ; Set up x cordinate
    mov bx, DATA_main 
                    ; Set up pointer to the main menu
    call SUB_menu   ; Call the menu display and handler
    ; We have returned from it, return to cassette basic
    pop es 
    pop ds
    retf

SUB_menu:
    ; This takes an x cordinate in dl
    ; and pointer to menu data structure in bx
    call SUB_drawbox
                    ; Draw the base box
    call SUB_drawlabels
                    ; Draw the labels
    mov cl, 0       ; Current selection is 0
    mov dh, [bx]    ; Load the maximum valid selection
    _menu_inputloop:
        ; Register Usage:
        ;   dl: x cordinate
        ;   bx: pointer to data
        ;   dh: maximum selection
        ;   cl: current selection
        ; Here we actually handle drawing
        ; the selected option
        ; and keyboard input, selection
        ; and code jumping/calling subroutines
        ; based off selection
        push dx
        call SUB_clearselection
                    ; We have moved the selection indicator to match our current selection
        pop dx 
        mov ax, 0
        int 0x16    ; Get keyboard input

        ; Up
        cmp ah, 72  ; Up arrow
        je _menu_handle_up 
        ; Down
        cmp ah, 80  ; Down arrow
        je _menu_handle_down 
        ; Continue
        cmp ah, 28  ; Enter
        je _menu_handle_continue 
        cmp ah, 77  ; Numpad 6
        je _menu_handle_continue 
        ; Back
        cmp ah, 1   ; Escape
        je _menu_handle_back 
        cmp ah, 14  ; Backspace
        je _menu_handle_back 
        cmp ah, 75  ; Numpad left
        je _menu_handle_back 

        jmp _menu_inputloop
        ; Register Usage:
        ;   dl: x cordinate
        ;   bx: pointer to data
        ;   dh: maximum selection
        ;   cl: current selection
    _menu_handle_up:
        cmp cl, 0
        je _menu_up_zero
        sub cl, 1
        _menu_up_zero:
        jmp _menu_inputloop
    _menu_handle_down:
        add cl, 1
        cmp cl, dh
        jg _menu_down_notwithinrange
        jmp _menu_down_inputwithinrange
        _menu_down_notwithinrange:
        mov cl, dh 
        _menu_down_inputwithinrange:
        jmp _menu_inputloop
    _menu_handle_back:
        ; Nothing is on the stack
        ; nor do we really care about any values
        ; we currently have, as we're going up a menu
        call SUB_clearbox 
        ret 
    _menu_handle_continue:
        ; First we check what mode it is operating in
        push ax 
        push bx 
        push cx 
        push dx 
        add bx, CONST_modeoffset
        mov ch, 0
        add bx, cx  ; Now bx is the address of the mode of the selected item
        cmp byte [bx], 0
        je _menu_continue_submenu
        cmp byte [bx], 1
        je _menu_continue_subroutine
        pop dx 
        pop cx 
        pop bx 
        pop ax 
        call SUB_errloop
        jmp _menu_inputloop
                    ; Something has gone wrong, invalid mode
        _menu_continue_submenu:
        add bx, CONST_mode_to_address
        add bx, cx  ; Multiply this by two to compensate for words instead of bytes
        mov bx, word [bx]
        add dl, 11
        call SUB_menu

        pop dx 
        pop cx 
        pop bx 
        pop ax 
        jmp _menu_inputloop
        _menu_continue_subroutine:
        add bx, CONST_mode_to_address
        add bx, cx  ; Multiply this by two to compensate for words instead of bytes
        call word [bx]
        call SUB_cleararea
        pop dx 
        pop cx 
        pop bx 
        pop ax 
        jmp _menu_inputloop
    

SUB_clearselection:
    ; This takes an x cordinate in dl
    ; and selection number in cl, 0 indexed
    push cx 
    push dx 
    add cl, 1
    mov dh, 1
    _clearselection_loop:
    call _clearselection_resetposition
    mov al, ' '
    cmp dh, cl 
    je _clearselection_selected
    _clearselection_continue:
    call _clearselection_printspace
    add dh, 1
    cmp dh, 9
    je _clearselection_loopfinished
    jmp _clearselection_loop
    _clearselection_loopfinished:
    pop dx 
    pop cx 
    ret

    _clearselection_selected:
        mov al, [STRING_selectchar]
        jmp _clearselection_continue

    _clearselection_resetposition:
        ; This expects an x cordinate in dl
        ; and selection number in dh, absolute
        push ax 
        push dx 
        push bx 
        mov bh, 0
        add dl, 1
        mov ah, 0x02
        int 0x10
        pop bx 
        pop dx 
        pop ax
        ret

    _clearselection_printspace:
        ; This just prints whatever is in al
        push ax 
        push bx 
        push cx 
        mov bx, 0
        mov ah, 0x0E
        mov cx, 1
        int 0x10
        pop cx 
        pop bx 
        pop ax 
        ret 

SUB_drawlabels:
    ; This takes an x cordinate in dl
    ; and pointer to menu data structure in bx
    push bx 
    push cx 
    add bx, CONST_labeloffset
    mov si, bx
    mov dh, 1
    _drawlabels_loop:
    call _drawlabels_resetposition
    mov si, bx 
    call SUB_print 
    add bx, 9
    add dh, 1
    cmp dh, 9
    je _drawlabels_loopfinished
    jmp _drawlabels_loop
    _drawlabels_loopfinished:
    pop cx 
    pop bx
    ret
    _drawlabels_resetposition:
        ; expects y cordinate in dh
        ; x cordinate in dl
        push dx 
        push bx 
        push ax 
        mov bh, 0
        mov ah, 2
        add dl, 2
        int 0x10
        pop ax 
        pop bx 
        pop dx 
        ret 

SUB_clearbox:
    ; This takes an x cordinate in dl
    push ax
    push bx
    push cx 
    mov dh, 0
    _clearbox_loop:
    call _clearbox_resetposition
    lea si, [STRING_clearspace]
    call SUB_print
    add dh, 1
    cmp dh, 10
    je _clearbox_loopfinished
    jmp _clearbox_loop
    _clearbox_loopfinished:

    pop cx 
    pop bx 
    pop ax 
    ret 
    _clearbox_resetposition:
        ; this takes the y cordinate in dh, x in dl
        push ax
        push bx 
        mov bh, 0
        mov ah, 2
        int 0x10    ; set position to dl, dh
        pop bx
        pop ax 
        ret

SUB_drawbox:
    ; This takes an x cordinate in dl
    push ax
    push bx
    push cx 
    mov dh, 0
    call _drawbox_resetposition
    lea si, [STRING_boxtop]
    call SUB_print 
    
    mov dh, 1
    _drawbox_loop:
    call _drawbox_resetposition
    lea si, [STRING_boxmid]
    call SUB_print
    add dh, 1
    cmp dh, 9
    je _drawbox_loopfinished
    jmp _drawbox_loop
    _drawbox_loopfinished:
    call _drawbox_resetposition
    lea si, [STRING_boxbottom]
    call SUB_print

    pop cx 
    pop bx 
    pop ax 
    ret 
    _drawbox_resetposition:
        ; this takes the y cordinate in dh, x in dl
        push ax
        push bx 
        mov bh, 0
        mov ah, 2
        int 0x10    ; set position to dl, dh
        pop bx
        pop ax 
        ret

SUB_cleararea:
    ;(80*11)/12 = 73.3, round down to 73 times
    push ax 
    push bx 
    push dx 
    ; First set cursor position to 0, 10
    mov ax, 0x0200
    mov bx, 0x0000
    mov dx, 0x0A00  ; Row 10, column 0
    int 0x10        ; Cursor position is now where we want
    mov ax, 0
    _cleararea_loop:
    lea si, [STRING_clearspace]
    call SUB_print 
    add ax, 1
    cmp ax, 74
    je _cleararea_finish
    jmp _cleararea_loop 
    _cleararea_finish:
        pop dx 
        pop bx 
        pop ax 
        ret 
;;;;;;;;;; End Menu Related code ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;; Get a 16 bit number ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; This will prompt the user for a 16 bit number, then using q w e r, a s d f, will get the number
; expects the starting digit in AX, returns the final digit in AX
; expects a pointer to string in BX
SUB_get16bit:
	push cx
    push dx 
    push ax
    _get16bit_loop:
        mov si, bx
        call SUB_print  ; Print out the string
        call SUB_print16bithex
        push ax
        
        mov ax, 0
        int 16h		    ; get keyboard input, al will contain the key
        
        cmp al, 'q'
        je _get16bit_q
        cmp al, 'w'
        je _get16bit_w
        cmp al, 'e'
        je _get16bit_e
        cmp al, 'r'
        je _get16bit_r
        
        cmp al, 'a'
        je _get16bit_a
        cmp al, 's'
        je _get16bit_s
        cmp al, 'd'
        je _get16bit_d
        cmp al, 'f'
        je _get16bit_f
        
        cmp ah, 28	    ; check if enter pressed
        je _get16bit_end
        
        cmp ah, 1       ; check if esc pressed
        je _get16bit_esc

        pop ax
        jmp _get16bit_loop
        
            _get16bit_q:
                pop ax
                add ax, 0x1000
                jmp _get16bit_loop
            _get16bit_w:
                pop ax
                add ax, 0x0100
                jmp _get16bit_loop
            _get16bit_e:
                pop ax
                add ax, 0x0010
                jmp _get16bit_loop
            _get16bit_r:
                pop ax
                add ax, 0x0001
                jmp _get16bit_loop

            _get16bit_a:
                pop ax
                sub ax, 0x1000
                jmp _get16bit_loop
            _get16bit_s:
                pop ax
                sub ax, 0x0100
                jmp _get16bit_loop
            _get16bit_d:
                pop ax
                sub ax, 0x0010
                jmp _get16bit_loop
            _get16bit_f:
                pop ax
                sub ax, 0x0001
                jmp _get16bit_loop

            _get16bit_end:
                pop ax  ; New AX, what the user input
                pop cx  ; Old AX, what was passed into the function
                pop dx 
                pop cx 
                ret
            
            _get16bit_esc:
                pop ax  ; New AX
                pop ax  ; Old AX
                pop dx
                pop cx 
                ret
;;;;;;;;;; print an 8 bit hex number ( 2 digits ) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; This expects the 8 bit number in al
SUB_print8bithex:
	push cx
	push bx
	push ax
	push ax
	
	and ax, 0x00F0
	mov cl, 4
	shr ax, cl	    ; shr ax, 4 is only valid on the 80186 and later, so this is a workaround
	add al, '0'	    ; align 0 with '0'
	cmp al, '9'	
	jle _print8bithex_MS
	add al, ('A'-'9'-1) 
                    ; If digit is larger than '9' then add the offset required to make 10 align with 'A'
    _print8bithex_MS:
        mov ah, 0x0E
        mov bh, 0
        
        int 0x10

        pop ax
        and ax, 0x000F
        add al, '0'
        cmp al, '9'
        jle _print8bithex_LS
        add al, ('A'-'9'-1)
    _print8bithex_LS:
        mov ah, 0x0E
        mov bh, 0
        
        int 0x10
        
        pop ax
        pop bx
        pop cx
        ret
	
;;;;;;;;;; print a 16 bit hex number (16 digits) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; This expects the 16 bit number in ax
SUB_print16bithex:
	
	push ax
	mov al, ah
	call SUB_print8bithex
	
	pop ax
	call SUB_print8bithex
	
	ret

;;;;;;;;;; Strings and constants ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CONST_labeloffset       equ 1
CONST_modeoffset        equ 73
CONST_addressoffset     equ 81
CONST_mode_to_address   equ 8
CONST_home              equ 13

STRING_selectchar:
    db  175,0       ; Zero terminated so printing it is easier

STRING_newline:
    db 10,13,0

STRING_boxtop:
    db  218,196,196,196,196,196,196,196,196,196,191,0
STRING_boxmid:
    db  179,'         ',179,0
STRING_boxbottom:
    db  192,196,196,196,196,196,196,196,196,196,217,0

STRING_clearspace:
    db  '           ',0

STRING_copyright:
    db  'Menu System for PC Compatibles.',10,13
    db  'You are free to modify and distribute.',10,13
    db  'Copyright 2021, Mason Gulu.',0
;;;;;;;;;; Data structures ;;;;;;;;;;
; menu data structure will follow this layout
; 1 byte: maximum valid options
; 9 bytes (times 8): null terminated strings
; 8 bytes: selection mode
;   0 represents submenu
;   1 represents subroutine
;   Anything else is ignored, option becomes unselectable
; 16 bytes: addresses
;   mode 0 has address to data structure
;   mode 1 has address to subroutine
DATA_main:
    db  1           ; Number of valid options, 0 indexed
    db  'SubMenu ',0
    db  'Nothing ',0
    db  '        ',0
    db  '        ',0
    db  '        ',0
    db  '        ',0
    db  '        ',0
    db  '        ',0; Labels for each
    db  0,2,2,2,2,2,2,2
                    ; Data modes
    db  word DATA_sub
    db  word 0      ; Unused words can be removed. (After the last selectable element).
    db  word 0
    db  word 0
    db  word 0
    db  word 0
    db  word 0
    db  word 0      ; Addresses
DATA_sub:
    db  1           ; Number of valid options, 0 indexed
    db  'MainMenu',0
    db  'Nothing ',0
    db  '        ',0
    db  '        ',0
    db  '        ',0
    db  '        ',0
    db  '        ',0
    db  '        ',0; Labels for each
    db  0,2,2,2,2,2,2,2
                    ; Data modes
    db  word DATA_main