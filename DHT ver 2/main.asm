;
; DHT ver 2.asm
;
; Created: 06.05.2016 18:15:40
; Author : Richard Smith
;
; Читаем данные с датчика DHT11 и отправляем в USART
; с периодичностью около 1 раз в секунду
; выход датчика подключен к порту D, нога D2, на плате DFRduino пин D2
; USART работает через TX через USB TTL адаптер, читаем терминальной программой Windows

;==========		DEFINES =======================================
; определения для порта, к которому подключем DHT11			
				.EQU DHT_Port=PORTD
				.EQU DHT_InPort=PIND
				.EQU DHT_Pin=PORTD2
				.EQU DHT_Direction=DDRD
				.EQU DHT_Direction_Pin=DDD2

; регистровые переменные
				.DEF Tmp1=R16
				.DEF USART_ByteR=R17		; регистровая переменная для отправки байта через USART
				.DEF Tmp2=R18
				.DEF USART_BytesN=R19		; регистровая переменная - сколько байт отправить в USART
				.DEF Tmp3=R20
				.DEF Cycles_Counter=R21		; счетчик циклов в Expect_X
				.DEF ERR_CODE=R22			; возврат ошибок из подпрограмм
				.DEF N_Cycles=R23			; счетчик в READ_CYCLES
				.DEF ACCUM=R24
				.DEF Tmp4=R25
					
;==========		END DEFINES =======================================

;==========		RAM ===============================================
				.DSEG
TEMPER_D:		.byte 20	; надпись "температура"
HUMID_D:		.byte 20	; надпись "влажность"
TEMPER_ASCII:	.byte 5		; температура в ASCII
HUMID_ASCII:	.byte 5		; влажность в ASCII
; здесь строгий порядок размещения переменных Hхх, Tхх в пямяти
H10:			.byte 1		; чиcло - целая часть влажность
H01:			.byte 1		; число - дробная часть влажность
T10:			.byte 1		; число - целая часть температура в C
T01:			.byte 1		; число - дробная часть температура
CRC_SUMM:		.byte 1		; TBD
CYCLES:			.byte 82	; буфер для хранения числа циклов
BITS:			.byte 6		; "биты" цифр 2+2+1 CRC TODO - проверить CRC
ERROR_CODE:		.byte 2


;==========		END RAM ============================


;===========	FLASH START ========================
				.CSEG
				.ORG $000
				RJMP RESET
				.ORG INT_VECTORS_SIZE

;==========		SUBROUTINES =======================

;==========		 USART0 Init ======================
USART0_INIT:	NOP
				.equ	XTAL=16000000
				.equ	baudrate=9600
				.equ	bauddivider=XTAL/(16*baudrate)-1

				LDI Tmp1, Low(bauddivider)		; установили скорость передачи
				STS UBRR0L, Tmp1
				LDI Tmp1, High(bauddivider)
				STS UBRR0H, Tmp1

				LDI Tmp1, 0
				STS UCSR0A, Tmp1		; обнулили регистр флагов

				LDI Tmp1, (1<<TXEN0)|(1<<RXEN0) ; TX, RX разрешены, прерывания не используем, 
				STS UCSR0B, Tmp1

				; асинхронный, без четности, 8 бит, 1 Стоп 
				LDI Tmp1, (1<<UCSZ01)|(1<<UCSZ00)|(0<<UMSEL00)|(0<<UMSEL01)|(0<<UPM00)|(0<<UPM01)|(0<<USBS0) 
				STS UCSR0C, Tmp1
				RET

;============	SEND 1 BYTE VIA USART =====================
SEND_BYTE:		NOP
SEND_BYTE_L1:	LDS Tmp1, UCSR0A
				SBRS Tmp1, UDRE0			; если регистр данных пустой
				RJMP SEND_BYTE_L1
				STS UDR0, USART_ByteR		; то шлем байт из регистра USART_ByteR
				NOP
				RET				

