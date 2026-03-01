;==============================================================================
; xmcf-cf.inc
; Imports and constants
;==============================================================================

.ifndef _CF_INC_			; Don't allow multiple includes
_CF_INC_ = 1				;

.ifndef _CF_NOIMPORTS_			; Skip imports

.import cf_init				; Startup routine
.import cf_isr				; Interrupt Routine
.import	ata_get_lock, ata_rejoin	; Procedures
.import ata_irq_enable, ata_irq_disable	;
.import	ATA_Cmd, ATA_Err		; Variables

.endif

.ifndef _XMCF_INC_			;
_XMCF_INC_ = 1				;
;==============================================================================
; XMICRO-CF Card Constants
;==============================================================================
; XMICRO-CF hardware addresses
.import __XMICRO_CF_START__, __XMICRO_CF_VECTOR__
XMCF		= __XMICRO_CF_START__	; Base Address
CF		= XMCF+$00		; CompactFlash base address
RTC_ADDR	:= XMCF+$20		; RTC Address register	(W)
RTC_DATA	:= XMCF+$21		; RTC Data register	(R/W)
XMCF_SR		:= XMCF+$80		; XMICRO-CF Status register (R)

; XMICRO-CF Pointers
XMCF_VECTOR	:= __XMICRO_CF_VECTOR__	; XMICRO-CF interrupt vector pointer

; XMICRO-CF Status Register Bits
XMCF_SR_RTCI		= %00000001	; RTC interrupt status
XMCF_SR_CFI		= %00000010	; CF interrupt status
XMCF_SR_CFCP		= %00000100	; CF card present status
XMCF_SR_IRQD		= %00001000	; Interrupt disable
.endif

;==============================================================================
; Task File (hardware) Registers
;==============================================================================
; Task File Register Offsets
CF_DATA			= $00		; Data register (R/W)
CF_ERR			= $01		; Error register (R)
CF_FEAT			= $01		; Features register (W)
CF_SECCO		= $02		; Sector Count (R/W)
CF_LBA0			= $03		; Sector Number, LBA bits 7-0 (R/W)
CF_LBA1			= $04		; Cylinder Low,	 LBA bits 15-8 (R/W)
CF_LBA2			= $05		; Cylinder High, LBA bits 23-16 (R/W)
CF_LBA3			= $06		; Drive/Head,    LBA bits 27-24 (R/W)
CF_STAT			= $07		; Status Register (R)
CF_CMD			= $07		; Command Register (W)
CF_ASR			= $1E		; Alternate Status Register (R)
CF_DCR			= $1E		; Device Control Register (W)

; Error Register Bits
CF_ERR_BBK		= %10000000	; Bad block detected
CF_ERR_UNC		= %01000000	; Uncorrectable error
CF_ERR_IDNF		= %00010000	; Sector ID not found
CF_ERR_ABRT		= %00000100	; Command aborted
CF_ERR_AMNF		= %00000001	; General error

; LBA3 (Drive/Head) Register Bits
CF_LBA3_LBA		= %01000000	; LBA mode enable
CF_LBA3_DN		= %00010000	; Drive number

; Status Register Bits
CF_STAT_BUSY		= %10000000	; Card busy
CF_STAT_RDY		= %01000000	; Card ready to accept command
CF_STAT_DWF		= %00100000	; Write Fault has occurred
CF_STAT_DSC		= %00010000	; Data Seek Complete (card ready)
CF_STAT_DRQ		= %00001000	; Data Request
CF_STAT_CORR		= %00000100	; Correctable data error
CF_STAT_ERR		= %00000001	; Previous command ended in error

; Device Control Register Bits
CF_DCR_SRST		= %00000100	; Software reset
CF_DCR_IE		= %00000010	; Interrupt enable (active-low)

;==============================================================================
; CF-ATA Command Set
; *Some commands have been excluded, where they are not recommended for use, or
; are implemented for backward-compatibility and unlikely to be of any value.
; Multiple Mode is not implemented.
;==============================================================================
; Label			; Value	; Class	; Name
CF_ATA_CPM		= $E5	; ND	; Check Power Mode
CF_ATA_EDD		= $90	; ND	; Execute Drive Diagnostic
CF_ATA_ES		= $C0	; ND	; Erase Sector(s)
CF_ATA_FC		= $E7	; ND	; Flush Cache
CF_ATA_FT		= $50	; DO	; Format Track
CF_ATA_ID		= $EC	; DI 	; Identify Device
CF_ATA_IDL		= $E3	; ND	; Idle
CF_ATA_IDLI		= $E1	; ND	; Idle Immediate
CF_ATA_IDP		= $91	; ND	; Initialize Drive Parameters
CF_ATA_NOP		= $00	; ND	; NOP
CF_ATA_RB		= $E4	; DI	; Read Buffer
CF_ATA_RM		= $C4	; DI	; Read Multiple
CF_ATA_RS		= $20	; DI	; Read Sector(s)
CF_ATA_RVS		= $40	; ND	; Read Verify Sector(s)
CF_ATA_RQS		= $03	; ND	; Request Sense (Extended error info)
CF_ATA_SEEK		= $70	; ND	; Seek
CF_ATA_SF		= $EF	; ND	; Set Features
CF_ATA_SM		= $C6	; ND	; Set Multiple Mode
CF_ATA_SSM		= $E6	; ND	; Set Sleep Mode
CF_ATA_STB		= $E2	; ND	; Standby
CF_ATA_STBI		= $E0	; ND	; Standby Immediate
CF_ATA_TS		= $87	; DI	; Translate Sector
CF_ATA_WB		= $E8	; DO	; Write Buffer
CF_ATA_WM		= $C5	; DO	; Write Multiple
CF_ATA_WMNE		= $CD	; DO	; Write Multiple without Erase
CF_ATA_WS		= $30	; DO	; Write Sector(s)
CF_ATA_WSNE		= $38	; DO	; Write Sector(s) without Erase
CF_ATA_WV		= $3C	; DO	; Write Verify

