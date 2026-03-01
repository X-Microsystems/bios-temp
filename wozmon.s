
;  The WOZ Monitor for the Apple 1
;  Written by Steve Wozniak in 1976


;! Holding Print Screen and repeatedly quitting causes crash

.constructor woz_init
.export wozmon

.include "vectors.inc"
.include "xms.inc"
.include "xms-uart.inc"
.include "xms-ps2.inc"
.include "print.inc"

; Page 0 Variables
XAML		:= $F8			; Last "opened" location Low
XAMH		:= $F9			; Last "opened" location High
STL		:= $FA			; Store address Low
STH		:= $FB			; Store address High
L		:= $FC			; Hex value parsing Low
H		:= $FD			; Hex value parsing High
YSAV		:= $FE			; Used to see if hex value is given
MODE		:= $FF			; $00=XAM, $7F=STOR, $AE=BLOCK XAM

; Other Variables
.segment "DATA"
IN:		.RES $50		; Input buffer

.segment "ONCE"
.proc woz_init				; Initialize Wozmon
;		LDA #$4C
;		STA BRK_VECTOR
;		LDA #<wozmon
;		STA BRK_VECTOR+1
;		LDA #>wozmon
;		STA BRK_VECTOR+2

		LDA #$4C
		STA BRK_VECTOR
		LDA #<monitor_brk
		STA BRK_VECTOR+1
		LDA #>monitor_brk
		STA BRK_VECTOR+2

		RTS
.endproc

.segment "CODE"
.proc wozmon
	;PHA
	;PHY
	;PHX
RESET:	;CLD			; Clear decimal arithmetic mode.
	;CLI
		LDY #$7F		; Mask for DSP data direction register.
		;STY DSP		; Set it up.
		LDA #$A7		; KBD and DSP control register mask.
		;STA KBDCR		; Enable interrupts, set CA1, CB1, for
		;STA DSPCR		; positive edge sense/output mode.
NOTCR:		;CMP #'_'		; "_"?
		CMP #$08 + $80
		BEQ BACKSPACE		; Yes.
		;CMP #$1B		; ESC?
		CMP #$9B		; ESC?
		BEQ ESCAPE		; Yes.
		INY			; Advance text index.
		BPL NEXTCHAR		; Auto ESC if > 127.
ESCAPE:		LDA #'\' + $80		; "\".
		JSR ECHO		; Output it.
GETLINE:	LDA #$8D		; CR.
		JSR ECHO		; Output it.
		LDA #$8A		; LF.
		JSR ECHO		; Output it.
		LDY #$01		; Initialize text index.
BACKSPACE:	DEY			; Back up text index.
		BMI GETLINE		; Beyond start of line, reinitialize.
NEXTCHAR:	jsr uart_rx_check	; Check for serial byte
		bcs GotChar		; If a byte was received, process it
		sec			; Set Carry for ASCII keyboard
		jsr kb_get		; Check for keyboard byte
		bcs GotChar		; If ASCII character was received, process it
		beq NEXTCHAR		; If no keycodes were received, loop
		cmp #KB_PRINT		; Is the keycoade a Print Screen?
		bne :+			; No, next
		jmp QUIT		; Yes, exit.
:		cmp #KB_BSPACE		; Is the keycoade a backspace?
		bne :+			; No, next
		lda #$08		; Yes, proceed with a Backspace
		bra GotChar		;
:		cmp #KB_ENTER		; Is the keycoade an Enter?
		bne NEXTCHAR		; No, loop
		lda #$0D		; Yes, proceed with a CR

GotChar:	CMP #$60		; Convert to upper-case
		BCC :+
		AND #$DF
:		ORA #$80
		STA IN,Y		; Add to text buffer.
		JSR ECHO		; Display character.
		CMP #$8D		; CR?
		;CMP #$0D		; check for $0D instead $8D because bit7
					; has been cleared during JSR ECHO
		BNE NOTCR		; No.
		LDY #$FF		; Reset text index.
		LDA #$00		; For XAM mode.
		TAX			; 0->X.
SETSTOR:	ASL			; Leaves $7B if setting STOR mode.
SETMODE:	STA MODE		; $00=XAM $7B=STOR $AE=BLOK XAM
BLSKIP:		INY			; Advance text index.
NEXTITEM:	LDA IN,Y		; Get character.
		CMP #$8D		; CR?
		BEQ GETLINE		; Yes, done this line.
		CMP #'.' + $80		; "."?
		BCC BLSKIP		; Skip delimiter.
		BEQ SETMODE		; Yes. Set STOR mode.
		CMP #':' + $80		; ":"?
		BEQ SETSTOR		; Yes. Set STOR mode.
		CMP #'R' + $80		; "R"?
