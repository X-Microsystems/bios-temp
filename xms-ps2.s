;==============================================================================
; xms_ps2.s
; PS/2 keyboard driver for XMICRO-SERIAL
;==============================================================================
; All bytes received from the keyboard are processed by the interrupt service
; routine, ps2_isr. Raw scancodes from key presses are converted to more usable
; keycodes and placed in a keycode buffer.
;
; Keycodes retrieved from the buffer using kb_get. kb_get keeps track of
; locks and modifier keys, and can optionally return ASCII characters for
; visible-character keys. For other keys, or if ASCII is not requested,
; make/break keycodes are returned.
;
; Commands are sent to the keyboard using ps2_command, which queues command
; bytes and initiates the send. The ISR continues sending the next command
; byte each time the keyboard acknowledges the previous one, until the buffer
; is depleted.
;==============================================================================
; Additional Notes:
; 1. The ph_PS2_Data hook is called when the ISR adds new data to the keycode
;    buffer.
; 2. The ph_PS2_Pabr hook is called when the Pause/Break key is pressed. The
;    default behavior is to add a Pause/Break keycode to the keycode buffer.
; 3. Hooks are expected to end with an RTS instruction.
; 4. Ctrl-Pause performs a soft-reset by jumping to the system reset vector.
;==============================================================================

;!Add routine to convert control characters to ascii after ps2_get returns them
;!Add error handler - load error code before returning
;  At some point a system-wide error logger can be added to this exit routine.

_PS2_NOIMPORTS_ = 1
.include "xms-ps2.inc"
.include "xms-uart.inc"

.constructor ps2_init					; Startup routine
.interruptor ps2_isr					; Interrupt routine
.export	kb_get, ps2_command				; Procedures
.export	KB_Locks, KB_Mods				; Variables
.export ph_PS2_Data, ph_PS2_Pabr			; Hooks
.export Sym_Normal_tbl, Sym_Shift_tbl, Pad_Numlock_tbl	; Lookup tables

; Configuration Constants
RETRY_LIMIT	= 2			; Command retries before error
KEY_BUFF_SIZE	= 10			; Maximum buffered keycodes
CMD_BUFF_SIZE	= 10			; Maximum buffered command bytes

;PS2_Flags bits
FLAG_RSND	= %10000000		; Resend flag - driver waiting for byte
FLAG_PABR	= %01000000		; Pause flag - PA/BR sequence in prog.
FLAG_EXT	= %00100000		; Extended-code flag
FLAG_BRK	= %00010000		; Break-code flag

; Variables
.segment "DATA"
PS2_Flags:	.res 1			; Flag bits for keyboard state
PS2_Scan_Idx:	.res 1			; Scancode index (PA/BR scancode)
PS2_Keybuff:	.res KEY_BUFF_SIZE	; Keycode buffer (FIFO)
PS2_Key_Idx:	.res 1			; Keycode buffer index - next position
PS2_Cmdbuff:	.res CMD_BUFF_SIZE	; Command buffer (FIFO)
PS2_Cmd_Idx:	.res 1			; Command buffer index - next position
PS2_Retry:	.res 1			; Command error-retry counter

KB_Locks:	.res 1			; Keyboard Lock toggle flags
KB_Mods:	.res 1			; Keyboard modifier key flags
KB_Add:		.res 1			; Temp keycode conversion arithmetic

; Hooks
; All hooks are expected to return with an RTS.
ph_PS2_Pabr:	.res 2			; Pause/Break key hook
ph_PS2_Data:	.res 2			; New-data hook

.segment "ONCE"
;==============================================================================
; ps2_init - Initialize the PS/2 hardware and driver
; Clobbers .AY
;==============================================================================
.proc ps2_init
		lda #<ps2_isr		; Set ISR hook
		sta ph_PS2_ISR		;
		lda #>ps2_isr		;
		sta ph_PS2_ISR+1	;
		lda #<::ps2_isr::StorePabr	; Set Pause/Break key hook
		sta ph_PS2_Pabr			; (Return keycode by default)
		lda #>::ps2_isr::StorePabr	;
		sta ph_PS2_Pabr+1		;
		lda #<Return		; Set new-data hook
		sta ph_PS2_Data		; (Just returns by default)
		lda #>Return		;
		sta ph_PS2_Data+1	;

		stz PS2_Scan_Idx	; Initialize PS/2 protocol
		stz PS2_Key_Idx		;
		stz PS2_Cmd_Idx		;
		stz PS2_Flags		;
		lda #RETRY_LIMIT	;
		sta PS2_Retry		;
		stz KB_Mods		; Initialize keyboard handling
		lda #KB_LOCK_NUM	; Set Num Lock
		sta KB_Locks		;
		lda PS2_DATA		; Clear data register

		ldy #$00		; Send initialization commands to
