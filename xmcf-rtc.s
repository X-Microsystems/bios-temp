;==============================================================================
; xmcf-rtc.s
; XMICRO-CF card and DS1685 RTC driver
; (CompactFlash driver is a separate module, xmcf-cf.s)
;==============================================================================
; Notes
; 1. RTC_Jiffy is a 16-bit counter which overflows and resets to 0 exactly
; once per second. The resolution at which it increments at depends on the
; Rate-Select setting. For example, if RS is set to 64Hz, RTC_Jiffy will
; increment by 1024. It is not guaranteed to hit 0 at the same time as the
; Seconds value changes, but it is reset to 0 at that time. For the purposes
; of this driver, 1/65,536 second (15.25879uS) is referred to as a "Jiffy"
;
; 2. RTC_Uptime is a 32-bit count of the seconds since initialization (boot).
;
; 3. Bank 1 is expected by all routines. Operations using Bank 0 must switch
; into and back out of Bank 0.
;
; 4. The ISR services the PI, UI, and AI interrupts. Each of these sub-ISRs
; has a hook that can be used by programs to run a subroutine. The address
; of the subroutine is placed in the Hook variable, and the subroutine must
; end with an RTS. When not used, these hooks point directly at an RTS
; instruction.
;==============================================================================

_RTC_NOIMPORTS_ = 1			; No imports from rtc.inc
.include "xmcf-rtc.inc"			;

.constructor rtc_init, 8				; Startup routine
.interruptor rtc_isr					; Interrupt Routine
.export	rtc_time_set, rtc_time_write, rtc_time_sync	; Procedures
.export rtc_alarm_read, rtc_alarm_write, rtc_pi_rate_set;
.export rtc_nv_read, rtc_nv_write, rtc_bank0, rtc_bank1	;
.export rtc_wait					;
.export	RTC_Time, RTC_Uptime, RTC_Jiffy, RTC_Alarm	; Variables
.export RTC_PI_Rate					;
.export ph_RTC_PI, ph_RTC_UI, ph_RTC_AI, ph_CF_ISR	; ISR hook pointers

; Configuration Constants
INIT_RATE	= RTC_RS_64		; Default PIE rate 64Hz/15.625ms

; Variables
.segment "DATA"
RTC_Time:	.tag RTCTime		; Current time from RTC
RTC_Uptime:	.res 4			; Number of seconds since startup
RTC_Jiffy:	.res 2			; 1Hz 16-bit Periodic-interrupt counter
RTC_PI_Rate:	.res 1			; PI rate selection
RTC_PI_Inc:	.res 2			; Amount to increment the RTC_Jiffy
RTC_Alarm:	.tag RTCAlarm		; Alarm values
Wait_Jiffy:	.res 1			; RTC jiffy counter target value
Wait_Second:	.res 1			; RTC seconds target value

; Hooks
; All hooks are expected to return with an RTS.
ph_RTC_PI:	.res 2			; Periodic interrupt hook
ph_RTC_UI:	.res 2			; Update interrupt hook
ph_RTC_AI:	.res 2			; Alarm interrupt hook
ph_CF_ISR:	.res 2			; CompactFlash interrupt hook

.segment "CODE"
;==============================================================================
; rtc_time_read - Updates the values in RTC_Time
;
; Outputs
;  RTC_Time (8 bytes)	Current time from the RTC
;
; Clobbers .AX
;==============================================================================
.proc rtc_time_read
		lda #RTC_CR_A		; Read Control Register A
		sta RTC_ADDR		;
:		lda RTC_DATA		; 
		and #RTC_UIP		; Check the UIP bit
		bne :-			; Loop if an update is in progress
		ldx #$00		;
GetTime:	lda RTC_Update_Tbl,x	; Get next RTC address from the table
		sta RTC_ADDR		; Set the RTC address
		lda RTC_DATA		; Read the data value from the RTC
		sta RTC_Time,x		; Store the value in RTC_Time
		inx			;
		cpx #$08		;
		bne GetTime		; Repeat until all bytes are updated.
Done:		rts			;
.endproc

;==============================================================================
; rtc_time_set - Enables the SET bit in the RTC to stop the time from updating.
; Should be followed by rtc_time_write to load the new values and disable the
; SET bit
;
; Clobbers .A
;==============================================================================
.proc rtc_time_set
		lda #RTC_CR_B		; Control Register B
		sta RTC_ADDR		;
		lda RTC_DATA		; Read current value
		ora #RTC_SET		; Set the SET bit (this clears UIE)
		sta RTC_DATA		;
		rts			;
