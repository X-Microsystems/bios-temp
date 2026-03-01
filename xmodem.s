;==============================================================================
; xmodem.s
; XMODEM-CRC sender/receiver
; Adapted from http://www.6502.org/source/io/xmodem/xmodem.htm
; Original by Daryl Rictor Aug 2002
;==============================================================================

;**************************************************************************
; This implementation of XMODEM/CRC does NOT conform strictly to the 
; XMODEM protocol standard in that it (1) does not accurately time character
; reception or (2) fall back to the Checksum mode.

; (1) For timing, it uses a crude timing loop to provide approximate
; delays.  These have been calibrated against a 1MHz CPU clock.  I have
; found that CPU clock speed of up to 5MHz also work but may not in
; every case.  Windows HyperTerminal worked quite well at both speeds!
;
; (2) Most modern terminal programs support XMODEM/CRC which can detect a
; wider range of transmission errors so the fallback to the simple checksum
; calculation was not implemented to save space.
;**************************************************************************
;
; Files transferred via XMODEM-CRC will have the load address and size
; contained in a four-byte header at the beginning of the file. Values are
; in little-endian format:
;  FIRST BLOCK
;     offset(0) = load start address (low)
;     offset(1) = load start address (high)
;     offset(2) = file size (low)
;     offset(3) = file size (high)
;     offset(4) = data byte (0)
;     offset(n) = data byte (n-4)
;
; Subsequent blocks
;     offset(n) = data byte (n)
;
; XMODEM sends data in 128-byte blocks. When sending, if the end of the data
; is reached before the end of the XMODEM block, then the last block will be
; padded with the value $1A.
;
; When receiving, data will be written to the location and size specified in
; the header. Because of this, the padding characters will not be written to
; memory when receiving. However, if the file size is set to $0000 (or greater
; than the length of the following data), then all following data will be
; written to memory, including padding characters added by the sender.
;

.include "crc.inc"
.include "xmcf-rtc.inc"
.include "xms-uart.inc"

Get_Chr		=	uart_rx_check
Put_Chr		=	uart_tx

.export xmodem_tx, xmodem_rx
.export p_Xmodem_Addr, Xmodem_Size

; XMODEM Control Character Constants
SOH		= $01			; start block
EOT		= $04			; end of text marker
ACK		= $06			; good block acknowledged
NAK		= $15			; bad block acknowledged
CAN		= $18			; cancel (not standard, not supported)
CR		= $0d			; carriage return
LF		= $0a			; line feed
ESC		= $1b			; ESC to exit

; Variables
.segment "ZEROPAGE"
p_Xmodem_Addr:	.res 2			; Start address and data pointer

.segment "DATA"
lastblk:	.res 1			; flag for last block
blkno:		.res 1			; block number 
errcnt:		.res 1			; error counter 10 is the limit
bflag:		.res 1			; block flag 
crc:		.res 2			; CRC
eofp:		.res 2			; end-of-file address pointer
Timeout:	.res 1			; Seconds to wait before timing out
Timer_Jiffy:	.res 1			; RTC jiffy counter target value
Timer_Second:	.res 1			; RTC seconds target value

Xmodem_Size:	.res 2			; Number of bytes to transfer
Rbuff		= $DD00			; temp 132 byte receive buffer 
					;(place anywhere, page aligned)
.segment "CODE"

;==============================================================================
; xmodem_tx
; Sends a file via XMODEM
;
; Inputs
;  p_Xmodem_Addr (2 bytes)	Data start address
;  Xmodem_Size			Number of bytes to send
;
; Clobbers .AXY, p_Xmodem_Addr
;==============================================================================
.proc xmodem_tx
		jsr PrintMsg		; send prompt and info
		lda #$00		;
		sta errcnt		; error counter set to 0
		sta lastblk		; set flag to false
		lda #$01		;
		sta blkno		; set block # to 1
		clc			; Calculate the end address from the size
		lda p_Xmodem_Addr		;
		adc Xmodem_Size		;
		sta eofp		;
		lda p_Xmodem_Addr+1	;
		adc Xmodem_Size+1	;
		sta eofp+1		;
		lda eofp		; Decrement the end-of-file address
		bne :+			; because size is not 0-indexed
		dec eofp+1		;
:		dec eofp		;
Wait4CRC:	lda #$03		; 3 seconds
		jsr get_byte		;
		bcc Wait4CRC		; wait for something to come in...
		cmp #'C'		; is it the "C" to start a CRC xfer?
		beq SetstAddr		; yes
		cmp #ESC		; is it a cancel? <Esc> Key
		bne Wait4CRC		; No, wait for another character
		jmp PrtAbort		; Print abort msg and exit
