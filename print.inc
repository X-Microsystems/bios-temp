;==============================================================================
; print.inc
;==============================================================================

.ifndef _PRINT_INC_			; Don't allow multiple includes
_PRINT_INC_ = 1

.ifndef _PRINT_NOIMPORTS_		; Skip imports

.import stdout, stderr
.import	print_char, print_imm, print_abs, print_word, print_byte, print_nybble	; Procedures
.import print_date, print_time
.import print_nl, print_space
.importzp p_Print				; Pointers

.endif

.include "xms.inc"

;==============================================================================
; 
;==============================================================================
; 

.endif