.endproc

;==============================================================================
; rtc_time_write - Loads the values in RTC_Time into the RTC's registers
; *The SET bit must be enabled before changing the values in RTC_Time. Use the
; rtc_time_set procedure. This procedure disables SET when finished.*
;
; Inputs
;  RTC_Time (8 bytes)	Current time from the RTC
;
; Clobbers .AX
;==============================================================================
.proc rtc_time_write
		lda #RTC_CR_A		; Read Control Register A
		sta RTC_ADDR		;
:		lda RTC_DATA		; 
		and #RTC_UIP		; Check the UIP bit
		bne :-			; Loop if an update is in progress
		ldx #$00		;
WriteTime:	lda RTC_Update_Tbl,x	; Get next RTC address from the table
		sta RTC_ADDR		; Set the RTC address
		lda RTC_Time,x		; Read the data value from the RTC
		sta RTC_DATA		; Store the value in RTC_Time
		inx			;
		cpx #$08		;
		bne WriteTime		; Repeat until all bytes are updated.
ClearSet:	lda #RTC_CR_B		; Control Register B
		sta RTC_ADDR		;
		lda RTC_DATA		; Read current value
		and #RTC_SET^$FF	; Clear the SET bit
		ora #RTC_UIE		; Re-enable the Update Interrupt
		sta RTC_DATA		;
Done:		rts			;
.endproc

;==============================================================================
; rtc_time_sync - Sets the seconds to 00. Rounds up if seconds >=30
; *Does not sync if it's past 23:59:30 - not worth the trouble/ROM
;
; Clobbers .A
;==============================================================================
.proc rtc_time_sync
		jsr rtc_time_set		; Stop updating the clock
		sed				; Set BCD mode
Seconds:	lda RTC_Time+RTCTime::Second	; Get the current Seconds value
		stz RTC_Time+RTCTime::Second	; Zero it
		cmp #$30			; Round up?
		bcc Done			; No, save the new time
Minutes:	lda RTC_Time+RTCTime::Minute	; Yes, increment Minutes
		cmp #$59			; 
		beq Hours			;
		adc #$01			;
		sta RTC_Time+RTCTime::Minute	;
		bra Done			;
Hours:		stz RTC_Time+RTCTime::Minute	; Also need to increment Hours
		lda RTC_Time+RTCTime::Hour	;
		cmp #$23			;
		beq Cancel			; Cancel if days need it too
		adc #$01			;
		sta RTC_Time+RTCTime::Hour	;
		bra Done			;

Done:		cld				; Clear BCD mode
		jsr rtc_time_write		; Write the values to the RTC
		rts				;

Cancel:		cld				; Clear BCD mode
		jmp rtc_time_write::ClearSet	; Clear the SET bit, no change
.endproc

;==============================================================================
; rtc_alarm_read - Loads the RTC's alarms into RTC_Alarm
;
; Outputs
;  RTC_Alarm (4 bytes)	Alarm values
;
; Clobbers .AX
;==============================================================================
.proc rtc_alarm_read
		ldx #$00		;
ReadAlarm:	lda RTC_Alarm_Tbl,x	; Get next RTC address from table
		sta RTC_ADDR		; Set the RTC address
		lda RTC_DATA		; Read the value from the RTC
		sta RTC_Alarm,x		; Store the value in RTC_Alarm
		inx			;
		cpx #.sizeof(RTCAlarm)	;
		bne ReadAlarm		; Repeat until all bytes are updated.
		rts			;
.endproc

;==============================================================================
; rtc_alarm_write - Loads the values in RTC_Alarm into the RTC
; Values of $FF indicate "Don't Care", any values of $DD disable alarms
;
; Inputs
;  RTC_Alarm (4 bytes)	Alarm values
;
; Clobbers .AX
;==============================================================================
.proc rtc_alarm_write
		ldx #$00		;
WriteAlarm:	lda RTC_Alarm_Tbl,x	; Get next RTC address from table
		sta RTC_ADDR		; Set the RTC address
		lda RTC_Alarm,x		; Read the value from RTC_Alarm
		sta RTC_DATA		; Set the value in the RTC
		inx			;
		cpx #.sizeof(RTCAlarm)	;
		bne WriteAlarm		; Repeat until all bytes are updated.
		rts			;
.endproc

