;==============================================================================
; xms-ps2.inc
; Dependencies: xms.inc
;==============================================================================

.ifndef _PS2_INC_			; Don't allow multiple includes
_PS2_INC_ = 1

.ifndef _PS2_NOIMPORTS_			; Skip imports

.import ps2_init					; Startup routine
.import ps2_isr						; Interrupt routine
.import	kb_get, ps2_command				; Procedures
.import	KB_Locks, KB_Mods				; Variables
.import ph_PS2_Data, ph_PS2_Pabr			; Hooks
.import Sym_Normal_tbl, Sym_Shift_tbl, Pad_Numlock_tbl	; Lookup tables

.endif

.include "xms.inc"

;==============================================================================
; PS/2 Protocol Driver
;==============================================================================
; Command Bytes
PS2_CMD_LED		= $ED		; Set LEDs
PS2_CMD_ECHO		= $EE		; Echo
PS2_CMD_SCS		= $F0		; Get/set scan code set
PS2_CMD_ID		= $F2		; Identify keyboard
PS2_CMD_REP		= $F3		; Set key repeat rate and delay
PS2_CMD_SE		= $F4		; Enable scanning (send scan codes)
PS2_CMD_SD		= $F5		; Disable scanning (no scan codes)
PS2_CMD_DFL		= $F6		; Set default parameters
PS2_CMD_AKR		= $F7		; Set all keys repeat (SCS 3)
PS2_CMD_AKMB		= $F8		; Set all keys make/break (SCS 3)
PS2_CMD_AKM		= $F9		; Set all keys make (SCS 3)
PS2_CMD_AKMBR		= $FA		; Set all keys make/break/repeat (SCS 3)
PS2_CMD_SKR		= $FB		; Set key repeat (SCS 3)
PS2_CMD_SKMB		= $FC		; Set key make/break (SCS 3)
PS2_CMD_SKM		= $FD		; Set key make (SCS 3)
PS2_CMD_RSND		= $FE		; Resend last byte
PS2_CMD_RST		= $FF		; Reset and self-test

; Special Receive Bytes
PS2_RB_ERR1		= $00		; Key detection error or buffer overrun
PS2_RB_STP		= $AA		; Self-test passed
PS2_RB_ESC		= $E0		; Start of a extended scan code
PS2_RB_PSC		= $E1		; Start of a pause/break scan code
PS2_RB_ECHO		= $EE		; Response to Echo command
PS2_RB_BSC		= $F0		; Start of a key-break scan code
PS2_RB_ACK		= $FA		; Command acknowledged
PS2_RB_STF1		= $FC		; Self-test failed
PS2_RB_STF2		= $FD		; Self-test failed
PS2_RB_RSND		= $FE		; Resend request
PS2_RB_ERR2		= $FF		; Key detection error or buffer overrun

; PS/2 Driver Fault Codes
.enum PS2Flt
	NONE	= $00			; No error
	UERR	= $01			; Unknown error
	RBOF	= $02			; Receive buffer overflow
	CBOF	= $03			; Command buffer overflow
	RLSC	= $04			; Retry limit - Send command
.endenum

;==============================================================================
; Keyboard Driver
;==============================================================================
; Keycodes - Scancodes from the keyboard are converted to keycodes which are
; easier to process.
;
; Bit 7 of the keycode indicates a key break when set
;==============================================================================
KB_NULL			= $00	; Null	; No key associated
KB_A			= $01	; Alp	; A
KB_B			= $02	; Alp	; B
KB_C			= $03	; Alp	; C
KB_D			= $04	; Alp	; D
KB_E			= $05	; Alp	; E
KB_F			= $06	; Alp	; F
KB_G			= $07	; Alp	; G
KB_H			= $08	; Alp	; H
KB_I			= $09	; Alp	; I
KB_J			= $0A	; Alp	; J
KB_K			= $0B	; Alp	; K
KB_L			= $0C	; Alp	; L
KB_M			= $0D	; Alp	; M
KB_N			= $0E	; Alp	; N
KB_O			= $0F	; Alp	; O

