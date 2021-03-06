;--------------------------------------------------------------------------
;
; Casual Connect 2015
; SDKBOX / Cocos2d-x Intro
; https://github.com/ricardoquesada/c64-casual-connect-15
;
; About file
;
; Zero Page global registers:
;   $f9/$fa -> charset:  ** MUST NOT be modifed by any other functions **
;
;--------------------------------------------------------------------------


; exported by the linker
.import __SIDMUSIC_LOAD__, __INTRO_CODE_LOAD__, __INTRO_GFX_LOAD__, _INTRO_CHARSET_LOAD__, __INTRO_CHARSET_LOAD__

; from utils.s
.import clear_screen, clear_color, get_key, sync_irq_timer, detect_pal_ntsc

;--------------------------------------------------------------------------
; Constants
;--------------------------------------------------------------------------

; bitwise: 1=raster-sync code. 2=50hz code (music)
DEBUG = 0

SCROLL_AT_LINE = 18
ROWS_PER_CHAR = 7

RASTER_SDKBOX_START = 30
RASTER_SDKBOX_END = 190
RASTER_SCROLLER_START = 50 + SCROLL_AT_LINE*8-1

SCREEN_TOP = $0400 + SCROLL_AT_LINE * 40


MUSIC_INIT = __SIDMUSIC_LOAD__
MUSIC_PLAY = __SIDMUSIC_LOAD__ + 3

; SPEED must be between 0 and 7. 0=Stop, 7=Max speed
SCROLL_SPEED = 6

; Black
SCROLL_BKG_COLOR = 0

; SPEED of colorwasher: 1=Max speed
COLORWASH_SPEED = 1

ANIM_SPEED = 1

KOALA_BITMAP_DATA = __INTRO_GFX_LOAD__
KOALA_CHARMEM_DATA = KOALA_BITMAP_DATA + $1f40
KOALA_COLORMEM_DATA = KOALA_BITMAP_DATA + $2328
KOALA_BACKGROUND_DATA = KOALA_BITMAP_DATA + $2710

;--------------------------------------------------------------------------
; Macros
;--------------------------------------------------------------------------
.macpack cbm			; adds support for scrcode
.macpack mymacros		; my own macros

.segment "CODE"
	jsr detect_pal_ntsc

	; turn off BASIC + Kernal. More RAM
	lda #$35
	sta $01

	jmp __INTRO_CODE_LOAD__

.segment "INTRO_CODE"

;--------------------------------------------------------------------------
; _main
;--------------------------------------------------------------------------
	jsr init

@mainloop:
	lda sync50hz
	beq :+
	jsr @do_sync50hz

:	lda sync
	beq :+
	jsr @do_sync

:
	; key pressed ?
	jsr get_key
	bcc @mainloop
	cmp #$47		; space
	bne @mainloop

	; do something
	jmp @mainloop

@do_sync:
	lda #$00
	sta sync
.if (DEBUG & 1)
	dec $d020
.endif
	jsr scroll
	jsr anim_char
	jsr anim_colorwash
	jsr anim_sdkbox_color
.if (DEBUG & 1)
	inc $d020
.endif
	rts

@do_sync50hz:
	lda #$00
	sta sync50hz
.if (DEBUG & 2)
	inc $d020
.endif
	jsr MUSIC_PLAY
.if (DEBUG & 2)
	dec $d020
.endif
	rts



;--------------------------------------------------------------------------
; IRQ handler: background begin
;--------------------------------------------------------------------------
irq_bkg_begin:
	pha			; saves A, X, Y
	txa
	pha
	tya
	pha

	sei
	asl $d019
	bcs @raster

	; timer A interrupt
	lda $dc0d		; clear the interrupt
	cli

	inc sync50hz

	pla			; restores A, X, Y
	tay
	pla
	tax
	pla
	rti			; restores previous PC, status

@raster:
	.repeat 16
		nop
	.endrepeat
	lda sdkbox_bkg_color
	sta $d020
	sta $d021

	ldx #<irq_bkg_end
	ldy #>irq_bkg_end
	stx $fffe
	sty $ffff

	lda raster_color_end
	sta $d012

	asl $d019
	cli

	pla			; restores A, X, Y
	tay
	pla
	tax
	pla
	rti			; restores previous PC, status