@InitCmds:	lda PS2_Init_tbl,y	;  keyboard
		sta PS2_Cmdbuff,y	;
		iny			;
		cpy #$06		;
		bne @InitCmds		;
		sty PS2_Cmd_Idx		;
		jsr ps2_send		;

		lda #UART_MCR_OP1	; Enable PS/2 interrupts
		ora UART1+UART_MCR	;
		sta UART1+UART_MCR 	;

Return:		rts			;
.endproc

.segment "CODE"
;==============================================================================
; kb_get - Get the next key from the buffer
; If Carry is clear when called, returns make/break keycodes for all keys.
; If Carry is set, returns make/break keycodes for non-character keys, and
;  make-only ASCII codes for character keys
;
; Inputs
;  C Flag	Set to return ASCII for character keys
;
; Outputs
;  .A		Keycode or ASCII character
;  Z flag	Set if no key was returned
;  C flag	Set if an ASCII character was returned
;
; Clobbers .A
;==============================================================================
.proc kb_get
		lda PS2_Key_Idx		; Is there is a keycode in the buffer?
		bne @GetCode		; Yes, get the next keycode
		clc			;
		rts			; No, return (Z=0)
@GetCode:	phx			;
		phy			;
		php			; Save the Carry flag for later
		sei			; SEI to prevent buffer corruption
		ldy PS2_Keybuff		; Load the keycode
		ldx #$00		;
@ShiftBuffer:	lda PS2_Keybuff+1,X	; Shift the buffer contents to the next keycode
		sta PS2_Keybuff,X	;
		inx			;
		cpx PS2_Key_Idx		;
		bne @ShiftBuffer	;
		dec PS2_Key_Idx		;
		cli			; Enable interrupts
		plp			; Retrieve the original Carry flag
		tya			; Load the keycode in the accumulator
		and #$7F		; Ignore the break bit for class checks
		bcc @CheckCon		; Skip ASCII checks if Carry was set
@CheckAscii:	cmp #KeyClass::Sym	; Alpha class (Make-only)?
		bcc ClassAlp		;
		cmp #KeyClass::Pad	; Symbol class (Make-only)?
		bcc ClassSym		;
		cmp #KeyClass::Con	; Numpad class (Make/Break)?
		bcc ClassPad		;
@CheckCon:	cmp #KeyClass::Mod	; Control class (Make/Break)?
		bcc ClassCon		;
		cmp #KB_RWIN+1		; Modifier class (Make/Break)?
		bcc ClassMod		;
		jmp ReturnNone		; Discard any other bytes

;------------------------------------------------------------------------------
; Alpha class keycode - Letters (Modified by Caps Lock/Shift).
; Convert to ASCII letter. Case is set the state of Shift/Caps Lock.
;------------------------------------------------------------------------------
ClassAlp:	cpy #$00		; Is the break bit set?
		bpl :+			;
		jmp ReturnNone		; Yes, discard the break code
:		stz KB_Add		; No, clear the addend
		lda KB_Mods		; Load the modifier flags
		and #KB_MOD_SHIFT	; Isolate the Shift bits
		bne :+			; Is the shift flag set?
		lda #$20		; No, add $20 to the addend (lowercase)
		sta KB_Add		;
:		lda #$40		; Add $40 to the addend (ASCII letter)
		ora KB_Add		;
		sta KB_Add		; Store the addend
		lda KB_Locks		; Is Caps Lock active?
		bit #KB_LOCK_CAPS	;
		beq @ConvertAscii	; No, don't change case
		lda #$20		; Yes, toggle the case on the addend
		eor KB_Add		;
		sta KB_Add		;
@ConvertAscii:	tya			; Get the keycode into the accumulator
		clc			;
		adc KB_Add		; Convert it to case-adjusted ASCII
		bra ReturnAscii		; Return ASCII

;------------------------------------------------------------------------------
; Symbol class keycode - Symbols/digits (Modified by Shift).
; Convert to ASCII character. Character depends on the state of Shift.
;------------------------------------------------------------------------------
ClassSym:	cpy #$00		; Is the break bit set?
		bmi ReturnNone		; Yes, discard the break code
		lda KB_Mods		; No, load the modifier flags
		and #KB_MOD_SHIFT	; Isolate the Shift bits
		bne :+			; Is the shift flag set?
		lda Sym_Normal_tbl,y	; No, look up unshifted character
		bra ReturnAscii		; Return ASCII
