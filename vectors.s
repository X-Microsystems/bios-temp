; ---------------------------------------------------------------------------
; vectors.s
; 6502 hardware vectors and xmicro-6502 interrupt vector labels
; ---------------------------------------------------------------------------

.include "move.inc"

.import _INIT									;Code labels
.import __VECTORTABLE_LOAD__, __VECTORTABLE_RUN__, __VECTORTABLE_SIZE__		;Segment information

.constructor vt_init
.export IRQ0, IRQ1, IRQ2, IRQ3, IRQ4, IRQ5, IRQ6, IRQ7, NMI_VECTOR, BRK_VECTOR	;Code labels

IRQ0		:= $0200		;IRQ0-IRQ7 vector address locations
IRQ1		:= $0204
IRQ2		:= $0208
IRQ3		:= $020C
IRQ4		:= $0210
IRQ5		:= $0214
IRQ6		:= $0218
IRQ7		:= $021C
NMI_VECTOR	:= $0220
DMA_VECTOR	:= $023C
BRK_VECTOR	:= $027C		;BRK code address

;==============================================================================
; vt_init
; Initialize the vector table to defaults.
; Populates the VT with vectortable segment
; Populates the brk vector with an rti instruction
;==============================================================================
.proc vt_init
		MOVE #__VECTORTABLE_LOAD__, #__VECTORTABLE_RUN__, #__VECTORTABLE_SIZE__

		lda #$40		; Place RTI opcode at the BRK vector
		sta DMA_VECTOR
		sta BRK_VECTOR
		rts
.endproc

.segment "VECTORTABLE"
		jmp BRK_VECTOR		;IRQ0
		brk
		jmp BRK_VECTOR		;IRQ1
		brk
		jmp BRK_VECTOR		;IRQ2
		brk
		jmp BRK_VECTOR		;IRQ3
		brk
		jmp BRK_VECTOR		;IRQ4
		brk
		jmp BRK_VECTOR		;IRQ5
		brk
		jmp BRK_VECTOR		;IRQ6
		brk
		jmp BRK_VECTOR		;IRQ7
		brk
		jmp BRK_VECTOR		;NMI
		brk

.segment "CPUVECTORS"
.addr		NMI_VECTOR		; NMI vector
.addr		_INIT			; Reset vector
.addr		BRK_VECTOR		; IRQ/BRK vector
