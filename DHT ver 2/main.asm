;
; DHT ver 2.asm
;
; Created: 06.05.2016 18:15:40
; Author : Dan
;
; ������ ������ � ������� DHT11 � ���������� � USART
; � �������������� ����� 1 ��� � �������
; ����� ������� ��������� � ����� D, ���� D2, �� ����� DFRduino ��� D2
; USART �������� ����� TX ����� USB TTL �������, ������ ������������ ���������� Windows
; Current State - ������� ������ � �������� ������ ������ ���� �� ������

;==========		DEFINES =======================================
; ����������� ��� �����, � �������� ��������� DHT11			
				.EQU DHT_Port=PORTD
				.EQU DHT_InPort=PIND
				.EQU DHT_Pin=PORTD2
				.EQU DHT_Direction=DDRD
				.EQU DHT_Direction_Pin=DDD2


				.DEF Tmp1=R16
				.DEF USART_ByteR=R17		; ���������� ��� �������� ����� ����� USART
				.DEF Tmp2=R18
				.DEF USART_BytesN=R19		; ���������� - ������� ���� ��������� � USART
				.DEF Tmp3=R20
				.DEF Cycle_Count=R21		; ������� ������ � Expect_X
				.DEF ERR_CODE=R22			; ������� ������ �� ������������
				.DEF N_Cycles=R23			; ������� � READ_CYCLES
				.DEF ACCUM=R24
				.DEF Tmp4=R25
				
			
				
;==========		END DEFINES =======================================

				

;==========		RAM ===============================================
				.DSEG
TEMPER_D:		.byte 20	; ������� "�����������"
HUMID_D:		.byte 20	; ������� "���������"
TEMPER_ASCII:	.byte 5		; ����������� � ASCII
HUMID_ASCII:	.byte 5		; ��������� � ASCII

DEC_TO_CHAR:	.byte 200	; ������� ��� ������� ������������� Dec - ASCII, ��-�� ���� ��� ������....[00]="00"


H10:			.byte 1		; ��c�� - ����� ����� ���������
H01:			.byte 1		; ����� - ������� ����� ���������
T10:			.byte 1		; ����� - ����� ����� ����������� � C
T01:			.byte 1		; ����� - ������� ����� �����������


CRC_SUMM:		.byte 1
CYCLES:			.byte 81	; ����� ��� �������� ����� ������
BITS:			.byte 6		; "����" ���� 2+2+1 CRC TODO - ��������� CRC
ERROR_CODE:		.byte 10


;==========		END RAM =======================


;===========	FLASH START ========================
				.CSEG
				.ORG $000
				RJMP RESET
				.ORG INT_VECTORS_SIZE

;==========		SUBROUTINES ===================

;==========		 USART0 Init ======================
USART0_INIT:	NOP
				.equ	XTAL=16000000
				.equ	baudrate=9600
				.equ	bauddivider=XTAL/(16*baudrate)-1

				LDI Tmp1, Low(bauddivider)		; ���������� �������� ��������
				STS UBRR0L, Tmp1
				LDI Tmp1, High(bauddivider)
				STS UBRR0H, Tmp1

				LDI Tmp1, 0
				STS UCSR0A, Tmp1		; �������� ������� ������

				LDI Tmp1, (1<<TXEN0)|(1<<RXEN0) ; TX, RX ���������, ���������� �� ����������, 
				STS UCSR0B, Tmp1

				LDI Tmp1, (1<<UCSZ01)|(1<<UCSZ00)|(0<<UMSEL00)|(0<<UMSEL01)|(0<<UPM00)|(0<<UPM01)|(0<<USBS0) ; �����������, ��� ��������, 8 ���, 1 ���� 
				STS UCSR0C, Tmp1
				RET

;============	SEND 1 BYTE VIA USART =====================
SEND_BYTE:		NOP
SEND_BYTE_L1:	LDS Tmp1, UCSR0A
				SBRS Tmp1, UDRE0			; ���� ������� ������ ������
				RJMP SEND_BYTE_L1
				STS UDR0, USART_ByteR		; �� ���� ���� �� R17
				NOP
				RET				

;============	SEND CRLF VIA USART ===============================
SEND_CRLF:		LDI USART_ByteR, $0D
				RCALL SEND_BYTE	
				LDI USART_ByteR, $0A
				RCALL SEND_BYTE
				RET			