;============	SEND CRLF VIA USART ===============================
SEND_CRLF:		LDI USART_ByteR, $0D
				RCALL SEND_BYTE	
				LDI USART_ByteR, $0A
				RCALL SEND_BYTE
				RET			

;============	SEND N BYTES VIA USART ============================
; Y - что слать, USART_BytesN - сколько байт
SEND_BYTES:		NOP
SBS_L1:			LD USART_ByteR, Y+
				RCALL SEND_BYTE
				DEC USART_BytesN
				BRNE SBS_L1
				RET				

;============== READ CYCLES ====================================
; читаем биты контроллера и сохраняем в Cycles 
READ_CYCLES:	
				LDI N_Cycles, 80			; читаем 80 циклов
READ:			NOP
				RCALL EXPECT_1				; Открутился 0
				ST X+, Cycles_Counter		; Сохранили число циклов 
			
				RCALL EXPECT_0
				ST X+, Cycles_Counter		; Сохранили число циклов 
		
				DEC N_Cycles				; уменьшили счетчик
				BRNE READ					
				RET							; все циклы считали

;=============	EXPECT 1 =========================================
; крутимся в цикле ждем нужного состояния на пине
; когда появилось - выходим
; сообщаем сколько циклов ждали
; или сообщение об ошибке тайм оута если не дождались
EXPECT_1:		LDI Cycles_Counter, 0			; загрузили счетчик циклов
				LDI ERR_CODE, 2			; Ошибка 2 - выход по тайм Out

				ldi  Tmp1, 2			; Загрузили 
				ldi  Tmp2, 169			; задержку 80 us

EXP1L1:			INC Cycles_Counter			; увеличили счетчик циклов

				IN Tmp3, DHT_InPort			; читаем порт
				SBRC Tmp3, DHT_Pin			; Если уже 1 
				RJMP EXIT_EXPECT_1			; То выходим
				dec  Tmp2					; если нет то крутимся в задержке
				brne EXP1L1
				dec  Tmp1
				brne EXP1L1
				NOP							; Здесь выход по тайм out
				RET

EXIT_EXPECT_1:	LDI ERR_CODE, 1				; ошибка 1, все нормально, в Cycles_Counter счетчик циклов
				RET

;==============	EXPECT 0 =========================================
; крутимся в цикле ждем нужного состояния на пине
; когда появилось - выходим
; сообщаем сколько циклов ждали
; или сообщение об ошибке тайм оута если не дождались
EXPECT_0:		LDI Cycles_Counter, 0			; загрузили счетчик циклов
				LDI ERR_CODE, 2			; Ошибка 2 - выход по тайм Out

				ldi  Tmp1, 2			; Загрузили 
				ldi  Tmp2, 169			; задержку 80 us

EXP0L1:			INC Cycles_Counter				; увеличили счетчик циклов

				IN Tmp3, DHT_InPort		; читаем порт
				SBRS Tmp3, DHT_Pin		; Если 0 
				RJMP EXIT_EXPECT_0		; То выходим
				dec  Tmp2
				brne EXP0L1
				dec  Tmp1
				brne EXP0L1
				NOP					; Здесь выход по тайм out
				RET

EXIT_EXPECT_0:	LDI ERR_CODE, 1			; ошибка 1, все нормально, в Cycles_Counter сколько циклов насчитали
				RET

;============	EXPECT 1->0 FALLING EDGE - START DHT11 RESPONSE ==========================
EXPECT_FROM1TO0:NOP
WLOW1:			IN Tmp1, DHT_InPort			; читаем порт D, ждем low
				SBRC Tmp1, DHT_Pin			; если 1 то крутимся на WLOW, если ноль, то пошла передача.
				RJMP WLOW1
				NOP							; Типа здесь старт передачи (подтвержение контроллера) - потупим пару тактов
				NOP
				NOP
				;RCALL DELAY_10US		; ждем 10 микросекунд и выходим
				RET