KB_P			= $10	; Alp	; P
KB_Q			= $11	; Alp	; Q
KB_R			= $12	; Alp	; R
KB_S			= $13	; Alp	; S
KB_T			= $14	; Alp	; T
KB_U			= $15	; Alp	; U
KB_V			= $16	; Alp	; V
KB_W			= $17	; Alp	; W
KB_X			= $18	; Alp	; X
KB_Y			= $19	; Alp	; Y
KB_Z			= $1A	; Alp	; Z
KB_SPACE		= $1B	; Sym	; Space
KB_BTICK		= $1C	; Sym	; `
KB_0			= $1D	; Sym	; 0
KB_1			= $1E	; Sym	; 1
KB_2			= $1F	; Sym	; 2

KB_3			= $20	; Sym	; 3
KB_4			= $21	; Sym	; 4
KB_5			= $22	; Sym	; 5
KB_6			= $23	; Sym	; 6
KB_7			= $24	; Sym	; 7
KB_8			= $25	; Sym	; 8
KB_9			= $26	; Sym	; 9
KB_MI			= $27	; Sym	; -
KB_EQ			= $28	; Sym	; =
KB_LBR			= $29	; Sym	; [
KB_RBR			= $2A	; Sym	; ]
KB_BSL			= $2B	; Sym	; \
KB_SEMI			= $2C	; Sym	; ;
KB_APOS			= $2D	; Sym	; '
KB_COM			= $2E	; Sym	; ,
KB_PER			= $2F	; Sym	; .

KB_FSL			= $30	; Sym	; /
KB_NUMFS		= $31	; Sym	; / (Numpad)
KB_NUMAS		= $32	; Sym	; * (Numpad)
KB_NUMMI		= $33	; Sym	; - (Numpad)
KB_NUMPL		= $34	; Sym	; + (Numpad)
KB_NUM0			= $35	; Pad	; 0 (Numpad)
KB_NUM1			= $36	; Pad	; 1 (Numpad)
KB_NUM2			= $37	; Pad	; 2 (Numpad)
KB_NUM3			= $38	; Pad	; 3 (Numpad)
KB_NUM4			= $39	; Pad	; 4 (Numpad)
KB_NUM5			= $3A	; Pad	; 5 (Numpad)
KB_NUM6			= $3B	; Pad	; 6 (Numpad)
KB_NUM7			= $3C	; Pad	; 7 (Numpad)
KB_NUM8			= $3D	; Pad	; 8 (Numpad)
KB_NUM9			= $3E	; Pad	; 9 (Numpad)
KB_NUMPER		= $3F	; Pad	; . (Numpad)

KB_ESC			= $40	; Con	; Escape
KB_F1			= $41	; Con	; F1
KB_F2			= $42	; Con	; F2
KB_F3			= $43	; Con	; F3
KB_F4			= $44	; Con	; F4
KB_F5			= $45	; Con	; F5
KB_F6			= $46	; Con	; F6
KB_F7			= $47	; Con	; F7
KB_F8			= $48	; Con	; F8
KB_F9			= $49	; Con	; F9
KB_F10			= $4A	; Con	; F10
KB_F11			= $4B	; Con	; F11
KB_F12			= $4C	; Con	; F12
KB_PRINT		= $4D	; Con	; Print Screen
KB_SCRL			= $4E	; Con	; Scroll Lock
KB_PABR			= $4F	; Con	; Pause/Break

KB_CPABR		= $50	; Con	; Ctrl-Pause/Break
KB_BSPACE		= $51	; Con	; Backspace
KB_ENTER		= $52	; Con	; Enter
KB_TAB			= $53	; Con	; Tab
KB_CAPS			= $54	; Con	; Caps Lock
KB_MENU			= $55	; Con	; Menu
KB_INS			= $56	; Con	; Insert
KB_DEL			= $57	; Con	; Delete
KB_HOME			= $58	; Con	; Home
KB_END			= $59	; Con	; End
KB_PGUP			= $5A	; Con	; Page Up
KB_PGDN			= $5B	; Con	; Page Down
KB_UP			= $5C	; Con	; Up Arrow
KB_DOWN			= $5D	; Con	; Down Arrow
KB_LEFT			= $5E	; Con	; Left Arrow
KB_RIGHT		= $5F	; Con	; Right Arrow

KB_NUMLOC		= $60	; Con	; Num Lock
KB_NUMENT		= $61	; Con	; Enter (Numpad)
KB_LSHIFT		= $62	; Mod	; Left Shift
KB_RSHIFT		= $63	; Mod	; Right Shift
KB_LCTRL		= $64	; Mod	; Left Ctrl
KB_RCTRL		= $65	; Mod	; Right Ctrl
KB_LALT			= $66	; Mod	; Left Alt
KB_RALT			= $67	; Mod	; Right Alt
KB_LWIN			= $68	; Mod	; Left Win
KB_RWIN			= $69	; Mod	; Right Win

; Key Classes
.enum KeyClass
	Nul		= $00		; Null key
	Alp		= $01		; Letters (Modified by Caps Lock/Shift)
	Sym		= $1B		; Symbols/digits (Modified by Shift)
	Pad		= $35		; Numpad keys (Modified by Num Lock)
	Con		= $40		; Control keys and static characters
	Mod		= $62		; Modifier keys
.endenum

; Modifier Flags
KB_MOD_SHIFT		= %11000000	; Shift key pressed
KB_MOD_CTRL		= %00110000	; Ctrl key pressed
KB_MOD_ALT		= %00001100	; Alt key pressed
KB_MOD_WIN		= %00000011	; Win key pressed

; Modifier Key Flags
KB_MOD_LS		= %10000000	; Left Shift pressed
KB_MOD_RS		= %01000000	; Right Shift pressed
KB_MOD_LC		= %00100000	; Left Ctrl pressed
KB_MOD_RC		= %00010000	; Right Ctrl pressed
KB_MOD_LA		= %00001000	; Left Alt pressed
KB_MOD_RA		= %00000100	; Right Alt pressed
KB_MOD_LW		= %00000010	; Left Win pressed
KB_MOD_RW		= %00000001	; Right Win pressed

; Lock Flags
KB_LOCK_CAPS		= %00000100	; Caps Lock flag
KB_LOCK_NUM		= %00000010	; Num Lock flag
KB_LOCK_SCR		= %00000001	; Scroll Lock flag

.endif
