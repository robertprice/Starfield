;------------------------------
; First attempt at plotting a moving starfield
; Robert Price - 01/02/2023
;
;---------- Includes ----------
            INCDIR      "include"
            INCLUDE     "hw.i"
            INCLUDE     "funcdef.i"
            INCLUDE     "exec/exec_lib.i"
            INCLUDE 	"graphics/gfxbase.i"
            INCLUDE     "graphics/graphics_lib.i"
            INCLUDE     "hardware/cia.i"
;---------- Const ----------

CIAA        EQU $bfe001

            SECTION Code,CODE,CHIP

init:
            movem.l     d0-a6,-(sp)
            move.l      4.w,a6							; execbase
            moveq.l		#0,d0

            move.l      #gfxname,a1						; get the name of the graphics library
            jsr         _LVOOldOpenLibrary(a6)
            move.l      d0,a1
            move.l		gb_copinit(a1),d4				; save the current copper list so we can restore it later.
            move.l      d4,CopperSave
            jsr         _LVOCloseLibrary(a6)

            lea         CUSTOM,a6                      ; Load the address of the custom registers indo a6


            move.w      INTENAR(a6),INTENARSave        ; Save original interupts
            move.w      DMACONR(a6),DMACONSave         ; Save DMACON
            move.w      #$138,d0                       ; wait for eoframe
            bsr.w       WaitRaster                     
            move.w      #$7fff,INTENA(a6)              ; disable interupts
													   ; Set INTREQ twice due to A4000 bug.
            move.w      #$7fff,INTREQ(a6)              ; disable all bits in INTREQ
            move.w      #$7fff,INTREQ(a6)              ; disable all bits in INTREQ

			; SET & BLTPRI & DMAEN & BPLEN & COPEN & BLTEN & SPREN bits
            move.w      #%1000011111100000,DMACON(a6)

; setup bitplane1 in the copper list to point to our 1 bitplane image.
			move.l	#screen,d0
			move.w	d0,copBp1P+6						; set the low word
			swap	d0
			move.w	d0,copBp1P+2						; set the high word

; install our copper list
            move.l      #myCopperList,COP1LC(a6)
            move.w      #0,COPJMP1(a6)
******************************************************************


;--------------
mainloop:
; Wait for vertical blank
            move.w      #$0c,d0                        ;No buffering, so wait until raster
            bsr.w       WaitRaster                     ;is below the Display Window.

			bsr			clearscreen						; clear the screen

; to plot the starfield we neeed to interate eoveer the starfield list
; this is stored in 3 words - speed, x, and y
; as we iterate we subtract the speed from x and save it back to the list
; if it's less than zero we reset it to 319, the width of the screen
; we also pick a new y coordinate from a pre-generated list of y coordinates and save that.
			moveq.l		#0,d1
			moveq.l		#0,d2
			moveq.l		#0,d3
			moveq.l		#0,d4

			lea			screen,a0
			lea			starfield,a1
			lea			endstarfield,a2
			move.l		nextycoord,a3
			lea			endycoords,a4
.plotstars
			move.w		(a1)+,d3						; speed
			move.w		(a1),d4							; x
			move.w		d4,d1							; x into d1
			sub.w		d3,d4							; work out the next x position
			bgt			.skipxyreset					; if greater than 0 we don't neeed to reset the x position

			move.w		#319,d1							; reset x to the far right of the screen
			move.w		d1,(a1)+						; save updated x coordinate
			move.w		(a3)+,d2						; get the next y coordinate
			move.w		d2,(a1)+						; save updated y coordinate
			move.l		a3,nextycoord					; update the next y random position
			cmp.l		a3,a4							; if it's not at the end of ycoords array we skip to the plot
			bgt			.doplot			
			move.l		#ycoords,nextycoord				; reset the nextycoord with the start of the ycoords array
			bra			.doplot							; jump to the plot 
.skipxyreset:
			move.w		d4,(a1)+						; save updated x coordinate
			move.w		(a1)+,d2						; y
.doplot
			bsr			plot							; plot the pixel

			cmp.l		a1,a2							; are we at the end of the star list?
			bgt			.plotstars						; if not, plot the next star


; check if the left mouse button has been pressed
; if it hasn't, loop back.
checkmouse:
            btst        #CIAB_GAMEPORT0,CIAA+ciapra
            bne       	mainloop

exit:
            move.w      #$7fff,DMACON(a6)              ; disable all bits in DMACON
            or.w        #$8200,(DMACONSave)            ; Bit mask inversion for activation
            move.w      (DMACONSave),DMACON(a6)        ; Restore values
            move.l      (CopperSave),COP1LC(a6)        ; Restore values
            or          #$c000,(INTENARSave)
            move        (INTENARSave),INTENA(a6)       ; interrupts reactivation
            movem.l     (sp)+,d0-a6
            moveq.l     #0,d0                          ; Return code 0 tells the OS we exited with errors.
            rts                                        ; End

;-------------------------
; Wait for a scanline
; d0 - the scanline to wait for
; trashes d1
WaitRaster:
            move.l      CUSTOM+VPOSR,d1
            lsr.l       #1,d1
            lsr.w       #7,d1
            cmp.w       d0,d1
            bne.s       WaitRaster                     ;wait until it matches (eq)
            rts