;--------------------------------------------------------------------------
; IRQ handler: background end
;--------------------------------------------------------------------------
irq_bkg_end:
	pha			; saves A, X, Y
	txa
	pha
	tya
	pha

	sei
	asl $d019
	bcs @raster

	; timer A interrupt
	lda $dc0d		; clear the interrupt
	cli

	inc sync50hz

	pla			; restores A, X, Y
	tay
	pla
	tax
	pla
	rti			; restores previous PC, status

@raster:
	.repeat 11
		nop
	.endrepeat
	lda #$00
	sta $d020
	sta $d021

	ldx #<irq_scroller
	ldy #>irq_scroller
	stx $fffe
	sty $ffff

	lda #RASTER_SCROLLER_START
	sta $d012


	asl $d019

	pla			; restores A, X, Y
	tay
	pla
	tax
	pla
	rti			; restores previous PC, status

;--------------------------------------------------------------------------
; IRQ handler: scroller
;--------------------------------------------------------------------------
irq_scroller:
	pha			; saves A, X, Y
	txa
	pha
	tya
	pha

	sei
	asl $d019
	bcs @raster

	; timer A interrupt
	lda $dc0d		; clear the interrupt
	cli

	inc sync50hz

	pla			; restores A, X, Y
	tay
	pla
	tax
	pla
	rti			; restores previous PC, status

@raster:
	STABILIZE_RASTER

	; char mode
	lda #%00011011		; +2
	sta $d011		; +4

	ldx #SCROLL_BKG_COLOR	; +6
	stx $d020		; +10
	stx $d021		; +14

	lda smooth_scroll_x	; +16
	sta $d016		; +20

	; raster bars
	ldx #$00		; +22

	ldy #7*8
:	lda $d012
:	cmp $d012
	beq :-
	lda raster_colors+8,x
	sta $d021
	inx
	dey
	bne :--

	; color
	lda #$00
	sta $d020
;	lda KOALA_BACKGROUND_DATA
	lda #00
	sta $d021

	; no scroll, multi-color
	lda #%00011000
	sta $d016

	; hires bitmap mode
	lda #%00111011
	sta $d011

	lda #<irq_bkg_begin
	sta $fffe
	lda #>irq_bkg_begin
	sta $ffff

	lda raster_color_start	; white border must start here
	sta $d012

	asl $d019

	inc sync

	cli

	pla			; restores A, X, Y
	tay
	pla
	tax
	pla
	rti			; restores previous PC, status

;--------------------------------------------------------------------------
; scroll(void)
; main scroll function
;--------------------------------------------------------------------------
.proc scroll
	; speed control

	sec
	lda smooth_scroll_x
	sbc #SCROLL_SPEED
	and #07
	sta smooth_scroll_x
	bcc :+
	rts

:
	jsr scroll_screen

	lda chars_scrolled
	cmp #%10000000
	bne :+

	; A and current_char will contain the char to print
	; $f9/$fa points to the charset definition of the char
	jsr setup_charset

:
	; basic setup
	ldx #<(SCREEN_TOP+7*40+39)
	ldy #>(SCREEN_TOP+7*40+39)
	stx @screen_address
	sty @screen_address+1

	; should not be bigger than 7 (8 rows)
	ldy #.min(ROWS_PER_CHAR,7)


@loop:
	lda ($f9),y
	and chars_scrolled
	beq @empty_char

;	 lda current_char
	; char to display
	lda #$fe		; full char
	bne :+

@empty_char:
	lda #$ff		; empty char

:
	; self-changing value
	; this value will be overwritten with the address of the screen
@screen_address = *+1
	sta $caca

	; next line for top scroller
	sec
	lda @screen_address
	sbc #40
	sta @screen_address
	bcs :+
	dec @screen_address+1
:

	dey			; next charset definition
	bpl @loop

	lsr chars_scrolled
	bcc @endscroll

	lda #128
	sta chars_scrolled

	clc
	lda scroller_text_ptr_low
	adc #1
	sta scroller_text_ptr_low
	bcc @endscroll
	inc scroller_text_ptr_hi

@endscroll:
	rts
.endproc


;--------------------------------------------------------------------------
; scroll_screen(void)
;--------------------------------------------------------------------------
; args: -
; modifies: A, X, Status
;--------------------------------------------------------------------------
scroll_screen:
	; move the chars to the left and right
	ldx #0

	; doing a cpy #$ff
	ldy #38

