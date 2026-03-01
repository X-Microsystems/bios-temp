;==============================================================================
; startup.s
; System initialization
;==============================================================================
.include "vectors.inc"
.include "move.inc"
.include "xmodem.inc"
.include "crc.inc"
.include "xmcf-rtc.inc"
.include "xmcf-cf.inc"
.include "xms.inc"
.include "xms-uart.inc"
.include "xms-ps2.inc"
.include "print.inc"

.import wozmon, woz_init

.export _INIT				;Code label

XM7SEG		:= $D000

.segment "STARTUP"
.proc _INIT
		sei			; CPU Init
		cld
		ldx #$FF
		txs
					; Hardware driver inits
		jsr vt_init		; Interrupt vector table
		jsr rtc_init		; Real-Time Clock
		jsr cf_init		; CompactFlash

		jsr xms_init		; XMICRO-SERIAL card
		jsr uart_init		; UART2
		jsr ps2_init		; PS/2

					; Software inits		
		jsr woz_init		; Woz Monitor
		jsr crc16_init		; Generate CRC16 lookup tables

		cli			; Inits complete. Enable interrupts


		lda #$3C		; XMICRO-7SEG Clock display (temporary!)
		sta XM7SEG+3
		sta XM7SEG
		
;		jmp Keyboard ;!DEBUG

		lda #<Clock		
		sta ph_RTC_PI
		lda #>Clock
		sta ph_RTC_PI+1

		lda #<brk_temp		
		sta ph_PS2_Pabr
		lda #>brk_temp
		sta ph_PS2_Pabr+1

		jmp Loop		;

.endproc

Loop:		brk $AA
		jmp Loop

brk_temp:	brk $FF
		rts

test_DateTime:	lda #$0D
		jsr stdout
		lda #$0A
		jsr stdout
		
		jsr print_date
		
		lda #$0D
		jsr stdout
		lda #$0A
		jsr stdout
		
		rts

test_char:	lda #$1F
		jsr print_char
		lda #$20
		jsr print_char
		lda #$7E
		jsr print_char
		lda #$7F
		jsr print_char
		rts

test_word:	lda #$AB
		ldx #$CD
		jsr print_word
		rts

test_byte:	lda #$01
		jsr print_byte
		lda #$23
		jsr print_byte
		lda #$45
		jsr print_byte
		lda #$67
		jsr print_byte
		lda #$89
		jsr print_byte
		lda #$AB
		jsr print_byte
		lda #$CD
		jsr print_byte
		lda #$EF
		jsr print_byte
		rts

test_primm:	jsr print_imm
TestStr:	.byte $0D, $0A
		.byte "The quick brown fox jumps over the lazy dog."
		.byte $0D, $0A, $00
		rts

test_prabs:	lda #<TestStr
		sta p_Print
		lda #>TestStr
		sta p_Print+1
		jsr print_abs
		rts
		


test_nybble:	lda #$AB
		jsr print_nybble
		rts

Error_Halt:	sta XM7SEG		;Error code location
		brk
		nop
		sei
		wai
		rts

Clock:		;!DEBUG
		lda RTC_Jiffy+1
		sta $D002
		lda RTC_Time+RTCTime::Second
		sta $D000
		lda RTC_Time+RTCTime::Minute
		sta $D001
		rts

Keyboard:	;!DEBUG
		clc
		jsr kb_get
		beq Keyboard
		sta $D000
		bra Keyboard
		rts

KeyAscii:	;!DEBUG
		sec
		jsr kb_get
		beq KeyAscii
		sta $D000
		bcc KeyAscii
		jsr uart_tx
		bra KeyAscii
		rts

.segment "DATA"
Dest_Addr:	.res 2
LBA:		.res 1
.segment "CODE"
.proc test_CF_Read_Individual
		lda #$00
		sta Dest_Addr
		lda #$10
		sta Dest_Addr+1
		lda #$00
		sta LBA

@ReadLoop:	jsr ata_get_lock
		bcc :+
		jmp Error_Halt
