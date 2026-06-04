; MagSort - sorts objects by whether they have a magnet or not
; STM32F4, ARM assembly
;
; PA0 = IR sensor (goes LOW when something is placed on the platform)
; PA1 = Hall sensor (HIGH if magnet detected)
; PA5 = LED that tells the user the object was seen
; PA6 = LED that tells the user a magnet was found
; PA8 = servo PWM
;
; Timing is done by counting servo pulses - each pulse is 20ms,
; so 50 pulses = 1 second. 

		AREA MYCODE, CODE, READONLY
        EXPORT __main

; register addresses from the STM32F4 reference manual
RCC_AHB1ENR  EQU 0x40023830
GPIOA_MODER  EQU 0x40020000
GPIOA_IDR    EQU 0x40020010
GPIOA_ODR    EQU 0x40020014

; servo pulse widths - these are loop counts, not milliseconds.
; calibrated by trial and error against the actual servo.
SERVO_0DEG    EQU 1000       ; 0 degrees (was 3000, pulled back slightly for more range)
SERVO_90DEG   EQU 6000       ; 90 degrees center, unchanged
SERVO_180DEG  EQU 10000      ; 180 degrees (was 9000, +1000 more tilt)
SERVO_PERIOD  EQU 80000      ; full 20ms period, never changes

; delay values in number of pulses (1 pulse = 20ms)
DELAY_1SEC    EQU 50         ; Hall sensor needs a moment to settle
DELAY_3SEC    EQU 150        ; enough time for the user to pull their hand back
DELAY_5SEC    EQU 250        ; holds the tilt while the object slides off
DELAY_2SEC5   EQU 125        ; cooldown so it doesn't re-trigger immediately

__main

; GPIOA clock is off by default, have to enable it before touching any pins
        LDR R0, =RCC_AHB1ENR
        LDR R1, [R0]
        ORR R1, R1, #1
        STR R1, [R0]

; set pin directions - 2 bits per pin in MODER, 00=input 01=output
; BIC clears both bits first so we don't accidentally set 11 (analog mode)
        LDR R0, =GPIOA_MODER
        LDR R1, [R0]
        BIC R1, R1, #(3 << 0)   ; PA0 input  - IR sensor
        BIC R1, R1, #(3 << 2)   ; PA1 input  - Hall sensor
        BIC R1, R1, #(3 << 10)  ; PA5 output - IR LED
        ORR R1, R1, #(1 << 10)
        BIC R1, R1, #(3 << 12)  ; PA6 output - Hall LED
        ORR R1, R1, #(1 << 12)
        BIC R1, R1, #(3 << 16)  ; PA8 output - Servo
        ORR R1, R1, #(1 << 16)
        STR R1, [R0]

; move to center on startup so we know where we're starting from
        MOV R6, #50
CENTER_SERVO
        LDR R5, =SERVO_90DEG
        BL  SERVO_PULSE
        SUBS R6, R6, #1
        BNE  CENTER_SERVO


; WAIT FOR OBJECT
; just sits here polling PA0 until something breaks the IR beam

WAIT_FOR_OBJECT
        LDR R0, =GPIOA_IDR
        LDR R1, [R0]

        TST R1, #(1 << 0)
        BEQ OBJECT_DETECTED     ; PA0 goes LOW when object is present (active-LOW sensor)

        ; nothing there - keep LEDs off and hold at 90
        LDR R0, =GPIOA_ODR
        LDR R2, [R0]
        BIC R2, R2, #(1 << 5)
        BIC R2, R2, #(1 << 6)
        STR R2, [R0]
        LDR R5, =SERVO_90DEG
        BL  SERVO_PULSE
        B   WAIT_FOR_OBJECT


; OBJECT DETECTED
; light the IR LED right away so the user gets feedback,
; then wait for them to move their hand before we do anything