;============	SEND N BYTES VIA USART ============================
; Y - ��� �����, USART_BytesN - ������� ����
SEND_BYTES:		NOP
SBS_L1:			LD USART_ByteR, Y+
				RCALL SEND_BYTE
				DEC USART_BytesN
				BRNE SBS_L1
				RET				

;============== READ CYCLES ====================================
; ������ ���� ����������� � ��������� � Cycles TODO - ��� ����� �� ��������� � ������!!!
READ_CYCLES:	
				LDI N_Cycles, 80			; ������ 80 ������
READ:			NOP
				RCALL EXPECT_1		; ���������� 0
				ST X+, Cycle_Count			; ��������� ����� ������ 
			
				RCALL EXPECT_0
				ST X+, Cycle_Count		; ��������� ����� ������ 
		
				DEC N_Cycles				; ��������� �������
				BRNE READ
				NOP; ��� ����� �������
				RET

;=============	EXPECT 1 =========================================
; �������� � ����� ���� ������� ��������� �� ����
; ����� ��������� - �������
; �������� ������� ������ �����
; ��� ��������� �� ������ ���� ���� ���� �� ���������
EXPECT_1:		LDI Cycle_Count, 0			; ��������� ������� ������
				LDI ERR_CODE, 2			; ������ 2 - ����� �� ���� Out

				ldi  Tmp1, 2			; ��������� 
				ldi  Tmp2, 169			; �������� 80 us

EXP1L1:			INC Cycle_Count			; ��������� ������� ������

				IN Tmp3, DHT_InPort		; ������ ����
				SBRC Tmp3, DHT_Pin	; ���� 1 
				RJMP EXIT_EXPECT_1	; �� �������
				dec  Tmp2			; ���� ��� �� �������� � ��������
				brne EXP1L1
				dec  Tmp1
				brne EXP1L1
				NOP					; ����� ����� �� ���� out
				RET

EXIT_EXPECT_1:	LDI ERR_CODE, 1			; ������ 1, ��� ���������, � Cycle_Count ������� ������
				RET

;==============	EXPECT 0 =========================================
; �������� � ����� ���� ������� ��������� �� ����
; ����� ��������� - �������
; �������� ������� ������ �����
; ��� ��������� �� ������ ���� ���� ���� �� ���������
EXPECT_0:		LDI Cycle_Count, 0			; ��������� ������� ������
				LDI ERR_CODE, 2			; ������ 2 - ����� �� ���� Out

				ldi  Tmp1, 2			; ��������� 
				ldi  Tmp2, 169			; �������� 80 us

EXP0L1:			INC Cycle_Count				; ��������� ������� ������

				IN Tmp3, DHT_InPort		; ������ ����
				SBRS Tmp3, DHT_Pin		; ���� 0 
				RJMP EXIT_EXPECT_0		; �� �������
				dec  Tmp2
				brne EXP0L1
				dec  Tmp1
				brne EXP0L1
				NOP					; ����� ����� �� ���� out
				RET

EXIT_EXPECT_0:	LDI ERR_CODE, 1			; ������ 1, ��� ���������, � Cycle_Count ������� ������ ���������
				RET

;============	EXPECT 1->0 FALLING EDGE - START DHT11 RESPONSE ==========================
EXPECT_FROM1TO0:NOP
WLOW1:			IN Tmp1, DHT_InPort			; ������ ���� D, ���� low
				SBRC Tmp1, DHT_Pin		; ���� 1 �� �������� �� WLOW, ���� ����, �� ����� ��������.
				RJMP WLOW1
				NOP						; ���� ����� ����� �������� (������������ �����������)
				NOP
				NOP
				;RCALL DELAY_10US		; ���� 10 ����������� � �������
				RET

