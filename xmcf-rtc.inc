;==============================================================================
; rtc.inc
;==============================================================================

.ifndef _RTC_INC_				; Don't allow multiple includes
_RTC_INC_ = 1

.ifndef _RTC_NOIMPORTS_			; Skip imports

.import rtc_init					; Startup routine
.import rtc_isr						; Interrupt Routine
.import	rtc_time_set, rtc_time_write, rtc_time_sync	; Procedures
.import rtc_alarm_read, rtc_alarm_write, rtc_pi_rate_set;
.import rtc_nv_read, rtc_nv_write, rtc_bank0, rtc_bank1	;
.import rtc_wait					;
.import	RTC_Time, RTC_Uptime, RTC_Jiffy, RTC_Alarm	; Variables
.import RTC_PI_Rate					;
.import ph_RTC_PI, ph_RTC_UI, ph_RTC_AI, ph_CF_ISR	; ISR hook pointers

.endif

.ifndef _XMCF_INC_
_XMCF_INC_ = 1
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
; RTC Constants
;==============================================================================
; Registers
RTC_SECOND		= $00		; Second
RTC_SECOND_ALARM	= $01		; Seconds alarm
RTC_MINUTE		= $02		; Minute
RTC_MINUTE_ALARM	= $03		; Minutes alarm
RTC_HOUR		= $04		; Hour
RTC_HOUR_ALARM		= $05		; Hours alarm
RTC_DAY			= $06		; Day
RTC_DATE		= $07		; Date
RTC_MONTH		= $08		; Month
RTC_YEAR		= $09		; Year
RTC_CR_A		= $0A		; Control Register A
RTC_CR_B		= $0B		; Control Register B
RTC_CR_C		= $0C		; Control Register C
RTC_CR_D		= $0D		; Control Register D
RTC_EXT_CENTURY		= $48		; Century byte
RTC_EXT_DATE_ALARM	= $49		; Date Alarm
RTC_EXT_4A		= $4A		; Extended Control Register 4A
RTC_EXT_4B		= $4B		; Extended Control Register 4B
RTC_EXT_ADDRESS_M2	= $4E		; RTC Address-2
RTC_EXT_ADDRESS_M3	= $4E		; RTC Address-3
RTC_EXT_RAM_ADDR	= $50		; Extended RAM address
RTC_EXT_RAM_DATA	= $53		; Extended RAM data


; Control Register A Bits
RTC_UIP			= %10000000	; Update-in-progress flag
RTC_DV2			= %01000000	; Countdown chain
RTC_DV1			= %00100000	; Oscillator enable
RTC_DV0			= %00010000	; Bank select
RTC_RS			= %00001111	; Divider rate-selection

; Control Register B Bits
RTC_SET			= %10000000	; Update inhibit
RTC_PIE			= %01000000	; Periodic-interrupt enable
RTC_AIE			= %00100000	; Alarm-interrupt enable
RTC_UIE			= %00010000	; Update-ended interrupt enable
RTC_SQWE		= %00001000	; Square-wave output enable
RTC_DM			= %00000100	; Data mode (BCD enable)
RTC_24H			= %00000010	; 24-hour mode enable
RTC_DSE			= %00000001	; Daylight Savings enable

; Control Register C Bits
RTC_IRQF		= %10000000	; Interrupt-request flag
RTC_PF			= %01000000	; Periodic-interrupt flag
RTC_AF			= %00100000	; Alarm-interrupt flag
RTC_UF			= %00010000	; Update-ended interrupt flag

; Control Register D Bits
RTC_VRT			= %10000000	; Valid RAM and time flag

; Extended Control Register 4A Bits
RTC_VRT2		= %10000000	; Aux battery status
RTC_INCR		= %01000000	; Increment-in-progress status
RTC_PAB			= %00001000	; Power-active bar control
RTC_RF			= %00000100	; Ram Clear flag
RTC_WF			= %00000010	; Wake-up alarm flag
RTC_KF			= %00000001	; Kickstart flag

; Extended Control Register 4B Bits
RTC_ABE			= %10000000	; Auxiliary battery enable
RTC_E32K		= %01000000	; 32.768kHz output enable
RTC_CS			= %00100000	; Crystal select
RTC_RCE			= %00010000	; RAM Clear enable
RTC_PRS			= %00001000	; PAB Reset-Select
RTC_RIE			= %00000100	; RAM-clear interrupt enable
RTC_WIE			= %00000010	; Wake-up interrupt enable
RTC_KSE			= %00000001	; Kickstart interrupt enable

; Rate Select values
RTC_RS_8192		= %00000011	; 8192Hz/122.070us
RTC_RS_4096		= %00000100	; 4096Hz/244.141us
RTC_RS_2048		= %00000101	; 2048Hz/488.281us
RTC_RS_1024		= %00000110	; 1024Hz/976.5625us
RTC_RS_512		= %00000111	; 512Hz/1.953125ms
RTC_RS_256		= %00001000	; 256Hz/3.90625ms
RTC_RS_128		= %00001001	; 128Hz/7.8125ms
RTC_RS_64		= %00001010	; 64Hz/15.625ms
RTC_RS_32		= %00001011	; 32Hz/31.25ms
RTC_RS_16		= %00001100	; 16Hz/62.5ms
RTC_RS_8		= %00001101	; 8Hz/125ms
RTC_RS_4		= %00001110	; 4Hz/250ms
RTC_RS_2		= %00001111	; 2Hz/500ms

;==============================================================================
; Structs
;==============================================================================
.struct RTCTime
	Second	.byte			; Second	(00-59 BCD)
	Minute	.byte			; Minute	(00-59 BCD)
	Hour	.byte			; Hour		(00-23 BCD)
	Day	.byte			; Day of week	(01-07 BCD)
	Date	.byte			; Date		(01-31 BCD)
	Month	.byte			; Month		(01-12 BCD)
	Year	.byte			; Year		(00-99 BCD)
	Century	.byte			; Century	(00-99 BCD)
.endstruct

.struct RTCAlarm
	Second	.byte			; Second	(00-59 BCD)
	Minute	.byte			; Minute	(00-59 BCD)
	Hour	.byte			; Hour		(00-23 BCD)
	Date	.byte			; Date		(01-31 BCD)
.endstruct

.endif