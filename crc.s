;==============================================================================
; crc.s
; CRC routines
; Adapted from http://www.6502.org/source/integers/CRC.htm
;==============================================================================

.constructor crc16_init                        ; Constructors
;.export crc16_add                        ; Procedures
.export crc16_val                        ; Variables
.export crc16_table_l, crc16_table_h        ; Lookup Tables

.segment "DATA"
crc16_val:        .res 2                        ; Computed CRC value

crc16_table_l        := $de00                ; Two 256-byte tables for quick lookup
crc16_table_h        := crc16_table_l+$100        ; (should be page-aligned for speed)

.segment "ONCE"
;==============================================================================
; crc16_init
; Generates 16-bit CRC lookup tables at CRC16_TABLE_L and CRC16_TABLE_H.
; 
; Clobbers .AXY, CRC
;==============================================================================
.proc crc16_init
                ldx #0                        ; X counts from 0 to 255
ByteLoop:        lda #0                        ; A contains the low 8 bits of the CRC-16
                stx crc16_val                ; and crc16_val contains the high 8 bits
                ldy #8                        ; Y counts bits in a byte
BitLoop:        asl
                rol crc16_val                ; Shift crc16_val left
                bcc NoAdd                ; Do nothing if no overflow
                eor #$21                ; else add CRC-16 polynomial $1021
                pha                        ; Save low byte
                lda crc16_val                ; Do high byte
                eor #$10
                sta crc16_val
                pla                        ; Restore low byte
NoAdd:                dey
                bne BitLoop                ; Do next bit
                sta crc16_table_l,x        ; Save CRC into table, low byte
                lda crc16_val                ; then high byte
                sta crc16_table_h,x
                inx
                bne ByteLoop                ; Do next byte
                rts
.endproc

;.segment "CODE"
;==============================================================================
; crc16_add
; Adds a data byte to the 16-bit CRC value stored in crc16_val.
;
; Inputs
;  crc16_val (2 bytes)        Current CRC value. *Initialize to $FFFF for new CRC*
;  .A                        Data byte to add
;
; Returns
;  crc16_val
;
; Clobbers .AX
;==============================================================================
;.proc crc16_add
;                eor crc16_val+1                ; Quick CRC computation with lookup tables
;                tax
;                lda crc16_val
;                eor crc16_table_h,x
;                sta crc16_val+1
;                lda crc16_table_l,x
;                sta crc
;                rts
;.endproc
