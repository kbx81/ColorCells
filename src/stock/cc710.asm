; ============================================================================
;  Color Cells CC710 LED sign - firmware source, reconstructed from EPROM
;  Assemble:  sjasmplus cc710.asm   (produces cc710.bin, 16384 bytes)
;  Byte-identical to the original EPROM dump:
;      md5 f346d39e5aa7b49709a717c85d7c7e11
;  FROZEN. Annotations may be added; code must not change.
;
;  The firmware is copyright its original owner (Color Cells / Innovative Sign
;  Technology, and successors); reconstructed for preservation and
;  interoperability. The labels and comments are MIT, see ../../LICENSE.
;
;  CC710: the ten-channel model on the CC784-3A board (4 MHz, 1302 Hz ISR, keypad
;  header instead of a DB9, 2 KB RAM, 7x59 panel driven as 60 columns). Same code
;  base as the NET: labels shared with the NIR source mean the same routine. The
;  firmware picks keypad, serial-terminal or packet mode at boot (store_init,
;  mode_test). See firmware.md section 15.
; ============================================================================
        DEVICE NONE
        OUTPUT "cc710.bin"

FRAMEBUF             equ 0x4040
FRAMEBUF_SIZE        equ 0x78   ; column ring: 60 visible + the glyph being written
FRAMEBUF_ROW1        equ FRAMEBUF+0x3c
FRAMEBUF_TINY        equ FRAMEBUF+0xab   ; the NIR's TINY line offset; unused, this ROM has no TINY buffer
; ---- variables follow the ring; their layout is baked into INIT_DATA, so only
;      the base moves
RAM_VARS             equ FRAMEBUF+FRAMEBUF_SIZE
FB_COLPTR            equ RAM_VARS+0x000   ; frame-buffer write pointer (next glyph column)
FB_COL               equ RAM_VARS+0x003   ; scroll position: the column the output window is moving toward
BGRND_PENDING        equ RAM_VARS+0x008   ; editor: BGRND key pressed, next key is the color digit
TXBUF                equ RAM_VARS+0x009   ; reply frames, and the effect staging frame (60 columns)
STAGE_PTR            equ RAM_VARS+0x045   ; next free column in TXBUF while an effect stages text
STAGE_OFFSET         equ RAM_VARS+0x048   ; centering offset of the staged text (free columns / 2)
ROW_PORT             equ RAM_VARS+0x04a   ; port group for the row data: 40 first pass, 48 second
BEEP_TICKS           equ RAM_VARS+0x04b   ; beeper on while non-zero (port bit 5); beep_start loads BEEP_LEN
CLK_H10              equ RAM_VARS+0x04d
CLK_H1               equ RAM_VARS+0x04e
CLK_SEC              equ RAM_VARS+0x051
CLK_PM               equ RAM_VARS+0x052
CLK_RUN              equ RAM_VARS+0x053
GLYPH_WIDTH          equ RAM_VARS+0x054
GLYPH_PTR            equ RAM_VARS+0x055
CUR_COLOR            equ RAM_VARS+0x059
SCROLLING            equ RAM_VARS+0x05a   ; FF while the output window is catching up with FB_COLPTR
CUR_CHAR             equ RAM_VARS+0x05b
FB_OUT_PTR           equ RAM_VARS+0x05d   ; first column sent to the panel (start of the output window)
DISP_ON              equ RAM_VARS+0x05f   ; 0 suppresses row output (effects rewrite FRAMEBUF meanwhile)
MENU_ACTIVE          equ RAM_VARS+0x063
INS_PTR              equ RAM_VARS+0x064
MAGIC_MODE           equ RAM_VARS+0x066   ; FF from MAGIC (1F) until a font or color attribute ends it
COL_COUNT            equ RAM_VARS+0x068   ; 60 while an effect stages text, the columns used once flushed; 0 = no staging (LEFT)
ROW_COLOR            equ RAM_VARS+0x06e   ; color byte sent ahead of each row
INPUT_MODE           equ RAM_VARS+0x06f   ; boot probe result: 00 keypad, FF serial terminal (keys over the line), FE packet protocol
EDIT_KEY             equ RAM_VARS+0x071   ; key/character the editor is processing (0 = none)
RX_BYTE              equ RAM_VARS+0x074
KEY_TIMER            equ RAM_VARS+0x076   ; counts down each frame (tick6_exit): keypad debounce pacing in editor_getkey and editor_exit
CTRL_LATCH_SHADOW    equ RAM_VARS+0x079
FB_OUT_LEN           equ RAM_VARS+0x07c   ; bytes to send from FB_OUT_PTR before wrapping to FRAMEBUF
FB_EXTRA_LEN         equ RAM_VARS+0x07e   ; bytes to send from FRAMEBUF after the wrap
STORE_END            equ RAM_VARS+0x080
EFFECT_ID            equ RAM_VARS+0x086   ; 0 LEFT, 1 PAUSE, 2 UP, 3 DOWN, 4 RIGHT
EFFECT_VECTOR        equ RAM_VARS+0x087
MENU_TEXT_PTR        equ RAM_VARS+0x089
ROW_INDEX            equ RAM_VARS+0x091
RX_BITMASK           equ RAM_VARS+0x092
RX_SHIFT             equ RAM_VARS+0x094
RX_TICKS             equ RAM_VARS+0x095
RX_FIFO              equ RAM_VARS+0x096
RX_COUNT             equ RAM_VARS+0x09e
RX_TIMING_PTR        equ RAM_VARS+0x09f
RX_STATE             equ RAM_VARS+0x0a3
CHAN_LOCK            equ RAM_VARS+0x0af
SEQ_LIST             equ RAM_VARS+0x0b0
SEQ_PTR              equ RAM_VARS+0x0d0
SEQ_ALL_EMPTY        equ RAM_VARS+0x0d2   ; 10 = every listed channel is empty, play the demo
FONT_MODE            equ RAM_VARS+0x136   ; bit 1 BOLD, bit 2 ITALIC, bit 3 BIG
TINY_MODE            equ RAM_VARS+0x137   ; FF = menu text: glyphs drawn without bold/big/italic
NMI_COUNT            equ RAM_VARS+0x139
STORE_TMP            equ RAM_VARS+0x13b
MOVE_DST             equ RAM_VARS+0x13d
MOVE_SRC             equ RAM_VARS+0x13f
STORE_CURSOR         equ RAM_VARS+0x143
TX_BITIDX            equ RAM_VARS+0x145
TX_BITMASK           equ RAM_VARS+0x146
TX_PENDING           equ RAM_VARS+0x147
TX_TICKS             equ RAM_VARS+0x148
TX_SHIFT             equ RAM_VARS+0x149
TX_STATUS            equ RAM_VARS+0x14a
TX_TIMING_PTR        equ RAM_VARS+0x14b
ROW_OUT_PENDING      equ RAM_VARS+0x14e   ; FF = the current row still has to be sent
NEXT_CHAN            equ RAM_VARS+0x150   ; channel to show first after the editor (FF = none)
MAGIC_LAST_CHAR      equ RAM_VARS+0x169   ; magic mode: last char of the current word (punctuation check)
RND_SEED             equ RAM_VARS+0x16b
RND_VAL              equ RAM_VARS+0x16c   ; magic mode: words until the next color change
MY_ADDRESS           equ RAM_VARS+0x171
MY_ADDRESS_INV       equ RAM_VARS+0x172   ; the probe byte the address was derived from (complement of MY_ADDRESS)
BLANK_TIMER          equ RAM_VARS+0x174
GLYPH_PTR_ORIG       equ RAM_VARS+0x176   ; glyph address before bold/italic/big copies
STORE_LIMIT          equ RAM_VARS+0x17a
STORE_SIZE           equ RAM_VARS+0x17c
MSG_STORE            equ RAM_VARS+0x184
PKT_READY            equ 0x46f0
PKT_BUF              equ 0x46f1
PKT_STATE            equ 0x47f1
PKT_CKSUM            equ 0x47f2
PKT_FLAG             equ 0x47f3
PKT_LEN              equ 0x47f4
PKT_VECTOR           equ 0x47f5
PKT_ADDR             equ 0x47f7
PKT_PTR              equ 0x47f8
PKT_REMAIN           equ 0x47fa
CTRL_LATCH           equ 0x8000

PORT_40_OUT          equ 0x40
PORT_ROW0            equ 0x48
PORT_STROBE          equ 0x80
PORT_IN              equ 0xc0

; ---- RAM locations named from their use. The ones marked "never read"
;      are written by the firmware but influence nothing.
MENU_MSG_PTR         equ RAM_VARS+0x057   ; message the editor is showing (set with MENU_MSG_FLAG)
TEST_MODE            equ RAM_VARS+0x05c   ; FF = TEST_MESSAGE is being displayed straight from ROM
CLK_RENDER_STEP      equ RAM_VARS+0x060   ; clock (5F) render step 0..8
CLK_RENDER_PTR       equ RAM_VARS+0x061   ; clock render: next CLK_ digit to emit
WINDOW_COLOR         equ RAM_VARS+0x067   ; last color byte at the output window start (bit 4 = flash)
FRAME_COUNT          equ RAM_VARS+0x069   ; frames since LATCH_BIT7 last toggled (mod 13)
FLASH_BIT            equ RAM_VARS+0x06a   ; 0x10 while the current word flashes; OR-ed into color bytes
LATCH_BIT7           equ RAM_VARS+0x06b   ; 00/80 toggled every 13 frames, OR-ed into CTRL_LATCH bit 7
COLOR_PENDING        equ RAM_VARS+0x06c   ; editor: COLOR key pressed, next key is the color digit
GRAPH_PENDING        equ RAM_VARS+0x06d   ; editor: GRAPH key pressed, next key selects A0-AF
MENU_MSG_FLAG        equ RAM_VARS+0x070   ; FF = editor has a message to display
PREV_KEY             equ RAM_VARS+0x072   ; editor key history (written, never read)
PREV_KEY2            equ RAM_VARS+0x073   ; editor key history (written, never read)
IR_KEY_CHAR          equ RAM_VARS+0x075   ; character decoded from the keypad code via the CHARSET_ tables (serial: the raw byte)
STORE_WRAPPED        equ RAM_VARS+0x082   ; FF when the editor cursor hit STORE_LIMIT (written, never read)
SHIFT_LABEL          equ RAM_VARS+0x08d   ; FF = redraw shows the SHIFT indicator
FLUSH_PENDING        equ RAM_VARS+0x08e   ; FF = staged text must be shown before the next effect runs
PROG_MSG_FORCE       equ RAM_VARS+0x08f   ; FF while the PROG? prompt waits for its channel key
FRAME_DELAY          equ RAM_VARS+0x090   ; frames to hold before the next column step (1, 3 or 0x50)
REDRAW_PTR           equ RAM_VARS+0x0a1   ; editor redraw: byte being rendered
CHAN_STATE           equ RAM_VARS+0x0a5   ; 11 bytes cleared by clear_chan_lock; only CHAN_LOCK (last) is read
GLYPH_BUF            equ RAM_VARS+0x0d3   ; working copy of the glyph (bold/plain), 32 bytes
GLYPH_BUF_ITALIC     equ RAM_VARS+0x0f3   ; sheared copy for ITALIC, 32 bytes
GLYPH_BUF_BIG        equ RAM_VARS+0x113   ; widened copy for BIG, 32 bytes
SEQ_MENU_ACTIVE      equ RAM_VARS+0x133   ; F0/FF while the SEQ? dialogue runs
SHIFT_STATE          equ RAM_VARS+0x134   ; SHIFT latch, toggled by keypad code 19 (getkey_check_shift)
PREV_SPACE           equ RAM_VARS+0x135   ; 1 = previous char was a space (two in a row reset the background)
FORCE_BOLD           equ RAM_VARS+0x138   ; editor redraw: FF = effect text is drawn bold (unless THIN)
REDRAW_FROM          equ RAM_VARS+0x141   ; editor redraw: first byte actually displayed (cursor-15, >= INS_PTR)
CAPS_LOCK            equ RAM_VARS+0x14d
SEQ_SET              equ RAM_VARS+0x14f   ; FF = sequence set by hand; do not auto-add the edited channel
MAGIC_COLOR_IDX      equ RAM_VARS+0x151   ; index into MAGIC_COLOR_CYCLE
STORE_BAD_COUNT      equ RAM_VARS+0x152   ; bytes replaced by ? in store_fix_bad_bytes (never read)
DRAW_BUF             equ RAM_VARS+0x153   ; 16 packed hex columns of a DRAW graphic
NEW_MSG_CHAN         equ RAM_VARS+0x16f   ; channel chosen for a new MAGIC message
MAGIC_FX_PREV        equ RAM_VARS+0x166   ; FF = last byte was a movement attribute (magic mode)
MAGIC_FLASH_WORD     equ RAM_VARS+0x167   ; '$' = flash the word that starts with $ (magic mode)
EDITOR_FIRST_KEY     equ RAM_VARS+0x168   ; FF until the first key in the editor is processed
MAGIC_WORD_COUNT     equ RAM_VARS+0x16a   ; words since the last color change (magic mode)
MAGIC_MSG_CHAN       equ RAM_VARS+0x16d   ; channel to announce as MAGIC MSG nn on redraw (0 = none)
REDRAW_MAGIC         equ RAM_VARS+0x16e   ; editor redraw: MAGIC seen, font resets at each word
FUNC_PENDING         equ RAM_VARS+0x170   ; editor: FUNC (B7) pressed, next key picks the second function
SCROLL_SPEED         equ RAM_VARS+0x173   ; 0..7 from F0-F7; blank ticks inserted after every frame
SPEED_PENDING        equ RAM_VARS+0x175   ; editor: SPEED key pressed, next key is the digit
THIN_MODE            equ RAM_VARS+0x178   ; non-zero after THIN (B9): no bold in effects
KEY_ECHO_TX          equ RAM_VARS+0x179   ; non-zero = echo accepted keys on serial TX
STORE_TEXT_LIMIT     equ RAM_VARS+0x17e   ; free text bytes; scan bound for store_repair
STORE_WARN_LIMIT     equ RAM_VARS+0x180   ; STORE_END here trips the ' 100 LEFT ' warning

; ---- Wire protocol bytes (protocol.md) ---------------------------------
FRAME_START          equ 0xb1
ADDR_BROADCAST       equ 0x2a   ; '*': processed, never answered
REPLY_ACK            equ 0x06
REPLY_NAK            equ 0x15
CMD_SPEED            equ 0x02   ; 02 n
CMD_CLEAR_ALL        equ 0x03
CMD_SEQUENCE         equ 0x04   ; 04 d d ... (D = demo)
CMD_CHANNEL          equ 0x09   ; 09 d
CMD_END              equ 0x0d
CMD_DELETE_TEXT      equ 0x0e
CMD_FORE_IDX         equ 0x15   ; 15 n
CMD_BACK_IDX         equ 0x16   ; 16 n
CMD_SET_TIME         equ 0x17   ; 17 hhmm a
CMD_COLOR_A0         equ 0x1e   ; 1E n
CMD_APPEND           equ 0xb3
CMD_QUERY            equ 0xb4   ; B4 c
QUERY_ROMID          equ '0'
QUERY_MEMORY         equ '1'
QUERY_NOP            equ '2'
QUERY_DUMP           equ '3'

; ---- Tuning and geometry (names shared with src/patched) ----------------------
FLASH_HALF_PERIOD    equ 13   ; frames per half period of CTRL_LATCH bit 7, the FLASH blink clock (2.4 Hz)
FRAME_COLS           equ 86   ; the NIR's columns per row; here only shift_chain_clear's count (this ROM sends 60)
HOLD_FRAMES          equ 80   ; frames a HALT, PAUSE, wipe or editor message holds the panel (~1.3 s)
BEEP_LEN             equ 150   ; beeper on for this many tick6 periods (~115 ms)

; ---- Message store format ------------------------------------------------------
MARK_LO              equ 0xd0   ; channel markers are one byte, D0+n (D0-D9)
MARK_HI              equ 0xda   ; the last marker byte value; alone, DA ends the store
TEXT_END             equ 0x03   ; ends a channel's text
CHANNELS             equ 100   ; the NIR's count (this ROM has ten, 0-9); here only the 100 in DEC_TABLE
CHAN_DEMO            equ 100   ; the NIR's value, unused: the demo pseudo-channel is 10 here
SEQ_LIST_LEN         equ 104   ; the NIR's value, unused: SEQ_LIST is 32 bytes here

