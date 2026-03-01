;==============================================================================
; xmcf-cf.s
; CompactFlash driver and ATA interface for XMICRO-CF
;==============================================================================
;
; This driver provides an interface for ATA commands and data transfers to the
; CompactFlash card. The ATA Process is a finite-state machine based on the
; outline provided in the ATA 6 specification (T13/1410D). Some elements have
; been excluded or adjustments made as needed for CompactFlash implementation.
; 
; Usage
; 1. Run ata_get_lock to secure exclusive access to the ATA process
; 2. Populate ATA_Cmd with all parameters needed for the command:
;   ATAPar structure:
; 	Feat	1-byte	R1 Feature
; 	SecCo	1-byte	R2 Sector Count
; 	LBA0	1-byte	R3 Sector Number, LBA 7-0
; 	LBA1	1-byte	R4 Cylinder Low,  LBA 15-8
; 	LBA2	1-byte	R5 Cylinder High, LBA 23-16
; 	LBA3	1-byte	R6 Drive/Head,    LBA 27-24
; 	Cmd	1-byte	R7 Command
; 	Class	1-byte	Command class
; 	Addr	2-byte	Memory address to read/write
; 
;   Command Classes:
; 	0 NonData	Commands with no data transfer
; 	1 DataIn	Commands reading data block(s)
; 	2 DataOut	Commands writing data block(s)
; 
; 3. Run ata_rejoin to enter the ATA process and run the command.
; 
; Notes
; 1. DMA is not implemented.
; 2. All operations that need to wait have a 3s tiemout period before error.
;==============================================================================
_CF_NOIMPORTS_ = 1			; No imports from xmcf-cf.inc
.include "xmcf-cf.inc"			;
.include "xmcf-rtc.inc"			;

.constructor cf_init			; Startup routine
.interruptor cf_isr			; Interrupt Routine
.export ata_get_lock, ata_rejoin	; Procedures
.export ata_irq_enable, ata_irq_disable	;
.export ATA_Cmd, ATA_Err		; Variables

; Constants
ATA_TIMEOUT	= $03			; Number of seconds for ATA timeouts

; Variables
.segment "ZEROPAGE"
p_ATA_Data:	.res 2			; Sector data transfer pointer

.segment "DATA"
ATA_Cmd:	.tag ATAPar		; Command parameters to pass to card
ATA_Lock:	.res 1			; ATA Command lock
ATA_Err:	.tag ATAErr		; Returned error details
ATA_Rejoin:	.res 1			; ATA protocol state to return to
ATA_Irq_Flag:	.res 1			; CF card interrupt disabled status
ATA_Sec_Count:	.res 1			; Sectors remaining in current command
ATA_Cmd_Timer:	.res 2			; Target for ATA command timeouts
ATA_Lock_Timer:	.res 2			; Target for ATA lock timeouts

;.segment "RODATA"
ATA_Buffer:	.addr $DB00		; Sector Buffer address

.segment "CODE"

;! ISRs seem to be overlapping in long interrupt-driven data transfers. How?

;==============================================================================
; ATA Protocol Process
;
; Labels and states are based on the ATA 6 specification, as described in
; Clause 9 - Protocol.
;==============================================================================
.scope ata
;==============================================================================
; HHR - Host power on or Hardware Reset
; *No hardware reset function at this time, so this is identical to HSR
;==============================================================================
hhr0:					; Assert_RESET- - Assert RESET- pin, wait >25uS
		lda #ATAStates::HHR0	; Set the rejoin process state in case
		sta ATA_Rejoin		;  the reset isn't completed properly
		jsr check_present	; Check if the device is connected
		lda #$06		; SRST=1, nIEN = 1
		sta CF+CF_DCR		; Set the SRST bit
		ldx #$38		; Loop 56 times (279c, 69us)
@WaitLoop:	dex		; 2c	;
		bne @WaitLoop	; 3c	;
hhr1:					; Negate_wait - Negate RESET- pin, wait >2ms
		jsr ata_irq_disable	; Disable interrupts (Clears SRST)
		ldy #$10		; Loop 4096 times (20545c, 5.1ms)
@WaitLoop:	dex		; 2c	;
		bne @WaitLoop	; 3c	;
		dey		; 2c	;
		bne @WaitLoop	; 3c	;
hhr2:					; Check_status - Read Status register
		bra hsr2		; HSR2 is identical, re-use it here

