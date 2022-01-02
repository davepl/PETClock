;-----------------------------------------------------------------------------------
; Large Text Clock for CBM/PET 6502
;-----------------------------------------------------------------------------------
; (c) Dave Plummer, 12/26/2016. If you can read it, you can use it!
;-----------------------------------------------------------------------------------

.cpu 6502
.OBJFILE  <petclock.obj>
.LISTFILE <petclock.lst>
.LISTOFF  SOURCE
.LISTOFF  INCLUDES

; Definitions -----------------------------------------------------------------------

PET             = 1
DEBUG           = 1					; Enable code that only is included for debug builds
EPROM           = 0					; When TRUE, no BASIC stub, no load address in file

DEVICE_NUM      = 9

.INCLUDE "pet.inc"
.INCLUDE "basic4.inc"

.if EPROM
    BASE		.equ $B000		; Open PET ROM space
.else
    BASE		.equ $0401		; PET Start of BASIC
.endif

; System Locations ------------------------------------------------------------------

SCREEN_MEM  = $8000
JIFFY_TIMER = $008F

; Our Definitions -------------------------------------------------------------------

zptmp = $BD
zptmpB = $00
zptmpC = $1F

.org 826							; Second cassette buffer on PET

; These are scratch variables - they are here in the cassette buffer so that we can
; be burned into ROM (if we just used .byte we couldn't write values back)

ScratchStart     
   ClockCount    .ds  2             ; 16 bit countup timer to move clock to avoid screen burn
   ClockXPos     .ds  1             ; Current cursor X pos of clock
   ClockYPos	 .ds  1             ; Current cursor Y pos of clock
   ClockX		 .ds  1             ; Temp X for clock draw code
   ClockY		 .ds  1             ; Temp Y for clock draw code
   temp			 .ds  1             ; General scratch variable
   bitmask		 .ds  1             ; Bitmask to use to walk through character bitmap row
   bitcount		 .ds  1             ; Count of which row we're on in bitmap character
   tempchar		 .ds  1	            ; Scratch variable
   MultiplyTemp	 .ds  1             ; Scratch variable for multiply code
   ResultLo		 .ds  1				; Results from multiply operations
   ResultHi		 .ds  1             
ScratchEnd		 

; This is where we store the time

ClockStart		 
   HourTens		 .ds  1             ; Various parts of the clock, in text like ASCII '0'
   HourDigits	 .ds  1
   MinTens		 .ds  1
   MinDigits	 .ds  1	
   SecTens		 .ds  1
   SecDigits	 .ds  1
   Tenths		 .ds  1
ClockEnd

; This is the structure we read the petSD+ clock into for parsing

DeviceBufferStart
    DevResponse     .equ *             ; 2017-01-09t12:34:56 mon
    ClkYear         .ds  4
    ClkDash1        .ds  1
    ClkMonth        .ds  2
    ClkDash2        .ds  1
    ClkDay          .ds  2
    ClkLetterT      .ds  1
    ClkHourTens     .ds  1
    ClkHourDigits   .ds  1
    ClkColon1       .ds  1
    ClkMinTens      .ds  1
    ClkMinDigits    .ds  1
    ClkColon2       .ds  1
    ClkSecTens      .ds  1
    ClkSecDigits    .ds  1
    ClkSpace1       .ds  1
    ClkDayOfWeek    .ds  3
DeviceBufferEnd

.assert DeviceBufferEnd - DeviceBufferStart == 23   ; Verify length of struct matches fixed RTC format
.assert $ <= 1000					                ; Make sure we haven't run off the end of the buffer

; Start of Binary -------------------------------------------------------------------

.org  $0000							
                 
.if !EPROM
  .word BASE	; If a program file, binary starts with 16 bit load address
.endif
.org  BASE      ; Binary loads at 0x0401 on the PET

; BASIC program to load and execute ourselves.  Simple lines of tokenized BASIC that
; have a banner comment and then a SYS command to start the machine language code.

.if !EPROM
Line10			.word Line20						; Next line number
                .word 10							; Line Number 10		
                .byte TK_REM						; REM token
                .string "ARKABLE CLOCK BY DAVEPL (C) 2017", 00

Line20			.word endOfBasic					; PTR to next line, which is 0000
                .word 20							; Line Number 20
                .byte TK_SYS						;   SYS token
                .string " "
                .string str$(*+7)					; Entry is 7 bytes from here, which is
                                                    ;  not how I'd like to do it but you cannot
                                                    ;  use a forward reference in STR$()

                .byte 00							; Do not modify without understanding 
endOfBasic		.word 00							;   the +7 expression above, as this is
.endif												;   exactly 7 bytes and must match it

;-----------------------------------------------------------------------------------
; Start of Code
;-----------------------------------------------------------------------------------

start			cld
                jsr InitVariables       ; Since we can be in ROM, zero stuff out

MainLoop		jsr UpdateClock
                ldy ClockYPos			
                ldx ClockXPos
                jsr DrawClockXY

InnerLoop		jsr UpdateClockPos      ; Carry will be clear when its time 
                bcs MainLoop            ;    to check keyboard and move clock

                jsr GETIN				; Keyboard Handling - check for input
                cmp #0
                beq InnerLoop

                cmp #$03
                bne notEscape
                beq ExitApp				; Escape pressed, go to exit

notEscape		cmp #$48				
                bne @notHour
                jsr IncrementHour		; H pressed, increment hour
                jmp MainLoop

@notHour		cmp #$C8
                bne @notHourDn
                jsr DecrementHour		; SHIFT-H pressed, decrement hour
                jmp MainLoop

@notHourDn		cmp #$4D
                bne @notMin
                jsr IncrementMinute		; M pressed, increment minute
                jmp MainLoop

@notMin			cmp #$CD
                bne @notMinDn
                jsr DecrementMinute		; SHIFT-M pressed, decrement minute
                jmp MainLoop

@notMinDn		jsr ShowInstructions	; Any other key shows the help text
                jmp InnerLoop			;  which gets erased after a few seconds

ExitApp			
.if DEBUG
                ldy #>hello				; Output load text and exit
                lda #<hello
                jsr WriteLine
.endif
                rts

;-----------------------------------------------------------------------------------
; InitVariables	
;-----------------------------------------------------------------------------------
; We use a bunch of storage in the system (on the PET, it's Cassette Buffer #2) and
; it starts out in an unknown state, so we have code to zero it or set it to defaults
;-----------------------------------------------------------------------------------

InitVariables	ldx #ScratchEnd-ScratchStart
                lda #$00							; Init variables to #0
-				sta ScratchStart, x
                dex
                cpx #$ff
                bne -

                ldx #ClockEnd-ClockStart			; Init all clock digits to '0'
                lda #'0'
-				sta ClockStart, x
                dex
                cpx #$ff
                bne -

;-----------------------------------------------------------------------------------
; UpdateClockPos - Moves the clock around on the screen so that it doesn't burn 
;                  into the phosophor quite so much.  Doesn't use the bottom 3
;                  rows so that we always have somewhere for instructions.
;
; Carry flag if set indicated on return that the clock has moved
;-----------------------------------------------------------------------------------

UpdateClockPos
                inc ClockCount			; Increment the low byte of counter
                bne @nomove
                inc ClockCount+1		; Increment the high byte 
                lda ClockCount+1
                cmp #200				; If high byte hasn't reached 200, a suitable delay, nothing to do
                bne @nomove
                 
                lda #$0					; Reset wait timer to zero
                sta ClockCount 
                sta ClockCount+1

                lda JIFFY_TIMER
                and #3
                sta ClockXPos
    
                inc ClockYPos
                lda ClockYPos
                cmp #15					; Don't go lower than this to leave room for instructions
                bne @donemove
                lda #0
                sta ClockYPos
@donemove
                sec
                rts

@nomove			clc
                rts

;-----------------------------------------------------------------------------------
; ConvertPetSCII - Convert .string ASCI to PET screen code		
;                  Apprently not a complete conversion but it works for my purposes
;-----------------------------------------------------------------------------------

ConvertPetSCII	sta temp
                lda #%00100000
                bit temp
                bvc +
                beq +
                lda temp
                and #%10011111
                rts
+				lda temp
                rts

;-----------------------------------------------------------------------------------
; ShowInstructions - Print the help banner on the bottom three rows
;-----------------------------------------------------------------------------------
 
ShowInstructions
                lda #$00						; Reset timer counter so banner will stay up a few seconds
                sta ClockCount
                sta ClockCount+1

                lda #<(SCREEN_MEM + 22 * 40)	; Place instructions at line 22-25 of the screen
                sta zptmp
                lda #>(SCREEN_MEM + 22 * 40)
                sta zptmp+1
                ldy #0
@loop			lda Instructions,y
                beq @done
                jsr ConvertPetSCII				; Our text is in ASCII, convert to PET screen codes
@output			sta (zptmp),y
                iny
                bne @loop
@done			rts

;-----------------------------------------------------------------------------------
; UpdateClock - Pulls the current time of day from the hardware
;-----------------------------------------------------------------------------------

UpdateClock     
                ldx #<CommandText
                ldy #>CommandText
                ;jsr SendCommand         ; Fetch time from Real Time Clock on petSD+
                jsr SetFakeResponse
                ;jsr GetDeviceStatus

                lda ClkHourTens
                sta HourTens
                lda ClkHourDigits
                sta HourDigits
                lda ClkMinTens
                sta MinTens
                lda ClkMinDigits
                sta MinDigits
                lda ClkSecTens
                sta SecTens
                lda ClkSecDigits
                sta SecDigits

                ; We don't want 24-hour time, so fix it up if needed

                lda HourTens            
                cmp #'0'                ; If the TENS digit is 0, nothing to do 
                beq ZeroInTens          

                cmp #'2'
                beq TwoInTens                
                lda HourDigits          

                cmp #'3'                ; If the ONES digit is < 3, nothing to do
                bcc +
BackUpTwelve    dec HourTens            ; But otherwise we back up 12 hours

                dec HourDigits
                dec HourDigits
ZeroInTens      rts

TwoInTens       cmp #'2'                ; If Ones digit is < 2, subtract 20 and add 8
		bcc AddEight            ; Otherwise, backup 10 and backup 2 hours
		jmp BackUpTwelve
		
AddEight        lda #'0'                ; To go back 12 hours we zero the
                sta HourTens            ;  tens portion and add 8 to the digits
                lda HourDigits
	        clc
                adc #8
                sta HourDigits
                rts

FakeResponse    .string "2017-01-09t21:34:56 MON", 0

;----------------------------------------------------------------------------
; SendCommand
;----------------------------------------------------------------------------
; Sends a command to an IEEE device
;----------------------------------------------------------------------------

CommandText     .string "T-RI",0        ; Command to read RTC in the petSD+

SendCommand     stx zptmpC
                sty zptmpC+1

	            lda #DEVICE_NUM         ; Device 8 or 9, etc
	            sta DN
	            lda #$6f			    ; DATA SA 15 (Must have $#60 or'd in)
	            sta SA
	            jsr LISTN   		    ; LISTEN
	            lda SA
	            jsr SECND       		; send secondary address
                ldy #0
-               lda (zptmpC), y
                beq @done
	            jsr CIOUT           	; send char to IEEE
                iny
                bne -

@done:
            	jsr UNLSN               ; Unlisten
                rts

;----------------------------------------------------------------------------
; GetDeviceStatus
;----------------------------------------------------------------------------
; Reads the response back from the device.   In our case the device is the
; petSD+ and we've sent it a "t-ti" command to read the clock.  The clock 
; comes back in the following fixed format:
;
; 2017-01-09t18:20:54 mon
; 0123456789012345678
;----------------------------------------------------------------------------

GetDeviceStatus    

	            lda #DEVICE_NUM
	            sta DN
	            jsr TALK    			; TALK
	            lda #$6f			    ; DATA SA 15
	            sta SA
	            jsr SECND               ; send secondary address
                ldy #$00
-
                phy
	            jsr ACPTR       	    ; read byte from IEEE bus
                ply
	            cmp #CR				    ; last byte = CR?
	            beq @done
	            sta DevResponse, y
                iny
	            jmp -		            ; branch always
@done:          lda #$00
                sta DevResponse, y   ; null terminate the buffer instead of CR
	            jsr UNTLK   		    ; UNTALK
	            rts

;-----------------------------------------------------------------------------------
; Increment/Decrement Hour/Minute
;
; Allows the user to step the hours or minutes up and down and to have the 00 roll
; under to 59, allows 59 to roll over to 00, and so on.  Handles the 12:59 -> 1:00
; overflow and underflow properly.
;-----------------------------------------------------------------------------------

IncrementMinute
                inc MinDigits
                lda #'9'+1
                cmp MinDigits
                bne doneHour
                lda #'0'
                sta MinDigits
                inc MinTens
                lda #'5'+1
                cmp MinTens
                bne doneHour
                lda #'0'
                sta MinTens
                ; fall through to increment hour

IncrementHour
                inc HourDigits				; If the hour hit 9, must be 09, so set hour to 10
                lda #'9'+1
                cmp HourDigits
                bne notNineHour
            
                lda #'0'
                sta HourDigits
                lda #'1'
                sta HourTens
                rts

notNineHour		lda #'2'+1					; If it's past not 2 (ie: possible 12 hour) then skip
                cmp HourDigits				
                bne doneHour				;   Last digit was 2 but first digit not 1 so go to 3
                lda #'1'
                cmp HourTens
                bne doneHour

                lda #'0'					; Roll from 12 to 01
                sta HourTens
                lda #'1'
                sta HourDigits
doneHour		rts

DecrementMinute
                dec minDigits
                lda #'0'-1
                cmp minDigits
                bne doneDec
                lda #'9'
                sta minDigits
                dec minTens
                lda #'0'-1
                cmp minTens
                bne doneDec
                lda #'5'
                sta minTens
                ; fall through to decrement Hour

DecrementHour
                dec hourDigits
                lda #'0'-1			    ; If we've gone under zero, must have been 10 so go to 09
                cmp hourDigits
                bne notsubzero
                lda #'9'
                sta hourDigits
                lda #'0'
                sta hourTens
                rts

notsubzero		lda #'1'-1			    ; If we're going under 1 
                cmp hourDigits
                bne doneDec
                lda #'0'
                cmp hourTens
                bne doneDec
                lda #'1'
                sta hourTens
                lda #'2'
                sta hourDigits
doneDec			rts
        
;-----------------------------------------------------------------------------------
; DrawClockXY	- Draws the current clock at the specified X/Y location on screen
;-----------------------------------------------------------------------------------
;			X:	Clock X position on screen
;			Y:	Clock Y position on screen
;-----------------------------------------------------------------------------------

DrawClockXY		stx ClockX
                sty ClockY
                jsr ClearScreen

                ; If there is no tens digit to the current hour, move the clock 
                ; left by half a digit onscreen to center it, and skip rendering
                ; the hour tens digit at all.  This could put the clock left edge at
                ; -4 but it still works just fine because that's added to the digit
                ; pos, which is never less than 8 anyway, so you're at 4 minimumn.

                lda HourTens
                cmp #'0'
                bne @notZeroHour
                lda ClockX			; Go left 4 columns (half a big char) to center single-digit hour
                sec
                sbc #4
                sta ClockX
                lda HourTens
                    
@notZeroHour	clc					; Colon	- We draw it first so other characters can overlap it
                lda #15
                adc ClockX
                tax
                lda #0
                clc
                adc ClockY
                tay
                lda #':'
                jsr DrawBigChar

                clc					; First digit of minutes
                lda #21
                adc ClockX
                tax
                lda #0
                clc
                adc ClockY
                tay
                lda MinTens
                jsr DrawBigChar
                EN
                clc					; Second Hour Digit
                lda #8
                adc ClockX
                tax
                lda #0
                clc
                adc ClockY
                tay
                lda HourDigits
                jsr DrawBigChar

                clc					; First Hour Digit
                lda #0
                adc ClockX
                tax
                lda #0
                clc
                adc ClockY
                tay
                lda HourTens
                cmp #'0'
                beq @skipHourTens
                jsr DrawBigChar
@skipHourTens
                clc					; 2nd digit of minutes
                lda #29
                adc ClockX
                tax
                lda #0
                clc
                adc ClockY
                tay
                lda MinDigits
                jsr DrawBigChar

                rts

;-----------------------------------------------------------------------------------
; DrawBigChar - Draws a given big character at the given X/Y positon
;-----------------------------------------------------------------------------------
;			A:	Character to print
;			X:  X pos on screen
;			Y:  Y pos on screen
;-----------------------------------------------------------------------------------

DrawBigChar		pha						; Save the A for later, it's the character 
                jsr GetCursorAddr		; Get the screen location based on the X/Y coord
                stx zptmp
                sty zptmp+1
                pla

                jsr GetCharTbl			; Find out the character block memory address
                stx zptmpB				;   for the character in A
                sty zptmpB+1

                lda #7					; Now do all 7 rows of the character definition
                sta bitcount

                ldx #0
@byteloop		ldy #0

                lda #%10000000			; Bitmask that walks right (10000000, 01000000, etc)
                sta bitmask

@bitloop		lda (zptmpB,x)			; x must be zero, we want indirect trhough zptmpB
                and bitmask				; If this bit is set in the character data, draw a block
                beq @prtblank			; If not set, skip and draw nothing
                lda #160
                sta (zptmp), y
                bne @doneprt
            
@prtblank		lda #' '
                sta (zptmp), y

@doneprt		lsr bitmask
                iny
                cpy #8					; 8 bits of work to do, so 8 steps
                bne @bitloop
                
                inc zptmpB
                bne @nocarry
                inc zptmpB+1
@nocarry		clc						; Advance the draw point to the next screen line
                lda zptmp
                adc #40
                sta zptmp
                lda zptmp+1
                adc #0
                sta zptmp+1

                dec bitcount			; Next character definition row, until all done
                bne @byteloop
                rts

;-----------------------------------------------------------------------------------
; GetCursorAddr - Returns address of X/Y positionon screen
;-----------------------------------------------------------------------------------
;		IN  X:	X pos
;       IN  Y:  Y pos
;       OUT X:  lsb of address
;       OUT Y:  msb of address
;-----------------------------------------------------------------------------------

GetCursorAddr   stx temp
                ldx #40
                jsr Multiply			; Result of Y*40 in AY
                sta resultLo
                sty resultHi
                lda resultLo
                clc
                adc #<SCREEN_MEM
                bcc nocarry
                inc resultHi
                clc
nocarry			adc temp
                sta resultLo
                lda resultHi
                adc #>SCREEN_MEM
                sta resultHi
                ldx resultLo
                ldy resultHi
                rts

;-----------------------------------------------------------------------------------
; Multiply		Multiplies X * Y == ResultLo/ResultHi
;-----------------------------------------------------------------------------------
;				X		8 bit value in
;				Y		8 bit value in
;-----------------------------------------------------------------------------------

Multiply
                stx ResultLo
                sty MultiplyTemp
                lda #$00
                tay
                sty ResultHi
                beq enterLoop
doAdd			clc
                adc ResultLo
                tax
                tya
                adc ResultHi
                tay
                txa
loop			asl ResultLo
                rol	ResultHi
enterLoop		lsr MultiplyTemp
                bcs doAdd
                bne loop
                rts

;-----------------------------------------------------------------------------------
; ClearScreen
;-----------------------------------------------------------------------------------
;			X:	lsb of address of null-terminated string
;           A:  msb of address
;-----------------------------------------------------------------------------------

ClearScreen		lda #147
                jsr CHROUT
                rts

;-----------------------------------------------------------------------------------
; WriteLine - Writes a line of text to the screen using CHROUT ($FFD2)
;-----------------------------------------------------------------------------------
;			Y:	MSB of address of null-terminated string
;           A:  LSB
;-----------------------------------------------------------------------------------

WriteLine		sta zptmp
                sty zptmp+1
                ldy #0
@loop			lda (zptmp),y
                beq done
                jsr CHROUT
                iny
                bne @loop
done 			rts

;-----------------------------------------------------------------------------------
; RepeatChar - Writes a character A to the output X times
;-----------------------------------------------------------------------------------
;			A:	Character to write
;           X:  Number of times to repeat it
;-----------------------------------------------------------------------------------
            
RepeatChar		jsr CHROUT
                dex
                bne RepeatChar
                rts
.if DEBUG
; During development we output the LOAD statement after running to make the 
; code-test-debug cycle go a little easier - less typing

hello			.string "LOAD ", 34,"PETCLOCK.OBJ",34,", 8",13,0
.endif

;-----------------------------------------------------------------------------------
; GetCharTbl - Returns the address of the character block table for whatever petscii
;              character is specified in the accumualtor
;-----------------------------------------------------------------------------------
;			A:	Character to look up
;       OUT X:  lsb of character map entry
;       OUT Y:  msb of character map entry
;-----------------------------------------------------------------------------------


GetCharTbl		sta tempchar
                ldx #<CharTable
                stx zptmpC
                ldx #>CharTable
                stx zptmpC+1
                ldy #0
@scanloop		lda (zptmpC),y
                beq FoundChar				; Hit the null terminator, return the zeros after it
                cmp tempchar
                beq FoundChar				; Hit the matching char, return the block address
                iny
                iny
                iny
                bne @scanloop				; Nothing found, keep scanning

FoundChar		iny
                lda (zptmpC),y				; Low byte of character entry in X
                tax
                iny
                lda (zptmpC),y				; High byte of character entry in Y
                tay
                rts
CharTable
                .string ":"
                .word  CharColon
                .string "0"
                .word  Char0
                .string "1"
                .word  Char1
                .string "2"
                .word  Char2
                .string "3"
                .word  Char3
                .string "4"
                .word  Char4
                .string "5"
                .word  Char5
                .string "6"
                .word  Char6
                .string "7"
                .word  Char7
                .string "8"
                .word  Char8
                .string "9"
                .word  Char9
                
                .string 0
                .word   0

Char0
                .byte   %01111111
                .byte   %01100011
                .byte   %01100011
                .byte   %01100011
                .byte   %01100011
                .byte   %01100011
                .byte   %01111111
Char1			
                .byte	%00001100
                .byte	%00011100
                .byte	%00001100
                .byte	%00001100
                .byte	%00001100
                .byte	%00001100
                .byte	%00111111
Char2
                .byte	%01111111
                .byte	%00000011
                .byte	%00000011
                .byte	%01111111
                .byte	%01100000
                .byte	%01100000
                .byte	%01111111
Char3
                .byte	%01111111
                .byte	%00000011
                .byte	%00000011
                .byte	%00011111
                .byte	%00000011
                .byte	%00000011
                .byte	%01111111
Char4
                .byte	%01100011
                .byte	%01100011
                .byte   %01100011
                .byte	%01111111
                .byte	%00000011
                .byte	%00000011
                .byte	%00000011
Char5
                .byte	%01111111
                .byte	%01100000
                .byte	%01100000
                .byte	%01111111
                .byte	%00000011
                .byte	%00000011
                .byte	%01111111
Char6
                .byte	%01111111
                .byte	%01100000
                .byte	%01100000
                .byte	%01111111
                .byte	%01100011
                .byte	%01100011
                .byte	%01111111
Char7
                .byte	%01111111
                .byte	%00000011
                .byte	%00000011
                .byte	%00000011
                .byte	%00000011
                .byte	%00000011
                .byte	%00000011
Char8
                .byte	%01111111
                .byte	%01100011
                .byte	%01100011
                .byte	%01111111
                .byte	%01100011
                .byte	%01100011
                .byte	%01111111
Char9				
                .byte	%01111111
                .byte	%01100011
                .byte	%01100011
                .byte	%01111111
                .byte	%00000011
                .byte	%00000011
                .byte	%00000011
CharColon		
                .byte	%00000000
                .byte	%00011000
                .byte	%00011000
                .byte	%00000000
                .byte	%00011000
                .byte	%00011000
                .byte	%00000000

Instructions	
                .string "                                        "
                .string "                                        "
                .string "         press runstop to exit", $00

dirname         .string "$",0

SetFakeResponse ldy #0
-               lda FakeResponse, y
                sta DevResponse, y
                beq +
                iny
                jmp -
+               rts

