;==============================================================================
; move.s
; Block memory move routines
; Adapted from http://www.6502.org/source/general/memory_move.html
;==============================================================================

.export move, movedown, moveup, zerofill	;Procedures
.exportzp Move_From, Move_To			;Zero-page variables
.export Move_Size				;Variables

.segment "ZEROPAGE"
	Move_From:	.res 2
	Move_To:	.res 2

.segment "DATA"
	Move_Size:	.res 2

.segment "CODE"
;==============================================================================
; move
; Copies a block of memory by automatically moveup or movedown
; 
; Inputs
;  Move_From		Source start address (clobbered)
;  Move_To		Destination start address (clobbered)
;  Move_Size		Number of bytes to move
;
; Clobbers .AXY, Move_From, Move_To
;==============================================================================
.proc move
		lda Move_From+1
		cmp Move_To+1
		bcc moveup
		bne movedown
		lda Move_From
		cmp Move_To
		bcc moveup
.endproc

;==============================================================================
; movedown
; Copies a block of memory starting at the lowest address
; *Can't be used on overlapping blocks where the destination is higher*
;
; move_from = source start address
; move_to = destination start address
; move_size = number of bytes to move
;
; Clobbers .AXY
;==============================================================================
.proc movedown
		ldy #00
		ldx Move_Size+1
		beq @2
@1:		lda (Move_From),Y	; Move a page at a time
		sta (Move_To),Y
		iny
		bne @1
		inc Move_From+1
		inc Move_To+1
		dex
		bne @1
@2:		ldx Move_Size
		beq @4
@3:		lda (Move_From),Y	; Move the remaining bytes
		sta (Move_To),Y
		iny
		dex
		bne @3
@4:		rts
.endproc

;==============================================================================
; moveup
; Copies a block of memory starting at the highest address
; *Can't be used on overlapping blocks where the destination is lower*
;
; Inputs
;  Move_From		Source start address
;  Move_To		Destination start address
;  Move_Size		Number of bytes to move
;
; Clobbers .AXY, Move_From, Move_To
;==============================================================================
.proc moveup
		ldx Move_Size+1		; THE LAST BYTE MUST BE MOVED FIRST
		clc			; START AT THE FINAL PAGES OF FROM AND TO
		txa
		adc Move_From+1
		sta Move_From+1
		clc
		txa
		adc Move_To+1
		sta Move_To+1
		inx			; ALLOWS THE USE OF BNE AFTER THE DEX BELOW
		ldy Move_Size
		beq @3
		dey			; MOVE BYTES ON THE LAST PAGE FIRST
		beq @2
@1:		lda (Move_From),Y
		sta (Move_To),Y
		dey
		bne @1
@2:		lda (Move_From),Y	; Handle Y = 0 separately
		sta (Move_To),Y
@3:		dey
		dec Move_From+1		; Move the next page (if any)
		dec Move_To+1
		dex
		bne @1
		rts
.endproc

;==============================================================================
; zerofill
; Copies all zeros to specified range
;
; Inputs
;  Move_To		Destination start address
;  Move_Size		Number of bytes to zero
;
; Clobbers .AXY
;==============================================================================
.proc zerofill
		lda #$00
		tay
		ldx Move_Size+1
		beq @2
@1:		sta (Move_To),Y
		iny
		bne @1
		inc Move_To+1
		dex
		bne @1
@2:		ldx Move_Size
		beq @4
@3:		sta (Move_To),Y
		iny
		dex
		bne @3
@4:		rts
.endproc