;==============================================================================
; HSR - Host Software Reset
;==============================================================================
hsr0:					; Set_SRST - Set SRST, wait >5uS
		lda #ATAStates::HSR0	; Set the rejoin process state in case
		sta ATA_Rejoin		;  the reset isn't completed properly
		jsr check_present	; Check if the device is connected
		lda #$06		; SRST=1, nIEN = 1
		sta CF+CF_DCR		; Set the SRST bit
		ldx #$0C		; Loop 12 times (60c, 14us)
@WaitLoop:	dex		; 2c	;
		bne @WaitLoop	; 3c	;
hsr1:					; Clear_wait - Clear SRST, wait >2ms
		jsr ata_irq_disable	; Disable interrupts (Clears SRST)
		ldy #$10		; Loop 4096 times (20575c, 5.1ms)
@WaitLoop:	dex		; 2c	;
		bne @WaitLoop	; 3c	;
		dey		; 2c	;
		bne @WaitLoop	; 3c	;
hsr2:					; Check_status - Read Status register
		jsr check_bsy		; Wait until Busy bit is clear
		jsr check_err		; Check for errors
						; Set 8-bit mode
		lda #CF_ATA_SF			; Command: Set Feature
		sta ATA_Cmd+ATAPar::Cmd		;
		lda #ATAClass::NonData		; Class: Non-data
		sta ATA_Cmd+ATAPar::Class	;
		lda #CF_FEAT_8BE		; Feature: 8-bit mode enable
		sta ATA_Cmd+ATAPar::Feat	;
		lda #$01			; Set ATA command lock
		sta ATA_Lock			;
		bra hi0			; Jump to HI0 and run the first command

;==============================================================================
; HI - Host bus Idle
;==============================================================================
hi0:					; Host_Idle - Host waits for a command to be issued to the device
		lda #ATAStates::HI0	; 
		sta ATA_Rejoin		; Set the rejoin state to HI0
		lda ATA_Lock		; Is there a pending command?
		bne hi1			; Yes, proceed to HI1.
		lda ATA_Irq_Flag	; No. Are interrupts enabled?
		beq @Return		; No, return to program.
		lda #CF_DCR_IE&$00	; Yes, re-enable device interrupts.
		sta CF+CF_DCR		;
@Return:	clc			; Clear carry to indicate success
		rts			; Return to program while waiting
hi1:					; Check_Status - Host issued a command
		lda ATA_Irq_Flag	; Are device interrupts enabled?
		beq @CheckCard		; No, skip ahead
		lda #CF_DCR_IE		; Yes, disable device interrupts
		sta CF+CF_DCR		;
		cli			; Allow other interrupts to continue
@CheckCard:	jsr check_present	; Check if the device is connected
		jsr check_bsy		; Wait until Busy bit is clear
		jsr check_drq		; Wait until Data Request bit is clear
		jsr check_rdy		; Wait until Ready bit is set
hi3:					; Write_Parameters - write parameters to the Command Block registers
		ldx #$00		;
@CmdLoop:	lda ATA_Cmd,x		; Load a value from ATA_Cmd
		sta CF+CF_FEAT,x	; Write it to the associated CF register
		inx			; Increment the index
		cpx #$06		;
		bne @CmdLoop		; Loop until all parameters are passed 
hi4:					; Write_Command - write the command to the Command register
		lda ATA_Cmd,x		; Load the command from ATA_Cmd
		sta CF+CF_FEAT,x	; Write it to the CF_CMD register
		lda ATA_Cmd+ATAPar::Class	; Branch according to the class
		beq hnd0			; Non-Data command class
		ldy ATA_Cmd+ATAPar::SecCo	; 
		sty ATA_Sec_Count		; Copy the command sector count
		ldy ATA_Cmd+ATAPar::Addr	;
		sty p_ATA_Data			; Copy the destination address
		ldy ATA_Cmd+ATAPar::Addr+1	;  to the data pointer
		sty p_ATA_Data+1		;
		cmp #ATAClass::DataIn		;
		beq hpioi0			; Data-In command class
		cmp #ATAClass::DataOut		;
		beq hpioo0			; Data-Out command class
@InvalidClass:	lda #ATAFlt::CCLS		; Error - Invalid class
		jsr error_dump			; Return to program.