;============	DHD11 INIT =======================================
; ����� ������������� ����� !!!! ���� ������� ����� ����������� � ���������� ������
DHT_INIT:		CLI	; ��� ���, �� ������ ������ - ��������� �� ������� ������

				; ��������� X ��� ������������� � READ_CYCLES - ��� ��� ������� ����������������
				LDI XH, High(CYCLES)	; ��������� ������� ���� ������ Cycles
				LDI XL, Low (CYCLES)	; ��������� ������� ���� ������ Cycles

				LDI Tmp1, (1<<DHT_Direction_Pin)
				OUT DHT_Direction, Tmp1			; ���� D, ��� 2 �� �����

				LDI Tmp1, (0<<DHT_Pin)
				OUT DHT_Port, Tmp1			; ��������� 0 

				RCALL DELAY_20MS		; ���� 20 �����������

				LDI Tmp1, (1<<DHT_Pin)		; ���������� ����� - ��������� 1
				OUT DHT_Port, Tmp1	

				RCALL DELAY_10US		; ���� 10 �����������

				
				LDI Tmp1, (0<<DHT_Direction_Pin)		; ���� D, Pin 2 �� ����
				OUT DHT_Direction, Tmp1	
				LDI Tmp1,(1<<DHT_Pin)		; ��������� pull-up ���� �� ������ � ������� ���������� �� �����
				OUT DHT_Port, Tmp1		

; ���� ������ �� ������� - �� ������ �������� ����� � ���� �� 80 us � ��������� �� 80 us
; ���� �� ���������� - ������� �� ������ ��� � ���� ���� � ������� - ��� ������ �� �������. TODO - �������

; ����� �� �������� � ������� �� ����
; ������ 40 ��� ������
; ��� ����� 
; ���� �������� � 1 �� 0,
; (�� � ����) � ���������� ������� ����� �� ��������� �������� � 1 - ������ ��� ���� - ������ ����� 50 us
; (�� � �������) ����� ���������� ������� ����� �� �������� � ���� - ������ �������

				RCALL EXPECT_FROM1TO0
				
				RCALL EXPECT_1		; ���������� 0
				;		����� ���� �� ��������� ����� ������  - ������ ����� �����������
				;			
				RCALL EXPECT_FROM1TO0	; � ����� ���� - ������ ���� ����� ����������			
										; ���� ����� �������� ����� ��������� �� ������ �����
				RET

;=============	GET BITS ===============================================
; �� Cycles ������ ����� �  BITS				
GET_BITS:		LDI Tmp1, 5			; ��� ���� ���� - ������� ��������
				LDI Tmp2, 8			; ��� ������� ����
				LDI ZH, High(CYCLES)	; ��������� ������� ���� ������ Cycles
				LDI ZL, Low (CYCLES)	; ��������� ������� ���� ������ Cycles
				LDI YH, High(BITS)	; ��������� ������� ���� ������ BITS
				LDI YL, Low (BITS)	; ��������� ������� ���� ������ BITS

ACC:			LDI ACCUM, 0			; ���������� ����������������
				LDI Tmp2, 8			; ��� ������� ����

TO_ACC:			LSL ACCUM				; �������� �����
				LD Tmp3, Z+			; ������� ������ [i]
				LD Tmp4, Z+			; � ������ � [i+1]
				CP Tmp3, Tmp4			; �������� ������ ��� ���� � ������ �������� ���� ���� ������������ - �� BITS=0, ���� ������������ �� BITS=1
				BRPL J_SHIFT		; ���� ������������ (0) �� ������ �����	
				ORI ACCUM, 1			; ���� ������������ (1) �� �������� 1
J_SHIFT:		DEC Tmp2				; ��������� ��� 8 ���
				BRNE TO_ACC
				ST Y+, ACCUM			; ��������� ����������
				DEC Tmp1				; ��� ���� ����
				BRNE ACC
				RET

;============	GET HnT DATA =========================================
; �� BITS ����������� ����� H10...
; !!! ���� �������, ������ ��� H10 � ������... ����� ��������������� � ������

GET_HnT_DATA:	NOP

				LDI ZH, HIGH(BITS)
				LDI ZL, LOW(BITS)
				LDI XH, HIGH(H10)
				LDI XL, LOW(H10)
												; TODO - ��������� �� ������� ����
				LD Tmp1, Z+			; �������
				ST X+, Tmp1			; ���������
				
				LD Tmp1, Z+			; �������
				ST X+, Tmp1			; ���������

				LD Tmp1, Z+			; �������
				ST X+, Tmp1			; ���������

				LD Tmp1, Z+			; �������
				ST X+, Tmp1			; ���������

				RET