@loop:
	.repeat ROWS_PER_CHAR,i
		lda SCREEN_TOP+40*i+1,x
		sta SCREEN_TOP+40*i+0,x
	.endrepeat

	inx
	dey
	bpl @loop
	rts

;--------------------------------------------------------------------------
; setup_charset(void)
;--------------------------------------------------------------------------
; Args: -
; Modifies A, X, Status
; returns A: the character to print
;--------------------------------------------------------------------------
.proc setup_charset
	; put next char in column 40

	; supports a scroller with more than 255 chars
	clc
	lda #<scroller_text
	adc scroller_text_ptr_low
	sta @address
	lda #>scroller_text
	adc scroller_text_ptr_hi
	sta @address+1

	; self-changing value
@address = *+1
	lda scroller_text
	cmp #$ff
	bne :+

	; reached $ff. Then start from the beginning
	lda #%10000000
	sta chars_scrolled
	lda #0
	sta scroller_text_ptr_low
	sta scroller_text_ptr_hi
	lda scroller_text
:
	sta current_char

	tax

	; address = CHARSET + 8 * index
	; multiply by 8 (LSB)
	asl
	asl
	asl
	clc
	adc #<(__INTRO_CHARSET_LOAD__ + 128*8)		; charset starting at pos 128
	sta $f9

	; multiply by 8 (MSB)
	; 256 / 8 = 32
	; 32 = %00100000
	txa
	lsr
	lsr
	lsr
	lsr
	lsr

	clc
	adc #>(__INTRO_CHARSET_LOAD__ + 128*8)		; charset starting at pos 128
	sta $fa

	rts
.endproc

;--------------------------------------------------------------------------
; anim_char(void)
;--------------------------------------------------------------------------
; Args: -
; Modifies A, X, Status
; returns A: the character to print
;--------------------------------------------------------------------------
ANIM_TOTAL_FRAMES = 4
.proc anim_char

	sec
	lda anim_speed
	sbc #ANIM_SPEED
	and #07
	sta anim_speed
	bcc @animation

	rts

@animation:
	lda anim_char_idx
	asl			; multiply by 8 (next char)
	asl
	asl
	tay

	ldx #7			; 8 rows
@loop:
	lda char_frames,y
	sta $3800 + $fe * 8,x

	iny
	dex
	bpl @loop

	dec anim_char_idx
	bpl :+

	; reset anim_char_idx
	lda #ANIM_TOTAL_FRAMES-1
	sta anim_char_idx
:
	rts

.endproc

;--------------------------------------------------------------------------
; anim_colorwash(void)
;--------------------------------------------------------------------------
; Args: -
; A Color washer routine
;--------------------------------------------------------------------------
.proc anim_colorwash

	dec colorwash_delay
	beq :+
	rts

:
	lda #COLORWASH_SPEED
	sta colorwash_delay

	; washer top
	lda raster_colors_top
	sta save_color_top

	ldx #0
:	lda raster_colors_top+1,x
	sta raster_colors_top,x
	inx
	cpx #TOTAL_RASTER_LINES
	bne :-

save_color_top = *+1
	lda #00			; This value will be overwritten
	sta raster_colors_top+TOTAL_RASTER_LINES-1

	; washer bottom
	lda raster_colors_bottom+TOTAL_RASTER_LINES-1
	sta save_color_bottom

	ldx #TOTAL_RASTER_LINES-1
:	lda raster_colors_bottom,x
	sta raster_colors_bottom+1,x
	dex
	bpl :-

save_color_bottom = *+1
	lda #00			; This value will be overwritten
	sta raster_colors_bottom
	rts
.endproc


;--------------------------------------------------------------------------
; void anim_sdkbox_color()
;--------------------------------------------------------------------------
; moves the white background color of the sdkbox logo
;--------------------------------------------------------------------------
.proc anim_sdkbox_color

	lda @anim_effect_idx
	asl
	tax

	lda @anim_jump_table,x
	ldy @anim_jump_table+1,x
	sta @jump_to
	sty @jump_to+1

@jump_to = *+1
	jsr $caca		; self-modifying

	bne @bye		; effect finished ?
	inc @anim_effect_idx	; set new effect
	lda @anim_effect_idx
	cmp #TOTAL_EFFECTS	; all effects ?
	bne @bye
	lda #$00
	sta @anim_effect_idx

@bye:
	rts