:		lda #$01
		sta ATA_Cmd+ATAPar::SecCo
		lda LBA
		sta ATA_Cmd+ATAPar::LBA0
		lda #$00
		sta ATA_Cmd+ATAPar::LBA1
		lda #$00
		sta ATA_Cmd+ATAPar::LBA2
		lda #$40
		sta ATA_Cmd+ATAPar::LBA3
		lda #$20
		sta ATA_Cmd+ATAPar::Cmd
		lda #ATAClass::DataIn
		sta ATA_Cmd+ATAPar::Class
		lda Dest_Addr
		sta ATA_Cmd+ATAPar::Addr
		lda Dest_Addr+1
		sta ATA_Cmd+ATAPar::Addr+1
		jsr ata_rejoin

		inc Dest_Addr+1
		inc Dest_Addr+1
		inc LBA
		lda LBA
		cmp #$40
		bne @ReadLoop
		rts
.endproc

.proc test_CF_Write_Individual
		lda #$00
		sta Dest_Addr
		lda #$10
		sta Dest_Addr+1
		lda #$00
		sta LBA

@ReadLoop:	jsr ata_get_lock
		bcc :+
		jmp Error_Halt
:		lda #$01
		sta ATA_Cmd+ATAPar::SecCo
		lda LBA
		sta ATA_Cmd+ATAPar::LBA0
		lda #$00
		sta ATA_Cmd+ATAPar::LBA1
		lda #$00
		sta ATA_Cmd+ATAPar::LBA2
		lda #$40
		sta ATA_Cmd+ATAPar::LBA3
		lda #CF_ATA_WS
		sta ATA_Cmd+ATAPar::Cmd
		lda #ATAClass::DataOut
		sta ATA_Cmd+ATAPar::Class
		lda Dest_Addr
		sta ATA_Cmd+ATAPar::Addr
		lda Dest_Addr+1
		sta ATA_Cmd+ATAPar::Addr+1
		jsr ata_rejoin

		inc Dest_Addr+1
		inc Dest_Addr+1
		inc LBA
		lda LBA
		cmp #$40
		bne @ReadLoop
		rts
.endproc

.proc test_CF_Read_8
		lda #$00
		sta Dest_Addr
		lda #$10
		sta Dest_Addr+1
		lda #$00
		sta LBA

@ReadLoop:	jsr ata_get_lock
		bcc :+
		jmp Error_Halt
:		lda #$40
		sta ATA_Cmd+ATAPar::SecCo
		lda LBA
		sta ATA_Cmd+ATAPar::LBA0
		lda #$00
		sta ATA_Cmd+ATAPar::LBA1
		lda #$00
		sta ATA_Cmd+ATAPar::LBA2
		lda #$40
		sta ATA_Cmd+ATAPar::LBA3
		lda #CF_ATA_RS
		sta ATA_Cmd+ATAPar::Cmd
		lda #ATAClass::DataIn
		sta ATA_Cmd+ATAPar::Class
		lda Dest_Addr
		sta ATA_Cmd+ATAPar::Addr
		lda Dest_Addr+1
		sta ATA_Cmd+ATAPar::Addr+1
		jsr ata_rejoin
		rts
.endproc 

.proc test_CF_Write_8
		lda #$00
		sta Dest_Addr
		lda #$10
		sta Dest_Addr+1
		lda #$00
		sta LBA

@ReadLoop:	jsr ata_get_lock
		bcc :+
		jmp Error_Halt
:		lda #$40
		sta ATA_Cmd+ATAPar::SecCo
		lda LBA
		sta ATA_Cmd+ATAPar::LBA0
		lda #$00
		sta ATA_Cmd+ATAPar::LBA1
		lda #$00
		sta ATA_Cmd+ATAPar::LBA2
		lda #$40
		sta ATA_Cmd+ATAPar::LBA3
		lda #CF_ATA_WS
		sta ATA_Cmd+ATAPar::Cmd
		lda #ATAClass::DataOut
		sta ATA_Cmd+ATAPar::Class
		lda Dest_Addr
		sta ATA_Cmd+ATAPar::Addr
		lda Dest_Addr+1
		sta ATA_Cmd+ATAPar::Addr+1
		jsr ata_rejoin
		rts
.endproc