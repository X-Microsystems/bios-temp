;==============================================================================
; xms-uart.s
; 16C550 single-UART driver for XMICRO-SERIAL
;==============================================================================
; Notes
; 1. This module works with a single UART. The "UART" constant defines the
; base address.

;==============================================================================

_UART_NOIMPORTS_ = 1			; No imports from xms-uart.inc
.include "xms-uart.inc"			; Constants for this module

.constructor uart_init, 6		; Startup routine
.interruptor uart_interrupt		; Interrupt Routine
.export uart_rx, uart_tx, uart_rx_check	; Procedures

.segment "CODE"
;==============================================================================
; uart_rx
; Waits until a received byte is available and returns it.
;
; Outputs
;  .A	Data byte received
;==============================================================================
.proc uart_rx
		lda #UART_LSR_RDR	; Load the Receive Data Ready bitmask
RxLoop:		bit UART+UART_LSR	; Check the RDR bit
		beq RxLoop		; Loop if there is no data ready
		lda UART+UART_RHR	; Load data byte
		rts			;		
.endproc

;==============================================================================
; uart_rx_check
; Checks if a received byte is available and returns it. If no data has been
; received, returns with Carry cleared.
;
; Outputs
;  .A	Data byte received (if available)
;  .C	Carry flag is set if data was received
;==============================================================================
.proc uart_rx_check
		lda #UART_LSR_RDR	; Load the Receive Data Ready bitmask
		bit UART+UART_LSR	; Check the RDR bit
		beq NoData		;
		lda UART+UART_RHR	; Data byte waiting - load it
		sec			; Set carry to indicate data in .A
		rts			;

NoData:		clc			; No new data available - clear carry
		rts			; and return
.endproc

;==============================================================================
; uart_tx
; Waits until the UART is ready to transmit a byte and sends one.
;
; Inputs
;  .A	Data byte to send
;==============================================================================
.proc uart_tx
		pha			; Push data byte
		lda #UART_LSR_THE	; Load the TX Holding Empty bitmask
TxLoop:		bit UART+UART_LSR	; Check the THE bit
		beq TxLoop		; Loop if the UART isn't ready
		pla			; THR ready - pull data byte
		sta UART+UART_THR	; Send it
		rts			;
.endproc

;==============================================================================
; uart_init
; Initializes the UART
;
; Inputs
;  .A
;==============================================================================
.proc uart_init
		lda #<uart_interrupt	; Set ISR hook
		sta UART_Hook		;
		lda #>uart_interrupt	;
		sta UART_Hook+1		;

		ldx #$00		;
InitLoop:	ldy UART_Init_Tbl,x	; Load register address from init table
		inx			;
		lda UART_Init_Tbl,x	; Load register value from init table
		inx			;
		sta UART,y		; Store the value in the UART register
		cpx #14			;
		bne InitLoop		; Loop until complete
		rts			;
.endproc

;==============================================================================
; uart_interrupt
; Interrupt Service Routine for UART
; *Exits with RTS, not RTI, to return from primary ISR hook*
;
;==============================================================================
.proc uart_interrupt
		rts			;
.endproc

.segment "RODATA"
; Tables
UART_Init_Tbl:
	.byte	UART_IER,	%00000000	; Disable interrupts
	.byte	UART_FCR,	%00000000	; Disable FIFO
	.byte	UART_LCR,	%10000011	; Enable Divisor Latch
	.byte	UART_DLL,	<UART_BG_9600	; 9600 baud
	.byte	UART_DLM,	>UART_BG_9600	; 9600 baud
	.byte	UART_LCR,	%00000011	; 8N1, disable Divisor Latch
	.byte	UART_MCR,	%00000000	; Modem Control lines high
	