SetstAddr:	ldy #$00		; init data block offset to 0
		ldx #$06		; preload X to Receive buffer
		lda #$01		; manually load blk number	
		sta Rbuff		; into 1st byte
		lda #$FE		; load 1's comp of block #	
		sta Rbuff+1		; into 2nd byte
		lda p_Xmodem_Addr		; load low byte of start address		
		sta Rbuff+2		; into 3rd byte	
		lda p_Xmodem_Addr+1	; load hi byte of start address		
		sta Rbuff+3		; into 4th byte
		lda Xmodem_Size		; Load filesize low byte
		sta Rbuff+4		; Into 5th byte
		lda Xmodem_Size+1	; Load filesize high byte
		sta Rbuff+5		; Into 6th byte
		bra LdBuff1		; jump into buffer load routine
LdBuffer:	lda lastblk		; Was the last block sent?
		beq LdBuff0		; no, send the next one	
		stz errcnt		; Yes, we're done. Reset error counter
		jmp SendEOT		; and close out the transfer
LdBuff0:	ldx #$02		; init pointers
		ldy #$00		;
		inc blkno		; inc block counter
		lda blkno		; 
		sta Rbuff		; save in 1st byte of buffer
		eor #$FF		; 
		sta Rbuff+1		; save 1's comp of blkno next
LdBuff1:	lda (p_Xmodem_Addr),y	; save 128 bytes of data
		sta Rbuff,x		;
LdBuff2:	sec			; 
		lda eofp		;
		sbc p_Xmodem_Addr		; Are we at the last address?
		bne LdBuff4		; no, inc pointer and continue
		lda eofp+1		;
		sbc p_Xmodem_Addr+1	;
		bne LdBuff4		; 
		inc lastblk		; Yes, Set last byte flag
LdBuff3:	inx			;
		cpx #$82		; Are we at the end of the 128 byte block?
		beq SCalcCRC		; Yes, calc CRC
		lda #$1A		; Fill rest of 128 bytes with $00
		sta Rbuff,x		;
		bra LdBuff3		; Loop
LdBuff4:	inc p_Xmodem_Addr		; Inc address pointer
		bne LdBuff5		;
		inc p_Xmodem_Addr+1	;
LdBuff5:	inx			;
		cpx #$82		; last byte in block?
		bne LdBuff1		; no, get the next
SCalcCRC:	jsr CalcCRC
		lda crc+1		; save Hi byte of CRC to buffer
		sta Rbuff,y		;
		iny			;
		lda crc			; save lo byte of CRC to buffer
		sta Rbuff,y		;
Resend:		ldx #$00		;
		lda #SOH
		jsr Put_Chr		; send SOH
SendBlk:	lda Rbuff,x		; Send 132 bytes in buffer to the console
		jsr Put_Chr		;
		inx			;
		cpx #$84		; last byte?
		bne SendBlk		; no, get next
		lda #$03		; yes, set 3 second delay 
		jsr get_byte		; Wait for Ack/Nack
		bcc Seterror		; No chr received after 3 seconds, resend
		cmp #ACK		; Chr received... is it:
		beq LdBuffer		; ACK, send next block
		cmp #NAK		; 
		beq Seterror		; NAK, inc errors and resend
		cmp #ESC		;
		beq PrtAbort		; Esc pressed to abort
					; fall through to error counter
Seterror:	inc errcnt		; Inc error counter
		lda errcnt		; 
		cmp #$0A		; are there 10 errors? (Xmodem spec)
		bne Resend		; no, resend block
PrtAbort:	jsr Flush		; yes, too many errors, flush buffer,
		jmp Print_Err		; print error msg and exit
SendEOT:	lda errcnt		; Check the error count
		cmp #$0A		;
		bne :+			;
		jmp Print_Err		; Too many errors, abort transfer.
:		lda #EOT		; 
		jsr Put_Chr		; Send an EOT and wait for an ACK
WaitForAck:	lda #$03		; set loop counter for 3 sec delay
		jsr get_byte		; get response
		bcs :+
		inc errcnt		; Timed out. Inc error count and retry
		bra SendEOT
:		cmp #ACK		; Got a response, check if it's an ACK
		beq Done
Done:		rts
		jmp Print_Good		; All Done..Print msg and exit
.endproc

;==============================================================================
; xmodem_rx
; Receives a file via XMODEM.
; Destination address and size are specified in the received header block.
;
; Clobbers .AXY, p_Xmodem_Addr, Xmodem_Size
;==============================================================================
.proc xmodem_rx
		jsr PrintMsg		; send prompt and info
		lda #$01
		sta blkno		; set block # to 1
		sta bflag		; set flag to get address from block 1