;============	DHD11 INIT =======================================
; после инициализации сразу !!!! надо считать ответ контроллера и собственно данные
DHT_INIT:		CLI	; еще раз, на всякий случай - критичная ко времени секция

				; сохранили X для использования в READ_CYCLES - там нет времени инициализировать
				LDI XH, High(CYCLES)	; загрузили старший байт адреса Cycles
				LDI XL, Low (CYCLES)	; загрузили младший байт адреса Cycles

				LDI Tmp1, (1<<DHT_Direction_Pin)
				OUT DHT_Direction, Tmp1			; порт D, Пин 2 на выход

				LDI Tmp1, (0<<DHT_Pin)
				OUT DHT_Port, Tmp1			; выставили 0 

				RCALL DELAY_20MS		; ждем 20 миллисекунд

				LDI Tmp1, (1<<DHT_Pin)		; освободили линию - выставили 1
				OUT DHT_Port, Tmp1	

				RCALL DELAY_10US		; ждем 10 микросекунд
			
				LDI Tmp1, (0<<DHT_Direction_Pin)		; порт D, Pin 2 на вход
				OUT DHT_Direction, Tmp1	
				LDI Tmp1,(1<<DHT_Pin)		; подтянули pull-up вход на вместе с внешним резистором на линии
				OUT DHT_Port, Tmp1		

; ждем ответа от сенсора - он должен положить линию в ноль на 80 us и отпустить на 80 us
; если не происходит - выходим по ошибке или о тайм ауту с ошибкой - нет ответа от сенсора. TODO - сделать
; потом по переходу с единицы на ноль читаем 40 бит подряд для этого 
; ждем falling edge с 1 на 0, после этого:
; Expect_1 (мы в нуле) И начинанаем считать такты до обратного перехода в 1 - первые пол бита - всегда около 50 us
; Expect_0 (мы в единице) Потом начинанаем считать такты до перехода в ноль - вторые полбита

				RCALL EXPECT_FROM1TO0
				
				RCALL EXPECT_1		; Открутился 0
				;		Здесь надо бы Сохранить число циклов  - первый ответ контроллера
				;			
				RCALL EXPECT_FROM1TO0	; и здесь тоже - второй полу ответ контролера			
										; Здесь старт передачи битов переходим на чтение битов
				RET

;=============	GET BITS ===============================================
; Из Cycles делаем байты в  BITS				
GET_BITS:		LDI Tmp1, 5			; для пяти байт - готовим счетчики
				LDI Tmp2, 8			; для каждого бита
				LDI ZH, High(CYCLES)	; загрузили старший байт адреса Cycles
				LDI ZL, Low (CYCLES)	; загрузили младший байт адреса Cycles
				LDI YH, High(BITS)	; загрузили старший байт адреса BITS
				LDI YL, Low (BITS)	; загрузили младший байт адреса BITS

ACC:			LDI ACCUM, 0			; акамулятор инициализировали
				LDI Tmp2, 8			; для каждого бита

TO_ACC:			LSL ACCUM				; сдвинули влево
				LD Tmp3, Z+			; считали данные [i]
				LD Tmp4, Z+			; о циклах и [i+1]
				CP Tmp3, Tmp4			; сравнить первые пол бита с второй половину бита если положительно - то BITS=0, если отрицительно то BITS=1
				BRPL J_SHIFT		; если положительно (0) то просто сдвиг	
				ORI ACCUM, 1			; если отрицательно (1) то добавили 1
J_SHIFT:		DEC Tmp2				; повторить для 8 бит
				BRNE TO_ACC
				ST Y+, ACCUM			; сохранили акамулятор
				DEC Tmp1				; для пяти байт
				BRNE ACC
				RET

;============	GET HnT DATA =========================================
; из BITS вытаскиваем цифры H10...
; чуть хакнули, потому что H10 и дальше лежат последовательно в памяти

GET_HnT_DATA:	NOP
				LDI ZH, HIGH(BITS)
				LDI ZL, LOW(BITS)
				LDI XH, HIGH(H10)
				LDI XL, LOW(H10)
												; TODO - перевести на счетчик таки
				LD Tmp1, Z+			; Считали
				ST X+, Tmp1			; сохранили
				LD Tmp1, Z+			; Считали
				ST X+, Tmp1			; сохранили
				LD Tmp1, Z+			; Считали
				ST X+, Tmp1			; сохранили
				LD Tmp1, Z+			; Считали
				ST X+, Tmp1			; сохранили
				RET

