;==============================================================================
; print.s
; Terminal I/O routines
;==============================================================================

_PRINT_NOIMPORTS_ = 1
.include "print.inc"
.include "xms-uart.inc"
.include "xmcf-rtc.inc"

.export stdout, stderr
.export	print_char, print_imm, print_abs, print_word, print_byte, print_nybble	; Procedures
.export print_date, print_time
.export print_nl, print_space
.export p_Print				; Pointers

; Variables
.segment "ZEROPAGE"
p_Print:		.res 2			; String pointer

.segment "CODE"
;==============================================================================
; stdout - Standard output
; Inputs .A
;==============================================================================
;.proc stdout
;		jsr uart_tx		;
;		rts			;
;.endproc
stdout 		:= uart_tx		; Currently only using the UART

;==============================================================================
; stderr - Standard error output
; Inputs .A
;==============================================================================
;.proc stdout
;		jsr uart_tx		;
;		rts			;
;.endproc
stderr 		:= uart_tx		; Currently only using the UART

;==============================================================================
; print_abs - Print a null-terminated string at the address in p_Print
; Inputs p_Print
; Clobbers .A, p_Print
;==============================================================================
.proc print_abs
		lda (p_Print)		; Load the value at the pointer
		beq Return		; Return if it's 0
		jsr stdout		; Otherwise, print it and increment
IncPtr:		inc p_Print		;  the pointer
		bne print_abs		;
		inc p_Print+1		;
		bra print_abs		; Loop until the string terminates
Return:		rts
.endproc

;==============================================================================
; print_imm - Print a null-terminated string immediately following the
; procedure call, and return to the address following the string.
; Clobbers .A
;==============================================================================
.proc print_imm
		pla 			; Get the invoking PC address LSB
		sta p_Print		; Store it in the string pointer
		pla			; Get the MSB
		sta p_Print+1		; Store it
		jsr ::print_abs::IncPtr	; Increment the pointer and print
		lda p_Print+1		; Return to the address following the
		pha			;  string
		lda p_Print		;
		pha			;
		rts			;
.endproc

;==============================================================================
; print_char - Print an ASCII character. If it isn't printable, print "."
; Clobbers .A
;==============================================================================
.proc print_char
		cmp #$20		;
		bcc NotAscii		; <$20 - not printable
		cmp #$7F		;
		bcc Print		; Character is printable. Print as-is
NotAscii:	lda #'.'		; Not printable. Load placeholder
Print:		jsr stdout		; Print it.
		rts			;
.endproc

;==============================================================================
; print_word - Print two bytes in hexadecimal
; Inputs
;  .A	MSB
;  .X	LSB
; Clobbers .A
;==============================================================================
.proc print_word
		jsr print_byte		; Print the MSB
		txa			;
;		bra print_byte		; Print the LSB
.endproc

;==============================================================================
; print_byte - Print one byte in hexadecimal
; Inputs .A
; Clobbers .A
;==============================================================================
.proc print_byte
		pha			;
		lsr			; Shift the high nybble right
		lsr			;
		lsr			;
		lsr			;
		jsr print_nybble	; Print it
		pla			; Get the original byte
;		jsr print_nybble	; Print the low nybble
;		rts			;
.endproc

;==============================================================================
; print_nybble - Print one nybble in hexadecimal.
; Inputs .A (Bits 3-0)
; Clobbers .A
;==============================================================================
.proc print_nybble
		and #$0F		; Mask LSD
		ora #$30		; Add ASCII "0"
		cmp #$3A		; Digit?
		bcc Print		; Yes, print it.
		adc #$06		; Add offset for letter
Print:		jsr stdout		;
		rts			;
.endproc

;==============================================================================
; print_date - Print the date and time
; Clobbers .AX
;==============================================================================
.proc print_date
		ldx #$03		;
Loop:		lda RTC_Time+RTCTime::Date,x	; Load date byte, MSB first
		jsr print_byte		; Print it
		dex			; Was that the last byte?
		bmi Space		; Yes, return.
		cpx #$02		; No. Middle of the year?
		beq Loop		; Yes, don't add a heyphen here, loop.
		lda #'-'		; No, add a separator
		jsr stdout		; Print it
		bra Loop		; Loop until finished
Space:		lda #' '		; Separate date and time with a space
		jsr stdout		;
;		bra print_time		;
.endproc

;==============================================================================
; print_time - Print the time (HH:MM:SS)
; Clobbers .AX
;==============================================================================
.proc print_time
		ldx #$02		;
Loop:		lda RTC_Time+RTCTime::Second,x	; Load time byte, MSB first
		jsr print_byte		; Print it
		dex			; Was that the last byte?
		bmi Return		; Yes, return.
		lda #':'		; No, add a separator
		jsr stdout		; Print it
		bra Loop		; Loop until finished
Return:		rts			;
.endproc

;==============================================================================
; print_nl - Print a new line
; Clobbers .A
;==============================================================================
.proc print_nl
		lda #$0D		; Print CR
		jsr stdout		;
		lda #$0A		; Print LF
		jmp stdout		; Return from stdout
.endproc

;==============================================================================
; print_space - Print a space
; Clobbers .A
;==============================================================================
.proc print_space
		lda #' '		; Print Space
		jmp stdout		; Return from stdout
.endproc

