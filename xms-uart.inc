;==============================================================================
; xms-uart.inc
; Dependencies: xms.inc
;==============================================================================

.ifndef _UART_INC_			; Don't allow multiple includes
_UART_INC_ = 1

.ifndef _UART_NOIMPORTS_			; Skip imports

.import uart_init			; Startup routine
.import uart_interrupt			; Interrupt Routine
.import uart_rx, uart_tx, uart_rx_check	; Procedures

.endif

.include "xms.inc"

;==============================================================================
; Module Configuration
;==============================================================================
UART		= UART2			; Functions will use UART2
UART_Hook	= ph_UART2_ISR		; Use ISR hook for UART2

;==============================================================================
; UART Constants
;==============================================================================
; General Registers
UART_RHR		= $00		; Receive Holding Register(R)
UART_THR		= $00		; Transmit Holding Register (W)
UART_IER		= $01		; Interrupt Enable Register (R/W)
UART_ISR		= $02		; Interrupt Status Register (R)
UART_FCR		= $02		; FIFO Control Register (W)
UART_LCR		= $03		; Line Control Register (R/W)
UART_MCR		= $04		; Modem Control Register (R/W)
UART_LSR		= $05		; Line Status Register (R)
UART_MSR		= $06		; Modem Status Register (R)
UART_SPR		= $07		; Scratchpad Register (R/W)

; Baud Rate Generator Registers (Accessible only whhen LCR Bit-7 is set to 1)
UART_DLL		= $00		; Divisor Latch LSB (R/W)
UART_DLM		= $01		; Divisor Latch MSB (R/W)

; Baud Rate Generator Values (for UART_DL)
UART_BG_50		= $0900		; 50 baud
UART_BG_75		= $0600		; 75 baud
UART_BG_150		= $0300		; 150 baud
UART_BG_300		= $0180		; 300 baud
UART_BG_600		= $00C0		; 600 baud
UART_BG_1200		= $0060		; 1200 baud
UART_BG_2400		= $0030		; 2400 baud
UART_BG_4800		= $0018		; 4800 baud
UART_BG_7200		= $0010		; 7200 baud
UART_BG_9600		= $000C		; 9600 baud
UART_BG_14400		= $0008		; 14.4k baud
UART_BG_19200		= $0006		; 19.2k baud
UART_BG_28800		= $0004		; 28.8k baud
UART_BG_38400		= $0003		; 38.4k baud
UART_BG_57600		= $0002		; 57.6k baud
UART_BG_115200		= $0001		; 115.2k baud

; Interrupt Enable Register Bits
UART_IER_MSI		= %00001000	; Modem Status Interrupt
UART_IER_RLSI		= %00000100	; Receive Line Status Interrupt
UART_IER_THR		= %00000010	; Transmit Holding Register Interrupt
UART_IER_RHR		= %00000001	; Receive Holding Register Interrupt

; FIFO Control Register Bits
UART_FCR_RT		= %11000000	; FIFO Receive trigger level
UART_FCR_DMS		= %00001000	; DMA mode select
UART_FCR_TFR		= %00000100	; Transmit FIFO Reset
UART_FCR_RFR		= %00000010	; Reveive FIFO Reset
UART_FCR_FE		= %00000001	; FIFO Enable

; FIFO Trigger Level Values (for UART_FCR_RT)
UART_FIFO_TRIG_1	= %00000000	; 1 byte
UART_FIFO_TRIG_4	= %01000000	; 4 bytes
UART_FIFO_TRIG_8	= %10000000	; 8 bytes
UART_FIFO_TRIG_14	= %11000000	; 14 bytes

; Interrupt Status Register Bits
UART_ISR_FE		= %11000000	; FIFOs Enabled
UART_ISR_IP		= %00001110	; Interrupt Priority
UART_ISR_IS		= %00000001	; Interrupt Status

; Interrupt Source Values (for UART_ISR_IP)
UART_ISRC_LSR		= %00000110	; LSR (Receiver Line Status Register)
UART_ISRC_RDR		= %00000100	; RXRDY (Received Data Ready)
UART_ISRC_RDT		= %00001100	; RXRDY (Received Data Timeout)
UART_ISRC_TRE		= %00000010	; TXRDY (Transmitter Holding Register empty)
UART_ISRC_MSR		= %00000000	; MSR (Modem Status Register)

; Line Control Register Bits
UART_LCR_DLE		= %10000000	; Divisor Latch Enable
UART_LCR_SBK		= %01000000	; Set Break
UART_LCR_SP		= %00100000	; Set Parity
UART_LCR_EP		= %00010000	; Even Parity
UART_LCR_PE		= %00001000	; Parity Enable
UART_LCR_SB		= %00000100	; Stop Bits
UART_LCR_WL		= %00000011	; Word Length

; Word Length Values (for UART_LCR_WL)
UART_WL_5		= %00000000	; 5 bits
UART_WL_6		= %00000001	; 6 bits
UART_WL_7		= %00000010	; 7 bits
UART_WL_8		= %00000011	; 8 bits

; Modem Control Register Bits
UART_MCR_LE		= %00010000	; Loopback Enable
UART_MCR_OP2		= %00001000	; OP2 Output (inverted)
UART_MCR_OP1		= %00000100	; OP1 Output (inverted)
UART_MCR_RTS		= %00000010	; RTS Output
UART_MCR_DTR		= %00000001	; DTR Output

; Line Status Register Bits
UART_LSR_FDE		= %10000000	; FIFO Data Error
UART_LSR_TE		= %01000000	; Transmit Empty
UART_LSR_THE		= %00100000	; Transmit Holding register Empty
UART_LSR_BI		= %00010000	; Break Interrupt
UART_LSR_FE		= %00001000	; Framing Error
UART_LSR_PE		= %00000100	; Parity Error
UART_LSR_OE		= %00000010	; Overrun Error
UART_LSR_RDR		= %00000001	; Receive Data Ready

; Modem Status Register Bits
UART_MSR_CD		= %10000000	; Carrier Detect input
UART_MSR_RI		= %01000000	; Ring Indicator input
UART_MSR_DSR		= %00100000	; Data Set Ready input
UART_MSR_CTS		= %00010000	; Clear to Send input
UART_MSR_DCD		= %00001000	; CD changed since last read
UART_MSR_DRI		= %00000100	; RI changed since last read
UART_MSR_DDSR		= %00000010	; DSR changed since last read
UART_MSR_DCTS		= %00000001	; CTS changed since last read


;==============================================================================
; Structs
;==============================================================================
.struct UARTInit
	LCR	.byte


.endstruct

.endif