;==============================================================================
; HND - Host Non-Data command
;==============================================================================
hnd0:					; INTRQ_WAIT - Non-data command has been written and nIEN bit is clear
		lda #ATAStates::HND0	; 
		sta ATA_Rejoin		; Set the rejoin state to HND0
		lda ATA_Irq_Flag	; Are interrupts enabled?
		beq hnd1		; No, proceed to HND1
		ldx XMCF_SR		; Yes, get the interrupt status
		lda #CF_DCR_IE		; Disable device interrupts until
		sta CF+CF_DCR		;  this cycle is complete.
		cli			; Allow other interrupts to continue
		txa			;
		bit #XMCF_SR_CFI	; Was there a pending CF interrupt?
		bne hnd1		; Interrupt pending. Proceed to HND1
		lda #CF_DCR_IE&$00	; Re-enable device interrupts
		sta CF+CF_DCR		;
		clc			; Clear carry to indicate success
		rts			; Return to program while waiting
hnd1:					; Check_Status - command issued, wait until ready
		jsr check_bsy		; Wait until Busy bit is clear
		jsr check_err		; Check for errors
		jmp cmd_done		; Done, return to HI0

;==============================================================================
; HPIOI - Host PIO data-In
;==============================================================================
hpioi0:					; INTRQ_Wait - PIO data-in command has been written and nIEN bit is clear
		lda #ATAStates::HPIOI0	; Set the rejoin state to HPIOI0
		sta ATA_Rejoin		; 
		lda ATA_Irq_Flag	; Are interrupts enabled?
		beq hpioi1		; No, proceed to HPIOI1
		ldx XMCF_SR		; Yes, get the interrupt status
		lda #CF_DCR_IE		; Disable device interrupts until
		sta CF+CF_DCR		;  this DRQ cycle is complete.
		cli			; Allow other interrupts to continue
		txa			;
		bit #XMCF_SR_CFI	; Was there a pending CF interrupt?
		bne hpioi1		; Yes. Proceed to HPIOI1
		lda #CF_DCR_IE&$00	; Re-enable device interrupts
		sta CF+CF_DCR		;
		clc			; Clear carry to indicate success
		rts			; Return to program while waiting
hpioi1:					; Check_Status
		jsr check_bsy		; Wait until Busy bit is clear
		lda #CF_STAT_DRQ	; Load the DRQ bit mask
		bit CF+CF_STAT		; Is the DRQ bit set?
		bne hpioi2		; Yes, proceed to HPIOI2.
		jsr check_err		; No, check for errors.
		bra cmd_done		; Command complete. Return to HI0
hpioi2:					; Transfer_Data - read the device data
		ldx #$02		; Loop twice per sector
		ldy #$00		; Read 256 bytes per loop
@Loop:		jsr check_bsy		; Wait until Busy bit is clear
		lda CF+CF_DATA		; Get a data byte from the card
		sta (p_ATA_Data),y	; Write it to the buffer
		iny			;
		bne @Loop		; Loop until .Y=0
		inc p_ATA_Data+1	; Increment pointer for another loop
		dex			;
		bne @Loop		; Loop until the sector is complete
		dec ATA_Sec_Count	; Sector done. Decrement sector count
		bne hpioi0		; If any remain, read another
		bra cmd_done		; No more sectors, return to HI0

;==============================================================================
; HPIOO - Host PIO Data-Out
;==============================================================================
hpioo0:					; Check_Status
		lda #ATAStates::HPIOO2	;
		sta ATA_Rejoin		; Set the rejoin state to HPIOO2
		jsr check_bsy		;
		lda #CF_STAT_DRQ	; Load the DRQ bit mask
		bit CF+CF_STAT		; Is the DRQ bit set?
		bne hpioo1		; Yes, proceed to HPIOO1.
		jsr check_err		; No, transfer is complete.
		bra cmd_done		; No more sectors, return to HI0
hpioo1:					; Transfer_Data - write data to device
		lda ATA_Sec_Count	; Is this sector write expected?
		bne @LoopSetup		; Yes, proceed to the write loop
@InvalidSector: lda ATAFlt::WSOR	; No, error. Set WSOR fault code
		jsr error_dump		; Return to program
@LoopSetup:	ldx #$02		; Loop twice per sector
		ldy #$00		; Read 256 bytes per loop
@Loop:		jsr check_bsy		; Wait until the device is ready
		lda (p_ATA_Data),y	; Get a data byte from the buffer
		sta CF+CF_DATA		; Write it to the card
		iny			;
		bne @Loop		; Loop until .Y=0
		inc p_ATA_Data+1	; Increment pointer for another loop
		dex			;
		bne @Loop		; Loop until the sector is complete
		dec ATA_Sec_Count	; Sector done. Decrement sector count
		lda ATA_Irq_Flag	; Are interrupts enabled?
		beq hpioo0		; No, proceed to HPIOO0
hpioo2:					; INTRQ_Wait
		ldx XMCF_SR		; Yes, get the interrupt status
		lda #CF_DCR_IE		; Disable device interrupts until
		sta CF+CF_DCR		;  this DRQ cycle is complete.
		cli			; Allow other interrupts to continue
		txa			;
		bit #XMCF_SR_CFI	; Was there a pending CF interrupt?
		bne hpioo0		; Interrupt pending. Proceed to HPIOO0
		lda #CF_DCR_IE&$00	; Re-enable device interrupts
		sta CF+CF_DCR		;
		clc			; Clear carry to indicate success
		rts			; Return to program while waiting

;==============================================================================
; cmd_done - Reset the command status before returning to HI0
;==============================================================================
cmd_done:	stz ATA_Lock		; Clear the command lock
		jmp hi0			; Return to HI0

;==============================================================================
; check_bsy - Loop until the BSY bit is cleared
; Clobbers .A
;==============================================================================
check_bsy:	bit CF+CF_STAT		; Load the status register
		bpl @Return		; Test the BSY bit (bit 7) return if 0
		jsr set_timeout		; BSY set. Set timer and enter loop.
@BsyLoop:	bit CF+CF_STAT		; Load the status register
		bpl @Return		; Test the BSY bit (bit 7) return if 0
		lda RTC_Uptime		; Get the current second
		cmp ATA_Cmd_Timer	; Is it less than the target?
		bmi @BsyLoop		; Yes, keep checking the status.
		lda RTC_Jiffy		; Get the current Jiffy
		cmp ATA_Cmd_Timer+1	; Is it less than the target?
		bcc @BsyLoop		; Yes, keep checking the status.
		lda ATAFlt::TBSY	; No, timed out. Set the fault code
		jmp error_timeout	;
@Return:	rts			;

;==============================================================================
; check_rdy - Loop until the RDY bit is set
; Clobbers .A
;==============================================================================
check_rdy:	bit CF+CF_STAT		; Load the status register
		bvs @Return		; Test the RDY bit (bit 6) return if 1
		jsr set_timeout		; RDY clear. Set timer and enter loop.
@RdyLoop:	bit CF+CF_STAT		; Load the status register
		bvs @Return		; Test the RDY bit (bit 6) return if 1
		lda RTC_Uptime		; RDY clear, get the current second
		cmp ATA_Cmd_Timer	; Is it less than the target?
		bmi @RdyLoop		; Yes, keep checking the status.
		lda RTC_Jiffy		; Get the current Jiffy
		cmp ATA_Cmd_Timer+1	; Is it less than the target?
		bcc @RdyLoop		; Yes, keep checking the status.
		lda ATAFlt::TRDY	; No, timed out. Set the fault code
		jmp error_timeout	;
@Return:	rts			;

;==============================================================================
; check_drq - Loop until the drq bit is clear
; Clobbers .A
;==============================================================================
check_drq:	lda #CF_STAT_DRQ	; Load the DRQ mask
		bit CF+CF_STAT		; Is DRQ clear?
		beq @Return		; Yes, return.
		jsr set_timeout		; No, set timer and enter loop.
@DrqLoop:	lda #CF_STAT_DRQ	; Load the DRQ mask
		bit CF+CF_STAT		; Is DRQ clear?
		beq @Return		; Yes, return.
		lda RTC_Uptime		; Get the current second
		cmp ATA_Cmd_Timer	; Is it less than the target?
		bmi @DrqLoop		; Yes, keep checking the status.
		lda RTC_Jiffy		; Get the current Jiffy
		cmp ATA_Cmd_Timer+1	; Is it less than the target?
		bcc @DrqLoop		; Yes, keep checking the status.
		lda ATAFlt::TDRQ	; No, timed out. Set the fault code
		bra error_timeout	;
@Return:	rts			;

;==============================================================================
; check_err - Check the Error bit and return.
; If there is an error, diagnostics are collected, the command is terminated,
; and the carry flag is set to indicate an error before returning to the
; program.
;
; Clobbers .A (on success)
;==============================================================================
check_err:	lda CF+CF_STAT			; Load the status register
		bit #CF_STAT_ERR		;
		bne @Error			; Is the Error bit clear?
		rts				; Yes, return.
@Error:		lda ATA_Rejoin			; No, get the ATA process state
		sta ATA_Err+ATAErr::State	;
						; Dump the device registers
		ldx #$06			;