;==============================================================================
; rtc_pi_rate_set - Sets the rate of the Periodic Interrupt, and the matches
; the jiffy counter resolution to it.
;
; Inputs
;  RTC_PI_Rate	Rate Select (RS3..0) bits for the DS1685
;		Valid values are from $03-$0F
;
; Clobbers .AX
;==============================================================================
.proc rtc_pi_rate_set
		lda #RTC_CR_A		;
		sta RTC_ADDR		; Open Control Register A
		lda RTC_PI_Rate		; Load the RTC_PI_Rate value
		and #%00001111		; Mask invalid bits to prevent errors
		sta RTC_PI_Rate		; Store the masked rate
		cmp #%00000011		; Check if the value is valid (>=%11)
		bcs SetInc		;
		lda RTC_DATA		; Reset rate variable if it's invalid
		and #%00001111		;
		sta RTC_PI_Rate		;
SetInc:		tax			; Setting up the RTC_Jiffy increment
		lda #$01		; Start with one bit ($0001)
		sta RTC_PI_Inc		;
		stz RTC_PI_Inc+1	;
SetInc1:	asl RTC_PI_Inc		; Shift the bit left [RTC_PI_Rate] times
		rol RTC_PI_Inc+1	;
		dex			;
		bne SetInc1		; Repeat until done
		lda RTC_DATA		; Load CR A's current value
SetRate:	and #%11110000		; 
		ora RTC_PI_Rate		; Replace the value of RS
		sta RTC_DATA		; Store it
		rts			;
.endproc

;==============================================================================
; rtc_nv_read - Read a byte from an NVRAM address.
; *Extended RAM addresses are mapped to $80-$FF
;
; Inputs
;  .X	NVRAM address ($0E-$FF)
;
; Outputs
;  .A	Data
;==============================================================================
.proc rtc_nv_read
		cpx #$0E		;
		bcc Return		; Address is invalid (<$0E)
		cpx #$40		;
		bcc LoRAM		; Address is $0E-$3F, no bank switch
		cpx #$80		;
		bcc HiRAM		; Address is $40-$7F, bank 0

ExRAM:		lda #RTC_EXT_RAM_ADDR	; Address is $80-$FF, extended RAM
		sta RTC_ADDR		;
		txa			; Transfer address to .A
		and #$7F		; Clear bit 7 (ext addresses $00-$7F)
		sta RTC_DATA		; Set the extended RAM address
		lda #RTC_EXT_RAM_DATA	;
		sta RTC_ADDR		;
		lda RTC_DATA		; Get the data
		rts			; Return

HiRAM:		jsr rtc_bank0		; Switch to Bank 0
		stx RTC_ADDR		;
		lda RTC_DATA		; Get the data
		pha			; Push data
		jsr rtc_bank1		; Switch back to Bank 1
		pla			; Pull data
		rts			; Return

LoRAM:		stx RTC_ADDR		;
		lda RTC_DATA		; Get the data
Return:		rts			; Return
.endproc

;==============================================================================
; rtc_nv_write - Read a byte from an NVRAM address.
; Extended RAM addresses are mapped to $80-$FF
;
; Inputs
;  .X	NVRAM address ($0E-$FF)
;  .A	Data
;==============================================================================
.proc rtc_nv_write
		cpx #$0E		;
		bcc Return		; Address is invalid (<$0E)
		cpx #$40		;
		bcc LoRAM		; Address is $0E-$3F, no bank switch
		cpx #$80		;
		bcc HiRAM		; Address is $40-$7F, bank 0

ExRAM:		pha			; Address is $80-$FF, extended RAM
		lda #RTC_EXT_RAM_ADDR	;
		sta RTC_ADDR		;
		txa			; Transfer address to .A
		and #$7F		; Clear bit 7 (ext addresses $00-$7F)
		sta RTC_DATA		; Set the extended RAM address
		lda #RTC_EXT_RAM_DATA	;
		sta RTC_ADDR		;
		pla			; Pull the data from the stack
		sta RTC_DATA		; Store the data
		rts			; Return

HiRAM:		pha			; Push data
		jsr rtc_bank0		; Switch to Bank 0
		pla			; Pull data
		stx RTC_ADDR		;
		sta RTC_DATA		; Store the data
		jsr rtc_bank1		; Switch back to Bank 1
		rts			; Return

LoRAM:		stx RTC_ADDR		;
		sta RTC_DATA		; Store the data
Return:		rts			; Return
.endproc

;==============================================================================
; rtc_bank0 - Switches to Bank 0
;
; Clobbers .A
;==============================================================================
.proc rtc_bank0
		lda #RTC_CR_A		; Control Register A
		sta RTC_ADDR		;
		lda RTC_DATA		; Read current value
		and #RTC_DV0^$FF	; Clear the bank select bit
		sta RTC_DATA		;
		rts			;
