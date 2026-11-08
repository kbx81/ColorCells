; ============================================================================
;  Color Cells CC784 LED sign (original model) - firmware source, reconstructed from EPROM
;  Assemble:  sjasmplus cc784.asm   (produces cc784.bin, 16384 bytes)
;  Byte-identical to the original EPROM dump:
;      md5 3e7a679f77d7dac121926182442f923a
;  FROZEN. Annotations may be added; code must not change.
;
;  The firmware is copyright its original owner (Color Cells / Innovative Sign
;  Technology, and successors); reconstructed for preservation and
;  interoperability. The labels and comments are MIT, see ../../LICENSE.
;
;  CC784 (original model, ROM ID '9g'): the ten-channel ancestor of the CC710 code
;  base, 9 KB of code (to 0x234C) in a 16 KB image. 2 KB RAM (store 4262-47FF),
;  86-byte rows for the 84-column panel, bit timing for a 1302 Hz tick. Keypad or
;  serial input chosen at boot from PORT_IN bit 0; no packet protocol, no ROM-ID
;  query, no IR. Labels shared with the CC710 and NIR sources mean the same routine.
;  See firmware.md section 16.
; ============================================================================
        DEVICE NONE
        OUTPUT "cc784.bin"

FRAMEBUF             equ 0x4040
FRAMEBUF_SIZE        equ 0xac   ; column ring: 86 visible + the glyph being written; also the TINY line
FRAMEBUF_ROW1        equ FRAMEBUF+0x56
; ---- variables follow the ring; their layout is baked into INIT_DATA, so only
;      the base moves
RAM_VARS             equ FRAMEBUF+FRAMEBUF_SIZE

FB_COLPTR            equ RAM_VARS+0x000   ; frame-buffer write pointer (next glyph column)
FB_COL               equ RAM_VARS+0x003   ; scroll position: the column the output window is moving toward
BGRND_PENDING        equ RAM_VARS+0x008   ; editor: BGRND key pressed, next key is the color digit
TXBUF                equ RAM_VARS+0x009   ; the effect staging frame (86 columns)
STAGE_PTR            equ RAM_VARS+0x05f   ; next free column in TXBUF while an effect stages text
STAGE_OFFSET         equ RAM_VARS+0x062   ; centering offset of the staged text (free columns / 2)
ROW_PORT             equ RAM_VARS+0x064   ; port group for the row data: 40 first pass, 48 second
BEEP_TICKS           equ RAM_VARS+0x065   ; beeper on while non-zero (port bit 5); beep_start loads BEEP_LEN
CLK_H10              equ RAM_VARS+0x067
CLK_H1               equ RAM_VARS+0x068
CLK_SEC              equ RAM_VARS+0x06b
CLK_PM               equ RAM_VARS+0x06c
CLK_RUN              equ RAM_VARS+0x06d
GLYPH_WIDTH          equ RAM_VARS+0x06e
GLYPH_PTR            equ RAM_VARS+0x06f
MENU_MSG_PTR         equ RAM_VARS+0x071   ; message the editor is showing (set with MENU_MSG_FLAG)
CUR_COLOR            equ RAM_VARS+0x073
SCROLLING            equ RAM_VARS+0x074   ; FF while the output window is catching up with FB_COLPTR
CUR_CHAR             equ RAM_VARS+0x075
FB_OUT_PTR           equ RAM_VARS+0x079   ; first column sent to the panel (start of the output window)
DISP_ON              equ RAM_VARS+0x07b   ; 0 suppresses row output (effects rewrite FRAMEBUF meanwhile)
CLK_RENDER_STEP      equ RAM_VARS+0x07c   ; clock (5F) render step 0..8; FF = finished
CLK_RENDER_PTR       equ RAM_VARS+0x07d   ; clock render: next CLK_ digit to emit
MENU_ACTIVE          equ RAM_VARS+0x07f
INS_PTR              equ RAM_VARS+0x080
MAGIC_MODE           equ RAM_VARS+0x082   ; FF from MAGIC (1F) until a color byte or the next channel
WINDOW_COLOR         equ RAM_VARS+0x083   ; last color byte at the output window start (bit 4 = flash)
COL_COUNT            equ RAM_VARS+0x084   ; columns still free in the staging frame; 0 = no staging (LEFT)
FRAME_COUNT          equ RAM_VARS+0x085   ; frames since LATCH_BIT7 last toggled (mod 13)
FLASH_BIT            equ RAM_VARS+0x086   ; 0x10 while the current word flashes; OR-ed into color bytes
LATCH_BIT7           equ RAM_VARS+0x087   ; 00/80 toggled every 13 frames, OR-ed into CTRL_LATCH bit 7
COLOR_PENDING        equ RAM_VARS+0x088   ; editor: COLOR key pressed, next key is the color digit
GRAPH_PENDING        equ RAM_VARS+0x089   ; editor: GRAPH key pressed, next key selects A0-AF
ROW_COLOR            equ RAM_VARS+0x08a   ; color byte sent ahead of each row
INPUT_MODE           equ RAM_VARS+0x08b   ; 00 keypad, FF serial (PORT_IN bit 0 low at boot)
MENU_MSG_FLAG        equ RAM_VARS+0x08c   ; FF = editor has a message to display
EDIT_KEY             equ RAM_VARS+0x08d   ; key/character the editor is processing (0 = none)
PREV_KEY             equ RAM_VARS+0x08e   ; editor key history (written, never read)
PREV_KEY2            equ RAM_VARS+0x08f   ; editor key history (written, never read)
RX_BYTE              equ RAM_VARS+0x090
IR_KEY_CHAR          equ RAM_VARS+0x091   ; key being read; translated through the CHARSET_ tables
KEY_TIMER            equ RAM_VARS+0x092   ; counts down each tick: keypad debounce pacing in editor_getkey and editor_exit
CTRL_LATCH_SHADOW    equ RAM_VARS+0x095
FB_OUT_LEN           equ RAM_VARS+0x098   ; bytes to send from FB_OUT_PTR before wrapping to FRAMEBUF
FB_EXTRA_LEN         equ RAM_VARS+0x09a   ; bytes to send from FRAMEBUF after the wrap
STORE_END            equ RAM_VARS+0x09c
STORE_WRAPPED        equ RAM_VARS+0x09e   ; FF when the editor cursor reached STORE_TOP (written, never read)
EFFECT_ID            equ RAM_VARS+0x0a2   ; 0 CRAWL, 1 JUMP, 2 UP, 3 DOWN, 4 BCRAWL
EFFECT_VECTOR        equ RAM_VARS+0x0a3
MENU_TEXT_PTR        equ RAM_VARS+0x0a5
SHIFT_LABEL          equ RAM_VARS+0x0a9   ; FF = redraw shows the SHIFT indicator
FLUSH_PENDING        equ RAM_VARS+0x0aa   ; FF = staged text must be shown before the next effect runs
PROG_MSG_FORCE       equ RAM_VARS+0x0ab   ; FF while PROG MSG? waits for its channel key
FRAME_DELAY          equ RAM_VARS+0x0ac   ; frames to hold before the next column step (1, 3 or 0x50)
ROW_INDEX            equ RAM_VARS+0x0ad
RX_BITMASK           equ RAM_VARS+0x0ae
RX_SHIFT             equ RAM_VARS+0x0b0
RX_TICKS             equ RAM_VARS+0x0b1
RX_FIFO              equ RAM_VARS+0x0b2
RX_COUNT             equ RAM_VARS+0x0ba
RX_TIMING_PTR        equ RAM_VARS+0x0bb
REDRAW_PTR           equ RAM_VARS+0x0bd   ; editor redraw: byte being rendered
RX_STATE             equ RAM_VARS+0x0bf
CHAN_STATE           equ RAM_VARS+0x0c1   ; 11 bytes cleared by clear_chan_lock; only CHAN_LOCK (last) is read
CHAN_LOCK            equ RAM_VARS+0x0cb
SEQ_LIST             equ RAM_VARS+0x0cc
SEQ_PTR              equ RAM_VARS+0x0ec
SEQ_ALL_EMPTY        equ RAM_VARS+0x0ee   ; 10 = every listed channel is empty, play the demo
GLYPH_BUF            equ RAM_VARS+0x0ef   ; working copy of the glyph (bold/plain), 32 bytes
GLYPH_BUF_ITALIC     equ RAM_VARS+0x10f   ; sheared copy for ITALIC, 32 bytes
GLYPH_BUF_BIG        equ RAM_VARS+0x12f   ; widened copy for BIG, 32 bytes
SEQ_MENU_ACTIVE      equ RAM_VARS+0x14f   ; FF while the SEQ MSG? dialogue runs
SHIFT_STATE          equ RAM_VARS+0x150   ; SHIFT latch, toggled by key code 19
PREV_SPACE           equ RAM_VARS+0x151   ; 1 = previous char was a space (two in a row reset the background)
FONT_MODE            equ RAM_VARS+0x152   ; bit 1 BOLD, bit 2 ITALIC, bit 3 BIG
TINY_MODE            equ RAM_VARS+0x153   ; FF = glyphs go to the tiny buffer (menus, TINY)
FORCE_BOLD           equ RAM_VARS+0x154   ; editor redraw: FF = effect text is drawn bold
NMI_COUNT            equ RAM_VARS+0x155
STORE_TMP            equ RAM_VARS+0x157
MOVE_DST             equ RAM_VARS+0x159
MOVE_SRC             equ RAM_VARS+0x15b
REDRAW_FROM          equ RAM_VARS+0x15d   ; editor redraw: first byte actually displayed (cursor-21, >= INS_PTR)
STORE_CURSOR         equ RAM_VARS+0x15f
TX_BITIDX            equ RAM_VARS+0x161
TX_BITMASK           equ RAM_VARS+0x162
TX_PENDING           equ RAM_VARS+0x163
TX_TICKS             equ RAM_VARS+0x164
TX_SHIFT             equ RAM_VARS+0x165
TX_STATUS            equ RAM_VARS+0x166
TX_TIMING_PTR        equ RAM_VARS+0x167
CAPS_LOCK            equ RAM_VARS+0x169
ROW_OUT_PENDING      equ RAM_VARS+0x16a   ; FF = the current row still has to be sent
MY_ADDRESS           equ RAM_VARS+0x16b   ; menu_enter's gate byte, set by editor key 5E (not initialised)
MAGIC_COLOR_IDX      equ RAM_VARS+0x16c   ; index into MAGIC_COLOR_CYCLE
STORE_BAD_COUNT      equ RAM_VARS+0x16d   ; bytes replaced by ? in store_fix_bad_bytes (never read)
SPEED_PENDING        equ RAM_VARS+0x16e   ; editor: SPEED key pressed, next key is the digit
SCROLL_SPEED         equ RAM_VARS+0x16f   ; 0..7 from F0-F7; blank ticks inserted after every frame
BLANK_TIMER          equ RAM_VARS+0x170
GLYPH_PTR_ORIG       equ RAM_VARS+0x171   ; glyph address before bold/italic/big copies
KEY_ECHO_TX          equ RAM_VARS+0x173   ; non-zero = echo accepted keys on serial TX
MSG_STORE            equ RAM_VARS+0x176
STACK_TOP            equ 0x403f   ; SP at reset; the stack grows down from below FRAMEBUF
STORE_TOP            equ 0x47ff   ; last RAM byte: the store runs from MSG_STORE to here
STORE_LEN            equ STORE_TOP+1-MSG_STORE   ; 1438 bytes
CTRL_LATCH           equ 0x8000

PORT_STROBE          equ 0x80
PORT_IN              equ 0xc0

; ---- Tuning and geometry (names shared with src/patched) ----------------------
FLASH_HALF_PERIOD    equ 13   ; frames per half period of CTRL_LATCH bit 7, the FLASH blink clock (2.4 Hz)
FRAME_COLS           equ 86   ; columns sent per row: the panel's 84 plus two that fall off the chain
HOLD_FRAMES          equ 80   ; frames a PAUSE, JUMP, wipe or clock holds the panel
BEEP_LEN             equ 150   ; beeper on for this many ticks (~115 ms)

; ---- Message store format ------------------------------------------------------
MARK_LO              equ 0xd0   ; channel markers are one byte, D0+channel (0-9)
MARK_HI              equ 0xda   ; alone, DA ends the store; it also precedes DEMO_MESSAGE
TEXT_END             equ 0x03   ; ends a channel's text