; ---- Message attribute bytes (the sign's own names, firmware.md §8) --------
ATTR_BIG             equ 0x10
ATTR_NORM            equ 0x11
ATTR_BOLD            equ 0x12
ATTR_ITALIC          equ 0x13
ATTR_FLASH           equ 0x14
ATTR_COLOR           equ 0x15   ; as an editor key; the packet command is CMD_FORE_IDX
ATTR_BGRND           equ 0x16   ; as an editor key; the packet command is CMD_BACK_IDX
ATTR_LEFT            equ 0x18   ; plain scroll
ATTR_PAUSE           equ 0x19
ATTR_UP              equ 0x1a
ATTR_DOWN            equ 0x1b
KEY_CASE             equ 0x1c   ; UPPER/LOWER key
KEY_SHIFT            equ 0x1d
ATTR_GRAPH           equ 0x1e
ATTR_MAGIC           equ 0x1f
ATTR_TIME            equ 0x5f
ATTR_REM             equ 0xb0   ; remark: skipped up to the next B0
KEY_EURO             equ 0xb6
KEY_FUNC             equ 0xb7
KEY_DEL              equ 0x7f
ATTR_DRAW            equ 0xb8
ATTR_THIN            equ 0xb9
ATTR_WAIT            equ 0xba
ATTR_HOLD            equ 0xbb
ATTR_RAINBOW         equ 0xbc
ATTR_MAGIC_OFF       equ 0xbd
ATTR_TINY            equ 0xbe
COLOR_BASE           equ 0x80   ; 80-8F foreground: bits 0-1 green, 2-3 red intensity
COLOR_DEFAULT        equ 0x8f   ; yellow, full
COLOR_FLASH          equ 0x10   ; the FLASH bit in a frame-buffer color byte
BGRND_BASE           equ 0x90   ; 90-93 background
GRAPH_BASE           equ 0xa0   ; A0-AF built-in graphics
SPEED_BASE           equ 0xf0   ; F0-F7 scroll speed
LATCH_TX             equ 0x10   ; CTRL_LATCH bit 4: serial TX
LATCH_BLINK          equ 0x80   ; CTRL_LATCH bit 7: the FLASH blink clock

        org 0x0000

; ---- RESET: cold start: set SP, run init routines, EI, jump to main loop
RESET:
        LD SP,0x403f
        CALL init_vars
        CALL store_init
        CALL boot_clear_check

; ---- restart_display: re-init the renderer, repair the store, rebuild the sequence, EI
;      and enter main_entry. RESET falls into it; the editor and pkt_process_done jump
;      here (the NIR's restart_display starts here too)
restart_display:
        CALL init_render

; ---- restart_no_render: tail of restart_display without init_render; editor_redraw's LD
;      DE,0x000F is the number 15, not this address
restart_no_render:
        CALL store_repair
        CALL init_sequence
        EI
        JP main_entry

        ds 0x001f-$,0xff

; ---- FILL_001F: 0xFF fill up to the IM 1 vector (25 bytes, not code). The one reference,
;      LD BC,ATTR_MAGIC in exit_seq_insert, is the LDDR count 31 = SEQ_LIST length - 1
FILL_001F:

        ds 0x0038-$,0xff

; ---- INT_VECTOR: IM1 interrupt entry (periodic timer, ~1300 Hz)
INT_VECTOR:
        CALL int_timer
        EI
        RETI

        ds 0x0050-$,0xff

; ---- ROM_ID: 3-byte model '710' here and 3-byte revision '09l' at 0x0060; query_0_romid
;      sends the two together as a 6-byte reply ('71009l'). The NIR/NET keep one 16-byte
;      string at 0x0048 instead
ROM_ID:
        db "710",0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff

; ---- ROM_REV: second half of the firmware ID, '09l' (rev 09, build l); copied after
;      ROM_ID by query_0_romid
ROM_REV:
        db 0x30,0x39,0x6c,0xff,0xff,0xff

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

; ---- main_entry: entry after restart_display / fx_end_of_channel. Only packet mode
;      (INPUT_MODE = FE) looks at PKT_READY; keypad and terminal modes go straight to the
;      channel start
main_entry:
        LD A,(INPUT_MODE)
        CP 0xfe
        JR nz,main_start_channel

; ---- main_loop: Main loop: if PKT_READY process packet, else init/render/effect step, then loop.
;      The PKT_READY test runs ONCE on entry - render_loop below never falls back
;      to 0x007A. Re-entry only happens via fx_end_of_channel (0x0C63) at the
;      end of a display cycle, or the BA wait-for-key spin at 0x07BA. That is
;      why NETCC sets PKT_FLAG=0x80: deferred packets wait for the current
;      channel to finish, which can be many seconds.
main_loop:
        LD A,(PKT_READY)
        AND A
        JP nz,pkt_process

; ---- main_start_channel: init_render, pick the next channel, then render_loop
main_start_channel:
        CALL init_render
        CALL seq_next_channel

render_loop:
        CALL render_next_char
        CALL effect_step
        LD A,(MAGIC_MODE)
        JR nz,render_loop
        XOR A
        LD (COL_COUNT),A

; ---- render_reset_effect: NOT a string: code. After effect_step returns with Z, drop
;      back to the plain LEFT crawl (EFFECT_ID = 0, fxv_none) and loop. The JP render_loop
;      after the JR is dead. its one data use, LD HL,0x0096 in fx_beep, is BEEP_LEN=150
render_reset_effect:
        LD HL,fxv_none
        LD (EFFECT_ID),A
        LD (EFFECT_VECTOR),HL
        JR render_loop
        db 0xc3,0x87,0x00

; ---- int_timer: timer ISR body, called from INT_VECTOR at 1302 Hz (4 MHz / 3072). If
;      (IX)=AA and (IY)=55, the sentinel mode_test points IX/IY at around its HALT, return
;      at once; otherwise run the whole tick service (the NIR's tick6_service, here done
;      on every interrupt, as in the NET)
int_timer:
        PUSH AF
        LD A,(IX+0)
        CP 0xaa
        JR nz,tick6_service
        LD A,(IY+0)
        CP 0x55
        JR nz,tick6_service
        POP AF
        EI
        RETI

; ---- tick6_service: per-interrupt work in the alternate register set: serial bit engines
;      (skipped in keypad mode, INPUT_MODE = 0), beeper countdown, row refresh / frame
;      step, then rx_consume. No GEN_COUNTDOWN here (no IR)
tick6_service:
        POP AF
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

; ---- row_out_send: DISP_ON set: send ROW_COLOR then the 60-column output window to port
;      ROW_PORT | (6 - ROW_INDEX), bit 5 set while beeping. The second OTIR (row_out_wrap)
;      is the part of the window that wrapped round the 120-byte FRAMEBUF ring, not a
;      second panel segment
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
        LD DE,0x003c
        CALL fb_ptr_add
        LD DE,(FB_COLPTR)
        OR A
        SBC HL,DE
        JR z,frame_scroll_stop
        LD HL,(FB_COL)
        CALL fb_ptr_inc
        LD (FB_COL),HL
        LD DE,0x003c
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
        LD DE,0x003c
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
        LD HL,0x003c
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

; ---- rx_consume: input, once per frame. Keypad mode (INPUT_MODE = 0): scan the keypad
;      into RX_BYTE and treat a key code like a received byte. Serial modes: pop RX_FIFO;
;      packet mode (FE) feeds the packet parser, terminal mode (FF) treats the byte as a
;      key code (rx_fifo_get has translated it)
rx_consume:
        LD A,(INPUT_MODE)
        AND A
        JR nz,rx_serial_byte
        CALL keypad_scan
        AND A
        JR z,tick6_exit
        JP rx_not_start

; ---- rx_serial_byte: serial modes: pop the FIFO; nothing -> tick6_exit. Packet mode goes
;      on to the parser, terminal mode to rx_not_start
rx_serial_byte:
        CALL rx_fifo_get
        JP c,tick6_exit
        LD A,(INPUT_MODE)
        CP 0xfe
        JR nz,rx_not_start

rx_have_byte:
        LD A,(PKT_STATE)
        AND A
        JR z,rx_idle_byte
        CALL pkt_feed_byte
        JP tick6_exit

rx_idle_byte:
        LD A,(RX_BYTE)
        CP FRAME_START
        JR nz,tick6_exit
        LD A,(PKT_READY)
        AND A
        JR nz,tick6_exit
        LD A,0xff
        LD (PKT_STATE),A
        LD HL,pkt_st_addr
        LD (PKT_VECTOR),HL
        JP tick6_exit

; ---- rx_not_start: a key code (keypad or terminal mode) outside the editor: 35 =
;      STOP/START (serial 01 is mapped to it) opens the editor with echo, 7E opens the
;      address-gated menu_enter; anything else is dropped
rx_not_start:
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,tick6_exit
        LD A,(RX_BYTE)
        CP 0x35
        JP z,key_handler
        CP 0x7e
        JP z,menu_enter

; ---- tick6_exit: KEY_TIMER (the NIR's dead SPARE_TIMER) counts down here;
;      editor_getkey and editor_exit set it to 2 to pace their keypad samples
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
        JP nz,pkt_process_end
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

; ---- SEQ_DEFAULT: default SEQ_LIST image: channels 0-9 then FF (32 bytes), followed by
;      the 0x32 end sentinel seq_reset_default stops on
SEQ_DEFAULT:
        db 0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0xff,0xff,0xff,0xff,0xff,0xff
        db 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
        db 0x32

; ---- seq_next_channel: pick the channel to display next: TEST_MODE -> the ROM
;      TEST_MESSAGE; NEXT_CHAN (< 11) once; else the next SEQ_LIST entry, demo (10) when
;      SEQ_ALL_EMPTY. A list entry >= 11 resets the sign (RESET via pkt_process_end). No
;      attribute skipping: the cursor lands on the first byte of the channel
seq_next_channel:
        LD A,(TEST_MODE)
        INC A
        JR z,seq_test_message
        LD A,(NEXT_CHAN)
        CP 11
        JP nc,seq_from_list
        LD E,A
        LD A,0xff
        LD (NEXT_CHAN),A
        LD A,E
        JP seq_open_channel

seq_from_list:
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
        JP nc,pkt_process_end
        LD E,A
        INC HL
        LD (SEQ_PTR),HL

; ---- seq_open_channel: A = channel 0-10: chan_select; empty (03) -> seq_chan_empty; else
;      STORE_CURSOR = its text, CHAN_STATE[E] = FF (E = 10 sets CHAN_LOCK)
seq_open_channel:
        CALL chan_select
        OR A
        JP nz,pkt_process_end
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

seq_test_message:
        LD HL,TEST_MESSAGE
        LD (STORE_CURSOR),HL
        CALL clear_chan_lock
        RET

; ---- clear_chan_lock: zero CHAN_STATE, 11 bytes ending in CHAN_LOCK
clear_chan_lock:
        LD HL,CHAN_STATE
        LD B,11
        LD A,0

clr_lock_loop:
        LD (HL),A
        INC HL
        DJNZ clr_lock_loop
        RET

; ---- chan_select: A & 15 = channel 0-10. 10 -> HL = DEMO_MESSAGE. Else CPIR for the
;      ONE-byte marker D0+n in MSG_STORE (10 channels, single-byte markers, unlike the
;      NIR's D0+tens D0+units pairs); HL -> first text byte. A = 0 found, FF not found
chan_select:
        AND 15
        CP 10
        JR nz,chan_scan
        LD HL,DEMO_MESSAGE
        JP chan_ok

chan_scan:
        OR 0xd0
        LD HL,MSG_STORE
        LD BC,(STORE_SIZE)
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
        LD BC,(STORE_TEXT_LIMIT)

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

; ---- repair_scan: find the next Dx byte within STORE_TEXT_LIMIT bytes
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
        LD BC,(STORE_SIZE)
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
        LD BC,(STORE_SIZE)

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

; ---- store_add_ends: from MSG_STORE+1, put 03 in front of every Dx byte over STORE_SIZE
;      bytes
store_add_ends:
        LD IX,0x423d
        LD BC,(STORE_SIZE)

addends_loop:
        LD A,(IX+0)
        AND 0xf0
        CP 0xd0
        JR nz,addends_next
        LD (IX-1),TEXT_END

; ---- addends_next: loop step. LD HL,addends_next in mode_store_address is the number 0x049F
;      (STORE_TEXT_LIMIT in packet mode), not a reference to this code
addends_next:
        INC IX
        DEC BC
        LD A,C
        OR B
        JR nz,addends_loop
        RET

; ---- init_vars: Zero the editor/magic/draw flags, NEXT_CHAN = FF, seed the magic RNG
;      from NMI_COUNT, then copy the four INIT_DATA blocks, IM 1, SEQ_PTR = SEQ_LIST
init_vars:
        XOR A
        LD (REDRAW_MAGIC),A
        LD (MAGIC_MSG_CHAN),A
        LD (MAGIC_WORD_COUNT),A
        LD (MAGIC_FLASH_WORD),A
        LD (THIN_MODE),A
        LD (KEY_ECHO_TX),A
        LD (SPEED_PENDING),A
        LD (FUNC_PENDING),A
        LD (SCROLL_SPEED),A
        LD (BLANK_TIMER),A
        CPL
        LD (NEXT_CHAN),A
        LD A,' '
        LD (MAGIC_LAST_CHAR),A
        LD A,(NMI_COUNT)
        LD (RND_SEED),A
        AND 3
        ADD A,3
        LD (RND_VAL),A

init_copy_tables:
        LD HL,INIT_DATA
        LD BC,9
        LD DE,FB_COLPTR
        LDIR
        LD HL,INIT_DATA+9     ; -> STAGE_PTR
        LD DE,STAGE_PTR
        LD BC,8
        LDIR
        LD HL,INIT_DATA+0x17     ; -> CLK_RUN..
        LD DE,CLK_RUN
        LD BC,0x0052
        LDIR
        LD HL,INIT_DATA+0x69     ; -> SEQ_MENU_ACTIVE..
        LD DE,SEQ_MENU_ACTIVE
        LD BC,KEY_CASE
        LDIR
        IM 1
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        RET

; ---- INIT_DATA: four RAM images copied by init_vars. +9..+16 -> 40FD (STAGE_PTR = TXBUF,
;      40FF = 3C, STAGE_OFFSET, ROW_PORT, BEEP_TICKS); +0x17..+0x68 (82 bytes) -> 410B
;      CLK_RUN .. 415C; +0x69..+0x84 (28 bytes) -> 41EB SEQ_MENU_ACTIVE .. 4206
;      ROW_OUT_PENDING. +0x11..+0x16 are copied nowhere. Frame geometry is 60 columns
;      (0x3C)
INIT_DATA:
        dw FRAMEBUF_ROW1                             ; 40b8 FB_COLPTR
        db 0x3c
        dw FRAMEBUF                                  ; 40bb FB_COL
        db 0x7b
        db 0x40                                      ; 40be 
        db 0x3b
        db 0x00
        db 0xc1
        dw 0x3c40
        db 0x00
        dw 0
        db 0x00                                      ; 4103 BEEP_TICKS
        dw 0x0100
        db 0x02,0x00,0x00,0x00,0x00,0x01
        db 0x00
        db 0x00                                      ; 410d GLYPH_PTR
        dw 0
        dw 0x0f00
        db 0x00
        db 0x00                                      ; 4113 CUR_CHAR
        db 0x00                                      ; 4114 TEST_MODE
        db 0x40
        dw 0x0140
        db 0x05
        db 0x00
        dw 0
        db 0x00                                      ; 411c INS_PTR
        db 0x00                                      ; 411d 
        dw 0x0f00
        db 0x00                                      ; 4120 COL_COUNT
        db 0x00                                      ; 4121 FRAME_COUNT
        db 0x0a
        db 0x00                                      ; 4123 LATCH_BIT7
        db 0x00                                      ; 4124 COLOR_PENDING
        db 0x00
        db 0x0f
        db 0x00                                      ; 4127 INPUT_MODE
        db 0x00                                      ; 4128 MENU_MSG_FLAG
        db 0x00
        db 0x00                                      ; 412a PREV_KEY
        db 0x00                                      ; 412b PREV_KEY2
        db 0x00                                      ; 412c RX_BYTE
        db 0x00                                      ; 412d IR_KEY_CHAR
        db 0x00                                      ; 412e KEY_TIMER
        db 0x00                                      ; 412f 
        dw 0
        db 0x00                                      ; 4132 
        dw 0x3c00
        db 0x00                                      ; 4135 
        dw 0
        dw 0x47ff
        dw 0
        dw 0
        db 0x00                                      ; 413e EFFECT_ID
        db 0x00                                      ; 413f EFFECT_VECTOR
        db 0x00                                      ; 4140 
        dw 0
        dw 0
        db 0x01
        db 0x00                                      ; 4146 FLUSH_PENDING
        db 0x00                                      ; 4147 PROG_MSG_FORCE
        db 0x00
        db 0x00                                      ; 4149 ROW_INDEX
        db 0x00                                      ; 414a RX_BITMASK
        db 0x00                                      ; 414b 
        dw 0
        db 0x00                                      ; 414e RX_FIFO
        dw 0
        db 0x00                                      ; 4151 
        db 0x00                                      ; 4152 
        dw 0
        db 0x00                                      ; 4155 
        db 0x00                                      ; 4156 RX_COUNT
        db 0xbd
        db 0x10
        db 0x00                                      ; 4159 REDRAW_PTR
        db 0x00                                      ; 415a 
        db 0x9e
        db 0x10
        dw 0
        dw 0
        db 0x00                                      ; 41ef TINY_MODE
        db 0x00                                      ; 41f0 FORCE_BOLD
        dw 0x04b0
        dw 0
        db 0x00                                      ; 41f5 MOVE_DST
        db 0x00                                      ; 41f6 
        db 0x00                                      ; 41f7 MOVE_SRC
        db 0x00                                      ; 41f8 
        db 0x00                                      ; 41f9 REDRAW_FROM
        db 0x00                                      ; 41fa 
        dw MSG_STORE
        dw 0x0100
        dw 0
        dw 0
        dw TX_TIMING

        ds 0x0596-$,0xff

; ---- init_render: reset the render state: 120-byte ring cleared, window 60 wide at
;      FRAMEBUF, no effect, default color 8F, staging at TXBUF. No TINY line, RAINBOW, DRAW or
;      FLASH_PENDING state exists in this ROM
init_render:
        CALL clear_framebuf
        LD HL,FRAMEBUF
        LD (FB_OUT_PTR),HL
        LD (FB_COL),HL
        LD HL,0
        LD (FB_EXTRA_LEN),HL
        LD HL,0x003c
        LD (FB_OUT_LEN),HL
        XOR A
        LD (REDRAW_MAGIC),A
        LD (THIN_MODE),A
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
        LD HL,(STORE_LIMIT)
        LD (HL),MARK_HI
        RET

; ---- render_next_char: fetch the next store byte and act on it. Inline track_flash_space
;      (FLASH ends at a space, two spaces drop the background unless TEST_MODE), then
;      DRAW/THIN/WAIT/REM checks, A0-AF graphics, 80-FF colors/speed, 00-1F controls, 5F
;      clock, else glyph_lookup
render_next_char:
        CALL fetch_char
        CALL magic_preprocess
        LD A,(CUR_CHAR)
        CP 0x20
        JR z,render_attr_checks
        XOR A
        LD (PREV_SPACE),A
        LD A,(CUR_CHAR)

; ---- render_attr_checks: B8 DRAW, B9 THIN, BA WAIT, B0 REM, then classify
render_attr_checks:
        CALL attr_draw_check
        CALL attr_thin_check
        CALL attr_wait_check
        CALL attr_remark_check
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
        JR nz,double_space
        LD A,1
        LD (PREV_SPACE),A
        JR render_glyph_or_clock

; ---- double_space: second space in a row clears the background bits of CUR_COLOR, except
;      in TEST_MODE (0x4114)
double_space:
        LD A,(TEST_MODE)
        INC A
        JR z,render_clear_prev_space
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

; ---- glyph_lookup: HL = FONT (0x28E5) + 8 * CUR_CHAR, GLYPH_WIDTH = byte 7. No
;      char_to_glyph: the byte indexes the 128-glyph font directly, so only 00-7F may
;      reach here (A0-AF graphics arrive masked to 0-F)
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

; ---- glyph_style: DRAW re-enters here with GLYPH_PTR = DRAW_BUF. Clear the glyph
;      buffers; unless TINY_MODE (menus) apply bold / big / italic, then the 00-0F
;      double-width rule and glyph_place
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
        LD A,(MAGIC_FLASH_WORD)
        AND A
        JR z,blit_use_flash
        XOR A
        LD (MAGIC_FLASH_WORD),A
        LD A,0x10
        JR blit_set_c

blit_use_flash:
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

; ---- fetch_char: CUR_CHAR = (STORE_CURSOR++). No CLK_RENDERED LEFT substitution in this
;      ROM
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

; ---- attr_remark_check: A = CUR_CHAR on entry; B0 REM skips to the next B0
attr_remark_check:
        CP ATTR_REM
        RET nz

remark_skip:
        CALL fetch_char
        LD A,(CUR_CHAR)

; ---- attr_remark: 0xB0: skip text until the next 0xB0 (hidden remark)
attr_remark:
        CP ATTR_REM
        JR z,remark_end
        CP 3
        RET z
        JR remark_skip

remark_end:
        POP HL
        JP render_next_char

; ---- attr_wait_check: BA WAIT. With text staged (COL_COUNT != 0) substitute the
;      pseudo-attribute 17 (goes through attr_control -> fx_attr and flushes the stage)
;      and step the cursor back so BA is read again. Otherwise reset the colors and spin
;      in wait_poll
attr_wait_check:
        CP 0xba
        RET nz
        LD A,(COL_COUNT)
        AND A
        JR z,wait_for_key
        LD A,0x17
        LD (CUR_CHAR),A
        CALL unfetch_char
        RET

wait_for_key:
        CALL fb_colors_default

; ---- wait_poll: packet mode releases on PKT_READY (-> pkt_process); keypad and terminal
;      modes release on RX_BYTE = 08 (keypad code 8, or a serial space, which rx_fifo_get
;      maps to 08 outside the editor)
wait_poll:
        LD A,(INPUT_MODE)
        CP 0xfe
        JR z,wait_check_pkt
        LD A,(RX_BYTE)
        CP 8
        JR z,wait_release
        JR wait_poll

; ---- wait_release: drop the caller's frame and continue rendering
wait_release:
        POP HL
        JP render_next_char

wait_check_pkt:
        LD A,(PKT_READY)
        AND A
        JP nz,pkt_process
        JP wait_poll

; ---- attr_thin_check: B9 THIN: THIN_MODE = B9, next byte
attr_thin_check:
        CP ATTR_THIN
        RET nz
        LD (THIN_MODE),A
        POP HL
        JP render_next_char

; ---- attr_draw_check: B8 DRAW: hex digit pairs packed by RRD into DRAW_BUF, up to 16
;      columns, ended by the first non-hex byte (pushed back). CUR_CHAR becomes '*' so the
;      glyph path treats it as an ordinary printable
attr_draw_check:
        CP 0xb8
        RET nz
        LD HL,DRAW_BUF
        PUSH HL
        PUSH HL
        LD B,0x10

draw_clear:
        LD (HL),0
        INC HL
        DJNZ draw_clear
        POP HL
        LD C,0
        LD B,0x10

draw_hex_loop:
        CALL fetch_char
        LD A,(CUR_CHAR)
        CALL hex_digit_value
        CP 0xff
        JR z,draw_end_item
        PUSH AF
        CALL fetch_char
        LD A,(CUR_CHAR)
        CALL hex_digit_value
        CP 0xff
        JR z,draw_odd_digit
        RRD
        POP AF
        RRD
        INC HL
        INC C
        DJNZ draw_hex_loop

draw_finish:
        POP HL
        LD (GLYPH_PTR),HL
        LD (GLYPH_PTR_ORIG),HL
        LD A,C
        LD (GLYPH_WIDTH),A
        POP HL
        JP glyph_style

; ---- draw_odd_digit: a lone high nibble was pushed: discard it
draw_odd_digit:
        POP AF

; ---- draw_end_item: push the terminating byte back, then finish the graphic
draw_end_item:
        CALL unfetch_char

draw_abort:
        LD A,'*'
        LD (CUR_CHAR),A
        JP draw_finish

; ---- hex_digit_value: A = value of ASCII hex digit, FF if not one
hex_digit_value:
        CP '0'
        JP c,hexval_bad
        CP '9'+1
        JP c,hexval_ok
        AND 0xdf
        CP 0x41
        JP c,hexval_bad
        CP 0x47
        JP nc,hexval_bad
        AND 15
        ADD A,9

hexval_ok:
        AND 15
        RET

hexval_bad:
        LD A,0xff
        RET

; ---- magic_preprocess: MAGIC mode: random font per word, color change every
;      few words or at punctuation, text pushed off before movement attributes
magic_preprocess:
        LD A,(MENU_ACTIVE)
        AND A
        RET nz
        LD A,(MAGIC_MODE)
        AND A
        RET z
        LD A,(EFFECT_ID)
        AND A
        JR z,magic_char
        LD A,(CUR_CHAR)
        CP ' '
        RET nz
        POP HL
        JP fx_flush_stage

magic_char:
        LD A,(CUR_CHAR)
        CP ' '
        JR nz,magic_fx_check
        LD HL,MAGIC_WORD_COUNT
        INC (HL)
        LD A,(MAGIC_LAST_CHAR)
        CP 0x2e
        JP z,magic_reseed
        CP '!'
        JP z,magic_reseed
        CP '?'
        JP z,magic_reseed
        CP '9'+1
        JP z,magic_reseed
        CP 0x2c
        JP z,magic_reseed
        LD A,' '
        LD (MAGIC_LAST_CHAR),A
        JP magic_ret

; ---- magic_fx_check: 0F, 19, 1A, 1B are movement attributes: push the text off once
;      before them
magic_fx_check:
        CP 15
        JR z,magic_before_fx
        CP 0x19
        JR c,magic_other
        CP 0x1c
        JR nc,magic_other

; ---- magic_before_fx: first of consecutive movement attributes: render ten spaces with
;      the plain crawl to clear the panel (CUR_CHAR saved around it)
magic_before_fx:
        LD A,(MAGIC_FX_PREV)
        AND A
        RET nz
        LD A,0xff
        LD (MAGIC_FX_PREV),A
        LD A,(CUR_CHAR)
        PUSH AF
        LD B,10

magic_push_off:
        PUSH BC
        LD A,' '
        LD (CUR_CHAR),A
        XOR A
        LD (EFFECT_ID),A
        LD HL,fxv_none
        LD (EFFECT_VECTOR),HL
        CALL glyph_lookup
        CALL effect_step
        POP BC
        DJNZ magic_push_off
        POP AF
        LD (CUR_CHAR),A
        RET

magic_other:
        XOR A
        LD (MAGIC_FX_PREV),A
        LD A,(CUR_CHAR)
        AND 0xf0
        CP GRAPH_BASE
        JP z,magic_printable
        CP 0x20
        JP c,magic_ret
        CP COLOR_BASE
        JP nc,magic_ret

magic_printable:
        LD A,(MAGIC_LAST_CHAR)
        CP 0x20
        JR z,magic_word_start
        LD A,(CUR_CHAR)
        LD (MAGIC_LAST_CHAR),A
        JP magic_ret

magic_word_start:
        LD A,(CUR_CHAR)
        LD (MAGIC_LAST_CHAR),A
        CP 0x24
        JR nz,magic_pick_font
        LD (MAGIC_FLASH_WORD),A

magic_pick_font:
        AND 0xf0
        CP GRAPH_BASE
        JP z,magic_color_check
        LD B,8
        LD HL,(STORE_CURSOR)

magic_scan_word:
        LD A,(HL)
        AND 0x5f
        CP 0x41
        JP c,magic_short_word
        CP 0x5b
        JP nc,magic_short_word
        INC HL
        DJNZ magic_scan_word
        JP magic_font_normal

magic_short_word:
        LD A,B
        CP 6
        JP nc,magic_font_normal
        LD A,(RND_SEED)
        ADD A,(HL)
        LD HL,(NMI_COUNT)
        ADD A,(HL)
        LD (RND_SEED),A
        AND 3
        JR z,magic_font_italic
        LD HL,FONT_MODE
        LD (HL),2
        JR magic_count_words

magic_font_italic:
        LD HL,FONT_MODE
        LD (HL),6
        JR magic_count_words

magic_font_normal:
        XOR A
        LD (FONT_MODE),A

magic_count_words:
        LD A,(MAGIC_WORD_COUNT)
        CP 3
        JP nc,magic_color_check
        LD A,(RND_VAL)
        AND A
        JP z,magic_reseed
        DEC A
        JP z,magic_reseed
        LD (RND_VAL),A
        JP magic_reset_words

magic_reseed:
        LD A,(NMI_COUNT)
        LD E,A
        AND 3
        ADD A,2
        LD (RND_VAL),A

magic_color_check:
        LD A,(MAGIC_COLOR_IDX)
        INC A
        LD E,A
        LD A,(NMI_COUNT)
        ADD A,E

magic_color_try:
        AND 15
        LD (MAGIC_COLOR_IDX),A
        LD E,A
        LD D,0
        LD HL,MAGIC_COLOR_CYCLE
        ADD HL,DE
        LD A,(CUR_COLOR)
        AND 15
        CP (HL)
        JR z,magic_color_retry
        LD A,(CUR_COLOR)
        LD E,A
        LD D,(HL)
        LD A,D
        LD HL,CUR_COLOR
        RLD
        LD A,(HL)
        LD HL,MAGIC_CLASH_PAIRS
        LD BC,6
        OR A
        CPIR
        JP nz,magic_color_apply
        LD A,E
        LD (CUR_COLOR),A

magic_color_retry:
        LD A,(MAGIC_COLOR_IDX)
        INC A
        JR magic_color_try

magic_color_apply:
        LD A,E
        AND COLOR_FLASH
        OR D
        AND 0x1f
        LD (CUR_COLOR),A

magic_reset_words:
        XOR A
        LD (MAGIC_WORD_COUNT),A

magic_ret:
        RET

; ---- MAGIC_CLASH_PAIRS: (old<<4 | new) foreground pairs too alike to follow each
;      other in MAGIC mode: yellow/lime, yellow/orange, red/orange
MAGIC_CLASH_PAIRS:
        db 0xf7,0x7f,0xfd,0xdf,0xcd,0xdc

; ---- MAGIC_COLOR_CYCLE: the 16 foregrounds MAGIC mode walks through
MAGIC_COLOR_CYCLE:
        db 0x07,0x0c,0x0f,0x03,0x0c,0x03,0x0d,0x03,0x0f,0x03
        db 0x0c,0x03,0x03,0x0c,0x0f,0x0c

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

; ---- glyph_bold: bold copy of the glyph in GLYPH_BUF: for BOLD, or for any effect
;      unless THIN. Three full (7F) columns in a row collapse to two.
glyph_bold:
        LD A,(FORCE_BOLD)
        AND A
        JR nz,bold_expand
        LD A,(EFFECT_ID)
        AND A
        JR z,bold_check_mode
        LD A,(THIN_MODE)
        AND A
        JR z,bold_expand
        LD A,(FONT_MODE)
        AND 10
        JR nz,bold_check_mode
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD B,0
        INC A
        LD (GLYPH_WIDTH),A
        LD HL,(GLYPH_PTR)
        LD DE,GLYPH_BUF
        LDIR
        LD HL,GLYPH_BUF
        LD (GLYPH_PTR),HL
        RET

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
        LD BC,0x1c
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
        CP 0x1e
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
        LD A,(MAGIC_MODE)
        AND A
        JR z,fx_toggle_flush
        LD A,15
        LD (CUR_COLOR),A

fx_toggle_flush:
        LD A,(FLUSH_PENDING)
        CPL
        AND A
        LD (FLUSH_PENDING),A
        JR z,fx_reset_stage
        XOR A
        LD (FLUSH_PENDING),A
        LD A,0x3c

fx_reset_stage:
        LD (COL_COUNT),A
        CALL clear_txbuf
        LD HL,TXBUF
        LD (STAGE_PTR),HL
        RET

attr_control:
        LD A,(CUR_CHAR)

; ---- attr_dispatch: 11 NORM,12 BOLD,13 ITALIC,14 FLASH,10 BIG,1F MAGIC; the rest go
;      through fx_attr: 06 HALT,07 BEEP,03 END,18 LEFT,19 PAUSE,1A UP,1B DOWN,0F RIGHT
attr_dispatch:
        CP ATTR_NORM
        JP nz,attr_bold
        XOR A
        LD (FLASH_BIT),A
        LD (FONT_MODE),A
        XOR A
        LD (MAGIC_MODE),A
        JP render_next_char

; ---- attr_bold: 12 BOLD: FONT_MODE bit 1, BIG off, MAGIC off
attr_bold:
        CP 0x12
        JP nz,attr_italic
        LD A,(FONT_MODE)
        SET 1,A
        RES 3,A
        LD (FONT_MODE),A
        XOR A
        LD (MAGIC_MODE),A
        JP render_next_char

; ---- attr_italic: 13 ITALIC: FONT_MODE bit 2, MAGIC off
attr_italic:
        CP 0x13
        JP nz,attr_not_italic
        LD A,(FONT_MODE)
        SET 2,A
        LD (FONT_MODE),A
        XOR A
        LD (MAGIC_MODE),A
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
        XOR A
        LD (MAGIC_MODE),A
        JP render_next_char

; ---- attr_not_big
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
        LD A,0x3c
        SUB L
        LD (COL_COUNT),A
        JP stage_centre

; ---- fx_dispatch: 06 fx_halt (this ROM's label for it is PAUSE), 07 fx_beep, 03
;      fx_end_of_channel, 18 fx_left (CRAWL), 19 fx_pause (JUMP), 1A fx_up, 1B fx_down, 0F
;      fx_right (BCRAWL). No BB HOLD, BC RAINBOW, BE TINY here
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
        LD A,0x3c
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

; ---- fx_end_of_channel: 03: scroll the text off, reset SP and go back through main_entry
;      (where packet mode picks up a pending packet)
fx_end_of_channel:
        LD HL,fxv_none
        LD (EFFECT_VECTOR),HL
        XOR A
        LD (EFFECT_ID),A
        CALL scroll_off_text
        LD SP,0x403f
        JP main_entry

; ---- fx_pause: 19 (labelled JUMP by this ROM): effect 1, fxv_pause shows the staged text
;      at once and holds HOLD_FRAMES.
fx_pause:
        XOR A
        LD (SCROLLING),A
        LD A,0x3c
        LD (COL_COUNT),A
        LD A,1
        LD HL,fxv_pause
        JP set_effect_vector

; ---- fx_magic: 1F: MAGIC_MODE = FF, word counter and RNG reset, first color
fx_magic:
        LD A,0xff
        LD (MAGIC_MODE),A
        LD A,' '
        LD (MAGIC_LAST_CHAR),A
        LD A,1
        LD (MAGIC_WORD_COUNT),A
        XOR A
        LD (MAGIC_FX_PREV),A
        LD A,(NMI_COUNT)
        LD E,A
        AND 3
        ADD A,2
        LD (RND_VAL),A
        CALL magic_first_color
        JP render_next_char

; ---- magic_first_color: first color of the cycle when MAGIC starts
magic_first_color:
        LD A,(MENU_ACTIVE)
        AND A
        RET nz
        LD A,(EFFECT_ID)
        AND A
        RET nz
        LD A,(MAGIC_COLOR_IDX)
        INC A
        AND 15
        LD (MAGIC_COLOR_IDX),A
        LD E,A
        LD D,0
        LD HL,MAGIC_COLOR_CYCLE
        ADD HL,DE
        LD A,(HL)
        AND 15
        LD (CUR_COLOR),A
        RET

; ---- fx_halt: 06: hold HOLD_FRAMES frames (~1.3 s) with the colors reset
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
        CALL fb_colors_default
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP ATTR_LEFT
        JP z,fx_left
        LD A,(EFFECT_ID)
        AND A
        JP z,fx_left
        LD A,0x3c
        LD (COL_COUNT),A
        JP render_next_char

; ---- fb_colors_default: every color byte in the 120-byte ring -> 8F keeping the flash
;      bit; WINDOW_COLOR/ROW_COLOR likewise; MAGIC gets color 15
fb_colors_default:
        LD HL,FRAMEBUF
        LD B,0x78

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
        LD E,A
        LD A,(MAGIC_MODE)
        AND A
        RET z
        LD A,15
        LD (CUR_COLOR),A
        RET

; ---- fx_up: 1A: effect 2, fxv_wipe_updown reveals the stage row by row from the bottom
fx_up:
        XOR A
        LD (SCROLLING),A
        LD A,0x3c
        LD (COL_COUNT),A
        LD A,2
        LD HL,fxv_wipe_updown
        JP set_effect_vector

; ---- fx_down: 1B: reveal the staged text row by row from the top
fx_down:
        XOR A
        LD (SCROLLING),A
        LD A,0x3c
        LD (COL_COUNT),A
        LD A,3
        LD HL,fxv_wipe_updown
        JP set_effect_vector

; ---- set_effect_vector: HL -> EFFECT_VECTOR, A -> effect id
set_effect_vector:
        LD (EFFECT_ID),A
        LD (EFFECT_VECTOR),HL
        JP render_next_char

; ---- attr_color_speed: 0x8x foreground color, 0x9x background, 0xFx speed
attr_color_speed:
        LD A,(CUR_CHAR)
        AND 0xf0
        CP COLOR_BASE
        JP z,attr_fore_color
        CP BGRND_BASE
        JP z,attr_back_color
        CP SPEED_BASE
        JP z,attr_speed
        JP render_next_char

; ---- attr_fore_color: 80-8F: in MAGIC mode also reset the font and flash bit; MAGIC
;      ends; low nibble into CUR_COLOR keeping the background bits
attr_fore_color:
        LD A,(MAGIC_MODE)
        AND A
        JR z,fore_clear_magic
        XOR A
        LD (FONT_MODE),A
        LD A,(CUR_COLOR)
        AND 0xcf
        LD (CUR_COLOR),A

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

; ---- attr_back_color: 90-93: background bits 5-6 = (n & 3) * 0x20 (94-9F also land
;      here). MAGIC ends (back_set clears MAGIC_MODE); the CC710 has no RAINBOW
attr_back_color:
        LD A,(MAGIC_MODE)
        AND A
        JR z,back_set
        XOR A
        LD (FONT_MODE),A
        LD A,(CUR_COLOR)
        OR 15
        LD (CUR_COLOR),A

back_set:
        XOR A
        LD (MAGIC_MODE),A
        LD HL,0
        LD DE,0x20
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
        LD HL,0x003c
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

; ---- boot_clear_check: keypad mode only: PORT_IN bit 1 low at power-up clears the store
;      and the sequence. mode_test leaves keypad row 3 selected and only column bit 1 is
;      read, so any row-3 key in column 0, 1, 4 or 5 does it: 0, SHIFT, 8 or 6 held while
;      powering on (verified on a CC100)
boot_clear_check:
        LD A,(INPUT_MODE)
        AND A
        RET nz
        IN A,(0xc0)
        BIT 1,A
        RET nz

; ---- store_clear_all: MSG_STORE = D0 03 D1 03 .. D9 03 DA (ten channels, single byte
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

; ---- store_init: boot input-mode decision and store geometry. Runs mode_test with
;      pattern 55: E (last 8 samples of PORT_IN bit 0) = 00 -> INPUT_MODE FF (serial
;      terminal: keys over the line, editor driven from a terminal); E = 55 -> FE (packet
;      protocol, address derived below); anything else (e.g. the pull-up's FF) -> 00
;      (keypad). Keypad/terminal: store ceiling 47FF, 1476 bytes. Packet: ceiling 46EF,
;      1204 bytes, 46F0-47FF zeroed for PKT_READY / PKT_BUF / parser state. Replaces the
;      NET's cable test
store_init:
        LD C,0x55
        CALL mode_test
        LD A,E
        AND A
        JR z,mode_terminal
        CP 0x55
        JR z,mode_packet
        JR mode_keypad

; ---- mode_terminal: SK1 pin 9 (DB9 pin 2) held low, e.g. the NET cable's 2-5 short
;      (SK1 9-2) -> FF
mode_terminal:
        LD A,0xff
        JR store_init_keypad

mode_keypad:
        XOR A

; ---- store_init_keypad: INPUT_MODE = A; store 423C-47FF: limit/end 47FF, warn 479B, text
;      limit 05AF, size 05C4; RX state reset (no packet buffer)
store_init_keypad:
        LD (INPUT_MODE),A
        LD HL,0x47ff
        LD (STORE_LIMIT),HL
        LD (STORE_END),HL
        LD HL,0x479b
        LD (STORE_WARN_LIMIT),HL
        LD HL,0x05af
        LD (STORE_TEXT_LIMIT),HL
        LD HL,0x05c4
        LD (STORE_SIZE),HL
        LD HL,rx_st_wait_start
        LD (RX_STATE),HL
        XOR A
        LD (RX_TICKS),A
        JP store_init_ret

; ---- mode_packet: INPUT_MODE = FE. The first 8 samples D carry the adapter's reply: D !=
;      55 -> MY_ADDRESS = ~D. D = 55 -> probe again with pattern AA: D = 55 again ->
;      address AA; else keep the stored address if its complement at 422A matches, else
;      fall back to 2A. BUG: mode_store_address expects the probe byte and stores its
;      complement, so the keep path flips the address between X and ~X on every boot
;      that takes it, and the 2A fallback gives MY_ADDRESS D5, not '*' (replies go out
;      as D5). Only an inverting echo (D = D5) really yields '*'
mode_packet:
        LD A,0xfe
        LD (INPUT_MODE),A
        LD A,D
        CP 0x55
        JR nz,mode_store_address
        LD C,0xaa
        CALL mode_test
        LD A,D
        CP 0x55
        JR z,mode_store_address
        LD A,(MY_ADDRESS)
        LD E,A
        LD A,(MY_ADDRESS_INV)     ; A = ~(422A) = the stored address when the pair is valid; mode_store_address then swaps the pair (bug)
        CPL
        CP E
        JR z,mode_store_address
        LD A,0x2a                 ; meant as '*', but stored complemented: MY_ADDRESS = D5 (bug)

; ---- mode_store_address: 422A = A, MY_ADDRESS (4229) = ~A, then the packet-mode store
;      geometry: limit/end 46EF, warn 468B, text limit 049F, size 04B4, DA at 46EF,
;      46F0-47FF cleared
mode_store_address:
        LD (MY_ADDRESS_INV),A
        CPL
        LD (MY_ADDRESS),A
        LD HL,0x46ef
        LD (STORE_LIMIT),HL
        LD (STORE_END),HL
        LD HL,0x468b
        LD (STORE_WARN_LIMIT),HL
        LD HL,addends_next     ; the number 0x049F (free text bytes), not the code label
        LD (STORE_TEXT_LIMIT),HL
        LD HL,0x04b4
        LD (STORE_SIZE),HL
        LD HL,0x46ef
        LD (HL),MARK_HI
        INC HL
        LD BC,0x0110

store_init_zero_page:
        LD (HL),0
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,store_init_zero_page
        LD HL,rx_st_wait_start
        LD (RX_STATE),HL
        XOR A
        LD (RX_TICKS),A

store_init_ret:
        RET

; ---- SENTINEL_AA / SENTINEL_55: the bytes mode_test points IX and IY at so that
;      int_timer returns without running the tick service while it syncs to a tick with
;      HALT
SENTINEL_AA:
        db 0xaa

SENTINEL_55:
        db 0x55

; ---- mode_test: boot probe of the keypad/serial header. Sync to a tick (HALT with the
;      IX/IY sentinel), DI, pulse latch bit 4 1-0-1, then clock the 8 bits of C out twice
;      (15 clocks, MSB first, data on latch bit 6 = SK1 pin 5 (DB9 7), row bit 2; clock on
;      bit 5 = SK1 pin 4 (DB9 4), row bit 1) sampling PORT_IN bit 0 = SK1 pin 9 (DB9 2)
;      before the first clock and after each one: DE = 16 samples, D the first eight.
;      Leaves interrupts disabled and the last latch write in place: 30 (row 3) after
;      the 55 probe, 70 (row 7) after the AA probe
mode_test:
        LD IX,SENTINEL_AA
        LD IY,SENTINEL_55
        EI
        NOP
        HALT
        LD IX,0
        LD IY,0
        DI
        LD A,0x10
        LD (CTRL_LATCH),A
        XOR A
        LD (CTRL_LATCH),A
        LD A,0x10
        LD (CTRL_LATCH),A
        LD DE,0
        LD B,15
        IN A,(0xc0)
        AND 1
        JR z,mode_test_shift_in
        SCF

; ---- mode_test_shift_in: shift the pre-clock sample into DE
mode_test_shift_in:
        RL E
        RL D

; ---- mode_test_bit: data = next bit of C on latch bit 6 (bit 4 kept high)
mode_test_bit:
        RLC C
        LD A,0x50
        JP c,mode_test_clock
        LD A,0x10

; ---- mode_test_clock: write data with clock low, then clock high, then sample
mode_test_clock:
        LD (CTRL_LATCH),A
        SET 5,A
        LD (CTRL_LATCH),A
        IN A,(0xc0)
        AND 1
        JR z,mode_test_sample
        SCF

mode_test_sample:
        RL E
        RL D
        DJNZ mode_test_bit
        RET

; ---- tx_send_byte: queue byte A for the bit-banged transmitter; spin until the previous
;      byte is accepted
tx_send_byte:
        PUSH HL

tx_send_retry:
        CALL tx_try_queue
        AND A
        JR nz,tx_send_retry
        POP HL
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

; ---- tx_bit_engine: every tick: shift TX_SHIFT out on CTRL_LATCH bit 4 with the
;      TX_TIMING bit times (300 baud at 1302 Hz). A new byte starts only while PORT_IN
;      bits 1 and 2 (SK1 pins 8 and 7, DB9 1 and 6) are both high: a CTS-style handshake the
;      NIR does not have
tx_bit_engine:
        LD HL,TX_STATUS
        BIT 0,(HL)
        JR nz,tx_bit_tick
        IN A,(0xc0)
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

; ---- rx_bit_engine: every tick. CTRL_LATCH bit 5 (SK1 pin 4, DB9 4) is driven high as 'ready',
;      dropped while RX_FIFO is full (8 bytes), and the receiver only runs while PORT_IN
;      bit 1 is high; otherwise the NIR's start/8 data/stop sampler on PORT_IN bit 3 with
;      RX_TIMING
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
        IN A,(0xc0)
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

; ---- data 10bd-10c6: ticks between RX bit samples (start,8 data,stop)
RX_TIMING:
        db 0x06,0x04,0x05,0x04,0x04,0x05,0x04,0x04,0x05,0x04

; ---- data 10c7-10d0: ticks per TX bit: start,8 data (4,4,5 pattern = 300 baud @ ~1300 Hz), stop = 10
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

; ---- rx_fifo_get: pop one FIFO byte into RX_BYTE (NC) or C if empty. Packet mode and the
;      editor take bytes raw; terminal mode outside the editor maps 01 -> 35 (STOP/START),
;      20 -> 08 (WAIT release), keeps 7E (menu_enter) and drops everything else
rx_fifo_get:
        LD A,(RX_COUNT)
        AND A
        JR z,fifo_empty
        LD HL,RX_FIFO
        LD A,(INPUT_MODE)
        CP 0xfe
        JR z,fifo_pop_raw
        LD A,(MENU_ACTIVE)
        AND A
        JR z,fifo_key_translate

fifo_pop_raw:
        LD A,(HL)
        JR fifo_pop

; ---- fifo_key_translate: terminal mode outside the editor: serial 01 = STOP/START
fifo_key_translate:
        LD A,(HL)
        CP 1
        JR nz,fifo_key_space
        LD A,0x35
        JR fifo_pop

; ---- fifo_key_space: 20 -> 08, the WAIT release code
fifo_key_space:
        CP 0x20
        JR nz,fifo_key_other
        LD A,8
        JR fifo_pop

; ---- fifo_key_other: 7E passes; any other byte is popped and reported empty
fifo_key_other:
        CP 0x7e
        JR z,fifo_pop
        CALL fifo_pop
        JP fifo_empty

; ---- fifo_pop: RX_BYTE = A, shift the FIFO down, RX_COUNT--, return NC
fifo_pop:
        LD (RX_BYTE),A
        LD A,(RX_COUNT)
        LD BC,8
        LD HL,RX_FIFO+1
        LD DE,RX_FIFO
        LDIR
        DEC A
        LD (RX_COUNT),A
        LD A,(RX_BYTE)
        OR A
        RET

; ---- fifo_empty: RX_BYTE = 0, return C
fifo_empty:
        LD A,0
        LD (RX_BYTE),A
        SCF
        RET

; ---- pkt_feed_byte: Feed RX_BYTE to the packet parser state in PKT_VECTOR
pkt_feed_byte:
        LD A,(RX_BYTE)
        LD HL,(PKT_VECTOR)
        JP (HL)

; ---- pkt_st_addr: address byte: '*' or MY_ADDRESS continues, anything else aborts the
;      frame (PKT_STATE = PKT_READY = 0)
pkt_st_addr:
        CP 0x2a
        JR z,pkt_addr_store
        LD E,A
        LD A,(MY_ADDRESS)
        CP E
        JR z,pkt_addr_store
        XOR A
        LD (PKT_STATE),A
        LD (PKT_READY),A
        RET

; ---- pkt_addr_store: tail of pkt_st_addr: PKT_ADDR (47F7) = A, next state pkt_st_flag.
pkt_addr_store:
        LD (PKT_ADDR),A
        LD HL,pkt_st_flag
        LD (PKT_VECTOR),HL
        RET

; ---- pkt_st_flag: PKT_FLAG (47F3) = A (80 = process at once), next pkt_st_len
pkt_st_flag:
        LD (PKT_FLAG),A
        LD HL,pkt_st_len
        LD (PKT_VECTOR),HL
        RET

; ---- pkt_st_len: PKT_LEN (47F4) = A, PKT_CKSUM (47F2) =
;      0, PKT_PTR (47F8) = PKT_BUF, PKT_REMAIN (47FA) = len; next state pkt_st_data, or
;      pkt_st_cksum when len = 0. The parser states run 11BB-1246: pkt_st_data 11DB,
;      pkt_data_store 11E4, pkt_data_last 11FD, pkt_st_cksum 1204, pkt_immediate 1235,
;      pkt_discard 123F
pkt_st_len:
        LD (PKT_LEN),A
        AND A
        LD HL,pkt_st_data
        JR nz,pkt_len_setup
        LD HL,pkt_st_cksum

pkt_len_setup:
        LD (PKT_VECTOR),HL
        XOR A
        LD (PKT_CKSUM),A
        LD HL,PKT_BUF
        LD (PKT_PTR),HL
        LD A,(PKT_LEN)
        LD (PKT_REMAIN),A
        RET

; ---- pkt_st_data: a B1 inside the payload aborts the frame (back to idle); otherwise
;      store the byte
pkt_st_data:
        CP 0xb1
        JR nz,pkt_data_store
        XOR A
        LD (PKT_STATE),A
        RET

; ---- pkt_data_store: (PKT_PTR++) = byte, PKT_CKSUM += byte, PKT_REMAIN--
pkt_data_store:
        LD HL,(PKT_PTR)
        LD (HL),A
        LD A,(PKT_CKSUM)
        ADD A,(HL)
        LD (PKT_CKSUM),A
        LD A,(PKT_REMAIN)
        DEC A
        JR z,pkt_data_last
        LD (PKT_REMAIN),A
        INC HL
        LD (PKT_PTR),HL
        RET

; ---- pkt_data_last: payload complete: next state pkt_st_cksum
pkt_data_last:
        LD HL,pkt_st_cksum
        LD (PKT_VECTOR),HL
        RET

; ---- pkt_st_cksum: E = PKT_CKSUM - byte. PKT_ADDR = '*': no reply; else ACK 06 or NAK 15
;      via tx_send_byte. Good and len > 0: PKT_READY = FF, PKT_STATE = 0, and PKT_FLAG =
;      80 goes on to pkt_immediate; bad -> pkt_discard
pkt_st_cksum:
        LD E,A
        LD A,(PKT_CKSUM)
        SUB E
        LD E,A
        LD A,(PKT_ADDR)
        CP ADDR_BROADCAST
        JR z,pkt_check_ok
        LD A,E
        AND A
        LD A,REPLY_ACK
        JR z,pkt_send_reply
        LD A,REPLY_NAK

pkt_send_reply:
        CALL tx_send_byte

pkt_check_ok:
        LD A,E
        AND A
        JR nz,pkt_discard
        LD A,(PKT_LEN)
        AND A
        JR z,pkt_discard
        LD A,0xff
        LD (PKT_READY),A
        XOR A
        LD (PKT_STATE),A
        LD A,(PKT_FLAG)
        CP COLOR_BASE
        RET nz

; ---- pkt_immediate: PKT_FLAG = 80: pop the three return addresses on the stack
;      (rx_have_byte, INT_VECTOR, the interrupted PC) and push them back with pkt_process
;      in place of the interrupted PC, so the ISR's RETI lands in pkt_process instead of
;      the display code
pkt_immediate:
        POP BC
        POP DE
        POP HL
        LD HL,pkt_process
        PUSH HL
        PUSH DE
        PUSH BC
        RET

; ---- pkt_discard: PKT_READY = PKT_STATE = 0
pkt_discard:
        XOR A
        LD (PKT_READY),A
        LD (PKT_STATE),A
        RET

; ---- tx_send_frame: Send reply frame: B1, MY_ADDRESS, then (HL)=len, len bytes, 8-bit sum of the data bytes
tx_send_frame:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD A,0xb1
        CALL tx_send_byte
        LD A,(MY_ADDRESS)
        CALL tx_send_byte
        LD E,0
        LD A,(HL)
        LD B,A
        CALL tx_send_byte
        INC HL

txf_data_loop:
        LD A,(HL)
        ADD A,E
        LD E,A
        LD A,(HL)
        CALL tx_send_byte
        INC HL
        DJNZ txf_data_loop
        LD A,E
        CALL tx_send_byte
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- editor_query_hook: serve B4 queries typed into the editor; when one is
;      consumed, drop the caller and fetch the next key
editor_query_hook:
        CALL query_dispatch
        LD A,(EDIT_KEY)
        AND A
        RET nz
        POP HL
        POP HL
        JP editor_next_key

; ---- query_dispatch: B4 typed into the editor (terminal mode): '0' ROM id, '1' memory,
;      '2' remarks, '3' dump. Nothing in keypad mode (INPUT_MODE = 0)
query_dispatch:
        LD A,(INPUT_MODE)
        AND A
        RET z
        LD A,(EDIT_KEY)
        CP CMD_QUERY
        RET nz
        CALL menu_getchar
        CP QUERY_ROMID
        JP z,query_0_romid
        CP QUERY_MEMORY
        JP z,query_1_memory
        CP QUERY_NOP
        JP z,query_2_remarks
        CP QUERY_DUMP
        JP z,query_3_dump
        RET

; ---- query_0_romid: B4 '0': reply 6 bytes, ROM_ID '710' + ROM_REV '09l'
query_0_romid:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD HL,TXBUF
        LD (HL),6
        INC HL
        LD DE,HOLD_FRAMES
        LD BC,3
        EX DE,HL
        LDIR
        LD HL,0x0060
        LD BC,3
        LDIR
        LD HL,TXBUF
        CALL tx_send_frame
        XOR A
        LD (EDIT_KEY),A
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- query_1_memory: B4 '1': reply two 5-digit ASCII numbers: STORE_SIZE (1204 packet
;      mode) and free bytes
query_1_memory:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        CALL store_finalize
        LD HL,TXBUF
        LD (HL),10
        INC HL
        PUSH HL
        POP IX
        LD HL,(STORE_SIZE)
        CALL bin_to_dec5
        PUSH IX
        LD HL,(STORE_LIMIT)
        LD DE,(STORE_END)
        OR A
        SBC HL,DE
        POP IX
        CALL bin_to_dec5
        LD HL,TXBUF
        CALL tx_send_frame
        XOR A
        LD (EDIT_KEY),A
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- query_2_remarks: B4 '2' (the NIR's NOP): reply B1 addr len, then for each of
;      channels 0-9 the text of its first B0 REM up to 20 bytes followed by a 19
;      separator, then the checksum. Pass 1 counts the bytes, pass 2 sends them. The
;      checksum adds B0 where 19 was sent. A way for the PC to read the message titles.
query_2_remarks:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD A,0xb1
        CALL tx_send_byte
        LD A,(MY_ADDRESS)
        CALL tx_send_byte
        LD D,0
        LD E,0xd0

; ---- remq_count_chan: pass 1: CPIR to marker E in MSG_STORE (BC = 0x4234 is an over-long
;      count, not STORE_SIZE's contents)
remq_count_chan:
        LD HL,MSG_STORE
        LD BC,STORE_SIZE
        LD A,E
        CPIR

; ---- remq_count_scan: walk the channel to its first B0; a marker ends it
remq_count_scan:
        LD A,(HL)
        CP 0xb0
        JR nz,remq_count_step
        LD B,0x14
        JP remq_count_rem

remq_count_step:
        AND 0xf0
        CP 0xd0
        JR z,remq_count_next
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,remq_count_scan
        JP remq_send_len

; ---- remq_count_rem: count up to 20 remark bytes (B0, 03 or a marker stops)
remq_count_rem:
        INC HL
        LD A,(HL)
        CP 0xb0
        JR z,remq_count_next
        CP 3
        JR z,remq_count_next
        AND 0xf0
        CP 0xd0
        JR z,remq_count_next
        INC D
        DJNZ remq_count_rem

; ---- remq_count_next: one more for the separator; next channel until DA
remq_count_next:
        INC D
        INC E
        LD A,E
        CP 0xda
        JP nz,remq_count_chan

; ---- remq_send_len: send D as the length byte, start pass 2 (D now the checksum)
remq_send_len:
        LD A,D
        CALL tx_send_byte
        LD D,0
        LD E,0xd0

remq_send_chan:
        LD HL,MSG_STORE
        LD BC,STORE_SIZE
        LD A,E
        CPIR

remq_send_scan:
        LD A,(HL)
        CP 0xb0
        JR nz,remq_send_step
        LD B,0x14
        JP remq_send_rem

remq_send_step:
        AND 0xf0
        CP 0xd0
        JR z,remq_send_sep
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,remq_send_scan
        JP remq_send_cksum

; ---- remq_send_rem: send and sum up to 20 remark bytes
remq_send_rem:
        INC HL
        LD A,(HL)
        CP 0xb0
        JR z,remq_send_sep
        CP 3
        JR z,remq_send_sep
        AND 0xf0
        CP 0xd0
        JR z,remq_send_sep
        LD A,(HL)
        ADD A,D
        LD D,A
        LD A,(HL)
        CALL tx_send_byte
        DJNZ remq_send_rem

; ---- remq_send_sep: send 19 after each channel but add B0 to the checksum
remq_send_sep:
        LD A,0x19
        CALL tx_send_byte
        LD A,0xb0
        ADD A,D
        LD D,A
        INC E
        LD A,E
        CP 0xda
        JP nz,remq_send_chan

remq_send_cksum:
        LD A,D
        CALL tx_send_byte
        XOR A
        LD (EDIT_KEY),A
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- query_3_dump: B4 '3': reply B1 addr <5 ASCII digits = bytes to STORE_END inclusive>
;      <MSG_STORE through DA> cksum.
query_3_dump:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD A,0xb1
        CALL tx_send_byte
        LD A,(MY_ADDRESS)
        CALL tx_send_byte
        LD HL,(STORE_END)
        INC HL
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        LD IX,TXBUF
        CALL bin_to_dec5
        LD HL,TXBUF
        LD B,5

dump_len_loop:
        LD A,(HL)
        CALL tx_send_byte
        INC HL
        DJNZ dump_len_loop
        LD HL,MSG_STORE
        LD E,0

dump_data_loop:
        LD A,(HL)
        ADD A,E
        LD E,A
        LD A,(HL)
        CALL tx_send_byte
        LD A,(HL)
        CP 0xda
        JP z,dump_cksum
        INC HL
        JP dump_data_loop

dump_cksum:
        LD A,E
        CALL tx_send_byte
        XOR A

; ---- dump_return: EDIT_KEY = 0
dump_return:
        LD (EDIT_KEY),A
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- bin_to_dec5: HL -> 5 ASCII digits at (IX) using table 10000,1000,100,10,1
bin_to_dec5:
        LD IY,DEC_TABLE

; ---- bin_to_dec_iy: digits from the place-value table at IY
bin_to_dec_iy:
        LD B,0x2f
        LD E,(IY+0)
        LD D,(IY+1)
        BIT 7,D
        RET nz

dec_digit_loop:
        INC B
        OR A
        SBC HL,DE
        JR nc,dec_digit_loop
        ADD HL,DE
        LD (IX+0),B
        INC IX
        INC IY
        INC IY
        JR bin_to_dec_iy

; ---- data 1449-1452: 10000,1000,100,10,1 for bin_to_dec5; the FF fill after it is the -1 end mark
DEC_TABLE:
        dw 0x2710
        dw 0x03e8
        dw CHANNELS
        dw 0x000a
        dw 0x0001

        ds 0x1455-$,0xff

; ---- clock_tick: NMI: NMI_COUNT to 60 (literal, no NMI_PER_SEC variable) -> CLK_SEC ->
;      minutes (4108, 4107) -> hours (4106, 4105), 12-hour with CLK_PM
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

; ---- scroll_off_text: push the displayed text off by rendering 10 spaces
scroll_off_text:
        LD B,10

scrolloff_loop:
        LD A,' '
        LD (CUR_CHAR),A
        PUSH BC
        CALL space_seen
        CALL effect_step
        POP BC
        DJNZ scrolloff_loop
        RET

; ---- keypad_scan: 8x8 matrix scan, identical to the NET's: rows 0-7 on CTRL_LATCH bits
;      4-6, column code on PORT_IN bits 0-2, key down = bit 3 low; code row*8+col ->
;      RX_BYTE (key 0 reported as 1E), 0 = none
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

; ---- clear_framebuf: the 120-byte ring (2 x 60 columns) = 0x80
clear_framebuf:
        PUSH HL
        PUSH BC
        LD HL,FRAMEBUF
        LD B,0x78

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
        LD B,0x3c

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

; ---- menu_enter: terminal-mode byte 7E: the next byte must be MY_ADDRESS or '*' to open
;      the editor, else RESET. Reachable here, unlike in the NIR
menu_enter:
        LD SP,0x403f
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
        CALL menu_getchar
        PUSH AF
        LD A,0
        LD (KEY_ECHO_TX),A
        POP AF
        LD HL,MY_ADDRESS
        CP (HL)
        JR z,editor_start
        CP 0x2a
        JR z,editor_start
        JP RESET

; ---- key_handler: STOP/START (keypad 35, or serial 01 in terminal mode): open the editor
;      with key echo on the serial TX
key_handler:
        LD A,1
        LD (KEY_ECHO_TX),A

; ---- editor_start: MENU_ACTIVE = FF, SP reset, EI, render state cleared; keypad mode
;      first waits for the key to be released
editor_start:
        LD SP,0x403f
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
        LD (SEQ_SET),A
        LD A,(INPUT_MODE)
        AND A
        JR nz,editor_init

; ---- editor_wait_release: keypad mode: spin until keypad_scan reports no key
editor_wait_release:
        CALL keypad_scan
        AND A
        JR nz,editor_wait_release

; ---- editor_init: leaving TEST_MODE (4114 = FF) puts the cursor on channel 0; then seat
;      the cursor and INS_PTR on the channel marker
editor_init:
        LD A,(TEST_MODE)
        INC A
        JR nz,editor_find_marker
        XOR A
        LD (TEST_MODE),A
        CALL chan_select
        LD (STORE_CURSOR),HL

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
        LD A,C
        OR B
        JR nz,editor_scan_loop
        JP pkt_process_end

; ---- editor_set_ins: INS_PTR = marker + 1, store_finalize, clear the prefix flags
editor_set_ins:
        INC HL
        LD (INS_PTR),HL
        CALL store_finalize
        XOR A
        LD (SPEED_PENDING),A
        LD (FUNC_PENDING),A
        LD (GRAPH_PENDING),A
        LD (COLOR_PENDING),A
        LD (BGRND_PENDING),A
        LD (SHIFT_LABEL),A
        LD (MENU_MSG_FLAG),A
        LD A,0xff
        LD (EDITOR_FIRST_KEY),A

; ---- editor_loop: Editor main loop: get key, dispatch
editor_loop:
        CALL editor_redraw

editor_next_key:
        CALL menu_getchar
        CALL editor_translate_key
        LD A,(EDIT_KEY)
        LD (CUR_CHAR),A
        CP KEY_SHIFT
        LD A,0
        JR z,editor_dispatch
        LD (COLOR_PENDING),A
        LD (BGRND_PENDING),A
        LD (FUNC_PENDING),A

; ---- editor_dispatch: keys: 5E address, 03 CLR ALL, 05 top of message, 7F delete, 1D
;      shift, 0A/08 cursor, 0C/0B cursor x8, 07 (BEEP) shows INVALID, 0E clear message, 1C
;      caps, 1E/15/16/B7/02 prefixes, 17 TIME?, B3 end, 09 PROG?, 04 SEQ?, 0D exit, 9F
;      ignored, else insert. No B6 EUROPE, no B1 exit
editor_dispatch:
        LD (SHIFT_LABEL),A
        LD A,(PROG_MSG_FORCE)
        OR A
        JP nz,menu_prog_msg
        LD A,(SEQ_MENU_ACTIVE)
        BIT 7,A
        JP nz,menu_seq_msg
        LD A,(EDIT_KEY)
        CP ATTR_MAGIC
        CALL z,magic_new_message
        XOR A
        LD (EDITOR_FIRST_KEY),A
        LD A,(EDIT_KEY)
        CP 0x5e
        JP z,menu_address
        CP 3
        JP z,menu_clear_all
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
        CP 7
        JP z,editor_show_invalid
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
        CP 0xb3
        JP z,editor_goto_end
        CP KEY_FUNC
        JP z,editor_key_func
        CP 9
        JP z,menu_prog_msg
        CP 4
        JP z,menu_seq_msg
        CP 13
        JP z,editor_exit
        CP 0x9f
        JP z,editor_loop
        JP editor_insert

; ---- magic_new_message: MAGIC as the first key in the editor: take the first empty
;      channel 0-9 (none -> ' CLR MEM?' prompt and a digit chooses one, whose text is
;      deleted), make it the whole sequence, announce 'MSG n  <MAGIC>' on the next redraw
magic_new_message:
        LD A,(EDITOR_FIRST_KEY)
        AND A
        RET z
        LD A,0xd0

; ---- newmsg_try_chan: A = D0+n: chan_select; (HL) = 03 means empty
newmsg_try_chan:
        LD E,A
        CALL chan_select
        AND A
        JP nz,pkt_process_end
        LD A,(HL)
        CP 3
        JR z,newmsg_empty_found
        LD A,E
        INC A
        CP 0xda
        JR nz,newmsg_try_chan
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STR_CLR_MEM
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

; ---- newmsg_ask_chan
newmsg_ask_chan:
        CALL menu_getchar
        CP 13
        RET z
        CP 9
        RET z
        CP 0x30
        JP c,newmsg_ask_chan
        CP 0x3a
        JP nc,newmsg_ask_chan
        AND 15
        OR 0xd0

newmsg_select:
        LD (NEW_MSG_CHAN),A
        CALL chan_select
        AND A
        JP nz,pkt_process_end
        LD (INS_PTR),HL
        DEC HL
        LD (STORE_CURSOR),HL
        CALL delete_chan_text
        LD A,0x1f
        LD (EDIT_KEY),A
        LD A,(NEW_MSG_CHAN)
        LD E,A
        JP newmsg_set_seq

newmsg_empty_found:
        LD (INS_PTR),HL
        DEC HL
        LD (STORE_CURSOR),HL

; ---- newmsg_set_seq: CHAN_STATE[n] = FF, SEQ_LIST = n then FF x 31, MAGIC_MSG_CHAN =
;      D0+n
newmsg_set_seq:
        PUSH DE
        CALL clear_chan_lock
        POP DE
        LD A,E
        AND 15
        LD E,A
        LD D,0
        LD HL,CHAN_STATE
        ADD HL,DE
        LD (HL),0xff
        LD HL,SEQ_LIST
        LD (HL),E
        INC HL
        LD B,0x1f

newmsg_seq_loop:
        LD (HL),0xff
        INC HL
        DJNZ newmsg_seq_loop
        LD A,E
        OR 0xd0
        LD (MAGIC_MSG_CHAN),A
        RET

; ---- store_finalize: STORE_END = address of the DA that ends the store
store_finalize:
        LD A,MARK_HI
        LD HL,MSG_STORE
        LD BC,(STORE_SIZE)
        INC BC
        CPIR
        LD A,B
        OR C
        JP z,pkt_process_end
        DEC HL
        LD (STORE_END),HL
        RET

; ---- editor_show_invalid: MENU_MSG_FLAG = FF, MENU_MSG_PTR = MENU_STR_INVALID (0x280D)
editor_show_invalid:
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_INVALID     ; MENU_MSG_PTR = MENU_STR_INVALID (0x280D)
        LD (MENU_MSG_PTR),HL
        JP editor_loop

; ---- editor_exit: 0D in the editor: SEQ_MENU_ACTIVE and PROG_MSG_FORCE cleared;
;      serial modes echo a CR, keypad mode waits
;      for the key to be released; then add the channel to SEQ_LIST if absent and resume
;      the display.
editor_exit:
        XOR A
        LD (SEQ_MENU_ACTIVE),A
        LD (PROG_MSG_FORCE),A
        LD A,(INPUT_MODE)
        AND A
        JR z,exit_wait_release
        LD A,13
        CALL tx_send_byte
        JP exit_add_to_seq

; ---- exit_wait_release: keypad: restart the two-tick no-key count
exit_wait_release:
        LD A,2
        LD C,A
        LD (KEY_TIMER),A

exit_release_tick:
        DEC C
        JR z,exit_add_to_seq

; ---- exit_release_poll: wait for KEY_TIMER to reach C; a key still down restarts
;      the count
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

exit_add_to_seq:
        LD A,0xff
        LD (NEXT_CHAN),A
        LD A,(SEQ_SET)
        AND A
        JP nz,exit_to_display
        LD HL,(INS_PTR)
        DEC HL
        LD A,(HL)
        CP MARK_LO
        JP c,exit_to_display
        CP MARK_HI+1
        JP nc,exit_to_display
        AND 15
        LD E,A
        LD HL,SEQ_LIST
        CP (HL)
        JP z,exit_to_display
        LD A,10
        CP (HL)
        JP nz,exit_seq_search
        LD A,E
        JP exit_seq_first

exit_seq_search:
        LD B,0x20

exit_seq_loop:
        LD A,(HL)
        CP E
        JP z,exit_seq_found
        CP 0xff
        JR z,exit_seq_insert
        INC HL
        DJNZ exit_seq_loop

; ---- exit_seq_insert: shift SEQ_LIST up one slot (31 bytes from 4186 to 4187, the last
;      entry falls off) and put the channel first
exit_seq_insert:
        LD A,E
        LD HL,0x4186
        LD (HL),0xff
        LD DE,0x4187
        LD BC,ATTR_MAGIC
        LDDR

exit_seq_first:
        LD HL,SEQ_LIST
        LD (HL),A
        JP exit_to_display

exit_seq_found:
        LD E,A
        LD (NEXT_CHAN),A

exit_to_display:
        LD SP,0x403f
        XOR A
        LD (MENU_ACTIVE),A
        LD (FORCE_BOLD),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        JP restart_display

; ---- menu_time: 17: 'TIME? ' then four digits into CLK_H10..CLK_M1 (4105-4108), hours
;      clamped to 12, then ' AM? Y/N '
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
        CALL menu_getchar
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

; ---- time_get_ampm: Y -> CLK_PM = 0, N -> FF, other keys ignored;
time_get_ampm:
        CALL menu_getchar
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
        db 0x3e,0x20,0x32,0x13,0x41

; ---- clock_last_char: the 'M' of AM/PM: CLK_RENDER_STEP back to 0 (no CLK_RENDERED /
;      forced LEFT in this ROM) and draw it without unfetching
clock_last_char:
        XOR A
        LD (CLK_RENDER_STEP),A
        LD A,(CUR_CHAR)
        JP glyph_lookup

; ---- menu_address: No prompt, no digit entry, no 0 / '*' refusal as in the NIR
menu_address:
        CALL menu_getchar
        LD (MY_ADDRESS),A
        CPL
        LD (MY_ADDRESS_INV),A
        JP editor_next_key

; ---- editor_goto_end: B3: cursor to the last text byte of the channel: demo (DA marker)
;      -> DEMO_MESSAGE_END-1, channel 9 -> STORE_END-2, else before the next marker's 03
editor_goto_end:
        LD HL,(INS_PTR)
        DEC HL
        LD A,(HL)
        CP MARK_LO
        JP c,editor_reshow
        CP MARK_HI+1
        JP nc,editor_reshow
        CP 0xda
        JR nz,gotoend_not_demo
        LD HL,DEMO_MESSAGE_END
        JR gotoend_back1

gotoend_not_demo:
        CP 0xd9
        JR nz,gotoend_next_marker
        LD HL,(STORE_END)
        JR gotoend_back2

; ---- gotoend_next_marker: chan_select of the next channel; HL -> its marker
gotoend_next_marker:
        INC A
        CALL chan_select
        AND A
        JP nz,editor_reshow
        DEC HL

gotoend_back2:
        DEC HL

gotoend_back1:
        DEC HL
        LD (STORE_CURSOR),HL

; ---- editor_reshow: cursor on a marker -> show_top_of_msg, else editor_loop.
;      cmd_B3_append also jumps here when chan_select fails (a stray path into editor code
;      with MENU_ACTIVE = 0)
editor_reshow:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,show_top_of_msg
        JP editor_loop

; ---- show_top_of_msg: 05 and after most edits: MSG_TOP_TABLE[cursor marker & 15] ('MSG 
;      n' / 'DEMO MSG') becomes the SHIFT_LABEL message
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
        LD (MENU_MSG_PTR),HL     ; MENU_MSG_PTR (410F)
        LD A,0xff
        LD (SHIFT_LABEL),A
        JP editor_loop

; ---- menu_clear_all: 03: ' CLR Y/N': Y clears the ten channels and re-selects the
;      current channel (channel 9 or the demo -> channel 0)
menu_clear_all:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STR_CLR_ALL
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        CALL menu_getchar
        AND 0x5f
        CP 'Y'
        JP nz,editor_loop
        LD HL,(INS_PTR)
        DEC HL
        LD A,(HL)
        AND 15
        CP 9
        JP c,clrall_do
        XOR A

clrall_do:
        PUSH AF
        CALL store_clear_all
        CALL store_finalize
        POP AF
        JP editor_select_chan

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
        CALL delete_chan_text
        JP show_top_of_msg

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
        JP z,pkt_process_end
        JP deltext_find_marker

deltext_move:
        LD (STORE_CURSOR),HL
        INC HL
        LD (MOVE_DST),HL
        EX DE,HL
        LD HL,(STORE_LIMIT)
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
        JP z,pkt_process_end
        DEC HL
        LD (MOVE_SRC),HL
        LD DE,(STORE_LIMIT)
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
        RET

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

; ---- editor_key_func: B7 FUNC: next key picks a second function (FUNC_PENDING).
editor_key_func:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_show_invalid
        LD A,0xff
        LD (FUNC_PENDING),A
        JP editor_loop

; ---- editor_key_bgrnd: 16 BACK: next key is the background digit (BGRND_PENDING).
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

; ---- menu_prog_msg: 09: PROG_MSG_FORCE = FF and the 'PROG? ' prompt; the next key comes
;      back here: a digit or D/d selects that channel
menu_prog_msg:
        LD A,(EDIT_KEY)
        CP 9
        JR nz,progmsg_key
        LD A,0xff
        LD (PROG_MSG_FORCE),A
        LD HL,MENU_STR_PROG_MSG
        LD (MENU_MSG_PTR),HL     ; MENU_MSG_PTR = MENU_STR_PROG_MSG
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
        JP nz,pkt_process_end
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

; ---- progmsg_other_key: 0D exits the editor, 0C cancels into SEQ?, else wait
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

; ---- menu_seq_msg: 04 SEQ?: SEQ_SET = FF; the first 04 shows the prompt (SEQ_MENU_ACTIVE
;      = F0: bit 7 dialogue open, bit 0 list cleared); later keys arrive here through
;      editor_dispatch
menu_seq_msg:
        LD A,0xff
        LD (SEQ_SET),A
        LD A,(EDIT_KEY)
        CP 4
        JR nz,seqmenu_key

; ---- seqmenu_prompt: SEQ_MENU_ACTIVE = F0, 'SEQ? ' as the
;      SHIFT_LABEL message
seqmenu_prompt:
        LD A,0xf0
        LD (SEQ_MENU_ACTIVE),A     ; SEQ_MENU_ACTIVE: bit 7 = dialogue open, bit 0 = list already cleared
        LD HL,MENU_STR_SEQ_MSG
        LD (MENU_MSG_PTR),HL     ; MENU_MSG_PTR = MENU_STR_SEQ_MSG
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

; ---- seqmenu_other_key: 0D exit, 0E clear, 09 PROG? (dialogue closed), 1F then C/c
;      enters TEST_MODE, else keep waiting
seqmenu_other_key:
        CP 13
        JP z,editor_exit
        CP 14
        JP z,editor_key_clear
        CP 9
        JR nz,seqmenu_magic_key
        LD A,0
        LD (SEQ_MENU_ACTIVE),A     ; SEQ_MENU_ACTIVE = 0
        JP menu_prog_msg

seqmenu_magic_key:
        CP 0x1f
        JR nz,seqmenu_next_key
        CALL menu_getchar
        CP 0x43
        JR z,test_mode_enter
        CP 0x63
        JR nz,seqmenu_next_key

; ---- test_mode_enter: SEQ? then MAGIC then C: TEST_MODE (4114) = FF and leave the
;      editor; seq_next_channel then shows the ROM TEST_MESSAGE directly. No ROM checksum
;      is computed or appended in this firmware
test_mode_enter:
        LD A,0xff
        LD (TEST_MODE),A
        JP editor_exit

seqmenu_next_key:
        JP editor_next_key

; ---- menu_getchar
menu_getchar:
        CALL editor_getkey
        LD A,(EDIT_KEY)
        AND A
        JR z,menu_getchar
        RET

; ---- editor_getkey: serial modes: echo the previous key if KEY_ECHO_TX is set,
;      then take RX_BYTE as the key, raw ASCII, no charset lookup. Keypad mode:
;      wait for release, then a code stable on two consecutive ticks (KEY_TIMER
;      paces the samples), 19 toggles SHIFT, else translate through
;      CHARSET_LOWER/UPPER/UPPER2/LOWER2 by SHIFT_STATE and CAPS_LOCK. No IR, no EURO
;      layer
editor_getkey:
        LD A,(INPUT_MODE)
        AND A
        JR z,getkey_wait_release
        LD A,(KEY_ECHO_TX)
        AND A
        JR z,getkey_serial
        CALL tx_send_byte

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
        LD DE,(STORE_LIMIT)
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

; ---- editor_insert: insert EDIT_KEY at the cursor (' MEM FULL ' / ' 100 LEFT '); the
;      LDDR shifts everything up to STORE_LIMIT (as in the NIR, bug B8)
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
        LD DE,(STORE_LIMIT)
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
        LD HL,(STORE_LIMIT)
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
        LD DE,(STORE_WARN_LIMIT)
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
        LD DE,(STORE_LIMIT)
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

; ---- editor_translate_key: apply the GRAPH/COLOR/BGRND/SPEED/FUNC prefixes
editor_translate_key:
        CALL apply_graph_prefix
        CALL apply_color_prefix
        CALL apply_speed_prefix
        CALL editor_key_to_attr
        CALL editor_query_hook
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

; ---- editor_key_to_attr: FUNC (B7) second functions in this ROM: GRAPH -> B8 DRAW, NORM
;      -> B9 THIN, BOLD -> BA WAIT, FLASH -> B0 REM; anything else cancels. No HALT,
;      RAINBOW, TINY, ADDRESS or ?/! functions
editor_key_to_attr:
        LD A,(FUNC_PENDING)
        AND A
        RET z
        XOR A
        LD (FUNC_PENDING),A
        LD A,(EDIT_KEY)
        LD C,ATTR_DRAW
        CP ATTR_GRAPH
        JR z,func_store
        INC C
        CP 0x11
        JR z,func_store
        INC C
        CP 0x12
        JR z,func_store
        LD C,0xb0
        CP 0x14
        JR z,func_store
        POP HL
        POP HL
        JP editor_loop

func_store:
        LD A,C
        LD (EDIT_KEY),A
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

; ---- FG_IDX_TABLE: cmd 15 n / COLOR n: six foreground codes (red, orange, yellow, lime,
;      green, black); index 6 is clamped to 2, n = 0 reads FG_IDX_TABLE+0xFF (EE)
FG_IDX_TABLE:
        db 0x8c,0x8d,0x8f,0x87,0x83,0x80

; ---- BG_IDX_TABLE: cmd 16 n / BACK n: six background codes; index 6 -> 5
BG_IDX_TABLE:
        db 0x91,0x93,0x93,0x93,0x92,0x90

; ---- editor_redraw: redraw the editor view: the 15 bytes before the cursor (LD
;      DE,0x000F, not restart_display) with attribute labels from ATTR_LABEL_TABLE, then
;      the status labels and any pending message
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
        LD A,(MAGIC_MSG_CHAN)
        AND A
        JP nz,redraw_status
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JP z,redraw_status

redraw_window:
        LD DE,15     ; 15 bytes before the cursor fit the 59-column panel (the NIR shows 21)
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
        LD A,(REDRAW_MAGIC)
        AND A
        JP z,redraw_char_check
        XOR A
        LD (FORCE_BOLD),A
        JP redraw_char_check

; ---- redraw_classify: bit 7 -> redraw_high_byte; bits 5,6 clear -> attribute; else
;      printable
redraw_classify:
        BIT 7,A
        JP nz,redraw_high_byte
        AND 0x60
        JR z,redraw_attr
        JP redraw_char_check

; ---- redraw_high_byte: A0-AF are drawn as graphics; 80-FF otherwise go to the label
;      lookup (the CP 90 after CP 80 can never match: dead REDRAW_MAGIC clear)
redraw_high_byte:
        LD A,(CUR_CHAR)
        AND 0xf0
        CP 0xa0
        JP z,redraw_char_check
        CP 0x80
        JR nz,redraw_attr
        CP 0x90
        JR nz,redraw_attr
        XOR A
        LD (REDRAW_MAGIC),A

; ---- redraw_attr: movement attributes force bold (unless THIN), 18 clears it, 11-14/10
;      track the font, B9 THIN, 1F MAGIC; then the label
redraw_attr:
        LD A,(CUR_CHAR)

redraw_attr2:
        CP 15
        JP z,redraw_fx_attr
        CP ATTR_PAUSE
        JP z,redraw_fx_attr
        CP ATTR_UP
        JP z,redraw_fx_attr
        CP ATTR_DOWN
        JP z,redraw_fx_attr
        CP ATTR_LEFT
        JP z,redraw_left_attr
        CP ATTR_NORM
        JP nz,redraw_flash
        XOR A
        LD (FLASH_BIT),A
        LD (FONT_MODE),A
        LD (REDRAW_MAGIC),A
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
        XOR A
        LD (REDRAW_MAGIC),A
        JR redraw_label_check

redraw_bold:
        CP 0x12
        JP nz,redraw_big
        LD A,(FONT_MODE)
        SET 1,A
        RES 3,A
        LD (FONT_MODE),A
        XOR A
        LD (REDRAW_MAGIC),A
        JR redraw_label_check

redraw_big:
        CP 0x10
        JP nz,redraw_not_big
        LD A,(FONT_MODE)
        SET 1,A
        SET 3,A
        LD (FONT_MODE),A
        XOR A
        LD (REDRAW_MAGIC),A
        JP redraw_label_check

; ---- redraw_not_big: B9 THIN: THIN_MODE = FF, no bold
redraw_not_big:
        CP ATTR_THIN
        JP nz,redraw_magic
        LD A,0xff
        LD (THIN_MODE),A
        XOR A
        LD (FORCE_BOLD),A
        JP redraw_label_check

; ---- redraw_magic: 1F: REDRAW_MAGIC = FF; anything else just gets its label
redraw_magic:
        CP 0x1f
        JP nz,redraw_label_check
        LD A,0xff
        LD (REDRAW_MAGIC),A
        JP redraw_label_check

redraw_fx_attr:
        LD A,(THIN_MODE)
        AND A
        JP nz,redraw_label_check
        LD A,0xff
        LD (FORCE_BOLD),A
        JP redraw_label_check

redraw_left_attr:
        LD A,0
        LD (FORCE_BOLD),A

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

; ---- redraw_show_label: ATTR_LABEL_TABLE[CUR_CHAR]; 80-9F index on into COLOR_NAME_TABLE,
;      B0-BF ATTR_LABEL_TABLE_B0, F0-F7 SPEED_STR_TABLE; rendered in tiny mode
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
        JP status_show

status_not_graph:
        LD A,(COLOR_PENDING)
        OR A
        JR z,status_not_color
        LD HL,STR_COLOR
        JP status_show

status_not_color:
        LD A,(BGRND_PENDING)
        OR A
        JR z,status_not_bgrnd
        LD HL,STR_BGRND
        JP status_show

status_not_bgrnd:
        LD A,(FUNC_PENDING)
        OR A
        JR z,status_not_func
        LD HL,STR_FUNC
        JP status_show

status_not_func:
        LD A,(SPEED_PENDING)
        OR A
        JP z,status_not_speed
        LD HL,STR_SPEED
        JP status_show

status_not_speed:
        LD A,(MAGIC_MSG_CHAN)
        OR A
        JP z,status_shift_msg
        AND 15
        SLA A
        LD E,A
        LD D,0
        LD IX,MAGIC_MSG_TABLE
        ADD IX,DE
        LD L,(IX+0)
        LD H,(IX+1)
        XOR A
        LD (MAGIC_MSG_CHAN),A
        JP status_show

; ---- MAGIC_MSG_TABLE: ten pointers to the 'MSG n  <MAGIC>' strings at 212D, 15 bytes
;      apart, indexed by MAGIC_MSG_CHAN & 15 on the redraw after magic_new_message
MAGIC_MSG_TABLE:
        db "-!<!K!Z!i!x!",0x87,"!",0x96,"!",0xa5,"!",0xb4,"!"

; ---- STR_MAGIC_MSG: 'MSG 0  <MAGIC>' .. 'MSG 9  <MAGIC>', NUL-terminated
STR_MAGIC_MSG:
        db "MSG 0  <MAGIC>",0x00
        db "MSG 1  <MAGIC>",0x00,"MSG 2  <MAGIC>",0x00,"MSG 3  <MAGIC>",0x00,"MSG 4  <MAGIC>",0x00
        db "MSG 5  <MAGIC>",0x00,"MSG 6  <MAGIC>",0x00,"MSG 7  <MAGIC>",0x00,"MSG 8  <MAGIC>",0x00
        db "MSG 9  <MAGIC>",0x00

status_show:
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

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

; ---- menu_show_text: Render the NUL-terminated string at MENU_TEXT_PTR with TINY_MODE set
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

; ---- fb_rewind_window: FB_COL = FB_COLPTR - 60 (ring wrap)
fb_rewind_window:
        LD HL,(FB_COLPTR)
        LD DE,0x003c
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

; ---- pkt_process_end
pkt_process_end:
        JP RESET

; ---- pkt_process: process a received packet: SP reset, wait for TX idle, DI, blank the
;      rows, seat STORE_CURSOR/INS_PTR on the current channel marker, then walk PKT_BUF:
;      IGNORE_TABLE bytes skipped, commands 02 03 04 09 0D 0E 15 16 17 1E B3 B4, anything
;      else inserted as text. Entered from main_entry, wait_poll, or straight out of the
;      ISR (pkt_immediate)
pkt_process:
        LD SP,0x403f

pkt_wait_tx:
        LD A,(TX_STATUS)
        AND 3
        JR nz,pkt_wait_tx
        DI
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JR nz,pkt_find_marker
        DEC HL

; ---- pkt_cursor_set: cursor was on a marker: step back one before scanning
pkt_cursor_set:
        LD (STORE_CURSOR),HL

; ---- pkt_find_marker
pkt_find_marker:
        PUSH HL
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        PUSH HL
        POP BC
        POP HL
        DEC HL

pkt_marker_loop:
        LD A,(HL)
        AND 0xf0
        CP 0xd0
        JR nz,pkt_marker_back
        LD A,(HL)
        CP 0xd0
        JR c,pkt_marker_back
        CP 0xdb
        JR c,pkt_set_ins

; ---- pkt_marker_back: no marker before MSG_STORE -> RESET
pkt_marker_back:
        DEC HL
        DEC BC
        LD A,C
        OR B
        JR nz,pkt_marker_loop
        JP pkt_process_end

; ---- pkt_set_ins: STORE_CURSOR = marker, INS_PTR = text, store_finalize, then PKT_LEN
;      (47F4) bytes of PKT_BUF
pkt_set_ins:
        LD (STORE_CURSOR),HL
        INC HL
        LD (INS_PTR),HL
        CALL store_finalize
        LD A,(PKT_LEN)
        AND A
        JP z,pkt_process_done
        LD B,A
        LD HL,PKT_BUF

pkt_byte_loop:
        LD A,(HL)
        PUSH HL
        PUSH BC
        LD (CUR_CHAR),A
        CALL is_ignored_byte
        AND A
        JP z,pkt_next
        CP CMD_SPEED
        JP z,cmd_02_speed
        CP CMD_CLEAR_ALL
        JP z,cmd_03_clear_all
        CP CMD_SEQUENCE
        JP z,cmd_04_sequence
        CP CMD_CHANNEL
        JP z,cmd_09_channel
        CP CMD_END
        JP z,pkt_process_done
        CP CMD_DELETE_TEXT
        JP z,cmd_0E_delete_text
        CP CMD_FORE_IDX
        JP z,cmd_15_fore_idx
        CP CMD_BACK_IDX
        JP z,cmd_16_back_idx
        CP CMD_SET_TIME
        JP z,cmd_17_set_time
        CP CMD_COLOR_A0
        JP z,cmd_1E_color_A0
        CP CMD_APPEND
        JP z,cmd_B3_append
        CP CMD_QUERY
        JP z,cmd_B4_query

; ---- pkt_insert_text: Insert CUR_CHAR at STORE_CURSOR (shifts the store up; refuses when CHAN_LOCK or memory full)
pkt_insert_text:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,pkt_next
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JR nz,pkt_ins_check_full
        DEC HL
        LD (STORE_CURSOR),A

pkt_ins_check_full:
        LD HL,(STORE_END)
        INC HL
        LD (STORE_TMP),HL
        LD DE,(STORE_LIMIT)
        OR A
        SBC HL,DE
        LD A,H
        OR L
        JR z,pkt_next
        LD HL,(STORE_TMP)
        LD (STORE_END),HL
        CALL store_make_room
        LD HL,(STORE_LIMIT)
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

pkt_next:
        POP BC
        POP HL
        INC HL
        DEC B
        JP nz,pkt_byte_loop

; ---- pkt_process_done: clear PKT_READY/PKT_STATE, re-init and return to main loop
pkt_process_done:
        LD SP,0x403f
        XOR A
        LD (PKT_READY),A
        LD (PKT_STATE),A
        LD (MENU_ACTIVE),A
        LD (FORCE_BOLD),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        CALL shift_chain_clear
        JP restart_display

; ---- shift_chain_clear: clock a row's worth of zeros through port 40, strobe
shift_chain_clear:
        LD B,FRAME_COLS-1
        XOR A

chainclr_loop:
        OUT (PORT_40_OUT),A
        DJNZ chainclr_loop
        OUT (PORT_STROBE),A
        RET

; ---- cmd_03_clear_all: 03: reset the ten channels, then re-select the current channel (9
;      or the demo -> 0) through select_chan_common
cmd_03_clear_all:
        LD HL,(INS_PTR)
        DEC HL
        LD A,(HL)
        AND 15
        CP 9
        JP c,clrall_select
        XOR A

clrall_select:
        PUSH AF
        CALL store_clear_all
        CALL store_finalize
        POP AF
        JP select_chan_common

; ---- cmd_0E_delete_text: delete existing text of the selected channel (from INS_PTR to its 0x03 terminator)
cmd_0E_delete_text:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,pkt_next
        LD HL,(INS_PTR)
        DEC HL
        LD (STORE_CURSOR),HL
        INC HL
        LD (MOVE_DST),HL
        EX DE,HL
        LD HL,(STORE_LIMIT)
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
        JP z,pkt_next
        DEC HL
        LD (MOVE_SRC),HL
        LD DE,(STORE_LIMIT)
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
        JP pkt_next

; ---- cmd_B4_query: B4 n: '0' ROM id, '1' memory, '2' remarks, '3' dump, each with
;      interrupts on so the bit engines run; then wait for TX idle. The NIR's B1 stack
;      overflow is unlikely to apply: this ISR saves registers with EXX instead of pushes,
;      so an interrupt frame is about 10 bytes [M]
cmd_B4_query:
        CALL clear_framebuf
        CALL shift_chain_clear
        EI
        CALL pkt_next_byte
        CP QUERY_ROMID
        CALL z,query_0_romid
        CP QUERY_MEMORY
        CALL z,query_1_memory
        CP QUERY_NOP
        CALL z,query_2_remarks
        CP QUERY_DUMP
        CALL z,query_3_dump

query_wait_tx:
        LD A,(TX_STATUS)
        AND 3
        JR nz,query_wait_tx
        DI
        JP z,pkt_next

; ---- cmd_1E_color_A0: 1E n -> insert 0xA0|(n&15)
cmd_1E_color_A0:
        CALL pkt_next_byte
        AND 15
        OR GRAPH_BASE
        LD (CUR_CHAR),A
        JP pkt_insert_text

; ---- cmd_15_fore_idx: 15 n -> insert FG_IDX_TABLE[n]
cmd_15_fore_idx:
        CALL pkt_next_byte
        AND 7
        DEC A
        CP 6
        JR nz,fore_idx_lookup
        LD A,2

fore_idx_lookup:
        NOP
        LD HL,FG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (CUR_CHAR),A
        JP pkt_insert_text

; ---- cmd_16_back_idx: 16 n -> insert BG_IDX_TABLE[n]
cmd_16_back_idx:
        CALL pkt_next_byte
        AND 7
        DEC A
        CP 6
        JR nz,back_idx_lookup
        LD A,5

back_idx_lookup:
        NOP
        LD HL,BG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (CUR_CHAR),A
        JP pkt_insert_text

; ---- cmd_17_set_time: 17 h h m m a: four ASCII digits -> 4105..4108 (H10 H1 M10 M1),
;      then a = 'A'/'a' -> AM, anything else PM (the NIR uses Y/y). CLK_RUN is cleared
;      first and restored only at the end, so a short packet stops the clock (the NIR's
;      bug B2). NMI_COUNT is not reset
cmd_17_set_time:
        XOR A
        LD (CLK_RUN),A
        LD HL,CLK_H10
        LD B,4

settime_digits:
        CALL pkt_next_byte
        LD (CUR_CHAR),A
        AND 15
        LD (HL),A
        INC HL
        DJNZ settime_digits
        CALL pkt_next_byte
        AND 0x5f
        CP 0x41
        LD A,0xff
        JR nz,settime_store_pm
        XOR A

settime_store_pm:
        LD (CLK_PM),A
        LD A,0xff
        LD (CLK_RUN),A
        JP pkt_next

; ---- pkt_next_byte: Fetch next payload byte (A); if none left, jump to pkt_process_done
pkt_next_byte:
        POP IX
        POP DE
        POP IY
        INC IY
        DEC D
        JP z,pkt_process_done
        LD A,(IY+0)
        PUSH IY
        PUSH DE
        PUSH IX
        RET

; ---- cmd_02_speed: 02 n -> insert 0xF0|(n&7)
cmd_02_speed:
        CALL pkt_next_byte
        AND 7
        OR SPEED_BASE
        LD (CUR_CHAR),A
        JP pkt_insert_text

; ---- cmd_B3_append: B3: STORE_CURSOR to the last text byte of the channel: demo ->
;      DEMO_MESSAGE_END-1, channel 9 -> STORE_END-2, else before the next marker's 03. If
;      chan_select fails it jumps into editor_reshow
cmd_B3_append:
        LD HL,(INS_PTR)
        DEC HL
        LD A,(HL)
        CP 0xda
        JR nz,append_not_demo
        LD HL,DEMO_MESSAGE_END
        JR append_back1

append_not_demo:
        CP 0xd9
        JR nz,append_next_marker
        LD HL,(STORE_END)
        JR append_back2

; ---- append_next_marker: chan_select of the next channel, HL -> its marker
append_next_marker:
        INC A
        CALL chan_select
        AND A
        JP nz,editor_reshow
        DEC HL

append_back2:
        DEC HL

append_back1:
        DEC HL
        LD (STORE_CURSOR),HL
        JP pkt_next

; ---- cmd_09_channel: 09 c: ONE byte: digit '0'-'9' or 'D'/'d' (demo = 10); any other
;      byte ends the command. The NIR takes two digits
cmd_09_channel:
        CALL pkt_next_byte
        CP 0x44
        JR z,chan_cmd_value
        CP 0x64
        JR z,chan_cmd_value
        CP 0x3a
        JP nc,pkt_next
        CP 0x30
        JP c,pkt_next

; ---- chan_cmd_value: D/d -> 10
chan_cmd_value:
        LD (CUR_CHAR),A
        AND 0x5f
        CP 0x44
        JR nz,select_chan_common
        LD A,10

; ---- select_chan_common: A & 15 = channel: chan_select (its error return is not
;      checked), INS_PTR = text, STORE_CURSOR = marker, CHAN_STATE[n] = FF (CHAN_LOCK for
;      10)
select_chan_common:
        AND 15
        LD E,A
        OR 0xd0
        CALL chan_select
        LD (INS_PTR),HL
        DEC HL
        LD (STORE_CURSOR),HL
        PUSH DE
        CALL clear_chan_lock
        POP DE
        LD D,0
        LD HL,CHAN_STATE
        ADD HL,DE
        LD A,0xff
        LD (HL),A
        JP pkt_next

; ---- cmd_04_sequence: 04 c c ... : rebuild SEQ_LIST, one byte per channel ('0'-'9',
;      'D'/'d' = demo), FF after the last; a non-digit ends it. The prefill is A0..A9 then
;      FF: a 04 with no digits leaves an invalid list that init_sequence resets to the
;      default 0-9
cmd_04_sequence:
        LD HL,SEQ_LIST
        LD C,10
        LD B,0x20
        LD A,0xa0

seq_fill_loop:
        LD (HL),A
        INC HL
        INC A
        DEC C
        JR nz,seq_fill_next
        INC C
        LD A,0xff

seq_fill_next:
        DJNZ seq_fill_loop
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        LD B,0x20

seq_digit_loop:
        CALL pkt_next_byte
        LD (CUR_CHAR),A
        CP 0x44
        JR z,seq_digit_demo
        CP 0x64
        JR z,seq_digit_demo
        CP 0x3a
        JP nc,pkt_next
        CP 0x30
        JP c,pkt_next
        JR seq_digit_store

seq_digit_demo:
        LD A,10

seq_digit_store:
        AND 15
        LD (HL),A
        INC HL
        LD A,0xff
        LD (HL),A
        DJNZ seq_digit_loop
        JP pkt_next

; ---- is_ignored_byte: Z (A=0) if A is in IGNORE_TABLE: 00 01 05 08 0A 0B 0C 1C 1D 7F
is_ignored_byte:
        LD HL,IGNORE_TABLE
        LD BC,10
        CPIR
        DEC HL
        CP (HL)
        RET nz
        XOR A
        RET

; ---- IGNORE_TABLE: payload bytes skipped by pkt_process: 00 01 05 08 0A 0B 0C 1C 1D 7F,
;      plus a 00 pad
IGNORE_TABLE:
        db 0x00,0x01,0x05,0x08,0x0a,0x0b,0x0c,0x1c,0x1d,0x7f
        db 0x00

; ---- ATTR_LABEL_TABLE: editor label per attribute byte 00-1F (0 = none). This ROM's own
;      names: 01 SPEED, 03 END, 04 SEQ?, 06 PAUSE (the NIR's HALT), 07 BEEP, 09 PROG?, 0F
;      BCRAWL (RIGHT), 10 BIG, 11 NORM, 12 BOLD, 13 ITALIC, 14 FLASH, 15 FORE, 16 BACK, 18
;      CRAWL (LEFT), 19 JUMP (PAUSE), 1A UP, 1B DOWN, 1D SHIFT, 1E GRAPH, 1F MAGIC
ATTR_LABEL_TABLE:
        dw 0
        dw STR_SPEED                                 ; 01  .SPEED
        dw 0
        dw STR_END                                   ; 03  .END.
        dw MENU_STR_SEQ_MSG                          ; 04  SEQ?
        dw 0
        dw STR_PAUSE
        dw STR_BEEP                                  ; 07  .BEEP.
        dw 0
        dw MENU_STR_PROG_MSG                         ; 09  PROG?
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw STR_BCRAWL
        dw STR_BIG                                   ; 10  .BIG.
        dw STR_NORM                                  ; 11  .NORM.
        dw STR_BOLD                                  ; 12  .BOLD.
        dw STR_ITALIC                                ; 13  .ITALIC.
        dw STR_FLASH                                 ; 14  .FLASH.
        dw STR_COLOR                                 ; 15  .FORE
        dw STR_BGRND                                 ; 16  .BACK
        dw 0
        dw STR_CRAWL
        dw STR_JUMP
        dw STR_UP                                    ; 1a  .UP.
        dw STR_DOWN                                  ; 1b  .DOWN.
        dw 0
        dw STR_SHIFT                                 ; 1d  .SHIFT.
        dw STR_GRAPH                                 ; 1e  .GRAPH
        dw STR_MAGIC                                 ; 1f  .MAGIC.

; ---- MSG_TOP_STRINGS: 'MSG  0' .. 'MSG  9' at 25B5 + 16n, zero-padded (seven zero bytes
;      lead the first), then 'DEMO MSG' at 264E; pointed to by MSG_TOP_TABLE
MSG_TOP_STRINGS:
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  0",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  1",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  2",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  3",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  4",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  5",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  6",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  7",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  8",0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db 0x00
        db "MSG  9",0x00
        db 0x00
        db 0x00
        db "DEMO MSG",0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00

STR_BEEP:
        db "<BEEP>",0x00

; ---- STR_BCRAWL: '<BCRAWL>', the label of 0F (the NIR's RIGHT)
STR_BCRAWL:
        db "<BCRAWL>",0x00

; ---- COLOR_NAME_TABLE: 16 foreground names (283E..) for 80-8F, then the four background
;      names B-BLK B-RED B-GRE B-YEL repeated four times for 90-9F
COLOR_NAME_TABLE:
        dw STR_C_BLACK                               ; 00  .BLACK.
        dw 0x2846
        dw 0x284e
        dw 0x2856
        dw 0x285e
        dw 0x2866
        dw 0x286e
        dw 0x2876
        dw 0x287d
        dw 0x2885
        dw 0x288d
        dw 0x2895
        dw 0x289d
        dw 0x28a3
        dw 0x28ac
        dw 0x28b4
        dw STR_B_BLK                                 ; 10  .B-BLK.
        dw STR_B_RED                                 ; 11  .B-RED.
        dw STR_B_GRE                                 ; 12  .B-GRE.
        dw STR_B_YEL                                 ; 13  .B-YEL.
        dw STR_B_BLK                                 ; 14  .B-BLK.
        dw STR_B_RED                                 ; 15  .B-RED.
        dw STR_B_GRE                                 ; 16  .B-GRE.
        dw STR_B_YEL                                 ; 17  .B-YEL.
        dw STR_B_BLK                                 ; 18  .B-BLK.
        dw STR_B_RED                                 ; 19  .B-RED.
        dw STR_B_GRE                                 ; 1a  .B-GRE.
        dw STR_B_YEL                                 ; 1b  .B-YEL.
        dw STR_B_BLK                                 ; 1c  .B-BLK.
        dw STR_B_RED                                 ; 1d  .B-RED.
        dw STR_B_GRE                                 ; 1e  .B-GRE.
        dw STR_B_YEL                                 ; 1f  .B-YEL.

STR_B_BLK:
        db "<B-BLK>",0x00

STR_B_RED:
        db "<B-RED>",0x00

STR_B_YEL:
        db "<B-YEL>",0x00

STR_B_GRE:
        db "<B-GRE>",0x00

; ---- ATTR_LABEL_TABLE_B0: labels for B0-BF: B0 REM, B8 DRAW, B9 THIN, BA WAIT only; no
;      HOLD, RAINBOW, MAGIC OFF or TINY in this ROM
ATTR_LABEL_TABLE_B0:
        dw STR_REM                                   ; b0  .REM.
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw STR_DRAW                                  ; b8  .DRAW.
        dw STR_THIN                                  ; b9  .THIN.
        dw STR_WAIT                                  ; ba  .WAIT.
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0

STR_ITALIC:
        db "<ITALIC>",0x00

STR_FLASH:
        db "<FLASH>",0x00

STR_END:
        db "<END>",0x00
        db 0x00

; ---- STR_CRAWL: '<CRAWL>', the label of 18 (the NIR's LEFT)
STR_CRAWL:
        db "<CRAWL>",0x00

; ---- MSG_TOP_TABLE: 32 pointers indexed by channel: 'MSG  0'..'MSG  9', 'DEMO MSG', then
;      zeros; show_top_of_msg puts the entry into MENU_MSG_PTR
MSG_TOP_TABLE:
        dw 0x25b5
        dw 0x25c5
        dw 0x25d5
        dw 0x25e5
        dw 0x25f5
        dw 0x2605
        dw 0x2615
        dw 0x2625
        dw 0x2635
        dw 0x2645
        dw 0x264e
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

; ---- SPEED_STR_TABLE: pointers to '<S0>'..'<S7>' (28BD..28E0)
SPEED_STR_TABLE:
        dw STR_SPEED_0                               ; 00  .S0.
        dw 0x28c2
        dw 0x28c7
        dw 0x28cc
        dw 0x28d1
        dw 0x28d6
        dw 0x28db
        dw 0x28e0

; ---- STR_COLOR: ' <FORE', the 15 COLOR key's label in this ROM
STR_COLOR:
        db " <FORE",0x00

; ---- STR_BGRND: ' <BACK', the 16 BGRND key's label in this ROM
STR_BGRND:
        db " <BACK",0x00

STR_NORM:
        db "<NORM>",0x00

STR_BOLD:
        db "<BOLD>",0x00

STR_DRAW:
        db "<DRAW>",0x00

STR_THIN:
        db "<THIN>",0x00

STR_WAIT:
        db "<WAIT>",0x00

STR_FUNC:
        db "<FUNC",0x00

STR_REM:
        db "<REM>",0x00

STR_BIG:
        db "<BIG>",0x00

STR_SHIFT:
        db "<SHIFT>",0x00

; ---- STR_JUMP: '<JUMP>', the label of 19 (the NIR's PAUSE)
STR_JUMP:
        db "<JUMP>",0x00

STR_UP:
        db "<UP>",0x00

STR_DOWN:
        db "<DOWN>",0x00

STR_SPEED:
        db "<SPEED ",0x00

; ---- STR_PAUSE: '<PAUSE>', the label of 06 (the NIR's HALT)
STR_PAUSE:
        db "<PAUSE>",0x00

STR_GRAPH:
        db "<GRAPH ",0x00

STR_MAGIC:
        db "<MAGIC>",0x00

; ---- MENU_STR_CLR_MEM
MENU_STR_CLR_MEM:
        db " CLR MEM?",0x00

; ---- MENU_STR_CLR_ALL: ' CLR Y/N'
MENU_STR_CLR_ALL:
        db " CLR Y/N",0x00

MENU_STR_TIME:
        db "TIME? ",0x00

; ---- MENU_STR_AM_PM
MENU_STR_AM_PM:
        db " AM? Y/N ",0x00

; ---- MENU_STR_PROG_MSG
MENU_STR_PROG_MSG:
        db "PROG? ",0x00

; ---- MENU_STR_SEQ_MSG: 'SEQ? '
MENU_STR_SEQ_MSG:
        db "SEQ? ",0x00

; ---- MENU_STR_INVALID: 03,'  INVALID ',00: the leading byte is skipped when shown
;      through MENU_MSG_FLAG (+1) and drawn as glyph 03 when shown as the SHIFT_LABEL
;      message
MENU_STR_INVALID:
        db 0x03,"  INVALID  ",0x00

; ---- MENU_STR_MEM_FULL: 0A,' MEM FULL ',00
MENU_STR_MEM_FULL:
        db 0x0a," MEM FULL ",0x00

; ---- MENU_STR_100_KEYS: 05,' 100 LEFT ',00
MENU_STR_100_KEYS:
        db 0x05," 100 LEFT ",0x00

; ---- MENU_STR_SEQ_FULL: 03,' SEQ FULL ',00
MENU_STR_SEQ_FULL:
        db 0x03," SEQ FULL ",0x00

; ---- STR_C_BLACK: the 16 foreground color names '<BLACK>' '<D-GRE>' '<M-GRE>' '<GREEN>'
;      '<D-RED>' '<D-YEL>' '<D-LIM>' '<LIME>' '<M-RED>' '<D-ORA>' '<M-YEL>' '<LEMON>'
;      '<RED>' '<ORANGE>' '<AMBER>' '<YELLOW>' (283E..28BC, AMBER where the NIR says
;      GOLD), then '<S0>'..'<S7>' at 28BD..28E4
STR_C_BLACK:
        db "<BLACK>",0x00
        db "<D-GRE>",0x00,"<M-GRE>",0x00,"<GREEN>",0x00,"<D-RED>",0x00,"<D-YEL>",0x00,"<D-LIM>",0x00,"<LIME>",0x00,"<M-RE"
        db "D>",0x00,"<D-ORA>",0x00,"<M-YEL>",0x00,"<LEMON>",0x00,"<RED>",0x00,"<ORANGE>",0x00,"<AMBER>",0x00,"<YELLOW>",0x00

; ---- STR_SPEED_0: '<S0>'..'<S7>', five bytes each, for SPEED_STR_TABLE
STR_SPEED_0:
        db "<S0>",0x00
        db "<S1>",0x00,"<S2>",0x00,"<S3>",0x00,"<S4>",0x00,"<S5>",0x00,"<S6>",0x00,"<S7>",0x00

; ---- FONT: 128 glyphs x 8 bytes (seven column bytes + width), 28E5-2CE4, indexed
;      directly by the byte value (glyph_lookup has no char_to_glyph): 00-0F are the A0-AF
;      graphics. everything from here to 2CE4 is glyph data, not instructions
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
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  24 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  25 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  26 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  27 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  28 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  29 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  30 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01   ; glyph  31 width 1
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x06
        db 0x5f,0x00,0x00,0x00,0x00,0x00,0x00,0x04   ; glyph  33 width 4
        db 0x07,0x00,0x07,0x00,0x00,0x00,0x00,0x03   ; glyph  34 width 3
        db 0x14,0x7f,0x14,0x7f,0x14,0x00,0x00,0x05   ; glyph  35 width 5
        db 0x26,0x49,0x7f,0x49,0x32,0x00,0x00,0x05   ; glyph  36 width 5
        db 0x42,0x25,0x12,0x08,0x24,0x52,0x21,0x07   ; glyph  37 width 7
        db 0x36,0x49,0x49,0x56,0x20,0x50,0x00,0x06   ; glyph  38 width 6
        db 0x07,0x00,0x00,0x00,0x00,0x00,0x00,0x01   ; glyph  39 width 1
        db 0x1c,0x22,0x41,0x00,0x00,0x00,0x00,0x03   ; glyph  40 width 3
        db 0x41,0x22,0x1c,0x00,0x00,0x00,0x00,0x03   ; glyph  41 width 3
        db 0x2a,0x1c,0x7f,0x1c,0x2a,0x00,0x00,0x05   ; glyph  42 width 5
        db 0x08,0x08,0x3e,0x08,0x08,0x00,0x00,0x05   ; glyph  43 width 5
        db 0x40,0x30,0x30,0x00,0x00,0x00,0x00,0x03   ; glyph  44 width 3
        db 0x08,0x08,0x08,0x08,0x00,0x00,0x00,0x04   ; glyph  45 width 4
        db 0x60,0x60,0x00,0x00,0x00,0x00,0x00,0x04   ; glyph  46 width 4
        db 0x40,0x20,0x10,0x08,0x04,0x02,0x01,0x07   ; glyph  47 width 7
        db 0x3e,0x51,0x49,0x45,0x3e,0x00,0x00,0x05
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
        db 0x40,0x6c,0x6c,0x00,0x00,0x00,0x00,0x03   ; glyph  59 width 3
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
        db 0x60,0x5e,0x55,0x55,0x41,0x02,0x00,0x06   ; glyph  96 width 6
        db 0x20,0x54,0x54,0x54,0x78,0x00,0x00,0x05   ; glyph  97 width 5
        db 0x7f,0x44,0x44,0x44,0x38,0x00,0x00,0x05   ; glyph  98 width 5
        db 0x38,0x44,0x44,0x44,0x44,0x00,0x00,0x05   ; glyph  99 width 5
        db 0x38,0x44,0x44,0x44,0x7f,0x00,0x00,0x05   ; glyph 100 width 5
        db 0x38,0x54,0x54,0x54,0x58,0x00,0x00,0x05   ; glyph 101 width 5
        db 0x08,0x7e,0x09,0x02,0x00,0x00,0x00,0x04   ; glyph 102 width 4
        db 0x4c,0x52,0x52,0x52,0x3c,0x00,0x00,0x05
        db 0x7f,0x04,0x04,0x04,0x78,0x00,0x00,0x05   ; glyph 104 width 5
        db 0x7a,0x00,0x00,0x00,0x00,0x00,0x00,0x01   ; glyph 105 width 1
        db 0x40,0x40,0x3d,0x00,0x00,0x00,0x00,0x03
        db 0x7f,0x10,0x28,0x44,0x00,0x00,0x00,0x04   ; glyph 107 width 4
        db 0x7f,0x00,0x00,0x00,0x00,0x00,0x00,0x01   ; glyph 108 width 1
        db 0x78,0x04,0x18,0x04,0x78,0x00,0x00,0x05   ; glyph 109 width 5
        db 0x7c,0x08,0x04,0x04,0x78,0x00,0x00,0x05   ; glyph 110 width 5
        db 0x38,0x44,0x44,0x44,0x38,0x00,0x00,0x05   ; glyph 111 width 5
        db 0x7e,0x12,0x12,0x0c,0x00,0x00,0x00,0x04
        db 0x0c,0x12,0x12,0x7e,0x00,0x00,0x00,0x04
        db 0x7c,0x08,0x04,0x04,0x08,0x00,0x00,0x05   ; glyph 114 width 5
        db 0x48,0x54,0x54,0x54,0x24,0x00,0x00,0x05   ; glyph 115 width 5
        db 0x04,0x3f,0x44,0x00,0x00,0x00,0x00,0x03   ; glyph 116 width 3
        db 0x3c,0x40,0x40,0x40,0x3c,0x00,0x00,0x05   ; glyph 117 width 5
        db 0x0c,0x30,0x40,0x30,0x0c,0x00,0x00,0x05   ; glyph 118 width 5
        db 0x3c,0x40,0x30,0x40,0x3c,0x00,0x00,0x05   ; glyph 119 width 5
        db 0x44,0x28,0x10,0x28,0x44,0x00,0x00,0x05   ; glyph 120 width 5
        db 0x4c,0x50,0x50,0x3c,0x00,0x00,0x00,0x04
        db 0x44,0x64,0x54,0x4c,0x44,0x00,0x00,0x05   ; glyph 122 width 5
        db 0x08,0x36,0x41,0x00,0x00,0x00,0x00,0x03   ; glyph 123 width 3
        db 0x40,0x40,0x40,0x40,0x40,0x00,0x00,0x05   ; glyph 124 width 5
        db 0x41,0x36,0x08,0x00,0x00,0x00,0x00,0x03   ; glyph 125 width 3
        db 0x08,0x04,0x08,0x04,0x00,0x00,0x00,0x04   ; glyph 126 width 4
        db 0x08,0x08,0x08,0x08,0x2a,0x1c,0x08,0x07   ; glyph 127 width 7

; ---- CHAR_FLAGS: 256 bytes indexed by character code, 2CE5-2DE4: bit 0 tested by
;      store_fix_bad_bytes (byte -> ?). Follows the 128-glyph FONT directly
CHAR_FLAGS:
        db 0x07,0x07,0x07,0x00,0x07,0x07,0x00,0x00,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; char 20-2f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; char 30-3f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; char 40-4f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; char 50-5f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; char 60-6f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; char 70-7f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; char a0-af
        db 0x00,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07

; ---- CHARSET_LOWER: keypad code 00-3F -> character, unshifted, caps off; the same four
;      tables as the NET, indexed by the raw key code (no IR table)
CHARSET_LOWER:
        db "kf",0x12,"pa",0x0e,0x11,0x1e             ; 00-07  k f BOLD p a 0E NORM GRAPH
        db " ",0x7f,")%zwyt"                         ; 08-0f  SP 7F ) % z w y t
        db "ni",0x1f,"hd",0x09,0x13,0x07
        db "0",0x1d,"2586k",0x00                     ; 18-1f  0 SHIFT 2 5 8 6 k 00
        db "lgvmq",0x04,0x10,0x14                    ; 20-27  l g v m q SEQ? BIG FLASH
        db ".",0x1c,"(*+9xs"                         ; 28-2f  . 1C ( * + 9 x s
        db "ojbce",0x0d,0x16,0x15
        db 0x08,0x0a,"1473ur"                        ; 38-3f  08 0A 1 4 7 3 u r

; ---- CHARSET_UPPER: unshifted, caps on
CHARSET_UPPER:
        db "KF",0x12,"PA",0x0e,0x11,0x1e             ; 00-07  K F BOLD P A 0E NORM GRAPH
        db " ",0x7f,")%ZWYT"                         ; 08-0f  SP 7F ) % Z W Y T
        db "NI",0x1f,"HD",0x09,0x13,0x07
        db "0",0x1d,"2586K",0x00                     ; 18-1f  0 SHIFT 2 5 8 6 K 00
        db "LGVMQ",0x04,0x10,0x14                    ; 20-27  L G V M Q SEQ? BIG FLASH
        db ".",0x1c,"(*+9XS"                         ; 28-2f  . 1C ( * + 9 X S
        db "OJBCE",0x0d,0x16,0x15
        db 0x08,0x0a,"1473UR"                        ; 38-3f  08 0A 1 4 7 3 U R

; ---- CHARSET_UPPER2: SHIFT held, caps off
CHARSET_UPPER2:
        db "KF",0x06,"PA",0x03,0x17,"_"
        db " ",0x7f,"&'ZWYT"                         ; 08-0f  SP 7F & ' Z W Y T
        db "NI",0x0f,"HD",0x02,0x1b,0x1a
        db "0",0x1d,"2586K",0x00                     ; 18-1f  0 SHIFT 2 5 8 6 K 00
        db "LGVMQ",0xb7,0x19,0x18
        db ":",0x1c,"$#-9XS"
        db "OJBCE",0x0d,0x16,0x15
        db 0x0b,0x0c,"1473UR"                        ; 38-3f  0B 0C 1 4 7 3 U R

; ---- CHARSET_LOWER2: SHIFT held, caps on
CHARSET_LOWER2:
        db "kf",0x06,"pa",0x03,0x17,"_"
        db " ",0x7f,"&'zwyt"                         ; 08-0f  SP 7F & ' z w y t
        db "ni",0x0f,"hd",0x02,0x1b,0x1a
        db "0",0x1d,"2586k",0x00                     ; 18-1f  0 SHIFT 2 5 8 6 k 00
        db "lgvmq",0xb7,0x19,0x18
        db ":",0x1c,"$#-9xs"
        db "ojbce",0x0d,0x16,0x15
        db 0x0b,0x0c,"1473ur"                        ; 38-3f  0B 0C 1 4 7 3 u r

; ---- DEMO_MARKER: the DA byte before DEMO_MESSAGE: when the demo is the current channel,
;      INS_PTR-1 reads it and cmd_B3_append / editor_goto_end / menu_clear_all recognise
;      the demo by it
DEMO_MARKER:
        db 0xda

; ---- DEMO_MESSAGE: channel 10: 'THIS IS A DEMONSTRATION OF THE NEW COLOR CELLS 700
;      SERIES SIX EXCITING COLORS - ... TIME _ BOLD ITALIC BIG FLASH ... JUMP UP DOWN
;      BACK' with 8x colors, 9x backgrounds, A0-AD graphics and the 19/1A/1B/0F effects;
;      ends at DEMO_MESSAGE_END
DEMO_MESSAGE:
        db 0x83,"/ ",0x8f,"/ ",0x8c,"/ ",0x83,"/ ",0x8f,"/ ",0x8c,"/ ",0x8f," THIS IS A "
        db "DEMONSTRATION OF THE               ",0x19,"NEW",0x18,"    "
        db 0x90,0x13,0x12,0x83,"C",0x87,"O",0x8c,"L",0x8d,"O",0x8f,"R ",0x8d,0x92," CELLS "
        db 0x90,"             ",0x11,0x1a,"700",0x18,0x90,0x12," SERIES             "
        db 0x11,0x8c,"      SIX ",0x90,0x8d," ",0x14,"EXCITING ",0x90,0x83,0x11," COLORS -    "
        db 0x90,0x10,0x83,0xa8,0x87,0xa8,0x8c,0xa8,0x8d,0xa8,0x8f,0xa8,0x80,0xa8,0x8f,0xa8
        db 0x8d,0xa8,0x8c,0xa8,0x87,0xa8,0x83,0xa8,0x80,0xa8,0x11,0x83,0x90,"        "
        db "TIME _        ",0x90,0x12,0x92,0x87," BOLD ",0x90,"   ",0x13,0x91,0x8f," ITALIC "
        db 0x90,"   ",0x11,0x8d,0x10,"BIG",0x90,0x11,"   ",0x90,0x83,0x12," ",0x14,"FLASH "
        db 0x90,0x11,"            ",0x12,0x91," ",0x87,0xa1,0xa1,0xa1,"    ",0x90,0x83,0xa2," "
        db 0x87,0xa3," ",0x8b,0xa4," ",0x8c,0xa5," ",0x8f,0xab," ",0x83,0xad,"    ",0x91," "
        db 0x87,0xa0,0xa0,0xa0,"    ",0x90,0x11,"              "
        db 0x19,"JUMP",0x1a,"UP",0x1b,"DOWN",0x0f,"BACK"

; ---- DEMO_MESSAGE_END: the demo's 03; editor_goto_end and cmd_B3_append seat the cursor
;      just before it
DEMO_MESSAGE_END:
        db 0x03

; ---- TEST_MESSAGE: 'CURRENT TEST  ' 80 93 then spaces and 03, in ROM. TEST_MODE displays
;      it straight from here: no RAM copy and no ROM checksum
TEST_MESSAGE:
        db "CURRENT TEST  "
        db 0x80,0x93,"        "
        db "      ",0x03

        ds 0x4000-$,0xff