;========		COPY STRINGS TO RAM ==================================
; копируем строки из флеша в RAM
COPY_STRINGS:	LDI ZH, HIGH(TEMPER*2)
				LDI ZL, LOW(TEMPER*2)
				LDI XH, HIGH(TEMPER_D)
				LDI XL, LOW(TEMPER_D)
				
				LDI Tmp1, 14		; для 14 байт
CP_L1:			LPM Tmp2, Z+		; из Z 
				ST X+, Tmp2			; в X
				DEC Tmp1
				BRNE CP_L1
				NOP

				LDI ZH, HIGH(HUMID*2)
				LDI ZL, LOW(HUMID*2)
				LDI XH, HIGH(HUMID_D)
				LDI XL, LOW(HUMID_D)
				
				LDI Tmp1, 14		; для 14 байт
CP_L2:			LPM Tmp2, Z+
				ST X+, Tmp2
				DEC Tmp1
				BRNE CP_L2
				NOP
				RET

;=============	CREATE ASCII DATA with ITOA
HnT_ASCII_DATA_EX:	
				NOP

				LDI XH, HIGH(TEMPER_ASCII)
				LDI XL, LOW(TEMPER_ASCII)
				
				LDI YH, HIGH(T10)
				LDI YL, LOW(T10) 

				LD Tmp1, Y
				RCALL ITOA_99

				LDI R24, '.'	
				ST X+, R24			; saved  '.' TODO - rebuild with Tmp4

				LDS R24, T01
				;INC R24				; тестовое увеличение дробной части +.01
				STS T01, R24


				LDI YH, HIGH(T01)
				LDI YL, LOW(T01) 

				LD Tmp1, Y
				RCALL ITOA_99
				
				; the same for humid
				LDI XH, HIGH(HUMID_ASCII)
				LDI XL, LOW(HUMID_ASCII)
				
				LDI YH, HIGH(H10)
				LDI YL, LOW(H10) 

				LD Tmp1, Y
				RCALL ITOA_99

				LDI R24, '.'	
				ST X+, R24			; saved  '.' TODO - rebuild with Tmp4

				LDS R24, H01
				;INC R24				; тестовое увеличение дробной части +.01
				STS H01, R24

				LDI YH, HIGH(H01)
				LDI YL, LOW(H01) 

				LD Tmp1, Y
				RCALL ITOA_99
				RET
;=============	CONVERT DEC to ASCII ==============================
; convert DEC stored in Tmp1 to CHAR stored in Tmp2 DEC is 0<=DEC<=99 
ITOA_99:		NOP
				;LDS Tmp1, T10		
				LDI ZL, LOW (DECTAB*2)
				LDI ZH, HIGH  (DECTAB*2)

ITOA_NEXT:		LDI Tmp2, '0'-1
				LPM Tmp3, z+		; загружаем вычитатели 10, 1 ...
								
ITOA_NUM:		INC Tmp2		
				SUB Tmp1, Tmp3				
				BRSH ITOA_NUM

				ADD Tmp1, Tmp3
				ST X+, Tmp2

				CPI Tmp3, 1
				BRNE ITOA_NEXT
				RET


;=============	CREATE TEST DATA ===================================
; создаем dummy данные для тестового вывода
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

;============== Отправить готовую температуру (надпись и ASCII данные) в USART
PRINT_TEMPER:	NOP
				LDI USART_BytesN, 14		; для 14 байт
				LDI YH, High(TEMPER_D)	; загрузили старшйи байт адреса Temper
				LDI YL, Low (TEMPER_D)	; загрузили младший байт адреса Temper
				RCALL SEND_BYTES
				
				LDI USART_BytesN, 5		; для 5 байт
				LDI YH, High(TEMPER_ASCII)	;
				LDI YL, Low (TEMPER_ASCII)	; 
				RCALL SEND_BYTES
				RET