;		BEQ RUN			; Yes. Run user program.
;		CMP #'S' + $80		; "S"?
		BEQ SUB			; Yes. Run subroutine.
		CMP #'Q' + $80		; "Q"?
		BEQ QUIT		; Yes. Return to program.
		STX L			; $00-> L.
		STX H			; and H.
		STY YSAV		; Save Y for comparison.
NEXTHEX:	LDA IN,Y		; Get character for hex test.
		EOR #$B0		; Map digits to $0-9.
		CMP #$0A		; Digit?
		BCC DIG			; Yes.
		ADC #$88		; Map letter "A"-"F" to $FA-FF.
		CMP #$FA		; Hex letter?
		BCC NOTHEX		; No, character not hex.
DIG:		ASL
		ASL			; Hex digit to MSD of A.
		ASL
		ASL
		LDX #$04		; Shift count.
HEXSHIFT:	ASL			; Hex digit left, MSB to carry.
		ROL L			; Rotate into LSD.
		ROL H			; Rotate into MSD's.
		DEX			; Done 4 shifts?
		BNE HEXSHIFT		; No, loop.
		INY			; Advance text index.
		BNE NEXTHEX		; Always taken. Check next char for hex.
NOTHEX:		CPY YSAV		; Check if L, H empty (no hex digits).
;		BEQ ESCAPE		; Yes, generate ESC sequence.
	bne :+
	jmp ESCAPE
:		BIT MODE		; Test MODE byte.
		BVC NOTSTOR		; B6=0 STOR 1 for XAM & BLOCK XAM
		LDA L			; LSD's of hex data.
		STA (STL,X)		; Store at current 'store index'.
		INC STL			; Increment store index.
		BNE NEXTITEM		; Get next item. (no carry).
		INC STH			; Add carry to 'store index' high order.
TONEXTITEM:	JMP NEXTITEM		; Get next command item.
SUB:		LDA #>(ESCAPE-1)	; Push wozmon return address to stack (simulate JSR)
		PHA
		LDA #<(ESCAPE-1)
		PHA
RUN:		JMP (XAML)		; Run at current XAM index.
QUIT:		PLX
		PLY
		PLA
		RTI
NOTSTOR:	BMI XAMNEXT		; B7=0 for XAM, 1 for BLOCK XAM.
		;BNE XAMNEXT
		LDX #$02		; Byte count.
SETADR:		LDA L-1,X		; Copy hex data to
		STA STL-1,X		; 'store index'.
		STA XAML-1,X		; And to 'XAM index'.
		DEX			; Next of 2 bytes.
		BNE SETADR		; Loop unless X=0.
NXTPRNT:	BNE PRDATA		; NE means no address to print.
		LDA #$8D		; LF.
		JSR ECHO		; Output it.
		LDA #$8A		; CR.
		JSR ECHO		; Output it.
		LDA XAMH		; 'Examine index' high-order byte.
		JSR PRBYTE		; Output it in hex format.
		LDA XAML		; Low-order 'examine index' byte.
		JSR PRBYTE		; Output it in hex format.
		LDA #':' + $80		; ":".
		JSR ECHO		; Output it.
PRDATA:		LDA #$A0		; Blank.
		JSR ECHO		; Output it.
		LDA (XAML,X)		; Get data byte at 'examine index'.
		JSR PRBYTE		; Output it in hex format.
XAMNEXT:	STX MODE		; 0->MODE (XAM mode).
		LDA XAML
		CMP L			; Compare 'examine index' to hex data.
		LDA XAMH
		SBC H
		BCS TONEXTITEM		; Not less, so no more data to output.
		INC XAML
		BNE MOD8CHK		; Increment 'examine index'.
		INC XAMH
MOD8CHK:	LDA XAML		; Check low-order 'examine index' byte
		AND #$07		; For MOD 8=0
		BPL NXTPRNT		; Always taken.
PRBYTE:		PHA			; Save A for LSD.
		LSR
		LSR
		LSR			; MSD to LSD position.
		LSR
		JSR PRHEX		; Output hex digit.
		PLA			; Restore A.
PRHEX:		AND #$0F		; Mask LSD for hex print.
		ORA #'0' + $80		; Add "0".
		CMP #$BA		; Digit?
		BCC ECHO		; Yes, output it.
		ADC #$06		; Add offset for letter.
ECHO:
		;BIT DSP		; bit (B7) cleared yet?
		;BMI ECHO		; No, wait for display.
		;STA DSP		; Output character. Sets DA.
		PHA
		AND #$7F
		JSR stdout
		PLA
		RTS			; Return.
.endproc




.struct MonBrk				; Data structure for BRK debug output
	Sig	.res 1			; BRK signature byte
	PC	.res 2			; Program Counter
	SP	.res 1			; Stack Pointer
	RegA	.res 1			; A register
	RegX	.res 1			; X register
	RegY	.res 1			; Y register
	SRBits	.res 8			; Status register bits (as characters)
	SR	.res 1			; Status Register
.endstruct

.proc monitor_brk
;BRK entry point
;Get the CPU PC, status register bits, and registers, and print them to the console
		cld			;
		cli			;
		phx			; Push the registers to the stack
		stx BrkData+MonBrk::RegX; And save them in BrkData
		tsx			; Retrieve the stack pointer
		inx			; Fix the retrieved stack pointer
		inx			;
		phy			;
		sty BrkData+MonBrk::RegY;
		pha			;
		sta BrkData+MonBrk::RegA;

StackData:	lda $0100,x		; Load SR from the stack
		sta BrkData+MonBrk::SR	; Save it in BrkData
		inx			;
		lda $0100,x		; Load PCL from the stack
		sec
		sbc #$01
		sta BrkData+MonBrk::PC+1; Save it in BrkData (Big-endian)
		sta L			; Save it as a pointer!Temp, needs cleanup
		inx			;
		lda $0100,x		; Load PCH from the stack
		sbc #$00
		sta BrkData+MonBrk::PC	; Save it in BrkData
		sta H			; Save it as a pointer!
		dec BrkData+MonBrk::PC+1
		bcs :+
		dec BrkData+MonBrk::PC
:		txa			;
		sta BrkData+MonBrk::SP	; Save pre-brk stack pointer

		lda (L)			; Load the break signature
		sta BrkData+MonBrk::Sig	; Save it in BrkData

SRBits:		ldx #$07		; Convert the status register bits to
		lda #%00000001		;  readable letters
@SRLoop:	bit BrkData+MonBrk::SR	; Check if the current bit is set
		pha			; Push current bit mask for next loop
		beq @BitClear		; 
@BitSet:	lda SR_tbl,x		; Bit is set - upper-case letter
		sta BrkData+MonBrk::SRBits,x	; Get the letter for this bit
		dex			; Was that the last bit?
		bmi PrintLine		; Yes, continue to next section.
		pla			; No, pull the bit mask
		asl			; Shift it left
		bra @SRLoop		; Loop
@BitClear:	lda SR_tbl,x		; Bit is clear - get the letter
		ora #$20		; Convert it to lower-case
		sta BrkData+MonBrk::SRBits,x	; Store it in BrkData
		dex			; Was that the last bit?
		bmi PrintLine		; Yes, continue to next section.
		pla			; No, pull the bit mask
		asl			; Shift it left
		bra @SRLoop		; Loop

PrintLine:	pla			; Fix the stack after SRBits
		jsr print_nl		;
		ldx #$00		; String index
		ldy #MonBrk::Sig	; Data index
@PrintLoop:	lda BrkString,x		; Get a string byte
		beq Done		; If the byte is $00, next section
		bpl @StringByte		; If the byte is <$80, print it
		cmp #$BF		;
		beq @CharByte		; If byte is $BF, print data as char
@HexByte:	lda BrkData,y		; Print a hexadecimal data byte
		jsr print_byte		; Print it
		inx			; Increment the string index
		iny			; Increment the data index
		bra @PrintLoop		; Next byte
@CharByte:	lda BrkData,y		; Print a character data byte
		jsr print_char		; Print it
		inx			; Increment the string index
		iny			; Increment the data index
		bra @PrintLoop		; Next byte
@StringByte:	jsr print_char		; Print the current string byte
		inx			; Increment the string index
		bra @PrintLoop		; Next byte

		jsr print_nl		;

Done:		jmp wozmon::RESET	; Jump into WozMon
.endproc

.segment "DATA"
BrkData:	.tag MonBrk

.segment "RODATA"
;Status register bits
SR_tbl:		.byte "NV", $80, "BDIZC"

; BRK line - $FF bytes get a byte from the BRK struct, $BF gets a character
; BRK $$ - P:$$$$ S:$$ A:$$ X:$$ Y:$$ nvbdizc\CR\LF
BrkString:
.byte "BRK ", $FF, " - "
.byte "PC:", $FF, $FF, " "
.byte "SP:", $FF, " "
.byte "A:", $FF, " "
.byte "X:", $FF, " "
.byte "Y:", $FF, " "
.byte $BF, $BF, $BF, $BF, $BF, $BF, $BF
.byte $00

