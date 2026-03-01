;==============================================================================
; xms.s
; XMICRO-SERIAL card driver
;==============================================================================
; Notes

;==============================================================================

_XMS_NOIMPORTS_ = 1			; No imports from xms.inc
.include "xms.inc"			; Constants for this module
.include "xms-uart.inc"			;

.constructor xms_init			; Startup routine
.interruptor xms_isr			; Interrupt Routine
.export ph_UART1_ISR, ph_UART2_ISR, ph_PS2_ISR	; ISR hook pointers

; Variables
.segment "DATA"

; Hooks
; All hooks are expected to return with an RTS.
ph_UART1_ISR:	.res 2			; UART1 interrupt hook
ph_UART2_ISR:	.res 2			; UART2 interrupt hook
ph_PS2_ISR:	.res 2			; PS/2 interrupt hook


.segment "CODE"

;==============================================================================
; xms_isr
; Interrupt service routine for the XMICRO-SERIAL card. Finds which device is
; Generating the IRQ and indirect-jumps to an ISR hook for that device.
;
; Hooks
;  ph_UART1_ISR		Vector location for a UART1 ISR
;  ph_UART2_ISR		Vector location for a UART2 ISR
;  ph_PS2_ISR		Vector location for a PS/2 ISR
;
; Clobbers .A
;==============================================================================
.proc xms_isr
		pha			;
		phx			;
		phy			;
		lda XMS_SR		;
U1Check:	bit #XMS_SR_UI1		; Check for a pending UART1 interrupt
		beq U2Check	 	;
		jsr U1			; Indirect JSR to UART1 hook
U2Check:	bit #XMS_SR_UI2		; Check for a pending UART1 interrupt
		beq PS2Check	 	;
		jsr U2			; Indirect JSR to UART2 hook
PS2Check:	bit #XMS_SR_PDR		; Check for a pending PS/2 interrupt
		beq Return 		;
		jsr PS2			; Indirect JSR to PS2 hook
Return:		ply			;
		plx			;
		pla			;
		rti			;

U1:		jmp (ph_UART1_ISR)	; UART 1 interrupt - jump to the ISR.
U2:		jmp (ph_UART2_ISR)	; UART 2 interrupt - jump to the ISR.
PS2:		jmp (ph_PS2_ISR)	; PS/2 interrupt - jump to the ISR.
.endproc

.segment "ONCE"
;==============================================================================
; xms_init
; Initializes the XMICRO-SERIAL hardware and functions
; *This should be run at system startup, before interrupts are enabled, and
; before other UART initialization routines.*
; 
; Clobbers .AX
;==============================================================================
.proc xms_init
		lda #<xms_isr		; Place the ISR in the vector table
		sta XMS_VECTOR		;
		lda #>xms_isr		;
		sta XMS_VECTOR+1	;
		ldx #$00		;
SoftVectors:	lda #<Return		; Set hooks to do nothing, point to RTS
		sta ph_UART1_ISR,x	;
		inx			;
		lda #>Return		;
		sta ph_UART1_ISR,x	;
		inx			;
		cpx #$06		; Repeat for 3 hooks
		bne SoftVectors		;

		ldx #$00		;
UartInit:	ldy XMS_Init_Tbl,x	; Load register address from init table
		inx			;
		lda XMS_Init_Tbl,x	; Load register value from init table
		inx			;
		sta UART1,y		; Store the value in the UART1 register
		sta UART2,y		; Store the value in the UART2 register		
		cpx #14			;
		bne UartInit		; Loop until complete

Ps2Init:	lda PS2_DATA		; Clear the PS2 Data Register

Return:		rts			;

.segment "RODATA"
; Tables
; Initialization table - Register/Value pairs for xms_init
XMS_Init_Tbl:
	.byte	UART_IER,	%00000000	; Disable interrupts
	.byte	UART_FCR,	%00000000	; Disable FIFO
	.byte	UART_LCR,	%10000011	; Enable Divisor Latch
	.byte	UART_DLL,	<UART_BG_9600	; 9600 baud
	.byte	UART_DLM,	>UART_BG_9600	; 9600 baud
	.byte	UART_LCR,	%00000011	; 8N1, disable Divisor Latch
	.byte	UART_MCR,	%00000000	; Modem Control lines high
.segment "ONCE"
.endproc