;========		COPY STRINGS TO RAM ==================================
; �������� ������ �� ����� � RAM
COPY_STRINGS:	LDI ZH, HIGH(TEMPER*2)
				LDI ZL, LOW(TEMPER*2)
				LDI XH, HIGH(TEMPER_D)
				LDI XL, LOW(TEMPER_D)
				
				LDI Tmp1, 14		; ��� 14 ����
CP_L1:			LPM Tmp2, Z+		; �� Z 
				ST X+, Tmp2			; � X
				DEC Tmp1
				BRNE CP_L1
				NOP

				LDI ZH, HIGH(HUMID*2)
				LDI ZL, LOW(HUMID*2)
				LDI XH, HIGH(HUMID_D)
				LDI XL, LOW(HUMID_D)
				
				LDI Tmp1, 14		; ��� 14 ����
CP_L2:			LPM Tmp2, Z+
				ST X+, Tmp2
				DEC Tmp1
				BRNE CP_L2
				NOP
				RET

;=============	CREATE DEC_TO_ASCII TABLE ==========================
; ������������ ����� xx � ������ ASCII "xx" �� ������ ������� 
; TODO ���� ���������� �� ������� �� ����� ��� �� ����������� �� ��������
BUILD_DEC_TO_CHAR:	
				NOP

				LDI ZH, HIGH(DEC_TO_CHAR)
				LDI ZL, LOW(DEC_TO_CHAR)

				LDI Tmp1, '0'
				ST Z+, Tmp1
				LDI Tmp1, '0'
				ST Z+, Tmp1

				LDI Tmp1, '0'
				ST Z+, Tmp1
				LDI Tmp1, '1'
				ST Z+, Tmp1

				; � ��� ����� �� "99"

				LDI ZH, HIGH(DEC_TO_CHAR)
				LDI ZL, LOW(DEC_TO_CHAR)

				
				LDI Tmp1, '1'
				STD Z+38, Tmp1
				LDI Tmp1, '9'
				STD Z+38+1, Tmp1

				LDI Tmp1, '2'
				STD Z+40, Tmp1
				LDI Tmp1, '0'
				STD Z+40+1, Tmp1

				LDI Tmp1, '2'
				STD Z+42, Tmp1
				LDI Tmp1, '1'
				STD Z+42+1, Tmp1

				LDI Tmp1, '2'
				STD Z+44, Tmp1
				LDI Tmp1, '2'
				STD Z+44+1, Tmp1

				LDI Tmp1, '2'
				STD Z+46, Tmp1
				LDI Tmp1, '3'
				STD Z+46+1, Tmp1

				LDI Tmp1, '2'
				STD Z+48, Tmp1
				LDI Tmp1, '4'
				STD Z+48+1, Tmp1

				LDI Tmp1, '2'
				STD Z+50, Tmp1
				LDI Tmp1, '5'
				STD Z+50+1, Tmp1

				LDI Tmp1, '2'
				STD Z+52, Tmp1
				LDI Tmp1, '6'
				STD Z+52+1, Tmp1

				LDI Tmp1, '2'
				STD Z+54, Tmp1
				LDI Tmp1, '7'
				STD Z+54+1, Tmp1

				; �������� 50 ���������� STD +k ��� �� ��������
				LDI ZH, HIGH(DEC_TO_CHAR)
				LDI ZL, LOW(DEC_TO_CHAR)

				LDI Tmp3, 50
				ADD R30, Tmp3

				LDI Tmp1, '3'
				STD Z+20, Tmp1
				LDI Tmp1, '5'
				STD Z+20+1, Tmp1

				LDI Tmp1, '3'
				STD Z+22, Tmp1
				LDI Tmp1, '6'
				STD Z+22+1, Tmp1
				
				LDI Tmp1, '3'
				STD Z+24, Tmp1
				LDI Tmp1, '7'
				STD Z+24+1, Tmp1

				LDI Tmp1, '3'
				STD Z+26, Tmp1
				LDI Tmp1, '8'
				STD Z+26+1, Tmp1

				LDI Tmp1, '3'
				STD Z+28, Tmp1
				LDI Tmp1, '9'
				STD Z+28+1, Tmp1

				LDI Tmp1, '4'
				STD Z+30, Tmp1
				LDI Tmp1, '0'
				STD Z+30+1, Tmp1

				RET