:		lda Sym_Shift_tbl,y	; Yes, look up shifted character
		bra ReturnAscii		; Return ASCII

;------------------------------------------------------------------------------
; Numpad class keycode - Numpad keys (Modified by Num Lock)
; If Num Lock is set, Convert to ASCII character. If not, return a keycode.
;------------------------------------------------------------------------------
ClassPad:	lda KB_Locks		; Load the lock flags
		bit #KB_LOCK_NUM	; Is the Num Lock flag set?
		beq ReturnKey		; No, return the keycode
		cpy #$00		; Yes. Is the break bit set?
		bmi ReturnNone		; Yes, discard the break code
		lda Pad_Numlock_tbl,y	; No, return an ASCII character
		bra ReturnAscii		; Return ASCII

;------------------------------------------------------------------------------
; Control class keycode - Control-type keys (not CTRL) and static characters
; Return a keycode. If it's a lock key, toggle the associated lock.
; *When ps2_get is called with carry clear, all previous classes are treated
; as control class to return keycodes instead of ASCII.
;------------------------------------------------------------------------------
ClassCon:	cpy #KB_CAPS		; Is it Caps Lock (make)?
		bne :+			;
		lda #KB_LOCK_CAPS	; Yes, toggle Caps Lock
		jsr kb_lock_toggle	;
:		cpy #KB_NUMLOC		; Is it Num Lock (make)?
		bne :+			;
		lda #KB_LOCK_NUM	; Yes, toggle Num Lock
		jsr kb_lock_toggle	;
:		cpy #KB_SCRL		; Is it Scroll Lock (make)?
		bne ReturnKey		;
		lda #KB_LOCK_SCR	; Yes, toggle Scroll Lock
		jsr kb_lock_toggle	;
		bra ReturnKey		;

;------------------------------------------------------------------------------
; Mofidier class keycode - Modifier keys (Shift, Ctrl, Alt, Win)
; Sets keyboard modifier flag and returns a keycode
;------------------------------------------------------------------------------
ClassMod:	sec			;
		sbc #KeyClass::Mod-1	; Get the modifier index
		tax			; Place it in .X for the loop
		lda #%10000000		; Load bit 7
:		dex			;
		beq @SetFlag		;
		lsr			; Shift it right to make a bit mask
		bra :-			;  for KB_Mods
@SetFlag:	cpy #$00		;
		bmi @Break		; Is the break bit set?
		tsb KB_Mods		; No, set the modifier flag
		bra ReturnKey		; Return keycode
@Break:		trb KB_Mods		; Yes, clear the modifier flag

;------------------------------------------------------------------------------
; Returns - standard returns for ASCII, keycodes, or null
;------------------------------------------------------------------------------
ReturnKey:	tya			; Retrieve the keycode
		ply			;
		plx			;
		clc			; Clear carry to indicate no character
		adc #$00		; Set the Z/N flags for the byte
		rts			; Return keycode

ReturnNone:	ply			;
		plx			;
		lda #$00		; Clear .A and set Z
		clc			; Clear carry to indicate no character
		rts			; Return empty

ReturnAscii:	ply			;
		plx			;
		sec			; Set carry to indicate ASCII
		sbc #$00		; Set the Z flag for the byte
		rts			; Return with an ASCII character
.endproc

;==============================================================================
; ps2_command - Add a command or data byte to the queue
;
; Inputs
;  .A		Command/data byte
;
; Outputs
;  C Flag	Set if buffer is full
;
; Clobbers .AY
;==============================================================================
.proc ps2_command
		ldy PS2_Cmd_Idx		; Check if buffer will overflow
		cpy #CMD_BUFF_SIZE+1	;
		bcc AddCmd		; Buffer is good, add the command
		rts			; Buffer overflow error, Return. !Should dump command buffer if it overflows? If the keyboard doesn't ACK a byte, the commands will not continue and it will overflow.
AddCmd:		sei			; Disable interrupts to prevent buffer
		ldy PS2_Cmd_Idx		;  corruption
		sta PS2_Cmdbuff,y	; Store the byte in the command buffer
		iny			;
		sty PS2_Cmd_Idx		;
		cpy #$02		; Last command in the queue?
		bcs Return		; No, waiting for an ACK. Return
		jsr ps2_send		; Yes, send it.
		lda #RETRY_LIMIT	; Reset the retry limit
		sta PS2_Retry		;
Return:		cli			; Enable interrupts
		clc			; Clear carry flag to indicate success
		rts			;
.endproc

;==============================================================================
; ps2_send - Send the next byte in the command queue and reset the flags
; *Does not shift the queue
; Clobbers .A
;==============================================================================
.proc ps2_send
		lda #XMS_SR_PWS		;
		bit XMS_SR		; Is another byte currently being sent?
		bne ps2_send		; Yes, wait until it's ready to send.
		lda PS2_Cmdbuff		; No, send the next byte.
		sta PS2_DATA		;
		stz PS2_Flags		; Reset the flags
		rts			;
.endproc

;==============================================================================
; kb_lock_toggle - Toggle a lock flag and update the keyboard status LEDs
;
; Inputs 	.A		Lock flag bit to invert
; Outputs	KB_Locks
;
; Clobbers .A
;==============================================================================
.proc kb_lock_toggle
		phy			;
		pha			; Save the bit mask
		lda #PS2_CMD_LED	; Set LED command
		jsr ps2_command		; Send it to the PS/2 port
		pla			; Retrieve the bit mask
		eor KB_Locks		; Invert the bits
		sta KB_Locks		; Store it
		jsr ps2_command		; Send it to the PS/2 port
		ply			;
		rts			;
.endproc

;==============================================================================
; ps2_isr - Interrupt service routine for the PS/2 port
; Receives a byte from the keyboard and processes it based on value and current
; state. Key presses add a keycode to the keycode FIFO buffer. Command bytes in
; the command FIFO buffer are automatically sent when a Command Acknowledge or
; Resend Request byte is received.
;==============================================================================
.proc ps2_isr
		lda #XMS_SR_PER		; PS/2 interrupt received
		bit XMS_SR		; Is there a parity error?
		beq @ReadByte		; No, continue.
		jmp ParityError		; Yes, handle the error.

@ReadByte:	lda #FLAG_RSND		; Byte is clean, reset the resend flag
		trb PS2_Flags		;
		ldy PS2_DATA		; Load the new byte from the keyboard
		cpy #PS2_RB_RSND	; Is it a resend request?
		bne :+			;
		jmp CmdResend		; Yes, resend the last command.
:		bit PS2_Flags		; Is the PABR flag set?
		bvc GoodByte		;
		jmp FinishPabr		; Yes, count down the remaining bytes

;------------------------------------------------------------------------------
; GoodByte - Byte is good. Determine what to do based on its value
;------------------------------------------------------------------------------
GoodByte:	cpy #$85		; Below $85? (not a special byte)
		bcc KeyLookup		;
		cpy #PS2_RB_ESC		; Start of an extended scancode?
		bne :+			;
		bra SetExt		;
:		cpy #PS2_RB_BSC		; Start of a key-break code?
		bne :+			;
		bra SetBrk		;
:		cpy #PS2_RB_PSC		; Start of a pause/break scancode?
		bne :+			;
		jmp SetPabr		;
:		cpy #PS2_RB_ACK		; Command acknowledged?
		bne :+			;
		bra CmdAck		;
:		cpy #PS2_RB_ECHO	; Echo response?
		bne :+			;
		bra CmdAck		;
:		cpy #PS2_RB_STP		; Keyboard reset passed?
		bne :+			;
		jmp ResetPass		;
:		cpy #PS2_RB_ERR1	; Keyboard reset failed?!Need error handler
		bne :+			;
:		cpy #PS2_RB_ERR2	; Keyboard reset failed?
		bne :+			;
:		rts			; Ignore other special bytes

;------------------------------------------------------------------------------
; KeyLookup - Scancode byte received, process it.
;------------------------------------------------------------------------------
KeyLookup:	lda #FLAG_EXT		;
		bit PS2_Flags		; Is it an extended scancode?
		bne @ExtCode		; Yes, use the extended lookup table
		ldx PS2_Normal_tbl,y	; No, use the normal lookup table
		bra CheckNull		;
@ExtCode:	ldx PS2_Ext_tbl,y	;
CheckNull:	beq @Return		; If keycode is $00, ignore and return
		cpx #KB_CPABR		; Is it a Ctrl-Pause/Break? 
		bne :+			; No, continue.
		jmp ($FFFC)		; Yes, soft-reboot
:		ldy PS2_Key_Idx		;
		cpy #KEY_BUFF_SIZE+1	; Is the buffer going to overflow?
		bcs @Overflow		; Yes, error. Receive buffer overflow
		lda #FLAG_BRK		; No, buffer is good.
		bit PS2_Flags		; Is it a break code?
		bne @BrkCode		; Yes, set the break bit
		txa			; No, it's a make code. Store as-is.
		bra @StoreCode		;
@BrkCode:	txa			; Change it to a break keycode
		ora #%10000000		;
