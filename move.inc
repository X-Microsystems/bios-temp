;==============================================================================
; move.inc
;==============================================================================
.ifndef _MOVE_INC_
_MOVE_INC_ = 1

.import move, move_down, move_up, zero_fill	;Procedures
.importzp Move_From, Move_To			;Zero-page variables
.import Move_Size				;Variables

;==============================================================================
; MOVE Macro
; Sets up parameters and runs the move routine
;==============================================================================
.macro MOVE From, To, Size
	.if (.match(.left(1, {From}), #))			;Immediate mode
		lda #<(.right(.tcount({From})-1, {From}))
		sta Move_From
		lda #>(.right(.tcount({From})-1, {From}))
		sta 1+Move_From
	.else							;Assume absolute or zero page
		lda From
		sta Move_From
		lda 1+From
		sta 1+Move_From
	.endif

	.if (.match(.left(1, {To}), #))				;Immediate mode
		lda #<(.right(.tcount({To})-1, {To}))
		sta Move_To
		lda #>(.right(.tcount({To})-1, {To}))
		sta 1+Move_To
	.else							;Assume absolute or zero page
		lda To
		sta Move_To
		lda 1+To
		sta 1+Move_To
	.endif

	.if (.match(.left(1, {Size}), #))			;Immediate mode
		lda #<(.right(.tcount({Size})-1, {Size}))
		sta Move_Size
		lda #>(.right(.tcount({Size})-1, {Size}))
		sta 1+Move_Size
	.else							;Assume absolute or zero page
		lda Size
		sta Move_Size
		lda 1+Size
		sta 1+Move_Size
	.endif

	jsr move
.endmacro

;==============================================================================
; ZEROFILL Macro
; Copies all zeros to specified range
;==============================================================================
.macro ZEROFILL To, Size
	.if (.match(.left(1, {From}), #))			;Immediate mode
		LDA #<(.right(.tcount({From})-1, {From}))
		STA Move_From
		LDA #>(.right(.tcount({From})-1, {From}))
		STA 1+Move_From
	.else							;Assume absolute or zero page
		LDA From
		STA Move_From
		LDA 1+From
		STA 1+Move_From
	.endif

	.if (.match(.left(1, {To}), #))			;Immediate mode
		LDA #<(.right(.tcount({To})-1, {To}))
		STA Move_To
		LDA #>(.right(.tcount({To})-1, {To}))
		STA 1+Move_To
	.else							;Assume absolute or zero page
		LDA To
		STA Move_To
		LDA 1+To
		STA 1+Move_To
	.endif

	.if (.match(.left(1, {Size}), #))			;Immediate mode
		LDA #<(.right(.tcount({Size})-1, {Size}))
		STA Move_Size
		LDA #>(.right(.tcount({Size})-1, {Size}))
		STA 1+Move_Size
	.else							;Assume absolute or zero page
		LDA Size
		STA Move_Size
		LDA 1+Size
		STA 1+Move_Size
	.endif

	jsr zero_fill
.endmacro

.endif