StartCrc:	lda #'C'		; "C" start with CRC mode
		jsr Put_Chr		; send it
		lda #$00
		sta crc
		sta crc+1		; init CRC value	
		lda #$01		; set loop counter for 1 sec delay
		jsr get_byte		; wait for input
		bcs GotByte		; byte received, process it
		bcc StartCrc		; resend "C"

StartBlk:	lda #$03		; set loop counter for 3 sec delay
		jsr get_byte		; get first byte of block
		bcc StartBlk		; timed out, keep waiting...
GotByte:	cmp #ESC		; quitting?
		bne GotByte1		; no
;		lda #$FE		; Error code in "A" of desired
		brk			; YES - do BRK or change to RTS if desired
GotByte1:	cmp #SOH		; start of block?
		beq BegBlk		; yes
		cmp #EOT		;
		bne BadCrc		; Not SOH or EOT, so flush buffer & send NAK	
		jmp RDone		; EOT - all done!
BegBlk:		ldx #$00
GetBlk:		lda #$03		; 3 sec window to receive characters
GetBlk1:	jsr get_byte		; get next character
		bcc BadCrc		; chr rcv error, flush and send NAK
GetBlk2:	sta Rbuff,x		; good char, save it in the rcv buffer
		inx			; inc buffer pointer	
		cpx #$84		; <01> <FE> <128 bytes> <CRCH> <CRCL>
		bne GetBlk		; get 132 characters
		ldx #$00		;
		lda Rbuff,x		; get block # from buffer
		cmp blkno		; compare to expected block #	
		beq GoodBlk1		; matched!
		jsr Print_Err		; Unexpected block number - abort	
		jsr Flush		; mismatched - flush buffer and then do BRK
;		lda #$FD		; put error code in "A" if desired
		brk			; unexpected block # - fatal error - BRK or RTS
GoodBlk1:	eor #$ff		; 1's comp of block #
		inx			;
		cmp Rbuff,x		; compare with expected 1's comp of block #
		beq GoodBlk2 		; matched!
		jsr Print_Err		; Unexpected block number - abort	
		jsr Flush		; mismatched - flush buffer and then do BRK
;		lda #$FC		; put error code in "A" if desired
		brk			; bad 1's comp of block#	
GoodBlk2:	jsr CalcCRC		; calc CRC
		lda Rbuff,y		; get hi CRC from buffer
		cmp crc+1		; compare to calculated hi CRC
		bne BadCrc		; bad crc, send NAK
		iny			;
		lda Rbuff,y		; get lo CRC from buffer
		cmp crc			; compare to calculated lo CRC
		beq GoodCrc		; good CRC
BadCrc:		jsr Flush		; flush the input port
		lda #NAK		;
		jsr Put_Chr		; send NAK to resend block
		jmp StartBlk		; start over, get the block again			
GoodCrc:	ldx #$02		;
		lda blkno		; get the block number
		cmp #$01		; 1st block?
		bne CopyBlk		; no, copy all 128 bytes
		lda bflag		; is it really block 1, not block 257, 513 etc.
		beq CopyBlk		; no, copy all 128 bytes
		lda Rbuff,x		; get target address from 1st 2 bytes of blk 1
		sta p_Xmodem_Addr		; save lo address
		inx			;
		lda Rbuff,x		; get hi address
		sta p_Xmodem_Addr+1	; save it
		inx			;
		lda Rbuff,x		; Get file size from next 2 bytes of blk 1
		sta Xmodem_Size		; Save file size low
		clc
		adc p_Xmodem_Addr		; Calculate the end-of-file address low
		sta eofp
		inx			;
		lda Rbuff,x		; Get file size high
		sta Xmodem_Size+1	; Save it
		adc p_Xmodem_Addr+1	; Calculate the end-of-file address high
		sta eofp+1
		inx			; point to first byte of data
		dec bflag		; set the flag so we won't get another address		
CopyBlk:	ldy #$00		; set offset to zero
CopyBlk2:	
		sec			;
		lda eofp		;
		sbc p_Xmodem_Addr		; Are we at the last address?
		bne CopyBlk3		; No, copy another byte
		lda eofp+1		;
		sbc p_Xmodem_Addr+1	;
		beq IncBlk		; Yes, stop copying data.
CopyBlk3:	lda Rbuff,x		; get data byte from buffer
		sta (p_Xmodem_Addr),y	; save to target
		inc p_Xmodem_Addr		; point to next address
		bne CopyBlk4		; did it step over page boundary?
		inc p_Xmodem_Addr+1	; adjust high address for page crossing