@StoreCode:	sta PS2_Keybuff,y	; Store keycode in buffer
		iny			; Increment the keycode buffer index
		sty PS2_Key_Idx		;
@Return:	stz PS2_Flags		; 
		jmp (ph_PS2_Data)	; Jump to the new-data hook (will return from there)
@Overflow:	bra @Return		; Buffer overflow error - currently does nothing, just ignores the key.!

;------------------------------------------------------------------------------
; SetExt - Extended scancode received, set the EXT flag
;------------------------------------------------------------------------------
SetExt:		lda #FLAG_EXT		; Set the extended-code flag
		tsb PS2_Flags		;
		rts			;

;------------------------------------------------------------------------------
; SetBrk - Key-break code received, set the BRK flag
;------------------------------------------------------------------------------
SetBrk:		lda #FLAG_BRK		; Set the key-break flag
		tsb PS2_Flags		;
		rts			;

;------------------------------------------------------------------------------
; CmdAck - Command acknowledged
;------------------------------------------------------------------------------
CmdAck:		lda #RETRY_LIMIT	; 
		sta PS2_Retry		; Reset the retry counter
		lda PS2_Cmd_Idx		; Any more command bytes in the queue?
		beq @Return		; No, return.
		ldx #$00		; Yes, shift the buffer to next byte.
@ShiftBuffer:	lda PS2_Cmdbuff+1,X	; 
		sta PS2_Cmdbuff,X	;
		inx			;
		cpx PS2_Cmd_Idx		;
		bne @ShiftBuffer	;
		dec PS2_Cmd_Idx		;
		beq @Return		;
		jsr ps2_send		; Send the next byte
@Return:	rts			;

;------------------------------------------------------------------------------
; CmdResend - Keyboard has requested the last command byte be re-sent
;------------------------------------------------------------------------------
CmdResend:	ldx PS2_Retry		; Has the retry limit been reached?
		beq @CmdError		; Yes, error. Command failed.
		jsr ps2_send		; No, send the last byte again.
		dex			; Count another retry attempt
		stx PS2_Retry		;
		rts			;

@CmdError:	ldx #RETRY_LIMIT	; Error - Command failed.
		stx PS2_Retry		; Reset the retry limit
		stz PS2_Cmd_Idx		; Clear the command buffer
		rts			;

;------------------------------------------------------------------------------
; ResetPass - Keyboard has been reset and passed self-test
;------------------------------------------------------------------------------
ResetPass:	stz PS2_Scan_Idx	; Reset driver variables
		stz PS2_Key_Idx		;
		stz PS2_Cmd_Idx		;
		stz PS2_Flags		;
		lda #RETRY_LIMIT	;
		sta PS2_Retry		;
		lda #$00		;
		jsr kb_lock_toggle	; Set the LEDs
		lda #PS2_CMD_REP	; Set the typematic delay/rate
		jsr ps2_command		;
		lda #%00100000		;
		jsr ps2_command		;
		rts			;

;------------------------------------------------------------------------------
; SetPabr - Start of Pause/Break sequence
;------------------------------------------------------------------------------
SetPabr:	lda #FLAG_PABR		; Set the PA/BR flag
		tsb PS2_Flags		;
		lda #$07		; Set the scancode index to count
		sta PS2_Scan_Idx	;  remaining bytes in the PA/BR code
		jmp (ph_PS2_Pabr)	; Jump to the Pabr hook

StorePabr:				; Default hook - add keycode to buffer
		lda #KB_PABR		; Load Pause/Break keycode
		ldy PS2_Key_Idx		; Store Pause/Break keycode
		cpy #KEY_BUFF_SIZE+1	; Is the buffer going to overflow?
		bcs @Return		; Yes, error. Receive buffer overflow !Error handling TBD
		sta PS2_Keybuff,y	; Store keycode in buffer
		iny			; Increment the keycode buffer index
		sty PS2_Key_Idx		;
@Return:	jmp (ph_PS2_Data)	; Jump to the new-data hook (will return from there)

;------------------------------------------------------------------------------
; FinishPabr - Pause/Break sequence in progress. Ignore remaining bytes
;------------------------------------------------------------------------------
FinishPabr:	dec PS2_Scan_Idx	; Decrement the scancode index
		bne @Return		;
		stz PS2_Flags		; If it's zero, clear the PA/BR flag
@Return:	rts			;

;------------------------------------------------------------------------------
; ParityError - Parity error detected
;------------------------------------------------------------------------------
ParityError:	lda #PS2_RB_RSND	; Request a resend
		sta PS2_DATA		;
		lda PS2_DATA		; Clear the PS/2 read register
		lda #FLAG_RSND		; Set the resend flag
		tsb PS2_Flags		; Was it already set?
		bne @ResetRetry		; No, reset the retry counter.
		dec PS2_Retry		; Yes, decrement the retry counter.
		beq @ErrorLimit		; Branch if the retry limit was reached
		rts			; Otherwise return as usual