@anim_effect_two_colors:
	ldx sine_idx
	clc
	lda #RASTER_SDKBOX_START
	adc sine_table,x
	sta raster_color_start

	sec
	lda #RASTER_SDKBOX_END
	sbc sine_table,x
	sta raster_color_end
	inc sine_idx
	rts

@anim_effect_top:
	ldx sine_idx
	clc
	lda #RASTER_SDKBOX_START
	adc sine_big_table,x
	sta raster_color_start
	inc sine_idx
	rts

@anim_effect_bottom:
	ldx sine_idx
	sec
	lda #RASTER_SDKBOX_END
	sbc sine_big_table,x
	sta raster_color_end
	inc sine_idx
	rts

@anim_effect_two_colors_fast:
	ldx sine_idx
	clc
	lda #RASTER_SDKBOX_START
	adc sine_freq4_table,x
	sta raster_color_start

	sec
	lda #RASTER_SDKBOX_END
	sbc sine_freq4_table,x
	sta raster_color_end
	inc sine_idx
	rts

@anim_effect_top_short_fast:
	ldx sine_idx
	clc
	lda #RASTER_SDKBOX_START
	adc sine_short_fast_table,x
	sta raster_color_start
	inx
	txa
	and #127
	sta sine_idx
	rts

@anim_effect_bottom_short_fast:
	ldx sine_idx
	sec
	lda #RASTER_SDKBOX_END
	sbc sine_short_fast_table,x
	sta raster_color_end
	inx
	txa
	and #127
	sta sine_idx
	rts

@anim_effect_bottom_up:
	ldx sine_idx
	sec
	lda #RASTER_SDKBOX_END
	sbc sine_half_table,x
	sta raster_color_end
	inx
	txa
	and #127
	sta sine_idx
	rts

@anim_effect_both_go_down:
	ldx sine_idx
	clc
	lda #RASTER_SDKBOX_START
	adc sine_half_table,x
	sta raster_color_start
	clc
	lda #RASTER_SDKBOX_END-140
	adc sine_half_table,x
	sta raster_color_end
	inx
	txa
	and #127
	sta sine_idx
	rts

@anim_effect_both_go_up:
	ldx sine_idx
	sec
	lda #RASTER_SDKBOX_START+140
	sbc sine_half_table,x
	sta raster_color_start
	sec
	lda #RASTER_SDKBOX_END
	sbc sine_half_table,x
	sta raster_color_end
	inx
	txa
	and #127
	sta sine_idx
	rts

@anim_effect_top_up:
	ldx sine_idx
	sec
	lda #RASTER_SDKBOX_START+140
	sbc sine_half_table,x
	sta raster_color_start
	inx
	txa
	and #127
	sta sine_idx
	rts


@anim_effect_bkg_color:
	ldx @bkg_colors_idx
	lda @bkg_colors,x
	sta sdkbox_bkg_color

	inx
	txa
	and #$3f
	sta @bkg_colors_idx

	ldy @bkg_colors,x
	cpy #$ff
	rts
@bkg_colors:
	.byte 0,0,0,0,1,1,1,1
	.byte 0,0,0,0,1,1,1,1
	.byte 0,0,0,0,1,1,1,1
	.byte 0,0,0,0,1,1,1,1
	.byte 0,0,0,0,1,1,1,1
	.byte 0,0,0,0,1,1,1,1
	.byte 0,0,0,0,1,1,1,1
	.byte 0,0,0,0,1,1,1,1
	.byte $ff
@bkg_colors_idx:
	.byte 0

@anim_effect_idx:
	.byte 0

@anim_jump_table:
	.addr @anim_effect_bottom_up
	.addr @anim_effect_both_go_down
	.addr @anim_effect_both_go_up
	.addr @anim_effect_both_go_down
	.addr @anim_effect_top_up

	.addr @anim_effect_top_short_fast
	.addr @anim_effect_bottom_short_fast
	.addr @anim_effect_two_colors_fast
	.addr @anim_effect_two_colors
	.addr @anim_effect_two_colors_fast
	.addr @anim_effect_two_colors
	.addr @anim_effect_top
	.addr @anim_effect_bottom
	.addr @anim_effect_bkg_color

TOTAL_EFFECTS = (* - @anim_jump_table) / 2

.endproc