@RegDump:	lda CF+CF_ERR			; Read the register
		sta ATA_Err+ATAErr::DevER,x	; Save it with the error info
		dex				;
		bne @RegDump			; Repeat for all registers
						; Set the fault code
@FindFault:	bit Err_Reg_tbl,x		; Test bit in error register
		bne @SetFault			; If set, leave the loop
		inx				; 
		inx				; Next bit to test
		cpx #$12			; Have they all been checked?
		bcs @FindFault			; No, loop and test another
@SetFault:	lda Err_Reg_tbl+1,x		; Load the paired fault code
		sta ATA_Err+ATAErr::Fault	; Set the fault code
						; Set the rejoin state
@SetRejoin:	lda #ATAStates::HSR0+1		;
		cmp ATA_Rejoin			; Error in a Reset state?
		bcc error_return		; Yes, rejoin at the Reset
		lda #ATAStates::HI0		; No, rejoin at HI0
		sta ATA_Rejoin			;
		bra error_return		;

.segment "RODATA"
; Error register table - error register bits and associated fault codes
Err_Reg_tbl:	.byte CF_ERR_IDNF,	ATAFlt::IDNF	; IDNF fault
		.byte CF_ERR_ABRT,	ATAFlt::ABRT	; ABRT fault
		.byte CF_ERR_UNC,	ATAFlt::UNCO	; UNCO fault
		.byte CF_ERR_BBK,	ATAFlt::BBLK	; BBLK fault
		.byte CF_ERR_AMNF,	ATAFlt::AMNF	; AMNF fault
		.byte $00,		ATAFlt::UERR	; Unknown fault

.segment "CODE"

;==============================================================================
; check_present - Check if the device is physically present
;==============================================================================
check_present:
		lda XMCF_SR		; Load the XMICRO-CF status register
		bit #XMCF_SR_CFCP	; Check CF card is physically present
		bne @NotPresent		;
		rts			; Card present. Return.
@NotPresent:	lda #ATAFlt::CCNP	; Card not present.
		sta ATA_Err+ATAErr::Fault	; Set CCNP fault code
		stz ATA_Irq_Flag	; Disable ATA interrupt servicing
		lda #ATAStates::HHR0	;
		sta ATA_Rejoin		; Set up hardware reset state
		bra error_return	; Return to program

;==============================================================================
; error_dump - A process error has occurred.
; Diagnostics are collected, the command is terminated, and the carry flag is
; set to indicate an error before returning to the program. Uses error_return,
; so this should be entered with JSR to prepare the stack.
;==============================================================================
error_dump:	sta ATA_Err+ATAErr::Fault	; Save the fault code
		lda ATA_Rejoin			;
		sta ATA_Err+ATAErr::State	; Save the ATA process state
		ldx #$06			; Dump the device registers
@RegDump:	lda CF+CF_ERR			; Read the register
		sta ATA_Err+ATAErr::DevER,x	; Save it with the error info
		dex				;
		bne @RegDump			; Repeat for all registers
		lda #ATAStates::HI0		;
		sta ATA_Rejoin			; Set the rejoin state to HI0
		bra error_return		; Return to program

;==============================================================================
; error_timeout - A status check has timed out.
; Diagnostics are collected, the command is terminated, and the carry flag is
; set to indicate an error before returning to the program.
;==============================================================================
error_timeout:	sta ATA_Err+ATAErr::Fault	; Save the fault code
		lda ATA_Rejoin			;
		sta ATA_Err+ATAErr::State	; Save the ATA process state
		lda #ATAStates::HI0		;
		sta ATA_Rejoin			; Set the rejoin state to HI0
;		bra error_return		; Return to program

;==============================================================================
; error_return - Return to the program after an error has occurred
; *Pulls the last address off the stack before returning to the second-last.
;==============================================================================
error_return:	lda ATA_Irq_Flag	; Are interrupts enabled?
		beq @Return		; No, return to program.
		lda #CF_DCR_IE&$00	; Yes, re-enable device interrupts.
		sta CF+CF_DCR		;
@Return:	pla			; Skip returning to ATA process
		pla			;
		sec			; Set carry to indicate fault
		rts			; Return to program

;==============================================================================
; set_timeout - Set the timer target values for a timeout error
;==============================================================================
set_timeout:	pha			;
		clc			;
		lda RTC_Uptime		; Get the current second
		adc #ATA_TIMEOUT	; Add the timeout value
		sta ATA_Cmd_Timer	; Set the timeout target
		lda RTC_Jiffy		; Get the current jiffy
		sta ATA_Cmd_Timer+1	; Set the jiffy target
		pla			;
		rts			;