.endproc

;==============================================================================
; rtc_bank1 - Switches to Bank 1
;
; Clobbers .A
;==============================================================================
.proc rtc_bank1
		lda #RTC_CR_A		; Control Register A
		sta RTC_ADDR		;
		lda RTC_DATA		; Read current value
		ora #RTC_DV0		; Set the bank select bit
		sta RTC_DATA		;
		rts			;
.endproc

;==============================================================================
; rtc_wait - Waits for a set period of time.
; *If the wait value is shorter than the PIE interval, one second will be
; added to the wait. If the wait value is equal to the PIE interval, the wait
; will be shorter than specified.
;
; Inputs
;  .A	Jiffies/256 (RTC_Jiffy MSB)
;  .Y	Seconds
;
; Clobbers .A
;==============================================================================
.proc rtc_wait
		clc			;
		adc RTC_Jiffy+1		; Add the current Jiffy value
		pha			; Push the Jiffy target
		tya			; Get the Seconds interval
		bne :+			;
		bcc LoopJif		; Skip the seconds check if not needed
:		adc RTC_Uptime		; Check the current Seconds count
LoopSec:	cmp RTC_Uptime		; Wait until the target is reached
		bcc LoopSec		;
LoopJif:	pla			; Retrieve the Jiffy target
LoopJif1:	cmp RTC_Jiffy+1		; Check the current Jiffy count
		bcc LoopJif1		; Loop until the target is reached
		rts			;
.endproc

;==============================================================================
; rtc_isr - Interrupt service routine for the XMICRO-CF card
; Extended interrupts (WI, KI, RI) are not implemented and should be disabled
;
; Hooks
;  ph_RTC_PI	Pointer for an RTC Periodic Interrupt ISR
;  ph_RTC_UI	Pointer for an RTC Update Interrupt ISR
;  ph_RTC_AI	Pointer for an RTC Alarm Interrupt ISR
;  ph_CF_ISR	Pointer for a CompactFlash ISR
;
; Outputs
;  Periodic Interrupt
;   Increments RTC_Jiffy
;  Update Interrupt
;   Reads the time values from the RTC and stores them in RTC_Time
;   Resets RTC_Jiffy to zero to ensure it stays in sync
;
;==============================================================================
.proc rtc_isr
		pha			;
		phx			;
		phy			;
		lda XMCF_SR		;
		bit #XMCF_SR_RTCI	; Check for a pending RTC interrupt
		beq CheckCF		;

GetPrevAddr:	lda #RTC_CR_A		; Recovering the current RTC address
		sta RTC_ADDR		; Open CR A
		lda RTC_DATA		; Start with the Bank Select bit
		and #RTC_DV0		; Mask the bit
		pha			; Push it to the stack
		bne :+			;
		jsr rtc_bank1		; Select Bank 1 if it isn't already
:		lda #RTC_EXT_ADDRESS_M2	; Open Register 4E (RTC Address-2)
		sta RTC_ADDR		;
		lda RTC_DATA		; Get the previous RTC address
		pha			; Push it to the stack

Find:		ldx #RTC_CR_B		; Find the source of the interrupt
		stx RTC_ADDR		; Starting with the most frequent
		lda #RTC_PIE|RTC_UIE|RTC_AIE
		and RTC_DATA		; Get the enabled interrupts
		inx			;
		stx RTC_ADDR		;
		and RTC_DATA		; Get only enabled and pending flags
		bit #RTC_PF		; Check the Periodic Interrupt flag
		beq :+			;
		and #RTC_PF^$FF		; Got a PI. Clear the flag
		pha			; Push the remaining flags for later
		jsr PI			;
		pla			; Back from PI. Reload the flags
		beq RestoreAddr		; If none remain, end the ISR
:		bit #RTC_UF		; Check the Update Interrupt flag
		beq :+			;
		and #RTC_UF^$FF		; Got a UI. Clear the flag
		pha			; Push the remaining flags for later
		jsr UI			;
		pla			; Back from UI. Reload the flags
		beq RestoreAddr		; If none remain, end the ISR
:		bit #RTC_AF		; Check the Alarm Interrupt flag
		beq :+			;
		jsr AI			; Got an AI.

RestoreAddr:	plx			; Pull the previous address
		pla			; Pull the previous Bank Select bit
		bne :+			;
		jsr rtc_bank0		; Select Bank 0 if it was before
:		stx RTC_ADDR		; Restore the previous address

CheckCF:	lda XMCF_SR		;
		bit #XMCF_SR_CFI	; Check for a pending CF interrupt
		beq Return		;
		jsr CF			;
Return:		ply			;
		plx			;
		pla			;
		rti			;

PI:		clc			; Periodic Interrupt
		lda RTC_Jiffy		; Inc RTC_Jiffy based on the PI rate
		adc RTC_PI_Inc		;
		sta RTC_Jiffy		;
		lda RTC_Jiffy+1		;
		adc RTC_PI_Inc+1	;
		sta RTC_Jiffy+1		;
		jmp (ph_RTC_PI)		; Jump to user vector for PI servicing
					; The routine must return with RTS

UI:		jsr rtc_time_read	; Update Interrupt - Read the time
		ldx #$00		; Increment the RTC_Uptime counter
@IncUptime:	inc RTC_Uptime,x	;
		bne @RstJiffy		; If it overflows, INC the next byte
		inx			;
		cpx #$04		; Check if the last byte has been done
		bne @IncUptime		; Loop if there's another byte
@RstJiffy:	stz RTC_Jiffy		; Reset the jiffy counter to zero
		stz RTC_Jiffy+1		; In case it isn't already aligned
		jmp (ph_RTC_UI)		; Jump to user vector for UI servicing

AI:		jmp (ph_RTC_AI)		; Alarm Interrupt
					; Jump to user vector for AI servicing
					; The routine must return with RTS

CF:		jmp (ph_CF_ISR)		; Jump to the CF service routine
.endproc

.segment "ONCE"
;==============================================================================
; rtc_init - Initializes the RTC hardware and functions
; *This should be run at system startup, before interrupts are enabled.*
; 
; Clobbers .AX
;==============================================================================
.proc rtc_init
		lda #<rtc_isr		; Place the ISR in the vector table
		sta XMCF_VECTOR		;
		lda #>rtc_isr		;
		sta XMCF_VECTOR+1	;
		ldx #$00		;
SoftVectors:	lda #<Return		; Set hooks to do nothing, point to RTS
		sta ph_RTC_PI,x	;
		inx			;
		lda #>Return		;
		sta ph_RTC_PI,x	;
		inx			;
		cpx #$08		; Repeat for 4 hooks
		bne SoftVectors		;

		ldx #$00		; Initialize RTC registers
RegInit:	lda RTC_Init_Tbl,x	; Get the register from the table
		sta RTC_ADDR		; Set the RTC address
		inx			;
		lda RTC_Init_Tbl,x	; Get the value from the table
		sta RTC_DATA		; Set the alarm to "Don't Care"
		inx			;
		cpx #14			;
		bne RegInit		; Repeat until all bytes are updated.

SetJiffy:	lda #INIT_RATE		; Set the jiffy counter rate
		sta RTC_PI_Rate		;
		jsr rtc_pi_rate_set	;

		jsr rtc_time_read	; Read the time from the RTC

		ldx #$00		; Zero the RTC_Uptime
ResetUptime:	stz RTC_Uptime,x	;
		inx			;
		cpx #$04		;
		bne ResetUptime		; Loop until all bytes are done

CardInit:	stz XMCF_SR		; Enable XMICRO-CF card inuerrupts

Return:		rts			;
.endproc

.segment "RODATA"
; Tables
; Clock update table - RTC register addresses aligning with the Time struct
RTC_Update_Tbl:	.byte	RTC_SECOND
		.byte	RTC_MINUTE
		.byte	RTC_HOUR
		.byte	RTC_DAY
		.byte	RTC_DATE
		.byte	RTC_MONTH
		.byte	RTC_YEAR
		.byte	RTC_EXT_CENTURY

; Alarm table - RTC register addresses aligning with the Alarm struct
RTC_Alarm_Tbl:	.byte	RTC_SECOND_ALARM
		.byte	RTC_MINUTE_ALARM
		.byte	RTC_HOUR_ALARM
		.byte	RTC_EXT_DATE_ALARM

; Initialization table - Register/Value pairs for rtc_init
RTC_Init_Tbl:	.byte	RTC_CR_A,		%00110000	; RTC on, Bank 1
		.byte	RTC_CR_B,		%01110010	; PIE, AIE, UIE, BCD, 24h enabled
		.byte	RTC_EXT_4B,		%01100000	; ABE off, 12.5pF
		.byte	RTC_SECOND_ALARM,	$DD		; Disable seconds alarm
		.byte	RTC_MINUTE_ALARM,	$DD		; Disable minutes alarm
		.byte	RTC_HOUR_ALARM,		$DD		; Disable hours alarm
		.byte	RTC_EXT_DATE_ALARM,	$DD		; Disable date alarm