;--------------------------------------------------------------------------
; init(void)
;--------------------------------------------------------------------------
; Args: -
; Clear screen, interrupts, charset and others
;--------------------------------------------------------------------------
.proc init
	; init music
	lda #0
	jsr MUSIC_INIT

	sei
	; must be BEFORE any screen-related function
	lda #$20
	jsr clear_screen
	lda #$00
	jsr clear_color

	; must be BEFORE init_charset / init_scroll_colors
	jsr init_koala_colors

	; must be AFTER koala colors
	jsr init_charset

	; must be AFTER koala colors
	jsr init_scroll_colors

	;default values for scroll variables
	jsr init_scroll_vars

	; no sprites please
	lda #$00
	sta $d015

	; colors
	lda #0
	sta $d020
	sta $d021

	; default is:
	;    %00010101
	; charset at $3800
	lda #%00011111
	sta $d018

	; no interrups
	jsr sync_irq_timer

	; turn off cia interrups
	lda #$7f
	sta $dc0d
	sta $dd0d

	; enable raster irq
	lda #01
	sta $d01a

	;default is:
	;    %00011011
	; disable bitmap mode
	; 25 rows
	; disable extended color
	; vertical scroll: default position
	lda #%00011011
	sta $d011

        ; Vic bank 0: $0000-$3FFF
	lda $dd00
	and #$fc
	ora #3
	sta $dd00


	; set Timer interrupt
	lda #$01
	sta $dc0e			; start time A
	lda #$81
	sta $dc0d			; enable time A interrupts

	;
	; irq handler
	; both for raster and timer interrupts
	;
	lda #<irq_bkg_begin
	sta $fffe
	lda #>irq_bkg_begin
	sta $ffff

	; raster interrupt
	lda #RASTER_SDKBOX_START
	sta $d012

	; clear interrupts and ACK irq
	lda $dc0d
	lda $dd0d
	asl $d019

	; enable interrups again
	cli

	rts
.endproc

;--------------------------------------------------------------------------
; init_koala_colors(void)
;--------------------------------------------------------------------------
; Args: -
; puts the koala colors in the correct address
; Assumes that bimap data was loaded in the correct position
;--------------------------------------------------------------------------
.proc init_koala_colors

	; Koala format
	; bitmap:           $0000 - $1f3f = $1f40 ( 8000) bytes
	; color %01 - %10:  $1f40 - $2327 = $03e8 ( 1000) bytes
	; color %11:        $2328 - $270f = $03e8 ( 1000) bytes
	; color %00:        $2710         =     1 (    1) byte
	; total:                    $2710 (10001) bytes

	ldx #$00
@loop:
	; $0400: colors %01, %10
	lda KOALA_CHARMEM_DATA,x
	sta $0400,x
	lda KOALA_CHARMEM_DATA+$0100,x
	sta $0400+$0100,x
	lda KOALA_CHARMEM_DATA+$0200,x
	sta $0400+$0200,x
	lda KOALA_CHARMEM_DATA+$02e8,x
	sta $0400+$02e8,x

	; $d800: color %11
	lda KOALA_COLORMEM_DATA,x
	sta $d800,x
	lda KOALA_COLORMEM_DATA+$0100,x
	sta $d800+$100,x
	lda KOALA_COLORMEM_DATA+$0200,x
	sta $d800+$200,x
	lda KOALA_COLORMEM_DATA+$02e8,x
	sta $d800+$02e8,x

	inx
	bne @loop
	rts
.endproc

;--------------------------------------------------------------------------
; init_scroll_colors(void)
;--------------------------------------------------------------------------
; Args: -
;--------------------------------------------------------------------------
.proc init_scroll_colors
	; foreground RAM color for scroll lines
	ldx #0
	; 9 lines: 40 * 9 = 360. 256 + 104
@loop:
	; clear color
	lda #SCROLL_BKG_COLOR
	sta $d800 + SCROLL_AT_LINE * 40,x
	sta $d800 + SCROLL_AT_LINE * 40 + (ROWS_PER_CHAR*40-256),x

	; clear char
	lda #$ff
	sta $0400 + SCROLL_AT_LINE * 40,x
	sta $0400 + SCROLL_AT_LINE * 40 + (ROWS_PER_CHAR*40-256),x

	inx
	bne @loop
	rts
.endproc

;--------------------------------------------------------------------------
; init_scroll_vars(void)
;--------------------------------------------------------------------------
; Args: -
;--------------------------------------------------------------------------
.proc init_scroll_vars
	lda #$07
	sta smooth_scroll_x
	lda #$80
	sta chars_scrolled
	lda #$00
	sta current_char
	lda #$07
	sta anim_speed
	lda #ANIM_TOTAL_FRAMES-1
	sta anim_char_idx
	lda #$00
	sta scroller_text_ptr_low
	sta scroller_text_ptr_hi
	rts
.endproc

;--------------------------------------------------------------------------
; init_charset(void)
;--------------------------------------------------------------------------
; Args: -
; copies 3 custom chars to the correct address
;--------------------------------------------------------------------------
.proc init_charset
	ldx #$07
@loop:
	lda empty_char,x
	sta $3800 + $ff*8,x
	eor #$ff
	sta $3800 + $fe*8,x
	dex
	bpl @loop
	rts
.endproc

;--------------------------------------------------------------------------
; variables
;--------------------------------------------------------------------------

; IMPORTANT: raster_colors must be at the beginning of the page in order to avoid extra cycles.
.segment "INTRO_DATA"
raster_colors:
raster_colors_top:
	; Color washer palette taken from: Dustlayer intro
	; https://github.com/actraiser/dust-tutorial-c64-first-intro/blob/master/code/data_colorwash.asm
	.byte $09,$09,$02,$02,$08,$08,$0a,$0a
	.byte $0f,$0f,$07,$07,$01,$01,$01,$01
	.byte $01,$01,$01,$01,$01,$01,$01,$01
	.byte $07,$07,$0f,$0f,$0a,$0a,$08,$08
	.byte $02,$02,$09,$09

raster_colors_bottom:
	.byte $09,$09,$02,$02
	.byte $08,$08,$0a,$0a,$0f,$0f,$07,$07
	.byte $01,$01,$01,$01,$01,$01,$01,$01
	.byte $01,$01,$01,$01,$07,$07,$0f,$0f
	.byte $0a,$0a,$08,$08,$02,$02,$09,$09
	; FIXME: ignore, for overflow
	.byte 0

TOTAL_RASTER_LINES = raster_colors_bottom-raster_colors_top

raster_color_start:	.byte RASTER_SDKBOX_START
raster_color_end:	.byte RASTER_SDKBOX_END
sdkbox_bkg_color:	.byte 1
sync:			.byte 0
sync50hz:		.byte 0
smooth_scroll_x:	.byte 7
chars_scrolled:		.byte 128
current_char:		.byte 0
anim_speed:		.byte 7
anim_char_idx:		.byte ANIM_TOTAL_FRAMES-1
scroller_text_ptr_low:	.byte 0
scroller_text_ptr_hi:	.byte 0
colorwash_delay:	.byte COLORWASH_SPEED

scroller_text:
	scrcode "            sdkbox, the cure for sdk fatigue. the first and only sdk available for all the 64 machines: "
	scrcode "  ios 64-bit support: yes.  android 64-bit support: yes.  commodore 64 support: yes!   only us support all the 64 machines... long live the commodore 64"
	scrcode "    download sdkbox from sdkbox.com "
	.byte $ff

char_frames:
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00011000
	.byte %00011000
	.byte %00000000
	.byte %00000000
	.byte %00000000

	.byte %00000000
	.byte %00000000
	.byte %00011000
	.byte %00111100
	.byte %00111100
	.byte %00011000
	.byte %00000000
	.byte %00000000

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00011000
	.byte %00011000
	.byte %00000000
	.byte %00000000
	.byte %00000000

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000

empty_char:
	.byte %11111111
	.byte %11111111
	.byte %11111111
	.byte %11111111
	.byte %11111111
	.byte %11111111
	.byte %11111111
	.byte %11111111

sine_idx: .byte $00
sine_table:
	.incbin "res/sine_table.bin"
sine_big_table:
	.incbin "res/sine_big_table.bin"
sine_freq4_table:
	.incbin "res/sine_freq4_table.bin"
sine_short_fast_table:
	.incbin "res/sine_l128_table.bin"
sine_half_table:
	.incbin "res/sine_half_l128_table.bin"

.segment "SIDMUSIC"
	 .incbin "res/1_45_Tune.sid",$7e

.segment "INTRO_GFX"
	 .incbin "res/sdkbox.kla",2

.segment "INTRO_CHARSET"
	.incbin "res/font-boulderdash-1writer.bin"