;--------------------------
; Plot a pixel d1=x, d2=y, a0=bitplane
plot:
			movem.l	d0-a0,-(sp)

			; multiply y with 40 to get add factor for bitplane
			move.w	d2,d3
			lsl.w	#4,d2
			lsl.w   #3,d3
			add.w   d2,d2
			add.w   d3,d2
			add.w	d2,a0

			; now work out x
			move.l	d1,d4		; copy x to d4
			move.l	d1,d5		; and d5
			move.l	d1,d3		; and d3
			lsr.l	#3,d3		; divide with 8 to get number of byte
			add.l	d3,a0		; get to the byte we are changing

			asl.l	#3,d3		; How many times did x fit in 8?
			cmp	#0,d3		; If zero, x is directly the bits to set
			beq	.nolla		;
			sub.l   d3,d4		; Substract multiply of 8 from original x
			move.l	d4,d5		; to get pixel number
.nolla:  
			move.l  #7,d6		; substract 7 from pixel number
			sub	d5,d6		; to get right bit
			bset	d6,(a0)		; set the "d6 th bit" on a0  

			movem.l	(sp)+,d0-a0
			rts


;-------------------
; clear the screen using the CPU
; trashes a0, d0, and d1
clearscreen:
			lea		screen,a0					; load the screen into a0
			move.l	#(endscreen-screen)/4,d1	; work out the numnbere of long words in the screen into d1
			moveq.l	#0,d0						; zero d0
.loop:		move.l	d0,(a0)+					; clear the screen
			dbra	d1,.loop					; iterate until complete
			rts									; return



******************************************************************
gfxname:
              GRAFNAME                                   ; inserts the graphics library name

              EVEN

DMACONSave:   dc.w        1
CopperSave:   dc.l        1
INTENARSave:  dc.w        1

			EVEN

; This is the copper list.
myCopperList:
    dc.w	$1fc,$0				; slow fetch for AGA compatibility
    dc.w	BPLCON0,$0200			; wait for screen start

; setup the screen so we can have our 320x256 bitplane
	dc.w	DIWSTRT,$2c81
	dc.w	DIWSTOP,$2cc1
	dc.w	DDFSTRT,$38
	dc.w	DDFSTOP,$d0
	dc.w	BPL1MOD,$0
	dc.w	BPL2MOD,$0

copBp1P:
	dc.w	BPL1PTH,0			; high word of bitplane1
	dc.w	BPL1PTL,0			; low word of bitplane1
	dc.w	BPLCON0,$1200		; turn on bitplane1

    dc.w	COLOR00,$0			; set COLOUR00 to black
    dc.w	COLOR01,$fff			; set COLOUR01, we cycle this value 


.copperEnd:
    dc.w	$d707,COPPER_HALT
    dc.w	COLOR00,$000

    dc.l	COPPER_HALT					; impossible position, so Copper halts.

;----------------------------
; starfield speed,x,y
starfield:
	dc.w	1,43,2
	dc.w	3,243,8
	dc.w	2,300,14
	dc.w	1,301,23
	dc.w	2,143,32
	dc.w	3,200,34
	dc.w	2,200,43
	dc.w	1,55,67
	dc.w	2,155,69
	dc.w	3,198,77
	dc.w	1,200,80
	dc.w	3,98,82
	dc.w	2,298,83
	dc.w	1,98,91
	dc.w	3,33,98
	dc.w	3,100,100
	dc.w	1,130,104
	dc.w	3,43,114
	dc.w	2,83,124
	dc.w	2,201,132
	dc.w	3,154,133
	dc.w	1,230,143
	dc.w	2,153,147
	dc.w	1,20,152
	dc.w	3,65,162
	dc.w	2,187,172
	dc.w	1,23,175
	dc.w	1,287,179
	dc.w	3,265,187
	dc.w	2,255,200
	dc.w	1,200,203
	dc.w	3,300,222
	dc.w	2,122,232
	dc.w	1,54,242
	dc.w	3,262,252
endstarfield:

; pointer to the next ycoordinate to use
nextycoord:	dc.l	ycoords
; the numbers 0 to 255 in a random order for picking the next y coordinate.
ycoords:
	dc.w    63,120,91,12,240,147,105,124,228,88,22,140,62,196,184,165,13,123,113,36,8,183,58,3,35,30,144,57,25,227,71,39,121,125,138,54,31,118,203,78,40,248,206,16,42,34,222,122,214,130,164,82,254,112,231,243,127,178,33,102,116,43,154,202,207,85,115,86,7,244,216,150,90,19,94,111,252,169,53,45,163,247,168,103,132,60,161,66,175,204,209,15,155,198,224,128,149,29,221,142,249,229,233,188,166,73,72,110,134,148,225,10,64,176,129,114,104,67,180,241,218,201,38,21,160,141,215,4,81,182,135,107,0,75,96,220,200,131,212,199,61,27,171,100,187,250,46,106,189,152,44,24,108,143,95,28,55,26,48,74,79,145,194,84,253,2,230,167,217,146,151,117,9,181,236,173,11,87,137,153,5,56,190,162,68,37,219,226,23,77,119,197,41,157,101,158,6,136,211,179,239,52,59,242,177,65,159,245,47,83,99,89,32,172,92,109,156,14,246,193,98,133,192,50,69,185,51,70,97,213,223,238,191,205,126,1,20,237,232,251,208,235,174,93,17,210,170,234,139,18,195,76,49,186,80
endycoords:

			SECTION logo,BSS_C
screen:	
		    ds.b (320*256)/8		; 320x256 single bit plane image
endscreen: