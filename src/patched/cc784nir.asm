; ============================================================================
;  Color Cells CC784NIR LED sign - PATCHED firmware source
;  Assemble:  sjasmplus cc784nir.asm   (produces cc784nir_patched.bin, 32768 B)
;  NOT byte-identical to the dump. The untouched reconstruction is
;  ../stock/cc784nir.asm; diff the two to see the patches.
; ============================================================================
        DEVICE NONE

; Patched build: the fixes described in CC784_firmware.md §11 are applied here,
; all written inline (the source is relocatable, so addresses above 0x144A
; differ from stock). Diff against ../stock/cc784nir.asm to see exactly what
; changed; everything else is intentionally kept identical.

        OUTPUT "cc784nir_patched.bin"

FRAMEBUF             equ 0x4000
FRAMEBUF_SIZE        equ 0xc0   ; column ring: 86 visible + the glyph being written; also the TINY line
FRAMEBUF_ROW1        equ FRAMEBUF+0x56
FRAMEBUF_TINY        equ FRAMEBUF+0xab   ; TINY line buffer inside the ring
; ---- variables follow the ring, packed with no gaps (P8). INIT_DATA mirrors
;      this order in four runs, so keep the two in step.
RAM_VARS             equ FRAMEBUF+FRAMEBUF_SIZE
FB_COLPTR            equ RAM_VARS+0x000   ; frame-buffer write pointer (next glyph column)
FB_COL               equ RAM_VARS+0x002   ; scroll position: the column the output window is moving toward
BGRND_PENDING        equ RAM_VARS+0x004   ; editor: BGRND key pressed, next key is the colour digit
TXBUF                equ RAM_VARS+0x005   ; reply frames, and the effect staging frame (86 columns)
STAGE_PTR            equ RAM_VARS+0x05b   ; next free column in TXBUF while an effect stages text
STAGE_OFFSET         equ RAM_VARS+0x05d   ; centring offset of the staged text (free columns / 2)
ROW_PORT             equ RAM_VARS+0x05f   ; port group for the row data: 40 first pass, 48 second
BEEP_TICKS           equ RAM_VARS+0x060   ; beeper on while non-zero (port bit 5); beep_start loads BEEP_LEN
GLYPH_PTR_ORIG       equ RAM_VARS+0x062   ; glyph address before bold/italic/big copies
ASK_CHAN_RESULT      equ RAM_VARS+0x064   ; menu_ask_chan return value
ASK_CHAN_PROMPT      equ RAM_VARS+0x065   ; menu_ask_chan prompt string
THIN_MODE            equ RAM_VARS+0x067   ; non-zero after THIN (B9): no bold in effects
CLK_RUN              equ RAM_VARS+0x068   ; set on every boot by the init image copy
GLYPH_WIDTH          equ RAM_VARS+0x069
GLYPH_PTR            equ RAM_VARS+0x06a
MENU_MSG_PTR         equ RAM_VARS+0x06c   ; message the editor is showing (set with MENU_MSG_FLAG)
CUR_COLOUR           equ RAM_VARS+0x06e
SCROLLING            equ RAM_VARS+0x06f   ; FF while the output window is catching up with FB_COLPTR
CUR_CHAR             equ RAM_VARS+0x070
TEST_MODE            equ RAM_VARS+0x071   ; FF = display the ROM-checksum test message (SEQ MSG? then MAGIC, C)
FB_OUT_PTR           equ RAM_VARS+0x072   ; first column sent to the panel (start of the output window)
DISP_ON              equ RAM_VARS+0x074   ; 0 suppresses row output (effects rewrite FRAMEBUF meanwhile)
CLK_RENDER_STEP      equ RAM_VARS+0x075   ; clock (5F) render step 0..8; FF = finished
CLK_RENDER_PTR       equ RAM_VARS+0x076   ; clock render: next CLK_ digit to emit
MENU_ACTIVE          equ RAM_VARS+0x078
INS_PTR              equ RAM_VARS+0x079
MAGIC_MODE           equ RAM_VARS+0x07b   ; FF between MAGIC (1F) and MAGIC OFF (BD)
WINDOW_COLOUR        equ RAM_VARS+0x07c   ; last colour byte at the output window start (bit 4 = flash)
COL_COUNT            equ RAM_VARS+0x07d   ; columns still free in the staging frame; 0 = no staging (LEFT)
FRAME_COUNT          equ RAM_VARS+0x07e   ; frames since LATCH_BIT7 last toggled (mod 13)
FLASH_BIT            equ RAM_VARS+0x07f   ; 0x10 while the current word flashes; OR-ed into colour bytes
LATCH_BIT7           equ RAM_VARS+0x080   ; 00/80 toggled every 13 frames, OR-ed into CTRL_LATCH bit 7
COLOR_PENDING        equ RAM_VARS+0x081   ; editor: COLOR key pressed, next key is the colour digit
GRAPH_PENDING        equ RAM_VARS+0x082   ; editor: GRAPH key pressed, next key selects A0-AF
ROW_COLOUR           equ RAM_VARS+0x083   ; colour byte sent ahead of each row
QUERIES_ENABLED      equ RAM_VARS+0x084   ; unused since P22 (gated the editor's typed queries)
MENU_MSG_FLAG        equ RAM_VARS+0x085   ; FF = editor has a message to display
EDIT_KEY             equ RAM_VARS+0x086   ; key/character the editor is processing (0 = none)
RX_BYTE              equ RAM_VARS+0x087
IR_KEY_CHAR          equ RAM_VARS+0x088   ; character decoded from the IR key via the CHARSET_ tables
CTRL_LATCH_SHADOW    equ RAM_VARS+0x089
FB_OUT_LEN           equ RAM_VARS+0x08a   ; bytes to send from FB_OUT_PTR before wrapping to FRAMEBUF
FB_EXTRA_LEN         equ RAM_VARS+0x08c   ; bytes to send from FRAMEBUF after the wrap
STORE_END            equ RAM_VARS+0x08e
EFFECT_ID            equ RAM_VARS+0x090   ; 0 LEFT, 1 PAUSE, 2 UP, 3 DOWN, 4 RIGHT, 5 HOLD
EFFECT_VECTOR        equ RAM_VARS+0x091
MENU_TEXT_PTR        equ RAM_VARS+0x093
SHIFT_LABEL          equ RAM_VARS+0x095   ; FF = redraw shows the SHIFT indicator
FLUSH_PENDING        equ RAM_VARS+0x096   ; FF = staged text must be shown before the next effect runs
FRAME_DELAY          equ RAM_VARS+0x097   ; frames to hold before the next column step (1, 3 or 0x50)
ROW_INDEX            equ RAM_VARS+0x098
RX_BITMASK           equ RAM_VARS+0x099
RX_SHIFT             equ RAM_VARS+0x09a
RX_TICKS             equ RAM_VARS+0x09b
RX_FIFO              equ RAM_VARS+0x09c
RX_COUNT             equ RAM_VARS+0x0a4
RX_TIMING_PTR        equ RAM_VARS+0x0a5   ; set by rx_st_wait_start before use
REDRAW_PTR           equ RAM_VARS+0x0a7   ; editor redraw: byte being rendered
RX_STATE             equ RAM_VARS+0x0a9   ; set by store_init before use
CHAN_LOCK            equ RAM_VARS+0x0ab
SEQ_LIST             equ RAM_VARS+0x0ac
SEQ_PTR              equ RAM_VARS+0x114
SEQ_ALL_EMPTY        equ RAM_VARS+0x116   ; 10 = every listed channel is empty, play the demo
GLYPH_BUF            equ RAM_VARS+0x117   ; working copy of the glyph (bold/plain), 32 bytes
GLYPH_BUF_ITALIC     equ RAM_VARS+0x137   ; sheared copy for ITALIC, 32 bytes
GLYPH_BUF_BIG        equ RAM_VARS+0x157   ; widened copy for BIG, 32 bytes
SEQ_MENU_ACTIVE      equ RAM_VARS+0x177   ; FF while the SEQ MSG? dialogue runs
SHIFT_STATE          equ RAM_VARS+0x178   ; SHIFT latch, toggled by key 29 (see section 9)
PREV_SPACE           equ RAM_VARS+0x179   ; 1 = previous char was a space (two in a row reset the background)
FONT_MODE            equ RAM_VARS+0x17a   ; bit 1 BOLD, bit 2 ITALIC, bit 3 BIG
TINY_MODE            equ RAM_VARS+0x17b   ; FF = glyphs go to the tiny buffer (menus, TINY)
FORCE_BOLD           equ RAM_VARS+0x17c   ; editor redraw: FF = effect text is drawn bold (unless THIN)
NMI_COUNT            equ RAM_VARS+0x17d   ; two bytes: magic_short_word reads through it as a pointer, so the 04 high byte is a ROM page
STORE_TMP            equ RAM_VARS+0x17f
MOVE_DST             equ RAM_VARS+0x181
MOVE_SRC             equ RAM_VARS+0x183
REDRAW_FROM          equ RAM_VARS+0x185   ; editor redraw: first byte actually displayed (cursor-21, >= INS_PTR)
STORE_CURSOR         equ RAM_VARS+0x187
TX_BITIDX            equ RAM_VARS+0x189
TX_BITMASK           equ RAM_VARS+0x18a
TX_PENDING           equ RAM_VARS+0x18b
TX_TICKS             equ RAM_VARS+0x18c
TX_SHIFT             equ RAM_VARS+0x18d
TX_STATUS            equ RAM_VARS+0x18e
TX_TIMING_PTR        equ RAM_VARS+0x18f
CAPS_LOCK            equ RAM_VARS+0x191
ROW_OUT_PENDING      equ RAM_VARS+0x192   ; FF = the current row still has to be sent
SEQ_SET              equ RAM_VARS+0x193   ; FF = sequence set by hand; do not auto-add the edited channel
NEXT_CHAN            equ RAM_VARS+0x194   ; channel to show first after the editor (FF = none)
NMI_PER_SEC          equ RAM_VARS+0x195
TINY_FRAME_READY     equ RAM_VARS+0x196   ; tiny mode: a frame is in FRAMEBUF_TINY
TINY_RENDER          equ RAM_VARS+0x197   ; FF while attr_tiny drives the display
DRAW_PREV            equ RAM_VARS+0x198   ; FF = previous item was a DRAW graphic
CLK_RENDERED         equ RAM_VARS+0x199   ; FF just after a clock display; forces LEFT in an effect
MAGIC_COLOUR_IDX     equ RAM_VARS+0x19a   ; index into MAGIC_COLOUR_CYCLE
EURO_STATE           equ RAM_VARS+0x19b
DRAW_BUF             equ RAM_VARS+0x19c   ; 16 packed hex columns of a DRAW graphic
IR_DEBOUNCE          equ RAM_VARS+0x1ac   ; key number seen once, awaiting its second frame
TICK6_COUNT          equ RAM_VARS+0x1ad
TICK1_COUNT          equ RAM_VARS+0x1ae
GEN_COUNTDOWN        equ RAM_VARS+0x1af   ; IR repeat/hold timer, counts down in tick6 (word)
IR_STATE_CNT         equ RAM_VARS+0x1b1
IR_BITCNT            equ RAM_VARS+0x1b2
IR_KEY               equ RAM_VARS+0x1b3   ; last accepted key number
IR_SHIFT             equ RAM_VARS+0x1b4
IR_CODE              equ RAM_VARS+0x1b5
IR_KEYNUM            equ RAM_VARS+0x1b6   ; IR_CODE & 3F = key number 0..63
TICK_VECTOR          equ RAM_VARS+0x1b7
NEW_MSG_CHAN         equ RAM_VARS+0x1b9   ; channel chosen for a new MAGIC message
MAGIC_FX_PREV        equ RAM_VARS+0x1ba   ; FF = last byte was a movement attribute (magic mode)
MAGIC_FLASH_WORD     equ RAM_VARS+0x1bb   ; '$' = flash the word that starts with $ (magic mode)
EDITOR_FIRST_KEY     equ RAM_VARS+0x1bc   ; FF until the first key in the editor is processed
MAGIC_LAST_CHAR      equ RAM_VARS+0x1bd   ; magic mode: last char of the current word (punctuation check)
MAGIC_COLOUR_SET     equ RAM_VARS+0x1be   ; magic mode: colour set by an attribute, skip the auto change
MAGIC_WORD_COUNT     equ RAM_VARS+0x1bf   ; words since the last colour change (magic mode)
RND_SEED             equ RAM_VARS+0x1c0
MAGIC_FONT_SET       equ RAM_VARS+0x1c1   ; magic mode: font set by an attribute, skip the random pick
RND_VAL              equ RAM_VARS+0x1c2   ; magic mode: words until the next colour change
MAGIC_MSG_CHAN       equ RAM_VARS+0x1c3   ; channel to announce as MAGIC MSG nn on redraw (0 = none)
REDRAW_MAGIC         equ RAM_VARS+0x1c4   ; editor redraw: MAGIC seen, font resets at each word
DRAW_NO_GAP          equ RAM_VARS+0x1c5   ; FF = butt this DRAW graphic against the previous one
CHAN_D10             equ RAM_VARS+0x1c6
CHAN_D1              equ RAM_VARS+0x1c7
FLASH_PENDING        equ RAM_VARS+0x1c8   ; 0x10 after FLASH until the next printable char
TEXT_DRAWN           equ RAM_VARS+0x1c9   ; FF once a printable char has been drawn since init_render
RAINBOW_IDX          equ RAM_VARS+0x1ca   ; RAINBOW per-char colour index, 0 = off
TEST_MSG_BUF         equ RAM_VARS+0x1cb   ; RAM copy of TEST_MESSAGE plus the ROM checksum, 28 bytes
MENU_ENTRY_BUF       equ RAM_VARS+0x1e7
FUNC_PENDING         equ RAM_VARS+0x1ec   ; editor: FUNC (B7) pressed, next key picks the second function
MY_ADDRESS           equ RAM_VARS+0x1ed
MY_ADDRESS_INV       equ RAM_VARS+0x1ee
SCROLL_SPEED         equ RAM_VARS+0x1ef   ; 0..7 from F0-F7; blank ticks inserted after every frame
BLANK_TIMER          equ RAM_VARS+0x1f0
SPEED_PENDING        equ RAM_VARS+0x1f1   ; editor: SPEED key pressed, next key is the digit
; P20: the clock digits must survive a power cycle, so they live up here next
; to the store, out of reach of the stub's library copy (RAM_VARS+00..81).
CLK_H10              equ RAM_VARS+0x1f2
CLK_H1               equ RAM_VARS+0x1f3
CLK_M10              equ RAM_VARS+0x1f4
CLK_M1               equ RAM_VARS+0x1f5
CLK_SEC              equ RAM_VARS+0x1f6
CLK_PM               equ RAM_VARS+0x1f7
KEY_ECHO_TX          equ RAM_VARS+0x1f8   ; non-zero = echo accepted keys on serial TX
STORE_LIMIT          equ RAM_VARS+0x1f9
STORE_SIZE           equ RAM_VARS+0x1fb
STORE_TEXT_LIMIT     equ RAM_VARS+0x1fd   ; free text bytes; scan bound for store_repair
STORE_WARN_LIMIT     equ RAM_VARS+0x1ff   ; STORE_END here trips the 100 KEYS LEFT warning
STORE_GUARD          equ RAM_VARS+0x201   ; store_repair writes a space at MSG_STORE-1 every boot
MSG_STORE            equ RAM_VARS+0x202
; ---- Top of RAM (patch 13). Everything at a fixed address sits in the last
;      272 bytes below RAM_TOP: on the stock 8 K chip 7Fxx aliases 5Fxx, so the
;      same build runs on either; only the store's ceiling is decided at boot.
RAM_TOP              equ 0x8000
PKT_READY            equ RAM_TOP-0x110   ; 7EF0 (5EF0 stock)
PKT_BUF              equ PKT_READY+1
PKT_STATE            equ RAM_TOP-0x0f
PKT_CKSUM            equ RAM_TOP-0x0e
PKT_FLAG             equ RAM_TOP-0x0d
PKT_LEN              equ RAM_TOP-0x0c
PKT_VECTOR           equ RAM_TOP-0x0b
PKT_ADDR             equ RAM_TOP-0x09
PKT_PTR              equ RAM_TOP-0x08
PKT_REMAIN           equ RAM_TOP-0x06
CTRL_LATCH           equ 0x8000
; ---- OTA (CC784_ota.md): the boot stub's RAM, above the packet parser state,
;      and the added '273 bank register. store_init leaves these bytes alone.
NMI_SEEN             equ RAM_TOP-0x10 ; FF once a mains NMI has fired since reset: the page writer syncs to the NMI only then (7FF0, between PKT_BUF and the parser state)
NMI_VEC              equ RAM_TOP-4   ; NMI_VECTOR jumps here once NMI_MAGIC holds 0xA5
NMI_MAGIC            equ RAM_TOP-2
ROM_BANK             equ RAM_TOP-1   ; bank the stub booted; BANK_REG cannot be read back
BANK_REG             equ 0xc000      ; write-only: bit 0 = EEPROM A14 (bits 1-2 reserved for A15/A16)

PORT_40_OUT          equ 0x40
PORT_ROW0            equ 0x48
PORT_STROBE          equ 0x80
PORT_IN              equ 0xc0

; ---- Stack / message-store geometry -----------------------------------------
; Stock: SP=0x403F leaves only 64 bytes before 0x4000, which is ROM - pushes
; below it are swallowed and the matching pops read ROM back.  Worst observed
; demand is ~120 bytes (B4 query chain ~40 + tick6_service with rx_consume ~40
; + int/NMI frames), hence bug B1.  Patched: 256-byte stack at 0x5DF0..0x5EEF,
; carved off the top of the message store so nothing else has to move.
STACK_TOP            equ PKT_READY   ; first PUSH lands two below
; FLASH blink: frames per half period of CTRL_LATCH bit 7. Stock 13 = 2.4 Hz;
; 7 gave a visible ~5 Hz on the sign (2026-09-19), which is what proved bit 7
; is the blink clock. Change here to retune, nothing else references it.
FLASH_HALF_PERIOD    equ 13
FRAME_COLS           equ 86          ; columns sent per row: the panel's 84 plus two that fall off the chain
HOLD_FRAMES          equ 80          ; frames a PAUSE, HOLD, wipe or clock holds the panel (~1.3 s)
BEEP_LEN             equ 150         ; beeper on for this many tick6 periods (~115 ms)
IR_REPEAT_DELAY      equ 1300        ; tick6 periods a held remote key waits before repeating (~1 s)
IR_REPEAT_TICKS      equ 300         ; ... and between repeats (~0.23 s)

; ---- Message store format ------------------------------------------------------
MARK_LO              equ 0xd0        ; channel markers are two bytes D0+tens, D0+units
MARK_HI              equ 0xda        ; the last marker byte value; alone, DA ends the store
TEXT_END             equ 0x03        ; ends a channel's text

; ---- Message attribute bytes (the sign's own names, CC784_firmware.md §7) --------
ATTR_BIG             equ 0x10
ATTR_NORM            equ 0x11
ATTR_BOLD            equ 0x12
ATTR_ITALIC          equ 0x13
ATTR_FLASH           equ 0x14
ATTR_COLOR           equ 0x15        ; as an editor key; the packet command is CMD_FORE_IDX
ATTR_BGRND           equ 0x16        ; as an editor key; the packet command is CMD_BACK_IDX
ATTR_LEFT            equ 0x18        ; plain scroll
ATTR_PAUSE           equ 0x19
ATTR_UP              equ 0x1a
ATTR_DOWN            equ 0x1b
KEY_CASE             equ 0x1c        ; UPPER/LOWER key
KEY_SHIFT            equ 0x1d
ATTR_GRAPH           equ 0x1e
ATTR_MAGIC           equ 0x1f
ATTR_TIME            equ 0x5f
ATTR_REM             equ 0xb0        ; remark: skipped up to the next B0
KEY_EURO             equ 0xb6
KEY_FUNC             equ 0xb7
ATTR_DRAW            equ 0xb8
ATTR_THIN            equ 0xb9
ATTR_WAIT            equ 0xba
ATTR_HOLD            equ 0xbb
ATTR_RAINBOW         equ 0xbc
ATTR_MAGIC_OFF       equ 0xbd
ATTR_TINY            equ 0xbe
COLOUR_BASE          equ 0x80        ; 80-8F foreground: bits 0-1 green, 2-3 red intensity
COLOUR_DEFAULT       equ 0x8f        ; yellow, full
COLOUR_FLASH         equ 0x10        ; the FLASH bit in a frame-buffer colour byte
BGRND_BASE           equ 0x90        ; 90-93 background
GRAPH_BASE           equ 0xa0        ; A0-AF built-in graphics
SPEED_BASE           equ 0xf0        ; F0-F7 scroll speed
LATCH_TX             equ 0x10        ; CTRL_LATCH bit 4: serial TX
LATCH_BLINK          equ 0x80        ; CTRL_LATCH bit 7: the FLASH blink clock
STACK_SIZE           equ 128         ; measured high-water 70 bytes, worst-case chain ~108
; P21: packet processing runs in the render loop and replies go out in the
; background, so their state cannot share renderer scratch. 32 bytes below the
; stack, carved off the store.
STREAM_AREA          equ STACK_TOP-STACK_SIZE-32
TX_SEG0              equ STREAM_AREA+0     ; segment being sent: ptr, count, flags (bit 0 = append the sum)
TX_SEG1              equ STREAM_AREA+5     ; next segment, same layout
TX_SUM               equ STREAM_AREA+10    ; running 8-bit sum of TX_SEG0's bytes
TX_DONE_PENDING      equ STREAM_AREA+11    ; FF = send DONE_BYTE once the segments are out
TX_ACTIVE            equ STREAM_AREA+12    ; FF = pkt_process_done handed its reply to the engine
PKT_BUSY             equ STREAM_AREA+13    ; FF from pkt_process entry until the reply and DONE are sent
PKT_RESTART          equ STREAM_AREA+14    ; FF = restart the display when the packet is done
PKT_LOW_EDIT         equ STREAM_AREA+15    ; lowest store address edited by this packet (FFFF = none)
PKT_SAVE_CURSOR      equ STREAM_AREA+17    ; the renderer's STORE_CURSOR, INS_PTR, STORE_END and
PKT_SAVE_INS         equ STREAM_AREA+19    ;   channel marker at entry
PKT_SAVE_END         equ STREAM_AREA+21
PKT_SAVE_MARK        equ STREAM_AREA+23
PKT_DISCARD          equ STREAM_AREA+25    ; FF = the frame being parsed arrived while busy: parse it, keep nothing
PKT_DONE_WANT        equ STREAM_AREA+26    ; the DONE decision, latched at pkt_process entry
STREAM_AREA_SIZE     equ 27
STORE_TOP            equ STREAM_AREA-1    ; with a 32 K chip (16 K usable)
STORE_TOP_8K         equ STORE_TOP-0x2000         ; with the stock 8 K chip
; store_init derives the warning level, the text allowance (301 = framing) and
; the B4 '1' size from whichever ceiling the RAM test picks.

; ---- Wire protocol bytes (CC784_protocol.md) ---------------------------------
FRAME_START          equ 0xb1
ADDR_BROADCAST       equ 0x2a        ; '*': processed, never answered
REPLY_ACK            equ 0x06
REPLY_NAK            equ 0x15
CMD_SPEED            equ 0x02        ; 02 n
CMD_CLEAR_ALL        equ 0x03
CMD_SEQUENCE         equ 0x04        ; 04 dd dd ... [D]
CMD_CHANNEL          equ 0x09        ; 09 dd
CMD_END              equ 0x0d
CMD_DELETE_TEXT      equ 0x0e
CMD_FORE_IDX         equ 0x15        ; 15 n
CMD_BACK_IDX         equ 0x16        ; 16 n
CMD_SET_TIME         equ 0x17        ; 17 hhmm a
CMD_COLOUR_A0        equ 0x1e        ; 1E n
CMD_APPEND           equ 0xb3
CMD_QUERY            equ 0xb4        ; B4 c
QUERY_ROMID          equ '0'
QUERY_MEMORY         equ '1'
QUERY_NOP            equ '2'
QUERY_DUMP           equ '3'
CMD_OTA              equ 0xb5        ; B5 c ... (patch 11)
DONE_BYTE            equ 0x04        ; sent after processing when the frame's flag was 81 (patch 16)

; ---- Boot stub and OTA (CC784_ota.md) ------------------------------------------
STUB_END             equ 0x0240      ; the stub owns 0000-023F; the app starts at the jump table here
APP_START            equ STUB_END
APP_INT              equ STUB_END+3
APP_NMI              equ STUB_END+6
STUB_STACK           equ PKT_READY
STUB_RAM             equ 0x4000      ; stub_lib runs here (FRAMEBUF: idle at boot and during pkt_process)
STUB_LIB_SIZE        equ stub_lib_end-stub_lib             ; the whole library, copied at boot
STUB_LIB_APP_SIZE    equ lib_app_end-STUB_RAM             ; the part the app copies: lib_copy and the page writer
ROM_CRC16            equ stub_lib+(lib_crc16-STUB_RAM)    ; position-independent: callable in ROM too
TRAILER_MAGIC        equ 0x3141544f  ; "OTA1"
; Trailer page at 3FC0: +0 magic, +4 seq, +5 state, +6 CRC-16 of STUB_END..3FBF,
; +8 CRC-16 of bytes +0..+7. CRC-16/XMODEM (poly 1021, init 0), tools/cc784_ota.py.
STATE_TRIAL          equ 1           ; written by F: boot me once, then I need confirming
STATE_TRIED          equ 2           ; the stub booted a TRIAL bank: invalid from now on unless confirmed
STATE_GOOD           equ 3
OTA_IDLE             equ TXBUF+0x55     ; the idle bank; replies never reach this byte
OTA_PAGE_BUF         equ PKT_BUF+0x80   ; 64-byte scratch; the commands using it have short payloads
OTA_FEATURES         equ 0x05           ; 'I' reply byte 21: bit 0 = DONE handshake (patch 16), bit 2 = trial/confirm (patch 18); bit 1 is NMI_SEEN

        org 0x0000

; ============================================================================
;  BOOT STUB 0000-00FF (CC784_ota.md §4). Byte-identical in both banks and
;  written by the T48 only: the OTA handler refuses its pages. It may reference
;  nothing in the app except the fixed jump table below, so that app changes
;  never change its bytes.
; ============================================================================

; ---- RESET: choose a bank, point the NMI at its app, run it
RESET:
        DI
        XOR A
        LD (NMI_MAGIC),A        ; RAM is random at power-up: no vector yet
        LD (NMI_SEEN),A
        LD SP,STUB_STACK
        JP stub_main

        ds 0x0038-$,0xff

; ---- INT_VECTOR: IM 1 entry, through the jump table
INT_VECTOR:
        JP APP_INT

        ds 0x0066-$,0xff

; ---- NMI_VECTOR: through NMI_VEC when it is valid; else ignored. The mains NMI
;      cannot be masked, and while the stub is checking a bank the code at
;      APP_NMI may be anything.
NMI_VECTOR:
        PUSH AF
        LD A,0xff
        LD (NMI_SEEN),A         ; the mains is alive (the page writer and a trial boot need it)
        LD A,(NMI_MAGIC)
        CP 0xa5
        JR nz,nmi_ignore
        POP AF
        PUSH HL
        LD HL,(NMI_VEC)
        EX (SP),HL
        RET

nmi_ignore:
        POP AF
        RETN

; ---- stub_main: check both trailers; prefer the newer sequence number; a
;      bank whose image CRC fails loses to the other; with nothing valid, bank 0
;      runs anyway (the T48 case). Everything that touches BANK_REG runs from
;      RAM (stub_lib), so the other bank's contents never execute here.
stub_main:
        XOR A
        LD (ROM_BANK),A         ; the lib restores this bank after each look
        LD HL,stub_lib
        LD DE,STUB_RAM
        LD BC,STUB_LIB_SIZE
        LDIR
        XOR A
        CALL lib_trailer_check
        PUSH AF                 ; valid0
        PUSH BC                 ; C = seq0
        LD A,1
        CALL lib_trailer_check
        LD E,A                  ; E = valid1, C = seq1
        POP HL                  ; L = seq0
        POP AF
        LD B,A                  ; B = valid0
        OR E
        JR z,stub_boot0         ; neither trailer is valid
        LD A,B
        AND E
        JR nz,stub_both
        LD A,B
        OR A
        LD A,0
        JR nz,stub_try_one      ; only bank 0 is valid
        INC A                   ; only bank 1 is valid

stub_try_one:
        CALL lib_image_check
        JP c,lib_boot
        JR stub_boot0

stub_both:
        LD A,L                  ; seq0 - seq1, signed
        SUB C
        LD A,0
        JP p,stub_try_pair      ; bank 0 is as new or newer: it goes first
        INC A

stub_try_pair:
        PUSH AF
        CALL lib_image_check
        JR c,stub_boot_pop
        POP AF
        XOR 1
        CALL lib_image_check
        JP c,lib_boot

stub_boot0:
        XOR A
        JP lib_boot

stub_boot_pop:
        POP AF
        JP lib_boot

; ============================================================================
;  stub_lib: assembled to run at STUB_RAM. The stub copies it there at boot; the
;  app copies it there again for the B5 commands. Every routine leaves BANK_REG
;  on ROM_BANK, the bank the code is running from.
; ============================================================================
stub_lib:
        DISP STUB_RAM

; ---- lib_copy: A = bank, HL = source in the ROM window, DE = destination in
;      RAM, BC = length. HL/DE advance as LDIR leaves them.
lib_copy:
        LD (BANK_REG),A
        LDIR
        LD A,(ROM_BANK)
        LD (BANK_REG),A
        RET

; ---- lib_page_writer: HL = 64 source bytes in RAM, DE = page address in the
;      ROM window (64-aligned), B = target bank. Interrupts must be off. Out:
;      A = 0 written and verified, 1 verify failed, 2 chip never finished.
;      Waits for the mains NMI first so the 10 ms write cycle, during which the
;      ROM is unreadable, cannot collide with the next one.
lib_page_writer:
        LD A,(NMI_SEEN)
        OR A
        JR z,pw_load            ; no mains NMI (DC supply): nothing to collide with
        HALT                    ; else start right after one: the next is ~16 ms away

pw_load:
        PUSH DE
        PUSH HL
        LD A,1
        LD (BANK_REG),A
        LD A,0xaa
        LD (0x1555),A           ; chip 5555
        XOR A
        LD (BANK_REG),A
        LD A,0x55
        LD (0x2aaa),A           ; chip 2AAA
        LD A,1
        LD (BANK_REG),A
        LD A,0xa0
        LD (0x1555),A           ; chip 5555: SDP write enable, stays armed
        LD A,B
        LD (BANK_REG),A
        LD BC,64
        LDIR
        DEC HL
        LD B,(HL)               ; last byte written, for DATA polling
        DEC DE
        LD C,0                  ; ~500 us: let the page-load window close first

pw_settle:
        DEC C
        JR nz,pw_settle
        LD HL,0x1800            ; poll timeout, ~30 ms

pw_poll:
        LD A,(DE)
        XOR B
        AND 0x80
        JR z,pw_verify
        DEC HL
        LD A,H
        OR L
        JR nz,pw_poll
        LD A,2
        JR pw_done

pw_verify:
        POP HL
        POP DE
        PUSH DE
        PUSH HL
        LD B,64

pw_cmp:
        LD A,(DE)
        CP (HL)
        JR nz,pw_bad
        INC HL
        INC DE
        DJNZ pw_cmp
        XOR A
        JR pw_done

pw_bad:
        LD A,1

pw_done:
        POP HL
        POP DE
        LD B,A
        LD A,(ROM_BANK)
        LD (BANK_REG),A
        LD A,B
        RET
lib_app_end:                    ; the app copies the lib only this far

; ---- lib_crc16: CRC-16/XMODEM of BC bytes at HL into DE (start with DE = 0)
lib_crc16:
        LD A,(HL)
        XOR D
        LD D,A
        PUSH BC
        LD B,8

crc_bit:
        SLA E
        RL D
        JR nc,crc_next
        LD A,D
        XOR 0x10
        LD D,A
        LD A,E
        XOR 0x21
        LD E,A

crc_next:
        DJNZ crc_bit
        POP BC
        INC HL
        DEC BC
        LD A,B
        OR C
        JR nz,lib_crc16
        RET

; ---- lib_trailer_check: A = bank -> A = FF and C = seq if its trailer is valid, else A = 0
lib_trailer_check:
        LD (BANK_REG),A
        LD HL,TRAILER
        LD DE,0
        LD BC,8
        CALL lib_crc16
        LD HL,(TRAILER+8)
        OR A
        SBC HL,DE
        JR nz,tc_bad
        LD HL,(TRAILER)
        LD DE,TRAILER_MAGIC & 0xffff
        OR A
        SBC HL,DE
        JR nz,tc_bad
        LD HL,(TRAILER+2)
        LD DE,TRAILER_MAGIC >> 16
        OR A
        SBC HL,DE
        JR nz,tc_bad
        LD A,(TRAILER+5)
        CP STATE_TRIED          ; booted once as a trial and never confirmed
        JR z,tc_bad
        LD A,(TRAILER+4)
        LD C,A
        LD A,0xff
        JR tc_done

tc_bad:
        XOR A

tc_done:
        LD B,A
        LD A,(ROM_BANK)
        LD (BANK_REG),A
        LD A,B
        RET

; ---- lib_image_check: A = bank -> CY if the app image CRC matches its trailer; A kept
lib_image_check:
        PUSH AF
        LD (BANK_REG),A
        LD HL,STUB_END
        LD BC,0x3fc0-STUB_END
        LD DE,0
        CALL lib_crc16
        LD HL,(TRAILER+6)
        OR A
        SBC HL,DE
        SCF
        JR z,ic_done
        OR A

ic_done:
        LD A,(ROM_BANK)         ; LD leaves the flags alone
        LD (BANK_REG),A
        POP BC
        LD A,B
        RET

; ---- lib_boot: A = bank. Select it, publish it, enable the NMI, enter its app
lib_boot:
        LD (ROM_BANK),A
        LD (BANK_REG),A
        LD A,(TRAILER+5)
        CP STATE_TRIAL
        JR nz,boot_go           ; a trial boots once: mark it TRIED before running it
        LD HL,TRAILER
        LD DE,OTA_PAGE_BUF
        LD BC,64
        LDIR
        LD A,STATE_TRIED
        LD (OTA_PAGE_BUF+5),A
        LD HL,OTA_PAGE_BUF
        LD BC,8
        LD DE,0
        CALL lib_crc16
        LD (OTA_PAGE_BUF+8),DE
        LD HL,OTA_PAGE_BUF
        LD DE,TRAILER
        LD A,(ROM_BANK)
        LD B,A
        CALL lib_page_writer

boot_go:
        LD HL,APP_NMI
        LD (NMI_VEC),HL
        LD A,0xa5
        LD (NMI_MAGIC),A
        JP APP_START

        ENT
stub_lib_end:
        ; the boot copy overwrites RAM_VARS from the start: keep it below the
        ; first variable that must survive a reset
        ASSERT STUB_RAM+STUB_LIB_SIZE <= STORE_END

        ds STUB_END-$,0xff

; ============================================================================
;  APPLICATION. The stub enters through this jump table and nowhere else.
; ============================================================================
        JP app_start
        JP int_timer
        JP nmi_entry

; ---- data: 16-byte firmware ID, returned by query B4 '0' (0048 in stock)
ROM_ID:
        db "78409O1702930205"

; ---- app_start: cold start: set SP, run init routines, EI, jump to main loop
app_start:
        LD SP,STACK_TOP
        CALL init_vars
        CALL store_init
        CALL ir_init
        CALL init_nmi_rate

; ---- restart_display: re-init and run the sequence (also from the editor)
restart_display:
        CALL init_render
        CALL store_repair
        CALL init_sequence
        EI
        JP main_loop

; ---- nmi_entry: NMI = real-time clock tick (mains frequency); calls clock_tick
nmi_entry:
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

; ---- int_timer: Timer ISR. Every 6th tick schedules tick6_service; every tick schedules the handler in TICK_VECTOR (IR decoder). Both are invoked by pushing their address so they run as the ISR returns.
int_timer:
        EX AF,AF'
        EXX
        LD A,(TICK6_COUNT)
        INC A
        CP 6
        JR nz,int_tick6_store
        LD HL,tick6_service     ; the address is pushed so the service runs as the ISR returns
        PUSH HL
        XOR A

int_tick6_store:
        LD (TICK6_COUNT),A
        LD A,(TICK1_COUNT)
        INC A
        CP 1
        JR nz,int_tick1_store
        LD HL,(TICK_VECTOR)
        PUSH HL
        XOR A

int_tick1_store:
        LD (TICK1_COUNT),A
        EX AF,AF'
        EXX
        EI
        RETI

; ---- main_loop: open the next channel, then render it a character at a time.
;      P21: pkt_poll runs here, at every render step and in every frame wait,
;      so a packet is processed within one step of its arrival.
main_loop:
        CALL pkt_poll
        CALL init_render
        CALL seq_next_channel

render_loop:
        CALL pkt_poll
        CALL render_next_char
        CALL effect_step
        ; LD A,(nn) sets no flags, so this JR tests effect_step's exit flags,
        ; not MAGIC_MODE. A is loaded for whatever runs after the branch.
        LD A,(MAGIC_MODE)
        JR nz,render_loop
        XOR A
        LD (COL_COUNT),A
        LD HL,fxv_none
        LD (EFFECT_ID),A
        LD (EFFECT_VECTOR),HL
        JR render_loop

; ---- pkt_poll (P21): process a pending packet here, between two render
;      steps. pkt_process returns unless the display has to restart.
pkt_poll:
        LD A,(PKT_READY)
        AND A
        RET z
        PUSH AF                 ; the spins that poll keep registers live
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        CALL pkt_process
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- tick6_service: Runs every 6 timer ticks: serial RX/TX bit engines, countdowns, display column refresh & flashing, then the RX byte consumer.
tick6_service:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD HL,(GEN_COUNTDOWN)
        DEC HL
        LD A,H
        AND L
        CP 0xff
        JR z,tick6_engines
        LD (GEN_COUNTDOWN),HL

tick6_engines:
        CALL rx_bit_engine
        CALL tx_bit_engine
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
        LD A,(TINY_RENDER)
        AND A
        JP nz,tiny_refresh
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
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,(DISP_ON)
        AND A
        JP z,row_phase_step
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
        JR z,row_out_colour
        SET 5,C

row_out_colour:
        LD A,(ROW_COLOUR)
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
        JR nz,frame_colour

frame_scroll_stop:
        XOR A
        LD (SCROLLING),A
        JP frame_colour

frame_check_still:
        LD HL,(FB_OUT_PTR)
        LD DE,(FB_COL)
        OR A
        SBC HL,DE
        JP z,frame_bit7_tick

frame_colour:
        LD HL,(FB_COL)
        BIT 7,(HL)
        JR z,frame_latch_colour
        LD A,(HL)
        LD (WINDOW_COLOUR),A

frame_latch_colour:
        LD A,(EFFECT_ID)
        AND A
        LD A,(WINDOW_COLOUR)
        JR z,frame_set_window
        AND COLOUR_FLASH
        OR 0x8f

frame_set_window:
        LD (ROW_COLOUR),A
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
; ---- rx_consume: Pop a byte from RX_FIFO; in normal mode feed the packet parser (or if IR_CODE=A4/A5 handle keypad); packet start needs 0xB1 while idle
rx_consume:
        LD A,(MENU_ACTIVE)
        AND A
        JP nz,tick6_exit
        CALL rx_fifo_get
        JP nc,rx_have_byte
        LD A,(IR_CODE)
        CP 0xa4
        JP z,rx_ir_stop_key
        CP 0xa5
        JP nz,tick6_exit
        LD A,0x20
        LD (RX_BYTE),A
        JP tick6_exit

rx_ir_stop_key:
        LD (IR_KEY),A
        JP key_handler

rx_have_byte:
        LD A,(PKT_STATE)
        AND A
        JR z,rx_idle_byte
        CALL pkt_feed_byte
        XOR A                   ; B12: a payload byte is not a key; a 0x20 left
        LD (RX_BYTE),A          ; here would release a WAIT (wait_poll)
        JP tick6_exit

rx_idle_byte:
        ; P21: while a packet waits, is processed or is being answered, a new
        ; frame is parsed but kept nowhere and never answered, so its bytes
        ; cannot leak into the editor as keys once the sign is free again.
        LD A,(PKT_READY)
        LD HL,PKT_BUSY
        OR (HL)
        LD (PKT_DISCARD),A
        LD HL,RX_BYTE
        JR z,rx_idle_free
        LD A,(HL)
        CP FRAME_START
        JP nz,tick6_exit
        JR rx_frame_start

rx_idle_free:
        LD A,(HL)
        CP FRAME_START
        JR nz,rx_not_start

rx_frame_start:
        LD A,0xff
        LD (PKT_STATE),A
        LD HL,pkt_st_addr
        LD (PKT_VECTOR),HL
        JP tick6_exit

rx_not_start:
        LD A,(RX_BYTE)
        CP 1
        JP z,key_handler

; ---- tick6_exit
tick6_exit:
tick6_arm_row:
        LD A,0xff
        LD (ROW_OUT_PENDING),A
        LD A,0x40
        LD (ROW_PORT),A

tick6_restore:
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- init_sequence: validate SEQ_LIST (reset to 0..99 if not), then flag
;      SEQ_ALL_EMPTY when no listed channel has text
init_sequence:
        XOR A
        LD (SEQ_ALL_EMPTY),A
        LD B,0x68
        LD HL,SEQ_LIST
        LD A,(HL)
        CP 0xff
        JR z,seq_reset_default

seq_scan:
        CP 0x65
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

seq_reset_default:
        LD HL,SEQ_LIST
        LD A,0
        LD B,0x64

seq_fill:
        LD (HL),A
        INC HL
        INC A
        DJNZ seq_fill
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff

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

; ---- seq_next_channel: pick the channel to display next: NEXT_CHAN once, else the
;      next SEQ_LIST entry (demo 100 when SEQ_ALL_EMPTY); seat STORE_CURSOR on its
;      first printable byte, or on TEST_MSG_BUF in TEST_MODE
seq_next_channel:
        LD A,(TEST_MODE)
        INC A
        JP z,seq_test_message
        LD A,(NEXT_CHAN)
        CP 0x64
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
        LD A,0x64
        JR z,seq_open_channel
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JR nz,seq_clamp_entry
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        JP seq_next_channel

seq_clamp_entry:
        CP 0x65
        JR c,seq_advance
        LD A,0x64
        LD (HL),0x64

seq_advance:
        LD E,A
        INC HL
        LD (SEQ_PTR),HL

seq_open_channel:
        LD E,A
        PUSH DE
        CALL chan_select
        POP DE
        OR A
        JP nz,pkt_process_end
        LD A,(HL)
        CP TEXT_END
        JR z,seq_chan_empty
        PUSH HL
        LD B,0
        LD C,A
        LD IX,CHAR_FLAGS
        ADD IX,BC
        BIT 1,(IX+0)
        JR z,seq_set_cursor

seq_skip_attrs:
        INC HL
        LD A,(HL)
        CP TEXT_END
        JR nz,seq_skip_attrs_next
        POP HL
        JP seq_chan_empty

seq_skip_attrs_next:
        LD B,0
        LD C,A
        LD IX,CHAR_FLAGS
        ADD IX,BC
        BIT 1,(IX+0)
        JR nz,seq_skip_attrs

seq_set_cursor:
        POP HL
        LD (STORE_CURSOR),HL
        PUSH DE
        CALL clear_chan_lock
        POP DE
        LD A,E
        CP 0x64
        JR nz,seq_ret
        LD (CHAN_LOCK),A

seq_ret:
        RET

seq_chan_empty:
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JP nz,seq_next_channel
        DEC HL
        LD DE,SEQ_LIST
        OR A
        SBC HL,DE
        JP nz,seq_next_channel
        LD A,0x64
        JP seq_open_channel

seq_test_message:
        LD HL,TEST_MSG_BUF
        LD (STORE_CURSOR),HL
        CALL clear_chan_lock
        RET

; ---- clear_chan_lock
clear_chan_lock:
        XOR A
        LD (CHAN_LOCK),A
        RET

; ---- chan_select: Select channel E: find/create its slot in MSG_STORE, set INS_PTR/STORE_CURSOR
chan_select:
        CP 0x64
        JR nz,chan_marker
        LD HL,DEMO_MESSAGE
        JP chan_ok

chan_marker:
        LD DE,MARK_LO*256+MARK_LO
        AND A
        JR z,chan_scan
        LD B,A
        LD A,MARK_HI

chan_marker_inc:
        INC E
        CP E
        JR nz,chan_marker_next
        LD E,MARK_LO
        INC D
        CP D
        JR z,chan_error

chan_marker_next:
        DJNZ chan_marker_inc

chan_scan:
        LD IX,MSG_STORE
        LD BC,(STORE_SIZE)

chan_scan_loop:
        LD A,(IX+0)
        CP 0xda
        JR z,chan_error
        LD H,A
        LD L,(IX+1)
        OR A
        SBC HL,DE
        JR z,chan_found
        INC IX
        DEC BC
        LD A,C
        OR B
        JR nz,chan_scan_loop
        JP z,chan_error

chan_found:
        INC IX
        INC IX
        PUSH IX
        POP HL

chan_ok:
        XOR A
        RET

chan_error:
        LD A,0xff
        RET

; ---- store_repair: every boot: bad bytes -> ?, stray 03 -> space, then re-sequence
;      the 100 channel markers and re-terminate (recovers a corrupted store)
store_repair:
        ; P25: the three whole-store passes stop at the first DA, the store's
        ; end; a store that has lost its DA still gets the full scan
        LD HL,MSG_STORE
        LD BC,(STORE_SIZE)
        LD A,MARK_HI
        CPIR
        LD DE,MSG_STORE
        JR nz,repair_full
        OR A
        SBC HL,DE               ; bytes up to and including the DA
        JR repair_bound

repair_full:
        LD HL,(STORE_SIZE)

repair_bound:
        LD (STORE_TMP),HL
        CALL store_fix_bad_bytes
        CALL store_strip_ends
        LD HL,MSG_STORE
        LD A,MARK_LO
        LD D,MARK_LO
        LD E,A
        LD BC,(STORE_TEXT_LIMIT)

repair_marker:
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,MARK_HI
        INC D
        CP D
        JR nz,repair_check_units
        LD D,MARK_LO
        INC E
        JR repair_fix_pair

repair_check_units:
        CP E
        JR nz,repair_fix_pair
        DEC HL
        JP repair_terminate

repair_fix_pair:
        DEC HL
        DEC HL
        LD (HL),0x20
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        CP MARK_LO
        JP c,repair_next
        CP MARK_HI+1
        JP nc,repair_next
        LD (HL),0x20

repair_next:
        INC HL

repair_scan:
        LD A,(HL)
        CP MARK_LO
        JP c,repair_scan_next
        CP MARK_HI+1
        JP nc,repair_scan_next
        JR repair_marker

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
        LD (HL),D
        INC HL
        LD (HL),TEXT_END
        INC HL
        INC D
        CP D
        JR nz,repair_append_loop
        LD D,MARK_LO
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
        LD BC,(STORE_TMP)
        LD D,0

fixbad_loop:
        LD E,(HL)
        LD IX,CHAR_FLAGS
        ADD IX,DE
        BIT 0,(IX+0)
        JR z,fixbad_next
        LD (HL),0x3f

fixbad_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,fixbad_loop
        RET

store_strip_ends:
        LD HL,MSG_STORE
        LD BC,(STORE_TMP)

strip_loop:
        LD A,(HL)
        CP TEXT_END
        JR nz,strip_next
        LD (HL),0x20

strip_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,strip_loop
        RET

store_add_ends:
        LD IX,MSG_STORE+2
        LD BC,(STORE_TMP)
        DEC BC
        DEC BC

addend_loop:
        LD A,(IX+0)
        CP MARK_LO
        JP c,addend_next
        CP MARK_HI+1
        JP nc,addend_next
        LD (IX-1),TEXT_END
        INC IX
        DEC BC
        LD A,C
        OR B
        RET z

addend_next:
        INC IX
        DEC BC
        LD A,C
        OR B
        JR nz,addend_loop
        RET

; ---- init_nmi_rate: NMI_PER_SEC = 60 -> NMI is a 60 Hz (mains) tick
init_nmi_rate:
        LD A,0x3c
        LD (NMI_PER_SEC),A
        RET

; ---- init_vars: Power-on RAM init: copies the blocks out of INIT_DATA,
;      validates MY_ADDRESS/MY_ADDRESS_INV (resets it if corrupt)
init_vars:
        XOR A
        LD (TINY_RENDER),A
        LD (TINY_FRAME_READY),A
        LD HL,MENU_ENTRY_BUF
        LD B,5

init_clear_addrbuf:
        LD (HL),A
        INC HL
        DJNZ init_clear_addrbuf
        LD (DRAW_NO_GAP),A
        LD (DRAW_PREV),A
        LD (EURO_STATE),A
        LD (CLK_RENDER_STEP),A
        LD (CLK_RENDERED),A
        LD (FLASH_PENDING),A
        LD (MAGIC_FONT_SET),A
        LD (MAGIC_COLOUR_SET),A
        LD (RAINBOW_IDX),A
        LD (REDRAW_MAGIC),A
        LD (MAGIC_MSG_CHAN),A
        LD (MAGIC_WORD_COUNT),A
        LD (MAGIC_FLASH_WORD),A
        LD (TEXT_DRAWN),A
        LD (THIN_MODE),A
        LD (KEY_ECHO_TX),A
        LD (SPEED_PENDING),A
        LD (FUNC_PENDING),A
        LD (SCROLL_SPEED),A
        LD (BLANK_TIMER),A
        LD (TICK6_COUNT),A
        LD HL,STREAM_AREA       ; P21: no reply in flight, no packet busy
        LD B,STREAM_AREA_SIZE

init_clear_stream:
        LD (HL),A
        INC HL
        DJNZ init_clear_stream
        LD A,0xff
        LD (NEXT_CHAN),A
        LD A,0x20
        LD (MAGIC_LAST_CHAR),A
        LD A,(NMI_COUNT)
        LD (RND_SEED),A
        AND 3
        ADD A,3
        LD (RND_VAL),A
        LD A,(MY_ADDRESS)
        LD C,A
        LD A,(MY_ADDRESS_INV)
        CPL
        CP C
        JR z,init_copy_tables
        ; MY_ADDRESS_INV is MY_ADDRESS+1, so one 16-bit store does both:
        ; L=0x01 -> address 1 (NETCC's default), H=0xFE -> its complement.
        LD HL,0xfe01
        LD (MY_ADDRESS),HL
        ; P6: RAM is fresh, so the clock bytes are noise too - the image copy
        ; below starts at CLK_RUN and never touches CLK_H10..CLK_PM. Start 12:00 AM.
        LD HL,0x0201
        LD (CLK_H10),HL         ; CLK_H10 = 1, CLK_H1 = 2
        LD HL,0
        LD (CLK_M10),HL         ; CLK_M10, CLK_M1
        LD (CLK_SEC),HL         ; CLK_SEC, CLK_PM (0 = AM)
        ; The message store is noise as well; store_repair would only tidy it
        ; into 100 channels of garbage. Empty it now: init_sequence then finds
        ; every channel empty and runs the demo, as after a CLR ALL.
        CALL store_clear_all

init_copy_tables:
        LD HL,INIT_DATA+0x00
        LD DE,FB_COLPTR
        LD BC,5
        LDIR
        LD HL,INIT_DATA+0x05
        LD DE,STAGE_PTR
        LD BC,7
        LDIR
        LD HL,INIT_DATA+0x0c
        LD DE,CLK_RUN
        LD BC,67
        LDIR
        LD HL,INIT_DATA+0x4f
        LD DE,SEQ_MENU_ACTIVE
        LD BC,28
        LDIR
        IM 1
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        RET

; ---- INIT_DATA: RAM images that init_vars LDIRs into place, one run per block
;      of initialised variables. The dw entries naming a ROM label hold an
;      address as DATA and must stay symbolic.
INIT_DATA:
; -- +00 -> FB_COLPTR, 5 bytes
        dw FRAMEBUF_ROW1       ; FB_COLPTR
        dw FRAMEBUF            ; FB_COL
        db 0x00                ; BGRND_PENDING
; -- +05 -> STAGE_PTR, 7 bytes
        dw TXBUF               ; STAGE_PTR
        dw 0x0000              ; STAGE_OFFSET
        db 0x00                ; ROW_PORT
        dw 0x0000              ; BEEP_TICKS
; -- +0c -> CLK_RUN, 67 bytes
        db 0x01                ; CLK_RUN
        db 0x00                ; GLYPH_WIDTH
        dw 0x0000              ; GLYPH_PTR
        dw 0x0000              ; MENU_MSG_PTR
        db 0x0f                ; CUR_COLOUR
        db 0x00                ; SCROLLING
        db 0x00                ; CUR_CHAR
        db 0x00                ; TEST_MODE
        dw FRAMEBUF            ; FB_OUT_PTR
        db 0x01                ; DISP_ON
        db 0x05                ; CLK_RENDER_STEP
        dw 0x0000              ; CLK_RENDER_PTR
        db 0x00                ; MENU_ACTIVE
        dw 0x0000              ; INS_PTR
        db 0x00                ; MAGIC_MODE
        db 0x00                ; WINDOW_COLOUR
        db 0x0f                ; COL_COUNT
        db 0x00                ; FRAME_COUNT
        db 0x00                ; FLASH_BIT
        db 0x0a                ; LATCH_BIT7
        db 0x00                ; COLOR_PENDING
        db 0x00                ; GRAPH_PENDING
        db 0x00                ; ROW_COLOUR
        db 0x0f                ; QUERIES_ENABLED
        db 0x00                ; MENU_MSG_FLAG
        db 0x00                ; EDIT_KEY
        db 0x00                ; RX_BYTE
        db 0x00                ; IR_KEY_CHAR
        db 0x00                ; CTRL_LATCH_SHADOW
        dw 0x5600              ; FB_OUT_LEN
        dw 0x0000              ; FB_EXTRA_LEN
        dw 0xff00              ; STORE_END
        db 0x00                ; EFFECT_ID
        dw 0x0000              ; EFFECT_VECTOR
        dw 0x0000              ; MENU_TEXT_PTR
        db 0x00                ; SHIFT_LABEL
        db 0x01                ; FLUSH_PENDING
        db 0x00                ; FRAME_DELAY
        db 0x00                ; ROW_INDEX
        db 0x00                ; RX_BITMASK
        db 0x00                ; RX_SHIFT
        db 0x00                ; RX_TICKS
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; RX_FIFO
        db 0x00                ; RX_COUNT
        dw 0                   ; RX_TIMING_PTR
        dw 0                   ; REDRAW_PTR (stock had junk here from a misaligned copy; set by editor_redraw)
        dw 0                   ; RX_STATE
; -- +4f -> SEQ_MENU_ACTIVE, 28 bytes
        db 0x00                ; SEQ_MENU_ACTIVE
        db 0x00                ; SHIFT_STATE
        db 0x00                ; PREV_SPACE
        db 0x00                ; FONT_MODE
        db 0x00                ; TINY_MODE
        db 0x00                ; FORCE_BOLD
        dw 0x04b0              ; NMI_COUNT
        dw 0x0000              ; STORE_TMP
        dw 0x0000              ; MOVE_DST
        dw 0x0000              ; MOVE_SRC
        dw 0x0000              ; REDRAW_FROM
        dw MSG_STORE           ; STORE_CURSOR
        db 0x00                ; TX_BITIDX
        db 0x01                ; TX_BITMASK
        db 0x00                ; TX_PENDING
        db 0x00                ; TX_TICKS
        db 0x00                ; TX_SHIFT
        db 0x00                ; TX_STATUS
        dw TX_TIMING           ; TX_TIMING_PTR
        db 0xff                ; CAPS_LOCK
        db 0xff                ; ROW_OUT_PENDING

; ---- init_render: Reset render state for the current message
init_render:
        CALL clear_framebuf
        XOR A
        LD (DRAW_NO_GAP),A
        LD (DRAW_PREV),A
        LD (TINY_RENDER),A
        LD (TINY_FRAME_READY),A
        LD A,0xff
        LD (DISP_ON),A
        LD HL,FRAMEBUF
        LD (FB_OUT_PTR),HL
        LD (FB_COL),HL
        LD HL,0
        LD (FB_EXTRA_LEN),HL
        LD HL,FRAME_COLS
        LD (FB_OUT_LEN),HL
        XOR A
        LD (MAGIC_MODE),A
        LD (SCROLLING),A
        LD (CLK_RENDER_STEP),A
        LD (MAGIC_MODE),A
        LD (FLASH_BIT),A
        LD (MAGIC_COLOUR_SET),A
        LD (REDRAW_MAGIC),A
        LD (MAGIC_FONT_SET),A
        LD (RND_VAL),A
        LD (EFFECT_ID),A
        LD (FRAME_DELAY),A
        LD (FLASH_PENDING),A
        LD (TEXT_DRAWN),A
        LD (RAINBOW_IDX),A
        LD (SCROLL_SPEED),A
        LD (FORCE_BOLD),A
        LD (TINY_MODE),A
        LD (FONT_MODE),A
        LD (THIN_MODE),A
        LD A,COLOUR_DEFAULT
        LD (WINDOW_COLOUR),A
        LD (ROW_COLOUR),A
        LD (CUR_COLOUR),A
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

; ---- track_flash_space: FLASH takes effect at the next printable char and ends
;      at the next space; two spaces in a row clear the background colour
track_flash_space:
        LD A,(CUR_CHAR)
        CP 0x20
        JR z,space_seen
        XOR A
        LD (PREV_SPACE),A
        LD A,(CUR_CHAR)
        LD D,0
        LD E,A
        LD HL,CHAR_FLAGS
        ADD HL,DE
        BIT 1,(HL)
        JR nz,track_done
        LD A,0xff
        LD (TEXT_DRAWN),A
        LD A,(FLASH_PENDING)
        AND A
        JR z,track_done
        LD (FLASH_BIT),A
        XOR A
        LD (FLASH_PENDING),A
        JR track_done

space_seen:
        XOR A
        LD (FLASH_BIT),A
        LD A,(PREV_SPACE)
        AND A
        JR nz,double_space
        LD A,1
        LD (PREV_SPACE),A
        JR track_done

double_space:
        LD A,(TEST_MODE)
        INC A
        JR z,track_done
        LD A,(CUR_COLOUR)
        AND 15
        LD (CUR_COLOUR),A

track_done:
        RET

; ---- render_next_char: Fetch next byte from the message store at STORE_CURSOR and act on it: attribute bytes are dispatched, printable bytes are drawn via glyph_lookup
render_next_char:
        CALL fetch_char

; ---- render_cur_char: render CUR_CHAR (render_next_char without the fetch)
render_cur_char:
        CALL track_flash_space
        CALL magic_preprocess
        CALL attr_rainbow
        CALL attr_draw_check
        CALL attr_thin_check
        CALL attr_wait_check
        CALL attr_remark_check
        CALL attr_hold_check
        CP ATTR_TINY
        JP z,attr_tiny
        AND 0xf0
        CP GRAPH_BASE
        JR nz,class_not_a0
        LD A,(CUR_CHAR)
        AND 15
        LD (CUR_CHAR),A
        JR glyph_lookup

class_not_a0:
        LD A,(CUR_CHAR)
        CP 0x17
        JR z,glyph_lookup
        BIT 7,A
        JP nz,class_high
        AND 0x60
        JP z,attr_control
        LD A,(CUR_CHAR)
        CP ATTR_TIME
        JP z,render_clock
        BIT 7,A
        JP z,glyph_lookup

class_high:
        CP 0x94
        JP c,attr_colour_speed
        CP GRAPH_BASE
        JR c,glyph_lookup
        AND 0xf0
        CP 0xc0
        JR z,glyph_lookup
        CP 0xe0
        JR z,glyph_lookup
        CP 0xd0
        JP nz,attr_colour_speed

; ---- glyph_lookup: HL = FONT + 8*glyph_index(CUR_CHAR); GLYPH_WIDTH = byte 7 of the glyph
glyph_lookup:
        LD HL,FONT
        LD A,(CUR_CHAR)
        CALL char_to_glyph
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
        CALL clear_glyph_tmp
        LD A,(TINY_MODE)
        AND A
        JR nz,glyph_place
        CALL glyph_bold
        CALL glyph_big
        CALL glyph_italic
        LD A,(CLK_RENDER_STEP)
        CP 0xff
        JR nz,glyph_graphic_check
        XOR A
        LD (CLK_RENDER_STEP),A
        LD A,0xff
        LD (CLK_RENDERED),A

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
        JR nz,glyph_direct
        LD A,(EFFECT_ID)
        AND A
        JP nz,glyph_stage

glyph_direct:

; ---- glyph_blit: write colour byte + glyph columns at FB_COLPTR
glyph_blit:
        LD A,(MAGIC_MODE)
        AND A
        JR z,blit_setup
        LD A,(CUR_CHAR)
        CP 0x20
        JR nz,blit_setup
        LD DE,WIDE_SPACE_GLYPH
        LD (GLYPH_PTR),DE
        LD A,9
        LD (GLYPH_WIDTH),A

blit_setup:
        LD DE,(GLYPH_PTR)
        LD HL,(FB_COLPTR)
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD A,(MENU_ACTIVE)
        AND A
        JR z,blit_flash_bit
        LD A,15
        LD (CUR_COLOUR),A
        LD A,(TINY_MODE)
        AND A
        LD C,0
        JR nz,blit_colour

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

blit_colour:
        PUSH BC
        LD A,(CUR_CHAR)
        CP 0x20
        LD C,0xf0
        JR z,blit_write_colour
        LD C,0xff

blit_write_colour:
        LD A,(CUR_COLOUR)
        AND C
        POP BC
        OR C
        SET 7,A
        LD (HL),A
        LD A,(DRAW_NO_GAP)
        AND A
        CALL z,fb_ptr_inc
        XOR A
        LD (DRAW_NO_GAP),A

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

; ---- WIDE_SPACE_GLYPH: 9-column blank used for spaces in MAGIC mode
WIDE_SPACE_GLYPH:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

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
        OR 0x8f
        LD (DE),A
        LD A,(DRAW_NO_GAP)
        AND A
        LD A,0
        LD (DRAW_NO_GAP),A
        JR nz,stage_copy
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

; ---- char_to_glyph: Map a character code to a font glyph index
;      (CHARSET_LOWER..CHARSET_EURO select upper/lower/tiny fonts)
char_to_glyph:
        PUSH AF
        AND 0xf0
        CP 0xc0
        LD DE,FONT+8*128
        JR z,glyph_base_sel
        CP 0xd0
        LD DE,FONT+8*175
        JR z,glyph_base_sel
        CP 0xe0
        LD DE,FONT+8*144
        JR z,glyph_base_sel
        CP 0x90
        LD DE,FONT+8*160
        JR z,glyph_base_sel
        POP AF
        RET

glyph_base_sel:
        POP AF
        AND 15
        EX DE,HL
        RET

; ---- fetch_char: CUR_CHAR = next store byte (LEFT substituted after a clock)
fetch_char:
        PUSH HL
        PUSH AF
        LD HL,(STORE_CURSOR)
        LD A,(EFFECT_ID)
        AND A
        JR z,fetch_read
        LD A,(CLK_RENDERED)
        AND A
        JR z,fetch_read
        LD A,0x18
        JR fetch_store

fetch_read:
        LD A,(HL)

fetch_store:
        INC HL
        LD (STORE_CURSOR),HL
        LD (CUR_CHAR),A
        XOR A
        LD (CLK_RENDERED),A
        POP AF
        POP HL
        RET

; ---- attr_hold_check: BB HOLD goes through fx_attr
attr_hold_check:
        LD A,(CUR_CHAR)
        CP ATTR_HOLD
        RET nz
        POP HL
        JP fx_attr

; ---- attr_rainbow: BC starts the per-character colour cycle
attr_rainbow:
        LD A,(CUR_CHAR)
        CP ATTR_RAINBOW
        JR nz,rainbow_step
        LD A,(MAGIC_MODE)
        AND A
        JR z,rainbow_on
        LD A,(RAINBOW_COLOURS+1)
        LD (CUR_COLOUR),A

rainbow_on:
        ; P19: start anywhere in the cycle. rainbow_step advances before it
        ; looks up, so an index of 1..5 makes the first character orange,
        ; yellow, lime, green or red; stock always started at 1 (orange).
        LD A,(RND_SEED)         ; a running 8-bit generator (a = 5, c odd: full
        LD B,A                  ; period), so the start keeps moving even on a
        ADD A,A                 ; DC supply where the counters are phase-locked
        ADD A,A                 ; to the display cycle; MAGIC reseeds it on entry
        ADD A,B
        INC A
        LD B,A
        LD A,(NMI_COUNT)
        ADD A,B
        LD B,A
        LD A,(TICK6_COUNT)
        ADD A,B
        LD (RND_SEED),A

rainbow_mod5:
        SUB 5
        JR nc,rainbow_mod5
        ADD A,6                 ; -5..-1 -> 1..5
        LD (RAINBOW_IDX),A
        LD (MAGIC_COLOUR_SET),A ; any non-zero value means "set"
        POP HL
        JP render_next_char

rainbow_step:
        LD A,(RAINBOW_IDX)
        AND A
        LD A,(CUR_CHAR)
        RET z
        CP 0x20
        RET z
        LD D,0
        LD E,A
        LD IX,CHAR_FLAGS
        ADD IX,DE
        BIT 1,(IX+0)
        RET nz
        LD A,(RAINBOW_IDX)
        INC A
        AND 7
        JR nz,rainbow_lookup
        LD A,1

rainbow_lookup:
        LD E,A
        LD D,0
        LD HL,RAINBOW_COLOURS
        ADD HL,DE
        LD A,(HL)
        CP 0xff
        JR nz,rainbow_apply
        LD E,1
        LD A,(RAINBOW_COLOURS+1)

rainbow_apply:
        AND 15
        LD (CUR_COLOUR),A
        LD A,E
        LD (RAINBOW_IDX),A
        LD A,(CUR_CHAR)
        RET

; ---- RAINBOW_COLOURS: per-character cycle red, orange, yellow, lime, green
RAINBOW_COLOURS:
        db 0x00,0x8c,0x8d,0x8f,0x87,0x83,0xff,0xff

attr_remark_check:
        LD A,(CUR_CHAR)
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

; ---- attr_wait_check: BA WAIT: flush, then spin until SPACE or a packet
attr_wait_check:
        LD A,(CUR_CHAR)
        CP ATTR_WAIT
        RET nz
        LD A,(COL_COUNT)
        AND A
        JR z,wait_for_key
        LD HL,(STAGE_PTR)
        LD DE,TXBUF
        XOR A
        SBC HL,DE
        JR z,wait_for_key
        LD A,ATTR_LEFT
        LD (CUR_CHAR),A
        RET

wait_for_key:
        CALL fb_colours_default
        XOR A
        LD (RX_BYTE),A
        LD (IR_CODE),A

wait_poll:
        LD A,(RX_BYTE)
        CP 0x20
        JR nz,wait_check_pkt
        POP HL
        JP render_next_char

wait_check_pkt:
        CALL pkt_poll
        JP wait_poll

; ---- attr_thin_check: B9 THIN
attr_thin_check:
        LD A,(CUR_CHAR)
        CP ATTR_THIN
        RET nz
        LD (THIN_MODE),A
        POP HL
        JP render_next_char

; ---- attr_draw_check: B8 DRAW: hex digit pairs -> DRAW_BUF columns, up to
;      16, ended by the first non-hex byte
attr_draw_check:
        LD A,(CUR_CHAR)

; ---- attr_draw: 0xB8: user-drawn graphic follows
attr_draw:
        CP ATTR_DRAW
        JR z,draw_begin
        LD A,0
        LD (DRAW_PREV),A
        LD A,(CUR_CHAR)
        RET

draw_begin:
        LD A,(DRAW_PREV)
        LD (DRAW_NO_GAP),A
        LD A,0xff
        LD (DRAW_PREV),A
        LD HL,DRAW_BUF
        PUSH HL
        PUSH HL
        LD B,0x10

draw_clear:
        LD (HL),0
        INC HL
        DJNZ draw_clear
        CALL clear_glyph_tmp
        POP HL
        LD C,0
        LD B,0x10

draw_hex_loop:
        CALL fetch_char
        LD A,(CUR_CHAR)
        CALL hex_digit_value
        CP 0xff
        JR z,draw_bad_hex
        PUSH AF
        CALL fetch_char
        LD A,(CUR_CHAR)
        CALL hex_digit_value
        CP 0xff
        JR z,draw_pop_odd
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
        AND A
        JP nz,draw_set_width
        XOR A
        LD (DRAW_NO_GAP),A
        LD A,0x20
        LD (CUR_CHAR),A
        RET

draw_set_width:
        LD (GLYPH_WIDTH),A
        POP HL
        LD A,(EFFECT_ID)
        AND A
        JP z,glyph_place
        CALL glyph_bold
        LD A,(GLYPH_WIDTH)
        DEC A
        LD (GLYPH_WIDTH),A
        JP glyph_place

draw_pop_odd:
        POP AF

draw_bad_hex:
        LD A,(CUR_CHAR)
        CP TEXT_END
        JR nz,draw_abort
        CALL unfetch_char

draw_abort:
        LD A,0x2a
        LD (CUR_CHAR),A
        JP draw_finish

; ---- hex_digit_value: A = value of ASCII hex digit, FF if not one
hex_digit_value:
        CP 0x30
        JP c,hexval_bad
        CP 0x3a
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

; ---- magic_preprocess: MAGIC mode: random font per word, colour change every
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
        CP 0x20
        RET nz
        POP HL
        JP fx_flush_stage

magic_char:
        LD A,(CUR_CHAR)
        CP 0x20
        JR nz,magic_attr
        LD HL,MAGIC_WORD_COUNT
        INC (HL)
        LD A,2
        LD (FONT_MODE),A
        LD A,(MAGIC_LAST_CHAR)
        CP 0x2e
        JP z,magic_reseed
        CP 0x21
        JP z,magic_reseed
        CP 0x3f
        JP z,magic_reseed
        CP 0x3a
        JP z,magic_reseed
        CP 0x2c
        JP z,magic_reseed
        LD A,0x20
        LD (MAGIC_LAST_CHAR),A
        JP magic_ret

magic_attr:
        CP ATTR_HOLD
        JR z,magic_effect_attr
        CP 15
        JR z,magic_effect_attr
        CP ATTR_PAUSE
        JR c,magic_other
        CP ATTR_DOWN+1
        JR nc,magic_other

magic_effect_attr:
        XOR A
        LD (MAGIC_FONT_SET),A
        LD (MAGIC_COLOUR_SET),A
        LD A,(MAGIC_FX_PREV)
        AND A
        RET nz
        LD A,0xff
        LD (MAGIC_FX_PREV),A
        LD A,(TEXT_DRAWN)
        AND A
        RET z
        LD A,(CUR_CHAR)
        PUSH AF
        LD B,14

magic_push_off:
        PUSH BC
        LD A,0x20
        LD (CUR_CHAR),A
        XOR A
        LD (EFFECT_ID),A
        LD HL,fxv_none
        LD (EFFECT_VECTOR),HL
        LD A,6
        LD (GLYPH_WIDTH),A
        LD HL,FONT+8*32
        LD (GLYPH_PTR),HL
        CALL glyph_blit
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
        CP ATTR_DRAW
        JP z,magic_printable
        AND 0xf0
        CP GRAPH_BASE
        JP z,magic_printable
        CP 0x20
        JP c,magic_ret
        CP COLOUR_BASE
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
        JP z,magic_colour_check
        LD A,(MAGIC_FONT_SET)
        AND A
        LD A,0
        LD (MAGIC_FONT_SET),A
        JR nz,magic_count_words
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
        JP nc,magic_colour_check
        LD A,(RND_VAL)
        AND A
        JP z,magic_reseed
        DEC A
        JP z,magic_reseed
        LD (RND_VAL),A
        LD A,(MAGIC_COLOUR_SET)
        AND A
        JR z,magic_reset_words
        XOR A
        LD (MAGIC_COLOUR_SET),A
        LD (RND_VAL),A
        JP magic_reset_words

magic_reseed:
        LD A,(NMI_COUNT)
        LD E,A
        AND 3
        ADD A,2
        LD (RND_VAL),A

magic_colour_check:
        LD A,(MAGIC_COLOUR_SET)
        AND A
        JR z,magic_next_colour
        XOR A
        LD (MAGIC_COLOUR_SET),A
        LD (RND_VAL),A
        JP magic_reset_words

magic_next_colour:
        XOR A
        LD (RAINBOW_IDX),A
        LD A,(MAGIC_COLOUR_IDX)
        INC A
        LD E,A
        LD A,(NMI_COUNT)
        ADD A,E

magic_colour_try:
        AND 15
        LD (MAGIC_COLOUR_IDX),A
        LD E,A
        LD D,0
        LD HL,MAGIC_COLOUR_CYCLE
        ADD HL,DE
        LD A,(CUR_COLOUR)
        AND 15
        CP (HL)
        JR z,magic_colour_retry
        LD A,(CUR_COLOUR)
        LD E,A
        LD D,(HL)
        LD A,D
        LD HL,CUR_COLOUR
        RLD
        LD A,(HL)
        LD HL,MAGIC_CLASH_PAIRS
        LD BC,6
        OR A
        CPIR
        JP nz,magic_colour_apply
        LD A,E
        LD (CUR_COLOUR),A

magic_colour_retry:
        LD A,(MAGIC_COLOUR_IDX)
        INC A
        JR magic_colour_try

magic_colour_apply:
        LD A,E
        AND COLOUR_FLASH
        OR D
        AND 0x1f
        LD (CUR_COLOUR),A

magic_reset_words:
        XOR A
        LD (MAGIC_WORD_COUNT),A

magic_ret:
        RET

; ---- MAGIC_CLASH_PAIRS: (old<<4 | new) foreground pairs too alike to follow each
;      other in MAGIC mode: yellow/lime, yellow/orange, red/orange
MAGIC_CLASH_PAIRS:
        db 0xf7,0x7f,0xfd,0xdf,0xcd,0xdc
; ---- MAGIC_COLOUR_CYCLE: the 16 foregrounds MAGIC mode walks through
MAGIC_COLOUR_CYCLE:
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
        CALL pkt_poll
        LD A,(FRAME_DELAY)
        AND A
        JR nz,effect_step

fx_wait_scroll:
        CALL pkt_poll
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

fx_done:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP ATTR_WAIT
        JR nz,fx_done_effect
        XOR A
        LD (FRAME_DELAY),A

fx_done_effect:
        LD A,(EFFECT_ID)
        AND A
        JR z,fx_reset_stage
        LD A,(MAGIC_MODE)
        AND A
        JR z,fx_toggle_flush
        LD A,15
        LD (CUR_COLOUR),A

fx_toggle_flush:
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

; ---- attr_dispatch: 11 NORM,12 BOLD,13 ITALIC,14 FLASH,10 BIG,1F MAGIC; the rest go
;      through fx_attr: 06 HALT,07 BEEP,03 END,18 LEFT,19 PAUSE,1A UP,1B DOWN,0F RIGHT,BB HOLD
attr_dispatch:
        CP ATTR_NORM
        JP nz,attr_not_norm
        XOR A
        LD (FLASH_BIT),A
        LD (FONT_MODE),A
        JP attr_set_font

attr_not_norm:
        CP ATTR_BOLD
        JP nz,attr_not_bold
        LD A,2
        JP attr_set_font

attr_not_bold:
        CP ATTR_ITALIC
        JP nz,attr_not_italic
        LD A,6
        JP attr_set_font

attr_not_italic:
        CP ATTR_FLASH
        JP nz,attr_not_flash
        LD A,COLOUR_FLASH
        LD (FLASH_PENDING),A
        JP render_next_char

attr_not_flash:
        CP ATTR_BIG
        JR nz,attr_not_big
        LD A,10

attr_set_font:
        LD (FONT_MODE),A
        LD A,0xff
        LD (MAGIC_FONT_SET),A
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
        CP ATTR_HOLD
        JP z,fx_hold
        JP render_next_char

; ---- fx_beep
fx_beep:
        CALL beep_start
        JP render_next_char

; ---- beep_start: BEEP_TICKS = BEEP_LEN (~115 ms)
beep_start:
        PUSH HL
        LD HL,BEEP_LEN
        LD (BEEP_TICKS),HL
        POP HL
        RET

; ---- fx_end_of_channel
fx_end_of_channel:
        LD HL,fxv_none
        LD (EFFECT_VECTOR),HL
        XOR A
        LD (EFFECT_ID),A
        CALL scroll_off_text
        LD SP,STACK_TOP
        JP main_loop

; ---- fx_right: 0F: reveal the staged text left to right, a column per frame
fx_right:
        XOR A
        LD (SCROLLING),A
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        LD A,4
        LD HL,fxv_right
        JP set_effect_vector

; ---- fx_left: 18: plain crawl, no staging
fx_left:
        XOR A
        LD (COL_COUNT),A
        LD HL,fxv_none
        JP set_effect_vector

; ---- fx_hold: BB: blank, then reveal the staged text right to left
fx_hold:
        XOR A
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        LD A,5
        LD HL,fxv_hold
        JP set_effect_vector

; ---- fx_pause: 19: show the staged text at once and hold HOLD_FRAMES frames
fx_pause:
        XOR A
        LD (SCROLLING),A
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        LD A,1
        LD HL,fxv_pause
        JP set_effect_vector

; ---- fx_up: 1A: reveal the staged text row by row from the top
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

; ---- fx_magic
fx_magic:
        XOR A
        LD (FLASH_PENDING),A
        LD (MAGIC_COLOUR_SET),A
        LD (MAGIC_FONT_SET),A
        LD (RAINBOW_IDX),A
        LD (MAGIC_FX_PREV),A
        LD A,0xff
        LD (MAGIC_MODE),A
        LD A,0x20
        LD (MAGIC_LAST_CHAR),A
        LD A,1
        LD (MAGIC_WORD_COUNT),A
        LD A,(NMI_COUNT)
        LD E,A
        AND 3
        ADD A,2
        LD (RND_VAL),A
        CALL magic_first_colour
        JP render_next_char

; ---- magic_first_colour: first colour of the cycle when MAGIC starts
magic_first_colour:
        LD A,(MENU_ACTIVE)
        AND A
        RET nz
        LD A,(EFFECT_ID)
        AND A
        RET nz
        LD A,(MAGIC_COLOUR_IDX)
        INC A
        AND 15
        LD (MAGIC_COLOUR_IDX),A
        LD E,A
        LD D,0
        LD HL,MAGIC_COLOUR_CYCLE
        ADD HL,DE
        LD A,(HL)
        AND 15
        LD (CUR_COLOUR),A
        RET

; ---- attr_magic_off: 0xBD: leave MAGIC mode, default colour and font
attr_magic_off:
        XOR A
        LD (MAGIC_MODE),A
        LD (MAGIC_FONT_SET),A
        LD (MAGIC_COLOUR_SET),A
        LD (FONT_MODE),A
        LD A,COLOUR_DEFAULT
        LD (CUR_COLOUR),A
        JP render_next_char

; ---- fx_halt: 06: hold 0x50 frames (~1.3 s) with the colours reset
fx_halt:
        XOR A
        LD (SCROLLING),A
        LD A,(EFFECT_ID)
        AND A
        JR nz,halt_hold

halt_wait_frames:
        CALL pkt_poll
        LD A,(FRAME_DELAY)
        AND A
        JR nz,halt_wait_frames

halt_hold:
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A
        CALL fb_colours_default
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP ATTR_LEFT
        JP z,fx_left
        LD A,(EFFECT_ID)
        AND A
        JP z,fx_left
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        JP render_next_char

; ---- fb_colours_default: every colour byte in FRAMEBUF -> 8F, keeping flash
fb_colours_default:
        LD HL,FRAMEBUF
        LD BC,FRAMEBUF_SIZE

fbcol_loop:
        BIT 7,(HL)
        JR z,fbcol_next
        LD A,(HL)
        AND COLOUR_FLASH
        OR 0x8f
        LD (HL),A

fbcol_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,fbcol_loop
        LD A,(WINDOW_COLOUR)
        AND COLOUR_FLASH
        OR 0x8f
        LD (WINDOW_COLOUR),A
        LD (ROW_COLOUR),A
        LD E,A
        LD A,(MAGIC_MODE)
        AND A
        RET z
        LD A,15
        LD (CUR_COLOUR),A
        RET

; ---- attr_colour_speed: 0x8x foreground colour, 0x9x background, 0xFx speed, 0xBD MAGIC OFF
attr_colour_speed:
        LD A,(CUR_CHAR)
        AND 0xf0
        CP COLOUR_BASE
        JP z,attr_fore_colour
        CP BGRND_BASE
        JP z,attr_back_colour
        CP SPEED_BASE
        JP z,attr_speed
        LD A,(CUR_CHAR)
        CP ATTR_MAGIC_OFF
        JP z,attr_magic_off
        JP render_next_char

; ---- attr_fore_colour
attr_fore_colour:
        XOR A
        LD (RAINBOW_IDX),A
        LD A,(MAGIC_MODE)
        AND A
        JR z,fore_set
        LD A,(CUR_COLOUR)
        AND 0xcf
        LD (CUR_COLOUR),A

fore_set:
        LD A,(CUR_CHAR)
        AND 15
        LD E,A
        LD A,(CUR_COLOUR)
        AND 0x60
        OR E
        LD (CUR_COLOUR),A
        LD A,0xff
        LD (MAGIC_COLOUR_SET),A
        JP render_next_char

; ---- attr_back_colour
attr_back_colour:
        LD A,(MAGIC_MODE)
        AND A
        JR z,back_set
        LD A,(CUR_COLOUR)
        OR 15
        LD (CUR_COLOUR),A

back_set:
        XOR A
        LD (RAINBOW_IDX),A
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
        LD A,(CUR_COLOUR)
        AND 15
        OR L
        AND 0x6f
        LD (CUR_COLOUR),A
        LD A,0xff
        LD (MAGIC_COLOUR_SET),A
        JP render_next_char

; ---- attr_speed
attr_speed:
        LD A,(CUR_CHAR)
        AND 7
        LD (SCROLL_SPEED),A
        JP render_next_char

; ---- attr_tiny: 0xBE: switch to tiny (28-char) font mode and render
attr_tiny:
        CALL tiny_scroll_off
        CALL clear_framebuf
        LD A,0xff
        LD (TINY_RENDER),A
        LD A,COLOUR_DEFAULT
        LD (FRAMEBUF_TINY),A

tiny_loop:
        CALL tiny_get_glyph
        AND A
        JR nz,tiny_end
        CALL tiny_scroll_cols
        LD HL,(STORE_CURSOR)
        INC HL
        LD (STORE_CURSOR),HL
        JR tiny_loop

tiny_end:
        CALL tiny_scroll_out
        CALL clear_framebuf
        XOR A
        LD (TINY_RENDER),A
        CALL init_render
        JP render_loop

; ---- tiny_scroll_off: push existing text off before TINY text
tiny_scroll_off:
        ; Stock scanned 86 bytes from the ADDRESS of FB_COL (LD HL,FB_COL, a typo
        ; for the pointer) looking for a colour byte; a 0x95 constant sat three
        ; bytes in, so the test never failed. P8 drops the scan and the bytes.
        LD B,14

tinyoff_loop:
        PUSH BC
        LD A,0x20
        LD (CUR_CHAR),A
        XOR A
        LD (EFFECT_ID),A
        LD HL,fxv_none
        LD (EFFECT_VECTOR),HL
        LD A,6
        LD (GLYPH_WIDTH),A
        LD HL,FONT+8*32
        LD (GLYPH_PTR),HL
        CALL glyph_blit
        CALL effect_step
        POP BC
        DJNZ tinyoff_loop
        RET

; ---- tiny_get_glyph: glyph for the byte at STORE_CURSOR; A=FF ends tiny mode
tiny_get_glyph:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        LD (CUR_CHAR),A
        AND 0xf0
        CP GRAPH_BASE
        JR nz,tinyg_check
        LD A,(CUR_CHAR)
        AND 15
        LD (CUR_CHAR),A
        JR tinyg_lookup

tinyg_check:
        LD A,(CUR_CHAR)
        AND 0x60
        JP z,tinyg_stop
        LD A,(CUR_CHAR)
        CP ATTR_TIME
        JP z,tinyg_stop
        BIT 7,A
        JP z,tinyg_lookup
        CP 0x94
        JP c,tinyg_stop
        CP 0x9e
        JR c,tinyg_lookup
        AND 0xf0
        CP 0xc0
        JR z,tinyg_lookup
        CP 0xe0
        JP nz,tinyg_stop

tinyg_lookup:
        LD HL,FONT
        LD A,(CUR_CHAR)
        CALL char_to_glyph
        LD E,A
        LD D,0
        SLA E
        RL D
        SLA E
        RL D
        SLA E
        RL D
        ADD HL,DE
        PUSH HL
        LD DE,7
        ADD HL,DE
        LD A,(HL)
        LD (GLYPH_WIDTH),A
        POP HL

; ---- tiny_put_glyph: colour byte + glyph into FRAMEBUF_TINY
tiny_put_glyph:
        LD DE,FRAMEBUF_TINY+1
        LD B,0
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD A,COLOUR_DEFAULT
        LD (DE),A
        INC DE
        LDIR
        XOR A
        RET

tinyg_stop:
        LD A,0xff
        RET

; ---- tiny_scroll_cols: scroll the tiny buffer GLYPH_WIDTH+1 columns
tiny_scroll_cols:
        LD A,(GLYPH_WIDTH)
        INC A

tinysc_loop:
        LD HL,FRAMEBUF+1
        LD DE,FRAMEBUF
        LD BC,0xbc
        LDIR
        PUSH AF
        CALL tiny_copy_frame
        POP AF
        DEC A
        JR nz,tinysc_loop
        RET

; ---- tiny_copy_frame: wait for the panel, copy every other column
tiny_copy_frame:
        LD HL,FRAMEBUF
        LD DE,TXBUF             ; P7: the TINY output frame lives in TXBUF
        LD BC,FRAME_COLS
        LD A,(TINY_FRAME_READY)
        AND A
        JR nz,tiny_copy_frame

tinycp_loop:
        LDI
        INC HL
        JP pe,tinycp_loop
        LD A,0xff
        LD (TINY_FRAME_READY),A
        RET

; ---- tiny_scroll_out: 28 spaces to clear the tiny line
tiny_scroll_out:
        LD B,0x1c

tinyout_loop:
        PUSH BC
        LD A,0x20
        LD (CUR_CHAR),A
        LD A,5
        LD (GLYPH_WIDTH),A
        LD HL,FONT+8*32
        CALL tiny_put_glyph
        CALL tiny_scroll_cols
        POP BC
        DJNZ tinyout_loop
        RET

tiny_refresh:
        LD A,(TINY_FRAME_READY)
        AND A
        JR nz,tiny_row_out
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        JP rx_consume

tiny_row_out:
        LD A,(ROW_OUT_PENDING)
        AND A
        JP z,disp_next_row
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A

; ---- disp_blank_row: Send 0x8F (all off) to the current row
disp_blank_row:
        LD HL,TXBUF             ; P7: see tiny_copy_frame
        LD B,FRAME_COLS
        LD C,0x48
        LD A,(ROW_INDEX)
        CPL
        AND 7
        DEC A
        OR C
        LD C,A
        RES 5,C
        LD A,COLOUR_DEFAULT
        OUT (C),A
        OTIR
        OUT (PORT_STROBE),A
        LD A,(ROW_INDEX)
        CPL
        AND 7
        DEC A
        JR nz,tiny_row_select
        LD A,7

tiny_row_select:
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
        XOR A
        LD (ROW_OUT_PENDING),A
        JP tick6_restore

; ---- disp_next_row: ROW_INDEX = (ROW_INDEX+1) mod 7
disp_next_row:
        LD A,(ROW_INDEX)
        LD C,A
        INC A
        LD (ROW_INDEX),A
        CP 7
        JP c,tick6_arm_row
        LD A,0
        LD (ROW_INDEX),A
        LD (TINY_FRAME_READY),A
        JP rx_consume

; ---- fxv_prepare: clear FRAMEBUF and reset the output window; HL = TXBUF,
;      DE = FRAMEBUF + STAGE_OFFSET (the staged text is centred)
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
        LD DE,FRAMEBUF
        LD (FB_COL),DE
        LD (FB_OUT_PTR),DE
        LD HL,(STAGE_OFFSET)
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
        CALL pkt_poll
        LD A,(FRAME_DELAY)
        AND A
        JR nz,right_wait_frame
        DJNZ right_wait_row
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A
        XOR A
        LD (SCROLLING),A
        JP fx_done

; ---- fxv_none: effect handler: nothing (straight to render loop)
fxv_none:
        JP fx_done

; ---- fxv_hold: effect 5: fill with 0x8F (no columns lit), then copy one staged
;      column per frame, right to left
fxv_hold:
        LD HL,FRAMEBUF
        LD BC,FRAMEBUF_SIZE

hold_fill:
        LD (HL),COLOUR_DEFAULT
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,hold_fill
        CALL fxv_pointers
        LD A,(COL_COUNT)
        PUSH HL
        LD H,0
        LD L,A
        ADD HL,DE
        POP DE
        EX DE,HL
        LD C,A
        LD B,0
        ADD HL,BC
        LD B,A
        INC B

hold_wait_row:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,hold_wait_row
        LD A,(HL)
        LD (DE),A
        DEC HL
        DEC DE
        LD A,0xff
        LD (DISP_ON),A
        LD A,1
        LD (FRAME_DELAY),A

hold_wait_frame:
        CALL pkt_poll
        LD A,(FRAME_DELAY)
        AND A
        JR nz,hold_wait_frame
        DJNZ hold_wait_row
        LD A,HOLD_FRAMES
        LD (FRAME_DELAY),A
        XOR A
        LD (SCROLLING),A
        JP fx_done

; ---- fxv_pause: effect 1: copy the whole stage, then FRAME_DELAY 0x50
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
        JP fx_done

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
        JR nz,wipev_colour_byte
        AND C
        JR wipev_store

wipev_colour_byte:
        LD A,C
        CP 0xff
        LD A,COLOUR_DEFAULT
        JR nz,wipev_store
        LD A,(HL)

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
        CALL pkt_poll
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
        JP fx_done

; ---- store_clear_all: Reset MSG_STORE: 100 empty channels D0..? then DA
store_clear_all:
        LD A,MARK_LO
        LD C,0xd0
        LD HL,MSG_STORE
        LD B,0x64

clr_chan_loop:
        LD (HL),A
        INC HL
        LD (HL),C
        INC HL
        LD (HL),TEXT_END
        INC HL
        INC C
        LD D,A
        LD A,C
        CP 0xda
        JR nz,clr_chan_next
        LD C,0xd0
        INC D

clr_chan_next:
        LD A,D
        DJNZ clr_chan_loop
        LD A,MARK_HI
        LD (HL),A
        LD HL,SEQ_LIST
        LD (HL),MARK_HI
        LD B,0x67

clr_seq_loop:
        INC HL
        LD (HL),0xff
        DJNZ clr_seq_loop
        RET

; ---- store_init: message-store init. Sets the store
;      ceiling and its three derived constants, writes the 0xDA store
;      terminator at the ceiling, then zeroes 0x5EF0..0x5FFF (PKT_READY,
;      PKT_BUF and the parser state, i.e. the whole top page of RAM).
;      0x43DE = ceiling-100, the "100 KEYS LEFT" trip point (used at 0x2601).
;      0x43DC = free text bytes, the scan bound used by store_repair at 0x0481.
store_init:
        LD A,0xff
        ; P13: which chip? An 8 K RAM mirrors 6000 onto 4000. FRAMEBUF is
        ; scratch at this point (the stub's library copy, cleared by init_render).
        LD A,0x55
        LD (FRAMEBUF),A
        CPL
        LD (FRAMEBUF+0x2000),A
        LD HL,STORE_TOP
        LD A,(FRAMEBUF)
        CP 0x55
        JR z,store_init_limits
        LD HL,STORE_TOP_8K

store_init_limits:
        LD (STORE_LIMIT),HL
        LD (STORE_END),HL
        PUSH HL
        LD DE,100
        OR A
        SBC HL,DE
        LD (STORE_WARN_LIMIT),HL
        POP HL
        LD DE,MSG_STORE-1
        OR A
        SBC HL,DE               ; size = top - MSG_STORE + 1
        LD (STORE_SIZE),HL
        LD DE,301
        OR A
        SBC HL,DE
        LD (STORE_TEXT_LIMIT),HL
        ; P1: the store terminator no longer sits one byte below the page to
        ; be cleared, so write it first, then set HL/BC for the clear.
        LD HL,(STORE_LIMIT)
        LD (HL),MARK_HI
        LD BC,NMI_VEC-PKT_READY ; stop short of the boot stub's bytes
        LD HL,PKT_READY

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
        RET

; ---- ir_init: clear the IR decoder state, then fall into ir_reset
ir_init:
        PUSH AF
        XOR A
        LD (IR_DEBOUNCE),A
        LD (IR_CODE),A
        LD (IR_KEYNUM),A
        LD (IR_KEY),A
        LD (GEN_COUNTDOWN),A
        LD (GEN_COUNTDOWN+1),A
        LD (TICK1_COUNT),A

; ---- ir_reset: IR decoder: reset state, wait for leader (port C0 bit1)
ir_reset:
        LD A,0x82
        LD (IR_STATE_CNT),A
        LD A,6
        LD (IR_BITCNT),A
        XOR A
        LD (IR_SHIFT),A
        PUSH HL
        LD HL,ir_st_idle
        LD (TICK_VECTOR),HL
        POP HL
        POP AF
        RET

; ---- ir_st_idle
ir_st_idle:
        PUSH AF
        IN A,(PORT_IN)
        BIT 1,A
        JP nz,ir_reset
        LD A,(IR_STATE_CNT)
        DEC A
        JP nz,ir_idle_count
        PUSH HL
        LD HL,ir_st_leader
        LD (TICK_VECTOR),HL
        POP HL

ir_idle_count:
        LD (IR_STATE_CNT),A
        POP AF
        RET

; ---- ir_st_leader
ir_st_leader:
        PUSH AF
        IN A,(PORT_IN)
        BIT 1,A
        JP z,ir_leader_ret
        PUSH HL
        LD HL,ir_st_leader2
        LD (TICK_VECTOR),HL
        POP HL
        LD A,4
        LD (IR_STATE_CNT),A

ir_leader_ret:
        POP AF
        RET

; ---- ir_st_leader2
ir_st_leader2:
        PUSH AF
        IN A,(PORT_IN)
        BIT 1,A
        JP nz,ir_leader2_ret
        PUSH HL
        LD HL,ir_st_leader3
        LD (TICK_VECTOR),HL
        POP HL
        LD A,0x15
        LD (IR_STATE_CNT),A

ir_leader2_ret:
        POP AF
        RET

; ---- ir_st_leader3
ir_st_leader3:
        PUSH AF
        LD A,(IR_STATE_CNT)
        DEC A
        JR nz,ir_leader3_count
        IN A,(PORT_IN)
        BIT 1,A
        JP z,ir_reset
        PUSH HL
        LD HL,ir_st_start
        LD (TICK_VECTOR),HL
        POP HL
        LD A,3

ir_leader3_count:
        LD (IR_STATE_CNT),A
        POP AF
        RET

; ---- ir_st_start
ir_st_start:
        PUSH AF
        LD A,(IR_STATE_CNT)
        DEC A
        JP nz,ir_start_count
        IN A,(PORT_IN)
        BIT 1,A
        JP nz,ir_reset
        PUSH HL
        LD HL,ir_st_bits
        LD (TICK_VECTOR),HL
        POP HL
        LD A,8

ir_start_count:
        LD (IR_STATE_CNT),A
        POP AF
        RET

; ---- ir_st_bits: sample a data bit (port C0 bit1) into IR_SHIFT every 4 ticks
ir_st_bits:
        PUSH AF
        LD A,(IR_STATE_CNT)
        DEC A
        JP z,ir_bit_verify
        CP 4
        JP nz,ir_bit_count
        LD (IR_STATE_CNT),A
        PUSH HL
        LD HL,IR_SHIFT
        RRC (HL)
        IN A,(PORT_IN)
        AND 2
        OR (HL)
        LD (IR_SHIFT),A
        POP HL
        POP AF
        RET

ir_bit_verify:
        PUSH HL
        LD A,(IR_SHIFT)
        CPL
        AND 2
        LD L,A
        IN A,(PORT_IN)
        AND 2
        CP L
        POP HL
        JP nz,ir_reset
        LD A,(IR_BITCNT)
        DEC A
        LD (IR_BITCNT),A
        JP z,ir_frame_done
        LD A,8

ir_bit_count:
        LD (IR_STATE_CNT),A
        POP AF
        RET

ir_frame_done:
        LD A,(IR_SHIFT)
        RRCA
        RRCA
        RRCA
        RRCA
        OR 0x80
        LD (IR_CODE),A
        JP ir_reset

; ---- tx_send_byte: Queue byte A for bit-banged transmission; blocks until the previous byte is out
tx_send_byte:
        PUSH HL
        PUSH DE

tx_wait_slot:
        CALL tx_try_queue
        JR c,tx_wait_slot
        POP DE
        POP HL
        RET

; ---- tx_try_queue: queue A; CY if the transmitter was busy and nothing was queued.
;      B10: stock signalled "queued" with A = 0 and "busy" with A unchanged, so a
;      0x00 byte offered to a busy transmitter was silently dropped.
tx_try_queue:
        LD HL,TX_STATUS
        BIT 1,(HL)
        SCF
        RET nz
        LD (TX_PENDING),A
        SET 1,(HL)
        XOR A
        RET

; ---- tx_bit_engine: Called every 6 ticks: shifts TX_SHIFT out on CTRL_LATCH bit 4 (1=start/space, 0=mark). Bit times from TX_TIMING table (4,4,5 ticks); state 9 = stop bits (10 ticks)
tx_bit_engine:
        LD HL,TX_STATUS
        BIT 0,(HL)
        JR nz,tx_bit_tick
        BIT 1,(HL)
        JR z,tx_stream_next     ; P21: nothing queued, feed the background reply

tx_start_byte:
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

; ---- tx_stream_next (P21): the background transmitter. Sends TX_SEG0, then
;      its sum if flagged, then TX_SEG1 the same way, then DONE if pending;
;      when all of that is out, the packet is no longer busy.
tx_stream_next:
        LD HL,(TX_SEG0+2)
        LD A,H
        OR L
        JR z,tx_stream_end
        DEC HL
        LD (TX_SEG0+2),HL
        LD HL,(TX_SEG0)
        LD C,(HL)
        INC HL
        LD (TX_SEG0),HL
        LD A,(TX_SUM)
        ADD A,C
        LD (TX_SUM),A
        LD A,C

tx_stream_queue:
        LD (TX_PENDING),A
        LD HL,TX_STATUS
        SET 1,(HL)
        JP tx_start_byte

tx_stream_end:
        LD HL,TX_SEG0+4
        BIT 0,(HL)
        JR z,tx_stream_shift
        RES 0,(HL)
        LD A,(TX_SUM)
        JR tx_stream_queue

tx_stream_shift:
        LD HL,(TX_SEG1+2)
        LD A,H
        OR L
        JR z,tx_stream_done
        LD HL,TX_SEG1
        LD DE,TX_SEG0
        LD BC,5
        LDIR
        XOR A
        LD (TX_SUM),A
        LD (TX_SEG1+2),A
        LD (TX_SEG1+3),A
        JR tx_stream_next

tx_stream_done:
        LD HL,TX_DONE_PENDING
        LD A,(HL)
        OR A
        JR z,tx_stream_idle
        LD (HL),0
        LD A,DONE_BYTE
        JR tx_stream_queue

tx_stream_idle:
        LD A,(TX_ACTIVE)
        OR A
        RET z
        XOR A
        LD (TX_ACTIVE),A
        LD (PKT_BUSY),A
        RET

; ---- rx_bit_engine: Called every 6 ticks: bit-banged receiver state machine on PORT_IN bit 3 (1 = space). Uses RX_TIMING table; assembled bytes go to RX_FIFO (8 deep, RX_COUNT)
rx_bit_engine:
        LD A,(RX_COUNT)
        CP 8
        JR nz,rx_tick
        LD HL,rx_st_wait_start
        LD (RX_STATE),HL
        LD A,0
        LD (RX_TICKS),A
        RET

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

; ---- data 164a-1653: ticks between RX bit samples (start,8 data,stop)
RX_TIMING:
        db 0x06,0x04,0x05,0x04,0x04,0x05,0x04,0x04,0x05,0x04

; ---- data 1654-165d: ticks per TX bit: start,8 data (4,4,5 pattern = 300 baud @ ~1300 Hz), stop = 10
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

; ---- rx_fifo_get: Pop one byte from RX_FIFO into RX_BYTE. Returns NC with A=byte, or C if empty
rx_fifo_get:
        LD A,(RX_COUNT)
        AND A
        JR z,rx_fifo_empty
        LD HL,RX_FIFO
        LD A,(HL)
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

rx_fifo_empty:
        XOR A
        LD (RX_BYTE),A
        SCF
        RET

; ---- pkt_feed_byte: Feed RX_BYTE to the packet parser state in PKT_VECTOR
pkt_feed_byte:
        LD A,(RX_BYTE)
        LD HL,(PKT_VECTOR)
        JP (HL)

; ---- pkt_st_addr: store address byte -> PKT_ADDR
pkt_st_addr:
        LD (PKT_ADDR),A
        LD HL,pkt_st_flag
        LD (PKT_VECTOR),HL
        RET

; ---- pkt_st_flag: store 3rd header byte -> PKT_FLAG (0x80 from PC)
pkt_st_flag:
        LD (PKT_FLAG),A
        LD HL,pkt_st_len
        LD (PKT_VECTOR),HL
        RET

; ---- pkt_st_len: store length; reset checksum & PKT_PTR=PKT_BUF; len 0 goes straight to checksum state
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

; ---- pkt_st_data: store payload byte, PKT_CKSUM += byte
pkt_st_data:
        LD C,A
        LD A,(PKT_DISCARD)
        OR A
        LD HL,(PKT_PTR)
        JR nz,pkt_data_sum      ; P21: a frame that arrived while busy is not stored
        LD (HL),C

pkt_data_sum:
        LD A,(PKT_CKSUM)
        ADD A,C
        LD (PKT_CKSUM),A
        LD A,(PKT_REMAIN)
        DEC A
        JR z,pkt_data_last
        LD (PKT_REMAIN),A
        INC HL
        LD (PKT_PTR),HL
        RET

pkt_data_last:
        LD HL,pkt_st_cksum
        LD (PKT_VECTOR),HL
        RET

; ---- pkt_st_cksum: E = computed - received. Broadcast (0x2A): no reply. Own address: send ACK 06 / NAK 15. If OK and len>0 set PKT_READY (PKT_FLAG==0x80 -> process immediately)
pkt_st_cksum:
        LD E,A
        LD A,(PKT_DISCARD)
        OR A
        JR nz,pkt_discard_frame ; P21: arrived while busy: no reply, nothing kept
        LD A,(PKT_CKSUM)
        SUB E
        LD E,A
        LD A,(PKT_ADDR)
        CP ADDR_BROADCAST
        JR z,pkt_check_ok
        LD D,A
        LD A,(MY_ADDRESS)
        CP D
        JR nz,pkt_discard
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
        LD (PKT_READY),A        ; P21: the render loop picks it up at its next step
        XOR A
        LD (PKT_STATE),A
        RET

pkt_discard:
        XOR A
        LD (PKT_READY),A

pkt_discard_frame:
        XOR A
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

; ---- data 18e8-18f3: 10000,1000,100,10,1,-1 for bin_to_dec5
DEC_TABLE:
        dw 0x2710
        dw 0x03e8
        dw 0x0064
        dw 0x000a
        dw 0x0001
        dw 0xffff

; ---- clock_tick: NMI: NMI_COUNT to NMI_PER_SEC -> seconds -> minutes -> hours (12h, CLK_PM toggles)
clock_tick:
        LD A,(CLK_RUN)
        AND A
        RET z
        LD A,(NMI_COUNT)
        INC A
        LD (NMI_COUNT),A
        LD HL,NMI_PER_SEC
        CP (HL)
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

; ---- scroll_off_text: push the displayed text off by rendering 14 spaces
scroll_off_text:
        LD B,14
        LD A,0
        LD (FONT_MODE),A

scrolloff_loop:
        LD A,0x20
        LD (CUR_CHAR),A
        PUSH BC
        CALL render_cur_char
        CALL effect_step
        POP BC
        DJNZ scrolloff_loop
        RET

; ---- clear_framebuf: FRAMEBUF (344 bytes) = 0x80
clear_framebuf:
        PUSH HL
        PUSH BC
        LD HL,FRAMEBUF
        LD BC,FRAMEBUF_SIZE

clrfb_loop:
        LD (HL),0x80
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,clrfb_loop
        POP BC
        POP HL
        RET

; ---- clear_txbuf: zero the staging frame at TXBUF
clear_txbuf:
        PUSH HL
        PUSH BC
        LD HL,TXBUF
        LD B,FRAME_COLS

clrtx_loop:
        LD (HL),0
        INC HL
        DJNZ clrtx_loop
        POP BC
        POP HL
        RET

; ---- clear_glyph_tmp
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

; ---- key_handler: Handle a key / IR code: menu navigation (ADDRESS?, TIME?, PROG MSG?, SEQ MSG? ...)
key_handler:
        LD A,0xff
        LD (CAPS_LOCK),A
        LD A,1
        LD (KEY_ECHO_TX),A

editor_start:
        LD SP,STACK_TOP
        LD A,0xff
        LD (MENU_ACTIVE),A
        EI
        CALL init_render
        LD A,(IR_CODE)
        CP 0xa4
        JR nz,editor_init
        CALL beep_start

editor_stop_wait:
        LD A,0xfe
        LD (IR_CODE),A
        LD HL,0x01a0
        LD (GEN_COUNTDOWN),HL

editor_stop_poll:
        LD A,(IR_CODE)
        CP 0xa4
        JR z,editor_stop_wait
        CP 0xfe
        JR nz,editor_init
        LD HL,(GEN_COUNTDOWN)
        LD A,H
        OR L
        JR nz,editor_stop_poll

editor_init:
        CALL ir_init
        XOR A
        LD (RX_BYTE),A
        LD (IR_KEY_CHAR),A
        LD (SEQ_SET),A
        LD A,(TEST_MODE)
        INC A
        JR nz,editor_find_marker
        XOR A
        LD (TEST_MODE),A
        CALL chan_select
        LD (STORE_CURSOR),HL
        CALL clear_chan_lock

editor_find_marker:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,editor_scan_back
        CP MARK_HI+1
        JP nc,editor_scan_back
        DEC HL
        DEC HL
        LD A,(HL)
        CP MARK_LO
        JP c,editor_cursor_set
        CP MARK_HI+1
        JP nc,editor_cursor_set
        DEC HL
        LD (STORE_CURSOR),HL
        JP editor_marker_skip

editor_cursor_set:
        LD (STORE_CURSOR),HL

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
        CP MARK_LO
        JP c,editor_scan_next
        CP MARK_HI+1
        JP nc,editor_scan_next
        JR editor_set_ins

editor_scan_next:
        DEC HL
        DEC BC
        LD A,C
        OR B
        JR nz,editor_scan_loop
        JP pkt_process_end

editor_marker_skip:
        INC HL

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

editor_dispatch:
        LD (SHIFT_LABEL),A
        LD A,(SEQ_MENU_ACTIVE)
        BIT 7,A
        JP nz,menu_seq_msg
        LD A,(EDIT_KEY)
        CP ATTR_MAGIC
        CALL z,magic_new_message
        XOR A
        LD (EDITOR_FIRST_KEY),A
        LD A,(EDIT_KEY)
        CP 1
        JP z,editor_next_key
        CP 3
        JP z,menu_clear_all
        CP 5
        JP z,show_top_of_msg
        CP 0x7f
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
        JP z,editor_clear_msg
        CP KEY_EURO
        JP z,editor_toggle_euro
        CP 0x5e
        JP z,menu_address
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
        CP 0xb1
        JP z,editor_exit
        JP editor_insert

; ---- magic_new_message: MAGIC as first key: take the first empty channel
;      (or ask via FULL!! MSG# ?), make it the whole sequence
magic_new_message:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,newmsg_from_0
        LD A,(EDITOR_FIRST_KEY)
        AND A
        RET z

newmsg_from_0:
        LD A,0

newmsg_try_chan:
        LD E,A
        PUSH DE
        CALL chan_select
        POP DE
        AND A
        JP nz,pkt_process_end
        LD A,(HL)
        CP TEXT_END
        JR z,newmsg_empty_found
        LD B,0
        LD C,A
        LD IX,CHAR_FLAGS
        ADD IX,BC
        BIT 1,(IX+0)
        JR z,newmsg_next_chan

newmsg_skip_attrs:
        INC HL
        LD A,(HL)
        CP TEXT_END
        JR nz,newmsg_skip_next
        LD A,E
        JP newmsg_select

newmsg_skip_next:
        LD B,0
        LD C,A
        LD IX,CHAR_FLAGS
        ADD IX,BC
        BIT 1,(IX+0)
        JR z,newmsg_next_chan
        JR newmsg_skip_attrs

newmsg_next_chan:
        LD A,E
        INC A
        CP 0x64
        JR nz,newmsg_try_chan
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL

newmsg_ask_full:
        LD HL,MENU_STR_MSG_FULL
        CALL menu_ask_chan
        CP 0x64
        JP nc,newmsg_ask_full

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
        DEC HL
        LD (STORE_CURSOR),HL

newmsg_set_seq:
        PUSH DE
        CALL clear_chan_lock
        POP DE
        LD A,E
        CP 0x64
        JR nz,newmsg_seq_fill
        LD (CHAN_LOCK),A

newmsg_seq_fill:
        LD HL,SEQ_LIST
        LD (HL),E
        INC HL
        LD B,0x67

newmsg_seq_loop:
        LD (HL),0xff
        INC HL
        DJNZ newmsg_seq_loop
        LD A,E
        LD (MAGIC_MSG_CHAN),A
        RET

; ---- store_finalize: Fix up MSG_STORE terminators after an edit
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

editor_show_invalid:
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_INVALID
        LD (MENU_MSG_PTR),HL
        JP editor_loop

; ---- editor_exit: STOP/START in the editor: add the channel to SEQ_LIST
;      if absent and go back to displaying
editor_exit:
        XOR A
        LD (SEQ_MENU_ACTIVE),A
        LD A,(KEY_ECHO_TX)
        AND A
        JR z,exit_wait_release
        CALL tx_send_byte
        JP exit_add_to_seq

exit_wait_release:
        LD A,(IR_CODE)
        CP ATTR_TINY
        JR z,exit_add_to_seq
        CP 0xa4
        JR z,exit_key_held
        CP 0xaf
        JR nz,exit_wait_release

exit_key_held:
        LD A,0xff
        LD (IR_CODE),A
        LD HL,0x028a
        LD (GEN_COUNTDOWN),HL

exit_held_poll:
        LD A,(IR_CODE)
        CP 0xa4
        JR z,exit_key_held
        CP 0xaf
        JR z,exit_key_held
        CP 0xff
        JR nz,exit_add_to_seq
        LD HL,(GEN_COUNTDOWN)
        LD A,H
        OR L
        JR nz,exit_held_poll

exit_add_to_seq:
        LD A,0xff
        LD (NEXT_CHAN),A
        LD A,(SEQ_SET)
        AND A
        JP nz,exit_to_display
        LD HL,(INS_PTR)
        DEC HL
        DEC HL
        LD B,2
        CALL ascii_dec_to_bin
        LD E,A
        LD HL,SEQ_LIST
        CP (HL)
        JP z,exit_to_display
        LD A,0x64
        CP (HL)
        JP nz,exit_seq_search
        LD A,E
        JP exit_seq_first

exit_seq_search:
        LD B,0x68

exit_seq_loop:
        LD A,(HL)
        CP E
        JP z,exit_seq_found
        CP 0xff
        JR z,exit_seq_insert
        INC HL
        DJNZ exit_seq_loop

exit_seq_insert:
        LD A,E
        LD HL,SEQ_LIST+102
        LD (HL),0xff
        LD DE,SEQ_LIST+103
        LD BC,0x67
        LDDR

exit_seq_first:
        LD HL,SEQ_LIST
        LD (HL),A
        JP exit_to_display

exit_seq_found:
        LD E,A
        LD (NEXT_CHAN),A

exit_to_display:
        LD SP,STACK_TOP
        XOR A
        LD (MENU_ACTIVE),A
        LD (FORCE_BOLD),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        JP restart_display

; ---- menu_time: 17: TIME? HHMM then AM? Y/N
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
        CP 0x3a
        JR nc,time_get_digit
        CP 0x30
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
        CALL pkt_poll
        LD A,(FRAME_DELAY)
        AND A
        JR nz,time_wait_loop
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STR_AM_PM
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

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
        JP editor_reshow

; ---- render_clock: 5F: emit H:MM AM/PM one character per call
render_clock:
        LD A,(MENU_ACTIVE)
        AND A
        JP nz,glyph_lookup
        LD A,(EFFECT_ID)
        AND A
        JR z,clock_step
        LD HL,FONT_MODE
        RES 2,(HL)

clock_step:
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
        LD A,0x3a
        LD (CUR_CHAR),A
        JP clock_emit

clock_not_colon:
        CP 6
        JR nz,clock_not_space
        LD A,0x20
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
        JR clock_emit_last

clock_digit:
        LD A,(HL)
        AND 15
        OR 0x30
        LD (CUR_CHAR),A
        INC HL
        LD A,(CLK_RENDER_STEP)
        LD (CLK_RENDER_PTR),HL

clock_emit:
        CALL unfetch_char
        LD A,(CUR_CHAR)
        JP glyph_lookup

clock_emit_last:
        LD A,0xff
        LD (CLK_RENDER_STEP),A
        LD A,(CUR_CHAR)
        JP glyph_lookup

; ---- menu_ask_chan_cur: ask for a channel number, prefilled from INS_PTR
menu_ask_chan_cur:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD (ASK_CHAN_PROMPT),HL
        JR askchan_prefill

; ---- menu_ask_chan: ask for a channel number; returns 0-99, 64 demo,
;      97 SEQ key, 98 MAGIC key, 99 A(ll), 9A blank + enter
menu_ask_chan:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD (ASK_CHAN_PROMPT),HL
        JP askchan_clear

askchan_prefill:
        LD HL,(INS_PTR)
        DEC HL
        LD A,(HL)
        CP 0xda
        JR nz,askchan_units_digit
        LD A,0x44
        JR askchan_store_units

askchan_units_digit:
        AND 15
        OR 0x30

askchan_store_units:
        LD (CHAN_D1),A
        DEC HL
        LD A,(HL)
        CP 0xda
        JR nz,askchan_tens_digit
        LD A,0x44
        JR askchan_store_tens

askchan_tens_digit:
        AND 15
        OR 0x30

askchan_store_tens:
        LD (CHAN_D10),A

askchan_show:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,(ASK_CHAN_PROMPT)
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        LD B,2
        LD HL,CHAN_D10

askchan_digits_loop:
        LD A,(HL)
        LD (CUR_CHAR),A
        PUSH HL
        PUSH BC
        CALL glyph_lookup
        POP BC
        POP HL
        INC HL
        DJNZ askchan_digits_loop

askchan_key:
        CALL menu_getchar
        LD (CUR_CHAR),A
        CP 4
        JP z,askchan_seq_key
        CP 8
        JR z,askchan_accept
        CP 9
        JR z,askchan_accept
        CP 13
        JR z,askchan_enter
        CP 14
        JR z,askchan_clear
        CP ATTR_MAGIC
        JP z,askchan_magic_key
        CP 0x7f
        JR z,askchan_backspace
        CP 'A'
        JR z,askchan_all
        CP 'a'
        JR z,askchan_all
        CP 'D'
        JR z,askchan_demo
        CP 'd'
        JR z,askchan_demo
        LD A,(CUR_CHAR)
        CALL is_digit
        JP nc,askchan_key
        LD IX,CHAN_D10
        LD A,(IX+1)
        LD (IX+0),A
        LD A,(CUR_CHAR)
        LD (IX+1),A
        JP askchan_show

askchan_backspace:
        LD IX,CHAN_D10
        LD A,(IX+0)
        LD (IX+1),A
        LD (IX+0),0x30
        JP askchan_show

askchan_accept:
        LD A,(CHAN_D10)
        OR 0x20
        CP 'd'
        JR z,askchan_demo
        LD A,(CHAN_D1)
        OR 0x20
        CP 'd'
        JR z,askchan_demo
        LD B,2
        LD HL,CHAN_D10
        CALL ascii_dec_to_bin

askchan_return:
        LD (ASK_CHAN_RESULT),A
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        LD A,(ASK_CHAN_RESULT)
        RET

askchan_clear:
        LD A,0x20
        LD (CHAN_D10),A
        LD (CHAN_D1),A
        JP askchan_show

askchan_enter:
        LD A,(CHAN_D1)
        CP 0x20
        JR nz,askchan_accept
        LD A,0x9a
        JR askchan_return

askchan_all:
        LD A,0x99
        JR askchan_return

askchan_demo:
        LD A,0x64
        JR askchan_return

askchan_seq_key:
        LD A,0x97
        JR askchan_return

askchan_magic_key:
        LD A,0x98
        JR askchan_return

; ---- menu_address: 5E (FUNC+MAGIC): ADDRESS? 1-255, never 0 or 2A
menu_address:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STRINGS
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        LD H,0
        LD A,(MY_ADDRESS)
        CP 0
        JR z,addr_default_1
        CP 0x2a
        JR nz,addr_to_ascii

addr_default_1:
        LD A,1

addr_to_ascii:
        LD L,A
        LD IX,MENU_ENTRY_BUF
        LD IY,DEC_TABLE+4
        CALL bin_to_dec_iy
        LD HL,MENU_ENTRY_BUF
        LD B,3

addr_skip_zeros:
        LD A,(HL)
        CP 0x30
        JR nz,addr_show_loop
        LD A,B
        CP 1
        JR z,addr_show_loop
        INC HL
        DJNZ addr_skip_zeros

addr_show_loop:
        LD A,(HL)
        CALL is_digit
        JP c,addr_show_digit
        LD A,0x30
        LD (HL),A

addr_show_digit:
        LD (CUR_CHAR),A
        PUSH HL
        PUSH BC
        CALL glyph_lookup
        POP BC
        POP HL
        INC HL
        DJNZ addr_show_loop
        LD HL,MENU_ENTRY_BUF
        LD B,0
        PUSH HL
        PUSH BC

addr_key:
        CALL menu_getchar
        LD (CUR_CHAR),A
        POP BC
        POP HL
        CP 8
        JR z,addr_enter
        CP 13
        JR z,addr_enter
        LD A,B
        CP 3
        JP z,menu_addr_invalid
        INC B
        LD A,(CUR_CHAR)
        CALL is_digit
        JP nc,menu_addr_invalid
        LD (HL),A
        INC HL
        PUSH HL
        PUSH BC
        LD A,B
        CP 1
        JR nz,addr_echo_digit
        CALL clear_framebuf
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STRINGS
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

addr_echo_digit:
        CALL glyph_lookup
        JP addr_key

addr_enter:
        LD A,B
        CP 0
        JR nz,addr_convert
        LD B,3

addr_convert:
        LD HL,MENU_ENTRY_BUF
        CALL ascii_dec_to_bin
        JP c,menu_addr_invalid
        CP 0x2a
        JP z,menu_addr_invalid
        CP 0
        JP z,menu_addr_invalid
        LD (MY_ADDRESS),A
        CPL
        LD (MY_ADDRESS_INV),A
        JP editor_reshow2

; ---- ascii_dec_to_bin: Convert B ASCII digits at (HL) to binary in A (C set if invalid)
ascii_dec_to_bin:
        PUSH BC
        LD IX,POW10_BYTES
        DEC B
        LD E,B
        LD D,0
        ADD IX,DE
        XOR A
        POP BC

a2b_digit_loop:
        PUSH BC
        LD E,A
        LD A,(HL)
        AND 15
        LD B,A
        CP 0
        LD A,E
        JR z,a2b_next

a2b_add_loop:
        ADD A,(IX+0)
        JR c,a2b_overflow
        DJNZ a2b_add_loop

a2b_next:
        INC HL
        DEC IX
        POP BC
        DJNZ a2b_digit_loop
        OR A
        RET

a2b_overflow:
        POP BC
        SCF
        RET
; ---- POW10_BYTES: place values 1, 10, 100 for ascii_dec_to_bin
POW10_BYTES:
        db 0x01,0x0a,"d"

; ---- is_digit: C set if A is ASCII 0-9
is_digit:
        CP 0x3a
        JR nc,not_digit
        CP 0x30
        JR c,not_digit
        SCF
        RET

not_digit:
        OR A
        RET

; ---- menu_addr_invalid
menu_addr_invalid:
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_INVALID
        LD (MENU_MSG_PTR),HL
        CALL editor_redraw
        JP menu_address

; ---- editor_goto_end: B3
editor_goto_end:
        LD HL,(STORE_CURSOR)

gotoend_loop:
        LD A,(HL)
        CP TEXT_END
        JR z,gotoend_back
        INC HL
        JR gotoend_loop

gotoend_back:
        DEC HL
        LD (STORE_CURSOR),HL
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,editor_loop
        CP MARK_HI+1
        JP nc,editor_loop
        DEC HL
        LD (STORE_CURSOR),HL
        JP show_top_of_msg

editor_reshow:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,editor_loop
        CP MARK_HI+1
        JP nc,editor_loop
        JP show_top_of_msg

; ---- show_top_of_msg: 05 and after most edits: "TOP OF MSG nn"
show_top_of_msg:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,STR_TOP_OF_MSG
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        LD B,2
        LD HL,(STORE_CURSOR)

top_digit_loop:
        LD A,(HL)
        CP 0xda
        JR nz,top_digit
        LD A,0x44
        JR top_emit

top_digit:
        AND 15
        OR 0x30
        CALL is_digit
        JP c,top_emit
        LD A,0x30
        LD (HL),A

top_emit:
        LD (CUR_CHAR),A
        PUSH HL
        PUSH BC
        CALL glyph_lookup
        POP BC
        POP HL
        INC HL
        DJNZ top_digit_loop
        JP editor_next_key

; ---- menu_clear_all: 03: CLR ALL Y/N
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
        CALL store_clear_all
        CALL store_finalize
        LD A,0
        JP editor_select_chan

editor_clear_msg:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_reshow
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
        CP MARK_LO
        LD HL,(STORE_CURSOR)

deltext_find_marker:
        LD A,(HL)
        CP MARK_LO
        JP c,deltext_back
        CP MARK_HI+1
        JP nc,deltext_back
        JR deltext_marker_end

deltext_back:
        DEC HL
        DEC BC
        LD A,B
        OR C
        JP z,pkt_process_end
        JP deltext_find_marker

deltext_marker_end:
        INC HL
        LD A,(HL)
        CP MARK_LO
        JP c,deltext_one_byte
        CP MARK_HI+1
        JP nc,deltext_one_byte
        JR deltext_move

deltext_one_byte:
        DEC HL

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
        LD HL,(STORE_CURSOR)
        DEC HL
        LD (STORE_CURSOR),HL
        RET

editor_toggle_caps:
        LD A,(CAPS_LOCK)
        CPL
        LD (CAPS_LOCK),A

editor_reshow2:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,editor_loop
        CP MARK_HI+1
        JP nc,editor_loop
        JP show_top_of_msg

editor_toggle_euro:
        LD A,(EURO_STATE)
        CPL
        LD (EURO_STATE),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,editor_loop
        CP MARK_HI+1
        JP nc,editor_loop
        JP show_top_of_msg

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

editor_key_func:
        LD A,0xff
        LD (FUNC_PENDING),A
        JP editor_loop

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

; ---- menu_prog_msg: 09: PROG MSG? channel
menu_prog_msg:
        LD HL,MENU_STR_PROG_MSG
        CALL menu_ask_chan_cur
        CP 0x65
        JP nc,menu_prog_msg
        LD E,A

editor_select_chan:
        PUSH DE
        CALL chan_select
        POP DE
        OR A
        JP nz,pkt_process_end
        LD (INS_PTR),HL
        DEC HL
        DEC HL
        LD (STORE_CURSOR),HL
        PUSH DE
        CALL clear_chan_lock
        POP DE
        LD A,E
        CP 0x64
        JR nz,editor_select_done
        LD (CHAN_LOCK),A

editor_select_done:
        JP show_top_of_msg

; ---- menu_seq_msg: 04: SEQ MSG? channels until blank+enter; A = all
menu_seq_msg:
        LD A,0xff
        LD (SEQ_SET),A
        LD HL,SEQ_LIST
        LD B,0x68
        LD A,0xff

seqmenu_clear:
        LD (HL),A
        INC HL
        DJNZ seqmenu_clear
        LD (SEQ_MENU_ACTIVE),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        LD B,0x67

seqmenu_loop:
        PUSH BC
        LD HL,MENU_STR_SEQ_MSG
        LD A,B
        CP 0x67
        JR z,seqmenu_first
        CALL menu_ask_chan
        JR seqmenu_result

seqmenu_first:
        CALL menu_ask_chan_cur

seqmenu_result:
        POP BC
        CP 0x98
        JR z,seqmenu_test_prompt
        CP 0x97
        JR z,seqmenu_done
        CP 0x99
        JR z,seqmenu_all
        CP 0x9a
        JP z,editor_exit
        LD HL,(SEQ_PTR)
        LD (HL),A
        INC HL
        LD (SEQ_PTR),HL
        DJNZ seqmenu_loop
        LD HL,MENU_STR_SEQ_FULL
        INC HL
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        CALL fb_rewind_window

seqmenu_done:
        LD A,0
        LD (SEQ_MENU_ACTIVE),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,editor_loop
        CP MARK_HI+1
        JP nc,editor_loop
        JP show_top_of_msg

seqmenu_test_prompt:
        CALL menu_getchar
        CP ATTR_BOLD
        JR z,seqmenu_test_prompt
        CP 0x43
        JR z,test_mode_enter
        CP 0x63
        JP nz,seqmenu_done

; ---- test_mode_enter: SEQ MSG? then MAGIC then C: TEST_MSG_BUF = "CURRENT
;      TEST" + sum of ROM 0000-3FFF as 4 hex digits, shown in TEST_MODE
test_mode_enter:
        LD A,0xff
        LD (TEST_MODE),A
        LD HL,TEST_MESSAGE
        LD DE,TEST_MSG_BUF

test_copy_loop:
        LD A,(HL)
        LD (DE),A
        CP 3
        JR z,test_rom_sum
        INC HL
        INC DE
        JR test_copy_loop

test_rom_sum:
        PUSH DE
        LD DE,0
        LD BC,0x4000
        LD HL,0

test_sum_loop:
        LD A,(DE)
        PUSH DE
        LD D,0
        LD E,A
        ADD HL,DE
        POP DE
        INC DE
        DEC BC
        LD A,C
        OR B
        JR nz,test_sum_loop
        POP DE
        CALL word_to_hex4
        INC DE
        INC DE
        INC DE
        INC DE
        LD A,3
        LD (DE),A
        JP editor_exit

seqmenu_all:
        LD HL,SEQ_LIST
        LD A,0
        LD B,0x64

seqmenu_all_fill:
        LD (HL),A
        INC HL
        INC A
        DJNZ seqmenu_all_fill
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        JP editor_exit

; ---- menu_getchar
menu_getchar:
        CALL editor_getkey
        LD A,(EDIT_KEY)
        AND A
        JR z,menu_getchar
        RET

; ---- editor_getkey: Editor key source: echoes the previous key on the serial TX, then takes a key from the serial RX FIFO if present, else from the IR decoder (IR_CODE). So the on-sign editor can be driven from a serial terminal as well as the remote.
editor_getkey:
        LD A,(KEY_ECHO_TX)
        AND A
        JR z,getkey_serial
        CALL tx_send_byte

getkey_serial:
        CALL rx_fifo_get
        JP c,getkey_ir
        AND A
        JR z,getkey_ir
        XOR A
        LD (EURO_STATE),A
        LD A,(RX_BYTE)
        LD (EDIT_KEY),A
        LD (KEY_ECHO_TX),A
        RET

getkey_ir:
        LD A,(IR_CODE)
        AND A
        JR z,getkey_none
        AND 0x3f
        LD (IR_KEYNUM),A
        XOR A
        LD (IR_CODE),A
        LD A,(IR_KEYNUM)
        CP 0x3e
        JR z,getkey_released
        LD C,A
        LD A,(IR_KEY)
        CP C
        JR nz,getkey_first_frame
        LD A,(IR_DEBOUNCE)
        AND A
        JR nz,getkey_accept
        CP 0x24
        JR z,getkey_none
        LD HL,(GEN_COUNTDOWN)
        LD A,H
        OR L
        JR nz,getkey_none
        LD HL,IR_REPEAT_TICKS
        LD (GEN_COUNTDOWN),HL
        JP getkey_check_shift

getkey_released:
        XOR A
        LD (IR_KEY),A
        LD (IR_DEBOUNCE),A

getkey_none:
        XOR A
        LD (IR_KEY_CHAR),A
        JP getkey_return

getkey_first_frame:
        LD A,(IR_KEYNUM)
        LD (IR_KEY),A
        LD (IR_DEBOUNCE),A
        XOR A
        LD (IR_CODE),A
        JR getkey_none

getkey_accept:
        LD A,(IR_KEYNUM)
        LD (IR_KEY),A
        LD HL,IR_REPEAT_DELAY
        LD (GEN_COUNTDOWN),HL
        XOR A
        LD (IR_DEBOUNCE),A

getkey_check_shift:
        LD A,(IR_KEYNUM)
        CP KEY_SHIFT
        JR nz,getkey_translate
        CALL beep_start
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

getkey_translate:
        LD HL,IR_KEY_TABLE
        LD D,0
        LD E,A
        ADD HL,DE
        LD A,(HL)
        LD (RX_BYTE),A
        LD A,(EURO_STATE)
        LD HL,CHARSET_EURO
        OR A
        JR nz,getkey_lookup
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
        LD A,(RX_BYTE)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(HL)
        LD (IR_KEY_CHAR),A
        LD A,0
        LD (SHIFT_STATE),A
        CALL beep_start

getkey_history:
        XOR A
        LD (EURO_STATE),A

getkey_return:
        LD A,(IR_KEY_CHAR)
        LD (EDIT_KEY),A
        XOR A
        LD (KEY_ECHO_TX),A
        LD A,(EDIT_KEY)
        AND A
        RET

; ---- data 2427-2464: IR/keypad code -> character map
IR_KEY_TABLE:
        db 0x0f,0x33,0x0c,0x0b,0x0d,0x09,0x0a,0x0e,0x03,0x3f,0x3c,0x3b,0x3d,0x39,0x3a,0x3e
        db 0x2f,0x13,0x2c,0x2b,0x2d,0x29,0x2a,0x2e,0x24,0x23,0x1c,0x1b,0x1d,0x1d,0x1a,0x22
        db 0x31,0x30,0x37,0x36,0x35,0x08,0x32,0x34,0x01,0x00,0x07,0x06,0x05,0x38,0x02,0x04
        db 0x11,0x10,0x17,0x16,0x15,0x28,0x12,0x14,0x21,0x20,0x27,0x26,0x25,0x18

editor_key_shift:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
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

; ---- editor_delete: 7F: delete the byte under the cursor
editor_delete:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_reshow
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JP z,editor_loop
        CP MARK_LO
        JP c,delete_do
        CP MARK_HI+1
        JP nc,delete_do
        JP show_top_of_msg

delete_do:
        LD A,0
        LD (DISP_ON),A
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
        LD A,0xff
        LD (DISP_ON),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,editor_loop
        CP MARK_HI+1
        JP nc,editor_loop
        DEC HL
        LD (STORE_CURSOR),HL
        JP show_top_of_msg

; ---- cursor_right: 0A
cursor_right:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JR z,cursor_right_done
        INC HL
        LD A,(HL)
        CP MARK_LO
        JP c,cursor_right_set
        CP MARK_HI+1
        JP nc,cursor_right_set
        INC HL

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

; ---- cursor_left: 08
cursor_left:
        LD IX,(STORE_CURSOR)
        LD A,(IX+0)
        CP MARK_LO
        JP c,cursor_left_do
        CP MARK_HI+1
        JP nc,cursor_left_do
        JP show_top_of_msg

cursor_left_do:
        DEC IX
        LD (STORE_CURSOR),IX
        LD A,(IX+0)
        CP MARK_LO
        JP c,editor_loop
        CP MARK_HI+1
        JP nc,editor_loop
        DEC IX
        LD (STORE_CURSOR),IX
        JP show_top_of_msg

; ---- cursor_left_8: 0B
cursor_left_8:
        LD B,8
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,left8_step
        CP MARK_HI+1
        JP nc,left8_step
        JP show_top_of_msg

left8_step:
        DEC HL
        LD (STORE_CURSOR),HL
        LD A,(HL)
        CP MARK_LO
        JP c,cursor_left_8
        CP MARK_HI+1
        JP nc,cursor_left_8
        DEC HL
        LD (STORE_CURSOR),HL
        JP show_top_of_msg

; ---- editor_insert: insert EDIT_KEY at the cursor (MEMORY FULL / 100 KEYS LEFT)
editor_insert:
        LD (CUR_CHAR),A
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_reshow
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JP z,insert_done
        CP MARK_LO
        JP c,insert_do
        CP MARK_HI+1
        JP nc,insert_do
        INC HL
        LD (STORE_CURSOR),HL

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
        JR nz,makeroom_ret
        LD HL,MSG_STORE
        LD (STORE_CURSOR),HL

makeroom_ret:
        RET

; ---- editor_translate_key: apply the GRAPH/COLOR/BGRND/SPEED/FUNC prefixes
editor_translate_key:
        CALL apply_graph_prefix
        CALL apply_colour_prefix
        CALL apply_speed_prefix
        CALL editor_key_to_attr
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

; ---- editor_key_to_attr: FUNC (B7) second functions: GRAPH->B8 DRAW, NORM->B9 THIN,
;      PAUSE->BA WAIT, FLASH->B0 REM, BOLD->06 HALT, COLOR->BC RAINBOW, Q->?, X->!,
;      MAGIC->5E (ADDRESS? menu), BIG->BE TINY; anything else cancels
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
        CP ATTR_NORM
        JR z,func_store
        INC C
        CP ATTR_PAUSE
        JR z,func_store
        LD C,ATTR_REM
        CP ATTR_FLASH
        JR z,func_store
        LD C,6
        CP ATTR_BOLD
        JR z,func_store
        LD C,ATTR_RAINBOW
        CP ATTR_COLOR
        JR z,func_store
        CP 0x8f
        JR z,func_store
        LD C,0x3f
        CP 0x51
        JR z,func_store
        CP 0x71
        JR z,func_store
        LD C,0x21
        CP 0x58
        JR z,func_store
        CP 0x78
        JR z,func_store
        LD C,0x5e
        CP ATTR_MAGIC
        JR z,func_store
        LD C,ATTR_TINY
        CP ATTR_BIG
        JR z,func_store
        POP HL
        POP HL
        JP editor_reshow

func_store:
        LD A,C
        LD (EDIT_KEY),A
        RET

; ---- apply_colour_prefix: COLOR n -> FG_IDX_TABLE, BGRND n -> BG_IDX_TABLE
apply_colour_prefix:
        LD A,(COLOR_PENDING)
        AND A
        JR nz,prefix_fore
        LD A,(BGRND_PENDING)
        AND A
        JR nz,prefix_back
        RET

prefix_fore:
        LD A,(EDIT_KEY)
        AND 15
        DEC A
        CP 10
        JR c,prefix_fore_lookup
        LD A,2

prefix_fore_lookup:
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
        JR c,prefix_back_lookup
        LD A,5

prefix_back_lookup:
        LD HL,BG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (EDIT_KEY),A
        XOR A
        LD (BGRND_PENDING),A
        RET

; ---- data 2718-2721: cmd 15 n: foreground colour codes (Red,Orange,Yellow,Lime,Green,84,8E,Black,8B,81)
FG_IDX_TABLE:
        db 0x8c,0x8d,0x8f,0x87,0x83,0x84,0x8e,0x80,0x8b,0x81

; ---- data 2722-2727: cmd 16 n: background colour codes
BG_IDX_TABLE:
        db 0x91,0x93,0x93,0x93,0x92,0x90

; ---- editor_redraw: Redraw the editor view of the current message
editor_redraw:
        CALL clear_txbuf
        CALL init_render
        XOR A
        LD (DISP_ON),A
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,(SEQ_MENU_ACTIVE)
        BIT 7,A
        JP nz,redraw_status
        LD A,(MAGIC_MSG_CHAN)
        AND A
        JP nz,redraw_status
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,redraw_window
        CP MARK_HI+1
        JP nc,redraw_window
        JP redraw_status

redraw_window:
        LD DE,0x15
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
        CP 0x20
        JR nz,redraw_classify
        LD A,(REDRAW_MAGIC)
        AND A
        JP z,redraw_char_check
        XOR A
        LD (FORCE_BOLD),A
        LD (FONT_MODE),A
        JP redraw_char_check

redraw_classify:
        BIT 7,A
        JP nz,redraw_high
        AND 0x60
        JR z,redraw_attr
        JP redraw_char_check

redraw_high:
        LD A,(CUR_CHAR)
        CP 0x94
        JP c,redraw_attr
        CP 0x9f
        JP c,redraw_char_check
        AND 0xf0
        CP 0xc0
        JP z,redraw_char_check
        CP 0xe0
        JP z,redraw_char_check
        CP 0xd0
        JP z,redraw_char_check
        CP GRAPH_BASE
        JP z,redraw_char_check

redraw_attr:
        LD A,(CUR_CHAR)
        CP ATTR_COLOR
        JP z,redraw_char_check
        CP ATTR_BGRND
        JP z,redraw_char_check
        CP ATTR_MAGIC_OFF
        JR nz,redraw_attr2
        XOR A
        LD (REDRAW_MAGIC),A
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
        JP nz,redraw_not_norm
        XOR A
        LD (FLASH_BIT),A
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_not_norm:
        CP ATTR_FLASH
        JP nz,redraw_not_flash
        LD A,COLOUR_FLASH
        LD (FLASH_PENDING),A
        JR redraw_label_check

redraw_not_flash:
        CP ATTR_ITALIC
        JP nz,redraw_not_italic
        LD A,0x64
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_not_italic:
        CP ATTR_BOLD
        JP nz,redraw_not_bold
        XOR A
        SET 1,A
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_not_bold:
        CP ATTR_BIG
        JP nz,redraw_not_big
        XOR A
        SET 1,A
        SET 3,A
        LD (FONT_MODE),A
        JP redraw_label_check

redraw_not_big:
        CP ATTR_THIN
        JP nz,redraw_not_thin
        LD A,0xff
        LD (THIN_MODE),A
        XOR A
        LD (FORCE_BOLD),A
        JP redraw_label_check

redraw_not_thin:
        CP ATTR_MAGIC
        JP nz,redraw_label_check
        XOR A
        LD (FONT_MODE),A
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
        CALL track_flash_space
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
        LD A,(EURO_STATE)
        OR A
        JR z,status_not_euro
        LD HL,STR_EURO
        JP status_show

status_not_euro:
        LD A,(SPEED_PENDING)
        OR A
        JP z,status_not_speed
        LD HL,STR_SPEED
        JP status_show

status_not_speed:
        LD A,(MAGIC_MSG_CHAN)
        OR A
        JP z,status_shift_msg
        XOR A
        LD (MAGIC_MSG_CHAN),A
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,STR_MAGIC_MSG
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        LD B,2
        LD HL,(INS_PTR)
        DEC HL
        DEC HL

magicmsg_digits:
        LD A,(HL)
        AND 15
        OR 0x30
        LD (CUR_CHAR),A
        PUSH HL
        PUSH BC
        CALL glyph_lookup
        POP BC
        POP HL
        INC HL
        DJNZ magicmsg_digits
        JR status_shift_msg

; ---- data 2979-2987:
STR_MAGIC_MSG:
        db "    MAGIC MSG ",0x00

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
        CP MARK_LO
        JP c,redraw_again
        CP MARK_HI+1
        JP nc,redraw_again
        POP HL
        JP show_top_of_msg

redraw_again:
        JP editor_redraw

redraw_ret:
        LD A,0xff
        LD (DISP_ON),A
        RET

; ---- redraw_hold: let one frame out, then hold 0x50 frames
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
        CALL pkt_poll
        LD A,(FRAME_DELAY)
        AND A
        JR nz,hold_wait_frames
        RET

; ---- menu_show_text: Render the NUL-terminated string at MENU_TEXT_PTR in tiny font
menu_show_text:
        LD HL,(MENU_TEXT_PTR)
        LD A,(TINY_MODE)
        PUSH AF
        LD A,(CUR_CHAR)
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
        LD (CUR_CHAR),A
        POP AF
        LD (TINY_MODE),A
        RET

; ---- fb_rewind_window: FB_COL = FB_COLPTR - 86 (ring wrap)
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

; ---- pkt_process_end
pkt_process_end:
        JP RESET

; ---- word_to_hex4: HL -> 4 ASCII hex digits at (DE)
word_to_hex4:
        PUSH DE
        LD B,2
        LD C,H

hex_byte_loop:
        LD A,C
        SRL A
        SRL A
        SRL A
        SRL A
        CALL nibble_to_hex
        LD (DE),A
        INC DE
        LD A,C
        AND 15
        CALL nibble_to_hex
        LD (DE),A
        INC DE
        LD C,L
        DJNZ hex_byte_loop
        POP DE
        RET

; ---- nibble_to_hex: A = ASCII hex digit for low nibble
nibble_to_hex:
        OR 0x30
        CP 0x3a
        RET c
        ADD A,7
        RET

; ---- pkt_process: Process a received packet: walk PKT_BUF byte by byte. Bytes in IGNORE_TABLE are skipped; command bytes dispatch (02 speed,03 clear all,04 sequence,09 channel,0D end,0E delete channel text,15 fg idx,16 bg idx,17 time,1E A0-colour,B3 append,B4 query,B5 OTA); anything else is inserted as message text
pkt_process:
        ; P21: called from the render loop with interrupts on. The renderer is
        ; suspended until this returns, and nothing in the tick service reads
        ; the store, so the edits below need no DI. Its pointers are saved and
        ; put back (shifted if a lower channel changed size) unless the text
        ; under it changed, which restarts the display as before.
        XOR A
        LD (PKT_READY),A
        LD (PKT_RESTART),A
        LD (PKT_DONE_WANT),A
        DEC A
        LD (PKT_BUSY),A
        ; P16: flag bit 0 asks for a DONE byte once the packet has been
        ; processed and its reply sent. Never for broadcast frames. Decided
        ; now: a frame parsed meanwhile overwrites PKT_FLAG and PKT_ADDR.
        LD A,(PKT_FLAG)
        BIT 0,A
        JR z,pkt_entry_nodone
        LD A,(PKT_ADDR)
        CP ADDR_BROADCAST
        JR z,pkt_entry_nodone
        LD A,0xff
        LD (PKT_DONE_WANT),A

pkt_entry_nodone:
        LD HL,(STORE_CURSOR)
        LD (PKT_SAVE_CURSOR),HL
        LD HL,(INS_PTR)
        LD (PKT_SAVE_INS),HL
        LD HL,(STORE_END)
        LD (PKT_SAVE_END),HL
        LD HL,0xffff
        LD (PKT_LOW_EDIT),HL
        LD HL,(STORE_CURSOR)
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        JR nc,pkt_cursor_in_store
        CALL clear_chan_lock    ; P24: the renderer is in ROM (demo) or the test
        LD HL,MSG_STORE+1       ; buffer, and the demo channel's lock is on: take
        JP pkt_set_ins          ; channel 0, seated as 09 30 30 0E leaves it

pkt_cursor_in_store:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP MARK_LO
        JP c,pkt_find_marker
        CP MARK_HI+1
        JP nc,pkt_find_marker
        DEC HL
        LD (STORE_CURSOR),HL

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
        CP MARK_LO
        JP c,pkt_marker_back
        CP MARK_HI+1
        JP nc,pkt_marker_back
        JR pkt_set_ins

pkt_marker_back:
        DEC HL
        DEC BC
        LD A,C
        OR B
        JR nz,pkt_marker_loop
        JP pkt_process_end

pkt_set_ins:
        LD (STORE_CURSOR),HL
        LD (PKT_SAVE_MARK),HL   ; the marker of the channel being played
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
        JP z,pkt_done_pop
        CP CMD_DELETE_TEXT
        JP z,cmd_0E_delete_text
        CP CMD_FORE_IDX
        JP z,cmd_15_fore_idx
        CP CMD_BACK_IDX
        JP z,cmd_16_back_idx
        CP CMD_SET_TIME
        JP z,cmd_17_set_time
        CP CMD_COLOUR_A0
        JP z,cmd_1E_colour_A0
        CP CMD_APPEND
        JP z,cmd_B3_append
        CP CMD_QUERY
        JP z,cmd_B4_query
        CP CMD_OTA
        JP z,cmd_B5_ota

; ---- pkt_insert_text: insert the plain text at the payload position into the
;      store after STORE_CURSOR. P21: the run of plain bytes that starts here
;      goes in with one move of the store's tail instead of one per byte.
;      Refuses under CHAN_LOCK; a full store takes what fits.
pkt_insert_text:
        POP BC                  ; B = payload bytes left, HL = payload position
        POP HL
        PUSH HL
        PUSH BC
        PUSH HL
        LD C,1

pkt_run_scan:
        DEC B
        JR z,pkt_run_end
        INC HL
        LD A,(HL)
        CALL is_plain_byte
        JR nz,pkt_run_end
        INC C
        JR pkt_run_scan

pkt_run_end:
        POP HL
        LD B,0
        JR pkt_insert_run

; ---- pkt_insert_one: insert CUR_CHAR (the colour and speed commands)
pkt_insert_one:
        LD HL,CUR_CHAR
        LD BC,1

; ---- pkt_insert_run: BC bytes at HL go in after STORE_CURSOR, which then
;      points at the last of them. The payload position advances past them.
pkt_insert_run:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,pkt_next
        PUSH BC                 ; the whole run: the payload skips it even if
        PUSH HL                 ; the store takes less (a full store refuses)
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JR nz,pkt_ins_room
        DEC HL
        LD (STORE_CURSOR),HL

pkt_ins_room:
        LD HL,(STORE_LIMIT)     ; free = LIMIT - END - 1; clamp the run to it
        LD DE,(STORE_END)
        OR A
        SBC HL,DE
        DEC HL
        OR A
        SBC HL,BC
        JR nc,pkt_ins_fits
        ADD HL,BC
        LD B,H
        LD C,L

pkt_ins_fits:
        LD A,B
        OR C
        JR z,pkt_ins_none
        PUSH BC                 ; count
        LD HL,(STORE_CURSOR)
        INC HL
        CALL pkt_note_edit
        LD HL,(STORE_END)
        LD DE,(STORE_CURSOR)
        OR A
        SBC HL,DE               ; bytes to move: cursor+1 .. END
        PUSH HL
        LD HL,(STORE_END)
        LD D,H
        LD E,L
        ADD HL,BC
        LD (STORE_END),HL
        EX DE,HL                ; HL = old END, DE = new END
        POP BC
        LDDR
        POP BC                  ; count
        POP HL                  ; source
        LD DE,(STORE_CURSOR)
        INC DE
        LDIR
        DEC DE
        LD (STORE_CURSOR),DE    ; the last byte put in
        JR pkt_ins_advance

pkt_ins_none:
        POP HL                  ; source

pkt_ins_advance:
        POP BC                  ; the whole run
        DEC BC                  ; the loop steps over the first byte itself
        POP DE                  ; payload bytes left (D)
        POP HL                  ; payload position
        ADD HL,BC
        LD A,D
        SUB C
        LD D,A
        PUSH HL
        PUSH DE
        JP pkt_next

; ---- pkt_note_edit: HL = store address this packet edits; PKT_LOW_EDIT keeps
;      the lowest, which decides whether the renderer can carry on
pkt_note_edit:
        PUSH BC
        PUSH HL
        LD DE,(PKT_LOW_EDIT)
        OR A
        SBC HL,DE
        POP HL
        JR nc,note_edit_ret
        LD (PKT_LOW_EDIT),HL

note_edit_ret:
        POP BC
        RET

pkt_next:
        POP BC
        POP HL
        INC HL
        DEC B
        JP nz,pkt_byte_loop
        JR pkt_process_done

; ---- pkt_done_pop: the exit for a handler that still holds the loop's HL/BC
pkt_done_pop:
        POP BC
        POP HL

; ---- pkt_process_done: hand the reply (if any) and DONE to the background
;      transmitter, then either carry on where the renderer was or restart
pkt_process_done:
        XOR A                   ; P21: PKT_STATE is the parser's; a frame may be
        LD (MENU_ACTIVE),A      ; in flight, being parsed and discarded
        LD (FORCE_BOLD),A
        ; B2: cmd_17_set_time clears CLK_RUN before fetching its five argument
        ; bytes; a short packet exits here through pkt_next_byte and the clock
        ; never restarts. Restoring it on the way out covers every early exit.
        LD A,0xff
        LD (CLK_RUN),A
        LD A,(PKT_DONE_WANT)
        LD (TX_DONE_PENDING),A

pkt_done_handoff:
        LD A,0xff
        LD (TX_ACTIVE),A
        LD A,(PKT_RESTART)
        OR A
        JR nz,pkt_done_restart
        LD HL,(PKT_LOW_EDIT)
        LD DE,(PKT_SAVE_CURSOR)
        OR A
        SBC HL,DE
        JR nc,pkt_done_continue ; nothing moved under the renderer
        LD HL,(PKT_LOW_EDIT)
        LD DE,(PKT_SAVE_MARK)
        OR A
        SBC HL,DE
        JR nc,pkt_done_restart  ; the text being played changed
        LD HL,(STORE_END)       ; a lower channel changed size: shift the
        LD DE,(PKT_SAVE_END)    ; renderer's pointers by the same amount
        OR A
        SBC HL,DE
        EX DE,HL
        LD HL,(PKT_SAVE_CURSOR)
        ADD HL,DE
        LD (PKT_SAVE_CURSOR),HL
        LD HL,(PKT_SAVE_INS)
        ADD HL,DE
        LD (PKT_SAVE_INS),HL

pkt_done_continue:
        LD HL,(PKT_SAVE_CURSOR)
        LD (STORE_CURSOR),HL
        LD HL,(PKT_SAVE_INS)
        LD (INS_PTR),HL
        LD HL,(STORE_END)
        LD DE,(PKT_SAVE_END)
        OR A
        SBC HL,DE
        RET z                   ; the store did not change size
        LD A,(SEQ_ALL_EMPTY)
        OR A
        JR nz,pkt_done_restart  ; the demo was playing: show the new text now
        JP init_sequence        ; else just recount the empty channels

pkt_done_restart:
        LD SP,STACK_TOP
        LD A,0xff
        LD (PKT_RESTART),A      ; left set: the emulator reads which exit was taken
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

; ---- cmd_03_clear_all
cmd_03_clear_all:
        LD A,0xff
        LD (PKT_RESTART),A
        CALL store_clear_all
        CALL store_finalize
        JP select_chan_common

; ---- cmd_0E_delete_text: delete existing text of the selected channel (from INS_PTR to its 0x03 terminator)
cmd_0E_delete_text:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,pkt_next
        LD HL,(INS_PTR)
        CALL pkt_note_edit
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
        EX DE,HL
        LD HL,(STORE_END)       ; P21: move the store up to its DA, not the
        INC HL                  ; whole RAM to STORE_LIMIT (15 K, 40 ms)
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

; ---- cmd_B4_query: B4 n: '0' rom id, '1' memory, '2' nop, '3' dump
;      (B1, the stock stack overflow in the reply chain, is covered by the
;      relocated stack.)
cmd_B4_query:
        ; P21: the reply is handed to the background transmitter and the
        ; display keeps running. The query ends the packet: the frame is built
        ; over PKT_BUF.
        CALL pkt_next_byte
        CP QUERY_ROMID
        JR z,pq_romid
        CP QUERY_MEMORY
        JR z,pq_memory
        CP QUERY_DUMP
        JR z,pq_dump
        JP pkt_done_pop

pq_romid:
        LD HL,ROM_ID
        LD BC,16
        JR pq_reply

pq_memory:
        CALL store_finalize
        LD IX,PKT_BUF+3
        LD HL,(STORE_SIZE)
        CALL bin_to_dec5
        LD HL,(STORE_LIMIT)
        LD DE,(STORE_END)
        OR A
        SBC HL,DE
        CALL bin_to_dec5
        LD HL,PKT_BUF+3
        LD BC,10

pq_reply:
        LD A,C
        LD (PKT_BUF+2),A
        LD E,3
        JR pq_stream

pq_dump:
        LD HL,(STORE_END)
        INC HL
        LD DE,MSG_STORE
        OR A
        SBC HL,DE               ; up to and including the DA
        PUSH HL
        LD IX,PKT_BUF+2
        CALL bin_to_dec5
        POP BC
        LD HL,MSG_STORE
        LD E,7

; ---- pq_stream: E header bytes at PKT_BUF (B1 addr ...), then BC bytes at HL
;      with their sum appended
pq_stream:
        LD (TX_SEG1),HL
        LD (TX_SEG1+2),BC
        LD A,1
        LD (TX_SEG1+4),A
        LD A,FRAME_START
        LD (PKT_BUF),A
        LD A,(MY_ADDRESS)
        LD (PKT_BUF+1),A
        LD HL,PKT_BUF
        LD (TX_SEG0),HL
        LD D,0
        LD (TX_SEG0+2),DE
        XOR A
        LD (TX_SEG0+4),A
        LD (TX_SUM),A
        JP pkt_done_pop

; ---- cmd_B5_ota: OTA commands (CC784_ota.md §6). B5 must be the first payload
;      byte and the frame ends with the command. Runs under pkt_process's DI;
;      interrupts come back only for the reply. Replies are tx_send_frame
;      frames: one status byte (0 ok, 1 verify failed, 2 chip timeout, 3 page
;      out of range, 4 CRC mismatch, 5 bad arguments) or the data asked for.
;        B5 'I'                 -> bank, 10 trailer bytes per bank, features byte
;        B5 'C' page n          -> n CRC-16s of idle-bank pages (n <= 42)
;        B5 'B'                 -> erase the idle bank's trailer page
;        B5 'W' page crc data   -> write 1-3 pages of data (crc covers data)
;        B5 'F' seq crc         -> CRC the idle bank; if it matches, write its trailer
;        B5 'K' state seq       -> rewrite the running bank's trailer (confirm, or roll back)
;        B5 'R'                 -> reset (no reply)
cmd_B5_ota:
        LD A,(TX_STATUS)        ; P21: pkt_process runs with interrupts on; let
        AND 3                   ; the ACK finish before the page writer's DI
        JR nz,cmd_B5_ota
        DI
        LD HL,stub_lib
        LD DE,STUB_RAM
        LD BC,STUB_LIB_APP_SIZE ; fits FRAMEBUF; the full lib would run into the variables
        LDIR
        LD A,(ROM_BANK)
        XOR 1
        LD (OTA_IDLE),A
        LD A,(PKT_BUF)
        CP CMD_OTA
        JR nz,ota_bad_args
        LD A,(PKT_BUF+1)
        CP 'I'
        JP z,ota_info
        CP 'C'
        JP z,ota_crc
        CP 'B'
        JP z,ota_begin
        CP 'W'
        JP z,ota_write
        CP 'F'
        JP z,ota_finish
        CP 'K'
        JP z,ota_confirm
        CP 'R'
        JP z,RESET

ota_bad_args:
        LD A,5

; ---- ota_status: A = the one-byte reply
ota_status:
        LD HL,TXBUF
        LD (HL),1
        INC HL
        LD (HL),A

; ---- ota_reply: send TXBUF (len, data) and finish the packet. The library
;      copy sits in FRAMEBUF and would be painted by the refresh once EI: blank
;      first, as cmd_B4_query does (it can do so before its work, we after).
ota_reply:
        CALL clear_framebuf
        CALL shift_chain_clear
        EI
        LD HL,TXBUF
        CALL tx_send_frame

ota_wait_tx:
        LD A,(TX_STATUS)
        AND 3
        JR nz,ota_wait_tx
        DI
        LD A,0xff               ; the library sits in FRAMEBUF: restart the display
        LD (PKT_RESTART),A
        JP pkt_process_done

; ---- ota_info: ROM_BANK, then the first 10 trailer bytes of bank 0 and bank 1
;      (magic, seq, state, image crc, trailer crc); the host judges them
ota_info:
        LD HL,TXBUF
        LD (HL),22
        INC HL
        LD A,(ROM_BANK)
        LD (HL),A
        INC HL
        EX DE,HL
        XOR A
        CALL ota_trailer_copy
        LD A,1
        CALL ota_trailer_copy
        LD A,(NMI_SEEN)
        AND 2
        OR OTA_FEATURES
        LD (DE),A
        JP ota_reply

; ---- ota_trailer_copy: A = bank, DE = destination for 10 bytes; DE advances
ota_trailer_copy:
        LD HL,TRAILER
        LD BC,10
        JP lib_copy

; ---- ota_crc: 'C' page n -> 2n bytes of page CRCs from the idle bank
ota_crc:
        LD A,(PKT_BUF+3)
        OR A
        JR z,ota_bad_args
        CP 43
        JR nc,ota_bad_args
        LD B,A
        ADD A,A
        LD HL,TXBUF
        LD (HL),A
        LD IX,TXBUF+1
        LD A,(PKT_BUF+2)
        LD C,A

ota_crc_loop:
        LD A,C
        CALL ota_page_crc
        LD (IX+0),E
        LD (IX+1),D
        INC IX
        INC IX
        INC C
        DJNZ ota_crc_loop
        JP ota_reply

; ---- ota_page_crc: A = page of the idle bank -> DE = its CRC-16 (BC kept)
ota_page_crc:
        PUSH BC
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        CALL ota_fetch_page
        LD BC,64
        LD DE,0
        CALL ROM_CRC16
        POP BC
        RET

; ---- ota_fetch_page: HL = address in the idle bank -> 64 bytes at OTA_PAGE_BUF, HL = the buffer
ota_fetch_page:
        LD DE,OTA_PAGE_BUF
        LD BC,64
        LD A,(OTA_IDLE)
        CALL lib_copy
        LD HL,OTA_PAGE_BUF
        RET

; ---- ota_erase_buf: OTA_PAGE_BUF = 64 x FF, HL = the buffer
ota_erase_buf:
        LD HL,OTA_PAGE_BUF
        LD B,64

ota_erase_loop:
        LD (HL),0xff
        INC HL
        DJNZ ota_erase_loop
        LD HL,OTA_PAGE_BUF
        RET

; ---- ota_confirm: 'K' state seq -> the running bank's trailer rewritten with
;      that state and sequence number (image CRC kept): confirm a trial, or
;      lower the sequence number to roll back to the other bank at the reboot
ota_confirm:
        LD HL,TRAILER
        LD DE,OTA_PAGE_BUF
        LD BC,64
        LDIR
        LD A,(PKT_BUF+2)
        LD (OTA_PAGE_BUF+5),A
        LD A,(PKT_BUF+3)
        LD (OTA_PAGE_BUF+4),A
        LD HL,OTA_PAGE_BUF
        LD BC,8
        LD DE,0
        CALL ROM_CRC16
        LD (OTA_PAGE_BUF+8),DE
        LD HL,OTA_PAGE_BUF
        LD DE,TRAILER
        LD A,(ROM_BANK)
        LD B,A
        CALL lib_page_writer
        JP ota_status

; ---- ota_begin: 'B' -> the idle bank's trailer page becomes FF, and the panel
;      shows UPDATING (held, not scrolled) through every restart until the
;      reboot: TEST_MODE makes seq_next_channel display TEST_MSG_BUF instead of
;      the sequence, and init_vars clears it on boot.
ota_begin:
        LD HL,ota_updating_msg
        LD DE,TEST_MSG_BUF
        LD BC,28                ; the whole buffer, so a longer message changes one page
        LDIR
        LD A,0xff
        LD (TEST_MODE),A
        CALL ota_erase_buf

; ---- ota_write_trailer: write OTA_PAGE_BUF over the idle bank's trailer, reply the status
ota_write_trailer:
        LD HL,OTA_PAGE_BUF
        LD DE,TRAILER
        LD A,(OTA_IDLE)
        LD B,A
        CALL lib_page_writer
        JP ota_status

; ---- ota_write: 'W' page crc data[64k] -> pages page..page+k-1 of the idle bank
ota_write:
        LD A,(PKT_LEN)
        SUB 5
        JP c,ota_bad_args
        JP z,ota_bad_args
        LD C,A
        AND 0x3f
        JP nz,ota_bad_args      ; whole pages only
        LD A,C
        RLCA
        RLCA
        AND 3
        LD C,A                  ; C = pages in the frame, 1..3
        LD A,(PKT_BUF+2)
        CP STUB_END/64
        LD B,A
        LD A,3
        JP c,ota_status         ; the stub is never written over the air
        LD A,C
        DEC A
        ADD A,B
        LD A,3
        JP c,ota_status         ; past the end of the bank
        LD A,C                  ; CRC of the data: 64 * C bytes
        RRCA
        RRCA
        LD C,A
        LD B,0                  ; BC = 64 * pages
        LD HL,PKT_BUF+5
        LD DE,0
        CALL ROM_CRC16
        LD HL,(PKT_BUF+3)
        OR A
        SBC HL,DE
        LD A,4
        JP nz,ota_status
        LD A,(PKT_BUF+2)
        LD D,A                  ; DE = page * 64
        LD E,0
        SRL D
        RR E
        SRL D
        RR E
        LD A,(PKT_LEN)
        SUB 5
        RLCA
        RLCA
        AND 3
        LD C,A
        LD HL,PKT_BUF+5

ota_write_loop:
        LD A,(OTA_IDLE)
        LD B,A
        PUSH BC
        CALL lib_page_writer    ; HL, DE preserved
        POP BC
        OR A
        JP nz,ota_status
        LD A,L
        ADD A,64
        LD L,A
        JR nc,ota_write_next
        INC H

ota_write_next:
        LD A,E
        ADD A,64
        LD E,A
        JR nc,ota_write_count
        INC D

ota_write_count:
        DEC C
        JR nz,ota_write_loop
        XOR A
        JP ota_status

; ---- ota_finish: 'F' seq crc -> CRC the idle bank's app; on a match write its trailer
ota_finish:
        LD DE,0                 ; running CRC; the source pointer lives in HL'
        EXX
        LD HL,STUB_END
        EXX

ota_finish_loop:
        EXX
        PUSH HL
        EXX
        POP HL
        PUSH DE
        CALL ota_fetch_page     ; HL = buffer
        POP DE
        LD BC,64
        CALL ROM_CRC16
        EXX
        LD BC,64
        ADD HL,BC
        LD A,H
        CP 0x3f
        JR nz,ota_finish_next
        LD A,L
        CP 0xc0
        JR z,ota_finish_done

ota_finish_next:
        EXX
        JR ota_finish_loop

ota_finish_done:
        EXX
        LD HL,(PKT_BUF+3)
        OR A
        SBC HL,DE
        LD A,4
        JP nz,ota_status
        CALL ota_erase_buf
        LD (HL),'O'
        INC HL
        LD (HL),'T'
        INC HL
        LD (HL),'A'
        INC HL
        LD (HL),'1'
        INC HL
        LD A,(PKT_BUF+2)
        LD (HL),A               ; seq
        INC HL
        LD (HL),STATE_TRIAL     ; the stub marks it TRIED when it boots it; K makes it GOOD
        INC HL
        LD A,(PKT_BUF+3)
        LD (HL),A
        INC HL
        LD A,(PKT_BUF+4)
        LD (HL),A
        LD HL,OTA_PAGE_BUF
        LD BC,8
        LD DE,0
        CALL ROM_CRC16
        LD (OTA_PAGE_BUF+8),DE
        JP ota_write_trailer

; ---- cmd_1E_colour_A0: 1E n -> insert 0xA0|(n&15)
cmd_1E_colour_A0:
        CALL pkt_next_byte
        AND 15
        OR GRAPH_BASE
        LD (CUR_CHAR),A
        JP pkt_insert_one

; ---- cmd_15_fore_idx: 15 n -> insert FG_IDX_TABLE[n]
cmd_15_fore_idx:
        CALL pkt_next_byte
        LD HL,FG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (CUR_CHAR),A
        JP pkt_insert_one

; ---- cmd_16_back_idx: 16 n -> insert BG_IDX_TABLE[n]
cmd_16_back_idx:
        CALL pkt_next_byte
        LD HL,BG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (CUR_CHAR),A
        JP pkt_insert_one

; ---- cmd_17_set_time: 17 h h m m a: 4 ASCII digits -> CLK_H10..CLK_M1, a=Y/y -> AM else PM.
;      B2: CLK_RUN is cleared here but restored only at 0x2C59, and every
;      pkt_next_byte below can jump straight to pkt_process_done on a short
;      packet - NETCC's "status query" 17 32 does exactly that and stops the
;      clock. Fixed in pkt_process_done below.
;      Unlike the menu's time editor (0x1D14..0x1D8A) this path does not reset
;      NMI_COUNT, so the new time starts up to one second out of phase.
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
        CP 'Y'
        LD A,0xff
        JR nz,settime_store_pm
        XOR A

settime_store_pm:
        LD (CLK_PM),A
        XOR A                   ; P23: the new minute starts at :00, like the
        LD (CLK_SEC),A          ; host tool times the frame to land
        LD (NMI_COUNT),A
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
        JP pkt_insert_one

; ---- cmd_B3_append: B3: move STORE_CURSOR to end of current channel.
;      B11: stock stepped back a second time when the byte before the 03 was a
;      marker byte (an empty channel), so the first insert split the marker.
cmd_B3_append:
        LD HL,(STORE_CURSOR)

append_find_end:
        LD A,(HL)
        CP TEXT_END
        JR z,append_seat
        INC HL
        JR append_find_end

append_seat:
        DEC HL                  ; the byte before the 03: last text byte, or the
        LD (STORE_CURSOR),HL    ; marker's last byte when the channel is empty, as 0E seats it
        JP pkt_next

; ---- cmd_09_channel: 09 d d: select channel (2 ASCII digits, 0-99) ; channel 100 sets CHAN_LOCK
cmd_09_channel:
        CALL pkt_next_byte
        AND 15
        LD (CHAN_D10),A
        CALL pkt_next_byte
        AND 15
        LD (CHAN_D1),A
        LD B,2
        LD HL,CHAN_D10
        CALL ascii_dec_to_bin
        LD E,A

select_chan_common:
        PUSH DE
        CALL chan_select
        POP DE
        LD (INS_PTR),HL
        DEC HL
        DEC HL
        LD (STORE_CURSOR),HL
        PUSH DE
        CALL clear_chan_lock
        POP DE
        LD A,E
        CP 0x64
        JR nz,select_chan_done
        LD (CHAN_LOCK),A

select_chan_done:
        JP pkt_next

; ---- cmd_04_sequence: 04 dd dd ... [D|d]: rebuild SEQ_LIST from 2-digit channel numbers
cmd_04_sequence:
        LD HL,SEQ_LIST
        LD A,0
        LD B,0x64

seq_default_fill:
        LD (HL),A
        INC HL
        INC A
        DJNZ seq_default_fill
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        LD B,0x67

seq_pair_loop:
        CALL pkt_next_byte
        CP 'D'
        JR z,seq_pair_demo
        CP 'd'
        JR z,seq_pair_demo
        LD (CUR_CHAR),A
        CP '9'+1
        JP nc,pkt_next
        CP '0'
        JP c,pkt_next
        AND 15
        LD (CHAN_D10),A
        CALL pkt_next_byte
        CP 'D'
        JR z,seq_pair_demo
        CP 'd'
        JR z,seq_pair_demo
        LD (CUR_CHAR),A
        CP '9'+1
        JP nc,pkt_next
        CP '0'
        JP c,pkt_next
        AND 15
        LD (CHAN_D1),A
        PUSH BC
        PUSH HL
        LD B,2
        LD HL,CHAN_D10
        CALL ascii_dec_to_bin
        POP HL
        POP BC
        JR seq_pair_store

seq_pair_demo:
        LD A,0x64

seq_pair_store:
        LD (HL),A
        INC HL
        LD A,0xff
        LD (HL),A
        DJNZ seq_pair_loop
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

; ---- data 2d57-2d60: payload bytes silently ignored by the parser
IGNORE_TABLE:
        db 0x00,0x01,0x05,0x08,0x0a,0x0b,0x0c,0x1c,0x1d,0x7f
; ---- COMMAND_TABLE: the bytes pkt_byte_loop dispatches; follows IGNORE_TABLE
;      so one CPIR covers both
COMMAND_TABLE:
        db CMD_SPEED,CMD_CLEAR_ALL,CMD_SEQUENCE,CMD_CHANNEL,CMD_END,CMD_DELETE_TEXT
        db CMD_FORE_IDX,CMD_BACK_IDX,CMD_SET_TIME,CMD_COLOUR_A0,CMD_APPEND,CMD_QUERY,CMD_OTA
COMMAND_TABLE_END:

; ---- is_plain_byte: Z if A is message text (neither ignored nor a command)
is_plain_byte:
        CP 0x20
        JR c,plain_lookup
        CP 0x7f
        RET c                   ; printable ASCII: never a command or ignored (Z from CP)

plain_lookup:
        PUSH BC
        PUSH HL
        LD HL,IGNORE_TABLE
        LD BC,COMMAND_TABLE_END-IGNORE_TABLE
        CPIR
        POP HL
        POP BC
        JR z,plain_no
        XOR A
        RET

plain_no:
        LD A,1
        OR A
        RET

; ---- data 2d61-2ff2: 16-bit pointers/data for big glyphs & graphics (0x2E00-0x2FF0)
; ============================================================================
;  Editor label tables (2D61-2FF2). Previously disassembled as an unnamed
;  "GLYPH_PTR_TABLE" of raw hex; it holds no glyph pointers. Each table maps
;  a message byte to the text the on-sign editor shows for it, which is where
;  the names below come from - they are the sign's own words, not guesses.
; ============================================================================
        db 0x00

; ---- ATTR_LABEL_TABLE: indexed by attribute byte 00-1F; 0000 = no label
ATTR_LABEL_TABLE:
        dw 0
        dw STR_SPEED               ; 01  .SPEED
        dw 0
        dw STR_END                 ; 03  .END.
        dw MENU_STR_SEQ_MSG        ; 04   SEQ MSG?
        dw 0
        dw STR_HALT                ; 06  .HALT.
        dw STR_BEEP                ; 07  .BEEP.
        dw 0
        dw MENU_STR_PROG_MSG       ; 09   PROG MSG?
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw STR_RIGHT               ; 0f  .RIGHT.
        dw STR_BIG                 ; 10  .BIG.
        dw STR_NORM                ; 11  .NORM.
        dw STR_BOLD                ; 12  .BOLD.
        dw STR_ITALIC              ; 13  .ITALIC.
        dw STR_FLASH               ; 14  .FLASH.
        dw STR_COLOR               ; 15  .COLOR
        dw STR_BGRND               ; 16  .BGRND
        dw 0
        dw STR_LEFT                ; 18  .LEFT.
        dw STR_PAUSE               ; 19  .PAUSE.
        dw STR_UP                  ; 1a  .UP.
        dw STR_DOWN                ; 1b  .DOWN.
        dw 0
        dw STR_SHIFT               ; 1d  .SHIFT.
        dw STR_GRAPH               ; 1e  .GRAPH
        dw STR_MAGIC               ; 1f  .MAGIC.

; ---- The lookup is ATTR_LABEL_TABLE + 2*attr for attributes 00-1F and colours
;      80-9F, so COLOUR_NAME_TABLE must sit at +0100; the 20-7F slots in between
;      are never indexed and hold label strings (P17: stock parked eleven dead
;      "TOP OF MSG n" strings here). The ds enforces the offset.
STR_BEEP:
        db 0x15,"BEEP",0x16,0x00
STR_RIGHT:
        db 0x15,"RIGHT",0x16,0x00
        db 0x00

STR_COLOR:
        db 0x15,"COLOR",0x00
STR_BGRND:
        db 0x15,"BGRND",0x00
STR_NORM:
        db 0x15,"NORM",0x16,0x00
STR_BOLD:
        db 0x15,"BOLD",0x16,0x00
STR_DRAW:
        db 0x15,"DRAW",0x16,0x00
STR_THIN:
        db 0x15,"THIN",0x16,0x00
STR_WAIT:
        db 0x15,"WAIT",0x16,0x00
STR_FUNC:
        db 0x15,"FUNC",0x00
STR_EURO:
        db 0x15,"EURO",0x00
STR_REM:
        db 0x15,"REM",0x16,0x00
STR_BIG:
        db 0x15,"BIG",0x16,0x00
STR_SHIFT:
        db 0x15,"SHIFT",0x16,0x00
STR_RAINBOW:
        db 0x15,"RAINBOW",0x16,0x00
STR_MAGIC_OFF:
        db 0x15,"MAGIC OFF",0x16,0x00
STR_PAUSE:
        db 0x15,"PAUSE",0x16,0x00
STR_HOLD:
        db 0x15,"HOLD",0x16,0x00
STR_HALT:
        db 0x15,"HALT",0x16,0x00
STR_UP:
        db 0x15,"UP",0x16,0x00
STR_DOWN:
        db 0x15,"DOWN",0x16,0x00
STR_SPEED:
        db 0x15,"SPEED ",0x00
STR_GRAPH:
        db 0x15,"GRAPH ",0x00
STR_MAGIC:
        db 0x15,"MAGIC",0x16,0x00

STR_C_BLACK:
        db 0x15,"BLACK",0x16,0x00
STR_SPEED_0:
        db 0x15,"S0",0x16,0x00
        ds ATTR_LABEL_TABLE+0x100-$,0

; ---- COLOUR_NAME_TABLE: indexed by colour code 80-8F fg, 90-9F bg; 0000 = no label
COLOUR_NAME_TABLE:
        dw STR_C_BLACK             ; 00  .BLACK.
        dw STR_C_D_GRE             ; 01  .D-GRE.
        dw STR_C_M_GRE             ; 02  .M-GRE.
        dw STR_C_GREEN             ; 03  .GREEN.
        dw STR_C_D_RED             ; 04  .D-RED.
        dw STR_C_D_YEL             ; 05  .D-YEL.
        dw STR_C_D_LIM             ; 06  .D-LIM.
        dw STR_C_LIME              ; 07  .LIME.
        dw STR_C_M_RED             ; 08  .M-RED.
        dw STR_C_D_ORA             ; 09  .D-ORA.
        dw STR_C_M_YEL             ; 0a  .M-YEL.
        dw STR_C_LEMON             ; 0b  .LEMON.
        dw STR_C_RED               ; 0c  .RED.
        dw STR_C_ORANGE            ; 0d  .ORANGE.
        dw STR_C_GOLD              ; 0e  .GOLD.
        dw STR_C_YELLOW            ; 0f  .YELLOW.
        dw STR_B_BLK               ; 10  .B-BLK.
        dw STR_B_RED               ; 11  .B-RED.
        dw STR_B_GRE               ; 12  .B-GRE.
        dw STR_B_YEL               ; 13  .B-YEL.
        dw STR_B_BLK               ; 14  .B-BLK.
        dw STR_B_RED               ; 15  .B-RED.
        dw STR_B_GRE               ; 16  .B-GRE.
        dw STR_B_YEL               ; 17  .B-YEL.
        dw STR_B_BLK               ; 18  .B-BLK.
        dw STR_B_RED               ; 19  .B-RED.
        dw STR_B_GRE               ; 1a  .B-GRE.
        dw STR_B_YEL               ; 1b  .B-YEL.
        dw STR_B_BLK               ; 1c  .B-BLK.
        dw STR_B_RED               ; 1d  .B-RED.
        dw STR_B_GRE               ; 1e  .B-GRE.
        dw STR_B_YEL               ; 1f  .B-YEL.
STR_B_BLK:
        db 0x15,"B-BLK",0x16,0x00
STR_B_RED:
        db 0x15,"B-RED",0x16,0x00
STR_B_YEL:
        db 0x15,"B-YEL",0x16,0x00
STR_B_GRE:
        db 0x15,"B-GRE",0x16,0x00

; ---- ATTR_LABEL_TABLE_B0: indexed by attribute byte B0-BF; 0000 = no label
ATTR_LABEL_TABLE_B0:
        dw STR_REM                 ; b0  .REM.
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw STR_DRAW                ; b8  .DRAW.
        dw STR_THIN                ; b9  .THIN.
        dw STR_WAIT                ; ba  .WAIT.
        dw STR_HOLD                ; bb  .HOLD.
        dw STR_RAINBOW             ; bc  .RAINBOW.
        dw STR_MAGIC_OFF           ; bd  .MAGIC OFF.
        dw STR_TINY                ; be  .TINY.
        dw 0
STR_ITALIC:
        db 0x15,"ITALIC",0x16,0x00
STR_FLASH:
        db 0x15,"FLASH",0x16,0x00
STR_END:
        db 0x15,"END",0x16,0x00
        db 0x00
STR_LEFT:
        db 0x15,"LEFT",0x16,0x00
        db 0x00


; ---- ATTR_LABEL_TABLE_B0 + 2*(attr-B0): the D0-EF slots are never indexed (the
;      editor's redraw treats D0/E0-class bytes as characters) and hold strings;
;      SPEED_STR_TABLE (F0-F7) must sit at +0080.
STR_C_D_GRE:
        db 0x15,"D-GRE",0x16,0x00
STR_C_M_GRE:
        db 0x15,"M-GRE",0x16,0x00
STR_C_GREEN:
        db 0x15,"GREEN",0x16,0x00
STR_C_D_RED:
        db 0x15,"D-RED",0x16,0x00
STR_C_D_YEL:
        db 0x15,"D-YEL",0x16,0x00
STR_C_D_LIM:
        db 0x15,"D-LIM",0x16,0x00
STR_C_LIME:
        db 0x15,"LIME",0x16,0x00
STR_C_M_RED:
        db 0x15,"M-RED",0x16,0x00
        ds ATTR_LABEL_TABLE_B0+0x80-$,0

; ---- SPEED_STR_TABLE: indexed by speed 0-7 -> "S0".."S7"; 0000 = no label
SPEED_STR_TABLE:
        dw STR_SPEED_0                            ; 00  .S0.
        dw STR_SPEED_1                            ; 01  .S1.
        dw STR_SPEED_2                            ; 02  .S2.
        dw STR_SPEED_3                            ; 03  .S3.
        dw STR_SPEED_4                            ; 04  .S4.
        dw STR_SPEED_5                            ; 05  .S5.
        dw STR_SPEED_6                            ; 06  .S6.
        dw STR_SPEED_7                            ; 07  .S7.
STR_TOP_OF_MSG:                 ; show_top_of_msg adds the channel digits
        db "TOP OF MSG ",0x00
MENU_STRINGS:
        db " ADDRESS? ",0x00
MENU_STR_MSG_FULL:
        db " FULL!! MSG# ?",0x00
MENU_STR_CLR_ALL:
        db " CLR ALL Y/N",0x00
MENU_STR_TIME:
        db " TIME?    ",0x00
MENU_STR_AM_PM:
        db " AM? Y/N ",0x00
MENU_STR_PROG_MSG:
        db " PROG MSG? ",0x00
MENU_STR_SEQ_MSG:
        db " SEQ MSG? ",0x00
MENU_STR_INVALID:
        db 0x03,"    INVALID    ",0x00
MENU_STR_MEM_FULL:
        db 0x0a," MEMORY FULL  ",0x00
MENU_STR_100_KEYS:
        db 0x05," 100 KEYS LEFT ",0x00
MENU_STR_SEQ_FULL:
        db 0x03," SEQUENCE FULL",0x00
STR_C_D_ORA:
        db 0x15,"D-ORA",0x16,0x00
STR_C_M_YEL:
        db 0x15,"M-YEL",0x16,0x00
STR_C_LEMON:
        db 0x15,"LEMON",0x16,0x00
STR_C_RED:
        db 0x15,"RED",0x16,0x00
STR_C_ORANGE:
        db 0x15,"ORANGE",0x16,0x00
STR_C_GOLD:
        db 0x15,"GOLD",0x16,0x00
STR_C_YELLOW:
        db 0x15,"YELLOW",0x16,0x00
STR_SPEED_1:
        db 0x15,"S1",0x16,0x00
STR_SPEED_2:
        db 0x15,"S2",0x16,0x00
STR_SPEED_3:
        db 0x15,"S3",0x16,0x00
STR_SPEED_4:
        db 0x15,"S4",0x16,0x00
STR_SPEED_5:
        db 0x15,"S5",0x16,0x00
STR_SPEED_6:
        db 0x15,"S6",0x16,0x00
STR_SPEED_7:
        db 0x15,"S7",0x16,0x00
STR_TINY:
        db 0x15,"TINY",0x16,0x00

; ---- data 3135-382c: 8 bytes per glyph: 7 column bytes + width byte (see glyph_lookup)
FONT:
        db 0x1c,0x14,0x14,0x77,0x22,0x14,0x08,0x07           ; glyph   0 width 7
        db 0x08,0x14,0x22,0x77,0x14,0x14,0x1c,0x07           ; glyph   1 width 7
        db 0x30,0x70,0x38,0x34,0x3c,0x74,0x38,0x07           ; glyph   2 width 7
        db 0x20,0x70,0x70,0x3f,0x02,0x04,0x00,0x06           ; glyph   3 width 6
        db 0x08,0x1c,0x22,0x2a,0x22,0x1c,0x08,0x07           ; glyph   4 width 7
        db 0x07,0x49,0x79,0x49,0x07,0x00,0x00,0x05           ; glyph   5 width 5
        db 0x10,0x18,0x1c,0x18,0x10,0x00,0x00,0x05           ; glyph   6 width 5
        db 0x08,0x1c,0x3e,0x7f,0x3e,0x1c,0x08,0x07           ; glyph   7 width 7
        db 0x7f,0x7f,0x7f,0x7f,0x7f,0x00,0x00,0x06           ; glyph   8 width 6
        db 0x1c,0x3e,0x7f,0x7f,0x3e,0x1c,0x00,0x07           ; glyph   9 width 7
        db 0x04,0x7c,0x46,0x77,0x46,0x7c,0x04,0x07           ; glyph  10 width 7
        db 0x10,0x30,0x54,0x56,0x5f,0x50,0x30,0x07           ; glyph  11 width 7
        db 0x18,0x1e,0x7f,0x1e,0x18,0x00,0x00,0x05           ; glyph  12 width 5
        db 0x2c,0x6e,0x6d,0x6f,0x6f,0x3e,0x1c,0x07           ; glyph  13 width 7
        db 0x1c,0x22,0x41,0x4f,0x51,0x22,0x1c,0x07           ; glyph  14 width 7
        db 0x20,0x3c,0x22,0x63,0x22,0x3c,0x20,0x07           ; glyph  15 width 7
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  16 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  17 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  18 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  19 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  20 width 1
        db 0x00,0x00,0x08,0x1c,0x00,0x00,0x00,0x04           ; glyph  21 width 4
        db 0x1c,0x08,0x00,0x00,0x00,0x00,0x00,0x04           ; glyph  22 width 4
        db 0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x00,0x06           ; glyph  23 width 6
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  24 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  25 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  26 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  27 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  28 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  29 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  30 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  31 width 1
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x05           ; glyph  32 width 5
        db 0x5f,0x00,0x00,0x00,0x00,0x00,0x00,0x04           ; glyph  33 width 4
        db 0x07,0x00,0x07,0x00,0x00,0x00,0x00,0x03           ; glyph  34 width 3
        db 0x14,0x7f,0x14,0x7f,0x14,0x00,0x00,0x05           ; glyph  35 width 5
        db 0x26,0x49,0x7f,0x49,0x32,0x00,0x00,0x05           ; glyph  36 width 5
        db 0x42,0x25,0x12,0x08,0x24,0x52,0x21,0x07           ; glyph  37 width 7
        db 0x36,0x49,0x49,0x56,0x20,0x50,0x00,0x06           ; glyph  38 width 6
        db 0x07,0x00,0x00,0x00,0x00,0x00,0x00,0x01           ; glyph  39 width 1
        db 0x1c,0x22,0x41,0x00,0x00,0x00,0x00,0x03           ; glyph  40 width 3
        db 0x41,0x22,0x1c,0x00,0x00,0x00,0x00,0x03           ; glyph  41 width 3
        db 0x2a,0x1c,0x7f,0x1c,0x2a,0x00,0x00,0x05           ; glyph  42 width 5
        db 0x08,0x08,0x3e,0x08,0x08,0x00,0x00,0x05           ; glyph  43 width 5
        db 0x40,0x30,0x30,0x00,0x00,0x00,0x00,0x03           ; glyph  44 width 3
        db 0x08,0x08,0x08,0x08,0x00,0x00,0x00,0x04           ; glyph  45 width 4
        db 0x60,0x60,0x00,0x00,0x00,0x00,0x00,0x04           ; glyph  46 width 4
        db 0x40,0x20,0x10,0x08,0x04,0x02,0x01,0x07           ; glyph  47 width 7
        db 0x3e,0x41,0x41,0x41,0x3e,0x00,0x00,0x05           ; glyph  48 width 5
        db 0x41,0x7f,0x40,0x00,0x00,0x00,0x00,0x03           ; glyph  49 width 3
        db 0x42,0x61,0x51,0x49,0x46,0x00,0x00,0x05           ; glyph  50 width 5
        db 0x22,0x41,0x49,0x49,0x36,0x00,0x00,0x05           ; glyph  51 width 5
        db 0x08,0x0c,0x0a,0x7f,0x08,0x00,0x00,0x05           ; glyph  52 width 5
        db 0x2f,0x49,0x49,0x49,0x31,0x00,0x00,0x05           ; glyph  53 width 5
        db 0x3c,0x4a,0x49,0x49,0x30,0x00,0x00,0x05           ; glyph  54 width 5
        db 0x01,0x71,0x09,0x05,0x03,0x00,0x00,0x05           ; glyph  55 width 5
        db 0x36,0x49,0x49,0x49,0x36,0x00,0x00,0x05           ; glyph  56 width 5
        db 0x06,0x49,0x49,0x49,0x3e,0x00,0x00,0x05           ; glyph  57 width 5
        db 0x6c,0x6c,0x00,0x00,0x00,0x00,0x00,0x02           ; glyph  58 width 2
        db 0x40,0x6c,0x6c,0x00,0x00,0x00,0x00,0x03           ; glyph  59 width 3
        db 0x08,0x14,0x22,0x41,0x00,0x00,0x00,0x04           ; glyph  60 width 4
        db 0x14,0x14,0x14,0x14,0x00,0x00,0x00,0x04           ; glyph  61 width 4
        db 0x41,0x22,0x14,0x08,0x00,0x00,0x00,0x04           ; glyph  62 width 4
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph  63 width 5
        db 0x3e,0x41,0x4f,0x49,0x2e,0x00,0x00,0x05           ; glyph  64 width 5
        db 0x7e,0x09,0x09,0x09,0x7e,0x00,0x00,0x05           ; glyph  65 width 5
        db 0x7f,0x49,0x49,0x49,0x36,0x00,0x00,0x05           ; glyph  66 width 5
        db 0x3e,0x41,0x41,0x41,0x22,0x00,0x00,0x05           ; glyph  67 width 5
        db 0x7f,0x41,0x41,0x41,0x3e,0x00,0x00,0x05           ; glyph  68 width 5
        db 0x7f,0x49,0x49,0x49,0x41,0x00,0x00,0x05           ; glyph  69 width 5
        db 0x7f,0x09,0x09,0x09,0x01,0x00,0x00,0x05           ; glyph  70 width 5
        db 0x3e,0x41,0x41,0x51,0x32,0x00,0x00,0x05           ; glyph  71 width 5
        db 0x7f,0x08,0x08,0x08,0x7f,0x00,0x00,0x05           ; glyph  72 width 5
        db 0x41,0x7f,0x41,0x00,0x00,0x00,0x00,0x03           ; glyph  73 width 3
        db 0x20,0x40,0x41,0x3f,0x01,0x00,0x00,0x05           ; glyph  74 width 5
        db 0x7f,0x08,0x14,0x22,0x41,0x00,0x00,0x05           ; glyph  75 width 5
        db 0x7f,0x40,0x40,0x40,0x40,0x00,0x00,0x05           ; glyph  76 width 5
        db 0x7f,0x02,0x0c,0x02,0x7f,0x00,0x00,0x05           ; glyph  77 width 5
        db 0x7f,0x02,0x04,0x08,0x7f,0x00,0x00,0x05           ; glyph  78 width 5
        db 0x3e,0x41,0x41,0x41,0x3e,0x00,0x00,0x05           ; glyph  79 width 5
        db 0x7f,0x09,0x09,0x09,0x06,0x00,0x00,0x05           ; glyph  80 width 5
        db 0x3e,0x41,0x51,0x61,0x7e,0x00,0x00,0x05           ; glyph  81 width 5
        db 0x7f,0x09,0x19,0x29,0x46,0x00,0x00,0x05           ; glyph  82 width 5
        db 0x26,0x49,0x49,0x49,0x32,0x00,0x00,0x05           ; glyph  83 width 5
        db 0x01,0x01,0x7f,0x01,0x01,0x00,0x00,0x05           ; glyph  84 width 5
        db 0x3f,0x40,0x40,0x40,0x3f,0x00,0x00,0x05           ; glyph  85 width 5
        db 0x1f,0x20,0x40,0x20,0x1f,0x00,0x00,0x05           ; glyph  86 width 5
        db 0x3f,0x40,0x38,0x40,0x3f,0x00,0x00,0x05           ; glyph  87 width 5
        db 0x63,0x14,0x08,0x14,0x63,0x00,0x00,0x05           ; glyph  88 width 5
        db 0x07,0x08,0x70,0x08,0x07,0x00,0x00,0x05           ; glyph  89 width 5
        db 0x61,0x51,0x49,0x45,0x43,0x00,0x00,0x05           ; glyph  90 width 5
        db 0x7f,0x41,0x41,0x00,0x00,0x00,0x00,0x03           ; glyph  91 width 3
        db 0x02,0x04,0x08,0x10,0x20,0x00,0x00,0x05           ; glyph  92 width 5
        db 0x41,0x41,0x7f,0x00,0x00,0x00,0x00,0x03           ; glyph  93 width 3
        db 0x04,0x02,0x7f,0x02,0x04,0x00,0x00,0x05           ; glyph  94 width 5
        db 0x1c,0x22,0x41,0x4f,0x51,0x22,0x1c,0x07           ; glyph  95 width 7
        db 0x60,0x5e,0x55,0x55,0x41,0x02,0x00,0x06           ; glyph  96 width 6
        db 0x20,0x54,0x54,0x54,0x78,0x00,0x00,0x05           ; glyph  97 width 5
        db 0x7f,0x44,0x44,0x44,0x38,0x00,0x00,0x05           ; glyph  98 width 5
        db 0x38,0x44,0x44,0x44,0x44,0x00,0x00,0x05           ; glyph  99 width 5
        db 0x38,0x44,0x44,0x44,0x7f,0x00,0x00,0x05           ; glyph 100 width 5
        db 0x38,0x54,0x54,0x54,0x58,0x00,0x00,0x05           ; glyph 101 width 5
        db 0x08,0x7e,0x09,0x02,0x00,0x00,0x00,0x04           ; glyph 102 width 4
        db 0x38,0x44,0x44,0x54,0x74,0x00,0x00,0x05           ; glyph 103 width 5
        db 0x7f,0x04,0x04,0x04,0x78,0x00,0x00,0x05           ; glyph 104 width 5
        db 0x7a,0x00,0x00,0x00,0x00,0x00,0x00,0x01           ; glyph 105 width 1
        db 0x20,0x40,0x44,0x3c,0x04,0x00,0x00,0x05           ; glyph 106 width 5
        db 0x7f,0x10,0x28,0x44,0x00,0x00,0x00,0x04           ; glyph 107 width 4
        db 0x7f,0x00,0x00,0x00,0x00,0x00,0x00,0x01           ; glyph 108 width 1
        db 0x78,0x04,0x18,0x04,0x78,0x00,0x00,0x05           ; glyph 109 width 5
        db 0x7c,0x08,0x04,0x04,0x78,0x00,0x00,0x05           ; glyph 110 width 5
        db 0x38,0x44,0x44,0x44,0x38,0x00,0x00,0x05           ; glyph 111 width 5
        db 0x7c,0x14,0x14,0x14,0x08,0x00,0x00,0x05           ; glyph 112 width 5
        db 0x38,0x44,0x54,0x64,0x78,0x00,0x00,0x05           ; glyph 113 width 5
        db 0x7c,0x08,0x04,0x04,0x08,0x00,0x00,0x05           ; glyph 114 width 5
        db 0x48,0x54,0x54,0x54,0x24,0x00,0x00,0x05           ; glyph 115 width 5
        db 0x04,0x3f,0x44,0x00,0x00,0x00,0x00,0x03           ; glyph 116 width 3
        db 0x3c,0x40,0x40,0x40,0x3c,0x00,0x00,0x05           ; glyph 117 width 5
        db 0x0c,0x30,0x40,0x30,0x0c,0x00,0x00,0x05           ; glyph 118 width 5
        db 0x3c,0x40,0x30,0x40,0x3c,0x00,0x00,0x05           ; glyph 119 width 5
        db 0x44,0x28,0x10,0x28,0x44,0x00,0x00,0x05           ; glyph 120 width 5
        db 0x04,0x08,0x70,0x08,0x04,0x00,0x00,0x05           ; glyph 121 width 5
        db 0x44,0x64,0x54,0x4c,0x44,0x00,0x00,0x05           ; glyph 122 width 5
        db 0x08,0x36,0x41,0x00,0x00,0x00,0x00,0x03           ; glyph 123 width 3
        db 0x40,0x40,0x40,0x40,0x40,0x00,0x00,0x05           ; glyph 124 width 5
        db 0x41,0x36,0x08,0x00,0x00,0x00,0x00,0x03           ; glyph 125 width 3
        db 0x08,0x04,0x08,0x04,0x00,0x00,0x00,0x04           ; glyph 126 width 4
        db 0x08,0x08,0x08,0x08,0x2a,0x1c,0x08,0x07           ; glyph 127 width 7
        db 0x78,0x15,0x16,0x14,0x78,0x00,0x00,0x05           ; glyph 128 width 5
        db 0x20,0x55,0x56,0x54,0x78,0x00,0x00,0x05           ; glyph 129 width 5
        db 0x1e,0x21,0x61,0x21,0x21,0x00,0x00,0x05           ; glyph 130 width 5
        db 0x18,0x24,0x64,0x24,0x24,0x00,0x00,0x05           ; glyph 131 width 5
        db 0x7c,0x56,0x55,0x56,0x44,0x00,0x00,0x05           ; glyph 132 width 5
        db 0x7c,0x54,0x56,0x55,0x44,0x00,0x00,0x05           ; glyph 133 width 5
        db 0x38,0x54,0x56,0x55,0x58,0x00,0x00,0x05           ; glyph 134 width 5
        db 0x7c,0x55,0x56,0x54,0x44,0x00,0x00,0x05           ; glyph 135 width 5
        db 0x38,0x55,0x56,0x54,0x58,0x00,0x00,0x05           ; glyph 136 width 5
        db 0x38,0x56,0x55,0x56,0x58,0x00,0x00,0x05           ; glyph 137 width 5
        db 0x78,0x0c,0x0a,0x7f,0x49,0x49,0x41,0x07           ; glyph 138 width 7
        db 0x20,0x54,0x54,0x78,0x54,0x54,0x08,0x07           ; glyph 139 width 7
        db 0x7c,0x09,0x11,0x21,0x7c,0x00,0x00,0x05           ; glyph 140 width 5
        db 0x7c,0x09,0x05,0x05,0x78,0x00,0x00,0x05           ; glyph 141 width 5
        db 0x3c,0x41,0x42,0x40,0x3c,0x00,0x00,0x05           ; glyph 142 width 5
        db 0x78,0x15,0x14,0x15,0x78,0x00,0x00,0x05           ; glyph 143 width 5
        db 0x20,0x55,0x54,0x55,0x78,0x00,0x00,0x05           ; glyph 144 width 5
        db 0x38,0x45,0x44,0x45,0x38,0x00,0x00,0x05           ; glyph 145 width 5
        db 0x30,0x4a,0x48,0x4a,0x30,0x00,0x00,0x05           ; glyph 146 width 5
        db 0x3c,0x41,0x40,0x41,0x3c,0x00,0x00,0x05           ; glyph 147 width 5
        db 0x78,0x14,0x15,0x14,0x78,0x00,0x00,0x05           ; glyph 148 width 5
        db 0x20,0x54,0x55,0x54,0x78,0x00,0x00,0x05           ; glyph 149 width 5
        db 0x40,0x3e,0x51,0x49,0x45,0x3e,0x01,0x07           ; glyph 150 width 7
        db 0x40,0x3c,0x52,0x4a,0x3c,0x02,0x00,0x06           ; glyph 151 width 6
        db 0x38,0x42,0x40,0x42,0x38,0x00,0x00,0x05           ; glyph 152 width 5
        db 0x1c,0x22,0x7f,0x22,0x1c,0x00,0x00,0x05           ; glyph 153 width 5
        db 0x07,0x08,0x7f,0x08,0x07,0x00,0x00,0x05           ; glyph 154 width 5
        db 0x5c,0x62,0x01,0x01,0x62,0x5c,0x00,0x06           ; glyph 155 width 6
        db 0x78,0x14,0x16,0x15,0x78,0x00,0x00,0x05           ; glyph 156 width 5
        db 0x7f,0x25,0x25,0x25,0x1a,0x00,0x00,0x05           ; glyph 157 width 5
        db 0x41,0x49,0x49,0x49,0x41,0x00,0x00,0x05           ; glyph 158 width 5
        db 0x01,0x7f,0x01,0x7f,0x01,0x00,0x00,0x05           ; glyph 159 width 5
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph 160 width 5
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph 161 width 5
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph 162 width 5
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph 163 width 5
        db 0x63,0x55,0x49,0x41,0x41,0x00,0x00,0x05           ; glyph 164 width 5
        db 0x20,0x54,0x56,0x55,0x78,0x00,0x00,0x05           ; glyph 165 width 5
        db 0x30,0x48,0x45,0x40,0x20,0x00,0x00,0x05           ; glyph 166 width 5
        db 0x70,0x4c,0x43,0x4c,0x70,0x00,0x00,0x05           ; glyph 167 width 5
        db 0x3e,0x49,0x49,0x49,0x3e,0x00,0x00,0x05           ; glyph 168 width 5
        db 0x70,0x0c,0x03,0x0c,0x70,0x00,0x00,0x05           ; glyph 169 width 5
        db 0x3e,0x40,0x42,0x41,0x3e,0x00,0x00,0x05           ; glyph 170 width 5
        db 0x7f,0x01,0x01,0x01,0x01,0x00,0x00,0x05           ; glyph 171 width 5
        db 0x3c,0x40,0x42,0x41,0x3c,0x00,0x00,0x05           ; glyph 172 width 5
        db 0x3e,0x41,0x42,0x40,0x3e,0x00,0x00,0x05           ; glyph 173 width 5
        db 0x00,0x7d,0x00,0x00,0x00,0x00,0x00,0x02           ; glyph 174 width 2
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 175 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 176 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 177 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 178 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 179 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 180 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 181 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 182 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 183 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 184 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 185 width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 186 width 1
        db 0x38,0x44,0x46,0x45,0x38,0x00,0x00,0x05           ; glyph 187 width 5
        db 0x76,0x01,0x00,0x00,0x00,0x00,0x00,0x02           ; glyph 188 width 2
        db 0x44,0x7e,0x45,0x00,0x00,0x00,0x00,0x03           ; glyph 189 width 3
        db 0x30,0x48,0x4c,0x4a,0x30,0x00,0x00,0x05           ; glyph 190 width 5

; ---- CHAR_FLAGS: 256 bytes, indexed by character code. Bit 0 is tested by
;      store_fix_bad_bytes (substitutes 0x3F for the character), bit 1 by the message
;      scanners to decide whether a byte is printable text. Rendered as part
;      of FONT by the original disassembly, but it is not glyph data - FONT
;      holds glyphs 0..190 and this table begins immediately after.
CHAR_FLAGS:
        db 0x07,0x07,0x07,0x02,0x07,0x07,0x02,0x02,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x02   ; char 00-0f
        db 0x02,0x02,0x02,0x02,0x02,0x00,0x00,0x00,0x02,0x02,0x02,0x02,0x07,0x07,0x07,0x02   ; char 10-1f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 20-2f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 30-3f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 40-4f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 50-5f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 60-6f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 70-7f
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02   ; char 80-8f
        db 0x02,0x02,0x02,0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07   ; char 90-9f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char a0-af
        db 0x02,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x00,0x02,0x02,0x02,0x02,0x02,0x02,0x07   ; char b0-bf
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char c0-cf
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x07,0x00,0x00,0x00,0x00   ; char d0-df
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char e0-ef
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07   ; char f0-ff

; ============================================================================
;  Key-position -> character/attribute tables, one per input layer. Indexed by
;  the key number that IR_KEY_TABLE yields, 64 keys laid out as the 8x8 matrix
;  keypad_scan walks. Layer chosen at 0x23C1:
;
;      EURO_STATE  set      -> CHARSET_EURO
;      SHIFT_STATE clear    -> CHARSET_LOWER  / CHARSET_UPPER   (by CAPS_LOCK)
;      SHIFT_STATE set      -> CHARSET_UPPER2 / CHARSET_LOWER2  (by CAPS_LOCK)
;
;  On the remote these are one key labelled UPPER/LOWER, whose shifted
;  function is EUROPE: unshifted it toggles CAPS_LOCK (0x216C), shifted it
;  toggles EURO_STATE (0x2184).
;
;  So SHIFT selects the alternate function layer and flips case; CAPS_LOCK
;  flips case on its own. Both SHIFT_STATE and EURO_STATE are cleared after
;  every key. Entries below 0x20 and 0xB0-0xBF are attribute bytes - the
;  glosses are the editor's own names, from ATTR_LABEL_TABLE.
; ============================================================================

; ---- CHARSET_LOWER: unshifted, caps off
CHARSET_LOWER:
        db "kf",0x12,"pa",0x0e,0x11,0x1e              ; 00-07  k f BOLD p a 0E NORM GRAPH
        db " ",0x7f,")%zwyt"                          ; 08-0f  SP 7F ) % z w y t
        db "ni",0x1f,"hd",0x09,0x1a,0x19              ; 10-17  n i MAGIC h d PROG MSG? UP PAUSE
        db "0",0x1d,"2586k",0x00                      ; 18-1f  0 SHIFT 2 5 8 6 k 00
        db "lgvmq",0x04,0x10,0x14                     ; 20-27  l g v m q SEQ MSG? BIG FLASH
        db ".",0x1c,"(*+9xs"                          ; 28-2f  . 1C ( * + 9 x s
        db "ojbce",0x0d,0x07,0x15                     ; 30-37  o j b c e 0D BEEP COLOR
        db 0x08,0x0a,"1473ur"                         ; 38-3f  08 0A 1 4 7 3 u r

; ---- CHARSET_UPPER: unshifted, caps on
CHARSET_UPPER:
        db "KF",0x12,"PA",0x0e,0x11,0x1e              ; 00-07  K F BOLD P A 0E NORM GRAPH
        db " ",0x7f,")%ZWYT"                          ; 08-0f  SP 7F ) % Z W Y T
        db "NI",0x1f,"HD",0x09,0x1a,0x19              ; 10-17  N I MAGIC H D PROG MSG? UP PAUSE
        db "0",0x1d,"2586K",0x00                      ; 18-1f  0 SHIFT 2 5 8 6 K 00
        db "LGVMQ",0x04,0x10,0x14                     ; 20-27  L G V M Q SEQ MSG? BIG FLASH
        db ".",0x1c,"(*+9XS"                          ; 28-2f  . 1C ( * + 9 X S
        db "OJBCE",0x0d,0x07,0x15                     ; 30-37  O J B C E 0D BEEP COLOR
        db 0x08,0x0a,"1473UR"                         ; 38-3f  08 0A 1 4 7 3 U R

; ---- CHARSET_UPPER2: SHIFT held, caps off
CHARSET_UPPER2:
        db "KF",0x18,"PA",0x03,0x17,"_"               ; 00-07  K F LEFT P A END 17 _
        db " ",0x7f,"&'ZWYT"                          ; 08-0f  SP 7F & ' Z W Y T
        db "NI",0xbd,"HD",0x02,0x1b,0x19              ; 10-17  N I MAGIC OFF H D 02 DOWN PAUSE
        db "0",0x1d,"2586K",0x00                      ; 18-1f  0 SHIFT 2 5 8 6 K 00
        db "LGVMQ",0xbb,0x13,0x14                     ; 20-27  L G V M Q HOLD ITALIC FLASH
        db ":",0xb6,"$#-9XS"                          ; 28-2f  : B6 $ # - 9 X S
        db "OJBCE",0xb7,0x0f,0x16                     ; 30-37  O J B C E B7 RIGHT BGRND
        db 0x0b,0x0c,"1473UR"                         ; 38-3f  0B 0C 1 4 7 3 U R

; ---- CHARSET_LOWER2: SHIFT held, caps on
CHARSET_LOWER2:
        db "kf",0x18,"pa",0x03,0x17,"_"               ; 00-07  k f LEFT p a END 17 _
        db " ",0x7f,"&'zwyt"                          ; 08-0f  SP 7F & ' z w y t
        db "ni",0xbd,"hd",0x02,0x1b,0x19              ; 10-17  n i MAGIC OFF h d 02 DOWN PAUSE
        db "0",0x1d,"2586k",0x00                      ; 18-1f  0 SHIFT 2 5 8 6 k 00
        db "lgvmq",0xbb,0x13,0x14                     ; 20-27  l g v m q HOLD ITALIC FLASH
        db ":",0xb6,"$#-9xs"                          ; 28-2f  : B6 $ # - 9 x s
        db "ojbce",0xb7,0x0f,0x16                     ; 30-37  o j b c e B7 RIGHT BGRND
        db 0x0b,0x0c,"1473ur"                         ; 38-3f  0B 0C 1 4 7 3 u r

; ---- CHARSET_EURO: EUROPE modifier active. 47 accented Latin characters in
;      94-9E, C0-CF, DC-DF, E0-EF - the demo text advertises "PROGRAMS 47
;      EUROPEAN CHARACTERS" and the editor displays "EURO" while this layer is
;      live (0x2928). Not graphics: built-in graphics are the 1E GRAPH
;      attribute, user-drawn ones the B8 DRAW attribute.
CHARSET_EURO:
        db 0xca,0xc5,0x12,0xcf,0xc0,0xde,0x11,0x1e    ; 00-07  CA C5 BOLD CF C0 DE NORM GRAPH
        db 0x9e,0x7f,0x9d,0x96,0xed,0xe6,0xe8,0xe3    ; 08-0f  9E 7F 9D 96 ED E6 E8 E3
        db 0xcd,0xc8,0x1f,0xc7,0xc3,0xdc,0x1a,0x19    ; 10-17  CD C8 MAGIC C7 C3 DC UP PAUSE
        db 0x9b,0x1d,0x98,0xef,0xea,0x94,0xca,0x00    ; 18-1f  9B SHIFT 98 EF EA 94 CA 00
        db 0xcb,0xc6,0xe5,0xcc,0xe0,0xdd,0x10,0x14    ; 20-27  CB C6 E5 CC E0 DD BIG FLASH
        db 0x9c,0x1c,0x9a,0x95,0xec,0xeb,0xe7,0xe2    ; 28-2f  9C 1C 9A 95 EC EB E7 E2
        db 0xce,0xc9,0xc1,0xc2,0xc4,0xdf,0x07,0x15    ; 30-37  CE C9 C1 C2 C4 DF BEEP COLOR
        db 0x08,0x0a,0x97,0xee,0xe9,0x99,0xe4,0xe1    ; 38-3f  08 0A 97 EE E9 99 E4 E1
        db 0xda,0xda                                  ; 40-41  DA DA


; ---- DEMO_MESSAGE: shown while every channel is empty. P21 cut the factory
;      sales pitch (~700 bytes) down to a line that still exercises the fonts
;      and colours; the room went to the render-loop packet processing.
DEMO_MESSAGE:
        db 0x12,"COLOR CELLS ",0x13,0x8c,"CC784 ",0x11,0xbc,0x14,"MULTI-COLOR DISPLAY"
        db 0xbe,"TINY PRICE",0x10,"LARGE IMPACT",0x03,0xdb

; ---- TEST_MESSAGE: built-in test pattern (test_mode_enter). Sits inside the demo
;      text block but is a separate message with its own 0x03 terminator.
TEST_MESSAGE:
        db "CURRENT TEST  "
        db 0x10,0x17,0x17,0x17,0x17,0x17,0x17,0x17," ",0x03

; ---- ota_updating_msg: what the panel shows from B5 'B' to the reboot, via the
;      test-mode buffer (28 bytes max). PAUSE, THIN, the word, WAIT: parked until
;      a key. Last thing before the trailer, so editing it moves nothing else.
ota_updating_msg:
        db 0x19,0xb9,">FW UPDATE<",0xba,0x03

; ---- trailer page 3FC0-3FFF (CC784_ota.md §3): magic, sequence number, state
;      and image CRC, filled in by tools/cc784_ota.py pack. Erased in the build.
        ds 0x3fc0-$,0xff
TRAILER:
        ds 0x4000-$,0xff

        ds 0x8000-$,0xff        ; bank B: the packer fills it, the T48 image carries both
