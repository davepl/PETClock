; --------- BASIC 4 ROM ROUTINES -----------------------------------------

BASIC			.equ 4		; remember BASIC 4 selection

SCROUT			.equ $e202	; output A to screen
RDOA			.equ $d754	; read hex address -> $FB,$FC
RDOB			.equ $d763	; read hex byte -> A
CLRSCR			.equ $e015	; clear screen
CRLF			.equ $d534	; move cursor to next line
FPOUT			.equ $cf8d	; write floating point
INTOUT			.equ $cf83	; write integer 0-65535 X.equLSB,A.equMSB
SCROLD			.equ $e021	; scroll down
SCROLU			.equ $e024	; scroll up
SPAC2			.equ $d52e	; write 2 spaces
SPACE			.equ $d531	; write space
STROUT			.equ $bb24	; X.equlen, STRADR.equptr

; STROUTZ	.equ $bb1d	; A.equLSB, Y.equMSB
; BASIC4 STROUTZ is broken!

WROA			.equ $d717	; write hex address
HEXOUT			.equ $d722	; write A as hex
WROB			.equ $d731	; write hex byte
WRTWO			.equ $d731	; write XA to screen

ADRFP			.equ $cd7f	; uint LSB.equ$5f, MSB.equ$60 -> FAC1
ASCII			.equ $d73a	; hex digit -> ascii hex digit
FPINT			.equ $cdd1	; FAC1 -> uint $61.equMSB, $62.equLSB
FPSTR			.equ $cf93	; fp -> str $0100..NUL
HEXIT			.equ $d78d	; hex ascii digit A -> hex digit A
INTFP			.equ $c4bc	; int Y.equLSB, A.equMSB -> FAC1
STRFP			.equ $c8eb	; string -> fp
RDINT			.equ $b8f6	; read basic text -> LINNUM

ABS				.equ $cd8e	; FAC1 .equ ABS(FAC1)
ADD				.equ $c9a0	; FAC1 .equ FAC1 + FAC2
ATN				.equ $d32C	; FAC1 .equ ATN(FAC1)
COS				.equ $d282	; FAC1 .equ COS(FAC1)
DIV				.equ $cc48	; FAC1 .equ FAC2 / FAC1
EXP				.equ $d184	; FAC1 .equ EXP(FAC1)
FAC12			.equ $cd45	; FAC2 :.equ FAC1

; TODO: add more FP routines!

ACPTR			.equ $f1c0	; input IEEE -> A
CHKIN			.equ $ffc6	; stdin from logical file # in X
CIOUT			.equ $f19e	; output A -> IEEE
CKOUT			.equ $ffc9	; stdout to logical file # in X
CLOSE			.equ $f2e0	; close file
CLSEI			.equ $f72f	; close and unlisten
CLRCH			.equ $ffcc	; reset stdio to defaults
LISTN			.equ $f0d5	; send LISTEN
LOAD			.equ $f408	; LOAD
LOADOP			.equ $f356	; LOAD without pointer change
FILENOTFOUND	.equ $f425	; FILE NOT FOUND, return to BASIC
OPEN			.equ $f563	; open file
OPENI			.equ $f4a5	; open file on IEEE device
SCNT			.equ $f2c1	; prepare SETT for logical file A
SECND			.equ $f143	; send secondary address A
SETT			.equ $f2cd	; set LF,DN,SA from table
TALK			.equ $f0d2	; send TALK
TWAIT			.equ $f92b	;
UNLSN			.equ $f1b9	; send UNLISTEN
UNTLK			.equ $f1ae	; send UNTALK

READY			.equ $b3ff	; basic warm start
RESET			.equ $fd16	; basic cold start
NEWSTT			.equ $b74a	; set up next statement for execution
STOPEQ			.equ $f335	; set Z flag if stop key pressed
STOPR			.equ $ffe1	; return to basic if stop key pressed
ERRO			.equ $b3e0	; BASIC error message
SYNERR			.equ $bf00	; SYNTAX ERROR
IQERR			.equ $c373	; ILLEGAL QUANTITY ERROR

MOVBLK			.equ $b357	; move block

GRAPHIC			.equ $e01b	; set graphic mode
TEXT			.equ $e018	; set text mode
BEEP			.equ $e02a	; beep

LINKPRG			.equ $b4b6	; rechain lines
RSTXCLR			.equ $b5e9	; reset TXTPTR and perform CLR
STXTPT			.equ $b622	; reset TXTPTR
CLR				.equ $b5f0	; perform CLR
SCRTCH			.equ $b5d4	; perform NEW

MAINS			.equ $b40f	; MAIN's return addr on stack for CHRGET routine