@ResetRetry:	lda #RETRY_LIMIT	; Reset the retry counter
		sta PS2_Retry		;
		rts			; Return

@ErrorLimit:	lda #PS2_CMD_RST	; Error - too many resend requests
		jsr ps2_command		; Send a reset command to the keyboard
		rts
.endproc

.segment "RODATA"
;==============================================================================
; Scancode lookup tables
; Maps the keyboard scancodes to keycodes used by the driver
;
; Keycodes are a one-byte code indicating which physical key was pressed
; Bit-7 indicates a key break
;==============================================================================
PS2_Normal_tbl:				; Convert normal scancodes to keycodes
		.byte	0		; 00
		.byte	KB_F9		; 01	F9
		.byte	0		; 02
		.byte	KB_F5		; 03	F5
		.byte	KB_F3		; 04	F3
		.byte	KB_F1		; 05	F1
		.byte	KB_F2		; 06	F2
		.byte	KB_F12		; 07	F12
		.byte	0		; 08
		.byte	KB_F10		; 09	F10
		.byte	KB_F8		; 0A	F8
		.byte	KB_F6		; 0B	F6
		.byte	KB_F4		; 0C	F4
		.byte	KB_TAB		; 0D	Tab
		.byte	KB_BTICK	; 0E	`
		.byte	0		; 0F

		.byte	0		; 10
		.byte	KB_LALT		; 11	Left Alt
		.byte	KB_LSHIFT	; 12	Left Shift
		.byte	0		; 13
		.byte	KB_LCTRL	; 14	Left Ctrl
		.byte	KB_Q		; 15	Q
		.byte	KB_1		; 16	1
		.byte	0		; 17
		.byte	0		; 18
		.byte	0		; 19
		.byte	KB_Z		; 1A	Z
		.byte	KB_S		; 1B	S
		.byte	KB_A		; 1C	A
		.byte	KB_W		; 1D	W
		.byte	KB_2		; 1E	2
		.byte	0		; 1F

		.byte	0		; 20
		.byte	KB_C		; 21	C
		.byte	KB_X		; 22	X
		.byte	KB_D		; 23	D
		.byte	KB_E		; 24	E
		.byte	KB_4		; 25	4
		.byte	KB_3		; 26	3
		.byte	0		; 27
		.byte	0		; 28
		.byte	KB_SPACE	; 29	Space
		.byte	KB_V		; 2A	V
		.byte	KB_F		; 2B	F
		.byte	KB_T		; 2C	T
		.byte	KB_R		; 2D	R
		.byte	KB_5		; 2E	5
		.byte	0		; 2F

		.byte	0		; 30
		.byte	KB_N		; 31	N
		.byte	KB_B		; 32	B
		.byte	KB_H		; 33	H
		.byte	KB_G		; 34	G
		.byte	KB_Y		; 35	Y
		.byte	KB_6		; 36	6
		.byte	0		; 37
		.byte	0		; 38
		.byte	0		; 39
		.byte	KB_M		; 3A	M
		.byte	KB_J		; 3B	J
		.byte	KB_U		; 3C	U
		.byte	KB_7		; 3D	7
		.byte	KB_8		; 3E	8
		.byte	0		; 3F

		.byte	0		; 40
		.byte	KB_COM		; 41	,
		.byte	KB_K		; 42	K
		.byte	KB_I		; 43	I
		.byte	KB_O		; 44	O
		.byte	KB_0		; 45	0
		.byte	KB_9		; 46	9
		.byte	0		; 47
		.byte	0		; 48
		.byte	KB_PER		; 49	.
		.byte	KB_FSL		; 4A	/
		.byte	KB_L		; 4B	L
		.byte	KB_SEMI		; 4C	;
		.byte	KB_P		; 4D	P
		.byte	KB_MI		; 4E	-
		.byte	0		; 4F

		.byte	0		; 50
		.byte	0		; 51
		.byte	KB_APOS		; 52	'
		.byte	0		; 53
		.byte	KB_LBR		; 54	[
		.byte	KB_EQ		; 55	=
		.byte	0		; 56
		.byte	0		; 57
		.byte	KB_CAPS		; 58	Caps Lock
		.byte	KB_RSHIFT	; 59	Right Shift
		.byte	KB_ENTER	; 5A	Enter
		.byte	KB_RBR		; 5B	]
		.byte	0		; 5C
		.byte	KB_BSL		; 5D	\
		.byte	0		; 5E
		.byte	0		; 5F

		.byte	0		; 60
		.byte	0		; 61
		.byte	0		; 62
		.byte	0		; 63
		.byte	0		; 64
		.byte	0		; 65
		.byte	KB_BSPACE	; 66	Backspace
		.byte	0		; 67
		.byte	0		; 68
		.byte	KB_NUM1		; 69	1 (Numpad)
		.byte	0		; 6A
		.byte	KB_NUM4		; 6B	4 (Numpad)
		.byte	KB_NUM7		; 6C	7 (Numpad)
		.byte	0		; 6D
		.byte	0		; 6E
		.byte	0		; 6F

		.byte	KB_NUM0		; 70	0 (Numpad)
		.byte	KB_NUMPER	; 71	. (Numpad)
		.byte	KB_NUM2		; 72	2 (Numpad)
		.byte	KB_NUM5		; 73	5 (Numpad)
		.byte	KB_NUM6		; 74	6 (Numpad)
		.byte	KB_NUM8		; 75	8 (Numpad)
		.byte	KB_ESC		; 76	Escape
		.byte	KB_NUMLOC	; 77	Num Lock
		.byte	KB_F11		; 78	F11
		.byte	KB_NUMPL	; 79	+ (Numpad)
		.byte	KB_NUM3		; 7A	3 (Numpad)
		.byte	KB_NUMMI	; 7B	- (Numpad)
		.byte	KB_NUMAS	; 7C	* (Numpad)
		.byte	KB_NUM9		; 7D	9 (Numpad)
		.byte	KB_SCRL		; 7E	Scroll Lock
		.byte	0		; 7F

		.byte	0		; 80	Error
		.byte	0		; 81
		.byte	0		; 82
		.byte	KB_F7		; 83	F7
		.byte	KB_PRINT	; 84	Alt-Print Screen

					; Convert extended scancodes to keycodes
PS2_Ext_tbl	:= *-$11		; Unused bytes excluded to save space
		.byte	KB_RALT		; 11	Right Alt
		.byte	0		; 12	Non-key extra code for LShift
		.byte	0		; 13
		.byte	KB_RCTRL	; 14	Right Control
		.byte	0		; 15
		.byte	0		; 16
		.byte	0		; 17
		.byte	0		; 18
		.byte	0		; 19
		.byte	0		; 1A
		.byte	0		; 1B
		.byte	0		; 1C
		.byte	0		; 1D
		.byte	0		; 1E
		.byte	KB_LWIN		; 1F	Left Win

		.byte	0		; 20
		.byte	0		; 21
		.byte	0		; 22
		.byte	0		; 23
		.byte	0		; 24
		.byte	0		; 25
		.byte	0		; 26
		.byte	KB_RWIN		; 27	Right Win

; Initialization command table - nested within PS2_Ext_tbl to save space
PS2_Init_tbl:	.byte PS2_CMD_SCS	; 28	; Scan code set 2
		.byte $02		; 29	;
		.byte PS2_CMD_REP	; 2A	; Typematic, 500ms/30Hz
		.byte %00100000		; 2B	;
		.byte PS2_CMD_LED	; 2C	; Turn on Num Lock LED
		.byte %00000010		; 2D	;
					; End of PS2_Init_tbl
					
		.byte	0		; 2E
		.byte	KB_MENU		; 2F	Menu

; Keycode to ASCII conversion table - nested within PS2_Ext_tbl to save space
Sym_Normal_tbl	:= *-KeyClass::Sym	; Symbols/digits (Unshifted)
		.byte	" "		; 30	; 1B	; Space
		.byte	"`"		; 31	; 1C	; `
		.byte	"0"		; 32	; 1D	; 0
		.byte	"1"		; 33	; 1E	; 1
		.byte	"2"		; 34	; 1F	; 2
		.byte	"3"		; 35	; 20	; 3
		.byte	"4"		; 36	; 21	; 4
		.byte	"5"		; 37	; 22	; 5
		.byte	"6"		; 38	; 23	; 6
		.byte	"7"		; 39	; 24	; 7
		.byte	"8"		; 3A	; 25	; 8
		.byte	"9"		; 3B	; 26	; 9
		.byte	"-"		; 3C	; 27	; -
		.byte	"="		; 3D	; 28	; =
		.byte	"["		; 3E	; 29	; [
		.byte	"]"		; 3F	; 2A	; ]
		.byte	$5C		; 40	; 2B	; \
		.byte	";"		; 41	; 2C	; ;
		.byte	"'"		; 42	; 2D	; '
		.byte	","		; 43	; 2E	; ,
		.byte	"."		; 44	; 2F	; .
		.byte	"/"		; 45	; 30	; /
		.byte	"/"		; 46	; 31	; / (Numpad)
		.byte	"*"		; 47	; 32	; * (Numpad)
		.byte	"-"		; 48	; 33	; - (Numpad)
		.byte	"+"		; 49	; 34	; + (Numpad)
					; End of Sym_Normal_tbl

		.byte	KB_NUMFS	; 4A	/ (Numpad)

; Keycode to ASCII conversion table - nested within PS2_Ext_tbl to save space
Pad_Numlock_tbl	:= *-KeyClass::Pad	; Numpad (Numlock on)
		.byte	"0"		; 4B	; 35	; 0 (Numpad)
		.byte	"1"		; 4C	; 36	; 1 (Numpad)
		.byte	"2"		; 4D	; 37	; 2 (Numpad)
		.byte	"3"		; 4E	; 38	; 3 (Numpad)
		.byte	"4"		; 4F	; 39	; 4 (Numpad)
		.byte	"5"		; 50	; 3A	; 5 (Numpad)
		.byte	"6"		; 51	; 3B	; 6 (Numpad)
		.byte	"7"		; 52	; 3C	; 7 (Numpad)
		.byte	"8"		; 53	; 3D	; 8 (Numpad)
		.byte	"9"		; 54	; 3E	; 9 (Numpad)
		.byte	"."		; 55	; 3F	; . (Numpad)
					; End of Sym_Normal_tbl

		.byte	0		; 56	
		.byte	0		; 57
		.byte	0		; 58
		.byte	0		; 59	Non-key extra code for RShift
		.byte	KB_NUMENT	; 5A	Enter (Numpad)
		.byte	0		; 5B
		.byte	0		; 5C
		.byte	0		; 5D
		.byte	0		; 5E
		.byte	0		; 5F

		.byte	0		; 60
		.byte	0		; 61
		.byte	0		; 62
		.byte	0		; 63
		.byte	0		; 64
		.byte	0		; 65
		.byte	0		; 66
		.byte	0		; 67
		.byte	0		; 68
		.byte	KB_END		; 69	End (Numpad)
		.byte	0		; 6A
		.byte	KB_LEFT		; 6B	Left Arrow
		.byte	KB_HOME		; 6C	Home
		.byte	0		; 6D
		.byte	0		; 6E
		.byte	0		; 6F

		.byte	KB_INS		; 70	Insert
		.byte	KB_DEL		; 71	Delete
		.byte	KB_DOWN		; 72	Down Arrow
		.byte	0		; 73
		.byte	KB_RIGHT	; 74	Right Arrow
		.byte	KB_UP		; 75	Up Arrow
		.byte	0		; 76
		.byte	0		; 77
		.byte	0		; 78
		.byte	0		; 79
		.byte	KB_PGDN		; 7A	Page Down
		.byte	0		; 7B
		.byte	KB_PRINT	; 7C	Print Screen
		.byte	KB_PGUP		; 7D	Page Up
		.byte	KB_CPABR	; 7E	Ctrl-Pause/Break
					; End of PS2_Ext_tbl