.endscope

;==============================================================================
; ata_get_lock - Set the ATA command lock, or wait for it to become available
;
; Outputs:
;  C flag	Cleared when successful, set when timed out.
;
; Clobbers .A
;==============================================================================
.proc ata_get_lock
		clc
		lda #$01		; Test and set the lock
		tsb ATA_Lock		; TSB prevents changes between test/set
		beq @Return		; Was it already locked? If not, return
@SetTimer:	lda RTC_Uptime		; Already locked, enter loop
		adc #ATA_TIMEOUT	; Add the timeout value to current sec
		sta ATA_Lock_Timer	; Set the timeout target
		lda RTC_Jiffy		; Get the current jiffy
		sta ATA_Lock_Timer+1	; Set the jiffy target
@LockLoop:	lda #$01		; Test and set the lock
		tsb ATA_Lock		; TSB prevents changes between test/set
		beq @Return		; Was it already locked? If not, return
		lda RTC_Uptime		; Get the current second
		cmp ATA_Lock_Timer	; Is it less than the target?
		bmi @LockLoop		; Yes, keep checking the status.
		lda RTC_Jiffy		; Get the current Jiffy
		cmp ATA_Lock_Timer+1	; Is it less than the target?
		bcc @LockLoop		; Yes, keep checking the status.
		sec			; Timed out. Return with carry set.
@Return:	rts			;
.endproc

;==============================================================================
; ata_rejoin - Re-enter the ATA process state where it left off.
; If interrupts are disabled, the process will return when the command is done.
; If interrupts are enabled, the process will return while waiting.
;
; Inputs
;  ATA_Cmd (Struct)	CF-ATA command parameters
;  ATA_Lock		ATA process lock
;
; Outputs
;  C Flag		Cleared when successful, set indicates a fault
;  ATA_Err		Error information (when C returns set)
;
; Clobbers .AXY
;==============================================================================
.proc ata_rejoin
		ldx ATA_Rejoin		; Load the process return state code
		jmp (ATA_Rejoin_tbl,x)	; Jump to that state

.segment "RODATA"
; ATA Process Rejoin State jump table
ATA_Rejoin_tbl:	.addr ata::hhr0		; Host Hardware Reset
		.addr ata::hsr0		; Host Software Reset
		.addr ata::hi0		; Host bus Idle
		.addr ata::hnd0		; Host Non-Data command
		.addr ata::hpioi0	; Host PIO Data-In command
		.addr ata::hpioo2	; Host PIO Data-Out command

.segment "CODE"
.endproc

.segment "ONCE"
;==============================================================================
; cf_init - Initialize the CompactFlash hardware and ATA process
; Clobbers .AX
;==============================================================================
.proc cf_init
		lda #<cf_isr		; Set ISR hook
		sta ph_CF_ISR		;
		lda #>cf_isr		;
		sta ph_CF_ISR+1		;
		ldx #.sizeof(ATA_Cmd)	; Zero the ATA_Cmd struct
:		stz ATA_Cmd,x		;
		dex			;
		bne :-			;
		jsr ata::hhr0		; ATA process initialization
Return:		rts			;
.endproc

.segment "CODE"
;==============================================================================
; cf_isr - Interrupt service routine for the CompactFlash card
;==============================================================================
.proc cf_isr
		lda ATA_Irq_Flag	;
		bne @Rejoin		; Are CF interrupts enabled/expected?
		lda CF+CF_STAT		; No, clear the card interrupt
		jmp ata_irq_disable	; Disable interrupts and return
@Rejoin:	jsr ata_rejoin		; Yes, rejoin the ATA process
		rts			;
.endproc

;==============================================================================
; ata_irq_enable - Enable interrupt-driven ATA commands
; Clobbers .A
;==============================================================================
.proc ata_irq_enable
		lda #$01		;
		sta ATA_Irq_Flag	; Set the IRQ status flag
		lda CF+CF_STAT		; Clear active interrupts
		stz CF+CF_DCR		; Clear the IE- bit on in the card
		rts			;
.endproc

;==============================================================================
; ata_irq_disable - Disable card interrupts and use polled ATA commands
; Clobbers .A
;==============================================================================
.proc ata_irq_disable
		stz ATA_Irq_Flag	; Clear the IRQ status flag
		lda #CF_DCR_IE		;
		sta CF+CF_DCR		; Set the IE- bit on in the card
		rts			;
.endproc
