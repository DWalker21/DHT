;
; DHT ver 2.asm
;
; Created: 06.05.2016 18:15:40
; Author : Dan
;
; Читаем данные с датчика DHT11 и отправляем в USART
; с периодичностью около 1 раз в секунду
; выход датчика подключен к порту D, нога D2, на плате DFRduino пин D2
; USART работает через TX через USB TTL адаптер, читаем терминальной программой Windows
; Current State - выводим строки и тестовые данные датчик пока не читали

;==========		DEFINES =======================================
; определения для порта, к которому подключем DHT11			
				.EQU DHT_Port=PORTD
				.EQU DHT_InPort=PIND
				.EQU DHT_Pin=PORTD2
				.EQU DHT_Direction=DDRD
				.EQU DHT_Direction_Pin=DDD2


				.DEF Tmp1=R16
				.DEF USART_ByteR=R17		; переменная для отправки байта через USART
				.DEF Tmp2=R18
				.DEF USART_BytesN=R19		; переменная - сколько байт отправить в USART
				.DEF Tmp3=R20
				.DEF Cycle_Count=R21		; счетчик циклов в Expect_X
				.DEF ERR_CODE=R22			; возврат ошибок из подпрограммы
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

DEC_TO_CHAR:	.byte 200	; таблица для прямого преобраования Dec - ASCII, че-то лень мне делить....[00]="00"


H10:			.byte 1		; чиcло - целая часть влажность
H01:			.byte 1		; число - дробная часть влажность
T10:			.byte 1		; число - целая часть температура в C
T01:			.byte 1		; число - дробная часть температура


CRC_SUMM:		.byte 1
CYCLES:			.byte 81	; буфер для хранения числа циклов
BITS:			.byte 6		; "биты" цифр 2+2+1 CRC TODO - проверить CRC
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

				LDI Tmp1, Low(bauddivider)		; установили скорость передачи
				STS UBRR0L, Tmp1
				LDI Tmp1, High(bauddivider)
				STS UBRR0H, Tmp1

				LDI Tmp1, 0
				STS UCSR0A, Tmp1		; обнулили регистр флагов

				LDI Tmp1, (1<<TXEN0)|(1<<RXEN0) ; TX, RX разрешены, прерывания не используем, 
				STS UCSR0B, Tmp1

				LDI Tmp1, (1<<UCSZ01)|(1<<UCSZ00)|(0<<UMSEL00)|(0<<UMSEL01)|(0<<UPM00)|(0<<UPM01)|(0<<USBS0) ; асинхронный, без четности, 8 бит, 1 Стоп 
				STS UCSR0C, Tmp1
				RET

;============	SEND 1 BYTE VIA USART =====================
SEND_BYTE:		NOP
SEND_BYTE_L1:	LDS Tmp1, UCSR0A
				SBRS Tmp1, UDRE0			; если регистр данных пустой
				RJMP SEND_BYTE_L1
				STS UDR0, USART_ByteR		; то шлем байт из R17
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
; читаем биты контроллера и сохраняем в Cycles TODO - где здесь мы стреляеям в память!!!
READ_CYCLES:	
				LDI N_Cycles, 80			; читаем 80 циклов
READ:			NOP
				RCALL EXPECT_1		; Открутился 0
				ST X+, Cycle_Count			; Сохранили число циклов 
			
				RCALL EXPECT_0
				ST X+, Cycle_Count		; Сохранили число циклов 
		
				DEC N_Cycles				; уменьшили счетчик
				BRNE READ
				NOP; все циклы считали
				RET

;=============	EXPECT 1 =========================================
; крутимся в цикле ждем нужного состояния на пине
; когда появилось - выходим
; сообщаем сколько циклов ждали
; или сообщение об ошибке тайм оута если не дождались
EXPECT_1:		LDI Cycle_Count, 0			; загрузили счетчик циклов
				LDI ERR_CODE, 2			; Ошибка 2 - выход по тайм Out

				ldi  Tmp1, 2			; Загрузили 
				ldi  Tmp2, 169			; задержку 80 us

EXP1L1:			INC Cycle_Count			; увеличили счетчик циклов

				IN Tmp3, DHT_InPort		; читаем порт
				SBRC Tmp3, DHT_Pin	; Если 1 
				RJMP EXIT_EXPECT_1	; То выходим
				dec  Tmp2			; если нет то крутимся в задержке
				brne EXP1L1
				dec  Tmp1
				brne EXP1L1
				NOP					; Здесь выход по тайм out
				RET

EXIT_EXPECT_1:	LDI ERR_CODE, 1			; ошибка 1, все нормально, в Cycle_Count счетчик циклов
				RET

;==============	EXPECT 0 =========================================
; крутимся в цикле ждем нужного состояния на пине
; когда появилось - выходим
; сообщаем сколько циклов ждали
; или сообщение об ошибке тайм оута если не дождались
EXPECT_0:		LDI Cycle_Count, 0			; загрузили счетчик циклов
				LDI ERR_CODE, 2			; Ошибка 2 - выход по тайм Out

				ldi  Tmp1, 2			; Загрузили 
				ldi  Tmp2, 169			; задержку 80 us

EXP0L1:			INC Cycle_Count				; увеличили счетчик циклов

				IN Tmp3, DHT_InPort		; читаем порт
				SBRS Tmp3, DHT_Pin		; Если 0 
				RJMP EXIT_EXPECT_0		; То выходим
				dec  Tmp2
				brne EXP0L1
				dec  Tmp1
				brne EXP0L1
				NOP					; Здесь выход по тайм out
				RET

EXIT_EXPECT_0:	LDI ERR_CODE, 1			; ошибка 1, все нормально, в Cycle_Count сколько циклов насчитали
				RET

;============	EXPECT 1->0 FALLING EDGE - START DHT11 RESPONSE ==========================
EXPECT_FROM1TO0:NOP
WLOW1:			IN Tmp1, DHT_InPort			; читаем порт D, ждем low
				SBRC Tmp1, DHT_Pin		; если 1 то крутимся на WLOW, если ноль, то пошла передача.
				RJMP WLOW1
				NOP						; Типа здесь старт передачи (подтвержение контроллера)
				NOP
				NOP
				;RCALL DELAY_10US		; ждем 10 микросекунд и выходим
				RET

;============	DHD11 INIT =======================================
; после инициализации сразу !!!! надо считать ответ контроллера и собственно данные
DHT_INIT:		CLI	; еще раз, на всякий случай - критичная ко времени секция

				; сохранили X для использования в READ_CYCLES - там нет времени инициализировать
				LDI XH, High(CYCLES)	; загрузили старшйи байт адреса Cycles
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

; потом по переходу с единицы на ноль
; читаем 40 бит подряд
; для этого 
; ждем перехода с 1 на 0,
; (мы в нуле) И начинанаем считать такты до обратного перехода в 1 - первые пол бита - всегда около 50 us
; (мы в единице) Потом начинанаем считать такты до перехода в ноль - вторые полбита

				RCALL EXPECT_FROM1TO0
				
				RCALL EXPECT_1		; Открутился 0
				;		Здесь надо бы Сохранить число циклов  - первый ответ контроллера
				;			
				RCALL EXPECT_FROM1TO0	; и здесь тоже - второй полу ответ контролера			
										; Типа старт передачи битов переходим на чтение битов
				RET

;=============	GET BITS ===============================================
; Из Cycles делаем байты в  BITS				
GET_BITS:		LDI Tmp1, 5			; для пяти байт - готовим счетчики
				LDI Tmp2, 8			; для каждого бита
				LDI ZH, High(CYCLES)	; загрузили старшйи байт адреса Cycles
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
; !!! чуть хакнули, потому что H10 и дальше... лежат последовательно в памяти

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

;=============	CREATE DEC_TO_ASCII TABLE ==========================
; конвертируем цифры xx в строки ASCII "xx" на основе таблицы 
; TODO надо переделать на таблицу во флеше или на конвертация по разрадям
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

				; и так далее до "99"

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

				; прибавим 50 посклольку STD +k уже не хвататет
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
; конвертируем цифры xx в строки ASCII "xx" на основе таблицы 
HnT_ASCII_DATA:	NOP
				
				LDI Tmp3, 0x00						

				LDI ZH, HIGH(DEC_TO_CHAR)			; загрузили адрес таблицы конвератции
				LDI ZL, LOW(DEC_TO_CHAR) ; R30

				LDI XH, HIGH(TEMPER_ASCII)			; загрузили адрес температуры в ASCII
				LDI XL, LOW(TEMPER_ASCII)
				
				LDI YH, HIGH(T10)					; загрузили адрес температуры в цифре
				LDI YL, LOW(T10) 

				LD Tmp3, Y							;  загрузили цифрц
				LSL Tmp3							; по цифре расчитали смещение в таблицы где строки лежат
				ADD R30, Tmp3

				;R30=R30+T10*2

				LD Tmp1, Z+							; загрузили байты ascii строки 
				LD Tmp2, Z

				ST X+, Tmp1							; и сохранили на постояннную в шаблон ASCII вывода
				ST X+, Tmp2

				LDI Tmp1, '.'						; точке десятичная в ASCII
				ST X+, Tmp1
				

				LDI Tmp1, '0'						; на нули пока забьем - датчик все равно после запятой пока ничего не выдавал
				LDI Tmp2, '0'

				ST X+, Tmp1							; засторили нули
				ST X+, Tmp2

				; то же самое для показатедлей влажности - таблица единая
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