; ---- Message attribute bytes (NIR names; this ROM's own labels in the comments) ----
ATTR_BIG             equ 0x10
ATTR_NORM            equ 0x11
ATTR_FLASH           equ 0x14
ATTR_COLOR           equ 0x15   ; FORE
ATTR_BGRND           equ 0x16   ; BACK
ATTR_LEFT            equ 0x18   ; CRAWL
ATTR_PAUSE           equ 0x19   ; JUMP
ATTR_UP              equ 0x1a
ATTR_DOWN            equ 0x1b
KEY_CASE             equ 0x1c   ; UPPER/LOWER key
KEY_SHIFT            equ 0x1d
ATTR_GRAPH           equ 0x1e
ATTR_MAGIC           equ 0x1f
KEY_DEL              equ 0x7f
COLOR_BASE           equ 0x80   ; 80-8F foreground: bits 0-1 green, 2-3 red intensity
COLOR_DEFAULT        equ 0x8f   ; yellow, full
COLOR_FLASH          equ 0x10   ; the FLASH bit in a frame-buffer color byte
BGRND_BASE           equ 0x90   ; 90-93 background
GRAPH_BASE           equ 0xa0   ; A0-AF built-in graphics
SPEED_BASE           equ 0xf0   ; F0-F7 scroll speed
LATCH_TX             equ 0x10   ; CTRL_LATCH bit 4: serial TX
LATCH_BLINK          equ 0x80   ; CTRL_LATCH bit 7: the FLASH blink clock

        org 0x0000


; ---- RESET: cold start: SP, init_vars, store_init (serial or keypad), boot_clear_check,
;      then fall into restart_display
RESET:
        LD SP,STACK_TOP
        CALL init_vars
        CALL store_init
        CALL boot_clear_check

; ---- restart_display: re-init the renderer, repair the store, rebuild the sequence, EI and
;      start the next channel. RESET falls into it; editor_exit jumps here
restart_display:
        CALL init_render

; ---- restart_no_render: tail of restart_display without init_render
restart_no_render:
        CALL store_repair
        CALL init_sequence
        EI
        JP main_start_channel

        ds 0x0038-$,0xff

; ---- INT_VECTOR: IM 1 interrupt entry: the periodic timer (1302 Hz, the rate
;      RX_TIMING/TX_TIMING assume for 300 baud)
INT_VECTOR:
        CALL int_timer
        EI
        RETI

        ds 0x0060-$,0xff

; ---- ROM_REV: the firmware ID '9g', in the spot where the CC710 keeps its revision; there
;      is no model string at 0x0050 and nothing reads it (no ROM-ID query in this ROM)
ROM_REV:
        db 0x39,0x67,0xff,0xff,0xff,0xff

; ---- NMI_VECTOR: NMI = real-time clock tick (mains frequency); calls clock_tick
NMI_VECTOR:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        CALL clock_tick
        POP HL
        POP DE
        POP BC
        POP AF
        RETN

; ---- main_start_channel: main loop: init_render, pick the next channel, then render
;      forever. No packet check: this ROM has no packet protocol
main_start_channel:
        CALL init_render
        CALL seq_next_channel

render_loop:
        CALL render_next_char
        CALL effect_step
        JP render_loop

; ---- int_timer: timer ISR body in the alternate register set: the serial bit engines
;      (skipped in keypad mode), beeper countdown, row refresh / frame step, then the input
;      poll. No sentinel check, no mode test
int_timer:
        EX AF,AF'
        EXX
        LD A,(INPUT_MODE)
        AND A
        JR z,tick6_beep

tick6_engines:
        CALL rx_bit_engine
        CALL tx_bit_engine

; ---- tick6_beep: count BEEP_TICKS down; the row output sets port bit 5 while it is
;      non-zero
tick6_beep:
        LD HL,(BEEP_TICKS)
        LD A,H
        OR L
        JR z,tick6_display
        DEC HL
        LD (BEEP_TICKS),HL

tick6_display:
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,row_output
        LD A,(EFFECT_ID)
        AND A
        JR nz,row_output
        LD A,(BLANK_TIMER)
        AND A
        JR z,row_output
        DEC A
        LD (BLANK_TIMER),A
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        JP tick6_restore

row_output:
        LD A,(ROW_OUT_PENDING)
        AND A
        JP z,row_advance
        LD A,(DISP_ON)
        AND A
        JR nz,row_out_send
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        JR row_phase_step

; ---- row_out_send: DISP_ON set: send ROW_COLOR then the 86-column output window to port
;      ROW_PORT | (6 - ROW_INDEX), bit 5 set while beeping. The second OTIR (row_out_wrap) is
;      the part of the window that wrapped round the 172-byte FRAMEBUF ring
row_out_send:
        LD HL,(FB_OUT_PTR)
        LD A,(FB_OUT_LEN)
        LD B,A
        LD A,(ROW_PORT)
        LD C,A
        LD A,(ROW_INDEX)
        CPL
        AND 7
        DEC A
        OR C
        LD C,A
        PUSH IX
        LD IX,BEEP_TICKS
        LD A,(IX+0)
        OR (IX+1)
        POP IX
        JR z,row_out_color
        SET 5,C

row_out_color:
        LD A,(ROW_COLOR)
        OUT (C),A
        LD A,B
        AND A
        JR z,row_out_wrap
        BIT 0,B
        JR z,row_out_data
        DEC B
        JR z,row_out_last

row_out_data:
        OTIR
        LD A,(FB_OUT_LEN)
        BIT 0,A
        JR z,row_out_wrap
        LD B,1

row_out_last:
        LD A,(HL)
        OUT (C),A

row_out_wrap:
        LD A,(FB_EXTRA_LEN)
        AND A
        JR z,row_strobe
        LD B,A
        LD HL,FRAMEBUF
        OTIR

row_strobe:
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x70
        OR 15
        LD (CTRL_LATCH),A
        OUT (PORT_STROBE),A
        LD A,(ROW_INDEX)
        CPL
        AND 7
        DEC A
        JR nz,row_select
        LD A,7

row_select:
        LD C,A
        LD A,(LATCH_BIT7)
        OR C
        AND 0x8f
        LD C,A
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x70
        OR C
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A

row_phase_step:
        LD A,(ROW_PORT)
        CP 0x48
        JR z,row_phase_done
        LD A,0x48
        LD (ROW_PORT),A
        JR row_exit

row_phase_done:
        XOR A
        LD (ROW_OUT_PENDING),A

row_exit:
        JP tick6_restore

row_advance:
        LD A,(ROW_INDEX)
        LD C,A
        INC A
        LD (ROW_INDEX),A
        CP 7
        JP c,tick6_arm_row
        LD A,0
        LD (ROW_INDEX),A
        LD A,(SCROLL_SPEED)
        LD (BLANK_TIMER),A
        LD A,(FRAME_DELAY)
        AND A
        JR z,frame_scroll
        DEC A
        LD (FRAME_DELAY),A
        JP frame_bit7_tick

frame_scroll:
        LD A,(SCROLLING)
        AND A
        JR z,frame_check_still
        LD HL,(FB_COL)
        LD DE,FRAME_COLS
        CALL fb_ptr_add
        LD DE,(FB_COLPTR)
        OR A
        SBC HL,DE
        JR z,frame_scroll_stop
        LD HL,(FB_COL)
        CALL fb_ptr_inc
        LD (FB_COL),HL
        LD DE,FRAME_COLS
        CALL fb_ptr_add
        LD DE,(FB_COLPTR)
        OR A
        SBC HL,DE
        JR nz,frame_color

frame_scroll_stop:
        XOR A
        LD (SCROLLING),A
        JP frame_color

frame_check_still:
        LD HL,(FB_OUT_PTR)
        LD DE,(FB_COL)
        OR A
        SBC HL,DE
        JP z,frame_bit7_tick

frame_color:
        LD HL,(FB_COL)
        BIT 7,(HL)
        JR z,frame_latch_color
        LD A,(HL)
        LD (WINDOW_COLOR),A

frame_latch_color:
        LD A,(EFFECT_ID)
        AND A
        LD A,(WINDOW_COLOR)
        JR z,frame_set_window
        AND COLOR_FLASH
        OR COLOR_DEFAULT

frame_set_window:
        LD (ROW_COLOR),A
        LD HL,(FB_COL)
        LD (FB_OUT_PTR),HL
        LD HL,FB_COLPTR
        LD BC,(FB_COL)
        LD DE,FRAME_COLS
        XOR A
        SBC HL,BC
        XOR A
        LD (FB_OUT_LEN),HL
        EX DE,HL
        SBC HL,DE
        JP z,frame_window_wrap
        JP c,frame_window_wrap
        JP frame_set_extra

frame_window_wrap:
        LD HL,FRAME_COLS
        LD (FB_OUT_LEN),HL
        LD HL,0

frame_set_extra:
        LD (FB_EXTRA_LEN),HL

frame_bit7_tick:
        LD A,(FRAME_COUNT)
        INC A
        LD (FRAME_COUNT),A
        CP FLASH_HALF_PERIOD
        JR nz,frame_done
        XOR A
        LD (FRAME_COUNT),A
        LD A,(LATCH_BIT7)
        AND A
        JR z,frame_bit7_set
        XOR A
        LD (LATCH_BIT7),A
        JR frame_done

frame_bit7_set:
        LD A,LATCH_BLINK
        LD (LATCH_BIT7),A

frame_done:
        NOP

; ---- rx_consume: input, once per tick. Serial mode (INPUT_MODE non-zero): pop RX_FIFO
;      through rx_fifo_get, which translates the byte; keypad mode: rx_keypad
rx_consume:
        LD A,(INPUT_MODE)
        AND A
        JR z,rx_keypad
        CALL rx_fifo_get
        AND A
        JR z,tick6_exit
        JR rx_not_start

; ---- rx_keypad: keypad mode: scan the keypad into RX_BYTE; no key -> tick6_exit
rx_keypad:
        CALL keypad_scan
        AND A
        JR z,tick6_exit

; ---- rx_not_start: a key code outside the editor: 35 = STOP/START (serial 01 is mapped to
;      it) opens the editor with echo, 7E opens menu_enter; anything else is dropped
rx_not_start:
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,tick6_exit
        LD A,(RX_BYTE)
        CP 0x35
        JP z,key_handler
        CP 0x7e
        JP z,menu_enter

; ---- tick6_exit: KEY_TIMER counts down here; editor_getkey and editor_exit set it to 2 to
;      pace their keypad samples
tick6_exit:
        LD A,(KEY_TIMER)
        AND A
        JR z,tick6_arm_row
        DEC A
        LD (KEY_TIMER),A

tick6_arm_row:
        LD A,0xff
        LD (ROW_OUT_PENDING),A
        LD A,0x40
        LD (ROW_PORT),A

; ---- tick6_restore: back to the main register set (EXX pair instead of pushes)
tick6_restore:
        EX AF,AF'
        EXX
        RET

; ---- init_sequence: validate the 32-entry SEQ_LIST (entries 0-10, FF ends it): a first
;      byte of FF or a stray value resets it from SEQ_DEFAULT; then flag SEQ_ALL_EMPTY =
;      10 when no listed channel has text
init_sequence:
        XOR A
        LD (SEQ_ALL_EMPTY),A
        LD B,0x20
        LD HL,SEQ_LIST
        LD A,(HL)
        CP 0xff
        JR z,seq_reset_default

; ---- seq_scan: walk the list while entries are < 11; no terminator in 32 -> force FF
;      into the last slot
seq_scan:
        CP 11
        JR nc,seq_scan_end
        INC HL
        LD A,(HL)
        DJNZ seq_scan
        DEC HL
        LD (HL),0xff
        JP seq_check_first

seq_scan_end:
        CP 0xff
        JR z,seq_check_first

; ---- seq_reset_default: copy SEQ_DEFAULT (0..9, FF...) until its 0x32 sentinel
seq_reset_default:
        LD DE,SEQ_DEFAULT
        LD HL,SEQ_LIST

seq_fill:
        LD A,(DE)
        CP 0x32
        JR z,seq_check_first
        LD (HL),A
        INC HL
        INC DE
        JP seq_fill

seq_check_first:
        LD HL,SEQ_LIST

seq_check_loop:
        LD A,(HL)
        INC HL
        PUSH HL
        CP 0xff
        JR z,seq_all_empty
        CALL chan_select
        OR A
        JP nz,store_fault_reset
        LD A,(HL)
        CP TEXT_END
        POP HL
        RET nz
        JP seq_check_loop

seq_all_empty:
        POP HL
        LD A,10
        LD (SEQ_ALL_EMPTY),A
        RET

; ---- SEQ_DEFAULT: default SEQ_LIST image: channels 0-9 then FF (32 bytes), followed by the
;      0x32 end sentinel seq_reset_default stops on
SEQ_DEFAULT:
        db 0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0xff,0xff,0xff,0xff,0xff,0xff
        db 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
        db 0x32

; ---- seq_next_channel: pick the channel to display next: the demo (10) when SEQ_ALL_EMPTY,
;      else the next SEQ_LIST entry, wrapping at FF. An entry >= 11 resets the sign. No
;      TEST_MODE or NEXT_CHAN in this ROM
seq_next_channel:
        LD A,(SEQ_ALL_EMPTY)
        LD E,A
        CP 10
        JR z,seq_open_channel
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JR nz,seq_advance
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        JP seq_next_channel

; ---- seq_advance: entry >= 11 -> RESET; else E = channel, SEQ_PTR++
seq_advance:
        CP 11
        JP nc,store_fault_reset
        LD A,(HL)
        LD E,A
        INC HL
        LD (SEQ_PTR),HL

; ---- seq_open_channel: A = channel 0-10: chan_select; empty (03) -> seq_chan_empty; else
;      STORE_CURSOR = its text, CHAN_STATE[E] = FF (E = 10 sets CHAN_LOCK)
seq_open_channel:
        CALL chan_select
        OR A
        JP nz,store_fault_reset
        LD A,(HL)
        CP 3
        JR z,seq_chan_empty
        LD (STORE_CURSOR),HL
        CALL clear_chan_lock
        LD D,0
        LD HL,CHAN_STATE
        ADD HL,DE
        LD A,0xff
        LD (HL),A
        RET

; ---- seq_chan_empty: skip an empty channel; a list of one empty channel plays the demo
;      instead
seq_chan_empty:
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JR nz,seq_next_channel
        DEC HL
        LD DE,SEQ_LIST
        OR A
        SBC HL,DE
        JR nz,seq_next_channel
        LD A,10
        JP seq_open_channel

; ---- clear_chan_lock: clear the 11 CHAN_STATE bytes (CHAN_LOCK is the last)
clear_chan_lock:
        LD HL,CHAN_STATE
        LD B,11
        LD A,0

clr_lock_loop:
        LD (HL),A
        INC HL
        DJNZ clr_lock_loop
        RET

; ---- chan_select: A & 15 = channel 0-10. 10 -> HL = DEMO_MARKER. Else CPIR for the one-byte
;      marker D0+n in MSG_STORE; HL -> first text byte. A = 0 found, FF not found
chan_select:
        AND 15
        CP 10
        JR nz,chan_scan
        LD HL,DEMO_MARKER
        JP chan_ok

chan_scan:
        OR 0xd0
        LD HL,MSG_STORE
        LD BC,STORE_LEN
        CPIR
        LD A,B
        OR C
        JP z,chan_error

chan_ok:
        XOR A
        RET

chan_error:
        LD A,0xff
        RET

; ---- store_repair: every boot: bad bytes -> ?, stray 03 -> space, then re-write the
;      markers D0..D9 one byte each over the Dx bytes found, append the missing ones, put
;      03 before every marker (store_add_ends) and DA after the last. The byte before the
;      first marker (MSG_STORE-1) gets a space
store_repair:
        CALL store_fix_bad_bytes
        CALL store_strip_ends
        LD HL,MSG_STORE
        LD A,MARK_LO
        LD E,A
        LD BC,0x0589

; ---- repair_marker: write marker E at HL, E++; E = DB means all ten are placed
repair_marker:
        LD (HL),E
        INC E
        LD A,0xdb
        CP E
        JR nz,repair_after_marker
        DEC HL
        LD (HL),0x20
        INC HL
        JP repair_terminate

; ---- repair_after_marker: space before the marker; a marker byte directly after it
;      becomes a space so every channel keeps at least one text byte
repair_after_marker:
        DEC HL
        LD (HL),0x20
        INC HL
        INC HL
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JR nz,repair_scan_from
        LD (HL),0x20

repair_scan_from:
        INC HL

; ---- repair_scan: find the next Dx byte; at the end of the store append the missing markers
repair_scan:
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JR z,repair_marker

repair_scan_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR z,repair_append_rest
        JP repair_scan

repair_append_rest:
        LD A,MARK_HI

repair_append_loop:
        LD (HL),E
        CP E
        JR z,repair_terminate
        INC HL
        LD (HL),3
        INC HL
        INC E
        CP E
        JR nz,repair_append_loop
        LD (HL),A

repair_terminate:
        PUSH HL
        CALL store_add_ends
        POP HL
        LD A,MARK_HI
        LD (HL),A
        RET

store_fix_bad_bytes:
        LD HL,MSG_STORE
        LD BC,STORE_LEN
        LD IY,STORE_BAD_COUNT
        LD (IY+0),0
        LD D,0

fixbad_loop:
        LD E,(HL)
        LD IX,CHAR_FLAGS
        ADD IX,DE
        BIT 0,(IX+0)
        JR z,fixbad_next
        LD (HL),'?'
        INC (IY+0)

fixbad_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,fixbad_loop
        RET

store_strip_ends:
        LD HL,MSG_STORE
        LD BC,STORE_LEN

strip_loop:
        LD A,(HL)
        CP TEXT_END
        JR nz,strip_next
        LD (HL),' '

strip_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,strip_loop
        RET

; ---- store_add_ends: from MSG_STORE+1, put 03 in front of every Dx byte in the store
store_add_ends:
        LD IX,MSG_STORE+1
        LD BC,STORE_LEN

addends_loop:
        LD A,(IX+0)
        AND 0xf0
        CP 0xd0
        JR nz,addends_next
        LD (IX-1),TEXT_END

addends_next:
        INC IX
        DEC BC
        LD A,C
        OR B
        JR nz,addends_loop
        RET

; ---- init_vars: zero KEY_ECHO_TX, SPEED_PENDING, SCROLL_SPEED and BLANK_TIMER, copy the
;      three INIT_DATA blocks, IM 1, SEQ_PTR = SEQ_LIST
init_vars:
        LD A,0x00
        LD (KEY_ECHO_TX),A
        LD (SPEED_PENDING),A
        LD (SCROLL_SPEED),A
        LD (BLANK_TIMER),A

init_copy_tables:
        LD HL,INIT_DATA
        LD BC,9
        LD DE,FB_COLPTR
        LDIR
        LD HL,INIT_DATA+9                            ; -> STAGE_PTR..
        LD DE,STAGE_PTR
        LD BC,96
        LDIR
        LD HL,INIT_DATA+0x6b                         ; -> SEQ_MENU_ACTIVE..
        LD DE,SEQ_MENU_ACTIVE
        LD BC,28
        LDIR
        IM 1
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        RET

; ---- INIT_DATA: three RAM images copied by init_vars: +0..+8 -> FB_COLPTR..BGRND_PENDING;
;      +9..+0x68 (96 bytes) -> STAGE_PTR..RX_STATE+1; +0x6B..+0x86 (28 bytes) ->
;      SEQ_MENU_ACTIVE..ROW_OUT_PENDING. +0x69..+0x6A are copied nowhere. The frame geometry
;      is 86 columns (0x56)
INIT_DATA:
        db 0x96,0x40,0x56,0x40,0x40,0x95,0x40,0x55,0x00

        db 0xf5,0x40,0x56,0x00,0x00,0x00,0x00,0x00,0x01,0x02,0x00,0x00,0x00,0x00,0x01,0x00
        db 0x00,0x00,0x00,0x00,0x0f,0x00,0x00,0x00,0x00,0x00,0x40,0x40,0x01,0x05,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x0f,0x00,0x00,0x0a,0x00,0x00,0x00,0x0f,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x56,0x00,0x00,0x00,0xff,0x47,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xfa,0x0c,0x00,0x00

        db 0xdb,0x0c

        db 0x00,0x00,0x00,0x00,0x00,0x00,0xb0,0x04,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x62,0x42,0x00,0x01,0x00,0x00,0x00,0x00,0x04,0x0d,0xff,0xff

; ---- init_render: reset the render state: the 172-byte ring cleared, window FRAME_COLS wide
;      at FRAMEBUF, no effect, default color 8F, staging at TXBUF; STORE_TOP = DA guards the
;      store end
init_render:
        CALL clear_framebuf
        LD HL,FRAMEBUF
        LD (FB_OUT_PTR),HL
        LD (FB_COL),HL
        LD HL,0
        LD (FB_EXTRA_LEN),HL
        LD HL,FRAME_COLS
        LD (FB_OUT_LEN),HL
        XOR A
        LD (MAGIC_MODE),A
        LD (TINY_MODE),A
        LD (CLK_RENDER_STEP),A
        LD (EFFECT_ID),A
        LD (FORCE_BOLD),A
        LD (FONT_MODE),A
        LD (FLASH_BIT),A
        LD (FRAME_DELAY),A
        LD (SCROLLING),A
        LD (SCROLL_SPEED),A
        LD A,COLOR_DEFAULT
        LD (WINDOW_COLOR),A
        LD (ROW_COLOR),A
        LD (CUR_COLOR),A
        LD HL,fxv_none
        LD (EFFECT_VECTOR),HL
        LD HL,FRAMEBUF_ROW1
        LD (FB_COLPTR),HL
        LD HL,TXBUF
        LD (STAGE_PTR),HL
        CALL clear_txbuf
        CALL clear_glyph_tmp
        LD HL,STORE_TOP
        LD (HL),MARK_HI
        RET

; ---- render_next_char: fetch the next store byte and act on it: MAGIC preprocessing, the
;      space tracking (FLASH ends at a space, two spaces drop the background), A0-AF
;      graphics, 80-FF colors/speed, 00-1F controls, 5F clock, else glyph_lookup
render_next_char:
        CALL fetch_char
        CALL magic_preprocess
        LD A,(CUR_CHAR)
        CP 0x20
        JR z,render_graphic_check
        XOR A
        LD (PREV_SPACE),A
        LD A,(CUR_CHAR)

; ---- render_graphic_check: A0-AF -> glyph 0-F
render_graphic_check:
        AND 0xf0
        CP GRAPH_BASE
        JR nz,render_classify
        LD A,(CUR_CHAR)
        AND 15
        LD (CUR_CHAR),A
        JR render_clear_prev_space

; ---- render_classify: bit 7 -> attr_color_speed; bits 5,6 clear -> attr_control; space
;      -> space_seen; else printable
render_classify:
        LD A,(CUR_CHAR)
        BIT 7,A
        JP nz,attr_color_speed
        AND 0x60
        JP z,attr_control
        LD A,(CUR_CHAR)
        CP 0x20
        JR nz,render_clear_prev_space

space_seen:
        XOR A
        LD (FLASH_BIT),A
        LD A,(PREV_SPACE)
        AND A
        JR nz,space_drop_bgrnd
        LD A,1
        LD (PREV_SPACE),A
        JR render_glyph_or_clock

; ---- space_drop_bgrnd: second space in a row: CUR_COLOR keeps only the foreground
space_drop_bgrnd:
        LD A,(CUR_COLOR)
        AND 15
        LD (CUR_COLOR),A

render_clear_prev_space:
        XOR A
        LD (PREV_SPACE),A

; ---- render_glyph_or_clock: 5F -> render_clock, else glyph_lookup
render_glyph_or_clock:
        LD A,(CUR_CHAR)
        CP 0x5f
        JP z,render_clock

; ---- glyph_lookup: HL = FONT + 8 * CUR_CHAR, GLYPH_WIDTH = byte 7. The byte indexes the
;      128-glyph font directly, so only 00-7F may reach here (A0-AF graphics arrive masked to
;      0-F)
glyph_lookup:
        LD A,(CUR_CHAR)
        LD HL,FONT
        LD E,A
        LD D,0
        SLA E
        RL D
        SLA E
        RL D
        SLA E
        RL D
        ADD HL,DE
        LD (GLYPH_PTR),HL
        LD (GLYPH_PTR_ORIG),HL
        LD DE,7
        ADD HL,DE
        LD A,(HL)
        LD (GLYPH_WIDTH),A

; ---- glyph_style: clear the glyph buffers; unless TINY_MODE (menus) apply bold / big /
;      italic, then the 00-0F double-width rule and glyph_place
glyph_style:
        CALL clear_glyph_tmp
        LD A,(TINY_MODE)
        AND A
        JR nz,glyph_place
        CALL glyph_bold
        CALL glyph_big
        CALL glyph_italic

glyph_graphic_check:
        LD A,(CUR_CHAR)
        AND 0xf0
        JR nz,glyph_place
        LD HL,(GLYPH_PTR)
        LD DE,(GLYPH_PTR_ORIG)
        OR A
        SBC HL,DE
        JR nz,glyph_double_width
        LD HL,(GLYPH_PTR)
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD B,0
        LD DE,GLYPH_BUF
        LDIR
        LD HL,GLYPH_BUF
        LD (GLYPH_PTR),HL

glyph_double_width:
        LD A,(GLYPH_WIDTH)
        SLA A
        CP 0x20
        JP c,glyph_set_width
        LD A,0x1f

glyph_set_width:
        LD (GLYPH_WIDTH),A

glyph_place:
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,blit_setup
        LD A,(EFFECT_ID)
        AND A
        JR nz,glyph_stage

blit_setup:
        LD DE,(GLYPH_PTR)
        LD HL,(FB_COLPTR)
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD A,(MENU_ACTIVE)
        AND A
        JR z,blit_flash_bit
        LD A,15
        LD (CUR_COLOR),A
        LD A,(TINY_MODE)
        AND A
        LD C,0
        JR nz,blit_color

blit_flash_bit:
        LD A,(FLASH_BIT)

blit_set_c:
        LD C,A

blit_color:
        PUSH BC
        LD A,(CUR_CHAR)
        CP ' '
        LD C,0xf0
        JR z,blit_write_color
        LD C,0xff

blit_write_color:
        LD A,(CUR_COLOR)
        AND C
        POP BC
        OR C
        SET 7,A
        LD (HL),A
        CALL fb_ptr_inc

blit_columns:
        LD A,(DE)
        LD (HL),A
        INC DE
        CALL fb_ptr_inc
        DJNZ blit_columns
        LD (FB_COLPTR),HL
        LD A,(MENU_ACTIVE)
        AND A
        LD A,0
        JR nz,blit_set_scroll
        LD A,0xff

blit_set_scroll:
        LD (SCROLLING),A
        RET

; ---- glyph_stage: effect active: stage the glyph into TXBUF instead
glyph_stage:
        LD HL,(STAGE_PTR)
        LD A,(GLYPH_WIDTH)
        LD D,0
        LD E,A
        ADD HL,DE
        LD DE,STAGE_PTR
        XOR A
        SBC HL,DE
        JP nc,fx_flush_stage
        LD DE,(STAGE_PTR)
        LD A,(FLASH_BIT)
        OR COLOR_DEFAULT
        LD (DE),A
        INC DE

stage_copy:
        LD HL,(GLYPH_PTR)
        LD A,(GLYPH_WIDTH)
        LD B,0
        LD C,A
        LDIR
        LD (STAGE_PTR),DE
        JP render_next_char

stage_centre:
        SRL H
        RR L
        LD (STAGE_OFFSET),HL
        CALL unfetch_char
        RET

; ---- fetch_char: CUR_CHAR = (STORE_CURSOR++)
fetch_char:
        PUSH HL
        PUSH AF
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        INC HL
        LD (STORE_CURSOR),HL
        LD (CUR_CHAR),A
        POP AF
        POP HL
        RET

; ---- magic_preprocess: MAGIC mode, outside effects and the editor: at a word start (the
;      byte two back is a space), when CUR_CHAR is a space or a font attribute 10-14 and the
;      next byte is printable or a graphic, step to the next MAGIC_COLOR_CYCLE entry and draw
;      a space in the new color ahead of the byte
magic_preprocess:
        LD A,(MENU_ACTIVE)
        AND A
        RET nz
        LD A,(MAGIC_MODE)
        AND A
        RET z
        LD A,(EFFECT_ID)
        AND A
        RET nz
        LD HL,(STORE_CURSOR)
        LD E,(HL)
        DEC HL
        DEC HL
        LD A,(HL)
        CP ' '
        RET nz

; ---- magic_printable: CUR_CHAR must be a space or 10-14
magic_printable:
        LD A,(CUR_CHAR)
        CP 0x20
        JR z,magic_check_next
        CP 0x10
        JR z,magic_check_next
        CP 0x11
        JR z,magic_check_next
        CP 0x12
        JR z,magic_check_next
        CP 0x13
        JR z,magic_check_next
        CP 0x14
        RET nz

; ---- magic_check_next: the next byte (E) must be a graphic or printable
magic_check_next:
        LD A,E
        AND 0xa0
        CP 0xa0
        JR z,magic_count_words
        LD A,E
        CP 0x20
        RET z
        AND 0x60
        RET z

magic_count_words:
        LD A,(CUR_CHAR)
        PUSH AF

; ---- magic_color_check: next entry of the cycle; when both the new and the current color
;      have a background, a space in color 0 goes out first
magic_color_check:
        LD A,(MAGIC_COLOR_IDX)
        INC A
        AND 0x3f
        LD (MAGIC_COLOR_IDX),A
        LD E,A
        LD D,0
        LD HL,MAGIC_COLOR_CYCLE
        ADD HL,DE
        PUSH HL
        LD A,(HL)
        AND 0x60
        JR z,magic_set_color
        LD A,(CUR_COLOR)
        AND 0x60
        JR z,magic_set_color
        XOR A
        LD (CUR_COLOR),A
        LD A,0x20
        LD (CUR_CHAR),A
        CALL glyph_lookup
        CALL effect_step

; ---- magic_set_color: CUR_COLOR = the entry, keeping the flash bit
magic_set_color:
        POP HL

magic_color_retry:
        LD A,(CUR_COLOR)
        AND COLOR_FLASH
        OR (HL)
        LD (CUR_COLOR),A

; ---- magic_reset_words: a space in the new color before the byte (unless it is a space
;      itself)
magic_reset_words:
        XOR A
        LD (PREV_SPACE),A
        POP AF
        CP 0x20
        RET z
        PUSH AF
        LD A,0x20
        LD (CUR_CHAR),A
        CALL glyph_lookup
        CALL effect_step
        POP AF
        LD (CUR_CHAR),A

magic_ret:
        RET

; ---- MAGIC_COLOR_CYCLE: 64 MAGIC colors: foreground in bits 0-3, background in bits 5-6;
;      MAGIC_COLOR_IDX walks it
MAGIC_COLOR_CYCLE:
        db 0x0d,0x07,0x03,0x6c,0x27,0x03,0x0c,0x4d,0x03,0x6c,0x4c,0x63,0x0d,0x2d,0x0c,0x07
        db 0x0c,0x4f,0x2f,0x27,0x0f,0x0d,0x2f,0x4d,0x03,0x07,0x07,0x63,0x0c,0x07,0x03,0x6c
        db 0x27,0x07,0x0f,0x4c,0x27,0x0c,0x07,0x4d,0x07,0x0d,0x6c,0x07,0x4c,0x27,0x07,0x03
        db 0x6c,0x0f,0x4f,0x2d,0x6c,0x0d,0x07,0x63,0x4d,0x03,0x07,0x03,0x0f,0x4d,0x2f,0x6c

; ---- unfetch_char: STORE_CURSOR back one byte
unfetch_char:
        LD HL,(STORE_CURSOR)
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        JR z,unfetch_ret
        LD HL,(STORE_CURSOR)
        DEC HL
        LD (STORE_CURSOR),HL

unfetch_ret:
        RET

; ---- glyph_bold: bold copy of the glyph in GLYPH_BUF: for BOLD, FORCE_BOLD or any effect.
;      Three full (7F) columns in a row collapse to two
glyph_bold:
        LD A,(FORCE_BOLD)
        AND A
        JR nz,bold_expand
        LD A,(EFFECT_ID)
        AND A
        JR nz,bold_expand

bold_check_mode:
        LD A,(FONT_MODE)
        BIT 1,A
        JR z,bold_ret

bold_expand:
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD HL,(GLYPH_PTR)
        LD DE,GLYPH_BUF
        LD C,0

bold_loop:
        LD A,(HL)
        LD (DE),A
        INC HL
        AND A
        JR z,bold_next
        OR (HL)
        INC DE
        INC C
        LD (DE),A

bold_next:
        INC DE
        INC C
        DJNZ bold_loop
        XOR A
        LD (DE),A
        LD A,C
        CP 2
        JR z,bold_set_width
        XOR A
        DEC DE
        LD (DE),A
        LD A,C

bold_set_width:
        LD (GLYPH_WIDTH),A
        LD HL,GLYPH_BUF
        LD (GLYPH_PTR),HL
        LD IX,GLYPH_BUF
        LD B,4

bold_scan_7f:
        LD A,(IX+0)
        CP 0x7f
        JR nz,bold_scan_next
        LD A,(IX+1)
        CP 0x7f
        JR nz,bold_scan_next
        LD A,(IX+2)
        CP 0x7f
        JR z,bold_collapse

bold_scan_next:
        INC IX
        DJNZ bold_scan_7f
        RET

bold_collapse:
        PUSH IX
        POP HL
        LD D,H
        LD E,L
        INC HL
        LD BC,0x001c
        LDIR
        LD A,(GLYPH_WIDTH)
        DEC A
        LD (GLYPH_WIDTH),A

bold_ret:
        RET

; ---- glyph_italic: shear the glyph into GLYPH_BUF_ITALIC (width + 2)
glyph_italic:
        LD A,(FONT_MODE)
        BIT 2,A
        JR z,italic_ret
        LD HL,(GLYPH_PTR)
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD DE,GLYPH_BUF_ITALIC
        LD B,0
        LDIR
        LD B,A
        LD E,B
        LD D,0
        LD HL,GLYPH_BUF_ITALIC
        ADD HL,DE
        PUSH HL
        POP IX

italic_loop:
        LD A,(HL)
        AND 3
        OR (IX+2)
        LD (IX+2),A
        LD A,(HL)
        AND 12
        OR (IX+1)
        LD (IX+1),A
        LD A,(HL)
        AND 0xf0
        LD (HL),A
        DEC HL
        DEC IX
        DEC B
        JP p,italic_loop
        LD A,(GLYPH_WIDTH)
        INC A
        INC A
        LD (GLYPH_WIDTH),A
        LD HL,GLYPH_BUF_ITALIC
        LD (GLYPH_PTR),HL

italic_ret:
        RET

; ---- glyph_big: double each column into GLYPH_BUF_BIG
glyph_big:
        LD A,(FONT_MODE)
        BIT 3,A
        JR z,big_ret
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD HL,(GLYPH_PTR)
        LD DE,GLYPH_BUF_BIG
        LD C,0

big_loop:
        LD A,(HL)
        LD (DE),A
        INC HL
        AND A
        JR z,big_next
        OR (HL)
        INC DE
        INC C
        LD (DE),A

big_next:
        INC DE
        INC C
        DJNZ big_loop
        XOR A
        LD (DE),A
        DEC DE
        LD (DE),A
        DEC DE
        LD (DE),A
        LD A,C
        DEC A
        LD (GLYPH_WIDTH),A
        LD HL,GLYPH_BUF_BIG
        LD (GLYPH_PTR),HL

big_ret:
        RET

; ---- fb_ptr_inc: HL++ inside the FRAMEBUF ring
fb_ptr_inc:
        INC HL
        PUSH AF
        PUSH DE
        PUSH HL
        LD DE,FB_COLPTR
        XOR A
        SBC HL,DE
        JP c,fbinc_nowrap
        LD HL,FRAMEBUF
        POP DE
        JR fbinc_ret

fbinc_nowrap:
        POP HL

fbinc_ret:
        POP DE
        POP AF
        RET

; ---- fb_ptr_add: HL += DE inside the FRAMEBUF ring
fb_ptr_add:
        PUSH AF
        PUSH DE
        ADD HL,DE
        PUSH HL
        LD DE,FB_COLPTR
        XOR A
        SBC HL,DE
        JR c,fbadd_nowrap
        POP DE
        LD DE,FRAMEBUF
        ADD HL,DE
        JR fbadd_ret

fbadd_nowrap:
        POP HL

fbadd_ret:
        POP DE
        POP AF
        RET

; ---- effect_step: Called from main loop: jump to EFFECT_VECTOR (current movement effect handler)
effect_step:
        LD A,(FRAME_DELAY)
        AND A
        JR nz,effect_step

fx_wait_scroll:
        LD A,(SCROLLING)
        AND A
        JR nz,fx_wait_scroll
        LD A,(EFFECT_ID)
        AND A
        RET z

fx_wait_row6:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,fx_wait_row6
        LD HL,(STAGE_OFFSET)
        LD A,L
        CP 0x2b
        JR z,fx_stage_empty
        LD HL,(EFFECT_VECTOR)
        JP (HL)

fx_stage_empty:
        LD HL,0
        LD (STAGE_OFFSET),HL

fx_done_effect:
        LD A,(EFFECT_ID)
        AND A
        JR z,fx_reset_stage
        LD A,(FLUSH_PENDING)
        CPL
        AND A
        LD (FLUSH_PENDING),A
        JR z,fx_reset_stage
        XOR A
        LD (FLUSH_PENDING),A
        LD A,FRAME_COLS

fx_reset_stage:
        LD (COL_COUNT),A
        CALL clear_txbuf
        LD HL,TXBUF
        LD (STAGE_PTR),HL
        RET

attr_control:
        LD A,(CUR_CHAR)

; ---- attr_dispatch: 11 NORM, 12 BOLD, 13 ITALIC, 14 FLASH, 10 BIG, 1F MAGIC; the rest go
;      through fx_attr: 06 PAUSE (the NIR's HALT), 07 BEEP, 03 END, 18 CRAWL, 19 JUMP, 1A UP,
;      1B DOWN, 0F BCRAWL
attr_dispatch:
        CP ATTR_NORM
        JP nz,attr_bold
        XOR A
        LD (FLASH_BIT),A
        LD (FONT_MODE),A
        JP render_next_char

; ---- attr_bold: 12 BOLD: FONT_MODE bit 1 on, BIG off
attr_bold:
        CP 0x12
        JP nz,attr_italic
        LD A,(FONT_MODE)
        SET 1,A
        RES 3,A
        LD (FONT_MODE),A
        JP render_next_char

; ---- attr_italic: 13 ITALIC: FONT_MODE bit 2
attr_italic:
        CP 0x13
        JP nz,attr_not_italic
        LD A,(FONT_MODE)
        SET 2,A
        LD (FONT_MODE),A
        JP render_next_char

attr_not_italic:
        CP ATTR_FLASH
        JP nz,attr_not_flash
        LD A,COLOR_FLASH
        LD (FLASH_BIT),A
        JP render_next_char

attr_not_flash:
        CP ATTR_BIG
        JR nz,attr_not_big
        LD A,(FONT_MODE)
        SET 1,A
        SET 3,A
        LD (FONT_MODE),A
        JP render_next_char

attr_not_big:
        CP ATTR_MAGIC
        JP z,fx_magic

fx_attr:
        LD A,(COL_COUNT)
        AND A
        JR z,fx_dispatch
        LD A,0xff
        LD (FLUSH_PENDING),A

fx_flush_stage:
        LD HL,(STAGE_PTR)
        LD DE,STAGE_PTR
        XOR A
        EX DE,HL
        SBC HL,DE
        LD A,FRAME_COLS
        SUB L
        LD (COL_COUNT),A
        JP stage_centre

; ---- fx_dispatch: 06 fx_halt (this ROM labels it PAUSE), 07 fx_beep, 03 fx_end_of_channel,
;      18 fx_left (CRAWL), 19 fx_pause (JUMP), 1A fx_up, 1B fx_down, 0F fx_right (BCRAWL)
fx_dispatch:
        LD A,(CUR_CHAR)
        CP 6
        JP z,fx_halt
        CP 7
        JP z,fx_beep
        CP 3
        JP z,fx_end_of_channel
        CP ATTR_LEFT
        JP z,fx_left
        CP ATTR_PAUSE
        JP z,fx_pause
        CP ATTR_UP
        JP z,fx_up
        CP ATTR_DOWN
        JP z,fx_down
        CP 15
        JP z,fx_right
        JP render_next_char

; ---- fx_beep
fx_beep:
        LD HL,BEEP_LEN
        LD (BEEP_TICKS),HL
        JP render_next_char

; ---- fx_right: 0F (labelled BCRAWL by this ROM): effect 4, fxv_right reveals the staged
;      text left to right.
fx_right:
        XOR A
        LD (SCROLLING),A
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        LD A,4
        LD HL,fxv_right
        JP set_effect_vector

; ---- fx_left: 18 (labelled CRAWL): plain crawl, no staging
fx_left:
        XOR A
        LD (COL_COUNT),A
        LD HL,fxv_none
        JP set_effect_vector

; ---- fx_end_of_channel: 03: scroll the text off, reset SP and start the next channel
fx_end_of_channel:
        LD HL,fxv_none
        LD (EFFECT_VECTOR),HL
        XOR A
        LD (EFFECT_ID),A
        CALL scroll_off_text
        LD SP,STACK_TOP
        JP main_start_channel

; ---- fx_pause: 19 (labelled JUMP by this ROM): effect 1, fxv_pause shows the staged text
;      at once and holds HOLD_FRAMES.
fx_pause:
        XOR A
        LD (SCROLLING),A
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        LD A,1
        LD HL,fxv_pause
        JP set_effect_vector

; ---- fx_magic: 1F: MAGIC_MODE = FF, the next cycle color, then a space
fx_magic:
        LD A,0xff
        LD (MAGIC_MODE),A
        CALL magic_first_color
        LD A,' '
        LD (CUR_CHAR),A
        JP glyph_lookup

; ---- magic_first_color: outside effects and the editor: step MAGIC_COLOR_IDX and take that
;      entry as CUR_COLOR
magic_first_color:
        LD A,(MENU_ACTIVE)
        AND A
        RET nz
        LD A,(EFFECT_ID)
        AND A
        RET nz
        LD A,(MAGIC_COLOR_IDX)
        INC A
        AND 0x3f
        LD (MAGIC_COLOR_IDX),A
        LD E,A
        LD D,0
        LD HL,MAGIC_COLOR_CYCLE
        ADD HL,DE
        LD A,(HL)
        LD (CUR_COLOR),A
        RET

; ---- fx_halt: 06 (labelled PAUSE): hold HOLD_FRAMES frames with the colors reset
fx_halt:
        XOR A
        LD (SCROLLING),A
        LD A,(EFFECT_ID)
        AND A
        JR nz,halt_hold

halt_wait_frames:
        LD A,(FRAME_DELAY)
        AND A
        JR nz,halt_wait_frames

halt_hold:
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A

; ---- fb_colors_default: every color byte in the 172-byte ring -> 8F keeping the flash bit,
;      WINDOW_COLOR/ROW_COLOR likewise; then CRAWL unless an effect continues
fb_colors_default:
        LD HL,FRAMEBUF
        LD B,0xac

fbcol_loop:
        BIT 7,(HL)
        JR z,fbcol_next
        LD A,(HL)
        AND COLOR_FLASH
        OR COLOR_DEFAULT
        LD (HL),A

fbcol_next:
        INC HL
        DJNZ fbcol_loop
        LD A,(WINDOW_COLOR)
        AND COLOR_FLASH
        OR COLOR_DEFAULT
        LD (WINDOW_COLOR),A
        LD (ROW_COLOR),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0x18
        JP z,fx_left
        LD A,(EFFECT_ID)
        AND A
        JP z,fx_left
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        JP render_next_char

; ---- fx_up: 1A: effect 2, fxv_wipe_updown reveals the stage row by row from the top
fx_up:
        XOR A
        LD (SCROLLING),A
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        LD A,2
        LD HL,fxv_wipe_updown
        JP set_effect_vector

; ---- fx_down: 1B: reveal the staged text row by row from the bottom
fx_down:
        XOR A
        LD (SCROLLING),A
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        LD A,3
        LD HL,fxv_wipe_updown
        JP set_effect_vector

; ---- set_effect_vector: HL -> EFFECT_VECTOR, A -> effect id
set_effect_vector:
        LD (EFFECT_ID),A
        LD (EFFECT_VECTOR),HL
        JP render_next_char

; ---- attr_color_speed: 8x foreground, 9x background (both end MAGIC), Fx speed; other high
;      bytes are skipped
attr_color_speed:
        LD A,(CUR_CHAR)
        AND 0xf0
        CP COLOR_BASE
        JP z,fore_clear_magic
        CP BGRND_BASE
        JP z,back_set
        CP SPEED_BASE
        JP z,attr_speed
        JP render_next_char

fore_clear_magic:
        XOR A
        LD (MAGIC_MODE),A

fore_set:
        LD A,(CUR_CHAR)
        AND 15
        LD E,A
        LD A,(CUR_COLOR)
        AND 0x60
        OR E
        LD (CUR_COLOR),A
        JP render_next_char

back_set:
        XOR A
        LD (MAGIC_MODE),A
        LD HL,0
        LD DE,0x0020
        LD A,(CUR_CHAR)
        AND 3
        JR z,back_apply

back_mul:
        ADD HL,DE
        DEC A
        JR nz,back_mul

back_apply:
        LD A,(CUR_COLOR)
        AND 15
        OR L
        AND 0x6f
        LD (CUR_COLOR),A
        JP render_next_char

; ---- attr_speed
attr_speed:
        LD A,(CUR_CHAR)
        AND 7
        LD (SCROLL_SPEED),A
        JP render_next_char

; ---- fxv_prepare: clear FRAMEBUF and reset the output window; HL = TXBUF, DE = FRAMEBUF
;      + STAGE_OFFSET. the effect handlers call this
fxv_prepare:
        CALL clear_framebuf

; ---- fxv_pointers: reset the output window; HL = TXBUF, DE = FRAMEBUF+offset
fxv_pointers:
        LD HL,FRAMEBUF_ROW1
        LD (FB_COLPTR),HL
        LD HL,FRAME_COLS
        LD (FB_OUT_LEN),HL
        LD HL,0
        LD (FB_EXTRA_LEN),HL
        LD HL,(STAGE_OFFSET)
        LD DE,FRAMEBUF
        LD (FB_COL),DE
        LD (FB_OUT_PTR),DE
        ADD HL,DE
        LD DE,TXBUF
        EX DE,HL
        RET

; ---- fxv_right: effect 4: copy one staged column per frame, left to right
fxv_right:
        LD A,0xff
        LD (DISP_ON),A
        CALL fxv_prepare
        LD A,(COL_COUNT)
        LD B,A

right_wait_row:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,right_wait_row
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,0xff
        LD (DISP_ON),A
        LD A,1
        LD (FRAME_DELAY),A

right_wait_frame:
        LD A,(FRAME_DELAY)
        AND A
        JR nz,right_wait_frame
        DJNZ right_wait_row
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A
        XOR A
        LD (SCROLLING),A
        JP fx_done_effect

; ---- fxv_none: effect handler: nothing (straight to render loop)
fxv_none:
        JP fx_done_effect

; ---- fxv_pause: effect 1 (19, the sign calls it JUMP): copy the staged text into the
;      frame buffer at once and hold it HOLD_FRAMES
fxv_pause:
        CALL fxv_prepare
        LD B,0
        LD A,(COL_COUNT)
        LD C,A
        LDIR
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A
        XOR A
        LD (SCROLLING),A
        JP fx_done_effect

; ---- fxv_wipe_updown: effects 2 (UP) and 3 (DOWN): eight passes copying the
;      stage through a row mask that grows one row per pass
fxv_wipe_updown:
        LD A,0
        LD (DISP_ON),A
        CALL fxv_prepare
        LD A,(COL_COUNT)
        LD B,A
        LD A,(EFFECT_ID)
        CP 2
        LD C,0x80
        JR z,wipev_start
        LD C,1

wipev_start:
        LD A,8

wipev_pass:
        PUSH AF
        PUSH HL
        PUSH DE
        PUSH BC

wipev_wait_row:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,wipev_wait_row

wipev_col:
        LD A,(HL)
        BIT 7,A
        JR nz,wipev_store
        AND C

; ---- wipev_store: color bytes pass unmasked, column bytes AND the row mask
wipev_store:
        LD (DE),A
        INC HL
        INC DE
        DJNZ wipev_col
        LD A,0xff
        LD (DISP_ON),A
        LD A,3
        LD (FRAME_DELAY),A

wipev_wait_frame:
        LD A,(FRAME_DELAY)
        AND A
        JR nz,wipev_wait_frame
        POP BC
        POP DE
        POP HL
        LD A,(EFFECT_ID)
        CP 2
        JR nz,wipev_mask_down
        SCF
        RR C
        JR wipev_next_pass

wipev_mask_down:
        SCF
        RL C

wipev_next_pass:
        POP AF
        DEC A
        JR nz,wipev_pass
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A
        XOR A
        LD (SCROLLING),A
        JP fx_done_effect

; ---- boot_clear_check: keypad mode only: PORT_IN bit 1 low at power-up clears the store and
;      the sequence. Which keys do that depends on the keypad row the latch selects at reset;
;      not tried
boot_clear_check:
        LD A,(INPUT_MODE)
        AND A
        RET nz
        IN A,(PORT_IN)
        BIT 1,A
        RET nz

; ---- store_clear_all: MSG_STORE = D0 03 D1 03 .. D9 03 DA (ten channels, single-byte
;      markers); SEQ_LIST = 10 (demo) then FF x 31
store_clear_all:
        LD A,0xd0
        LD HL,MSG_STORE
        LD B,10

clr_chan_loop:
        LD (HL),A
        INC HL
        LD (HL),3
        INC HL
        INC A
        DJNZ clr_chan_loop
        LD A,0xda
        LD (HL),A
        LD HL,SEQ_LIST
        LD (HL),10
        LD B,0x1f

clr_seq_loop:
        INC HL
        LD (HL),0xff
        DJNZ clr_seq_loop
        RET

; ---- store_init: boot input mode, from one pin: PORT_IN bit 0 low -> FF, serial; high ->
;      00, keypad. No probe pattern, no packet mode, no address
store_init:
        IN A,(PORT_IN)
        BIT 0,A
        JR nz,mode_keypad

; ---- mode_serial: PORT_IN bit 0 low at boot -> INPUT_MODE FF
mode_serial:
        LD A,0xff
        JR store_init_mode

mode_keypad:
        XOR A

; ---- store_init_mode: INPUT_MODE = A; RX engine reset. The store bounds are fixed
;      (MSG_STORE..STORE_TOP)
store_init_mode:
        LD (INPUT_MODE),A
        LD HL,rx_st_wait_start
        LD (RX_STATE),HL
        XOR A
        LD (RX_TICKS),A
        RET

; ---- tx_try_queue
tx_try_queue:
        LD HL,TX_STATUS
        BIT 1,(HL)
        RET nz
        LD (TX_PENDING),A
        SET 1,(HL)
        XOR A
        RET

; ---- tx_bit_engine: every tick: shift TX_SHIFT out on CTRL_LATCH bit 4 with the TX_TIMING
;      bit times (300 baud at 1302 Hz). A new byte starts only while PORT_IN bits 1 and 2 are
;      both high (a CTS-style handshake, as in the CC710)
tx_bit_engine:
        LD HL,TX_STATUS
        BIT 0,(HL)
        JR nz,tx_bit_tick
        IN A,(PORT_IN)
        AND 6
        CP 6
        RET nz
        BIT 1,(HL)
        RET z
        LD A,(TX_PENDING)
        LD (TX_SHIFT),A
        LD (HL),1
        XOR A
        LD (TX_BITIDX),A
        INC A
        LD (TX_BITMASK),A
        LD HL,TX_TIMING
        LD (TX_TIMING_PTR),HL
        LD A,(CTRL_LATCH_SHADOW)
        OR LATCH_TX
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,(HL)
        LD (TX_TICKS),A
        RET

tx_bit_tick:
        LD HL,TX_TICKS
        DEC (HL)
        RET nz
        LD HL,TX_BITIDX
        INC (HL)
        LD A,(HL)
        CP 9
        JR z,tx_stop_bit
        CP 10
        JR z,tx_idle
        LD HL,TX_BITMASK
        LD E,(HL)
        SLA (HL)
        LD A,(TX_SHIFT)
        AND E
        LD A,(CTRL_LATCH_SHADOW)
        JR nz,tx_mark
        OR LATCH_TX
        JR tx_latch_bit

tx_mark:
        AND ~LATCH_TX&0xff

tx_latch_bit:
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD HL,(TX_TIMING_PTR)
        INC HL
        LD (TX_TIMING_PTR),HL
        LD A,(HL)
        LD (TX_TICKS),A
        RET

tx_stop_bit:
        LD A,(CTRL_LATCH_SHADOW)
        AND ~LATCH_TX&0xff
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,10
        LD (TX_TICKS),A
        RET

tx_idle:
        LD HL,TX_STATUS
        RES 0,(HL)
        RET

; ---- rx_bit_engine: every tick. CTRL_LATCH bit 5 is driven high as 'ready' and dropped
;      while RX_FIFO is full (8 bytes); the receiver only runs while PORT_IN bit 1 is high.
;      The sampler is the NIR's start / 8 data / stop on PORT_IN bit 3 with RX_TIMING
rx_bit_engine:
        LD A,(CTRL_LATCH_SHADOW)
        AND 0xdf
        LD E,A
        LD A,(RX_COUNT)
        CP 8
        JR nz,rx_engine_ready
        LD A,E
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD HL,rx_st_wait_start
        LD (RX_STATE),HL
        LD A,0
        LD (RX_TICKS),A
        RET

; ---- rx_engine_ready: FIFO has room: raise latch bit 5; sample only while PORT_IN bit 1
;      is high
rx_engine_ready:
        LD A,0x20
        OR E
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        IN A,(PORT_IN)
        BIT 1,A
        RET z

rx_tick:
        LD A,(RX_TICKS)
        AND A
        JR z,rx_run_state
        DEC A
        LD (RX_TICKS),A
        RET nz

rx_run_state:
        LD HL,(RX_STATE)
        JP (HL)

; ---- rx_st_wait_start
rx_st_wait_start:
        IN A,(PORT_IN)
        BIT 3,A
        RET z
        LD HL,rx_st_sample_bit
        LD (RX_STATE),HL
        LD HL,RX_TIMING
        LD (RX_TIMING_PTR),HL
        LD A,(HL)
        LD (RX_TICKS),A
        LD A,1
        LD (RX_BITMASK),A
        XOR A
        LD (RX_SHIFT),A
        RET

; ---- RX_TIMING: ticks per RX bit: start (6, lands mid-bit), then 8 data bits in the 4,5,4
;      pattern = 300 baud at 1302 Hz
RX_TIMING:
        db 0x06,0x04,0x05,0x04,0x04,0x05,0x04,0x04,0x05,0x04

; ---- TX_TIMING: ticks per TX bit: start, 8 data (4,4,5 pattern), stop = 10
TX_TIMING:
        db 0x04,0x04,0x05,0x04,0x04,0x05,0x04,0x04,0x05,0x0a

; ---- rx_st_sample_bit
rx_st_sample_bit:
        IN A,(PORT_IN)
        BIT 3,A
        LD A,0xff
        JR z,rx_merge_bit
        XOR A

rx_merge_bit:
        LD E,A
        LD A,(RX_SHIFT)
        LD D,A
        LD A,(RX_BITMASK)
        PUSH AF
        CPL
        AND D
        LD D,A
        POP AF
        AND E
        OR D
        LD (RX_SHIFT),A
        LD HL,(RX_TIMING_PTR)
        INC HL
        LD (RX_TIMING_PTR),HL
        LD A,(HL)
        LD (RX_TICKS),A
        LD A,(RX_BITMASK)
        SLA A
        LD (RX_BITMASK),A
        RET nc
        LD HL,rx_st_stop_bit
        LD (RX_STATE),HL
        RET

; ---- rx_st_stop_bit: stop bit must read as mark else byte is dropped
rx_st_stop_bit:
        IN A,(PORT_IN)
        BIT 3,A
        JR nz,rx_byte_done
        LD A,(RX_SHIFT)
        AND A
        JR z,rx_byte_done
        LD A,(RX_COUNT)
        CP 8
        JR z,rx_byte_done
        AND 7
        LD HL,RX_FIFO
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(RX_SHIFT)
        LD (HL),A
        LD A,E
        INC A
        LD (RX_COUNT),A

rx_byte_done:
        XOR A
        LD (RX_TICKS),A
        LD (RX_SHIFT),A
        LD HL,rx_st_wait_start
        LD (RX_STATE),HL
        RET

; ---- rx_fifo_get: pop one FIFO byte into RX_BYTE. A received 00 resets the sign. The editor
;      takes bytes raw; outside it 01 -> 35 (STOP/START), 7E passes, everything else is
;      popped and reported as 0
rx_fifo_get:
        LD A,(RX_COUNT)
        AND A
        JR z,fifo_empty
        LD HL,RX_FIFO
        LD A,(HL)
        CP 0x00
        JP z,RESET
        LD A,(MENU_ACTIVE)
        AND A
        JR z,fifo_key_translate

fifo_pop_raw:
        LD A,(HL)
        LD (RX_BYTE),A
        JR fifo_shift

; ---- fifo_key_translate: outside the editor: serial 01 = STOP/START
fifo_key_translate:
        LD A,(HL)
        CP 1
        JR nz,fifo_key_other
        LD A,0x35
        JR fifo_pop

; ---- fifo_key_other: 7E passes; any other byte is popped and reported empty
fifo_key_other:
        CP 0x7e
        JR z,fifo_pop
        XOR A

; ---- fifo_pop: RX_BYTE = A, shift the FIFO down, RX_COUNT--, return NC
fifo_pop:
        LD (RX_BYTE),A

; ---- fifo_shift: shift the FIFO down, RX_COUNT--, A = RX_BYTE
fifo_shift:
        LD A,(RX_COUNT)
        LD BC,8
        LD HL,RX_FIFO+1
        LD DE,RX_FIFO
        LDIR
        DEC A
        LD (RX_COUNT),A
        LD A,(RX_BYTE)
        RET

; ---- fifo_empty: RX_BYTE = 0
fifo_empty:
        LD A,0
        LD (RX_BYTE),A
        RET

; ---- clock_tick: NMI: NMI_COUNT to 60 -> CLK_SEC -> minutes -> hours, 12-hour with CLK_PM;
;      nothing counts while CLK_RUN is 0
clock_tick:
        LD A,(CLK_RUN)
        AND A
        RET z
        LD A,(NMI_COUNT)
        INC A
        LD (NMI_COUNT),A
        CP 0x3c
        RET nz
        LD A,0
        LD (NMI_COUNT),A
        LD HL,CLK_SEC
        INC (HL)
        LD A,(HL)
        CP 0x3c
        RET nz
        LD (HL),0
        DEC HL
        INC (HL)
        LD A,(HL)
        CP 10
        RET nz
        LD (HL),0
        DEC HL
        INC (HL)
        LD A,(HL)
        CP 6
        RET nz
        LD (HL),0
        DEC HL
        INC (HL)
        LD A,(HL)
        CP 10
        JR nz,clk_check_12h
        LD (HL),0
        DEC HL
        LD A,(HL)
        INC A
        AND 1
        LD (HL),A
        RET

clk_check_12h:
        DEC HL
        CP 3
        JP z,clk_wrap_13
        CP 2
        RET nz
        LD A,(HL)
        AND A
        RET z
        LD A,(CLK_PM)
        INC A
        AND 1
        LD (CLK_PM),A
        RET

clk_wrap_13:
        LD A,(HL)
        AND A
        RET z
        XOR A
        LD (HL),A
        INC A
        INC HL
        LD (HL),A
        RET

; ---- scroll_off_text: push 14 spaces through the renderer so the text leaves the panel
scroll_off_text:
        LD B,0x0e

scrolloff_loop:
        LD A,' '
        LD (CUR_CHAR),A
        PUSH BC
        CALL space_seen
        CALL effect_step
        POP BC
        DJNZ scrolloff_loop
        RET

; ---- keypad_scan: 8x8 matrix scan: rows 0-7 on CTRL_LATCH bits 4-6, column code on PORT_IN
;      bits 0-2, key down = bit 3 low; code row*8+col -> RX_BYTE (key 0 reported as 1E), 0 =
;      none
keypad_scan:
        LD L,0
        LD H,0xf0
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x8f
        LD E,A
        LD B,8

kp_row_loop:
        LD A,H
        ADD A,0x10
        LD H,A
        OR E
        LD (CTRL_LATCH),A
        IN A,(PORT_IN)
        BIT 3,A
        JR z,kp_key_found
        LD A,8
        ADD A,L
        LD L,A
        DJNZ kp_row_loop
        XOR A
        JR kp_store

kp_key_found:
        AND 7
        ADD A,L
        JR nz,kp_store
        LD A,0x1e

kp_store:
        LD (RX_BYTE),A
        AND A
        RET

; ---- clear_framebuf: the 172-byte ring (2 x 86 columns) = 0x80
clear_framebuf:
        PUSH HL
        PUSH BC
        LD HL,FRAMEBUF
        LD B,0xac

clrfb_loop:
        LD (HL),0x80
        INC HL
        DJNZ clrfb_loop
        POP BC
        POP HL
        RET

; ---- clear_txbuf
clear_txbuf:
        PUSH HL
        PUSH BC
        LD HL,TXBUF
        LD B,FRAME_COLS

clrtxbuf_loop:
        LD (HL),0
        INC HL
        DJNZ clrtxbuf_loop
        POP BC
        POP HL
        RET

; ---- clear_glyph_tmp: zero the three 32-byte glyph buffers at GLYPH_BUF
clear_glyph_tmp:
        PUSH HL
        PUSH BC
        LD HL,GLYPH_BUF
        LD B,0x60

clrglyph_loop:
        LD (HL),0
        INC HL
        DJNZ clrglyph_loop
        POP BC
        POP HL
        RET

; ---- menu_enter: serial byte 7E: blank the panel, then open the editor if the next key
;      equals MY_ADDRESS (set by the editor key 5E), else RESET. There is no '*' broadcast
menu_enter:
        LD SP,STACK_TOP
        LD A,0xff
        LD (MENU_ACTIVE),A
        EI
        CALL init_render
        XOR A
        LD (RX_BYTE),A
        LD (IR_KEY_CHAR),A
        LD (PREV_KEY),A
        LD (PREV_KEY2),A
        LD (KEY_TIMER),A
        LD (EDIT_KEY),A
        LD (KEY_ECHO_TX),A

; ---- menu_enter_wait: wait for a key; no echo
menu_enter_wait:
        CALL editor_getkey
        OR A
        JR z,menu_enter_wait
        PUSH AF
        LD A,0
        POP AF
        LD (KEY_ECHO_TX),A
        LD HL,MY_ADDRESS
        CP (HL)
        JP nz,RESET
        JR editor_start

; ---- key_handler: STOP/START (keypad 35, or serial 01): open the editor with key echo on
;      the serial TX
key_handler:
        LD A,1
        LD (KEY_ECHO_TX),A

; ---- editor_start: MENU_ACTIVE = FF, SP reset, EI, render state cleared; keypad mode
;      first waits for the key to be released
editor_start:
        LD SP,STACK_TOP
        LD A,0xff
        LD (MENU_ACTIVE),A
        EI
        CALL init_render
        XOR A
        LD (RX_BYTE),A
        LD (IR_KEY_CHAR),A
        LD (PREV_KEY),A
        LD (PREV_KEY2),A
        LD (KEY_TIMER),A
        LD A,(INPUT_MODE)
        AND A
        JR nz,editor_find_marker

; ---- editor_wait_release: keypad mode: spin until keypad_scan reports no key
editor_wait_release:
        CALL keypad_scan
        AND A
        JR nz,editor_wait_release

; ---- editor_find_marker: cursor on a marker byte -> step back one, then scan back for
;      the channel's marker
editor_find_marker:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JR nz,editor_scan_back
        DEC HL
        LD (STORE_CURSOR),HL

; ---- editor_scan_back
editor_scan_back:
        PUSH HL
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        PUSH HL
        POP BC
        POP HL
        DEC HL

editor_scan_loop:
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JR nz,editor_scan_next
        LD A,(HL)
        CP 0xd0
        JR c,editor_scan_next
        CP 0xdb
        JR c,editor_set_ins

; ---- editor_scan_next: reaching MSG_STORE without a marker resets the sign
editor_scan_next:
        DEC HL
        DEC BC
        LD A,B
        OR C
        JR nz,editor_scan_loop
        JP store_fault_reset

; ---- editor_set_ins: INS_PTR = marker + 1, store_finalize, clear the prefix flags
editor_set_ins:
        INC HL
        LD (INS_PTR),HL
        CALL store_finalize
        XOR A
        LD (GRAPH_PENDING),A
        LD (COLOR_PENDING),A
        LD (BGRND_PENDING),A
        LD (SHIFT_LABEL),A
        LD (MENU_MSG_FLAG),A

; ---- editor_loop: Editor main loop: get key, dispatch
editor_loop:
        CALL editor_redraw

editor_next_key:
        CALL editor_getkey
        LD A,(EDIT_KEY)
        OR A
        JR z,editor_next_key
        CALL apply_prefixes
        LD A,(EDIT_KEY)
        LD (CUR_CHAR),A
        CP KEY_SHIFT
        LD A,0
        JR z,editor_dispatch
        LD (COLOR_PENDING),A
        LD (BGRND_PENDING),A

; ---- editor_dispatch: keys: 5E address, 05 top of message, 7F delete, 1D shift, 0A/08
;      cursor, 0C/0B cursor x8, 0E clear message, 1C caps, 1E/15/16/02 prefixes, 17 TIME?, 09
;      PROG?, 04 SEQ?, 0D exit, 9F ignored, else insert. No CLR ALL, FUNC or B3 here
editor_dispatch:
        LD (SHIFT_LABEL),A
        LD A,(PROG_MSG_FORCE)
        OR A
        JP nz,menu_prog_msg
        LD A,(SEQ_MENU_ACTIVE)
        BIT 7,A
        JP nz,menu_seq_msg
        LD A,(EDIT_KEY)
        CP 0x5e
        JP z,menu_address
        CP 5
        JP z,show_top_of_msg
        CP KEY_DEL
        JP z,editor_delete
        CP KEY_SHIFT
        JP z,editor_key_shift
        CP 10
        JP z,cursor_right
        CP 12
        JP z,cursor_right_8
        CP 8
        JP z,cursor_left
        CP 11
        JP z,cursor_left_8
        CP 14
        JP z,editor_key_clear
        CP KEY_CASE
        JP z,editor_toggle_caps
        CP ATTR_GRAPH
        JP z,editor_key_graph
        CP ATTR_COLOR
        JP z,editor_key_color
        CP ATTR_BGRND
        JP z,editor_key_bgrnd
        CP 0x17
        JP z,menu_time
        CP 2
        JP z,editor_key_speed
        CP 9
        JP z,menu_prog_msg
        CP 4
        JP z,menu_seq_msg
        CP 13
        JP z,editor_exit
        CP 0x9f
        JP z,editor_loop
        JP editor_insert

; ---- store_finalize: Fix up MSG_STORE terminators after an edit
store_finalize:
        LD A,MARK_HI
        LD HL,MSG_STORE
        LD BC,0x059f
        CPIR
        LD A,B
        OR C
        JR z,store_finalize
        DEC HL
        LD (STORE_END),HL
        RET

; ---- editor_show_invalid: MENU_MSG_FLAG = FF, MENU_MSG_PTR = MENU_STR_INVALID
editor_show_invalid:
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_INVALID                       ; MENU_MSG_PTR = MENU_STR_INVALID
        LD (MENU_MSG_PTR),HL
        JP editor_loop

; ---- editor_exit: 0D in the editor: SEQ_MENU_ACTIVE and PROG_MSG_FORCE cleared; serial mode
;      echoes a CR, keypad mode waits for the key to be released; then the display restarts
;      from the top of SEQ_LIST
editor_exit:
        XOR A
        LD (SEQ_MENU_ACTIVE),A
        LD (PROG_MSG_FORCE),A
        LD A,(INPUT_MODE)
        AND A
        JR z,exit_wait_release
        LD A,13

; ---- exit_echo_cr: queue the CR until the TX engine takes it
exit_echo_cr:
        CALL tx_try_queue
        AND A
        JR nz,exit_echo_cr
        JP exit_to_display

; ---- exit_wait_release: keypad: restart the two-tick no-key count
exit_wait_release:
        LD A,2
        LD C,A
        LD (KEY_TIMER),A

exit_release_tick:
        DEC C
        JR z,exit_to_display

; ---- exit_release_poll: wait for KEY_TIMER to reach C; a key still down restarts the count
exit_release_poll:
        LD A,(KEY_TIMER)
        AND A
        JR z,exit_wait_release
        CP C
        JR nz,exit_release_poll
        LD A,(RX_BYTE)
        AND A
        JR z,exit_release_tick
        JR exit_wait_release

exit_to_display:
        LD SP,STACK_TOP
        XOR A
        LD (MENU_ACTIVE),A
        LD (FORCE_BOLD),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        JP restart_display

; ---- menu_time: 17: ' TIME?' then four digits into CLK_H10..CLK_SEC-1, hours clamped to 12,
;      then ' AM? Y/N '
menu_time:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STR_TIME
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        XOR A
        LD (CLK_RUN),A
        LD HL,CLK_H10
        LD B,4

time_digit_loop:
        PUSH BC
        PUSH HL

time_get_digit:
        CALL editor_getkey
        LD A,(EDIT_KEY)
        OR A
        JR z,time_get_digit
        LD (CUR_CHAR),A
        CP '9'+1
        JR nc,time_get_digit
        CP '0'
        JR c,time_get_digit
        PUSH AF
        CALL glyph_lookup
        POP AF
        AND 15
        POP HL
        LD (HL),A
        INC HL
        POP BC
        DJNZ time_digit_loop
        LD A,(CLK_H10)
        AND 1
        LD (CLK_H10),A
        OR A
        JR z,time_wait
        LD A,(CLK_H1)
        CP 3
        JR c,time_wait
        LD A,2
        LD (CLK_H1),A

time_wait:
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A

time_wait_loop:
        LD A,(FRAME_DELAY)
        AND A
        JR nz,time_wait_loop
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STR_AM_PM
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

; ---- time_get_ampm: Y -> CLK_PM = 0, N -> FF, other keys ignored
time_get_ampm:
        CALL editor_getkey
        LD A,(EDIT_KEY)
        AND A
        JR z,time_get_ampm
        RES 5,A
        CP 'Y'
        JR nz,time_check_n
        LD A,0
        JR time_store_pm

time_check_n:
        CP 'N'
        JR nz,time_get_ampm
        LD A,0xff

time_store_pm:
        LD (CLK_PM),A
        LD A,0
        LD (NMI_COUNT),A
        LD A,0xff
        LD (CLK_RUN),A
        JP editor_loop

; ---- render_clock: 5F: emit H:MM AM/PM one character per call via CLK_RENDER_STEP 0..8;
;      in the editor the 5F byte itself is drawn
render_clock:
        LD A,(MENU_ACTIVE)
        AND A
        JP nz,glyph_lookup
        LD A,(CLK_RENDER_STEP)
        LD HL,(CLK_RENDER_PTR)
        AND A
        JR nz,clock_next_step
        LD HL,CLK_H10
        LD A,(HL)
        AND A
        LD A,(CLK_RENDER_STEP)
        JR nz,clock_next_step
        LD A,(CLK_RENDER_STEP)
        INC A
        LD (CLK_RENDER_STEP),A
        INC HL
        LD (CLK_RENDER_PTR),HL
        JR render_clock

clock_next_step:
        INC A
        LD (CLK_RENDER_STEP),A
        CP 3
        JR nz,clock_not_colon
        LD A,':'
        LD (CUR_CHAR),A
        JP clock_emit

clock_not_colon:
        CP 6
        JR nz,clock_not_space
        LD A,' '
        LD (CUR_CHAR),A
        JP clock_emit

clock_not_space:
        CP 7
        JR nz,clock_not_ampm
        LD A,(CLK_PM)
        AND 1
        LD A,'A'
        JR z,clock_ampm_char
        LD A,'P'

clock_ampm_char:
        LD (CUR_CHAR),A
        JR clock_emit

clock_not_ampm:
        CP 8
        JR nz,clock_digit
        LD A,0x4d
        LD (CUR_CHAR),A
        JR clock_last_char

clock_digit:
        LD A,(HL)
        AND 15
        OR '0'
        LD (CUR_CHAR),A
        INC HL
        LD A,(CLK_RENDER_STEP)
        LD (CLK_RENDER_PTR),HL

clock_emit:
        CALL unfetch_char
        LD A,(CUR_CHAR)
        JP glyph_lookup

        LD A,0x20                                    ; unreachable
        LD (CUR_CHAR),A

; ---- clock_last_char: the 'M' of AM/PM: CLK_RENDER_STEP back to 0, drawn without
;      unfetching. The two instructions above it are unreachable
clock_last_char:
        XOR A
        LD (CLK_RENDER_STEP),A
        LD A,(CUR_CHAR)
        JP glyph_lookup

; ---- menu_address: 5E: the next key becomes MY_ADDRESS, the byte menu_enter checks. No
;      prompt and no echo
menu_address:
        CALL editor_getkey
        OR A
        JR z,menu_address
        LD (MY_ADDRESS),A
        JP editor_next_key

; ---- show_top_of_msg: 05 and after most edits: MSG_TOP_TABLE[cursor marker & 15] ('TOP OF
;      MSG  n' / 'TOP DEMO MSG') becomes the SHIFT_LABEL message
show_top_of_msg:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 15
        SLA A
        LD HL,MSG_TOP_TABLE
        LD E,A
        LD D,0
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (MENU_MSG_PTR),HL                         ; MENU_MSG_PTR
        LD A,0xff
        LD (SHIFT_LABEL),A
        JP editor_loop

; ---- editor_key_clear: 0E: inside the SEQ? dialogue (SEQ_MENU_ACTIVE bit 7) clear the
;      sequence list, else clear the message
editor_key_clear:
        LD A,(SEQ_MENU_ACTIVE)
        BIT 7,A
        JR nz,seqmenu_clear_list

; ---- editor_clear_msg: delete the channel's text unless CHAN_LOCK (demo)
editor_clear_msg:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_loop

; ---- delete_chan_text: remove the selected channel's text up to its 03
delete_chan_text:
        LD HL,(STORE_CURSOR)
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        PUSH HL
        POP BC
        INC BC
        LD HL,(STORE_CURSOR)

; ---- deltext_find_marker: scan back from the cursor to the channel marker
deltext_find_marker:
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JR z,deltext_move

deltext_back:
        DEC HL
        DEC BC
        LD A,B
        OR C
        JP z,store_fault_reset
        JP deltext_find_marker

deltext_move:
        LD (STORE_CURSOR),HL
        INC HL
        LD (MOVE_DST),HL
        EX DE,HL
        LD HL,STORE_TOP
        OR A
        SBC HL,DE
        PUSH HL
        POP BC
        INC BC
        EX DE,HL
        LD A,3
        CPIR
        LD A,B
        OR C
        JP z,store_fault_reset
        DEC HL
        LD (MOVE_SRC),HL
        LD DE,STORE_TOP
        EX DE,HL
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        INC BC
        LD HL,(MOVE_SRC)
        LD DE,(MOVE_DST)
        LDIR
        CALL store_finalize
        JP show_top_of_msg

; ---- seqmenu_clear_list: 0E in SEQ?: SEQ_LIST = FF x 32, prompt again
seqmenu_clear_list:
        LD HL,SEQ_LIST
        LD B,0x20
        LD A,0xff

seqmenu_clear_loop:
        LD (HL),A
        INC HL
        DJNZ seqmenu_clear_loop
        JP seqmenu_prompt

; ---- editor_toggle_caps
editor_toggle_caps:
        LD A,(CAPS_LOCK)
        CPL
        LD (CAPS_LOCK),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,show_top_of_msg
        JP editor_loop

; ---- editor_key_speed: 02 SPEED: next key is the speed digit (SPEED_PENDING); not on the 03
;      or in the demo
editor_key_speed:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_show_invalid
        LD A,0xff
        LD (SPEED_PENDING),A
        JP editor_loop

; ---- editor_key_graph: 1E GRAPH: next key selects A0-AF (GRAPH_PENDING)
editor_key_graph:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_show_invalid
        LD A,0xff
        LD (GRAPH_PENDING),A
        JP editor_loop

; ---- editor_key_color: 15 FORE: next key is the foreground digit (COLOR_PENDING)
editor_key_color:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_show_invalid
        LD A,0xff
        LD (COLOR_PENDING),A
        JP editor_loop

; ---- editor_key_bgrnd: 16 BACK: next key is the background digit (BGRND_PENDING)
editor_key_bgrnd:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_show_invalid
        LD A,0xff
        LD (BGRND_PENDING),A
        JP editor_loop

; ---- menu_prog_msg: 09: PROG_MSG_FORCE = FF and the 'PROG MSG?' prompt; the next key comes
;      back here: a digit or D/d selects that channel
menu_prog_msg:
        LD A,(EDIT_KEY)
        CP 9
        JR nz,progmsg_key
        LD A,0xff
        LD (PROG_MSG_FORCE),A
        LD HL,MENU_STR_PROG_MSG
        LD (MENU_MSG_PTR),HL                         ; MENU_MSG_PTR = MENU_STR_PROG_MSG
        LD (SHIFT_LABEL),A
        JP editor_loop

; ---- progmsg_key: digit 0-9 or D/d (demo) selects; other keys -> progmsg_other_key
progmsg_key:
        LD A,(EDIT_KEY)
        CP 0x44
        JR z,progmsg_echo
        CP 0x64
        JR z,progmsg_echo
        CP 0x3a
        JP nc,progmsg_other_key
        CP 0x30
        JP c,progmsg_other_key

; ---- progmsg_echo: draw the digit after the prompt, D/d = channel 10
progmsg_echo:
        LD (CUR_CHAR),A
        CALL glyph_lookup
        CALL fb_rewind_window
        LD A,(EDIT_KEY)
        CP 0x44
        JR z,progmsg_demo
        CP 0x64
        JR nz,editor_select_chan

progmsg_demo:
        LD A,10

; ---- editor_select_chan: A & 15 = channel: chan_select (failure resets the sign),
;      PROG_MSG_FORCE = 0, INS_PTR = text, STORE_CURSOR = marker
editor_select_chan:
        AND 15
        LD E,A
        OR 0xd0
        CALL chan_select
        OR A
        JP nz,store_fault_reset
        LD A,0
        LD (PROG_MSG_FORCE),A
        LD (INS_PTR),HL
        DEC HL
        LD (STORE_CURSOR),HL

; ---- select_chan_flag
select_chan_flag:
        PUSH DE
        CALL clear_chan_lock
        POP DE
        LD D,0
        LD HL,CHAN_STATE
        ADD HL,DE
        LD A,0xff
        LD (HL),A
        JP show_top_of_msg

; ---- progmsg_other_key: 0D exits the editor, 0C goes to SEQ?, else wait
progmsg_other_key:
        CP 13
        JP z,editor_exit
        CP 12
        JR nz,progmsg_next_key
        LD A,0
        LD (PROG_MSG_FORCE),A
        JP menu_seq_msg

progmsg_next_key:
        JP editor_next_key

; ---- menu_seq_msg: 04: SEQ? dialogue; further keys come back here while SEQ_MENU_ACTIVE bit
;      7 is set
menu_seq_msg:
        LD A,(EDIT_KEY)
        CP 4
        JR nz,seqmenu_key

; ---- seqmenu_prompt: SEQ_MENU_ACTIVE = F0, 'SEQ MSG?' as the SHIFT_LABEL message
seqmenu_prompt:
        LD A,0xf0
        LD (SEQ_MENU_ACTIVE),A                       ; SEQ_MENU_ACTIVE: bit 7 = dialogue open, bit 0 = list already cleared
        LD HL,MENU_STR_SEQ_MSG
        LD (MENU_MSG_PTR),HL                         ; MENU_MSG_PTR = MENU_STR_SEQ_MSG
        LD A,0xff
        LD (SHIFT_LABEL),A
        JP editor_loop

; ---- seqmenu_key: digit or D/d adds a channel; other keys -> seqmenu_other_key
seqmenu_key:
        LD A,(EDIT_KEY)
        CP 0x44
        JR z,seqmenu_digit
        CP 0x64
        JR z,seqmenu_digit
        CP 0x3a
        JP nc,seqmenu_other_key
        CP 0x30
        JP c,seqmenu_other_key

; ---- seqmenu_digit: first entry clears the list (bit 0 of SEQ_MENU_ACTIVE)
seqmenu_digit:
        LD A,(SEQ_MENU_ACTIVE)
        BIT 0,A
        JR nz,seqmenu_check_full
        LD HL,SEQ_LIST
        LD B,0x20
        LD A,0xff

seqmenu_clear:
        LD (HL),A
        INC HL
        DJNZ seqmenu_clear
        LD (SEQ_MENU_ACTIVE),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL

; ---- seqmenu_check_full: 32 entries -> ' SEQ FULL ' and ignore
seqmenu_check_full:
        LD A,(EDIT_KEY)
        LD (CUR_CHAR),A
        LD HL,SEQ_LIST
        LD DE,0x0020
        ADD HL,DE
        LD DE,(SEQ_PTR)
        OR A
        SBC HL,DE
        LD A,H
        OR L
        JR nz,seqmenu_value
        LD HL,MENU_STR_SEQ_FULL
        INC HL
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        CALL fb_rewind_window
        JP editor_next_key

seqmenu_value:
        LD A,(EDIT_KEY)
        CP 0x44
        JR z,seqmenu_demo
        CP 0x64
        JR nz,seqmenu_store

seqmenu_demo:
        LD A,10

; ---- seqmenu_store: append the channel, FF after it, echo the digit
seqmenu_store:
        AND 15
        LD HL,(SEQ_PTR)
        LD (HL),A
        INC HL
        LD A,0xff
        LD (HL),A
        LD (SEQ_PTR),HL
        LD A,(EDIT_KEY)
        LD (CUR_CHAR),A
        CALL glyph_lookup
        CALL fb_rewind_window
        JP editor_next_key

; ---- seqmenu_other_key: 0D exit, 0E clear the list; any other key closes the dialogue and
;      goes on to menu_prog_msg
seqmenu_other_key:
        CP 13
        JP z,editor_exit
        CP 14
        JP z,editor_key_clear
        LD A,0
        LD (SEQ_MENU_ACTIVE),A                       ; SEQ_MENU_ACTIVE = 0
        JP menu_prog_msg

; ---- editor_getkey: serial mode: echo the previous key if KEY_ECHO_TX, then take RX_BYTE as
;      the key, raw ASCII, no charset lookup. Keypad mode: wait for release, then a code
;      stable on two consecutive ticks (KEY_TIMER paces the samples), 19 toggles SHIFT, else
;      translate through CHARSET_LOWER/UPPER/UPPER2/LOWER2 by SHIFT_STATE and CAPS_LOCK
editor_getkey:
        LD A,(INPUT_MODE)
        AND A
        JR z,getkey_wait_release
        LD A,(KEY_ECHO_TX)
        AND A
        JR z,getkey_serial

; ---- getkey_echo: queue the echo until the TX engine takes it
getkey_echo:
        CALL tx_try_queue
        AND A
        JR nz,getkey_echo

; ---- getkey_serial: take and clear RX_BYTE under DI
getkey_serial:
        DI
        LD A,(RX_BYTE)
        LD (IR_KEY_CHAR),A
        XOR A
        LD (RX_BYTE),A
        EI
        NOP
        JP getkey_history

; ---- getkey_wait_release: keypad: two consecutive ticks with no key down
getkey_wait_release:
        LD A,2
        LD C,A
        LD (KEY_TIMER),A

getkey_release_tick:
        DEC C
        JR z,getkey_wait_key

; ---- getkey_release_poll: wait for KEY_TIMER = C, then test RX_BYTE
getkey_release_poll:
        LD A,(KEY_TIMER)
        AND A
        JR z,getkey_wait_release
        CP C
        JR nz,getkey_release_poll
        LD A,(RX_BYTE)
        AND A
        JR z,getkey_release_tick
        JR getkey_wait_release

; ---- getkey_wait_key: then wait for a key code that reads the same on two consecutive
;      ticks (debounce)
getkey_wait_key:
        XOR A
        LD (RX_BYTE),A
        LD (IR_KEY_CHAR),A

getkey_key_arm:
        LD A,2
        LD (KEY_TIMER),A
        LD C,A

getkey_key_tick:
        DEC C
        JR z,getkey_check_shift

; ---- getkey_key_poll: no key or a different code restarts the count
getkey_key_poll:
        LD A,(KEY_TIMER)
        AND A
        JR z,getkey_wait_key
        CP C
        JR nz,getkey_key_poll
        LD A,(IR_KEY_CHAR)
        LD B,A
        LD A,(RX_BYTE)
        LD (IR_KEY_CHAR),A
        AND A
        JR z,getkey_key_arm
        CP B
        JR nz,getkey_key_arm
        JR getkey_key_tick

; ---- getkey_check_shift: key 19 toggles SHIFT_STATE: 1D while on, 9F when off
getkey_check_shift:
        LD A,(IR_KEY_CHAR)
        CP 0x19
        JR nz,getkey_translate
        LD A,(SHIFT_STATE)
        CPL
        LD (SHIFT_STATE),A
        AND A
        LD A,0x1d
        JR nz,getkey_shift_code
        LD A,0x9f

getkey_shift_code:
        LD (IR_KEY_CHAR),A
        JP getkey_history

; ---- getkey_translate: key code -> character through the four CHARSET_ tables
getkey_translate:
        LD A,(SHIFT_STATE)
        LD HL,CHARSET_LOWER
        AND A
        JR z,getkey_caps
        LD HL,CHARSET_UPPER2
        LD A,(CAPS_LOCK)
        AND A
        JR z,getkey_lookup
        LD HL,CHARSET_LOWER2
        JR getkey_lookup

getkey_caps:
        LD A,(CAPS_LOCK)
        AND A
        JR z,getkey_lookup
        LD HL,CHARSET_UPPER

getkey_lookup:
        LD A,(IR_KEY_CHAR)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(HL)
        LD (IR_KEY_CHAR),A
        LD A,0
        LD (SHIFT_STATE),A

; ---- getkey_history: PREV_KEY2/PREV_KEY shift, EDIT_KEY = key, KEY_ECHO_TX = key (echoed
;      on the next call in serial modes)
getkey_history:
        LD A,(PREV_KEY)
        LD (PREV_KEY2),A
        LD A,(EDIT_KEY)
        LD (PREV_KEY),A
        LD A,(IR_KEY_CHAR)
        LD (EDIT_KEY),A
        LD (KEY_ECHO_TX),A
        RET

; ---- editor_key_shift: 1D: show the SHIFT label while SHIFT_STATE is set
editor_key_shift:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,editor_loop
        LD A,(SHIFT_STATE)
        OR A
        JR z,shift_done
        LD A,0xff
        LD (SHIFT_LABEL),A
        LD HL,STR_SHIFT
        LD (MENU_MSG_PTR),HL

shift_done:
        JP editor_loop

; ---- editor_delete: 7F: delete the byte under the cursor (not on 03 or a marker; the
;      display is blanked and DISP_ON left 0 until the redraw)
editor_delete:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_loop
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,0
        LD (DISP_ON),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,editor_loop
        AND 0xf0
        CP 0xd0
        JP z,show_top_of_msg
        LD HL,(STORE_END)
        DEC HL
        LD (STORE_END),HL
        CALL unfetch_char
        LD HL,(STORE_CURSOR)
        INC HL
        LD (MOVE_DST),HL
        INC HL
        LD (MOVE_SRC),HL
        LD DE,STORE_TOP
        EX DE,HL
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        LD HL,(MOVE_SRC)
        LD DE,(MOVE_DST)
        LDIR
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,show_top_of_msg
        JP editor_loop

; ---- cursor_right: 0A: one byte right, not past the 03
cursor_right:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JR z,cursor_right_done
        INC HL
        LD A,(HL)

cursor_right_set:
        LD (STORE_CURSOR),HL

cursor_right_done:
        JP editor_loop

; ---- cursor_right_8: 0C
cursor_right_8:
        LD B,8
        LD HL,(STORE_CURSOR)

right8_loop:
        LD A,(HL)
        CP TEXT_END
        JR z,right8_done
        INC HL
        LD (STORE_CURSOR),HL
        DJNZ right8_loop

right8_done:
        JP editor_loop

; ---- cursor_left: 08: one byte left; on or onto a marker -> show_top_of_msg
cursor_left:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,show_top_of_msg
        DEC HL
        LD (STORE_CURSOR),HL
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,show_top_of_msg
        JP editor_loop

; ---- cursor_left_8: 0B: up to eight bytes left, stopping at the marker
cursor_left_8:
        LD B,8
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,show_top_of_msg

left8_step:
        DEC HL
        LD (STORE_CURSOR),HL
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,show_top_of_msg
        DJNZ left8_step
        JP editor_loop

; ---- editor_insert: insert EDIT_KEY at the cursor (' MEMORY FULL ' at STORE_TOP, ' 100 KEYS
;      LEFT ' at STORE_TOP-100); the LDDR shifts everything up to STORE_TOP
editor_insert:
        LD (CUR_CHAR),A
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_show_invalid
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JP z,insert_done

insert_do:
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,0
        LD (DISP_ON),A
        LD HL,(STORE_END)
        INC HL
        LD (STORE_TMP),HL
        LD DE,STORE_TOP
        OR A
        SBC HL,DE
        LD A,H
        OR L
        JR nz,insert_shift
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_MEM_FULL
        LD (MENU_MSG_PTR),HL
        JP editor_loop

insert_shift:
        LD HL,(STORE_TMP)
        LD (STORE_END),HL
        CALL store_make_room
        LD HL,STORE_TOP
        LD (MOVE_DST),HL
        DEC HL
        LD (MOVE_SRC),HL
        LD DE,(STORE_CURSOR)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        LD HL,(MOVE_SRC)
        LD DE,(MOVE_DST)
        INC BC
        LDDR
        LD HL,(STORE_CURSOR)
        LD A,(CUR_CHAR)
        LD (HL),A
        LD HL,(STORE_END)
        LD DE,STORE_TOP-100
        OR A
        SBC HL,DE
        JR nz,insert_done
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_100_KEYS
        LD (MENU_MSG_PTR),HL

insert_done:
        JP editor_loop

; ---- store_make_room
store_make_room:
        LD HL,(STORE_CURSOR)
        LD DE,STORE_TOP
        INC HL
        LD (STORE_CURSOR),HL
        OR A
        SBC HL,DE
        JR nz,makeroom_ret
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,makeroom_wrap_flag
        LD HL,MSG_STORE
        LD (STORE_CURSOR),HL
        JR makeroom_ret

makeroom_wrap_flag:
        LD A,0xff
        LD (STORE_WRAPPED),A

makeroom_ret:
        RET

; ---- apply_prefixes: turn a pending GRAPH / FORE / BACK / SPEED prefix plus this key into
;      the attribute byte
apply_prefixes:
        CALL apply_graph_prefix
        CALL apply_color_prefix
        CALL apply_speed_prefix
        RET

; ---- apply_graph_prefix: GRAPH n -> A0|n
apply_graph_prefix:
        LD A,(GRAPH_PENDING)
        OR A
        RET z
        LD A,(EDIT_KEY)
        AND 15
        OR GRAPH_BASE
        LD (EDIT_KEY),A
        LD A,0
        LD (GRAPH_PENDING),A
        RET

; ---- apply_speed_prefix: SPEED n -> F0|(n&7)
apply_speed_prefix:
        LD A,(SPEED_PENDING)
        AND A
        RET z
        LD A,(EDIT_KEY)
        AND 7
        OR SPEED_BASE
        LD (EDIT_KEY),A
        XOR A
        LD (SPEED_PENDING),A
        RET

; ---- apply_color_prefix: COLOR n -> FG_IDX_TABLE, BGRND n -> BG_IDX_TABLE
apply_color_prefix:
        LD A,(COLOR_PENDING)
        AND A
        JR nz,prefix_fore
        LD A,(BGRND_PENDING)
        AND A
        JR nz,prefix_back
        RET

prefix_fore:
        LD A,(EDIT_KEY)
        AND 7
        DEC A
        CP 6
        JR nz,prefix_fore_lookup
        LD A,2

prefix_fore_lookup:
        NOP
        LD HL,FG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (EDIT_KEY),A
        XOR A
        LD (COLOR_PENDING),A
        RET

prefix_back:
        LD A,(EDIT_KEY)
        AND 7
        DEC A
        CP 6
        JR nz,prefix_back_lookup
        LD A,5

prefix_back_lookup:
        NOP
        LD HL,BG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (EDIT_KEY),A
        XOR A
        LD (BGRND_PENDING),A
        RET

; ---- FG_IDX_TABLE: FORE n: six foreground codes; index 6 -> 2
FG_IDX_TABLE:
        db 0x8c,0x8d,0x8f,0x87,0x83,0x80

; ---- BG_IDX_TABLE: BACK n: six background codes; index 6 -> 5
BG_IDX_TABLE:
        db 0x91,0x93,0x93,0x93,0x92,0x90

; ---- editor_redraw: redraw the editor view: up to 21 bytes before the cursor with attribute
;      labels from ATTR_LABEL_TABLE, then the status labels and any pending message
editor_redraw:
        CALL clear_txbuf
        CALL init_render
        XOR A
        LD (DISP_ON),A
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,(PROG_MSG_FORCE)
        AND A
        JP nz,redraw_status
        LD A,(SEQ_MENU_ACTIVE)
        BIT 7,A
        JP nz,redraw_status
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,redraw_status

redraw_window:
        LD DE,0x0015                                 ; 21 bytes before the cursor
        OR A
        SBC HL,DE
        LD (REDRAW_FROM),HL
        LD DE,(INS_PTR)
        OR A
        SBC HL,DE
        JR nc,redraw_start
        EX DE,HL
        LD (REDRAW_FROM),HL

redraw_start:
        LD HL,(INS_PTR)
        LD (REDRAW_PTR),HL

redraw_loop:
        LD HL,(REDRAW_PTR)
        LD A,(HL)
        LD (CUR_CHAR),A
        LD A,0xff
        LD (TINY_MODE),A
        LD A,(CUR_CHAR)
        CP ' '
        JR nz,redraw_classify
        LD A,0
        LD (FLASH_BIT),A
        JP redraw_char_check

; ---- redraw_classify: bit 7 -> redraw_high_byte; bits 5,6 clear -> attribute; else
;      printable
redraw_classify:
        BIT 7,A
        JP nz,redraw_high_byte
        AND 0x60
        JR z,redraw_attr
        JP redraw_char_check

; ---- redraw_high_byte: A0-AF are drawn as graphics; other 80-FF bytes go to the label
;      lookup
redraw_high_byte:
        LD A,(CUR_CHAR)
        AND 0xf0
        CP 0xa0
        JP z,redraw_char_check

; ---- redraw_attr: movement attributes force bold, 18 clears it, 10-14 track the font; then
;      the label
redraw_attr:
        LD A,(CUR_CHAR)

redraw_attr2:
        CP 15
        JP z,redraw_force_bold
        CP ATTR_PAUSE
        JP z,redraw_force_bold
        CP ATTR_UP
        JP z,redraw_force_bold
        CP ATTR_DOWN
        JP z,redraw_force_bold
        CP ATTR_LEFT
        JP z,redraw_left_attr
        CP ATTR_NORM
        JP nz,redraw_flash
        XOR A
        LD (FLASH_BIT),A
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_flash:
        CP 0x14
        JP nz,redraw_italic
        LD A,0x10
        LD (FLASH_BIT),A
        JR redraw_label_check

redraw_italic:
        CP 0x13
        JP nz,redraw_bold
        LD A,(FONT_MODE)
        SET 2,A
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_bold:
        CP 0x12
        JP nz,redraw_big
        LD A,(FONT_MODE)
        SET 1,A
        RES 3,A
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_big:
        CP 0x10
        JP nz,redraw_label_check
        LD A,(FONT_MODE)
        SET 1,A
        SET 3,A
        LD (FONT_MODE),A
        JP redraw_label_check

; ---- redraw_force_bold: 0F/19/1A/1B: the following text is shown bold, as the effects draw
;      it
redraw_force_bold:
        LD A,0xff
        LD (FORCE_BOLD),A
        JP redraw_label_check

redraw_left_attr:
        LD A,0
        LD (FORCE_BOLD),A
        JP redraw_label_check

redraw_label_check:
        LD HL,(REDRAW_PTR)
        LD DE,(REDRAW_FROM)
        OR A
        EX DE,HL
        SBC HL,DE
        EX DE,HL
        JP c,redraw_show_label
        JP z,redraw_show_label
        JP redraw_next

; ---- redraw_show_label: ATTR_LABEL_TABLE[CUR_CHAR] rendered in tiny mode. The table is
;      indexed by the whole byte: 80-9F land in COLOR_NAME_TABLE, the markers D0-DA in
;      MSG_TOP_TABLE and F0-F7 in SPEED_STR_TABLE, which sit where those entries fall
redraw_show_label:
        LD HL,ATTR_LABEL_TABLE
        LD A,(CUR_CHAR)
        LD E,A
        LD D,0
        SLA E
        RL D
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (MENU_TEXT_PTR),DE
        CALL menu_show_text
        LD A,(CUR_CHAR)
        JP redraw_next

redraw_char_check:
        LD HL,(REDRAW_PTR)
        LD DE,(REDRAW_FROM)
        OR A
        EX DE,HL
        SBC HL,DE
        EX DE,HL
        JP c,redraw_char
        JP z,redraw_char
        JP redraw_next

redraw_char:
        XOR A
        LD (TINY_MODE),A
        LD A,(CUR_CHAR)
        AND 0xf0
        CP GRAPH_BASE
        LD A,(CUR_CHAR)
        JR nz,redraw_char_glyph
        AND 15
        LD (CUR_CHAR),A

redraw_char_glyph:
        CALL glyph_lookup

redraw_next:
        LD HL,(REDRAW_PTR)
        INC HL
        LD (REDRAW_PTR),HL
        LD DE,(STORE_CURSOR)
        EX DE,HL
        OR A
        SBC HL,DE
        EX DE,HL
        JP nc,redraw_loop

redraw_status:
        LD A,0xff
        LD (TINY_MODE),A
        LD A,(GRAPH_PENDING)
        AND A
        JR z,status_not_graph
        LD HL,STR_GRAPH
        JR status_show

status_not_graph:
        LD A,(COLOR_PENDING)
        OR A
        JR z,status_not_color
        LD HL,STR_COLOR
        JR status_show

status_not_color:
        LD A,(BGRND_PENDING)
        OR A
        JR z,status_not_bgrnd
        LD HL,STR_BGRND
        JR status_show

status_not_bgrnd:
        LD A,(SPEED_PENDING)
        OR A
        JR z,status_shift_msg
        LD HL,STR_SPEED

status_show:
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        JR status_shift_msg

status_shift_msg:
        LD A,(SHIFT_LABEL)
        AND A
        JR z,status_menu_msg
        LD HL,(MENU_MSG_PTR)
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

status_menu_msg:
        LD A,(MENU_MSG_FLAG)
        OR A
        JR z,redraw_finish
        LD HL,(MENU_MSG_PTR)
        INC HL
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

redraw_finish:
        CALL fb_rewind_window
        LD A,(MENU_MSG_FLAG)
        OR A
        JR z,redraw_ret
        CALL redraw_hold
        LD A,0
        LD (MENU_MSG_FLAG),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JR nz,redraw_again
        POP HL
        JP show_top_of_msg

redraw_again:
        JP editor_redraw

redraw_ret:
        LD A,0xff
        LD (DISP_ON),A
        RET

; ---- redraw_hold: let one frame out, then hold HOLD_FRAMES frames
redraw_hold:
        LD A,0xff
        LD (DISP_ON),A

hold_wait_row3:
        LD A,(ROW_INDEX)
        CP 3
        JR nz,hold_wait_row3

hold_wait_row2:
        LD A,(ROW_INDEX)
        CP 2
        JR nz,hold_wait_row2
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A

hold_wait_frames:
        LD A,(FRAME_DELAY)
        AND A
        JR nz,hold_wait_frames
        RET

; ---- menu_show_text: Render the NUL-terminated string at MENU_TEXT_PTR in tiny font
menu_show_text:
        LD HL,(MENU_TEXT_PTR)
        LD A,(TINY_MODE)
        PUSH AF
        LD A,0xff
        LD (TINY_MODE),A

showtext_loop:
        LD A,(HL)
        INC HL
        OR A
        JR z,showtext_done
        LD (CUR_CHAR),A
        PUSH HL
        CALL glyph_lookup
        POP HL
        JP showtext_loop

showtext_done:
        POP AF
        LD (TINY_MODE),A
        RET

; ---- fb_rewind_window: FB_COL = FB_COLPTR - FRAME_COLS (ring wrap)
fb_rewind_window:
        LD HL,(FB_COLPTR)
        LD DE,FRAME_COLS
        XOR A
        SBC HL,DE
        LD (FB_COL),HL
        LD DE,FRAMEBUF
        XOR A
        SBC HL,DE
        JP nc,rewind_ret
        LD DE,FB_COLPTR
        ADD HL,DE
        LD (FB_COL),HL

rewind_ret:
        RET

; ---- store_fault_reset: every store-consistency failure ends here: restart from RESET
store_fault_reset:
        JP RESET

; ---- ATTR_LABEL_TABLE: editor label per attribute byte 00-1F (0 = none). This ROM's names:
;      01 SPEED, 03 END, 04 SEQ MSG?, 06 PAUSE, 07 BEEP, 09 PROG MSG?, 0F BCRAWL, 10 BIG, 11
;      NORM, 12 BOLD, 13 ITALIC, 14 FLASH, 15 FORE, 16 BACK, 18 CRAWL, 19 JUMP, 1A UP, 1B
;      DOWN, 1D SHIFT, 1E GRAPH, 1F MAGIC. redraw_show_label indexes it with the full byte,
;      so the data that follows doubles as entries 20-FF
ATTR_LABEL_TABLE:
        dw 0
        dw STR_SPEED
        dw 0
        dw STR_END
        dw MENU_STR_SEQ_MSG
        dw 0
        dw STR_PAUSE
        dw STR_BEEP
        dw 0
        dw MENU_STR_PROG_MSG
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw STR_BCRAWL
        dw STR_BIG
        dw STR_NORM
        dw STR_BOLD
        dw STR_ITALIC
        dw STR_FLASH
        dw STR_COLOR
        dw STR_BGRND
        dw 0
        dw STR_CRAWL
        dw STR_JUMP
        dw STR_UP
        dw STR_DOWN
        dw 0
        dw STR_SHIFT
        dw STR_GRAPH
        dw STR_MAGIC

; ---- MSG_TOP_STRINGS: 'TOP OF MSG  0' .. 'TOP OF MSG  9' and 'TOP DEMO MSG', 16 bytes each,
;      pointed to by MSG_TOP_TABLE
MSG_TOP_STRINGS:
        db "TOP OF MSG  0",0x00,0x00,0x00
        db "TOP OF MSG  1",0x00,0x00,0x00
        db "TOP OF MSG  2",0x00,0x00,0x00
        db "TOP OF MSG  3",0x00,0x00,0x00
        db "TOP OF MSG  4",0x00,0x00,0x00
        db "TOP OF MSG  5",0x00,0x00,0x00
        db "TOP OF MSG  6",0x00,0x00,0x00
        db "TOP OF MSG  7",0x00,0x00,0x00
        db "TOP OF MSG  8",0x00,0x00,0x00
        db "TOP OF MSG  9",0x00,0x00,0x00
        db "TOP DEMO MSG ",0x00,0x00,0x00

STR_BEEP:
        db "<BEEP>",0x00

STR_BCRAWL:
        db "<BCRAWL>",0x00

; ---- COLOR_NAME_TABLE: ATTR_LABEL_TABLE entries 80-9F: 16 foreground names, then B-BLK
;      B-RED B-GRE B-YEL four times for 90-9F
COLOR_NAME_TABLE:
        dw STR_C_BLACK
        dw STR_C_BLACK+8
        dw STR_C_BLACK+12
        dw STR_C_BLACK+16
        dw STR_C_BLACK+24
        dw STR_C_BLACK+28
        dw STR_C_BLACK+32
        dw STR_C_BLACK+36
        dw STR_C_BLACK+43
        dw STR_C_BLACK+47
        dw STR_C_BLACK+51
        dw STR_C_BLACK+55
        dw STR_C_BLACK+59
        dw STR_C_BLACK+65
        dw STR_C_BLACK+74
        dw STR_C_BLACK+78
        dw STR_B_BLK
        dw STR_B_RED
        dw STR_B_GRE
        dw STR_B_YEL
        dw STR_B_BLK
        dw STR_B_RED
        dw STR_B_GRE
        dw STR_B_YEL
        dw STR_B_BLK
        dw STR_B_RED
        dw STR_B_GRE
        dw STR_B_YEL
        dw STR_B_BLK
        dw STR_B_RED
        dw STR_B_GRE
        dw STR_B_YEL

STR_B_BLK:
        db "<B-BLK>",0x00

STR_B_RED:
        db "<B-RED>",0x00

STR_B_YEL:
        db "<B-YEL>",0x00

STR_B_GRE:
        db "<B-GRE>",0x00

STR_COLOR:
        db " <FORE",0x00,0x00

STR_BGRND:
        db " <BACK",0x00,0x00

STR_NORM:
        db "<NORM>",0x00,0x00

STR_BOLD:
        db "<BOLD>",0x00,0x00

STR_ITALIC:
        db "<ITALIC>",0x00

STR_FLASH:
        db "<FLASH>",0x00

STR_END:
        db "<END>",0x00,0x00

STR_CRAWL:
        db "<CRAWL>",0x00

; ---- MSG_TOP_TABLE: 32 pointers indexed by channel, then zeros; show_top_of_msg puts the
;      entry into MENU_MSG_PTR. These are also ATTR_LABEL_TABLE entries D0-DF, so a marker in
;      the editor view shows the title of its channel
MSG_TOP_TABLE:
        dw MSG_TOP_STRINGS
        dw MSG_TOP_STRINGS+16
        dw MSG_TOP_STRINGS+32
        dw MSG_TOP_STRINGS+48
        dw MSG_TOP_STRINGS+64
        dw MSG_TOP_STRINGS+80
        dw 0x194c
        dw 0x195c
        dw 0x196c
        dw 0x197c
        dw 0x198c
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0

; ---- SPEED_STR_TABLE: ATTR_LABEL_TABLE entries F0-F7: '<S0>'..'<S7>'
SPEED_STR_TABLE:
        dw STR_SPEED_0
        dw STR_SPEED_0+5
        dw STR_SPEED_0+10
        dw STR_SPEED_0+15
        dw STR_SPEED_0+20
        dw STR_SPEED_0+25
        dw STR_SPEED_0+30
        dw STR_SPEED_0+35

STR_BIG:
        db "<BIG>",0x00

MENU_STR_TIME:
        db " TIME?    ",0x00

MENU_STR_AM_PM:
        db " AM? Y/N ",0x00

MENU_STR_PROG_MSG:
        db "PROG MSG?  ",0x00

MENU_STR_SEQ_MSG:
        db "SEQ MSG?  ",0x00

STR_SHIFT:
        db "<SHIFT>",0x00

; ---- MENU_STR_INVALID: 03 then the text: the leading byte is skipped when shown through
;      MENU_MSG_FLAG (+1) and drawn as glyph 03 when shown as the SHIFT_LABEL message
MENU_STR_INVALID:
        db 0x03,"    INVALID    ",0x00

MENU_STR_MEM_FULL:
        db 0x0a," MEMORY FULL  ",0x00

MENU_STR_100_KEYS:
        db 0x05," 100 KEYS LEFT ",0x00

MENU_STR_SEQ_FULL:
        db 0x03," SEQUENCE FULL",0x00

STR_JUMP:
        db "<JUMP>",0x00

STR_UP:
        db "<UP>",0x00

STR_DOWN:
        db "<DOWN>",0x00

STR_SPEED:
        db "<SPEED ",0x00

STR_PAUSE:
        db "<PAUSE>",0x00

STR_GRAPH:
        db "<GRAPH ",0x00

STR_MAGIC:
        db "<MAGIC>",0x00

; ---- STR_C_BLACK: the 16 foreground names: only BLACK (80), GREEN (83), LIME (87), RED
;      (8C), ORANGE (8D) and YELLOW (8F) are named, the six colors of the demo's 'SIX
;      EXCITING COLORS'; the rest show '<?>'
STR_C_BLACK:
        db "<BLACK>",0x00
        db "<?>",0x00
        db "<?>",0x00
        db "<GREEN>",0x00
        db "<?>",0x00
        db "<?>",0x00
        db "<?>",0x00
        db "<LIME>",0x00
        db "<?>",0x00
        db "<?>",0x00
        db "<?>",0x00
        db "<?>",0x00
        db "<RED>",0x00
        db "<ORANGE>",0x00
        db "<?>",0x00
        db "<YELLOW>",0x00

STR_SPEED_0:
        db "<S0>",0x00
        db "<S1>",0x00
        db "<S2>",0x00
        db "<S3>",0x00
        db "<S4>",0x00
        db "<S5>",0x00
        db "<S6>",0x00
        db "<S7>",0x00

; ---- FONT: 128 glyphs x 8 bytes (seven column bytes + width), indexed directly by the byte
;      value: 00-0F are the A0-AF graphics
FONT:
        db 0x1c,0x14,0x14,0x77,0x22,0x14,0x08,0x07   ; glyph   0 width 7
        db 0x08,0x14,0x22,0x77,0x14,0x14,0x1c,0x07   ; glyph   1 width 7
        db 0x30,0x70,0x38,0x34,0x3c,0x74,0x38,0x07   ; glyph   2 width 7
        db 0x20,0x70,0x70,0x3f,0x02,0x04,0x00,0x06   ; glyph   3 width 6
        db 0x08,0x1c,0x22,0x2a,0x22,0x1c,0x08,0x07   ; glyph   4 width 7
        db 0x07,0x49,0x79,0x49,0x07,0x00,0x00,0x05   ; glyph   5 width 5
        db 0x10,0x18,0x1c,0x18,0x10,0x00,0x00,0x05   ; glyph   6 width 5
        db 0x08,0x1c,0x3e,0x7f,0x3e,0x1c,0x08,0x07   ; glyph   7 width 7
        db 0x7f,0x7f,0x7f,0x7f,0x7f,0x00,0x00,0x06   ; glyph   8 width 6
        db 0x1c,0x3e,0x7f,0x7f,0x3e,0x1c,0x00,0x07   ; glyph   9 width 7
        db 0x04,0x7c,0x46,0x77,0x46,0x7c,0x04,0x07   ; glyph  10 width 7
        db 0x10,0x30,0x54,0x56,0x5f,0x50,0x30,0x07   ; glyph  11 width 7
        db 0x18,0x1e,0x7f,0x1e,0x18,0x00,0x00,0x05   ; glyph  12 width 5
        db 0x2c,0x6e,0x6d,0x6f,0x6f,0x3e,0x1c,0x07   ; glyph  13 width 7
        db 0x1c,0x22,0x41,0x4f,0x51,0x22,0x1c,0x07   ; glyph  14 width 7
        db 0x20,0x3c,0x22,0x63,0x22,0x3c,0x20,0x07   ; glyph  15 width 7
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  16 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  17 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  18 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  19 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  20 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  21 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  22 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  23 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  24 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  25 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  26 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  27 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  28 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  29 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  30 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  31 width 1
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x06   ; glyph  32 width 6
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02   ; glyph  33 width 2
        db 0x07,0x00,0x07,0x00,0x00,0x00,0x00,0x03   ; glyph  34 width 3
        db 0x14,0x7f,0x14,0x7f,0x14,0x00,0x00,0x05   ; glyph  35 width 5
        db 0x26,0x49,0x7f,0x49,0x32,0x00,0x00,0x05   ; glyph  36 width 5
        db 0x42,0x25,0x12,0x08,0x24,0x52,0x21,0x07   ; glyph  37 width 7
        db 0x60,0x5e,0x55,0x55,0x41,0x02,0x00,0x06   ; glyph  38 width 6
        db 0x07,0x00,0x00,0x00,0x00,0x00,0x00,0x01   ; glyph  39 width 1
        db 0x1c,0x22,0x41,0x00,0x00,0x00,0x00,0x03   ; glyph  40 width 3
        db 0x41,0x22,0x1c,0x00,0x00,0x00,0x00,0x03   ; glyph  41 width 3
        db 0x2a,0x1c,0x7f,0x1c,0x2a,0x00,0x00,0x05   ; glyph  42 width 5
        db 0x08,0x08,0x3e,0x08,0x08,0x00,0x00,0x05   ; glyph  43 width 5
        db 0x40,0x30,0x30,0x00,0x00,0x00,0x00,0x03   ; glyph  44 width 3
        db 0x08,0x08,0x08,0x08,0x00,0x00,0x00,0x04   ; glyph  45 width 4
        db 0x60,0x60,0x00,0x00,0x00,0x00,0x00,0x02   ; glyph  46 width 2
        db 0x40,0x20,0x10,0x08,0x04,0x02,0x01,0x07   ; glyph  47 width 7
        db 0x3e,0x51,0x49,0x45,0x3e,0x00,0x00,0x05   ; glyph  48 width 5
        db 0x41,0x7f,0x40,0x00,0x00,0x00,0x00,0x03   ; glyph  49 width 3
        db 0x42,0x61,0x51,0x49,0x46,0x00,0x00,0x05   ; glyph  50 width 5
        db 0x22,0x41,0x49,0x49,0x36,0x00,0x00,0x05   ; glyph  51 width 5
        db 0x08,0x0c,0x0a,0x7f,0x08,0x00,0x00,0x05   ; glyph  52 width 5
        db 0x2f,0x49,0x49,0x49,0x31,0x00,0x00,0x05   ; glyph  53 width 5
        db 0x3c,0x4a,0x49,0x49,0x30,0x00,0x00,0x05   ; glyph  54 width 5
        db 0x01,0x71,0x09,0x05,0x03,0x00,0x00,0x05   ; glyph  55 width 5
        db 0x36,0x49,0x49,0x49,0x36,0x00,0x00,0x05   ; glyph  56 width 5
        db 0x06,0x49,0x49,0x49,0x3e,0x00,0x00,0x05   ; glyph  57 width 5
        db 0x6c,0x6c,0x00,0x00,0x00,0x00,0x00,0x02   ; glyph  58 width 2
        db 0x80,0x6c,0x6c,0x00,0x00,0x00,0x00,0x03   ; glyph  59 width 3
        db 0x08,0x14,0x22,0x41,0x00,0x00,0x00,0x04   ; glyph  60 width 4
        db 0x14,0x14,0x14,0x14,0x00,0x00,0x00,0x04   ; glyph  61 width 4
        db 0x41,0x22,0x14,0x08,0x00,0x00,0x00,0x04   ; glyph  62 width 4
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05   ; glyph  63 width 5
        db 0x3e,0x41,0x4f,0x49,0x2e,0x00,0x00,0x05   ; glyph  64 width 5
        db 0x7e,0x09,0x09,0x09,0x7e,0x00,0x00,0x05   ; glyph  65 width 5
        db 0x7f,0x49,0x49,0x49,0x36,0x00,0x00,0x05   ; glyph  66 width 5
        db 0x3e,0x41,0x41,0x41,0x22,0x00,0x00,0x05   ; glyph  67 width 5
        db 0x7f,0x41,0x41,0x41,0x3e,0x00,0x00,0x05   ; glyph  68 width 5
        db 0x7f,0x49,0x49,0x49,0x41,0x00,0x00,0x05   ; glyph  69 width 5
        db 0x7f,0x09,0x09,0x09,0x01,0x00,0x00,0x05   ; glyph  70 width 5
        db 0x3e,0x41,0x41,0x51,0x32,0x00,0x00,0x05   ; glyph  71 width 5
        db 0x7f,0x08,0x08,0x08,0x7f,0x00,0x00,0x05   ; glyph  72 width 5
        db 0x41,0x7f,0x41,0x00,0x00,0x00,0x00,0x03   ; glyph  73 width 3
        db 0x20,0x40,0x41,0x3f,0x01,0x00,0x00,0x05   ; glyph  74 width 5
        db 0x7f,0x08,0x14,0x22,0x41,0x00,0x00,0x05   ; glyph  75 width 5
        db 0x7f,0x40,0x40,0x40,0x40,0x00,0x00,0x05   ; glyph  76 width 5
        db 0x7f,0x02,0x0c,0x02,0x7f,0x00,0x00,0x05   ; glyph  77 width 5
        db 0x7f,0x02,0x04,0x08,0x7f,0x00,0x00,0x05   ; glyph  78 width 5
        db 0x3e,0x41,0x41,0x41,0x3e,0x00,0x00,0x05   ; glyph  79 width 5
        db 0x7f,0x09,0x09,0x09,0x06,0x00,0x00,0x05   ; glyph  80 width 5
        db 0x3e,0x41,0x51,0x61,0x7e,0x00,0x00,0x05   ; glyph  81 width 5
        db 0x7f,0x09,0x19,0x29,0x46,0x00,0x00,0x05   ; glyph  82 width 5
        db 0x26,0x49,0x49,0x49,0x32,0x00,0x00,0x05   ; glyph  83 width 5
        db 0x01,0x01,0x7f,0x01,0x01,0x00,0x00,0x05   ; glyph  84 width 5
        db 0x3f,0x40,0x40,0x40,0x3f,0x00,0x00,0x05   ; glyph  85 width 5
        db 0x1f,0x20,0x40,0x20,0x1f,0x00,0x00,0x05   ; glyph  86 width 5
        db 0x3f,0x40,0x38,0x40,0x3f,0x00,0x00,0x05   ; glyph  87 width 5
        db 0x63,0x14,0x08,0x14,0x63,0x00,0x00,0x05   ; glyph  88 width 5
        db 0x07,0x08,0x70,0x08,0x07,0x00,0x00,0x05   ; glyph  89 width 5
        db 0x61,0x51,0x49,0x45,0x43,0x00,0x00,0x05   ; glyph  90 width 5
        db 0x7f,0x41,0x41,0x00,0x00,0x00,0x00,0x03   ; glyph  91 width 3
        db 0x02,0x04,0x08,0x10,0x20,0x00,0x00,0x05   ; glyph  92 width 5
        db 0x41,0x41,0x7f,0x00,0x00,0x00,0x00,0x03   ; glyph  93 width 3
        db 0x04,0x02,0x7f,0x02,0x04,0x00,0x00,0x05   ; glyph  94 width 5
        db 0x1c,0x22,0x41,0x4f,0x51,0x22,0x1c,0x07   ; glyph  95 width 7
        db 0x10,0x20,0x7f,0x20,0x10,0x00,0x00,0x05   ; glyph  96 width 5
        db 0x20,0x54,0x54,0x54,0x78,0x00,0x00,0x05   ; glyph  97 width 5
        db 0x7f,0x44,0x44,0x44,0x38,0x00,0x00,0x05   ; glyph  98 width 5
        db 0x38,0x44,0x44,0x44,0x44,0x00,0x00,0x05   ; glyph  99 width 5
        db 0x38,0x44,0x44,0x44,0x7f,0x00,0x00,0x05   ; glyph 100 width 5
        db 0x38,0x54,0x54,0x54,0x58,0x00,0x00,0x05   ; glyph 101 width 5
        db 0x08,0x7e,0x09,0x02,0x00,0x00,0x00,0x04   ; glyph 102 width 4
        db 0x4c,0x52,0x52,0x52,0x3c,0x00,0x00,0x05   ; glyph 103 width 5
        db 0x7f,0x04,0x04,0x04,0x78,0x00,0x00,0x05   ; glyph 104 width 5
        db 0x7a,0x00,0x00,0x00,0x00,0x00,0x00,0x01   ; glyph 105 width 1
        db 0x40,0x40,0x3d,0x00,0x00,0x00,0x00,0x03   ; glyph 106 width 3
        db 0x7f,0x10,0x28,0x44,0x00,0x00,0x00,0x04   ; glyph 107 width 4
        db 0x7f,0x00,0x00,0x00,0x00,0x00,0x00,0x01   ; glyph 108 width 1
        db 0x78,0x04,0x18,0x04,0x78,0x00,0x00,0x05   ; glyph 109 width 5
        db 0x7c,0x08,0x04,0x04,0x78,0x00,0x00,0x05   ; glyph 110 width 5
        db 0x38,0x44,0x44,0x44,0x38,0x00,0x00,0x05   ; glyph 111 width 5
        db 0x7e,0x12,0x12,0x0c,0x00,0x00,0x00,0x04   ; glyph 112 width 4
        db 0x0c,0x12,0x12,0x7e,0x00,0x00,0x00,0x04   ; glyph 113 width 4
        db 0x7c,0x08,0x04,0x04,0x08,0x00,0x00,0x05   ; glyph 114 width 5
        db 0x48,0x54,0x54,0x54,0x24,0x00,0x00,0x05   ; glyph 115 width 5
        db 0x04,0x3f,0x44,0x00,0x00,0x00,0x00,0x03   ; glyph 116 width 3
        db 0x3c,0x40,0x40,0x40,0x3c,0x00,0x00,0x05   ; glyph 117 width 5
        db 0x0c,0x30,0x40,0x30,0x0c,0x00,0x00,0x05   ; glyph 118 width 5
        db 0x3c,0x40,0x30,0x40,0x3c,0x00,0x00,0x05   ; glyph 119 width 5
        db 0x44,0x28,0x10,0x28,0x44,0x00,0x00,0x05   ; glyph 120 width 5
        db 0x4c,0x50,0x50,0x3c,0x00,0x00,0x00,0x04   ; glyph 121 width 4
        db 0x44,0x64,0x54,0x4c,0x44,0x00,0x00,0x05   ; glyph 122 width 5
        db 0x08,0x36,0x41,0x00,0x00,0x00,0x00,0x03   ; glyph 123 width 3
        db 0x08,0x08,0x00,0x08,0x08,0x00,0x00,0x05   ; glyph 124 width 5
        db 0x41,0x36,0x08,0x00,0x00,0x00,0x00,0x03   ; glyph 125 width 3
        db 0x08,0x04,0x08,0x04,0x00,0x00,0x00,0x04   ; glyph 126 width 4
        db 0x08,0x08,0x08,0x08,0x2a,0x1c,0x08,0x07   ; glyph 127 width 7

; ---- CHAR_FLAGS: per byte value: bit 0 set = invalid in the store (store_fix_bad_bytes
;      turns it into ?)
CHAR_FLAGS:
        db 0x07,0x07,0x07,0x00,0x07,0x07,0x00,0x00,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x00
        db 0x00,0x07,0x07,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x00,0x00,0x07
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x00
        db 0x07,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x00
        db 0x07,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07
        db 0x00,0x07,0x07,0x00,0x07,0x07,0x07,0x00,0x07,0x07,0x07,0x07,0x00,0x00,0x07,0x00
        db 0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07

; ---- CHARSET_LOWER: keypad code 00-3F -> character, SHIFT off, caps off (UPPER: caps on;
;      UPPER2/LOWER2: SHIFT on)
CHARSET_LOWER:
        db "kf",0x12,"pa",0x0e,0x11,0x1e             ; 00-07
        db " ",0x7f,")%zwyt"                         ; 08-0f
        db "ni",0x1f,"hd",0x09,0x13,0x07             ; 10-17
        db "0",0x1d,"2586k",0x00                     ; 18-1f
        db "lgvmq",0x04,0x10,0x14                    ; 20-27
        db ".",0x1c,"(*+9xs"                         ; 28-2f
        db "ojbce",0x0d,0x16,0x15                    ; 30-37
        db 0x08,0x0a,"1473ur"                        ; 38-3f

CHARSET_UPPER:
        db "KF",0x12,"PA",0x0e,0x11,0x1e             ; 00-07
        db " ",0x7f,")%ZWYT"                         ; 08-0f
        db "NI",0x1f,"HD",0x09,0x13,0x07             ; 10-17
        db "0",0x1d,"2586K",0x00                     ; 18-1f
        db "LGVMQ",0x04,0x10,0x14                    ; 20-27
        db ".",0x1c,"(*+9XS"                         ; 28-2f
        db "OJBCE",0x0d,0x16,0x15                    ; 30-37
        db 0x08,0x0a,"1473UR"                        ; 38-3f

CHARSET_UPPER2:
        db "KF",0x06,"PA",0x0e,0x17,"_"              ; 00-07
        db " ",0x7f,"&'ZWYT"                         ; 08-0f
        db "NI",0x0f,"HD",0x02,0x1b,0x1a             ; 10-17
        db "0",0x1d,"2586K",0x00                     ; 18-1f
        db "LGVMQ",0x04,0x19,0x18                    ; 20-27
        db ":",0x1c,"$#-9XS"                         ; 28-2f
        db "OJBCE",0x0d,0x16,0x15                    ; 30-37
        db 0x0b,0x0c,"1473UR"                        ; 38-3f

CHARSET_LOWER2:
        db "kf",0x06,"pa",0x0e,0x17,"_"              ; 00-07
        db " ",0x7f,"&'zwyt"                         ; 08-0f
        db "ni",0x0f,"hd",0x02,0x1b,0x1a             ; 10-17
        db "0",0x1d,"2586k",0x00                     ; 18-1f
        db "lgvmq",0x04,0x19,0x18                    ; 20-27
        db ":",0x1c,"$#-9xs"                         ; 28-2f
        db "ojbce",0x0d,0x16,0x15                    ; 30-37
        db 0x0b,0x0c,"1473ur"                        ; 38-3f

; ---- DEMO_MARKER: the DA byte before DEMO_MESSAGE: chan_select points the demo channel here
DEMO_MARKER:
        db 0xda

; ---- DEMO_MESSAGE: channel 10: 'THIS IS A DEMONSTRATION OF THE NEW COLOR CELLS DYNAMIC
;      DISPLAY SYSTEM. SIX EXCITING COLORS - ... TIME _ BOLD ITALIC BIG FLASH BEEP ... JUMP
;      WIPE UP DOWN BACK'
DEMO_MESSAGE:
        db 0x83,"/ ",0x8f,"/ ",0x8c,"/ ",0x83,"/ ",0x8f,"/ ",0x8c,"/ "
        db 0x8f," THIS IS A DEMONSTRATION OF THE               ",0x19,"NEW",0x18
        db "    ",0x90,0x13,0x12,0x83,"C",0x87,"O",0x8c,"L",0x8d,"O",0x8f
        db "R ",0x8d,0x92," CELLS ",0x90,"             ",0x11,0x1a,"DYNAMIC"
        db 0x1b,"DISPLAY",0x19,"SYSTEM.",0x18,0x90,0x11,0x8c,"      SIX "
        db 0x90,0x8d," ",0x14,"EXCITING ",0x90,0x83,0x11," COLORS -    "
        db 0x90,0x10,0x83,0xa8,0x87,0xa8,0x8c,0xa8,0x8d,0xa8,0x8f,0xa8
        db 0x80,0xa8,0x8f,0xa8,0x8d,0xa8,0x8c,0xa8,0x87,0xa8,0x83,0xa8
        db 0x80,0xa8,0x11,0x83,0x90,"        TIME _        ",0x90,0x12,0x92
        db 0x87," BOLD ",0x90,"   ",0x13,0x91,0x8f," ITALIC ",0x90,"   "
        db 0x11,0x8d,0x10,"BIG",0x90,0x11,"   ",0x90,0x83,0x12," ",0x14
        db "FLASH ",0x90,0x11,"            ",0x07," BEEP ",0x07,0x12,0x91
        db " ",0x87,0xa1,0xa1,0xa1,"    ",0x90,0x83,0xa2," ",0x87,0xa3
        db " ",0x8b,0xa4," ",0x8c,0xa5," ",0x8f,0xab," ",0x83,0xad,"    "
        db 0x91," ",0x87,0xa0,0xa0,0xa0,"    ",0x90,0x11,"              "
        db 0x19,"JUMP",0x1a,"WIPE UP",0x1b,"DOWN",0x0f,"BACK"

; ---- DEMO_MESSAGE_END: the demo's 03
DEMO_MESSAGE_END:
        db 0x03

        ds 0x4000-$,0xff