;============== Отправить готовую влажность (надпись и ASCII данные) в USART
PRINT_HUMID:	NOP
				LDI USART_BytesN, 14		; для 14 байт
				LDI YH, High(HUMID_D)	; загрузили старшйи байт адреса Temper
				LDI YL, Low (HUMID_D)	; загрузили младший байт адреса Temper
				RCALL SEND_BYTES

				LDI USART_BytesN, 5		; для 5 байт
				LDI YH, High(HUMID_ASCII)	;
				LDI YL, Low (HUMID_ASCII)	; 
				RCALL SEND_BYTES
				RET

;============== TEST SUBROUTINES =============================

;============== Тест - отправить Cycles в USART
TEST_CYCLES:	NOP
				LDI USART_BytesN, 80		; для 80 байт
				LDI YH, High(CYCLES)	; загрузили старшйи байт адреса Cycles
				LDI YL, Low (CYCLES)	; загрузили младший байт адреса Cycles
				RCALL SEND_BYTES		; И отправили
				RCALL SEND_CRLF
				RET 
				
;============== Тест - отправить BITS в USART==========================
TEST_BITS:		NOP
				LDI USART_BytesN, 5		; для 5 байт
				LDI YH, High(BITS)	; загрузили старшйи байт адреса Cycles
				LDI YL, Low (BITS)	; загрузили младший байт адреса Cycles
				RCALL SEND_BYTES		; И отправили
				RCALL SEND_CRLF
				RET 

;============== Тест - отправить 4 байта начиная с H10 в USART
TEST_H10_T01:	NOP
				LDI USART_BytesN, 4		; для 5 байт
				LDI YH, High(H10)		; загрузили старшйи байт адреса H10
				LDI YL, Low (H10)		; загрузили младший байт адреса H10
				RCALL SEND_BYTES		; оно лежит в памиьти подряд и отправили
				RCALL SEND_CRLF
				RET

;========		SUBS END ==========================================


;=============	DATA IN FLASH =====================================
TEMPER:			.db "Temperature = "
HUMID:			.db "   Humidity = "
DECTAB:			.db	10,1,0,0			; используется для конверсии DEC to ASCII


;============	MAIN
				;!!! Главный вход
RESET:			NOP		

				; Internal Hardware Init
				CLI		; нам прерывания не нужны пока
				
				; stack init		
				LDI Tmp1, Low(RAMEND)
				OUT SPL, Tmp1
				LDI Tmp1, High(RAMEND)
				OUT SPH, Tmp1

				RCALL USART0_INIT

				; Init data
				RCALL COPY_STRINGS		; скопировали данные в RAM
				RCALL TEST_DATA			; подготовили тестовые данные

loop:			NOP						; крутисся в вечном цикле ....
				; External Hardware Init
				RCALL DHT_INIT
				; получили здесь подтверждение контроллера и надо в темпе читать биты
				RCALL READ_CYCLES
				; критичная ко времени секция завершилась...
				
				;Тест - отправить Cycles в USART		
				;RCALL TEST_CYCLES
				
				; получаем из посылки биты
				RCALL GET_BITS
				
				;Тест - отправить BITS в USART
				;RCALL TEST_BITS  
				
				; получаем из BITS цифровые данные
				RCALL GET_HnT_DATA
				
				;Тест - отправить 4 байта начиная с H10 в USART
				;RCALL TEST_H10_T01
				
				; подготовидли температуру и влажность в ASCII		
				RCALL HnT_ASCII_DATA_EX
				
				; Отправить готовую температуру (надпись и ASCII данные) в USART
				RCALL PRINT_TEMPER
				; Отправить готовую влажность (надпись и ASCII данные) в USART
				RCALL PRINT_HUMID
				; переведем строку дял красоты				
				RCALL SEND_CRLF
							
				RCALL DELAY_1200MS				;повторяем каждые 1.2 секунды 
				rjmp loop		; зациклились

;========	END FLASH