;========		SUBS END ==========================================


;=============	DATA IN FLASH =====================================
TEMPER:			.db "Temperature = "
HUMID:			.db "   Humidity = "


;============	MAIN
RESET:			NOP		;!!! Главный вход

; Internal Hardware Init
				CLI		; нам прерывания не нужны пока
				
				; stack init		
				LDI Tmp1, Low(RAMEND)
				OUT SPL, Tmp1
				LDI Tmp1, High(RAMEND)
				OUT SPH, Tmp1

				RCALL USART0_INIT

				; tests - отправляем A
				;LDI USART_ByteR, 'A'
				;RCALL SEND_BYTE
				;RCALL SEND_CRLF


; Init data
				RCALL COPY_STRINGS		; скопировали данные в RAM
				RCALL TEST_DATA			; подготовили тестовые данные
				RCALL BUILD_DEC_TO_CHAR	; создали таблицу DEC_TO_CHAR

loop:			NOP	
; External Hardware Init
				RCALL DHT_INIT
; получили здесь подтверждение контроллера и надо в темпе читать биты
				RCALL READ_CYCLES
				; критичная ко времени секция завершилась...
							
				;Тест - отправить Cycles в USART
				/*
				LDI USART_BytesN, 80		; для 80 байт
				LDI YH, High(CYCLES)	; загрузили старшйи байт адреса Cycles
				LDI YL, Low (CYCLES)	; загрузили младший байт адреса Cycles
				RCALL SEND_BYTES		; И отправили
				
				RCALL SEND_CRLF
				*/

				RCALL GET_BITS
				/*
				;Тест - отправить BITS в USART
				LDI USART_BytesN, 5		; для 5 байт
				LDI YH, High(BITS)	; загрузили старшйи байт адреса Cycles
				LDI YL, Low (BITS)	; загрузили младший байт адреса Cycles
				RCALL SEND_BYTES		; И отправили

				RCALL SEND_CRLF
				RCALL SEND_CRLF
				*/

				RCALL GET_HnT_DATA
				
				
				;Тест - отправить 4 байта начиная с H10 в USART
				/*
				LDI USART_BytesN, 4		; для 5 байт
				LDI YH, High(H10)	; загрузили старшйи байт адреса Cycles
				LDI YL, Low (H10)	; загрузили младший байт адреса Cycles
				RCALL SEND_BYTES		; И отправили
				
				RCALL SEND_CRLF
				*/
				RCALL HnT_ASCII_DATA

;loop:			NOP				
				

				 ; Отправить готовую температуру (надпись и ASCII данные) в USART
				LDI USART_BytesN, 14		; для 14 байт
				LDI YH, High(TEMPER_D)	; загрузили старшйи байт адреса Temper
				LDI YL, Low (TEMPER_D)	; загрузили младший байт адреса Temper
				RCALL SEND_BYTES
				
				LDI USART_BytesN, 5		; для 5 байт
				LDI YH, High(TEMPER_ASCII)	;
				LDI YL, Low (TEMPER_ASCII)	; 
				RCALL SEND_BYTES
				
				 ; Отправить готовую влажность (надпись и ASCII данные) в USART
				LDI USART_BytesN, 14		; для 14 байт
				LDI YH, High(HUMID_D)	; загрузили старшйи байт адреса Temper
				LDI YL, Low (HUMID_D)	; загрузили младший байт адреса Temper
				RCALL SEND_BYTES

				LDI USART_BytesN, 5		; для 5 байт
				LDI YH, High(HUMID_ASCII)	;
				LDI YL, Low (HUMID_ASCII)	; 
				RCALL SEND_BYTES
				
				; переведем строку дял красоты				
				RCALL SEND_CRLF
				
				
				RCALL DELAY_1200MS
				rjmp loop		; зациклились





;========	END FLASH