;=============	CREATE ASCII DATA
; ������������ ����� xx � ������ ASCII "xx" �� ������ ������� 
HnT_ASCII_DATA:	NOP
				
				LDI Tmp3, 0x00						

				LDI ZH, HIGH(DEC_TO_CHAR)			; ��������� ����� ������� �����������
				LDI ZL, LOW(DEC_TO_CHAR) ; R30

				LDI XH, HIGH(TEMPER_ASCII)			; ��������� ����� ����������� � ASCII
				LDI XL, LOW(TEMPER_ASCII)
				
				LDI YH, HIGH(T10)					; ��������� ����� ����������� � �����
				LDI YL, LOW(T10) 

				LD Tmp3, Y							;  ��������� �����
				LSL Tmp3							; �� ����� ��������� �������� � ������� ��� ������ �����
				ADD R30, Tmp3

				;R30=R30+T10*2

				LD Tmp1, Z+							; ��������� ����� ascii ������ 
				LD Tmp2, Z

				ST X+, Tmp1							; � ��������� �� ����������� � ������ ASCII ������
				ST X+, Tmp2

				LDI Tmp1, '.'						; ����� ���������� � ASCII
				ST X+, Tmp1
				

				LDI Tmp1, '0'						; �� ���� ���� ������ - ������ ��� ����� ����� ������� ���� ������ �� �������
				LDI Tmp2, '0'

				ST X+, Tmp1							; ��������� ����
				ST X+, Tmp2

				; �� �� ����� ��� ������������ ��������� - ������� ������
				LDI XH, HIGH(HUMID_ASCII)
				LDI XL, LOW(HUMID_ASCII)

				LDI ZH, HIGH(DEC_TO_CHAR)
				LDI ZL, LOW(DEC_TO_CHAR) ; R30

				LDI YH, HIGH(H10)
				LDI YL, LOW(H10) 

				LDI Tmp3, 0x00

				LD Tmp3, Y
				LSL Tmp3
				ADD R30, Tmp3

				;R30=R30+H10*2

				LD Tmp1, Z+
				LD Tmp2, Z

				ST X+, Tmp1
				ST X+, Tmp2


				LDI Tmp1, '.'
				ST X+, Tmp1
				LDI Tmp1, '0'
				ST X+, Tmp1
				LDI Tmp1, '0'
				ST X+, Tmp1

				RET				

;=============	CREATE TEST DATA ===================================
; ������� dummy ������ ��� ��������� ������
TEST_DATA:		NOP

				LDI XH, HIGH(TEMPER_ASCII)
				LDI XL, LOW(TEMPER_ASCII)
				LDI Tmp1, '6'
				ST X+, Tmp1
				LDI Tmp1, '7'
				ST X+, Tmp1
				LDI Tmp1, '.'
				ST X+, Tmp1
				LDI Tmp1, '5'
				ST X+, Tmp1
				LDI Tmp1, '1'
				ST X+, Tmp1

				LDI XH, HIGH(HUMID_ASCII)
				LDI XL, LOW(HUMID_ASCII)
				LDI Tmp1, '8'
				ST X+, Tmp1
				LDI Tmp1, '5'
				ST X+, Tmp1
				LDI Tmp1, '.'
				ST X+, Tmp1
				LDI Tmp1, '4'
				ST X+, Tmp1
				LDI Tmp1, '7'
				ST X+, Tmp1

				RET

;=============	DELAY 1200 mil sec ================================
; Delay 19 199 999 cycles
; 1s 199ms 999us 937 1/2 ns
; at 16.0 MHz

DELAY_1200MS:	NOP
				ldi  Tmp1, 98
				ldi  Tmp2, 103
				ldi  Tmp3, 206
DL1:			dec  Tmp3
				brne DL1
				dec  Tmp2
				brne DL1
				dec  Tmp1
				brne DL1
				nop
				RET

;=================================
; Delay 20 ms
; Delay 320 000 cycles
; 20ms at 16 MHz

DELAY_20MS:		ldi  Tmp1, 2
				ldi  Tmp2, 160
				ldi  Tmp3, 147