CopyBlk4:	inx			; point to next data byte
		cpx #$82		; is it the last byte
		bne CopyBlk2		; no, get the next one
IncBlk:		inc blkno		; done.  Inc the block #
		lda #ACK		; send ACK
		jsr Put_Chr		;
		jmp StartBlk		; get next block

RDone:		lda #ACK		; last block, send ACK and exit.
		jsr Put_Chr		;
		jsr Flush		; get leftover characters, if any
		jsr Print_Good		;
		rts			;
.endproc

;
; input chr from ACIA (no waiting)
;
;Get_Chr:	clc			; no chr present
;              	lda	ACIA_Status     ; get Serial port status
;              	and	#$08            ; mask rcvr full bit
;              	beq	Get_Chr2	; if not chr, done
;              	Lda	ACIA_Data       ; else get chr
;	       	sec			; and set the Carry Flag
;Get_Chr2:    	rts			; done
;
; output to OutPut Port
;
;Put_Chr:   	PHA                     ; save registers
;Put_Chr1:     	lda	ACIA_Status     ; serial port status
;              	and	#$10            ; is tx buffer empty
;              	beq	Put_Chr1        ; no, go back and test it again
;              	PLA                     ; yes, get chr to send
;              	sta	ACIA_Data       ; put character to Port
;              	RTS                     ; done
;==============================================================================



;==============================================================================
; Misc. Subroutines
;==============================================================================
;==============================================================================
; get_byte
; Get a byte from the serial port. Times out after specified time
;
; Inputs
;  .A	Timeout in seconds
;
; Outputs
;  .A	Received data byte
;==============================================================================
get_byte:	jsr Get_Chr		; First attempt to get a byte
		bcs Return		; If successful, skip timeout & return
SetTimeout:	adc RTC_Uptime		; Add .A to the current uptime
		sta Timer_Second	; This is the 1s digit we're aiming for
		lda RTC_Jiffy+1		; Get the RTC jiffy count (high)
		sta Timer_Jiffy		; This is the jiffy we're aiming for
Loop:		jsr Get_Chr		; get chr from serial port, don't wait 
		bcs Return		; got one, so exit
		lda RTC_Uptime		;! Load current uptime (low)
		cmp Timer_Second	;! Compare with the timeout value
		bne Loop		;! Loop if we're not there
		lda Timer_Jiffy		; If it matches, check the jiffy
		cmp RTC_Jiffy+1		;
		bcs Loop		; Loop if the jiffy is lower
Return:		rts			;

Flush:		lda #$01		; flush until empty for 1 sec.
Flush1:		jsr get_byte		; read the port
		bcs Flush		; if chr recvd, wait for another
		rts			; else done

PrintMsg:	ldx #$00		; PRINT starting message
PrtMsg1:	lda Msg,x		;
		beq PrtMsg2		;	
		jsr Put_Chr		;
		inx			;
		bne PrtMsg1		;
PrtMsg2:	rts			;
		.BYTE CR, LF
Msg:		.byte "Begin XMODEM transfer. Press <Esc> to abort..."
		.BYTE CR, LF
               	.byte 0

Print_Err:	ldx #$00		; PRINT Error message
PrtErr1:	lda ErrMsg,x		;
		beq PrtErr2		;
		jsr Put_Chr		;
		inx			;
		bne PrtErr1		;
PrtErr2:	rts			;
ErrMsg:		.byte "Transfer Error!"
		.BYTE CR, LF
                .byte 0

Print_Good:	ldx #$00		; PRINT Good Transfer message
Prtgood1:	lda GoodMsg,x		;
		beq Prtgood2		;
		jsr Put_Chr		;
		inx			;
		bne Prtgood1		;
Prtgood2:	rts			;
GoodMsg:	.byte "Transfer Successful!"
		.BYTE CR, LF
                .byte 0

;==============================================================================
; CalcCRC
; Calculate the 16-bit CRC for the contents of the data buffer
; 
; Returns
;  crc (2 bytes)
;
; Clobbers .AXY
;==============================================================================
.proc CalcCRC
		lda #$00		; Initialize the CRC value
		sta crc			;
		sta crc+1		;
		ldy #$02		;
CalcCRC1:	lda Rbuff,y		;
		eor crc+1 		; Quick CRC computation with lookup tables
       		tax		 	; updates the two bytes at crc & crc+1
       		lda crc			; with the byte send in the "A" register
       		eor crc16_table_h,x	;
       		sta crc+1		;
      	 	lda crc16_table_l,x	;
       		sta crc			;
		iny			;
		cpy #$82		; done yet?
		bne CalcCRC1		; no, get next
		rts			; y=82 on exit
.endproc