; Feature Codes (for CF_ATA_SF - Set Features)
CF_FEAT_8BE		= $01		; Enable 8-bit data transfers
CF_FEAT_WCE		= $02		; Enable Write Cache
CF_FEAT_STM		= $03		; Set Transfer Mode
CF_FEAT_APME		= $05		; Enable Advanced Power Mode
CF_FEAT_EPE		= $09		; Enable Extended Power operations
CF_FEAT_PL1E		= $0A		; Enable Power Level 1 commands
CF_FEAT_ECC		= $44		; Product specific ECC on R/W Long cmds
CF_FEAT_RLAD		= $55		; Disable Read Lookahead
CF_FEAT_PORD		= $66		; Disable Power-on defaults on soft-rst
CF_FEAT_NOP		= $69		; NOP
CF_FEAT_8BD		= $81		; Disable 8-bit data transfers
CF_FEAT_WCD		= $82		; Disable Write Cache
CF_FEAT_APMD		= $85		; Disable Advanced Power Mode
CF_FEAT_EPD		= $89		; Disable Extended Power operations
CF_FEAT_PL1D		= $8A		; Disable Power Level 1 commands
CF_FEAT_HCS		= $9A		; Set Host Current Source capability
CF_FEAT_RLAE		= $AA		; Enable Read Lookahead
CF_FEAT_PORE		= $CC		; Enable Power-on defaults for soft-rst


; ATA Command Parameters
; *Parameters must not to be modified while ATA_Lock is set*
.struct ATAPar
	Feat	.byte			; R1 Feature
	SecCo	.byte			; R2 Sector Count
	LBA0	.byte			; R3 Sector Number, LBA 7-0
	LBA1	.byte			; R4 Cylinder Low,  LBA 15-8
	LBA2	.byte			; R5 Cylinder High, LBA 23-16
	LBA3	.byte			; R6 Drive/Head,    LBA 27-24
	Cmd	.byte			; R7 Command
	Class	.byte			; Command class (ATAClass enum)
	Addr	.addr			; Memory address to read/write
	Size	.word			; Size of data to transfer
.endstruct

; ATA Command Classes
.enum ATAClass
	NonData	= 0			; Commands with no data transfer
	DataIn	= 1			; Commands reading data block(s)
	DataOut	= 2			; Commands writing data block(s)
.endenum

; ATA Process Error Information
.struct ATAErr
	DevER	.byte			; Error Register
	DevSC	.byte			; Sector Number, LBA bits 7-0
	DevCL	.byte			; Cylinder Low,	 LBA bits 15-8
	DevCH	.byte			; Cylinder High, LBA bits 23-16
	DevDH	.byte			; Drive/Head,    LBA bits 27-24
	DevSR	.byte			; Status Register
	DevExt	.byte			; Extended error code
	Fault	.byte			; ATA Process fault code
	State	.byte			; ATA Process rejoin state
.endstruct

; ATA Process Fault Codes
.enum ATAFlt
	NONE	= $00			; No error
	UERR	= $01			; Unknown error
	CCNP	= $02			; CompactFlash - Card not present
	TBSY	= $03			; Timeout - Device busy
	TRDY	= $04			; Timeout - Device not ready
	TDRQ	= $05			; Timeout - Data request at Host Idle
	TLCK	= $06			; Timeout - ATA process locked
	CCLS	= $07			; ATA - Invalid command class
	IDNF	= $08			; ATA - Sector ID not found
	ABRT	= $09			; ATA - Command aborted
	UNCO	= $0A			; ATA - Uncorrectable block
	BBLK	= $0B			; ATA - Bad block
	AMNF	= $0C			; ATA - General error
	WSOR	= $0D			; ATA - Write sector overrun
.endenum

; ATA Process Rejoin States
.struct ATAStates
	HHR0	.addr			; Host Hardware Reset
	HSR0	.addr			; Host Software Reset
	HI0	.addr			; Host bus Idle
	HND0	.addr			; Host Non-Data command
	HPIOI0	.addr			; Host PIO Data-In command
	HPIOO2	.addr			; Host PIO Data-Out command
.endstruct

; All ATA process states and descriptions
;	Host Hardware Reset
;HHR0	 Assert_RESET-		Assert RESET- pin
;HHR1	 Negate_wait		Negate RESET- and wait
;HHR2	 Check_status		Loop until ready
;	Host Software Reset
;HSR0	 Set_SRST		Set SRST
;HSR1	 Negate_wait		Clear SRST and wait
;HSR2	 Check_status		Loop until ready
;	Host bus Idle
;HI0	 Host_Idle		Wait for a command
;HI1	 Check_status		Loop until ready
;HI2	 Device_Select		Select the correct device
;HI3	 Write_Parameters	Write parameters to device
;HI4	 Write_Command		Write the command and branch
;	Host Non-Data command
;HND0	 INTRQ_Wait		Wait for an interrupt
;HND1	 Check_Status		Loop until ready
;	Host PIO Data-In command
;HPIOI0	 INTRQ_Wait		Wait for an interrupt
;HPIOI1	 Check_Status		Loop until ready
;HPIOI2	 Transfer_Data		Read data from device
;	Host PIO Data-Out command
;HPIOO0	 INTRQ_Wait		Wait for an interrupt
;HPIOO1	 Check_Status		Loop until ready
;HPIOO2	 Transfer_Data		Write data to device

.endif