L20MS1:			dec  Tmp3
				brne L20MS1
				dec  Tmp2
				brne L20MS1
				dec  Tmp1
				brne L20MS1
				nop
				RET

;==================================
; Delay 160 cycles
; 10us at 16.0 MHz
DELAY_10US:		ldi  Tmp1, 53
L10MS1:			dec  Tmp1
				brne L10MS1
				nop
				RET

;========		SUBS END ==========================================


;=============	DATA IN FLASH =====================================
TEMPER:			.db "Temperature = "
HUMID:			.db "   Humidity = "


;============	MAIN
RESET:			NOP		;!!! ������� ����

; Internal Hardware Init
				CLI		; ��� ���������� �� ����� ����
				
				; stack init		
				LDI Tmp1, Low(RAMEND)
				OUT SPL, Tmp1
				LDI Tmp1, High(RAMEND)
				OUT SPH, Tmp1

				RCALL USART0_INIT

				; tests - ���������� A
				;LDI USART_ByteR, 'A'
				;RCALL SEND_BYTE
				;RCALL SEND_CRLF


; Init data
				RCALL COPY_STRINGS		; ����������� ������ � RAM
				RCALL TEST_DATA			; ����������� �������� ������
				RCALL BUILD_DEC_TO_CHAR	; ������� ������� DEC_TO_CHAR

loop:			NOP	
; External Hardware Init
				RCALL DHT_INIT
; �������� ����� ������������� ����������� � ���� � ����� ������ ����
				RCALL READ_CYCLES
				; ��������� �� ������� ������ �����������...
							
				;���� - ��������� Cycles � USART
				/*
				LDI USART_BytesN, 80		; ��� 80 ����
				LDI YH, High(CYCLES)	; ��������� ������� ���� ������ Cycles
				LDI YL, Low (CYCLES)	; ��������� ������� ���� ������ Cycles
				RCALL SEND_BYTES		; � ���������
				
				RCALL SEND_CRLF
				*/

				RCALL GET_BITS
				/*
				;���� - ��������� BITS � USART
				LDI USART_BytesN, 5		; ��� 5 ����
				LDI YH, High(BITS)	; ��������� ������� ���� ������ Cycles
				LDI YL, Low (BITS)	; ��������� ������� ���� ������ Cycles
				RCALL SEND_BYTES		; � ���������

				RCALL SEND_CRLF
				RCALL SEND_CRLF
				*/

				RCALL GET_HnT_DATA
				
				
				;���� - ��������� 4 ����� ������� � H10 � USART
				/*
				LDI USART_BytesN, 4		; ��� 5 ����
				LDI YH, High(H10)	; ��������� ������� ���� ������ Cycles
				LDI YL, Low (H10)	; ��������� ������� ���� ������ Cycles
				RCALL SEND_BYTES		; � ���������
				
				RCALL SEND_CRLF
				*/
				RCALL HnT_ASCII_DATA

;loop:			NOP				
				

				 ; ��������� ������� ����������� (������� � ASCII ������) � USART
				LDI USART_BytesN, 14		; ��� 14 ����
				LDI YH, High(TEMPER_D)	; ��������� ������� ���� ������ Temper
				LDI YL, Low (TEMPER_D)	; ��������� ������� ���� ������ Temper
				RCALL SEND_BYTES
				
				LDI USART_BytesN, 5		; ��� 5 ����
				LDI YH, High(TEMPER_ASCII)	;
				LDI YL, Low (TEMPER_ASCII)	; 
				RCALL SEND_BYTES
				
				 ; ��������� ������� ��������� (������� � ASCII ������) � USART
				LDI USART_BytesN, 14		; ��� 14 ����
				LDI YH, High(HUMID_D)	; ��������� ������� ���� ������ Temper
				LDI YL, Low (HUMID_D)	; ��������� ������� ���� ������ Temper
				RCALL SEND_BYTES

				LDI USART_BytesN, 5		; ��� 5 ����
				LDI YH, High(HUMID_ASCII)	;
				LDI YL, Low (HUMID_ASCII)	; 
				RCALL SEND_BYTES
				
				; ��������� ������ ��� �������				
				RCALL SEND_CRLF
				
				
				RCALL DELAY_1200MS
				rjmp loop		; �����������





;========	END FLASH