;==============================================================================
; Keycode to ASCII Conversion Tables
; Table labels are offset to use keycodes directly as an index.
;==============================================================================
Sym_Shift_tbl	:= *-KeyClass::Sym	; Symbols/digits (Shifted)
		.byte	" "		; 1B	; Space
		.byte	"~"		; 1C	; `
		.byte	")"		; 1D	; 0
		.byte	"!"		; 1E	; 1
		.byte	"@"		; 1F	; 2
		.byte	"#"		; 20	; 3
		.byte	"$"		; 21	; 4
		.byte	"%"		; 22	; 5
		.byte	"^"		; 23	; 6
		.byte	"&"		; 24	; 7
		.byte	"*"		; 25	; 8
		.byte	"("		; 26	; 9
		.byte	"_"		; 27	; -
		.byte	"+"		; 28	; =
		.byte	"{"		; 29	; [
		.byte	"}"		; 2A	; ]
		.byte	"|"		; 2B	; \
		.byte	":"		; 2C	; ;
		.byte	$22		; 2D	; '
		.byte	"<"		; 2E	; ,
		.byte	">"		; 2F	; .
		.byte	"?"		; 30	; /
		.byte	"/"		; 31	; / (Numpad)
		.byte	"*"		; 32	; * (Numpad)
		.byte	"-"		; 33	; - (Numpad)
		.byte	"+"		; 34	; + (Numpad)





