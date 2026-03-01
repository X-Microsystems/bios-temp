;==============================================================================
; xms.inc
;==============================================================================

.ifndef _XMS_INC_				; Don't allow multiple includes
_XMS_INC_ = 1

.ifndef _XMS_NOIMPORTS_				; Skip imports

.import xms_init				; Startup routine
.import xms_isr					; Interrupt Routine
.import ph_UART1_ISR, ph_UART2_ISR, ph_PS2_ISR	; ISR hook locations

.endif

;==============================================================================
; XMICRO-SERIAL Card Constants
;==============================================================================
; XMICRO-SERIAL hardware addresses
.import __XMICRO_SERIAL_START__, __XMICRO_SERIAL_VECTOR__
XMS		= __XMICRO_SERIAL_START__	; Card base address
UART1		:= XMS+$00			; UART1 base address
UART2		:= XMS+$08			; UART2 base address
PS2_DATA	:= XMS+$10			; PS/2 Data Register (R/W)
XMS_SR		:= XMS+$11			; XMICRO-SERIAL Status Register (R)

; XMICRO-SERIAL Pointers
XMS_VECTOR	:= __XMICRO_SERIAL_VECTOR__	; XMICRO-SERIAL interrupt vector location

; XMICRO-SERIAL Status Register Bits
XMS_SR_UI1		= %10000000	; UART1 interrupt status
XMS_SR_UI2		= %01000000	; UART2 interrupt status
XMS_SR_PDR		= %00100000	; PS/2 Data Ready
XMS_SR_PER		= %00010000	; PS/2 parity error
XMS_SR_PWS		= %00001000	; PS/2 Write in-progress status

.endif