OBJECT_DETECTED
        LDR R0, =GPIOA_ODR
        LDR R2, [R0]
        ORR R2, R2, #(1 << 5)  ; IR LED on - "we saw it"
        STR R2, [R0]

        ; 3 seconds for the user to get their hand clear
        MOV R6, #DELAY_3SEC
HAND_REMOVAL_WAIT
        LDR R5, =SERVO_90DEG
        BL  SERVO_PULSE
        SUBS R6, R6, #1
        BNE  HAND_REMOVAL_WAIT

        ; extra second for the Hall sensor to settle on the stationary object
        MOV R6, #DELAY_1SEC
HALL_SETTLE_WAIT
        LDR R5, =SERVO_90DEG
        BL  SERVO_PULSE
        SUBS R6, R6, #1
        BNE  HALL_SETTLE_WAIT

        ; now read Hall sensor and decide which way to sort
        LDR R0, =GPIOA_IDR
        LDR R1, [R0]
        TST R1, #(1 << 1)
        BNE HALL_ON             ; PA1 HIGH = magnet found
        B   HALL_OFF            ; PA1 LOW  = no magnet


; HALL ON - magnet detected, tilt to 180

HALL_ON
        LDR R0, =GPIOA_ODR
        LDR R2, [R0]
        ORR R2, R2, #(1 << 6)  ; Hall LED on so we know which path it took
        STR R2, [R0]

        MOV R6, #DELAY_5SEC
HOLD_180
        LDR R5, =SERVO_180DEG
        BL  SERVO_PULSE
        SUBS R6, R6, #1
        BNE  HOLD_180
        B   RESET_AND_WAIT


; HALL OFF - no magnet, tilt to 0

HALL_OFF
        LDR R0, =GPIOA_ODR
        LDR R2, [R0]
        BIC R2, R2, #(1 << 6)  ; make sure Hall LED is off
        STR R2, [R0]

        MOV R6, #DELAY_5SEC
HOLD_0
        LDR R5, =SERVO_0DEG
        BL  SERVO_PULSE
        SUBS R6, R6, #1
        BNE  HOLD_0

; RESET - back to center, LEDs off, brief cooldown then loop

RESET_AND_WAIT
        MOV R6, #50
BACK_TO_90
        LDR R5, =SERVO_90DEG
        BL  SERVO_PULSE
        SUBS R6, R6, #1
        BNE  BACK_TO_90

        LDR R0, =GPIOA_ODR
        LDR R2, [R0]
        BIC R2, R2, #(1 << 5)  ; IR LED off
        BIC R2, R2, #(1 << 6)  ; Hall LED off
        STR R2, [R0]

        ; short cooldown so it doesn't immediately retrigger on the same object
        MOV R6, #DELAY_2SEC5
COOLDOWN
        LDR R5, =SERVO_90DEG
        BL  SERVO_PULSE
        SUBS R6, R6, #1
        BNE  COOLDOWN

        B   WAIT_FOR_OBJECT


; SERVO_PULSE - generates one 20ms PWM cycle on PA8
;
; R5 controls how long PA8 stays HIGH (the pulse width = the angle).
; The rest of the 20ms is LOW. Servo reads the ratio and moves accordingly.
; Called with BL so LR needs to be saved.

SERVO_PULSE
        PUSH {R5, R6, LR}

        LDR R0, =GPIOA_ODR
        LDR R2, [R0]
        ORR R2, R2, #(1 << 8)  ; PA8 HIGH - start of pulse
        STR R2, [R0]

        MOV R3, R5              ; count down for the high portion
HIGH_WAIT
        SUBS R3, R3, #1
        BNE  HIGH_WAIT

        LDR R0, =GPIOA_ODR
        LDR R2, [R0]
        BIC R2, R2, #(1 << 8)  ; PA8 LOW - end of pulse
        STR R2, [R0]

        LDR R3, =SERVO_PERIOD
        SUB R3, R3, R5          ; low time = total period minus high time
LOW_WAIT
        SUBS R3, R3, #1
        BNE  LOW_WAIT

        POP {R5, R6, PC}        ; return

        END
