; ============================================================================
;  Color Cells CC784NIR LED sign - PATCHED firmware source
;  Assemble:  sjasmplus cc784nir.asm   (produces cc784nir_patched.bin, 32768 B)
;             sjasmplus -DCC710 cc784nir.asm   (cc710_patched.bin: the 59-column panel)
;  NOT byte-identical to the dump. The untouched reconstruction is
;  ../stock/cc784nir.asm; diff the two to see the patches.
;
;  The original firmware is copyright its owner (Color Cells / Innovative Sign
;  Technology, 1993, and successors). The patches, labels and comments are
;  MIT, see ../../LICENSE.
; ============================================================================
        DEVICE NONE

; Patched build: the stock reconstruction (../stock/cc784nir.asm) plus the
; patches in CC784_patched.md. Up to the tag patched-v39 the rest was kept
; identical to stock; after it the code is restructured freely and the git
; history is the changelog. Addresses differ from stock throughout.

    IFDEF CC710
        OUTPUT "cc710_patched.bin"
    ELSE
        OUTPUT "cc784nir_patched.bin"
    ENDIF

FRAMEBUF             equ 0x4000
FRAMEBUF_SIZE        equ 0xc0   ; column ring: 86 visible + the glyph being written; also the TINY line
FRAMEBUF_ROW1        equ FRAMEBUF+FRAME_COLS
FRAMEBUF_TINY        equ FRAMEBUF+2*FRAME_COLS-1   ; TINY line buffer inside the ring
; ---- variables follow the ring, packed with no gaps (P8), grouped by how they
;      start: IMAGE (one INIT_DATA copy), BOOT_ZERO (one clear, its head cleared
;      again for every message), scratch, then what survives a reset.
RAM_VARS             equ FRAMEBUF+FRAMEBUF_SIZE
FRAMEBUF_END         equ RAM_VARS         ; the column ring ends where the variables begin
TXBUF                equ RAM_VARS+0x000   ; reply frames, and the effect staging frame (86 columns)
STAGE_END            equ TXBUF+FRAME_COLS ; end of the staging frame (STAGE_PTR itself on the CC784)
; ---- IMAGE: the variables with a non-zero boot value; init_vars copies INIT_DATA over them
IMAGE                equ RAM_VARS+0x056
FB_COLPTR            equ RAM_VARS+0x056   ; frame-buffer write pointer (next glyph column)
FB_COL               equ RAM_VARS+0x058   ; scroll position: the column the output window is moving toward
STAGE_PTR            equ RAM_VARS+0x05a   ; next free column in TXBUF while an effect stages text
FB_OUT_PTR           equ RAM_VARS+0x05c   ; first column sent to the panel (start of the output window)
STORE_CURSOR         equ RAM_VARS+0x05e
CLK_RUN              equ RAM_VARS+0x060   ; set on every boot by the init image copy
CUR_COLOR            equ RAM_VARS+0x061
DISP_ON              equ RAM_VARS+0x062   ; 0 suppresses row output (effects rewrite FRAMEBUF meanwhile)
COL_COUNT            equ RAM_VARS+0x063   ; columns still free in the staging frame; 0 = no staging (LEFT)
LATCH_BIT7           equ RAM_VARS+0x064   ; 00/80 toggled every 13 frames, OR-ed into CTRL_LATCH bit 7
FLUSH_PENDING        equ RAM_VARS+0x065   ; FF = staged text must be shown before the next effect runs
BAUD_T               equ RAM_VARS+0x066   ; P30: the 300-baud bit in fifths of an interrupt, calibrated from the NMI, 128 by default (was RX_TIMING_PTR)
BAUD_STEP            equ RAM_VARS+0x067   ; P30: fifths of an interrupt per interrupt at the current rate: 5, 10 or 20 (was TX_TIMING_PTR)
BAUD_CAL_LAST        equ RAM_VARS+0x068   ; P30: the previous second's tick count, for the agreement test
RX_IDLE              equ RAM_VARS+0x069   ; P30: frames since the last start bit, held at 255 (was TX_BITMASK)
CAPS_LOCK            equ RAM_VARS+0x06a
ROW_OUT_PENDING      equ RAM_VARS+0x06b   ; FF = the current row still has to be sent
DISP_COUNT           equ RAM_VARS+0x06c   ; P26: interrupts to the next display tick (was TICK1_COUNT, a divider by 1)
NEXT_CHAN            equ RAM_VARS+0x06d   ; channel to show first after the editor (FF = none)
MAGIC_LAST_CHAR      equ RAM_VARS+0x06e   ; magic mode: last char of the current word (punctuation check)
IMAGE_LEN            equ 25
; ---- BOOT_ZERO: cleared at boot; its first RENDER_ZERO_LEN bytes again by init_render
BOOT_ZERO            equ RAM_VARS+0x06f
RENDER_ZERO          equ BOOT_ZERO
DRAW_NO_GAP          equ RAM_VARS+0x06f   ; FF = butt this DRAW graphic against the previous one
DRAW_PREV            equ RAM_VARS+0x070   ; FF = previous item was a DRAW graphic
TINY_RENDER          equ RAM_VARS+0x071   ; FF while attr_tiny drives the display
TINY_FRAME_READY     equ RAM_VARS+0x072   ; tiny mode: a frame is in FRAMEBUF_TINY
MAGIC_MODE           equ RAM_VARS+0x073   ; FF between MAGIC (1F) and MAGIC OFF (BD)
SCROLLING            equ RAM_VARS+0x074   ; FF while the output window is catching up with FB_COLPTR
CLK_RENDER_STEP      equ RAM_VARS+0x075   ; clock (5F) render step 0..8; FF = finished
FLASH_BIT            equ RAM_VARS+0x076   ; 0x10 while the current word flashes; OR-ed into color bytes
MAGIC_COLOR_SET      equ RAM_VARS+0x077   ; magic mode: color set by an attribute, skip the auto change
REDRAW_MAGIC         equ RAM_VARS+0x078   ; editor redraw: MAGIC seen, font resets at each word
MAGIC_FONT_SET       equ RAM_VARS+0x079   ; magic mode: font set by an attribute, skip the random pick
RND_VAL              equ RAM_VARS+0x07a   ; magic mode: words until the next color change
FRAME_DELAY          equ RAM_VARS+0x07b   ; frames to hold before the next column step (1, 3 or 0x50)
FLASH_PENDING        equ RAM_VARS+0x07c   ; 0x10 after FLASH until the next printable char
TEXT_DRAWN           equ RAM_VARS+0x07d   ; FF once a printable char has been drawn since init_render
RAINBOW_IDX          equ RAM_VARS+0x07e   ; RAINBOW per-char color index 1..5, 0 = off; bit 7 = P28 reverse
RAINBOW_REVERSE      equ 0x80
SCROLL_SPEED         equ RAM_VARS+0x07f   ; 0..7 from F0-F7; blank ticks inserted after every frame
FORCE_BOLD           equ RAM_VARS+0x080   ; editor redraw: FF = effect text is drawn bold (unless THIN)
TINY_MODE            equ RAM_VARS+0x081   ; FF = glyphs go to the tiny buffer (menus, TINY)
FONT_MODE            equ RAM_VARS+0x082   ; bit 1 BOLD, bit 2 ITALIC, bit 3 BIG
THIN_MODE            equ RAM_VARS+0x083   ; non-zero after THIN (B9): no bold in effects
RENDER_ZERO_LEN      equ 21
BGRND_PENDING        equ RAM_VARS+0x084   ; editor: BGRND key pressed, next key is the color digit
STAGE_OFFSET         equ RAM_VARS+0x085   ; centering offset of the staged text (free columns / 2)
ROW_PORT             equ RAM_VARS+0x087   ; port group for the row data: 40 first pass, 48 second
BEEP_TICKS           equ RAM_VARS+0x088   ; beeper on while non-zero (port bit 5); beep_start loads BEEP_LEN
ASK_CHAN_PROMPT      equ RAM_VARS+0x08a   ; menu_ask_chan prompt string
GLYPH_WIDTH          equ RAM_VARS+0x08c
GLYPH_PTR            equ RAM_VARS+0x08d
MENU_MSG_PTR         equ RAM_VARS+0x08f   ; message the editor is showing (set with MENU_MSG_FLAG)
CUR_CHAR             equ RAM_VARS+0x091
TEST_MODE            equ RAM_VARS+0x092   ; FF = display TEST_MSG_BUF instead of the sequence; P29: only the OTA parked message sets it
CLK_RENDER_PTR       equ RAM_VARS+0x093   ; clock render: next CLK_ digit to emit
MENU_ACTIVE          equ RAM_VARS+0x095
INS_PTR              equ RAM_VARS+0x096
WINDOW_COLOR         equ RAM_VARS+0x098   ; last color byte at the output window start (bit 4 = flash)
FRAME_COUNT          equ RAM_VARS+0x099   ; frames since LATCH_BIT7 last toggled (mod 13)
COLOR_PENDING        equ RAM_VARS+0x09a   ; editor: COLOR key pressed, next key is the color digit
GRAPH_PENDING        equ RAM_VARS+0x09b   ; editor: GRAPH key pressed, next key selects A0-AF
ROW_COLOR            equ RAM_VARS+0x09c   ; color byte sent ahead of each row
MENU_MSG_FLAG        equ RAM_VARS+0x09d   ; FF = editor has a message to display
EDIT_KEY             equ RAM_VARS+0x09e   ; key/character the editor is processing (0 = none)
RX_BYTE              equ RAM_VARS+0x09f
IR_KEY_CHAR          equ RAM_VARS+0x0a0   ; character decoded from the IR key via the CHARSET_ tables
CTRL_LATCH_SHADOW    equ RAM_VARS+0x0a1
FB_OUT_LEN           equ RAM_VARS+0x0a2   ; bytes to send from FB_OUT_PTR before wrapping to FRAMEBUF
FB_EXTRA_LEN         equ RAM_VARS+0x0a4   ; bytes to send from FRAMEBUF after the wrap
STORE_END            equ RAM_VARS+0x0a6
EFFECT_ID            equ RAM_VARS+0x0a8   ; 0 LEFT, 1 PAUSE, 2 UP, 3 DOWN, 4 RIGHT, 5 HOLD
EFFECT_VECTOR        equ RAM_VARS+0x0a9
CHAN_HINT            equ RAM_VARS+0x0ab   ; P39: the marker chan_select found last (was MENU_TEXT_PTR)
SHIFT_LABEL          equ RAM_VARS+0x0ad   ; FF = redraw shows the SHIFT indicator
ROW_INDEX            equ RAM_VARS+0x0ae
RX_BITS              equ RAM_VARS+0x0af   ; P30: data bits still to sample (was RX_BITMASK)
RX_SHIFT             equ RAM_VARS+0x0b0
RX_ACC               equ RAM_VARS+0x0b1   ; P30: fifths of an interrupt to the next sample (was RX_TICKS)
RX_FIFO              equ RAM_VARS+0x0b2
RX_COUNT             equ RAM_VARS+0x0ba
RX_WIDTH             equ RAM_VARS+0x0bb   ; P30: interrupts the start pulse has lasted while it sets the rate
REDRAW_PTR           equ RAM_VARS+0x0bc   ; editor redraw: byte being rendered
RX_PHASE             equ RAM_VARS+0x0be   ; P30: 0 idle, 1 timing the start pulse, 2 sampling bits (was the RX_STATE vector)
TICK6_CAL            equ RAM_VARS+0x0bf   ; P30: low byte of the tick6 runs this second, read and zeroed by baud_calibrate
CHAN_LOCK            equ RAM_VARS+0x0c0
SEQ_PTR              equ RAM_VARS+0x0c1
SEQ_ALL_EMPTY        equ RAM_VARS+0x0c3   ; 10 = every listed channel is empty, play the demo
SEQ_MENU_ACTIVE      equ RAM_VARS+0x0c4   ; FF while the SEQ MSG? dialogue runs
SHIFT_STATE          equ RAM_VARS+0x0c5   ; SHIFT latch, toggled by key 29 (see section 9)
PREV_SPACE           equ RAM_VARS+0x0c6   ; 1 = previous char was a space (two in a row reset the background)
NMI_COUNT            equ RAM_VARS+0x0c7   ; two bytes: magic_short_word reads through it as a pointer, so the 04 high byte is a ROM page
STORE_TMP            equ RAM_VARS+0x0c8
REDRAW_FROM          equ RAM_VARS+0x0ca   ; editor redraw: first byte actually displayed (cursor-21, >= INS_PTR)
TX_BITIDX            equ RAM_VARS+0x0cc
TX_PENDING           equ RAM_VARS+0x0cd
TX_ACC               equ RAM_VARS+0x0ce   ; P30: fifths of an interrupt to the next edge (was TX_TICKS)
TX_SHIFT             equ RAM_VARS+0x0cf
TX_STATUS            equ RAM_VARS+0x0d0
SEQ_SET              equ RAM_VARS+0x0d1   ; FF = sequence set by hand; do not auto-add the edited channel
NMI_PER_SEC          equ RAM_VARS+0x0d2
CLK_RENDERED         equ RAM_VARS+0x0d3   ; FF just after a clock display; forces LEFT in an effect
MAGIC_COLOR_IDX      equ RAM_VARS+0x0d4   ; index into MAGIC_COLOR_CYCLE
EURO_STATE           equ RAM_VARS+0x0d5
IR_DEBOUNCE          equ RAM_VARS+0x0d6   ; key number seen once, awaiting its second frame
TICK6_COUNT          equ RAM_VARS+0x0d7
GEN_COUNTDOWN        equ RAM_VARS+0x0d8   ; IR repeat/hold timer, counts down in tick6 (word)
IR_STATE_CNT         equ RAM_VARS+0x0da
IR_BITCNT            equ RAM_VARS+0x0db
IR_KEY               equ RAM_VARS+0x0dc   ; last accepted key number
IR_SHIFT             equ RAM_VARS+0x0dd
IR_CODE              equ RAM_VARS+0x0de
IR_KEYNUM            equ RAM_VARS+0x0df   ; IR_CODE & 3F = key number 0..63
TICK_VECTOR          equ RAM_VARS+0x0e0
NEW_MSG_CHAN         equ RAM_VARS+0x0e2   ; channel chosen for a new MAGIC message
MAGIC_FX_PREV        equ RAM_VARS+0x0e3   ; FF = last byte was a movement attribute (magic mode)
MAGIC_FLASH_WORD     equ RAM_VARS+0x0e4   ; '$' = flash the word that starts with $ (magic mode)
EDITOR_FIRST_KEY     equ RAM_VARS+0x0e5   ; FF until the first key in the editor is processed
MAGIC_WORD_COUNT     equ RAM_VARS+0x0e6   ; words since the last color change (magic mode)
RND_SEED             equ RAM_VARS+0x0e7
MAGIC_MSG_CHAN       equ RAM_VARS+0x0e8   ; channel to announce as MAGIC MSG nn on redraw (0 = none)
CHAN_D10             equ RAM_VARS+0x0e9
CHAN_D1              equ RAM_VARS+0x0ea
MENU_ENTRY_BUF       equ RAM_VARS+0x0eb
FUNC_PENDING         equ RAM_VARS+0x0f0   ; editor: FUNC (B7) pressed, next key picks the second function
LIT_COUNT            equ RAM_VARS+0x0f1   ; P35: interrupts the lit row has left
LIT_LIMIT            equ RAM_VARS+0x0f2   ; P35: the row's share of interrupts; 0 = full brightness or parked
LATCH_PENDING        equ RAM_VARS+0x0f3   ; P35: row select code the ISR latches on its next interrupt; 0 = none
DISP_ACC             equ RAM_VARS+0x0f4   ; P26: sevenths of an interrupt carried to the next display tick (was BLANK_TIMER)
SPEED_PENDING        equ RAM_VARS+0x0f5   ; editor: SPEED key pressed, next key is the digit
KEY_ECHO_TX          equ RAM_VARS+0x0f6   ; non-zero = echo accepted keys on serial TX
BOOT_ZERO_LEN        equ 136
; ---- scratch, never initialized
GLYPH_BUF            equ RAM_VARS+0x0f7   ; working copy of the glyph (bold/plain), 32 bytes
GLYPH_BUF_ITALIC     equ RAM_VARS+0x117   ; sheared copy for ITALIC, 32 bytes
GLYPH_BUF_BIG        equ RAM_VARS+0x137   ; widened copy for BIG, 32 bytes
TEST_MSG_BUF         equ RAM_VARS+0x157   ; the message shown in TEST_MODE, 28 bytes (stock: the test pattern plus the ROM checksum)
DRAW_BUF             equ RAM_VARS+0x173   ; 16 packed hex columns of a DRAW graphic
; ---- SEQ_LIST survives a reset: it must stay above the stub's library copy (RAM_VARS+00..81)
SEQ_LIST             equ RAM_VARS+0x183
; RAM_VARS+0x1eb .. 0x1f2: 8 bytes free
; P20: the clock digits must survive a power cycle, so they live up here next
; to the store, out of reach of the stub's library copy (RAM_VARS+00..81).
CLK_H10              equ RAM_VARS+0x1f3
CLK_H1               equ RAM_VARS+0x1f4
CLK_M10              equ RAM_VARS+0x1f5
CLK_M1               equ RAM_VARS+0x1f6
CLK_SEC              equ RAM_VARS+0x1f7
CLK_PM               equ RAM_VARS+0x1f8
BOOT_COUNT           equ RAM_VARS+0x1f9   ; boots since RAM was last fresh
STORE_LIMIT          equ RAM_VARS+0x1fa
STORE_SIZE           equ RAM_VARS+0x1fc
STORE_TEXT_LIMIT     equ RAM_VARS+0x1fe   ; free text bytes; scan bound for store_repair
STORE_WARN_LIMIT     equ RAM_VARS+0x200   ; STORE_END here trips the 100 KEYS LEFT warning
; P35: the configuration block. Battery-backed like the clock; its signature
; and sum are the RAM-validity test (was MY_ADDRESS against its complement).
CFG                  equ RAM_VARS+0x202
CFG_SIG              equ CFG+0            ; CFG_MAGIC while the block is valid
MY_ADDRESS           equ CFG+1            ; written only by the editor's ADDRESS? dialog
CFG_FLAGS            equ CFG+2            ; bits 0-1 brightness, 2 muted, 3 mute pending, 4 alert, 5 editor, 6 wrapped
CFG_PIN2_ROLE        equ CFG+3            ; P36: 0 none, 1 alert, 2 chain input
CFG_PIN6_ROLE        equ CFG+4            ; P36: 0 none, 1 mute
CFG_PIN4_ROLE        equ CFG+5            ; P36: 0 none, 1 boundary
CFG_PIN7_ROLE        equ CFG+6            ; P36: 0 none, 1 heartbeat, 2 busy
CFG_ALERT_CHAN       equ CFG+7            ; P36: the channel the alert line plays
CFG_HOLD             equ CFG+8            ; frames a PAUSE, HOLD, wipe or clock holds the panel
CFG_FLASH            equ CFG+9            ; frames per half period of the FLASH blink
CFG_BEEP             equ CFG+10           ; 0: the beeper stays silent
CFG_LOCK             equ CFG+11           ; non-zero: remote keys are ignored
CFG_STATUS           equ CFG+12           ; P41: non-zero: a status report at each channel start and editor entry
CFG_CLKSRC           equ CFG+13           ; reserved: clock source override
CFG_SUM              equ CFG+15           ; 8-bit sum of the 15 bytes before it
CFG_LEN              equ 16
CFG_MAGIC            equ 0xa5
STORE_GUARD          equ CFG+CFG_LEN      ; store_repair writes a space at MSG_STORE-1 every boot
MSG_STORE            equ STORE_GUARD+1
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
FLASH_HALF_PERIOD    equ 13          ; P35: the default of CFG_FLASH
    IFDEF CC710
FRAME_COLS           equ 60          ; columns sent per row: the CC710 panel's 59 plus one that falls off the chain
    ELSE
FRAME_COLS           equ 86          ; columns sent per row: the panel's 84 plus two that fall off the chain
    ENDIF
HOLD_FRAMES          equ 80          ; frames a PAUSE, HOLD, wipe or clock holds the panel (~1.3 s); P35: the default of CFG_HOLD
BEEP_LEN             equ 150         ; beeper on for this many tick6 periods (~115 ms)
IR_REPEAT_DELAY      equ 1300        ; tick6 periods a held remote key waits before repeating (~1 s)
IR_REPEAT_TICKS      equ 300         ; ... and between repeats (~0.23 s)

; ---- Message store format ------------------------------------------------------
MARK_LO              equ 0xd0        ; channel markers are two bytes D0+tens, D0+units
MARK_HI              equ 0xda        ; the last marker byte value; alone, DA ends the store
TEXT_END             equ 0x03        ; ends a channel's text
CHANNELS             equ 100         ; message channels 0-99
CHAN_DEMO            equ 100         ; the pseudo-channel that plays DEMO_MESSAGE
SEQ_LIST_LEN         equ 104         ; SEQ_LIST: up to 100 entries plus FF terminators

; ---- Message attribute bytes (the sign's own names, CC784_firmware.md §8) --------
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
KEY_DEL              equ 0x7f
; P30: serial timing. An interrupt is 128 us plus the acknowledge latency, about
; 130 us; the 300-baud bit is 25.6 of them, kept in fifths as BAUD_T, and the
; faster rates step the same accumulator 10 or 20 fifths per interrupt. 2400
; is not offered: sampled once per interrupt, its bits are read within a third
; of a bit of their middles and long frames fail on the board.
; baud_calibrate sets BAUD_T from the tick6 count per NMI second (1280 + s ticks
; -> (1280 + s) / 10); until then, or on a DC supply, it is the default.
BAUD_T_DEFAULT       equ 128
BAUD_STEP_300        equ 5
BAUD_STEP_600        equ 10
BAUD_STEP_1200       equ 20
BAUD_CAL_LIMIT       equ 60          ; |s| beyond this (4.7 %) is a partial second or a stall: ignored
; P31: the NMI is the mains zero-cross on AC, or the add-in board's HC4060 Q9
; when BANK_REG bit 7 selects it through the board's '151 (CC784_hardware.md)
NMI_PER_SEC_MAINS    equ 60
NMI_PER_SEC_XTAL     equ 64
BANK_CLOCK_XTAL      equ 0x80        ; BANK_REG bit 7, its top bit; bits 0-2 are kept for a larger EEPROM's A14-A16
CLK_24H              equ 0x02        ; P32: CLK_PM bit 1 = 24-hour clock; bit 0 = PM
BAUD_IDLE_FRAMES     equ 62          ; display frames, about a second
IR_CODE_STOP         equ 0xa4        ; 0x80 | remote key 36, STOP/START
IR_CODE_SPACE        equ 0xa5        ; 0x80 | remote key 37, SPACE
ATTR_DRAW            equ 0xb8
ATTR_THIN            equ 0xb9
ATTR_WAIT            equ 0xba
ATTR_HOLD            equ 0xbb
ATTR_RAINBOW         equ 0xbc
ATTR_MAGIC_OFF       equ 0xbd
ATTR_TINY            equ 0xbe
COLOR_BASE           equ 0x80        ; 80-8F foreground: bits 0-1 green, 2-3 red intensity
COLOR_DEFAULT        equ 0x8f        ; yellow, full
COLOR_FLASH          equ 0x10        ; the FLASH bit in a frame-buffer color byte
BGRND_BASE           equ 0x90        ; 90-93 background
GRAPH_BASE           equ 0xa0        ; A0-AF built-in graphics
SPEED_BASE           equ 0xf0        ; F0-F7 scroll speed
LATCH_TX             equ 0x10        ; CTRL_LATCH bit 4: serial TX
IR_BIT               equ 4           ; P36: PORT_IN bit of the IR receiver, on a '244 piggybacked on U12; bit 1 is the keypad's
PORT_IR              equ 1<<IR_BIT
LATCH_BLINK          equ 0x80        ; CTRL_LATCH bit 7: the FLASH blink clock
STACK_SIZE           equ 160         ; P35: a boot-time canary measured 130 bytes at most (a 57-channel store fill); 128 overran into the TX segments
STACK_CANARY         equ 128         ; bytes of 0x55 laid at the stack's bottom at boot; the stats query counts those left
STALL_FRAMES         equ 3           ; frames without a pkt_poll that count as a renderer stall
CRAWL_LEAD           equ 8           ; P42: columns the plain crawl keeps in hand (~130 ms at full speed)
; P21: packet processing runs in the render loop and replies go out in the
; background, so their state cannot share renderer scratch. 32 bytes below the
; stack, carved off the store.
STREAM_AREA          equ STACK_TOP-STACK_SIZE-STREAM_AREA_SIZE
TX_SEG0              equ STREAM_AREA+0     ; segment being sent: ptr, count, flags (bit 0 = append the sum)
TX_SEG1              equ STREAM_AREA+5     ; next segment, same layout
TX_SUM               equ STREAM_AREA+10    ; running 8-bit sum of TX_SEG0's bytes
TX_DONE_PENDING      equ STREAM_AREA+11    ; a byte to send once the segments are out: DONE_BYTE, or a deferred ACK/NAK (P41); 0 = none
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
PKT_SAVE_LOCK        equ STREAM_AREA+27    ; P27: the renderer's CHAN_LOCK at entry
PKT_SEQ_CHANGED      equ STREAM_AREA+28    ; P27: FF once the packet has rewritten SEQ_LIST
DISP_STRETCH         equ STREAM_AREA+29    ; P26: sevenths of an interrupt added to every display tick: 2 x speed
SVC_DUE              equ STREAM_AREA+30    ; P26: bit 0 = tick6 engines due, bit 1 = display tick due
SVC_ACTIVE           equ STREAM_AREA+31    ; P26: FF while tick6_service runs; it drains SVC_DUE, so it never nests
PORT_SAMPLE          equ STREAM_AREA+32    ; P35: PORT_IN as the ISR read it this interrupt
IR_QUIET             equ STREAM_AREA+33    ; P35: 1 = the IR decoder waits for the line to rise, PORT_IR|1 = to fall: its handler is skipped meanwhile
KP_MODE              equ STREAM_AREA+34    ; P36: 0 = serial, else the wired keypad is scanned
KP_SPACE             equ STREAM_AREA+35    ; P36: frames in a row the RX line read space (serial mode)
KP_HELD              equ STREAM_AREA+36    ; P36: empty scans left before a key's release is reported
STAT_MERGE           equ STREAM_AREA+37    ; display ticks merged this second (a tick marked while still due)
STATS                equ STREAM_AREA+38    ; the stats query copies STATS_LEN bytes from here
STAT_MERGE_LAST      equ STREAM_AREA+38    ; ... last second
STAT_MERGE_MAX       equ STREAM_AREA+39    ; ... worst second since boot
STAT_UPTIME          equ STREAM_AREA+40    ; seconds since boot, 3 bytes
STAT_STALLS          equ STREAM_AREA+43    ; times the renderer went STALL_FRAMES frames without polling
STAT_STALL_MAX       equ STREAM_AREA+44    ; longest such gap in frames
STAT_PKT_OK          equ STREAM_AREA+45    ; frames with a good checksum (own address or broadcast)
STAT_PKT_BAD         equ STREAM_AREA+46    ; ... with a bad one
STAT_IR_OK           equ STREAM_AREA+47    ; remote frames decoded
STAT_IR_BAD          equ STREAM_AREA+48    ; remote frames dropped after the leader
STATS_LEN            equ 11
POLL_AGE             equ STREAM_AREA+49    ; frames since pkt_poll last ran
STATUS_BUF           equ STREAM_AREA+50    ; P41: the status report being sent, B1 addr 03 'S' channel flags
STREAM_AREA_SIZE     equ 56
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
CMD_COLOR_A0         equ 0x1e        ; 1E n
CMD_APPEND           equ 0xb3
CMD_QUERY            equ 0xb4        ; B4 c
QUERY_ROMID          equ '0'
QUERY_MEMORY         equ '1'
QUERY_NOP            equ '2'
QUERY_DUMP           equ '3'
QUERY_STATS          equ '4'         ; P30: BAUD_T, BAUD_STEP, BAUD_CAL_LAST, NMI_SEEN; P40: then the health counters
QUERY_CONFIG         equ '5'         ; P35: the 16-byte configuration block
QUERY_SEQ            equ '6'         ; P35: SEQ_LIST, 104 bytes
CMD_OTA              equ 0xb5        ; B5 c ... (patch 11)
CMD_CONFIG           equ 0xb6        ; B6 index value (patch 35)
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

; ---- DKEY: one entry of a dispatch table (see dispatch)
        MACRO DKEY zk, zt
        db zk
        dw zt
        ENDM

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
        CP IR_CODE_SPACE
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
        ASSERT STUB_RAM+STUB_LIB_SIZE <= SEQ_LIST

        ds STUB_END-$,0xff

; ============================================================================
;  APPLICATION. The stub enters through this jump table and nowhere else.
; ============================================================================
        JP app_start            ; three-byte entries: the stub uses STUB_END+3 and +6
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
nmi_entry:                      ; clock_tick and baud_calibrate use A, BC and HL
        PUSH AF
        PUSH BC
        PUSH HL
        CALL clock_tick
        POP HL
        POP BC
        POP AF
        RETN

; ---- int_timer: Timer ISR. Every 6th tick schedules tick6_service; every tick schedules the handler in TICK_VECTOR (IR decoder). Both are invoked by pushing their address so they run as the ISR returns.
;      P26: the display has its own divider. A display tick is 6 interrupts plus
;      DISP_STRETCH sevenths, carried in DISP_ACC, so the plain crawl's slower
;      speeds come from longer rows rather than dark ticks. Both dividers only
;      mark SVC_DUE; tick6_service is pushed when it is not already running and
;      drains the marks itself, so the engines and the display never nest and
;      share the latch shadow and the RX FIFO as they did on one divider.
int_timer:
        EX AF,AF'
        EXX
        IN A,(PORT_IN)          ; P35: one sample for the IR gate at the end
        LD (PORT_SAMPLE),A
        LD A,(RX_PHASE)         ; P30: the serial bit engines, every interrupt,
        AND A                   ; so 1200 baud fits; idle they cost a line poll
        JR nz,int_rx_active
        IN A,(PORT_IN)
        BIT 3,A
        CALL nz,rx_start
        JR int_tx

int_rx_active:
        CALL rx_phase_run

int_tx:
        LD A,(TX_STATUS)
        AND 3
        CALL nz,tx_isr
        LD A,(LIT_LIMIT)        ; P35: brightness by lit time (see latch_row_dim):
        AND A                   ; 0 at full brightness, the cheap way out
        JR z,int_lit_on
        LD A,(LATCH_PENDING)    ; a row waiting to be lit: lit here, on the
        AND A                   ; interrupt grid, so the count is exact
        JR z,int_lit_count
        LD C,A
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x70
        OR C
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,(LIT_LIMIT)        ; lit: the row's share, counted down below
        LD (LIT_COUNT),A
        XOR A
        LD (LATCH_PENDING),A
        JR int_lit_on

int_lit_count:
        LD HL,LIT_COUNT         ; park the rows once it has had its share
        DEC (HL)
        JR nz,int_lit_on
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        XOR A                   ; parked: nothing more to do until the next row arms it
        LD (LIT_LIMIT),A

int_lit_on:
        LD HL,DISP_COUNT
        DEC (HL)
        JR nz,int_tick6
        LD A,(DISP_STRETCH)
        LD C,A
        LD A,(DISP_ACC)
        ADD A,C
        LD B,6

int_disp_carry:
        CP 7
        JR c,int_disp_reload
        SUB 7
        INC B
        JR int_disp_carry

int_disp_reload:
        LD (DISP_ACC),A
        LD (HL),B
        LD HL,SVC_DUE
        BIT 1,(HL)              ; P40: the last tick still due: this one merges with it
        JR z,int_disp_mark
        LD A,(STAT_MERGE)
        INC A
        LD (STAT_MERGE),A

int_disp_mark:
        SET 1,(HL)

int_tick6:
        LD A,(TICK6_COUNT)
        INC A
        CP 6
        JR nz,int_tick6_store
        LD HL,TICK6_CAL         ; P35: counted here, where the mark is made, so a late
        INC (HL)                ; service cannot shrink the calibration's second
        LD HL,SVC_DUE
        SET 0,(HL)
        XOR A

int_tick6_store:
        LD (TICK6_COUNT),A
        LD A,(SVC_DUE)
        OR A
        JR z,int_vector
        LD HL,SVC_ACTIVE
        OR (HL)
        JP m,int_vector         ; the running service picks the new mark up
        LD (HL),0xff
        LD HL,tick6_service     ; the address is pushed so the service runs as the ISR returns
        PUSH HL

int_vector:
        LD A,(IR_QUIET)         ; P35: the decoder waiting on the line has nothing to
        AND A                   ; do until it moves: its handler, ~90 cycles an interrupt
        JR z,int_vector_push    ; (a reset every interrupt on a sign with no receiver), is skipped
        LD C,A
        LD A,(PORT_SAMPLE)
        AND PORT_IR
        OR 1
        CP C
        JR z,int_vector_done
        XOR A
        LD (IR_QUIET),A

int_vector_push:
        LD HL,(TICK_VECTOR)
        PUSH HL

int_vector_done:
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
        CALL crawl_step
        ; LD A,(nn) sets no flags, so this JR tests effect_step's exit flags,
        ; not MAGIC_MODE. A is loaded for whatever runs after the branch.
        LD A,(MAGIC_MODE)
        JR nz,render_loop
        CALL effect_none
        LD (COL_COUNT),A
        JR render_loop

; ---- pkt_poll (P21): process a pending packet here, between two render
;      steps. pkt_process returns unless the display has to restart.
pkt_poll:
        XOR A                   ; P40: the renderer is alive (A and the flags are reloaded next)
        LD (POLL_AGE),A
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
tick6_service:                  ; nothing it runs touches IX or IY
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL

svc_loop:
        LD HL,SVC_DUE           ; P26: the engines on the tick6 mark, the display on its own
        BIT 0,(HL)
        JR z,svc_display
        RES 0,(HL)
        LD HL,(GEN_COUNTDOWN)
        DEC HL
        LD A,H
        AND L
        CP 0xff
        JR z,tick6_engines
        LD (GEN_COUNTDOWN),HL

tick6_engines:
        LD A,(TX_STATUS)        ; P30: the bit engines run in the ISR; a reply
        AND 3                   ; handed over while the line is idle starts here
        JR nz,tick6_beep
        LD A,(TX_ACTIVE)
        OR A
        JR z,tick6_beep
        DI
        CALL tx_stream_next
        EI

tick6_beep:
        LD HL,(BEEP_TICKS)
        LD A,H
        OR L
        JR z,svc_display
        DEC HL
        LD (BEEP_TICKS),HL

svc_display:
        LD HL,SVC_DUE
        BIT 1,(HL)
        JP z,tick6_restore
        RES 1,(HL)

; ---- tick6_display: one display tick: a row pass, or the row advance with the
;      frame end and the RX byte consumer; every exit leads to tick6_restore
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
        ; P26: no blanked ticks; the scroll speed stretches the display tick
        ; instead (DISP_STRETCH, set at the end of the frame)

row_output:
        LD A,(ROW_OUT_PENDING)
        AND A
        JP z,row_advance
        CALL latch_blank
        LD A,(DISP_ON)
        AND A
        JP z,row_phase_step
        LD A,(CFG_FLAGS)        ; P35: muted or brightness 0: the row stays dark
        AND 7
        CP 4
        JR nc,row_phase_step
        AND A
        JR z,row_phase_step
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
        LD DE,(BEEP_TICKS)
        LD A,D
        OR E
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
        DI                      ; P30: the ISR's transmitter owns latch bit 4
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x70
        OR 15
        LD (CTRL_LATCH),A
        EI
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
        CALL latch_row_dim      ; P35: lit now at full brightness, else by the ISR

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
        CALL row_step
        JP c,tick6_arm_row
        LD (DISP_STRETCH),A     ; P26: full rate unless the plain crawl below asks
        LD HL,RX_IDLE           ; P30: frames since the last start bit, held at 255
        INC (HL)
        JR nz,frame_idle_held
        DEC (HL)

frame_idle_held:
        LD A,(MENU_ACTIVE)      ; P40: renderer stalls; the editor does not poll
        AND A
        JR nz,frame_poll_done
        LD HL,POLL_AGE
        INC (HL)
        JR nz,frame_poll_age
        DEC (HL)

frame_poll_age:
        LD A,(HL)
        CP STALL_FRAMES
        JR nz,frame_poll_max
        LD HL,STAT_STALLS
        INC (HL)

frame_poll_max:
        LD HL,STAT_STALL_MAX
        CP (HL)
        JR c,frame_poll_done
        LD (HL),A

frame_poll_done:
        CALL clock_bank         ; P31: the OTA library may have dropped the clock bit
        LD A,(FRAME_DELAY)
        AND A
        JR z,frame_speed
        DEC A
        LD (FRAME_DELAY),A
        JP frame_bit7_tick

; ---- frame_speed (P26): where stock queued SCROLL_SPEED dark ticks after the
;      frame, the next frame's 21 display ticks are stretched by the same total
;      (2 x speed sevenths each), so the rows stay lit and evenly so.
;      Effects, the editor and TINY run at the full rate, as before.
frame_speed:
        LD A,(MENU_ACTIVE)
        LD HL,EFFECT_ID
        OR (HL)
        LD HL,TINY_RENDER
        OR (HL)
        JR nz,frame_scroll
        LD A,(SCROLL_SPEED)
        ADD A,A
        LD (DISP_STRETCH),A
        LD HL,DISP_ACC          ; 21 ticks is a multiple of 7: rotate the carry
        INC (HL)                ; pattern a seventh per frame so every row averages the same

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
        JR frame_color

frame_check_still:
        LD HL,(FB_OUT_PTR)
        LD DE,(FB_COL)
        OR A
        SBC HL,DE
        JR z,frame_bit7_tick

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
        LD HL,FRAMEBUF_END      ; the window runs to the ring's end, then wraps
        LD BC,(FB_COL)
        LD DE,FRAME_COLS
        XOR A
        SBC HL,BC
        XOR A
        LD (FB_OUT_LEN),HL
        EX DE,HL
        SBC HL,DE
        JR z,frame_window_wrap
        JR nc,frame_set_extra

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
        LD HL,CFG_FLASH         ; P35
        CP (HL)
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
; ---- kp_poll (P36): the wired keypad. Serial until the RX line has read space
;      (a keypad's idle, or nothing plugged in) for 256 frames; keypad until all
;      eight rows read a key, which is a host's TX idling at mark. A key is
;      handed to the remote's consumers as its remote code, so the editor,
;      debounce, repeat and STOP/START treat both alike.
        LD HL,KP_MODE
        LD A,(HL)
        AND A
        JR nz,kp_scan
        INC HL
        IN A,(PORT_IN)
        AND 8
        JR nz,kp_space
        LD (HL),A
        JR rx_consume

kp_space:
        INC (HL)
        JR nz,rx_consume
        DEC HL
        INC (HL)
        JR rx_consume

kp_scan:
        LD BC,0x0800            ; B rows to go, C rows that read a key
        LD D,C                  ; row x 8

kp_row:
        DI                      ; the rows are latch bits 4-6, which the ISR rewrites;
        LD A,(CTRL_LATCH_SHADOW) ; a row at a time, so the IR decoder's ticks stay on time
        AND 0x8f
        LD E,A
        LD A,D
        ADD A,A
        OR E
        LD (CTRL_LATCH),A
        IN A,(PORT_IN)
        EI
        BIT 3,A
        JR nz,kp_next
        INC C
        AND 7
        OR D
        LD L,A                  ; key code: row x 8 + column

kp_next:
        LD A,D
        ADD A,8
        LD D,A
        DJNZ kp_row
        DI
        LD A,(CTRL_LATCH_SHADOW)
        LD (CTRL_LATCH),A
        EI
        LD A,C
        CP B                    ; B is 0
        JR z,kp_none
        CP 8
        JR nz,kp_key
        XOR A
        LD (KP_MODE),A
        JR rx_consume

kp_key:
        LD A,L
        CP 0x1e                 ; K has two positions; the remote's table holds 00
        JR nz,kp_lookup
        XOR A

kp_lookup:
        LD HL,IR_KEY_TABLE
        LD BC,62
        CPIR
        JR nz,kp_none           ; 1F: an empty position
        LD A,0x80+61
        SUB C
        LD (IR_CODE),A
        LD A,2                  ; release after two empty scans: no contact bounce
        LD (KP_HELD),A
        JR rx_consume

kp_none:
        LD HL,KP_HELD
        LD A,(HL)
        AND A
        JR z,rx_consume
        DEC (HL)
        JR nz,rx_consume
        LD A,0x80+0x3e          ; the remote's release code
        LD (IR_CODE),A

; ---- rx_consume: Pop a byte from RX_FIFO; in normal mode feed the packet parser (or if IR_CODE=A4/A5 handle keypad); packet start needs 0xB1 while idle
;      P30: runs once per display frame, so it drains the FIFO rather than taking
;      one byte: 62 bytes a second was enough for 300 baud only
rx_consume:
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,tick6_exit
        CALL rx_fifo_get
        JR nc,rx_have_byte
        LD A,(IR_CODE)
        CP IR_CODE_STOP
        JR z,rx_ir_stop_key
        CP IR_CODE_SPACE
        JR nz,tick6_exit
        LD A,' '
        LD (RX_BYTE),A
        JR tick6_exit

rx_ir_stop_key:
        LD (IR_KEY),A

key_handler_jr1:
        LD A,(TEST_MODE)        ; P43: no editor while an update is under way:
        INC A                   ; the remote, the keypad and a serial 01 all end here
        JP nz,key_handler
        LD (IR_CODE),A          ; the key is used up
        LD (RX_BYTE),A
        JR tick6_exit

rx_have_byte:
        LD A,(PKT_STATE)
        AND A
        JR z,rx_idle_byte
        CALL pkt_feed_byte
        XOR A                   ; B12: a payload byte is not a key; a 0x20 left
        LD (RX_BYTE),A          ; here would release a WAIT (wait_poll)
        JR rx_consume

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
        JR nz,rx_consume
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
        JR rx_consume

rx_not_start:
        LD A,(RX_BYTE)
        CP 1
        JR z,key_handler_jr1
        JR rx_consume

; ---- tick6_exit
tick6_exit:
tick6_arm_row:
        LD A,0xff
        LD (ROW_OUT_PENDING),A
        LD A,0x40
        LD (ROW_PORT),A

tick6_restore:
        DI                      ; P26: a mark set after this check would be lost
        LD A,(SVC_DUE)
        OR A
        JR nz,svc_again
        LD (SVC_ACTIVE),A
        EI
        POP HL
        POP DE
        POP BC
        POP AF
        RET

svc_again:
        EI
        JP svc_loop

; ---- init_sequence: validate SEQ_LIST (reset to 0..99 if not), then flag
;      SEQ_ALL_EMPTY when no listed channel has text
init_sequence:
        XOR A
        LD (SEQ_ALL_EMPTY),A
        LD B,SEQ_LIST_LEN
        LD HL,SEQ_LIST
        LD A,(HL)
        CP 0xff
        JR z,seq_reset_default

seq_scan:
        CP CHAN_DEMO+1
        JR nc,seq_scan_end
        INC HL
        LD A,(HL)
        DJNZ seq_scan
        DEC HL
        LD (HL),0xff
        JR seq_check_first

seq_scan_end:
        CP 0xff
        JR z,seq_check_first

seq_reset_default:
        CALL seq_list_default

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
        JR seq_check_loop

seq_all_empty:
        POP HL
        LD A,10
        LD (SEQ_ALL_EMPTY),A
        RET

; ---- seq_list_default: SEQ_LIST = channels 0..99, then four FF
seq_list_default:
        LD HL,SEQ_LIST
        XOR A
        LD B,CHANNELS

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
        RET

; ---- seq_list_one: SEQ_LIST = A, then FF to the end (A kept)
seq_list_one:
        LD HL,SEQ_LIST
        LD (HL),A
        LD B,SEQ_LIST_LEN-1

seq_one_loop:
        INC HL
        LD (HL),0xff
        DJNZ seq_one_loop
        RET

; ---- seq_next_channel: pick the channel to display next: NEXT_CHAN once, else the
;      next SEQ_LIST entry (demo 100 when SEQ_ALL_EMPTY); seat STORE_CURSOR on its
;      first printable byte, or on TEST_MSG_BUF in TEST_MODE
seq_next_channel:
        CALL chan_boundary      ; P35: once per message; the retries below skip it

seq_pick:
        LD A,(TEST_MODE)
        INC A
        JP z,seq_test_message
        LD A,(NEXT_CHAN)
        CP CHAN_DEMO
        JR nc,seq_from_list
        LD E,A
        LD A,0xff
        LD (NEXT_CHAN),A
        LD A,E
        JR seq_open_channel

seq_from_list:
        LD A,(SEQ_ALL_EMPTY)
        LD E,A
        CP 10
        LD A,CHAN_DEMO
        JR z,seq_open_channel
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JR nz,seq_clamp_entry
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        LD HL,CFG_FLAGS         ; P35: the sequence starts over
        SET 6,(HL)
        JR seq_pick

seq_clamp_entry:
        CP CHAN_DEMO+1
        JR c,seq_advance
        LD A,CHAN_DEMO
        LD (HL),CHAN_DEMO

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
        CALL char_flags
        JR z,seq_set_cursor

seq_skip_attrs:
        INC HL
        LD A,(HL)
        CP TEXT_END
        JR nz,seq_skip_attrs_next
        POP HL
        JR seq_chan_empty

seq_skip_attrs_next:
        CALL char_flags
        JR nz,seq_skip_attrs

seq_set_cursor:
        POP HL
        LD (STORE_CURSOR),HL
        CALL status_send        ; P41: E = the channel starting
        JR chan_lock_set

seq_ret:                        ; the emulator's seq gate watches cursor writes from seq_set_cursor to here
seq_chan_empty:
        CALL pkt_poll           ; P40: 99 empty channels take ~50 ms; keep packets moving
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JR nz,seq_pick
        DEC HL
        LD DE,SEQ_LIST
        OR A
        SBC HL,DE
        JP nz,seq_pick
        LD A,CHAN_DEMO
        JR seq_open_channel

seq_test_message:
        LD HL,TEST_MSG_BUF
        LD (STORE_CURSOR),HL    ; falls into clear_chan_lock

; ---- clear_chan_lock
clear_chan_lock:
        XOR A
        LD (CHAN_LOCK),A
        RET

; ---- chan_lock_set: the lock is on for the demo channel (E) and off for any other
chan_lock_set:
        LD A,E
        CP CHAN_DEMO
        JR z,chan_lock_store
        XOR A

chan_lock_store:
        LD (CHAN_LOCK),A
        RET

; ---- chan_open: select channel E for editing: INS_PTR after its marker, the
;      cursor on the marker, the lock as the channel wants it
chan_open:
        PUSH DE
        CALL chan_select
        POP DE
        OR A
        JP nz,pkt_process_end
        LD (INS_PTR),HL
        DEC HL
        DEC HL
        LD (STORE_CURSOR),HL
        JR chan_lock_set

; ---- status_send (P41): with reports on and the line quiet, hand the transmitter
;      B1 addr 03 'S' E flags sum. Dropped while a reply streams or a frame is arriving.
status_send:
        LD A,(CFG_STATUS)
        AND A
        RET z
        LD A,(TX_ACTIVE)
        LD HL,RX_PHASE
        OR (HL)
        LD HL,PKT_STATE
        OR (HL)
        RET nz
        LD HL,STATUS_BUF
        LD (TX_SEG0),HL
        LD (HL),FRAME_START
        INC HL
        LD A,(MY_ADDRESS)
        LD (HL),A
        INC HL
        LD (HL),3
        INC HL
        LD (TX_SEG1),HL
        LD (HL),'S'
        INC HL
        LD (HL),E
        INC HL
        LD A,(CFG_FLAGS)
        LD (HL),A
        LD HL,3
        LD (TX_SEG0+2),HL
        LD (TX_SEG1+2),HL
        LD A,1
        LD (TX_SEG1+4),A
        XOR A
        LD (TX_SEG0+4),A
        LD (TX_SUM),A
        DEC A
        LD (TX_ACTIVE),A
        RET

; ---- chan_select: Select channel E: find/create its slot in MSG_STORE, set INS_PTR/STORE_CURSOR
chan_select:
        CP CHAN_DEMO
        JR nz,chan_marker
        LD HL,DEMO_MESSAGE
        JR chan_ok

chan_marker:
        CP CHANNELS             ; P39: D = tens, E = units by dividing, not counting up
        JR nc,chan_error
        LD D,MARK_LO-1

chan_marker_tens:
        INC D
        SUB 10
        JR nc,chan_marker_tens
        ADD A,MARK_LO+10
        LD E,A

chan_scan:
        ; P39: markers are stored in channel order, so a channel at or above the one at
        ; CHAN_HINT is scanned for from there. Two marker bytes in a row are always one marker.
        LD BC,(CHAN_HINT)
        LD HL,(STORE_END)       ; a store that shrank leaves stale markers past its DA
        OR A
        SBC HL,BC
        JR c,chan_scan_full
        LD A,(BC)
        LD H,A
        SUB MARK_LO
        CP 10
        JR nc,chan_scan_full
        INC BC
        LD A,(BC)
        DEC BC
        LD L,A
        SUB MARK_LO
        CP 10
        JR nc,chan_scan_full
        OR A
        SBC HL,DE
        JR z,chan_scan_go
        JR c,chan_scan_go

chan_scan_full:
        LD BC,MSG_STORE

chan_scan_go:
        LD HL,(STORE_SIZE)      ; bytes left to look at

chan_scan_loop:
        LD A,(BC)
        CP MARK_HI
        JR z,chan_error
        CP D
        JR nz,chan_scan_next
        INC BC
        LD A,(BC)
        DEC BC
        CP E
        JR z,chan_found

chan_scan_next:
        INC BC
        DEC HL
        LD A,H
        OR L
        JR nz,chan_scan_loop

chan_error:
        LD A,0xff
        RET

chan_found:
        LD (CHAN_HINT),BC
        INC BC
        INC BC
        LD H,B
        LD L,C

chan_ok:
        XOR A
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
        LD DE,MARK_LO*0x100+MARK_LO
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
        JR repair_terminate

repair_fix_pair:
        DEC HL
        DEC HL
        LD (HL),' '
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        CALL is_marker
        JR nc,repair_next
        LD (HL),' '

repair_next:
        INC HL

repair_scan:
        LD A,(HL)
        CALL is_marker
        JR c,repair_marker

repair_scan_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,repair_scan

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

fixbad_loop:
        LD A,(HL)
        CALL char_flags
        JR nc,fixbad_next
        LD (HL),'?'

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
        LD (HL),' '

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
        CALL is_marker
        JR nc,addend_next
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
        LD BC,12000             ; P31: about 75 ms, four mains cycles. No NMI in
                                ; that time means no mains: take the add-in
init_nmi_wait:                  ; board's 64 Hz. Without the board the bit does
        LD A,(NMI_SEEN)         ; nothing and the clock stands, as before.
        OR A                    ; (NMI is not maskable, so this works under DI.)
        JR nz,init_nmi_mains
        DEC BC
        LD A,B
        OR C
        JR nz,init_nmi_wait
        LD A,NMI_PER_SEC_XTAL
        JR init_nmi_store

init_nmi_mains:
        LD A,NMI_PER_SEC_MAINS

init_nmi_store:
        LD (NMI_PER_SEC),A
        JP clock_bank

; ---- init_vars: power-on RAM init: BOOT_ZERO and the stream area cleared, the
;      IMAGE copied from INIT_DATA, the random seed, then the configuration
;      block validated (P35) and the defaults applied if it fails
init_vars:
        LD A,(NMI_COUNT)        ; the seed: RAM noise at power-up, the count after a reset
        PUSH AF
        XOR A
        LD HL,BOOT_ZERO
        LD B,BOOT_ZERO_LEN

init_clear:
        LD (HL),A
        INC HL
        DJNZ init_clear
        LD HL,STREAM_AREA       ; P21: no reply in flight, no packet busy
        LD B,STREAM_AREA_SIZE

init_clear_stream:
        LD (HL),A
        INC HL
        DJNZ init_clear_stream
        LD A,0x55               ; P40: HL is at the stack's bottom: lay the canary
        LD B,STACK_CANARY

init_canary:
        LD (HL),A
        INC HL
        DJNZ init_canary
        LD HL,INIT_DATA
        LD DE,IMAGE
        LD BC,IMAGE_LEN
        LDIR
        POP AF
        LD (RND_SEED),A
        AND 3
        ADD A,3
        LD (RND_VAL),A
        CALL cfg_valid          ; P35: the block's signature and sum say whether RAM survived
        JR z,init_vars_done
        LD HL,CFG_DEFAULTS
        LD DE,CFG
        LD BC,CFG_LEN-1
        LDIR
        CALL cfg_seal
        ; P6: RAM is fresh, so the clock bytes are noise too - the image copy
        ; below starts at CLK_RUN and never touches CLK_H10..CLK_PM. Start 12:00 AM.
        LD HL,0x0201
        LD (CLK_H10),HL         ; CLK_H10 = 1, CLK_H1 = 2
        LD HL,0
        LD (CLK_M10),HL         ; CLK_M10, CLK_M1
        LD (CLK_SEC),HL         ; CLK_SEC, CLK_PM (0 = AM)
        LD (CLK_PM),HL          ; P40: and BOOT_COUNT
        ; The message store is noise as well; store_repair would only tidy it
        ; into 100 channels of garbage. Empty it now: init_sequence then finds
        ; every channel empty and runs the demo, as after a CLR ALL.
        CALL store_clear_all

init_vars_done:
        IM 1
        LD HL,BOOT_COUNT        ; P40
        INC (HL)
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        RET

; ---- cfg_sum (P35): A = 8-bit sum of the block's first 15 bytes, HL -> CFG_SUM.
;      The live bits of CFG_FLAGS (4-7) change without a reseal and do not count.
cfg_sum:
        LD HL,CFG
        LD B,CFG_LEN-1
        XOR A

cfg_sum_loop:
        ADD A,(HL)
        INC HL
        DJNZ cfg_sum_loop
        LD C,A
        LD A,(CFG_FLAGS)
        AND 0xf0
        LD B,A
        LD A,C
        SUB B
        RET

; ---- chan_boundary: a new message starts: a pending mute takes effect and the
;      wrapped flag is cleared until the sequence starts over again
chan_boundary:
        LD HL,CFG_FLAGS
        RES 6,(HL)
        BIT 3,(HL)
        RET z
        RES 3,(HL)
        SET 2,(HL)
        JR cfg_seal

; ---- cfg_seal: store the sum; every write to the block ends here
cfg_seal:
        CALL cfg_sum
        LD (HL),A
        RET

; ---- cfg_valid: Z if the sum matches and the signature is in place
cfg_valid:
        CALL cfg_sum
        CP (HL)
        RET nz
        LD A,(CFG_SIG)
        CP CFG_MAGIC
        RET

; ---- CFG_DEFAULTS: the block after a RAM loss, the sum computed at boot
CFG_DEFAULTS:
        db CFG_MAGIC, 1         ; signature, address 1 (NETCC's default)
        db 0x03                 ; full brightness, not muted
        db 0, 0, 0, 0           ; spare line roles: none
        db 99                   ; alert channel
        db HOLD_FRAMES, FLASH_HALF_PERIOD
        db 1, 0                 ; beeper on, remote unlocked
        db 0, 0, 0              ; status reports off, clock source auto, reserved

; ---- INIT_DATA: the boot values of the IMAGE variables, in their RAM order
INIT_DATA:
        dw FRAMEBUF_ROW1       ; FB_COLPTR
        dw FRAMEBUF            ; FB_COL
        dw TXBUF               ; STAGE_PTR
        dw FRAMEBUF            ; FB_OUT_PTR
        dw MSG_STORE           ; STORE_CURSOR
        db 0x01                ; CLK_RUN
        db 0x0f                ; CUR_COLOR
        db 0x01                ; DISP_ON
        db 0x0f                ; COL_COUNT
        db 0x0a                ; LATCH_BIT7
        db 0x01                ; FLUSH_PENDING
        db BAUD_T_DEFAULT      ; BAUD_T
        db BAUD_STEP_300       ; BAUD_STEP
        db 0x7f                ; BAUD_CAL_LAST
        db 0xff                ; RX_IDLE
        db 0xff                ; CAPS_LOCK
        db 0xff                ; ROW_OUT_PENDING
        db 0x01                ; DISP_COUNT
        db 0xff                ; NEXT_CHAN
        db ' '                 ; MAGIC_LAST_CHAR

; ---- init_render: Reset render state for the current message
init_render:
        CALL clear_framebuf
        XOR A
        LD HL,RENDER_ZERO
        LD B,RENDER_ZERO_LEN

init_render_zero:
        LD (HL),A
        INC HL
        DJNZ init_render_zero
        LD A,0xff
        LD (DISP_ON),A
        LD HL,FRAMEBUF
        LD (FB_OUT_PTR),HL
        LD (FB_COL),HL
        LD HL,0
        LD (FB_EXTRA_LEN),HL
        LD HL,FRAME_COLS
        LD (FB_OUT_LEN),HL
        LD A,COLOR_DEFAULT
        LD (WINDOW_COLOR),A
        LD (ROW_COLOR),A
        LD (CUR_COLOR),A
        CALL effect_none
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
;      at the next space; two spaces in a row clear the background color
track_flash_space:
        LD A,(CUR_CHAR)
        CP ' '
        JR z,space_seen
        XOR A
        LD (PREV_SPACE),A
        LD A,(CUR_CHAR)
        CALL char_flags
        RET nz
        LD A,0xff
        LD (TEXT_DRAWN),A
        LD A,(FLASH_PENDING)
        AND A
        RET z
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
        RET z
        LD A,(CUR_COLOR)
        AND 15
        LD (CUR_COLOR),A

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
        JR nz,class_high
        AND 0x60
        JP z,attr_control
        LD A,(CUR_CHAR)
        CP ATTR_TIME
        JP z,render_clock
        BIT 7,A
        JR z,glyph_lookup

class_high:
        CP 0x94
        JP c,attr_color_speed
        CP GRAPH_BASE
        JR c,glyph_lookup
        AND 0xf0
        CP 0xc0
        JR z,glyph_lookup
        CP 0xe0
        JR z,glyph_lookup
        CP 0xd0
        JP nz,attr_color_speed

; ---- glyph_lookup: the glyph of CUR_CHAR, copied to GLYPH_BUF_ITALIC with zero
;      columns after it (glyph_bold and glyph_big read one past the end, and a
;      graphic is drawn at twice its width), then styled and placed
glyph_lookup:
        CALL glyph_addr
        CALL clear_glyph_tmp
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD B,0
        LD DE,GLYPH_BUF_ITALIC
        LDIR
        LD HL,GLYPH_BUF_ITALIC
        LD (GLYPH_PTR),HL
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
        LD A,(GLYPH_WIDTH)
        SLA A
        CP 0x20
        JR c,glyph_set_width
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

; ---- glyph_blit: write color byte + glyph columns at FB_COLPTR
glyph_blit:
        LD A,(MAGIC_MODE)
        AND A
        JR z,blit_setup
        LD A,(CUR_CHAR)
        CP ' '
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

; ---- WIDE_SPACE_GLYPH: 9-column blank for spaces in MAGIC mode; also the 5 and 6
;      blank columns the TINY push-offs blit
WIDE_SPACE_GLYPH:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

; ---- glyph_stage: effect active: stage the glyph into TXBUF instead
glyph_stage:
        LD HL,(STAGE_PTR)
        LD A,(GLYPH_WIDTH)
        LD D,0
        LD E,A
        ADD HL,DE
        LD DE,STAGE_END
        XOR A
        SBC HL,DE
        JP nc,fx_flush_stage
        LD DE,(STAGE_PTR)
        LD A,(FLASH_BIT)
        OR COLOR_DEFAULT
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
        JP unfetch_char

; ---- char_to_glyph: A = character -> A = its glyph index: the code itself for
;      00-7F, then C0-CF, E0-EF, 90-9F and D0-DF map to glyphs 128-190 (E lost)
char_to_glyph:
        PUSH AF
        AND 0xf0
        CP 0xc0
        LD E,128
        JR z,glyph_base_sel
        CP 0xd0
        LD E,175
        JR z,glyph_base_sel
        CP 0xe0
        LD E,144
        JR z,glyph_base_sel
        CP 0x90
        LD E,160
        JR z,glyph_base_sel
        POP AF
        RET

glyph_base_sel:
        POP AF
        AND 15
        ADD A,E
        RET

; ---- glyph_put_next: draw A, keeping BC, then HL+1
glyph_put_next:
        LD (CUR_CHAR),A
        PUSH HL
        PUSH BC
        CALL glyph_lookup
        POP BC
        POP HL
        INC HL
        RET

; ---- char_flags: A = character -> Z if printable text, CY if an invalid byte;
;      an attribute is NZ and NC. Only A and the flags change.
char_flags:
        PUSH BC
        PUSH HL
        LD C,A
        AND 3
        INC A
        LD B,A                  ; rotations: 1 for char 4n .. 4 for 4n+3
        LD A,C
        RRCA
        RRCA
        AND 0x3f
        ADD A,CHAR_FLAGS & 0xff
        LD L,A
        ADC A,CHAR_FLAGS >> 8
        SUB L
        LD H,A
        LD A,(HL)

cf_rotate:
        RLCA
        RLCA
        DJNZ cf_rotate
        AND 3
        RRCA                    ; bit 0 to CY; Z from the AND stands
        POP HL
        POP BC
        RET

; ---- glyph_addr: HL = the columns of CUR_CHAR's glyph, GLYPH_WIDTH = its width.
;      The glyphs are packed at their widths: FONT_BLOCK gives every eighth
;      glyph's address and the widths of the glyphs before it in its block are added.
glyph_addr:
        LD A,(CUR_CHAR)
        CALL char_to_glyph
        LD E,A
        LD D,0
        LD HL,FONT_WIDTH
        ADD HL,DE               ; HL -> its width
        LD A,E
        AND 7
        LD C,A                  ; glyphs before it in the block
        LD B,0
        SBC HL,BC               ; HL -> the block's first width (ADD left CY clear)
        LD A,E
        AND 0xf8
        RRCA
        RRCA                    ; twice the block number
        LD E,A
        PUSH HL
        LD HL,FONT_BLOCK
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)               ; DE = the block's first column
        POP HL
        INC C
        JR glyph_addr_test

glyph_addr_skip:
        LD A,(HL)
        ADD A,E
        LD E,A
        JR nc,glyph_addr_next
        INC D

glyph_addr_next:
        INC HL

glyph_addr_test:
        DEC C
        JR nz,glyph_addr_skip
        LD A,(HL)
        LD (GLYPH_WIDTH),A
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

; ---- attr_rainbow: BC starts the per-character color cycle
attr_rainbow:
        LD A,(CUR_CHAR)
        CP ATTR_RAINBOW
        JR nz,rainbow_step
        LD A,(MAGIC_MODE)
        AND A
        JR z,rainbow_on
        LD A,(RAINBOW_COLORS+1)
        LD (CUR_COLOR),A

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
        LD B,A
        LD A,(RND_SEED)         ; P28: bit 7 of the index is the direction, from
        AND RAINBOW_REVERSE     ; the generator's best bit
        OR B
        LD (RAINBOW_IDX),A
        LD (MAGIC_COLOR_SET),A ; any non-zero value means "set"
        POP HL
        JR render_next_char_jr4

rainbow_step:
        LD A,(RAINBOW_IDX)
        AND A
        LD A,(CUR_CHAR)
        RET z
        CP 0x20
        RET z
        CALL char_flags
        RET nz
        LD A,(RAINBOW_IDX)
        LD B,A
        AND 7
        BIT 7,B
        JR nz,rainbow_back
        INC A                   ; forward: 1..5 then round to 1
        CP 6
        JR c,rainbow_lookup
        LD A,1
        JR rainbow_lookup

rainbow_back:
        DEC A                   ; P28: reverse: 5..1 then round to 5
        JR nz,rainbow_lookup
        LD A,5

rainbow_lookup:
        LD E,A
        LD D,0
        LD HL,RAINBOW_COLORS
        ADD HL,DE
        LD A,(HL)
        CP 0xff
        JR nz,rainbow_apply
        LD E,1
        LD A,(RAINBOW_COLORS+1)

rainbow_apply:
        AND 15
        LD (CUR_COLOR),A
        LD A,B
        AND RAINBOW_REVERSE     ; keep the direction with the new index
        OR E
        LD (RAINBOW_IDX),A
        LD A,(CUR_CHAR)
        RET

; ---- RAINBOW_COLORS: per-character cycle red, orange, yellow, lime, green
RAINBOW_COLORS:
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

render_next_char_jr4:
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
        CALL fb_colors_default
        XOR A
        LD (RX_BYTE),A
        LD (IR_CODE),A

wait_poll:
        LD A,(RX_BYTE)
        CP ' '
        JR nz,wait_check_pkt
        POP HL
        JR render_next_char_jr4

wait_check_pkt:
        CALL pkt_poll
        JR wait_poll

; ---- attr_thin_check: B9 THIN
attr_thin_check:
        LD A,(CUR_CHAR)
        CP ATTR_THIN
        RET nz
        LD (THIN_MODE),A
        POP HL
        JR render_next_char_jr4

; ---- attr_draw_check: B8 DRAW: hex digit pairs -> DRAW_BUF columns, up to
;      16, ended by the first non-hex byte
attr_draw_check:
        LD A,(CUR_CHAR)

; ---- attr_draw: 0xB8: user-drawn graphic follows
attr_draw:
        CP ATTR_DRAW
        JR z,draw_begin
        XOR A
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
        LD A,C
        AND A
        JR nz,draw_set_width
        XOR A
        LD (DRAW_NO_GAP),A
        LD A,' '
        LD (CUR_CHAR),A
        RET

draw_set_width:
        LD (GLYPH_WIDTH),A
        POP HL
        LD A,(EFFECT_ID)
        AND A
        JR z,glyph_place_jr6
        CALL glyph_bold
        LD A,(GLYPH_WIDTH)
        DEC A
        LD (GLYPH_WIDTH),A

glyph_place_jr6:
        JP glyph_place

draw_pop_odd:
        POP AF

draw_bad_hex:
        LD A,(CUR_CHAR)
        CP TEXT_END
        JR nz,draw_abort
        CALL unfetch_char

draw_abort:
        LD A,'*'
        LD (CUR_CHAR),A
        JR draw_finish

; ---- hex_digit_value: A = value of ASCII hex digit, FF if not one
hex_digit_value:
        CP '0'
        JR c,hexval_bad
        CP '9'+1
        JR c,hexval_ok
        AND 0xdf
        CP 0x41
        JR c,hexval_bad
        CP 0x47
        JR nc,hexval_bad
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
        JR nz,magic_attr
        LD HL,MAGIC_WORD_COUNT
        INC (HL)
        LD A,2
        LD (FONT_MODE),A
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

magic_ret_jr7:
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
        LD (MAGIC_COLOR_SET),A
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
        CALL tiny_scroll_off    ; push the text off: a panel width of spaces
        POP AF
        LD (CUR_CHAR),A
        RET

magic_other:
        XOR A
        LD (MAGIC_FX_PREV),A
        LD A,(CUR_CHAR)
        CP ATTR_DRAW
        JR z,magic_printable
        AND 0xf0
        CP GRAPH_BASE
        JR z,magic_printable
        CP 0x20
        RET c
        CP COLOR_BASE
        RET nc

magic_printable:
        LD A,(MAGIC_LAST_CHAR)
        CP 0x20
        JR z,magic_word_start
        LD A,(CUR_CHAR)
        LD (MAGIC_LAST_CHAR),A
        JR magic_ret_jr7

magic_word_start:
        LD A,(CUR_CHAR)
        LD (MAGIC_LAST_CHAR),A
        CP 0x24
        JR nz,magic_pick_font
        LD (MAGIC_FLASH_WORD),A

magic_pick_font:
        AND 0xf0
        CP GRAPH_BASE
        JR z,magic_color_check
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
        JR c,magic_short_word
        CP 0x5b
        JR nc,magic_short_word
        INC HL
        DJNZ magic_scan_word
        JR magic_font_normal

magic_short_word:
        LD A,B
        CP 6
        JR nc,magic_font_normal
        LD A,(RND_SEED)
        ADD A,(HL)
        LD HL,NMI_COUNT
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
        JR nc,magic_color_check
        LD A,(RND_VAL)
        AND A
        JR z,magic_reseed
        DEC A
        JR z,magic_reseed
        LD (RND_VAL),A
        LD A,(MAGIC_COLOR_SET)
        AND A
        JR z,magic_reset_words
        XOR A
        LD (MAGIC_COLOR_SET),A
        LD (RND_VAL),A
        JR magic_reset_words

magic_reseed:
        LD A,(NMI_COUNT)
        LD E,A
        AND 3
        ADD A,2
        LD (RND_VAL),A

magic_color_check:
        LD A,(MAGIC_COLOR_SET)
        AND A
        JR z,magic_next_color
        XOR A
        LD (MAGIC_COLOR_SET),A
        LD (RND_VAL),A
        JR magic_reset_words

magic_next_color:
        XOR A
        LD (RAINBOW_IDX),A
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
        JR nz,magic_color_apply
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
        RET z
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
        RET z

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
        RET z
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
        RET z
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
        LD DE,FRAMEBUF_END
        XOR A
        SBC HL,DE
        JR c,fbinc_nowrap
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
        LD DE,FRAMEBUF_END
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

; ---- wait_frame_delay: spin, polling for packets, until FRAME_DELAY runs out
wait_frame_delay:
        CALL pkt_poll
        LD A,(FRAME_DELAY)
        AND A
        JR nz,wait_frame_delay
        RET

; ---- wait_row6: spin until the display is on row 6
wait_row6:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,wait_row6
        RET

; ---- effect_none: no movement effect: EFFECT_ID = 0 (A = 0 on return), fxv_none
effect_none:
        XOR A
        LD (EFFECT_ID),A
        LD HL,fxv_none
        LD (EFFECT_VECTOR),HL
        RET

; ---- crawl_step (P42): effect_step for the render loop. The plain crawl draws the
;      next character once CRAWL_LEAD columns or fewer are left to scroll in, so a
;      packet processed meanwhile does not stop the scroll. Anything but a plain
;      character next (attributes, the clock, the end) waits for the full catch-up.
crawl_step:
        CALL wait_frame_delay

crawl_wait:
        CALL pkt_poll
        LD A,(SCROLLING)
        AND A
        JR z,fx_scroll_done
        LD A,(EFFECT_ID)
        LD HL,MAGIC_MODE
        OR (HL)
        JR nz,crawl_wait
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP ATTR_TIME
        JR z,crawl_wait
        CALL char_flags
        JR nz,crawl_wait
        LD HL,(FB_COLPTR)       ; columns still to scroll in: FB_COLPTR - FB_COL
        LD DE,(FB_COL)          ; round the ring, less the panel's width
        OR A
        SBC HL,DE
        JR nc,crawl_lead
        LD DE,FRAMEBUF_SIZE
        ADD HL,DE

crawl_lead:
        LD DE,FRAME_COLS+CRAWL_LEAD+1
        OR A
        SBC HL,DE
        JR nc,crawl_wait
        JR fx_scroll_done

; ---- effect_step: Called from main loop: jump to EFFECT_VECTOR (current movement effect handler)
effect_step:
        CALL wait_frame_delay

fx_wait_scroll:
        CALL pkt_poll
        LD A,(SCROLLING)
        AND A
        JR nz,fx_wait_scroll

fx_scroll_done:
        LD A,(EFFECT_ID)
        AND A
        RET z

fx_wait_row6:
        CALL wait_row6
        LD HL,(STAGE_OFFSET)
        LD A,L
        CP FRAME_COLS/2
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
        LD (CUR_COLOR),A

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
        JR nz,attr_not_norm
        XOR A
        LD (FLASH_BIT),A
        LD (FONT_MODE),A
        JR attr_set_font

attr_not_norm:
        CP ATTR_BOLD
        JR nz,attr_not_bold
        LD A,2
        JR attr_set_font

attr_not_bold:
        CP ATTR_ITALIC
        JR nz,attr_not_italic
        LD A,6
        JR attr_set_font

attr_not_italic:
        CP ATTR_FLASH
        JR nz,attr_not_flash
        LD A,COLOR_FLASH
        LD (FLASH_PENDING),A
        JR render_next_char_jr2

attr_not_flash:
        CP ATTR_BIG
        JR nz,attr_not_big
        LD A,10

attr_set_font:
        LD (FONT_MODE),A
        LD A,0xff
        LD (MAGIC_FONT_SET),A
        JR render_next_char_jr2

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
        LD DE,STAGE_END
        XOR A
        EX DE,HL
        SBC HL,DE
        LD A,FRAME_COLS
        SUB L
        LD (COL_COUNT),A
        JP stage_centre

fx_dispatch:
        LD A,(CUR_CHAR)
        CALL dispatch
        DKEY 6, fx_halt
        DKEY 7, fx_beep
        DKEY 3, fx_end_of_channel
        DKEY ATTR_LEFT, fx_left
        DKEY ATTR_PAUSE, fx_pause
        DKEY ATTR_UP, fx_up
        DKEY ATTR_DOWN, fx_down
        DKEY 15, fx_right
        DKEY ATTR_HOLD, fx_hold
        db 0xff

render_next_char_jr2:
        JP render_next_char

; ---- fx_beep
fx_beep:
        CALL beep_start
        JR render_next_char_jr2

; ---- beep_start: BEEP_TICKS = BEEP_LEN (~115 ms); P35: nothing with the beeper off
beep_start:
        LD A,(CFG_BEEP)
        AND A
        RET z
        PUSH HL
        LD HL,BEEP_LEN
        LD (BEEP_TICKS),HL
        POP HL
        RET

; ---- fx_end_of_channel
fx_end_of_channel:
        CALL effect_none
        CALL scroll_off_text
        LD SP,STACK_TOP
        JP main_loop

; ---- the movement attributes: 0F RIGHT (effect 4), 18 LEFT (plain crawl, no
;      staging), BB HOLD (5), 19 PAUSE (1), 1A UP (2), 1B DOWN (3). The staged
;      ones take the whole frame; all but HOLD stop the window first.
fx_right:
        LD A,4
        LD HL,fxv_right
        JR fx_staged

fx_pause:
        LD A,1
        LD HL,fxv_pause
        JR fx_staged

fx_up:
        LD A,2
        LD HL,fxv_wipe_updown
        JR fx_staged

fx_hold:
        LD A,5
        LD HL,fxv_hold
        JR fx_set

fx_down:
        LD A,3
        LD HL,fxv_wipe_updown

fx_staged:
        LD C,A
        XOR A
        LD (SCROLLING),A
        LD A,C

fx_set:
        LD (EFFECT_ID),A
        LD (EFFECT_VECTOR),HL
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        JR render_next_char_jr2

fx_left:
        CALL effect_none
        LD (COL_COUNT),A
        JR render_next_char_jr2

; ---- fx_magic
fx_magic:
        XOR A
        LD (FLASH_PENDING),A
        LD (MAGIC_COLOR_SET),A
        LD (MAGIC_FONT_SET),A
        LD (RAINBOW_IDX),A
        LD (MAGIC_FX_PREV),A
        LD A,0xff
        LD (MAGIC_MODE),A
        LD A,' '
        LD (MAGIC_LAST_CHAR),A
        LD A,1
        LD (MAGIC_WORD_COUNT),A
        LD A,(NMI_COUNT)
        LD E,A
        AND 3
        ADD A,2
        LD (RND_VAL),A
        CALL magic_first_color

render_next_char_jr5:
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

; ---- attr_magic_off: 0xBD: leave MAGIC mode, default color and font
attr_magic_off:
        XOR A
        LD (MAGIC_MODE),A
        LD (MAGIC_FONT_SET),A
        LD (MAGIC_COLOR_SET),A
        LD (FONT_MODE),A
        LD A,COLOR_DEFAULT
        LD (CUR_COLOR),A
        JR render_next_char_jr5

; ---- fx_halt: 06: hold 0x50 frames (~1.3 s) with the colors reset
fx_halt:
        XOR A
        LD (SCROLLING),A
        LD A,(EFFECT_ID)
        AND A
        JR nz,halt_hold

        CALL wait_frame_delay

halt_hold:
        LD A,(CFG_HOLD)         ; P35
        LD (FRAME_DELAY),A
        CALL fb_colors_default
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP ATTR_LEFT
        JP z,fx_left
        LD A,(EFFECT_ID)
        AND A
        JP z,fx_left
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        JR render_next_char_jr3

; ---- fb_colors_default: every color byte in FRAMEBUF -> 8F, keeping flash
fb_colors_default:
        LD HL,FRAMEBUF
        LD BC,FRAMEBUF_SIZE

fbcol_loop:
        BIT 7,(HL)
        JR z,fbcol_next
        LD A,(HL)
        AND COLOR_FLASH
        OR COLOR_DEFAULT
        LD (HL),A

fbcol_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,fbcol_loop
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

; ---- attr_color_speed: 0x8x foreground color, 0x9x background, 0xFx speed, 0xBD MAGIC OFF
attr_color_speed:
        LD A,(CUR_CHAR)
        AND 0xf0
        CP COLOR_BASE
        JR z,attr_fore_color
        CP BGRND_BASE
        JR z,attr_back_color
        CP SPEED_BASE
        JR z,attr_speed
        LD A,(CUR_CHAR)
        CP ATTR_MAGIC_OFF
        JP z,attr_magic_off

render_next_char_jr3:
        JP render_next_char

; ---- attr_fore_color
attr_fore_color:
        XOR A
        LD (RAINBOW_IDX),A
        LD A,(MAGIC_MODE)
        AND A
        JR z,fore_set
        LD A,(CUR_COLOR)
        AND 0xcf
        LD (CUR_COLOR),A

fore_set:
        LD A,(CUR_CHAR)
        AND 15
        LD E,A
        LD A,(CUR_COLOR)
        AND 0x60
        OR E
        LD (CUR_COLOR),A
        LD A,0xff
        LD (MAGIC_COLOR_SET),A
        JR render_next_char_jr3

; ---- attr_back_color
attr_back_color:
        LD A,(MAGIC_MODE)
        AND A
        JR z,back_set
        LD A,(CUR_COLOR)
        OR 15
        LD (CUR_COLOR),A

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
        LD A,(CUR_COLOR)
        AND 15
        OR L
        AND 0x6f
        LD (CUR_COLOR),A
        LD A,0xff
        LD (MAGIC_COLOR_SET),A
        JR render_next_char_jr3

; ---- attr_speed
attr_speed:
        LD A,(CUR_CHAR)
        AND 7
        LD (SCROLL_SPEED),A
        JR render_next_char_jr3

; ---- attr_tiny: 0xBE: switch to tiny (28-char) font mode and render
attr_tiny:
        CALL tiny_scroll_off
        CALL clear_framebuf
        LD A,0xff
        LD (TINY_RENDER),A
        LD A,COLOR_DEFAULT
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

; ---- tiny_scroll_off: push existing text off before TINY text or a MAGIC effect
tiny_scroll_off:
        ; Stock scanned 86 bytes from the ADDRESS of FB_COL (LD HL,FB_COL, a typo
        ; for the pointer) looking for a color byte; a 0x95 constant sat three
        ; bytes in, so the test never failed. P8 drops the scan and the bytes.
        LD B,FRAME_COLS/6

tinyoff_loop:
        PUSH BC
        LD A,' '
        LD (CUR_CHAR),A
        CALL effect_none
        LD A,6
        LD (GLYPH_WIDTH),A
        LD HL,WIDE_SPACE_GLYPH
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
        JR z,tinyg_stop
        LD A,(CUR_CHAR)
        CP ATTR_TIME
        JR z,tinyg_stop
        BIT 7,A
        JR z,tinyg_lookup
        CP 0x94
        JR c,tinyg_stop
        CP 0x9e
        JR c,tinyg_lookup
        AND 0xf0
        CP 0xc0
        JR z,tinyg_lookup
        CP 0xe0
        JR nz,tinyg_stop

tinyg_lookup:
        CALL glyph_addr

; ---- tiny_put_glyph: color byte + glyph into FRAMEBUF_TINY
tiny_put_glyph:
        LD DE,FRAMEBUF_TINY+1
        LD B,0
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD A,COLOR_DEFAULT
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
        LD BC,2*FRAME_COLS+16
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

tiny_copy_wait:
        CALL pkt_poll           ; P26: a TINY line is seconds of these waits
        LD A,(TINY_FRAME_READY)
        AND A
        JR nz,tiny_copy_wait

tinycp_loop:
        LDI
        INC HL
        JP pe,tinycp_loop
        LD A,0xff
        LD (TINY_FRAME_READY),A
        RET

; ---- tiny_scroll_out: 28 spaces to clear the tiny line
tiny_scroll_out:
        LD B,2*FRAME_COLS/6

tinyout_loop:
        PUSH BC
        LD A,' '
        LD (CUR_CHAR),A
        LD A,5
        LD (GLYPH_WIDTH),A
        LD HL,WIDE_SPACE_GLYPH
        CALL tiny_put_glyph
        CALL tiny_scroll_cols
        POP BC
        DJNZ tinyout_loop
        RET

tiny_refresh:
        LD A,(TINY_FRAME_READY)
        AND A
        JR nz,tiny_row_out
        CALL latch_blank

rx_consume_jr8:
        JP rx_consume

tiny_row_out:
        LD A,(ROW_OUT_PENDING)
        AND A
        JR z,disp_next_row
        CALL latch_blank
        LD A,(CFG_FLAGS)        ; P35: TINY has one pass, so it is dark only
        AND 7                   ; when muted or at brightness 0
        CP 4
        JR nc,tiny_row_done
        AND A
        JR z,tiny_row_done

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
        LD A,COLOR_DEFAULT
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
        CALL latch_row_dim_tiny ; P35

tiny_row_done:
        XOR A
        LD (ROW_OUT_PENDING),A
        JP tick6_restore

; ---- disp_next_row: ROW_INDEX = (ROW_INDEX+1) mod 7
disp_next_row:
        CALL row_step
        JP c,tick6_arm_row
        LD (TINY_FRAME_READY),A
        JR rx_consume_jr8

; ---- row_step: ROW_INDEX + 1: CY while rows are left, else back to 0 with A = 0
row_step:
        LD A,(ROW_INDEX)
        INC A
        LD (ROW_INDEX),A
        CP 7
        RET c
        XOR A
        LD (ROW_INDEX),A
        RET

; ---- fxv_prepare: clear FRAMEBUF and reset the output window; HL = TXBUF,
;      DE = FRAMEBUF + STAGE_OFFSET (the staged text is centered)
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
        CALL wait_row6
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,0xff
        LD (DISP_ON),A
        LD A,1
        LD (FRAME_DELAY),A

        CALL wait_frame_delay
        DJNZ right_wait_row
        JR fx_hold_done

; ---- fxv_none: effect handler: nothing (straight to render loop)
fxv_none:

fx_done_jr9:
        JP fx_done

; ---- fxv_hold: effect 5: fill with 0x8F (no columns lit), then copy one staged
;      column per frame, right to left
fxv_hold:
        LD HL,FRAMEBUF
        LD BC,FRAMEBUF_SIZE

hold_fill:
        LD (HL),COLOR_DEFAULT
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
        CALL wait_row6
        LD A,(HL)
        LD (DE),A
        DEC HL
        DEC DE
        LD A,0xff
        LD (DISP_ON),A
        LD A,1
        LD (FRAME_DELAY),A

        CALL wait_frame_delay
        DJNZ hold_wait_row
        JR fx_hold_done

; ---- fxv_pause: effect 1: copy the whole stage, then FRAME_DELAY 0x50
fxv_pause:
        CALL fxv_prepare
        LD B,0
        LD A,(COL_COUNT)
        LD C,A
        LDIR

; ---- fx_hold_done: an effect has its frame up: hold it, then end the effect
fx_hold_done:
        LD A,(CFG_HOLD)         ; P35
        LD (FRAME_DELAY),A
        XOR A
        LD (SCROLLING),A
        JR fx_done_jr9

; ---- fxv_wipe_updown: effects 2 (UP) and 3 (DOWN): eight passes copying the
;      stage through a row mask that grows one row per pass
fxv_wipe_updown:
        XOR A
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
        CALL wait_row6

wipev_col:
        LD A,(HL)
        BIT 7,A
        JR nz,wipev_color_byte
        AND C
        JR wipev_store

wipev_color_byte:
        LD A,C
        CP 0xff
        LD A,COLOR_DEFAULT
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

        CALL wait_frame_delay
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
        JR fx_hold_done

; ---- store_clear_all: Reset MSG_STORE: 100 empty channels D0..? then DA
store_clear_all:
        LD A,MARK_LO
        LD C,0xd0
        LD HL,MSG_STORE
        LD B,CHANNELS

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
        LD A,MARK_HI            ; not a channel: init_sequence loads the default
        JP seq_list_one

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
        XOR A
        LD (RX_PHASE),A
        LD (RX_ACC),A
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
        LD (IR_QUIET),A         ; P36: a gate left set by the leader wait would keep the idle count asleep and cost the next frame

; ---- ir_reset: IR decoder: reset state, wait for leader (port C0 IR_BIT)
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
        BIT IR_BIT,A
        JR z,ir_idle_low
        LD A,PORT_IR|1
        LD (IR_QUIET),A         ; P35: a high line while idle: sleep until it falls
        JR ir_reset

ir_idle_low:
        LD A,(IR_STATE_CNT)
        DEC A
        JR nz,ir_idle_count
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
        BIT IR_BIT,A
        JR nz,ir_leader_seen
        LD A,1
        LD (IR_QUIET),A         ; P35: sleep until the ISR sees the line rise
        JR ir_leader_ret

ir_leader_seen:
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
        BIT IR_BIT,A
        JR z,ir_leader2_fell
        LD A,PORT_IR|1
        LD (IR_QUIET),A         ; P35: a line that stays high (a receiver unplugged) parks the decoder here
        JR ir_leader2_ret

ir_leader2_fell:
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
        BIT IR_BIT,A
        JR z,ir_reject
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
        JR nz,ir_start_count
        IN A,(PORT_IN)
        BIT IR_BIT,A
        JR nz,ir_reject
        PUSH HL
        LD HL,ir_st_bits
        LD (TICK_VECTOR),HL
        POP HL
        LD A,8

ir_start_count:
        LD (IR_STATE_CNT),A
        POP AF
        RET

ir_reject:                  ; P40: a frame dropped after its leader
        LD A,(STAT_IR_BAD)
        INC A
        LD (STAT_IR_BAD),A
        JP ir_reset

; ---- ir_st_bits: sample a data bit (port C0 IR_BIT) into IR_SHIFT every 4 ticks
ir_st_bits:
        PUSH AF
        LD A,(IR_STATE_CNT)
        DEC A
        JR z,ir_bit_verify
        CP 4
        JR nz,ir_bit_count
        LD (IR_STATE_CNT),A
        PUSH HL
        LD HL,IR_SHIFT
        RRC (HL)
        IN A,(PORT_IN)
        AND PORT_IR
        OR (HL)
        LD (IR_SHIFT),A
        POP HL
        POP AF
        RET

ir_bit_verify:
        PUSH HL
        LD A,(IR_SHIFT)
        CPL
        AND PORT_IR
        LD L,A
        IN A,(PORT_IN)
        AND PORT_IR
        CP L
        POP HL
        JR nz,ir_reject
        LD A,(IR_BITCNT)
        DEC A
        LD (IR_BITCNT),A
        JR z,ir_frame_done
        LD A,8

ir_bit_count:
        LD (IR_STATE_CNT),A
        POP AF
        RET

ir_frame_done:
        LD A,(STAT_IR_OK)       ; P40
        INC A
        LD (STAT_IR_OK),A
        LD A,(CFG_LOCK)         ; P35: a locked sign drops the key here, before
        AND A                   ; either consumer sees it
        JR nz,ir_done
        LD A,(IR_SHIFT)
        RLCA                    ; P36: bits enter at IR_BIT, so the first lands in bit 7
        OR 0x80
        LD (IR_CODE),A

ir_done:
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

; ---- tx_isr (P30, ISR): called while TX_STATUS has bit 0 (shifting) or bit 1
;      (a byte queued). Shifts TX_SHIFT out on CTRL_LATCH bit 4 (1 = start/space,
;      0 = mark), one bit per BAUD_T fifths of an interrupt, two stop bits.
tx_isr:
        LD HL,TX_STATUS
        BIT 0,(HL)
        JR z,tx_start_byte

tx_tick:
        LD A,(BAUD_STEP)
        LD C,A
        INC A
        SRL A
        LD B,A
        LD A,(TX_ACC)
        SUB C
        JR c,tx_edge
        CP B
        JR c,tx_edge
        LD (TX_ACC),A
        RET

tx_edge:
        LD C,A
        LD A,(BAUD_T)
        ADD A,C
        LD (TX_ACC),A
        LD HL,TX_BITIDX
        INC (HL)
        LD A,(HL)
        CP 9
        JR z,tx_stop_bit
        CP 10
        RET z                   ; the second stop bit: one more bit time of mark
        CP 11
        JR z,tx_idle
        LD HL,TX_SHIFT
        SRL (HL)                ; LSB first
        LD A,(CTRL_LATCH_SHADOW)
        JR c,tx_mark
        OR LATCH_TX
        JR tx_latch_bit

tx_mark:
        AND ~LATCH_TX&0xff

tx_latch_bit:
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        RET

tx_stop_bit:
        LD A,(CTRL_LATCH_SHADOW)
        AND ~LATCH_TX&0xff
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        RET

tx_idle:
        LD HL,TX_STATUS
        RES 0,(HL)
        BIT 1,(HL)
        RET nz                  ; a queued byte starts on the next interrupt
        JR tx_stream_next       ; else the background reply's next byte, now

; ---- tx_start_byte: TX_PENDING goes out; TX_STATUS is set last so the ISR
;      only sees a byte whose timing is in place
tx_start_byte:
        LD A,(TX_PENDING)
        LD (TX_SHIFT),A
        XOR A
        LD (TX_BITIDX),A
        LD A,(BAUD_T)
        LD (TX_ACC),A
        LD A,(CTRL_LATCH_SHADOW)
        OR LATCH_TX
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD HL,TX_STATUS
        LD (HL),1
        RET

; ---- tx_stream_next (P21): the background transmitter. Sends TX_SEG0, then
;      its sum if flagged, then TX_SEG1 the same way, then DONE if pending;
;      when all of that is out, the packet is no longer busy.
tx_stream_next:
        LD A,(TX_ACTIVE)        ; P27: the segments are written one at a time;
        OR A                    ; nothing streams until pkt_done_handoff
        RET z
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
        JR tx_start_byte

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
        JR tx_stream_queue

tx_stream_idle:
        LD A,(TX_ACTIVE)
        OR A
        RET z
        XOR A
        LD (TX_ACTIVE),A
        LD (PKT_BUSY),A
        RET

; ---- rx_start (P30, ISR): a start bit has just been seen on PORT_IN bit 3
;      (1 = space). After BAUD_IDLE_FRAMES of silence the pulse is timed to set
;      the rate (a frame's B1 has a one-bit start pulse: 26 interrupts at 300
;      baud, 13 at 600, 6.5 at 1200); otherwise the first sample
;      is scheduled 1.5 bits out at the known rate. Times are in fifths of an
;      interrupt (BAUD_T, stepped BAUD_STEP per interrupt), so 1200 baud keeps its half.
rx_start:
        LD A,(KP_MODE)          ; P36: a keypad holds the line at space between keys
        AND A
        RET nz
        LD (RX_SHIFT),A
        LD (RX_WIDTH),A
        LD A,8
        LD (RX_BITS),A
        LD A,(RX_IDLE)
        CP BAUD_IDLE_FRAMES
        LD A,0
        LD (RX_IDLE),A
        JR c,rx_start_timed
        LD A,1
        LD (RX_PHASE),A
        RET

rx_start_timed:
        LD A,(BAUD_T)
        LD C,A
        SRL A
        ADD A,C                 ; 1.5 bits: the middle of bit 0, less the half
        LD C,A                  ; interrupt the edge was seen late by on average
        LD A,(BAUD_STEP)
        SRL A
        LD B,A
        LD A,C
        SUB B
        LD (RX_ACC),A
        LD A,2
        LD (RX_PHASE),A
        RET

; ---- rx_phase_run (P30, ISR): A = RX_PHASE, 1 or 2
rx_phase_run:
        DEC A
        JR nz,rx_sample_tick
        IN A,(PORT_IN)          ; phase 1: how long is the start pulse
        BIT 3,A
        JR z,rx_measured
        LD HL,RX_WIDTH
        INC (HL)
        RET nz
        DEC (HL)                ; held at 255
        RET

rx_measured:
        LD A,(RX_WIDTH)
        CP 5
        JR c,rx_abort           ; a 2400-baud start bit, or noise: not taken
        LD C,BAUD_STEP_1200
        CP 10
        JR c,rx_rate
        LD C,BAUD_STEP_600
        CP 19
        JR c,rx_rate
        LD C,BAUD_STEP_300

rx_rate:
        LD A,C
        LD (BAUD_STEP),A        ; the transmitter follows: replies at the host's rate
        LD A,(RX_WIDTH)         ; the pulse ran width + 1.5 interrupts: the edge
        LD H,0                  ; was seen up to one late and the count began
        LD L,A                  ; an interrupt after that. HL = that in BAUD_STEP
        LD D,H                  ; units + T/2: whole bits the pulse covered (the
        LD E,L                  ; start bit and leading 0 bits), remainder to the next middle
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE               ; 5 x width

rx_rate_scale:
        LD A,C                  ; x 2 for each doubling of the step
        CP 6
        JR c,rx_rate_scaled
        ADD HL,HL
        SRL C
        JR rx_rate_scale

rx_rate_scaled:
        LD A,(BAUD_STEP)
        LD E,A
        SRL A
        ADD A,E                 ; 1.5 interrupts
        LD E,A
        LD A,(BAUD_T)
        LD C,A
        SRL A
        ADD A,E                 ; + T/2
        LD E,A
        LD D,0
        ADD HL,DE
        LD E,C                  ; DE = T
        LD B,0

rx_bits_loop:
        OR A
        SBC HL,DE
        JR c,rx_bits_done
        INC B
        JR rx_bits_loop

rx_bits_done:
        ADD HL,DE
        LD A,B
        OR A
        JR z,rx_abort           ; shorter than half a bit: noise
        LD A,C
        SUB L                   ; to the next bit's middle
        LD (RX_ACC),A
        LD A,9
        SUB B                   ; data bits left after the ones the pulse covered
        JR c,rx_abort           ; longer than a byte: not a byte
        LD (RX_BITS),A
        LD A,2
        LD (RX_PHASE),A
        RET

rx_abort:
        XOR A
        LD (RX_PHASE),A
        RET

; ---- rx_sample_tick (P30, ISR): phase 2, one sample per bit at the middle
rx_sample_tick:
        LD A,(BAUD_STEP)
        LD C,A
        INC A
        SRL A
        LD B,A                  ; half an interrupt
        LD A,(RX_ACC)
        SUB C
        JR c,rx_sample_now
        CP B
        JR c,rx_sample_now      ; within half an interrupt of the middle
        LD (RX_ACC),A
        RET

rx_sample_now:
        LD C,A
        LD A,(BAUD_T)
        ADD A,C
        LD (RX_ACC),A
        LD A,(RX_BITS)
        AND A
        JR z,rx_stop_sample
        DEC A
        LD (RX_BITS),A
        IN A,(PORT_IN)
        AND 8                   ; space is a 0 bit
        LD A,(RX_SHIFT)
        JR nz,rx_bit_zero
        SCF
        RR A                    ; bits arrive LSB first: in at the top
        LD (RX_SHIFT),A
        RET

rx_bit_zero:
        SRL A
        LD (RX_SHIFT),A
        RET

rx_stop_sample:
        IN A,(PORT_IN)
        BIT 3,A
        JR nz,rx_byte_end       ; no stop bit: dropped
        LD A,(RX_COUNT)
        CP 8
        JR nc,rx_byte_end       ; FIFO full: dropped
        LD E,A
        LD D,0
        LD HL,RX_FIFO
        ADD HL,DE
        LD A,(RX_SHIFT)
        LD (HL),A
        LD A,E
        INC A
        LD (RX_COUNT),A

rx_byte_end:
        XOR A
        LD (RX_PHASE),A
        RET

; ---- baud_calibrate (P30): from the NMI once a second. TICK6_CAL is the low
;      byte of the tick6 runs in that second, 1280 + s, so the 300-baud bit in
;      fifths of an interrupt is (1280 + s) / 10 = 128 + s / 10. A second is
;      taken only when it agrees with the one before within 3 ticks and is
;      within 5 % of nominal: a window that lost interrupts to a long DI
;      stretch (an OTA page write, a restart) disagrees with its neighbors.
baud_calibrate:
        LD HL,TICK6_CAL
        LD A,(HL)
        LD (HL),0
        LD HL,BAUD_CAL_LAST
        LD C,(HL)
        LD (HL),A
        LD B,A
        SUB C
        ADD A,3
        CP 7
        RET nc
        LD A,B
        ADD A,BAUD_CAL_LIMIT
        CP 2*BAUD_CAL_LIMIT+1
        RET nc
        LD A,B
        ADD A,5                 ; round to the nearest tenth
        LD B,BAUD_T_DEFAULT
        JP m,cal_down

cal_up:
        CP 10
        JR c,cal_done
        SUB 10
        INC B
        JR cal_up

cal_down:
        DEC B
        ADD A,10                ; last, so the branch tests A
        JP m,cal_down

cal_done:
        LD A,B
        LD (BAUD_T),A
        RET

; ---- clock_bank (P31): BANK_REG = the running bank, plus the clock-source bit
;      when the add-in board's crystal is the NMI. The OTA library writes the
;      bank alone, so this is repeated at every frame end and before each page
;      write, whose NMI sync would otherwise wait on a source that is off.
clock_bank:
        PUSH AF
        PUSH HL
        LD A,(ROM_BANK)
        LD HL,NMI_PER_SEC
        BIT 6,(HL)              ; 64 has it, 60 does not
        JR z,clock_bank_set
        OR BANK_CLOCK_XTAL

clock_bank_set:
        LD (BANK_REG),A
        POP HL
        POP AF
        RET

; ---- latch_blank / latch_row (P30): CTRL_LATCH read-modify-writes, closed to
;      the ISR, whose transmitter owns bit 4. latch_blank parks the rows (code
;      15); latch_row selects the row in C, which carries the blink bit.
latch_blank:
        DI
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        XOR A                   ; P35: a row code still waiting for the ISR goes with the
        LD (LATCH_PENDING),A    ; row, or a late service's next pass would light it mid-shift
        EI
        RET

latch_row:
        DI
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x70
        OR C
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        EI
        RET

; ---- latch_row_dim (P35): row_output's latch, C = the row code. At full
;      brightness the row is lit here, as before. Dimmed, the code is left for
;      the ISR, which lights the row on its next interrupt and parks the rows
;      again after LIT_LIMIT interrupts: 1 or 2 of the single-tick pass, 3 or 6
;      of the double-tick pass, for 1/3 and 2/3. A row is lit for 3 and 9
;      interrupts of those passes, not 6 and 12: the next tick blanks it first
;      and then spends three interrupts sending the next 86 bytes. Lighting on
;      the interrupt grid makes the lit time exact; lit from the latch, it
;      carried a 0-128 us remainder that drifted and pulsed at dim levels.
;      Every pixel loses the same share, so no color shifts. TINY rows last two
;      ticks, like the double-tick pass.
latch_row_dim:
        LD A,(ROW_PORT)
        AND 8
        LD B,A
        JR latch_dim

latch_row_dim_tiny:
        LD B,8

latch_dim:
        LD A,(CFG_FLAGS)
        AND 3
        CP 3
        JR z,latch_row          ; full: LIT_LIMIT is 0 (cmd_B6_config clears it)
        BIT 3,B
        JR z,lit_set
        LD B,A
        ADD A,A
        ADD A,B

lit_set:
        LD (LIT_LIMIT),A
        LD A,C
        LD (LATCH_PENDING),A
        RET

; ---- rx_fifo_get: Pop one byte from RX_FIFO into RX_BYTE. Returns NC with A=byte, or C if empty
rx_fifo_get:
        DI                      ; P30: the ISR appends to the FIFO
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
        EI
        LD A,(RX_BYTE)
        OR A
        RET

rx_fifo_empty:
        EI
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
        LD D,A                  ; P41: a status report streaming: the ACK follows it
        LD A,(TX_ACTIVE)
        OR A
        LD A,D
        JR z,pkt_send_now
        LD (TX_DONE_PENDING),A
        JR pkt_check_ok

pkt_send_now:
        CALL tx_send_byte

pkt_check_ok:
        LD HL,STAT_PKT_OK       ; P40
        LD A,E
        AND A
        JR z,pkt_count
        INC HL                  ; STAT_PKT_BAD

pkt_count:
        INC (HL)
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
tx_send_frame:                  ; ota_reply, its one caller, keeps nothing
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
        JP tx_send_byte

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
        XOR A
        LD (NMI_COUNT),A
        LD HL,STAT_MERGE        ; P40: roll the merge count, keep the worst, count uptime
        LD A,(HL)
        LD (HL),0
        INC HL
        LD (HL),A               ; STAT_MERGE_LAST
        INC HL
        CP (HL)                 ; STAT_MERGE_MAX
        JR c,clock_uptime
        LD (HL),A

clock_uptime:
        INC HL                  ; STAT_UPTIME, 3 bytes
        INC (HL)
        JR nz,clock_uptime_done
        INC HL
        INC (HL)
        JR nz,clock_uptime_done
        INC HL
        INC (HL)

clock_uptime_done:
        CALL baud_calibrate     ; P30: a second of NMIs has passed
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
        DEC HL                  ; CLK_H1
        INC (HL)
        LD A,(CLK_PM)
        AND CLK_24H
        JR nz,clk_hours_24
        LD A,(HL)
        CP 10
        JR nz,clk_check_12h
        LD (HL),0               ; 9 -> 10
        DEC HL
        LD (HL),1
        RET

clk_check_12h:
        DEC HL                  ; CLK_H10
        CP 3
        JR z,clk_wrap_13
        CP 2
        RET nz
        LD A,(HL)
        AND A
        RET z
        LD A,(CLK_PM)           ; 11:59 -> 12:00 flips AM/PM; the mode bit stays
        XOR 1
        LD (CLK_PM),A
        RET

clk_wrap_13:
        LD A,(HL)
        AND A
        RET z
        XOR A
        LD (HL),A               ; 13 -> 1
        INC A
        INC HL
        LD (HL),A
        RET

clk_hours_24:                   ; P32: 00..23
        LD A,(HL)
        CP 10
        JR z,clk_h1_wrap
        CP 4
        RET nz
        DEC HL
        LD A,(HL)
        CP 2
        RET nz
        LD (HL),0               ; 24:00 -> 00:00
        INC HL
        LD (HL),0
        RET

clk_h1_wrap:
        LD (HL),0
        DEC HL
        INC (HL)
        RET

; ---- scroll_off_text: push the displayed text off by rendering 14 spaces
scroll_off_text:
        LD B,14
        LD A,0
        LD (FONT_MODE),A

scrolloff_loop:
        LD A,' '
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
        XOR A
        LD (SVC_ACTIVE),A       ; P26: entered from rx_consume inside the service
        LD A,0xff
        LD (MENU_ACTIVE),A
        EI
        LD E,A                  ; P41: FF = playback stopped
        CALL status_send
        CALL init_render
        LD A,(IR_CODE)
        CP IR_CODE_STOP
        JR nz,editor_init
        CALL beep_start

editor_stop_wait:
        LD A,0xfe
        LD (IR_CODE),A
        LD HL,0x01a0
        LD (GEN_COUNTDOWN),HL

editor_stop_poll:
        LD A,(IR_CODE)
        CP IR_CODE_STOP
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
        CALL is_marker
        JR nc,editor_scan_back
        DEC HL
        DEC HL
        LD A,(HL)
        CALL is_marker
        JR nc,editor_cursor_set
        DEC HL
        LD (STORE_CURSOR),HL
        JR editor_marker_skip

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
        CALL is_marker
        JR c,editor_set_ins

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
        CALL dispatch
        DKEY 1, editor_next_key
        DKEY 3, menu_clear_all
        DKEY 5, show_top_of_msg
        DKEY KEY_DEL, editor_delete
        DKEY KEY_SHIFT, editor_key_shift
        DKEY 10, cursor_right
        DKEY 12, cursor_right_8
        DKEY 8, cursor_left
        DKEY 11, cursor_left_8
        DKEY 14, editor_clear_msg
        DKEY KEY_EURO, editor_toggle_euro
        DKEY 0x5e, menu_address
        DKEY KEY_CASE, editor_toggle_caps
        DKEY ATTR_GRAPH, editor_key_graph
        DKEY ATTR_COLOR, editor_key_color
        DKEY ATTR_BGRND, editor_key_bgrnd
        DKEY 0x17, menu_time
        DKEY 2, editor_key_speed
        DKEY 0xb3, editor_goto_end
        DKEY KEY_FUNC, editor_key_func
        DKEY 9, menu_prog_msg
        DKEY 4, menu_seq_msg
        DKEY 13, editor_exit
        DKEY 0x9f, editor_loop
        DKEY 0xb1, editor_exit
        db 0xff
        JP editor_insert

; ---- magic_new_message: MAGIC as first key: take the first empty channel
;      (or ask via FULL!! MSG# ?), make it the whole sequence
magic_new_message:
        LD A,(CHAN_LOCK)
        OR A
        JR nz,newmsg_from_0
        LD A,(EDITOR_FIRST_KEY)
        AND A
        RET z

newmsg_from_0:
        XOR A

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
        CALL char_flags
        JR z,newmsg_next_chan

newmsg_skip_attrs:
        INC HL
        LD A,(HL)
        CP TEXT_END
        JR nz,newmsg_skip_next
        LD A,E
        JR newmsg_select

newmsg_skip_next:
        CALL char_flags
        JR nz,newmsg_skip_attrs

newmsg_next_chan:
        LD A,E
        INC A
        CP CHAN_DEMO
        JR nz,newmsg_try_chan
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL

newmsg_ask_full:
        LD HL,MENU_STR_MSG_FULL
        CALL menu_ask_chan
        CP CHAN_DEMO
        JR nc,newmsg_ask_full

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
        JR newmsg_set_seq

newmsg_empty_found:
        LD (INS_PTR),HL
        DEC HL
        DEC HL
        LD (STORE_CURSOR),HL

newmsg_set_seq:
        CALL chan_lock_set
        LD A,E
        CALL seq_list_one
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

; ---- store_delete_text: remove the text from HL to its 03 by moving the tail of
;      the store (the 03 up to its DA) down over it, then fix STORE_END. Z with
;      nothing done if no 03 lies below STORE_LIMIT (a corrupt store)
store_delete_text:
        PUSH HL
        EX DE,HL
        LD HL,(STORE_LIMIT)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        INC BC
        EX DE,HL
        LD A,TEXT_END
        CPIR
        LD A,B
        OR C
        POP DE                  ; the destination
        RET z
        DEC HL                  ; HL = the 03
        PUSH DE
        EX DE,HL                ; DE = the 03
        LD HL,(STORE_END)
        INC HL
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        INC BC                  ; the 03 .. the DA, and one more
        EX DE,HL                ; HL = the 03
        POP DE                  ; DE = the destination
        LDIR
        JR store_finalize       ; returns NZ

; ---- is_marker: CY if A is a channel marker byte, D0-DA (A is lost)
is_marker:
        SUB MARK_LO
        CCF
        RET nc
        CP MARK_HI-MARK_LO+1
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
        JR exit_add_to_seq

exit_wait_release:
        LD A,(IR_CODE)
        CP ATTR_TINY
        JR z,exit_add_to_seq
        CP IR_CODE_STOP
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
        CP IR_CODE_STOP
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
        JR nz,exit_to_display
        LD HL,(INS_PTR)
        DEC HL
        DEC HL
        LD B,2
        CALL ascii_dec_to_bin
        LD E,A
        LD HL,SEQ_LIST
        CP (HL)
        JR z,exit_to_display
        LD A,CHAN_DEMO
        CP (HL)
        JR nz,exit_seq_search
        LD A,E
        JR exit_seq_first

exit_seq_search:
        LD B,SEQ_LIST_LEN

exit_seq_loop:
        LD A,(HL)
        CP E
        JR z,exit_seq_found
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
        JR exit_to_display

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
        LD HL,MENU_STR_TIME
        CALL menu_prompt
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
        LD A,(CFG_HOLD)         ; P35
        LD (FRAME_DELAY),A

        CALL wait_frame_delay
        LD HL,MENU_STR_AM_PM
        CALL menu_prompt

time_get_ampm:
        CALL menu_getchar
        RES 5,A
        CP 'Y'
        JR nz,time_check_n
        XOR A
        JR time_store_pm

time_check_n:
        CP 'N'
        JR nz,time_get_ampm
        LD A,1                  ; P32: PM; the editor sets the 12-hour mode

time_store_pm:
        LD (CLK_PM),A
        XOR A
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
        LD A,(CLK_PM)
        AND CLK_24H             ; P32: 24-hour keeps the leading zero
        OR (HL)
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
        JR clock_emit

clock_not_colon:
        CP 6
        JR nz,clock_not_space
        LD A,' '
        LD (CUR_CHAR),A
        JR clock_emit

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
        OR '0'
        LD (CUR_CHAR),A
        INC HL
        LD A,(CLK_RENDER_STEP)
        LD (CLK_RENDER_PTR),HL
        CP 5
        JR nz,clock_emit
        LD A,(CLK_PM)
        AND CLK_24H             ; P32: 24-hour ends at the last minute digit:
        JR nz,clock_emit_last   ; no space, no AM or PM

clock_emit:
        CALL unfetch_char
        LD A,(CUR_CHAR)

glyph_lookup_jr15:
        JP glyph_lookup

clock_emit_last:
        LD A,0xff
        LD (CLK_RENDER_STEP),A
        LD A,(CUR_CHAR)
        JR glyph_lookup_jr15

; ---- menu_ask_chan_cur: ask for a channel number, prefilled from INS_PTR
menu_ask_chan_cur:
        LD (ASK_CHAN_PROMPT),HL
        JR askchan_prefill

; ---- menu_ask_chan: ask for a channel number; returns 0-99, 64 demo,
;      97 SEQ key, 98 MAGIC key, 99 A(ll), 9A blank + enter
menu_ask_chan:                  ; the callers keep nothing in the registers
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
        OR '0'

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
        OR '0'

askchan_store_tens:
        LD (CHAN_D10),A

askchan_show:
        LD HL,(ASK_CHAN_PROMPT)
        CALL menu_prompt
        LD B,2
        LD HL,CHAN_D10

askchan_digits_loop:
        LD A,(HL)
        CALL glyph_put_next
        DJNZ askchan_digits_loop

askchan_key:
        CALL menu_getchar
        LD (CUR_CHAR),A
        CALL dispatch
        DKEY 4, askchan_seq_key
        DKEY 8, askchan_accept
        DKEY 9, askchan_accept
        DKEY 13, askchan_enter
        DKEY 14, askchan_clear
        DKEY ATTR_MAGIC, askchan_magic_key
        DKEY KEY_DEL, askchan_backspace
        DKEY 'A', askchan_all
        DKEY 'a', askchan_all
        DKEY 'D', askchan_demo
        DKEY 'd', askchan_demo
        db 0xff
        CALL is_digit           ; A is still the key
        JR nc,askchan_key
        LD IX,CHAN_D10
        LD A,(IX+1)
        LD (IX+0),A
        LD A,(CUR_CHAR)
        LD (IX+1),A
        JR askchan_show

askchan_backspace:
        LD IX,CHAN_D10
        LD A,(IX+0)
        LD (IX+1),A
        LD (IX+0),0x30
        JR askchan_show

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
        RET

askchan_clear:
        LD A,' '
        LD (CHAN_D10),A
        LD (CHAN_D1),A
        JP askchan_show

askchan_enter:
        LD A,(CHAN_D1)
        CP 0x20
        JR nz,askchan_accept
        LD A,0x9a
        RET

askchan_all:
        LD A,0x99
        RET

askchan_demo:
        LD A,CHAN_DEMO
        RET

askchan_seq_key:
        LD A,0x97
        RET

askchan_magic_key:
        LD A,0x98
        RET

; ---- menu_address: 5E (FUNC+MAGIC): ADDRESS? 1-255, never 0 or 2A
menu_address:
        LD HL,MENU_STRINGS
        CALL menu_prompt
        LD H,0
        LD A,(MY_ADDRESS)
        OR A
        JR z,addr_default_1
        CP ADDR_BROADCAST
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
        CP '0'
        JR nz,addr_show_loop
        LD A,B
        CP 1
        JR z,addr_show_loop
        INC HL
        DJNZ addr_skip_zeros

addr_show_loop:
        LD A,(HL)
        CALL is_digit
        JR c,addr_show_digit
        LD A,'0'
        LD (HL),A

addr_show_digit:
        CALL glyph_put_next
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
        JR z,menu_addr_invalid
        INC B
        LD A,(CUR_CHAR)
        CALL is_digit
        JR nc,menu_addr_invalid
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
        CALL menu_show_text

addr_echo_digit:
        CALL glyph_lookup
        JR addr_key

addr_enter:
        LD A,B
        OR A
        JR nz,addr_convert
        LD B,3

addr_convert:
        LD HL,MENU_ENTRY_BUF
        CALL ascii_dec_to_bin
        JR c,menu_addr_invalid
        CP ADDR_BROADCAST
        JR z,menu_addr_invalid
        OR A
        JR z,menu_addr_invalid
        LD (MY_ADDRESS),A
        CALL cfg_seal           ; P35
        JR editor_reshow

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
        OR A
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
        CP '9'+1
        JR nc,not_digit
        CP '0'
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

; ---- editor_back_if_mark: HL = STORE_CURSOR; on a channel marker step back and show TOP
editor_back_if_mark:
        LD A,(HL)
        CALL is_marker
        JP nc,editor_loop
        DEC HL
        LD (STORE_CURSOR),HL
        JR show_top_of_msg

editor_reshow:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CALL is_marker
        JP nc,editor_loop

; ---- show_top_of_msg: 05 and after most edits: "TOP OF MSG nn"
show_top_of_msg:
        LD HL,STR_TOP_OF_MSG
        CALL menu_prompt
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
        OR '0'
        CALL is_digit
        JR c,top_emit
        LD A,'0'
        LD (HL),A

top_emit:
        CALL glyph_put_next
        DJNZ top_digit_loop
        JP editor_next_key

; ---- menu_clear_all: 03: CLR ALL Y/N
menu_clear_all:
        LD HL,MENU_STR_CLR_ALL
        CALL menu_prompt
        CALL menu_getchar
        AND 0x5f
        CP 'Y'
        JP nz,editor_loop
        CALL store_clear_all
        CALL store_finalize
        XOR A
        JP editor_select_chan

editor_clear_msg:
        LD A,(CHAN_LOCK)
        OR A
        JR nz,editor_reshow
        CALL delete_chan_text
        JR show_top_of_msg

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
        CALL is_marker
        JR c,deltext_marker_end

deltext_back:
        DEC HL
        DEC BC
        LD A,B
        OR C
        JP z,pkt_process_end
        JR deltext_find_marker

deltext_marker_end:
        INC HL
        LD A,(HL)
        CALL is_marker
        JR c,deltext_move

deltext_one_byte:
        DEC HL

deltext_move:
        LD (STORE_CURSOR),HL
        INC HL
        CALL store_delete_text
        JP z,pkt_process_end
        LD HL,(STORE_CURSOR)
        DEC HL
        LD (STORE_CURSOR),HL
        RET

editor_toggle_caps:
        LD A,(CAPS_LOCK)
        CPL
        LD (CAPS_LOCK),A


editor_reshow_jr14:
        JP editor_reshow

editor_toggle_euro:
        LD A,(EURO_STATE)
        CPL
        LD (EURO_STATE),A
        JR editor_reshow_jr14

editor_key_speed:
        LD DE,SPEED_PENDING
        JR editor_set_pending

editor_key_graph:
        LD DE,GRAPH_PENDING
        JR editor_set_pending

editor_key_color:
        LD DE,COLOR_PENDING
        JR editor_set_pending

editor_key_func:
        LD A,0xff
        LD (FUNC_PENDING),A

editor_loop_jr12:
        JP editor_loop

editor_key_bgrnd:
        LD DE,BGRND_PENDING

; ---- editor_set_pending: DE = a prefix flag; set it unless at the end or on a locked channel
editor_set_pending:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JR z,editor_loop_jr12
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_show_invalid
        LD A,0xff
        LD (DE),A
        JR editor_loop_jr12

; ---- menu_prog_msg: 09: PROG MSG? channel
menu_prog_msg:
        LD HL,MENU_STR_PROG_MSG
        CALL menu_ask_chan_cur
        CP CHAN_DEMO+1
        JR nc,menu_prog_msg
        LD E,A

editor_select_chan:
        CALL chan_open
        JP show_top_of_msg

; ---- menu_seq_msg: 04: SEQ MSG? channels until blank+enter; A = all
menu_seq_msg:
        LD A,0xff
        LD (SEQ_SET),A
        LD A,0xff
        CALL seq_list_one       ; empty: FF throughout
        LD (SEQ_MENU_ACTIVE),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        LD B,SEQ_LIST_LEN-1

seqmenu_loop:
        PUSH BC
        LD HL,MENU_STR_SEQ_MSG
        LD A,B
        CP SEQ_LIST_LEN-1
        JR z,seqmenu_first
        CALL menu_ask_chan
        JR seqmenu_result

seqmenu_first:
        CALL menu_ask_chan_cur

seqmenu_result:
        POP BC
        CP 0x98
        JR z,seqmenu_done       ; P29: MAGIC used to open the factory test prompt
        CP 0x97
        JR z,seqmenu_done
        CP 0x99
        JR z,seqmenu_all
        CP 0x9a
        JR z,editor_exit_jr17
        LD HL,(SEQ_PTR)
        LD (HL),A
        INC HL
        LD (SEQ_PTR),HL
        DJNZ seqmenu_loop
        LD HL,MENU_STR_SEQ_FULL
        CALL menu_show_text
        CALL fb_rewind_window

seqmenu_done:
        XOR A
        LD (SEQ_MENU_ACTIVE),A
        JP editor_reshow

seqmenu_all:
        CALL seq_list_default

editor_exit_jr17:
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
        JR c,getkey_ir
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
        JR getkey_check_shift

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
        JR getkey_history

getkey_translate:
        LD HL,IR_KEY_TABLE
        LD D,0
        LD E,A
        ADD HL,DE
        LD E,(HL)               ; the key's position in the layers
        LD A,(EURO_STATE)
        LD HL,CHARSET_EURO
        OR A
        JR nz,getkey_lookup
        LD A,(SHIFT_STATE)
        LD HL,CHARSET_LOWER
        AND A
        JR z,getkey_lookup
        LD HL,CHARSET_LOWER2

getkey_lookup:
        ADD HL,DE
        LD A,(HL)
        LD C,A
        LD HL,CAPS_LOCK         ; the layers hold lower case: upper when exactly
        LD A,(SHIFT_STATE)      ; one of SHIFT and CAPS is on
        XOR (HL)
        LD A,C
        JR z,getkey_store
        CP 'a'
        JR c,getkey_store
        CP 'z'+1
        JR nc,getkey_store
        AND 0xdf

getkey_store:
        LD (IR_KEY_CHAR),A
        XOR A
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
        db 0x2f,0x13,0x2c,0x2b,0x2d,0x29,0x2a,0x2e,0x24,0x23,0x1c,0x1b,0x1d,0x19,0x1a,0x22   ; P36: 1D is SHIFT, caught before the table: its entry finds the keypad's SHIFT
        db 0x31,0x30,0x37,0x36,0x35,0x08,0x32,0x34,0x01,0x00,0x07,0x06,0x05,0x38,0x02,0x04
        db 0x11,0x10,0x17,0x16,0x15,0x28,0x12,0x14,0x21,0x20,0x27,0x26,0x25,0x18

editor_key_shift:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JR z,editor_loop_jr11
        LD A,(SHIFT_STATE)
        OR A
        JR z,shift_done
        LD A,0xff
        LD (SHIFT_LABEL),A
        LD HL,STR_SHIFT
        LD (MENU_MSG_PTR),HL

shift_done:
        JR editor_loop_jr11

; ---- editor_delete: 7F: delete the byte under the cursor
editor_delete:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_reshow
        CALL latch_blank
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JR z,editor_loop_jr11
        CALL is_marker
        JR c,show_top_of_msg_jr24

delete_do:
        XOR A
        LD (DISP_ON),A
        LD HL,(STORE_END)
        DEC HL
        LD (STORE_END),HL
        CALL unfetch_char
        LD HL,(STORE_END)       ; already one less: END - cursor = cursor+2 .. the old DA
        LD DE,(STORE_CURSOR)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        LD HL,(STORE_CURSOR)
        INC HL
        LD D,H
        LD E,L
        INC HL
        LDIR
        LD A,0xff
        LD (DISP_ON),A
        LD HL,(STORE_CURSOR)
        JP editor_back_if_mark

; ---- cursor_right: 0A
cursor_right:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JR z,cursor_right_done
        INC HL
        LD A,(HL)
        CALL is_marker
        JR nc,cursor_right_set
        INC HL

cursor_right_set:
        LD (STORE_CURSOR),HL

cursor_right_done:

editor_loop_jr11:
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
        JR editor_loop_jr11

; ---- cursor_left: 08
cursor_left:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CALL is_marker
        JR c,show_top_of_msg_jr16

cursor_left_do:
        DEC HL
        LD (STORE_CURSOR),HL
        LD A,(HL)
        CALL is_marker
        JR nc,editor_loop_jr11
        DEC HL
        LD (STORE_CURSOR),HL

show_top_of_msg_jr16:

show_top_of_msg_jr24:
        JP show_top_of_msg

; ---- cursor_left_8: 0B
cursor_left_8:
        LD B,8
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CALL is_marker
        JR c,show_top_of_msg_jr16

left8_step:
        DEC HL
        LD (STORE_CURSOR),HL
        LD A,(HL)
        CALL is_marker
        JR nc,cursor_left_8
        DEC HL
        LD (STORE_CURSOR),HL
        JR show_top_of_msg_jr16

; ---- editor_insert: insert EDIT_KEY at the cursor (MEMORY FULL / 100 KEYS LEFT)
editor_insert:
        LD (CUR_CHAR),A
        LD A,(CHAN_LOCK)
        OR A
        JP nz,editor_reshow
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP TEXT_END
        JR z,insert_done
        CALL is_marker
        JR nc,insert_do
        INC HL
        LD (STORE_CURSOR),HL

insert_do:
        CALL latch_blank
        XOR A
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

editor_loop_jr13:
        JP editor_loop

insert_shift:
        LD HL,(STORE_TMP)
        LD (STORE_END),HL       ; the DA moves up one
        CALL store_make_room
        LD HL,(STORE_TMP)
        LD DE,(STORE_CURSOR)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L                  ; the cursor .. the old DA
        LD HL,(STORE_TMP)
        LD D,H
        LD E,L
        DEC HL
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
        JR editor_loop_jr13

; ---- store_make_room
store_make_room:
        LD HL,(STORE_CURSOR)
        LD DE,(STORE_LIMIT)
        INC HL
        LD (STORE_CURSOR),HL
        OR A
        SBC HL,DE
        RET nz
        LD A,(MENU_ACTIVE)
        AND A
        RET nz
        LD HL,MSG_STORE
        LD (STORE_CURSOR),HL

makeroom_ret:
        RET

; ---- editor_translate_key: apply the GRAPH/COLOR/BGRND/SPEED/FUNC prefixes
editor_translate_key:
        CALL apply_graph_prefix
        CALL apply_color_prefix
        CALL apply_speed_prefix
        JR editor_key_to_attr

; ---- apply_graph_prefix: GRAPH n -> A0|n
apply_graph_prefix:
        LD A,(GRAPH_PENDING)
        OR A
        RET z
        LD A,(EDIT_KEY)
        AND 15
        OR GRAPH_BASE
        LD (EDIT_KEY),A
        XOR A
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
        LD HL,FUNC_TABLE

func_search:
        LD C,(HL)
        INC HL
        INC C                   ; FF: not a second function
        JR z,func_cancel
        DEC C
        CP C
        JR z,func_store
        INC HL
        JR func_search

func_cancel:
        POP HL
        POP HL
        JP editor_reshow

func_store:
        LD A,(HL)
        LD (EDIT_KEY),A
        RET

; ---- FUNC_TABLE: key, the attribute FUNC turns it into
FUNC_TABLE:
        db ATTR_GRAPH, ATTR_DRAW
        db ATTR_NORM, ATTR_DRAW+1
        db ATTR_PAUSE, ATTR_DRAW+1+1
        db ATTR_FLASH, ATTR_REM
        db ATTR_BOLD, 6
        db ATTR_COLOR, ATTR_RAINBOW
        db 0x8f, ATTR_RAINBOW
        db 0x51, '?'
        db 0x71, '?'
        db 0x58, '!'
        db 0x78, '!'
        db ATTR_MAGIC, 0x5e
        db ATTR_BIG, ATTR_TINY
        db 0xff

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

; ---- data 2718-2721: cmd 15 n: foreground color codes (Red,Orange,Yellow,Lime,Green,84,8E,Black,8B,81)
FG_IDX_TABLE:
        db 0x8c,0x8d,0x8f,0x87,0x83,0x84,0x8e,0x80,0x8b,0x81

; ---- data 2722-2727: cmd 16 n: background color codes
BG_IDX_TABLE:
        db 0x91,0x93,0x93,0x93,0x92,0x90

; ---- editor_redraw: Redraw the editor view of the current message
editor_redraw:
        CALL clear_txbuf
        CALL init_render
        XOR A
        LD (DISP_ON),A
        CALL latch_blank
        LD A,(SEQ_MENU_ACTIVE)
        BIT 7,A
        JP nz,redraw_status
        LD A,(MAGIC_MSG_CHAN)
        AND A
        JP nz,redraw_status
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CALL is_marker
        JP c,redraw_status

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
        CP ' '
        JR nz,redraw_classify
        LD A,(REDRAW_MAGIC)
        AND A
        JR z,redraw_char_check_jr18
        XOR A
        LD (FORCE_BOLD),A
        LD (FONT_MODE),A

redraw_char_check_jr18:
        JP redraw_char_check

redraw_classify:
        BIT 7,A
        JR nz,redraw_high
        AND 0x60
        JR z,redraw_attr
        JR redraw_char_check_jr18

redraw_high:
        LD A,(CUR_CHAR)
        CP 0x94
        JR c,redraw_attr
        CP 0x9f
        JR c,redraw_char_check_jr18
        AND 0xf0
        CP 0xc0
        JR z,redraw_char_check_jr18
        CP 0xe0
        JR z,redraw_char_check_jr18
        CP 0xd0
        JR z,redraw_char_check_jr18
        CP GRAPH_BASE
        JR z,redraw_char_check_jr18

redraw_attr:
        LD A,(CUR_CHAR)
        CP ATTR_COLOR
        JR z,redraw_char_check_jr18
        CP ATTR_BGRND
        JR z,redraw_char_check_jr18
        CP ATTR_MAGIC_OFF
        JR nz,redraw_attr2
        XOR A
        LD (REDRAW_MAGIC),A
        LD A,(CUR_CHAR)

redraw_attr2:
        CP 15
        JR z,redraw_fx_attr
        CP ATTR_PAUSE
        JR z,redraw_fx_attr
        CP ATTR_UP
        JR z,redraw_fx_attr
        CP ATTR_DOWN
        JR z,redraw_fx_attr
        CP ATTR_LEFT
        JR z,redraw_left_attr
        CP ATTR_NORM
        JR nz,redraw_not_norm
        XOR A
        LD (FLASH_BIT),A
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_not_norm:
        CP ATTR_FLASH
        JR nz,redraw_not_flash
        LD A,COLOR_FLASH
        LD (FLASH_PENDING),A
        JR redraw_label_check

redraw_not_flash:
        CP ATTR_ITALIC
        JR nz,redraw_not_italic
        LD A,CHAN_DEMO
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_not_italic:
        CP ATTR_BOLD
        JR nz,redraw_not_bold
        LD A,2
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_not_bold:
        CP ATTR_BIG
        JR nz,redraw_not_big
        LD A,10
        LD (FONT_MODE),A
        JR redraw_label_check

redraw_not_big:
        CP ATTR_THIN
        JR nz,redraw_not_thin
        LD A,0xff
        LD (THIN_MODE),A
        XOR A
        LD (FORCE_BOLD),A
        JR redraw_label_check

redraw_not_thin:
        CP ATTR_MAGIC
        JR nz,redraw_label_check
        XOR A
        LD (FONT_MODE),A
        LD A,0xff
        LD (REDRAW_MAGIC),A
        JR redraw_label_check

redraw_fx_attr:
        LD A,(THIN_MODE)
        AND A
        JR nz,redraw_label_check
        LD A,0xff
        LD (FORCE_BOLD),A
        JR redraw_label_check

redraw_left_attr:
        XOR A
        LD (FORCE_BOLD),A

redraw_label_check:
        CALL redraw_in_window
        JR c,redraw_next

redraw_show_label:
        LD A,(CUR_CHAR)
        AND 0xf8
        CP SPEED_BASE
        JR z,redraw_speed_label
        LD A,(CUR_CHAR)
        LD D,A
        LD HL,LABELS

label_search:
        LD A,(HL)
        INC HL
        INC A                   ; FF: the end, nothing to show
        JR z,redraw_next
        DEC A
        CP D
        JR z,label_found
        XOR A
        LD BC,0x10              ; skip the text and its NUL
        CPIR
        JR label_search

label_found:
        CALL show_label
        JR redraw_next

redraw_speed_label:
        LD HL,STR_S
        CALL show_label
        LD A,(CUR_CHAR)
        AND 7
        OR '0'
        CALL glyph_put_next
        LD HL,STR_CLOSE
        CALL menu_show_text
        JR redraw_next

redraw_char_check:
        CALL redraw_in_window
        JR c,redraw_next

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
        LD A,(FUNC_PENDING)
        OR A
        JR z,status_not_func
        LD HL,STR_FUNC
        JR status_show

status_not_func:
        LD A,(EURO_STATE)
        OR A
        JR z,status_not_euro
        LD HL,STR_EURO
        JR status_show

status_not_euro:
        LD A,(SPEED_PENDING)
        OR A
        JR z,status_not_speed
        LD HL,STR_SPEED
        JR status_show

status_not_speed:
        LD A,(MAGIC_MSG_CHAN)
        OR A
        JR z,status_shift_msg
        XOR A
        LD (MAGIC_MSG_CHAN),A
        LD HL,STR_MAGIC_MSG
        CALL menu_prompt
        LD B,2
        LD HL,(INS_PTR)
        DEC HL
        DEC HL

magicmsg_digits:
        LD A,(HL)
        AND 15
        OR '0'
        CALL glyph_put_next
        DJNZ magicmsg_digits
        JR status_shift_msg

status_show:
        CALL show_label

status_shift_msg:
        LD A,(SHIFT_LABEL)
        AND A
        JR z,status_menu_msg
        LD HL,(MENU_MSG_PTR)
        CALL show_label

status_menu_msg:
        LD A,(MENU_MSG_FLAG)
        OR A
        JR z,redraw_finish
        LD HL,(MENU_MSG_PTR)
        CALL menu_show_text

redraw_finish:
        CALL fb_rewind_window
        LD A,(MENU_MSG_FLAG)
        OR A
        JR z,redraw_ret
        CALL redraw_hold
        XOR A
        LD (MENU_MSG_FLAG),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CALL is_marker
        JR nc,redraw_again
        POP HL
        JP show_top_of_msg

redraw_again:
        JP editor_redraw

redraw_ret:
        LD A,0xff
        LD (DISP_ON),A
        RET

; ---- redraw_in_window: CY if the byte at REDRAW_PTR lies before REDRAW_FROM (not shown)
redraw_in_window:
        LD HL,(REDRAW_PTR)
        LD DE,(REDRAW_FROM)
        OR A
        SBC HL,DE
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
        LD A,(CFG_HOLD)         ; P35
        LD (FRAME_DELAY),A

        CALL wait_frame_delay
        RET

; ---- menu_prompt: HL = string: start a fresh frame and show it
menu_prompt:
        PUSH HL
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        POP HL

; ---- menu_show_text: Render the NUL-terminated string at HL in tiny font
menu_show_text:
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
        JR showtext_loop

showtext_done:
        POP AF
        LD (CUR_CHAR),A
        POP AF
        LD (TINY_MODE),A
        RET

; ---- show_label: the bracket glyph 15, then the text at HL
show_label:
        PUSH HL
        LD HL,STR_BRACKET
        CALL menu_show_text
        POP HL
        JR menu_show_text

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
        RET nc
        LD DE,FRAMEBUF_END
        ADD HL,DE
        LD (FB_COL),HL

rewind_ret:
        RET

; ---- dispatch: A against the table that follows the CALL (DISP key, target;
;      FF ends it). A match jumps to its target with A kept and Z set; with no
;      match the code after the table runs. B is lost.
dispatch:
        EX (SP),HL              ; HL = the table, the caller's HL under it
        LD B,A

dispatch_loop:
        LD A,(HL)
        INC HL
        INC A                   ; FF: the end
        JR z,dispatch_end
        DEC A
        CP B
        JR z,dispatch_found
        INC HL
        INC HL
        JR dispatch_loop

dispatch_found:
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A

dispatch_end:
        LD A,B
        EX (SP),HL              ; the caller's HL back; the destination on the stack
        RET

; ---- pkt_process_end
pkt_process_end:
        JP RESET

; ---- pkt_process: Process a received packet: walk PKT_BUF byte by byte. Bytes in IGNORE_TABLE are skipped; command bytes dispatch (02 speed,03 clear all,04 sequence,09 channel,0D end,0E delete channel text,15 fg idx,16 bg idx,17 time,1E A0-color,B3 append,B4 query,B5 OTA); anything else is inserted as message text
pkt_process:
        ; P21: called from the render loop with interrupts on. The renderer is
        ; suspended until this returns, and nothing in the tick service reads
        ; the store, so the edits below need no DI. Its pointers are saved and
        ; put back (shifted if a lower channel changed size) unless the text
        ; under it changed, which restarts the display as before.
        LD A,(TX_ACTIVE)        ; P41: a status report still streaming: let it finish
        OR A
        JR nz,pkt_process
        LD (PKT_READY),A
        LD (PKT_RESTART),A
        LD (PKT_DONE_WANT),A
        LD (PKT_SEQ_CHANGED),A
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
        LD A,(CHAN_LOCK)        ; P27: put back with the cursor unless the display restarts
        LD (PKT_SAVE_LOCK),A
        LD HL,0xffff
        LD (PKT_LOW_EDIT),HL
        LD HL,(STORE_CURSOR)
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        JR nc,pkt_cursor_in_store
        CALL clear_chan_lock    ; P24: the renderer is in ROM (demo) or the test
        LD HL,MSG_STORE+1       ; buffer, and the demo channel's lock is on: take
        JR pkt_set_ins          ; channel 0, seated as 09 30 30 0E leaves it

pkt_cursor_in_store:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CALL is_marker
        JR nc,pkt_find_marker
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
        CALL is_marker
        JR c,pkt_set_ins

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
        CALL dispatch
        DKEY CMD_SPEED, cmd_02_speed
        DKEY CMD_CLEAR_ALL, cmd_03_clear_all
        DKEY CMD_SEQUENCE, cmd_04_sequence
        DKEY CMD_CHANNEL, cmd_09_channel
        DKEY CMD_END, pkt_done_pop
        DKEY CMD_DELETE_TEXT, cmd_0E_delete_text
        DKEY CMD_FORE_IDX, cmd_15_fore_idx
        DKEY CMD_BACK_IDX, cmd_16_back_idx
        DKEY CMD_SET_TIME, cmd_17_set_time
        DKEY CMD_COLOR_A0, cmd_1E_color_A0
        DKEY CMD_APPEND, cmd_B3_append
        DKEY CMD_QUERY, cmd_B4_query
        DKEY CMD_OTA, cmd_B5_ota
        DKEY CMD_CONFIG, cmd_B6_config
        db 0xff

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

; ---- pkt_insert_one: insert CUR_CHAR (the color and speed commands)
pkt_insert_one:
        LD HL,CUR_CHAR
        LD BC,1

; ---- pkt_insert_run: BC bytes at HL go in after STORE_CURSOR, which then
;      points at the last of them. The payload position advances past them.
pkt_insert_run:
        LD A,(CHAN_LOCK)
        OR A
        JR nz,pkt_next
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
        JR pkt_next

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
        AND DONE_BYTE
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
        LD A,(PKT_SAVE_LOCK)    ; P27: cmd_09 and the P24 entry path clear the lock;
        LD (CHAN_LOCK),A        ; the renderer keeps the channel it was playing
        LD HL,(STORE_END)
        LD DE,(PKT_SAVE_END)
        OR A
        SBC HL,DE
        JR nz,pkt_done_resized
        LD A,(SEQ_ALL_EMPTY)    ; P27: the store is unchanged, but a SEQ command, or
        LD B,A                  ; any packet while the demo plays, may change what
        LD HL,PKT_SEQ_CHANGED   ; there is to play: recount, and restart only when
        OR (HL)                 ; the answer flips between the demo and real text
        RET z
        PUSH BC
        CALL init_sequence
        POP BC
        LD A,(SEQ_ALL_EMPTY)
        CP B
        RET z                   ; same as before: a new sequence starts at the next channel
        JR pkt_done_restart

pkt_done_resized:
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
        JR nz,pkt_next_jr20
        LD HL,(INS_PTR)
        CALL pkt_note_edit
        DEC HL
        LD (STORE_CURSOR),HL
        INC HL
        CALL store_delete_text  ; a store without its 03 skips the command

pkt_next_jr20:
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
        CP QUERY_STATS
        JP z,pq_stats
        CP QUERY_CONFIG
        JR z,pq_config
        CP QUERY_SEQ
        JR z,pq_seq
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

pq_config:
        LD HL,CFG               ; P35
        LD BC,CFG_LEN
        JR pq_reply

pq_seq:
        LD HL,SEQ_LIST
        LD BC,SEQ_LIST_LEN
        JR pq_reply

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

pq_stats:
        LD IX,PKT_BUF+3         ; P30: the serial timing state, for the bench
        LD A,(BAUD_T)
        LD (IX+0),A
        LD A,(BAUD_STEP)
        LD (IX+1),A
        LD A,(BAUD_CAL_LAST)
        LD (IX+2),A
        LD A,(NMI_SEEN)
        LD (IX+3),A
        LD A,(NMI_PER_SEC)      ; P40: 60 mains, 64 the add-in board's crystal
        LD (IX+4),A
        LD A,(BOOT_COUNT)
        LD (IX+5),A
        LD HL,STACK_TOP-STACK_SIZE
        LD A,0x55
        LD B,STACK_CANARY

pq_canary:
        CP (HL)
        JR nz,pq_canary_end
        INC HL
        DJNZ pq_canary

pq_canary_end:
        LD A,STACK_CANARY
        SUB B
        LD (IX+6),A
        LD HL,STATS
        LD DE,PKT_BUF+3+7
        LD BC,STATS_LEN
        LDIR
        LD HL,PKT_BUF+3
        LD BC,7+STATS_LEN
        JP pq_reply

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
        JR z,ota_info
        CP 'C'
        JR z,ota_crc
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
        JR ota_reply

; ---- ota_trailer_copy: A = bank, DE = destination for 10 bytes; DE advances
ota_trailer_copy:
        LD HL,TRAILER
        LD BC,10

; ---- ota_copy: lib_copy with the NMI vector held off. The stub's NMI_VECTOR
;      jumps to this image's nmi_entry, and with the idle bank mapped in that
;      address holds whatever the other image has there (patch 35 moved it).
ota_copy:
        PUSH AF
        XOR A
        LD (NMI_MAGIC),A
        POP AF
        CALL lib_copy
        LD A,IR_CODE_SPACE
        LD (NMI_MAGIC),A
        RET

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
        JR ota_reply

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
        CALL ota_copy
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
        CALL clock_bank         ; P31: the writer's NMI sync needs the source on
        CALL lib_page_writer
        JR ota_status_jr21

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
        CALL clock_bank         ; P31
        CALL lib_page_writer

ota_status_jr21:
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
        JR c,ota_status_jr21         ; the stub is never written over the air
        LD A,C
        DEC A
        ADD A,B
        LD A,3
        JR c,ota_status_jr21         ; past the end of the bank
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
        JR nz,ota_status_jr21
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
        CALL clock_bank         ; P31
        CALL lib_page_writer    ; HL, DE preserved
        POP BC
        OR A
        JR nz,ota_status_jr21
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

ota_status_jr22:
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
        CP '?'
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
        JR nz,ota_status_jr22
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

; ---- cmd_1E_color_A0: 1E n -> insert 0xA0|(n&15)
cmd_1E_color_A0:
        CALL pkt_next_byte
        AND 15
        OR GRAPH_BASE
        LD (CUR_CHAR),A
        JR pkt_insert_one_jr23

; ---- cmd_15_fore_idx: 15 n -> insert FG_IDX_TABLE[n]
cmd_15_fore_idx:
        CALL pkt_next_byte
        LD HL,FG_IDX_TABLE
        JR idx_insert

; ---- cmd_16_back_idx: 16 n -> insert BG_IDX_TABLE[n]
cmd_16_back_idx:
        CALL pkt_next_byte
        LD HL,BG_IDX_TABLE

idx_insert:
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (CUR_CHAR),A

pkt_insert_one_jr23:
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
        LD C,CLK_24H
        CP 'H'                  ; P32: 24-hour, hours 00..23
        JR z,settime_store_pm
        LD C,0                  ; 'Y': AM
        CP 'Y'
        JR z,settime_store_pm
        LD C,1                  ; anything else: PM

settime_store_pm:
        LD A,C
        LD (CLK_PM),A
        XOR A                   ; P23: the new minute starts at :00, like the
        LD (CLK_SEC),A          ; host tool times the frame to land
        LD (NMI_COUNT),A
        LD A,0xff
        LD (CLK_RUN),A
        JR pkt_next_jr19

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
        JR pkt_insert_one_jr23

; ---- cmd_B6_config (P35): B6 index value -> the configuration block. The
;      signature, the address and the sum are not writable; CFG_FLAGS keeps its
;      live bits and takes only the brightness and mute bits.
cmd_B6_config:
        CALL pkt_next_byte
        LD C,A
        CALL pkt_next_byte
        LD B,A
        LD A,C
        CP 2
        JR c,cfg_cmd_done
        CP CFG_LEN-1
        JR nc,cfg_cmd_done
        LD HL,CFG
        LD E,A
        LD D,0
        ADD HL,DE
        CP 2
        JR nz,cfg_store
        LD A,(HL)
        AND 0xf0
        LD C,A
        LD A,B
        AND 0x0f
        OR C
        LD B,A
        XOR A
        LD (LIT_LIMIT),A        ; a brightness change: latch_row_dim re-arms, or not at full
        LD (LATCH_PENDING),A

cfg_store:
        LD (HL),B
        CALL cfg_seal

cfg_cmd_done:
        JR pkt_next_jr19

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

pkt_next_jr19:
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
        CALL chan_open
        JR pkt_next_jr19

; ---- cmd_04_sequence: 04 dd dd ... [D|d]: rebuild SEQ_LIST from 2-digit channel numbers
cmd_04_sequence:
        LD A,0xff
        LD (PKT_SEQ_CHANGED),A  ; P27: pkt_done_continue recounts the empty channels
        CALL seq_list_default
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        LD B,SEQ_LIST_LEN-1

seq_pair_loop:
        CALL pkt_next_byte
        CP 'D'
        JR z,seq_pair_demo
        CP 'd'
        JR z,seq_pair_demo
        LD (CUR_CHAR),A
        CP '9'+1
        JR nc,pkt_next_jr19
        CP '0'
        JR c,pkt_next_jr19
        AND 15
        LD (CHAN_D10),A
        CALL pkt_next_byte
        CP 'D'
        JR z,seq_pair_demo
        CP 'd'
        JR z,seq_pair_demo
        LD (CUR_CHAR),A
        CP '9'+1
        JR nc,pkt_next_jr19
        CP '0'
        JR c,pkt_next_jr19
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
        LD A,CHAN_DEMO

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
        db CMD_FORE_IDX,CMD_BACK_IDX,CMD_SET_TIME,CMD_COLOR_A0,CMD_APPEND,CMD_QUERY,CMD_OTA
        db CMD_CONFIG
COMMAND_TABLE_END:

; ---- is_plain_byte: Z if A is message text (neither ignored nor a command)
is_plain_byte:
        CP 0x20
        JR c,plain_lookup
        CP 0x7f
        JR nc,plain_lookup
        XOR A                   ; printable ASCII: never a command or ignored
        RET

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

; ============================================================================
;  Editor labels: the text the editor shows for an attribute byte, drawn by
;  show_label between the bracket glyphs 15 and 16 (the four a digit follows,
;  SPEED COLOR BGRND GRAPH, carry no 16). They are the sign's own words.
;  LABELS is one list searched by redraw_show_label: a key byte, the text, a
;  NUL; FF ends it. Speeds F0-F7 are drawn as S plus the digit. Stock indexed
;  four pointer tables, 594 bytes with their strings, for the same text.
; ============================================================================
LABELS:
        db TEXT_END,"END"
STR_CLOSE:
        db 0x16,0x00            ; also the closing bracket of a speed label
        db 0x06,"HALT",0x16,0x00
        db 0x07,"BEEP",0x16,0x00
        db 0x0f,"RIGHT",0x16,0x00
        db ATTR_BIG,"BIG",0x16,0x00
        db ATTR_NORM,"NORM",0x16,0x00
        db ATTR_BOLD,"BOLD",0x16,0x00
        db ATTR_ITALIC,"ITALIC",0x16,0x00
        db ATTR_FLASH,"FLASH",0x16,0x00
        db ATTR_LEFT,"LEFT",0x16,0x00
        db ATTR_PAUSE,"PAUSE",0x16,0x00
        db ATTR_UP,"UP",0x16,0x00
        db ATTR_DOWN,"DOWN",0x16,0x00
        db ATTR_MAGIC,"MAGIC",0x16,0x00
        db COLOR_BASE+0,"BLACK",0x16,0x00
        db COLOR_BASE+1,"D-GRE",0x16,0x00
        db COLOR_BASE+2,"M-GRE",0x16,0x00
        db COLOR_BASE+3,"GREEN",0x16,0x00
        db COLOR_BASE+4,"D-RED",0x16,0x00
        db COLOR_BASE+5,"D-YEL",0x16,0x00
        db COLOR_BASE+6,"D-LIM",0x16,0x00
        db COLOR_BASE+7,"LIME",0x16,0x00
        db COLOR_BASE+8,"M-RED",0x16,0x00
        db COLOR_BASE+9,"D-ORA",0x16,0x00
        db COLOR_BASE+10,"M-YEL",0x16,0x00
        db COLOR_BASE+11,"LEMON",0x16,0x00
        db COLOR_BASE+12,"RED",0x16,0x00
        db COLOR_BASE+13,"ORANGE",0x16,0x00
        db COLOR_BASE+14,"GOLD",0x16,0x00
        db COLOR_BASE+15,"YELLOW",0x16,0x00
        db BGRND_BASE+0,"B-BLK",0x16,0x00
        db BGRND_BASE+1,"B-RED",0x16,0x00
        db BGRND_BASE+2,"B-GRE",0x16,0x00
        db BGRND_BASE+3,"B-YEL",0x16,0x00
        db ATTR_REM,"REM",0x16,0x00
        db ATTR_DRAW,"DRAW",0x16,0x00
        db ATTR_THIN,"THIN",0x16,0x00
        db ATTR_WAIT,"WAIT",0x16,0x00
        db ATTR_HOLD,"HOLD",0x16,0x00
        db ATTR_RAINBOW,"RAINBOW",0x16,0x00
        db ATTR_MAGIC_OFF,"MAGIC OFF",0x16,0x00
        db ATTR_TINY,"TINY",0x16,0x00
        db 0xff
; ---- the status line's labels and the SHIFT indicator (through MENU_MSG_PTR)
STR_S:
        db "S",0x00
STR_SPEED:
        db "SPEED ",0x00
STR_GRAPH:
        db "GRAPH ",0x00
STR_COLOR:
        db "COLOR",0x00
STR_BGRND:
        db "BGRND",0x00
STR_FUNC:
        db "FUNC",0x00
STR_EURO:
        db "EURO",0x00
STR_SHIFT:
        db "SHIFT",0x16,0x00
STR_BRACKET:
        db 0x15,0x00

    IFDEF CC710
; Prompts plus their typed digits fit 59 columns; the right-aligned messages
; are padded to the window as on the CC784 (the factory CC710 wordings where it has them).
STR_TOP_OF_MSG:                 ; show_top_of_msg adds the channel digits
        db "MSG ",0x00
MENU_STRINGS:
        db "ADDR? ",0x00
MENU_STR_MSG_FULL:
        db " FULL? ",0x00
MENU_STR_CLR_ALL:
        db " CLR? Y/N",0x00
MENU_STR_TIME:
        db "TIME? ",0x00
MENU_STR_AM_PM:
        db " AM? Y/N ",0x00
MENU_STR_PROG_MSG:
        db " PROG? ",0x00
MENU_STR_SEQ_MSG:
        db " SEQ? ",0x00
MENU_STR_INVALID:
        db "  INVALID  ",0x00
MENU_STR_MEM_FULL:
        db " MEM FULL ",0x00
MENU_STR_100_KEYS:
        db " 100 LEFT ",0x00
MENU_STR_SEQ_FULL:
        db " SEQ FULL ",0x00
STR_MAGIC_MSG:                  ; the redraw adds the channel digits
        db "  MAGIC ",0x00
    ELSE
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
        db "    INVALID    ",0x00
MENU_STR_MEM_FULL:
        db " MEMORY FULL  ",0x00
MENU_STR_100_KEYS:
        db " 100 KEYS LEFT ",0x00
MENU_STR_SEQ_FULL:
        db " SEQUENCE FULL",0x00
STR_MAGIC_MSG:                  ; the redraw adds the channel digits
        db "    MAGIC MSG ",0x00
    ENDIF

; ---- FONT: 191 glyphs of 1 to 7 columns, each stored at its width (glyph_addr
;      finds one through FONT_BLOCK and FONT_WIDTH). Glyph i draws character i
;      for 00-7F; 128-190 are the Euro layer's C0-CF, E0-EF, 90-9F and D0-DF.
;      Stock kept 8 bytes a glyph, 7 columns and the width.
FONT_BLOCK:                     ; the first column of glyphs 0, 8, 16 ...
        dw FONT_G0,FONT_G8,FONT_G16,FONT_G24,FONT_G32,FONT_G40,FONT_G48,FONT_G56
        dw FONT_G64,FONT_G72,FONT_G80,FONT_G88,FONT_G96,FONT_G104,FONT_G112,FONT_G120
        dw FONT_G128,FONT_G136,FONT_G144,FONT_G152,FONT_G160,FONT_G168,FONT_G176,FONT_G184
FONT_WIDTH:
        db 7,7,7,6,7,5,5,7,6,7,7,7,5,7,7,7   ; glyphs 0-15
        db 1,1,1,1,1,4,4,6,1,1,1,1,1,1,1,1   ; glyphs 16-31
        db 5,4,3,5,5,7,6,1,3,3,5,5,3,4,4,7   ; glyphs 32-47
        db 5,3,5,5,5,5,5,5,5,5,2,3,4,4,4,5   ; glyphs 48-63
        db 5,5,5,5,5,5,5,5,5,3,5,5,5,5,5,5   ; glyphs 64-79
        db 5,5,5,5,5,5,5,5,5,5,5,3,5,3,5,7   ; glyphs 80-95
        db 6,5,5,5,5,5,4,5,5,1,5,4,1,5,5,5   ; glyphs 96-111
        db 5,5,5,5,3,5,5,5,5,5,5,3,5,3,4,7   ; glyphs 112-127
        db 5,5,5,5,5,5,5,5,5,5,7,7,5,5,5,5   ; glyphs 128-143
        db 5,5,5,5,5,5,7,6,5,5,5,6,5,5,5,5   ; glyphs 144-159
        db 5,5,5,5,5,5,5,5,5,5,5,5,5,5,2,1   ; glyphs 160-175
        db 1,1,1,1,1,1,1,1,1,1,1,5,2,3,5   ; glyphs 176-190
FONT:
FONT_G0:
        db 0x1c,0x14,0x14,0x77,0x22,0x14,0x08     ; glyph   0
        db 0x08,0x14,0x22,0x77,0x14,0x14,0x1c     ; glyph   1
        db 0x30,0x70,0x38,0x34,0x3c,0x74,0x38     ; glyph   2
        db 0x20,0x70,0x70,0x3f,0x02,0x04          ; glyph   3
        db 0x08,0x1c,0x22,0x2a,0x22,0x1c,0x08     ; glyph   4
        db 0x07,0x49,0x79,0x49,0x07               ; glyph   5
        db 0x10,0x18,0x1c,0x18,0x10               ; glyph   6
        db 0x08,0x1c,0x3e,0x7f,0x3e,0x1c,0x08     ; glyph   7
FONT_G8:
        db 0x7f,0x7f,0x7f,0x7f,0x7f,0x00          ; glyph   8
        db 0x1c,0x3e,0x7f,0x7f,0x3e,0x1c,0x00     ; glyph   9
        db 0x04,0x7c,0x46,0x77,0x46,0x7c,0x04     ; glyph  10
        db 0x10,0x30,0x54,0x56,0x5f,0x50,0x30     ; glyph  11
        db 0x18,0x1e,0x7f,0x1e,0x18               ; glyph  12
        db 0x2c,0x6e,0x6d,0x6f,0x6f,0x3e,0x1c     ; glyph  13
        db 0x1c,0x22,0x41,0x4f,0x51,0x22,0x1c     ; glyph  14
        db 0x20,0x3c,0x22,0x63,0x22,0x3c,0x20     ; glyph  15
FONT_G16:
        db 0x01                                   ; glyph  16
        db 0x01                                   ; glyph  17
        db 0x01                                   ; glyph  18
        db 0x01                                   ; glyph  19
        db 0x01                                   ; glyph  20
        db 0x00,0x00,0x08,0x1c                    ; glyph  21
        db 0x1c,0x08,0x00,0x00                    ; glyph  22
        db 0x7f,0x7f,0x7f,0x7f,0x7f,0x7f          ; glyph  23
FONT_G24:
        db 0x01                                   ; glyph  24
        db 0x01                                   ; glyph  25
        db 0x01                                   ; glyph  26
        db 0x01                                   ; glyph  27
        db 0x01                                   ; glyph  28
        db 0x01                                   ; glyph  29
        db 0x01                                   ; glyph  30
        db 0x01                                   ; glyph  31
FONT_G32:
        db 0x00,0x00,0x00,0x00,0x00               ; glyph  32
        db 0x5f,0x00,0x00,0x00                    ; glyph  33
        db 0x07,0x00,0x07                         ; glyph  34
        db 0x14,0x7f,0x14,0x7f,0x14               ; glyph  35
        db 0x26,0x49,0x7f,0x49,0x32               ; glyph  36
        db 0x42,0x25,0x12,0x08,0x24,0x52,0x21     ; glyph  37
        db 0x36,0x49,0x49,0x56,0x20,0x50          ; glyph  38
        db 0x07                                   ; glyph  39
FONT_G40:
        db 0x1c,0x22,0x41                         ; glyph  40
        db 0x41,0x22,0x1c                         ; glyph  41
        db 0x2a,0x1c,0x7f,0x1c,0x2a               ; glyph  42
        db 0x08,0x08,0x3e,0x08,0x08               ; glyph  43
        db 0x40,0x30,0x30                         ; glyph  44
        db 0x08,0x08,0x08,0x08                    ; glyph  45
        db 0x60,0x60,0x00,0x00                    ; glyph  46
        db 0x40,0x20,0x10,0x08,0x04,0x02,0x01     ; glyph  47
FONT_G48:
        db 0x3e,0x41,0x41,0x41,0x3e               ; glyph  48
        db 0x41,0x7f,0x40                         ; glyph  49
        db 0x42,0x61,0x51,0x49,0x46               ; glyph  50
        db 0x22,0x41,0x49,0x49,0x36               ; glyph  51
        db 0x08,0x0c,0x0a,0x7f,0x08               ; glyph  52
        db 0x2f,0x49,0x49,0x49,0x31               ; glyph  53
        db 0x3c,0x4a,0x49,0x49,0x30               ; glyph  54
        db 0x01,0x71,0x09,0x05,0x03               ; glyph  55
FONT_G56:
        db 0x36,0x49,0x49,0x49,0x36               ; glyph  56
        db 0x06,0x49,0x49,0x49,0x3e               ; glyph  57
        db 0x6c,0x6c                              ; glyph  58
        db 0x40,0x6c,0x6c                         ; glyph  59
        db 0x08,0x14,0x22,0x41                    ; glyph  60
        db 0x14,0x14,0x14,0x14                    ; glyph  61
        db 0x41,0x22,0x14,0x08                    ; glyph  62
        db 0x02,0x01,0x51,0x09,0x06               ; glyph  63
FONT_G64:
        db 0x3e,0x41,0x4f,0x49,0x2e               ; glyph  64
        db 0x7e,0x09,0x09,0x09,0x7e               ; glyph  65
        db 0x7f,0x49,0x49,0x49,0x36               ; glyph  66
        db 0x3e,0x41,0x41,0x41,0x22               ; glyph  67
        db 0x7f,0x41,0x41,0x41,0x3e               ; glyph  68
        db 0x7f,0x49,0x49,0x49,0x41               ; glyph  69
        db 0x7f,0x09,0x09,0x09,0x01               ; glyph  70
        db 0x3e,0x41,0x41,0x51,0x32               ; glyph  71
FONT_G72:
        db 0x7f,0x08,0x08,0x08,0x7f               ; glyph  72
        db 0x41,0x7f,0x41                         ; glyph  73
        db 0x20,0x40,0x41,0x3f,0x01               ; glyph  74
        db 0x7f,0x08,0x14,0x22,0x41               ; glyph  75
        db 0x7f,0x40,0x40,0x40,0x40               ; glyph  76
        db 0x7f,0x02,0x0c,0x02,0x7f               ; glyph  77
        db 0x7f,0x02,0x04,0x08,0x7f               ; glyph  78
        db 0x3e,0x41,0x41,0x41,0x3e               ; glyph  79
FONT_G80:
        db 0x7f,0x09,0x09,0x09,0x06               ; glyph  80
        db 0x3e,0x41,0x51,0x61,0x7e               ; glyph  81
        db 0x7f,0x09,0x19,0x29,0x46               ; glyph  82
        db 0x26,0x49,0x49,0x49,0x32               ; glyph  83
        db 0x01,0x01,0x7f,0x01,0x01               ; glyph  84
        db 0x3f,0x40,0x40,0x40,0x3f               ; glyph  85
        db 0x1f,0x20,0x40,0x20,0x1f               ; glyph  86
        db 0x3f,0x40,0x38,0x40,0x3f               ; glyph  87
FONT_G88:
        db 0x63,0x14,0x08,0x14,0x63               ; glyph  88
        db 0x07,0x08,0x70,0x08,0x07               ; glyph  89
        db 0x61,0x51,0x49,0x45,0x43               ; glyph  90
        db 0x7f,0x41,0x41                         ; glyph  91
        db 0x02,0x04,0x08,0x10,0x20               ; glyph  92
        db 0x41,0x41,0x7f                         ; glyph  93
        db 0x04,0x02,0x7f,0x02,0x04               ; glyph  94
        db 0x1c,0x22,0x41,0x4f,0x51,0x22,0x1c     ; glyph  95
FONT_G96:
        db 0x60,0x5e,0x55,0x55,0x41,0x02          ; glyph  96
        db 0x20,0x54,0x54,0x54,0x78               ; glyph  97
        db 0x7f,0x44,0x44,0x44,0x38               ; glyph  98
        db 0x38,0x44,0x44,0x44,0x44               ; glyph  99
        db 0x38,0x44,0x44,0x44,0x7f               ; glyph 100
        db 0x38,0x54,0x54,0x54,0x58               ; glyph 101
        db 0x08,0x7e,0x09,0x02                    ; glyph 102
        db 0x38,0x44,0x44,0x54,0x74               ; glyph 103
FONT_G104:
        db 0x7f,0x04,0x04,0x04,0x78               ; glyph 104
        db 0x7a                                   ; glyph 105
        db 0x20,0x40,0x44,0x3c,0x04               ; glyph 106
        db 0x7f,0x10,0x28,0x44                    ; glyph 107
        db 0x7f                                   ; glyph 108
        db 0x78,0x04,0x18,0x04,0x78               ; glyph 109
        db 0x7c,0x08,0x04,0x04,0x78               ; glyph 110
        db 0x38,0x44,0x44,0x44,0x38               ; glyph 111
FONT_G112:
        db 0x7c,0x14,0x14,0x14,0x08               ; glyph 112
        db 0x38,0x44,0x54,0x64,0x78               ; glyph 113
        db 0x7c,0x08,0x04,0x04,0x08               ; glyph 114
        db 0x48,0x54,0x54,0x54,0x24               ; glyph 115
        db 0x04,0x3f,0x44                         ; glyph 116
        db 0x3c,0x40,0x40,0x40,0x3c               ; glyph 117
        db 0x0c,0x30,0x40,0x30,0x0c               ; glyph 118
        db 0x3c,0x40,0x30,0x40,0x3c               ; glyph 119
FONT_G120:
        db 0x44,0x28,0x10,0x28,0x44               ; glyph 120
        db 0x04,0x08,0x70,0x08,0x04               ; glyph 121
        db 0x44,0x64,0x54,0x4c,0x44               ; glyph 122
        db 0x08,0x36,0x41                         ; glyph 123
        db 0x40,0x40,0x40,0x40,0x40               ; glyph 124
        db 0x41,0x36,0x08                         ; glyph 125
        db 0x08,0x04,0x08,0x04                    ; glyph 126
        db 0x08,0x08,0x08,0x08,0x2a,0x1c,0x08     ; glyph 127
FONT_G128:
        db 0x78,0x15,0x16,0x14,0x78               ; glyph 128
        db 0x20,0x55,0x56,0x54,0x78               ; glyph 129
        db 0x1e,0x21,0x61,0x21,0x21               ; glyph 130
        db 0x18,0x24,0x64,0x24,0x24               ; glyph 131
        db 0x7c,0x56,0x55,0x56,0x44               ; glyph 132
        db 0x7c,0x54,0x56,0x55,0x44               ; glyph 133
        db 0x38,0x54,0x56,0x55,0x58               ; glyph 134
        db 0x7c,0x55,0x56,0x54,0x44               ; glyph 135
FONT_G136:
        db 0x38,0x55,0x56,0x54,0x58               ; glyph 136
        db 0x38,0x56,0x55,0x56,0x58               ; glyph 137
        db 0x78,0x0c,0x0a,0x7f,0x49,0x49,0x41     ; glyph 138
        db 0x20,0x54,0x54,0x78,0x54,0x54,0x08     ; glyph 139
        db 0x7c,0x09,0x11,0x21,0x7c               ; glyph 140
        db 0x7c,0x09,0x05,0x05,0x78               ; glyph 141
        db 0x3c,0x41,0x42,0x40,0x3c               ; glyph 142
        db 0x78,0x15,0x14,0x15,0x78               ; glyph 143
FONT_G144:
        db 0x20,0x55,0x54,0x55,0x78               ; glyph 144
        db 0x38,0x45,0x44,0x45,0x38               ; glyph 145
        db 0x30,0x4a,0x48,0x4a,0x30               ; glyph 146
        db 0x3c,0x41,0x40,0x41,0x3c               ; glyph 147
        db 0x78,0x14,0x15,0x14,0x78               ; glyph 148
        db 0x20,0x54,0x55,0x54,0x78               ; glyph 149
        db 0x40,0x3e,0x51,0x49,0x45,0x3e,0x01     ; glyph 150
        db 0x40,0x3c,0x52,0x4a,0x3c,0x02          ; glyph 151
FONT_G152:
        db 0x38,0x42,0x40,0x42,0x38               ; glyph 152
        db 0x1c,0x22,0x7f,0x22,0x1c               ; glyph 153
        db 0x07,0x08,0x7f,0x08,0x07               ; glyph 154
        db 0x5c,0x62,0x01,0x01,0x62,0x5c          ; glyph 155
        db 0x78,0x14,0x16,0x15,0x78               ; glyph 156
        db 0x7f,0x25,0x25,0x25,0x1a               ; glyph 157
        db 0x41,0x49,0x49,0x49,0x41               ; glyph 158
        db 0x01,0x7f,0x01,0x7f,0x01               ; glyph 159
FONT_G160:
        db 0x02,0x01,0x51,0x09,0x06               ; glyph 160
        db 0x02,0x01,0x51,0x09,0x06               ; glyph 161
        db 0x02,0x01,0x51,0x09,0x06               ; glyph 162
        db 0x02,0x01,0x51,0x09,0x06               ; glyph 163
        db 0x63,0x55,0x49,0x41,0x41               ; glyph 164
        db 0x20,0x54,0x56,0x55,0x78               ; glyph 165
        db 0x30,0x48,0x45,0x40,0x20               ; glyph 166
        db 0x70,0x4c,0x43,0x4c,0x70               ; glyph 167
FONT_G168:
        db 0x3e,0x49,0x49,0x49,0x3e               ; glyph 168
        db 0x70,0x0c,0x03,0x0c,0x70               ; glyph 169
        db 0x3e,0x40,0x42,0x41,0x3e               ; glyph 170
        db 0x7f,0x01,0x01,0x01,0x01               ; glyph 171
        db 0x3c,0x40,0x42,0x41,0x3c               ; glyph 172
        db 0x3e,0x41,0x42,0x40,0x3e               ; glyph 173
        db 0x00,0x7d                              ; glyph 174
        db 0x01                                   ; glyph 175
FONT_G176:
        db 0x01                                   ; glyph 176
        db 0x01                                   ; glyph 177
        db 0x01                                   ; glyph 178
        db 0x01                                   ; glyph 179
        db 0x01                                   ; glyph 180
        db 0x01                                   ; glyph 181
        db 0x01                                   ; glyph 182
        db 0x01                                   ; glyph 183
FONT_G184:
        db 0x01                                   ; glyph 184
        db 0x01                                   ; glyph 185
        db 0x01                                   ; glyph 186
        db 0x38,0x44,0x46,0x45,0x38               ; glyph 187
        db 0x76,0x01                              ; glyph 188
        db 0x44,0x7e,0x45                         ; glyph 189
        db 0x30,0x48,0x4c,0x4a,0x30               ; glyph 190

; ---- CHAR_FLAGS: four characters a byte, two bits each, the lowest character
;      in the top bits: 0 printable text, 2 attribute, 3 invalid (store_repair
;      turns it into '?'). Read through char_flags only.
CHAR_FLAGS:
        db 0xfe,0xfa,0xff,0xfe,0xaa,0x80,0xaa,0xfe,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 00-3f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 40-7f
        db 0xaa,0xaa,0xaa,0xaa,0xaa,0x00,0x00,0x03,0x00,0x00,0x00,0x00,0xbf,0xff,0x2a,0xab   ; char 80-bf
        db 0x00,0x00,0x00,0x00,0xaa,0xaa,0xab,0x00,0x00,0x00,0x00,0x00,0xaa,0xaa,0xff,0xff   ; char c0-ff

; ============================================================================
;  Key-position -> character/attribute tables, one per input layer. Indexed by
;  the key number that IR_KEY_TABLE yields, 64 keys laid out as the 8x8 matrix
;  keypad_scan walks. Layer chosen at 0x23C1:
;
;      EURO_STATE  set      -> CHARSET_EURO
;      SHIFT_STATE clear    -> CHARSET_LOWER
;      SHIFT_STATE set      -> CHARSET_LOWER2
;
;  Both layers are stored in lower case; getkey_lookup folds a-z to upper case
;  when exactly one of SHIFT_STATE and CAPS_LOCK is on (stock kept four tables).
;
;  On the remote these are one key labeled UPPER/LOWER, whose shifted
;  function is EUROPE: unshifted it toggles CAPS_LOCK (0x216C), shifted it
;  toggles EURO_STATE (0x2184).
;
;  So SHIFT selects the alternate function layer and flips case; CAPS_LOCK
;  flips case on its own. Both SHIFT_STATE and EURO_STATE are cleared after
;  every key. Entries below 0x20 and 0xB0-0xBF are attribute bytes - the
;  glosses are the editor's own names, from ATTR_LABEL_TABLE.
; ============================================================================

; ---- CHARSET_LOWER: unshifted (upper case when CAPS_LOCK is on)
CHARSET_LOWER:
        db "kf",0x12,"pa",0x0e,0x11,0x1e              ; 00-07  k f BOLD p a 0E NORM GRAPH
        db " ",0x7f,")%zwyt"                          ; 08-0f  SP 7F ) % z w y t
        db "ni",0x1f,"hd",0x09,0x1a,0x19              ; 10-17  n i MAGIC h d PROG MSG? UP PAUSE
        db "0",0x1d,"2586k",0x00                      ; 18-1f  0 SHIFT 2 5 8 6 k 00
        db "lgvmq",0x04,0x10,0x14                     ; 20-27  l g v m q SEQ MSG? BIG FLASH
        db ".",0x1c,"(*+9xs"                          ; 28-2f  . 1C ( * + 9 x s
        db "ojbce",0x0d,0x07,0x15                     ; 30-37  o j b c e 0D BEEP COLOR
        db 0x08,0x0a,"1473ur"                         ; 38-3f  08 0A 1 4 7 3 u r

; ---- CHARSET_LOWER2: SHIFT held (upper case when CAPS_LOCK is off)
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
;      and colors; the room went to the render-loop packet processing.
DEMO_MESSAGE:
        db 0x12,"COLOR CELLS ",0x13,0x8c
    IFDEF CC710
        db "CC710"
    ELSE
        db "CC784"
    ENDIF
        db " ",0x11,0xbc,0x14,"MULTI-COLOR DISPLAY"
        db 0xbe,"TINY PRICE",0x10,"LARGE IMPACT!",0x03,0xdb

; ---- ota_updating_msg: what the panel shows from B5 'B' to the reboot, via the
;      test-mode buffer (28 bytes max). PAUSE, THIN, the word, WAIT: parked until
;      a key. Last thing before the trailer, so editing it moves nothing else.
ota_updating_msg:
        db 0x19,0xb9,">FW ^<",0xba,0x03     ; ^ is the up-arrow glyph; fits 59 columns

; ---- trailer page 3FC0-3FFF (CC784_ota.md §3): magic, sequence number, state
;      and image CRC, filled in by tools/cc784_ota.py pack. Erased in the build.
        ds 0x3fc0-$,0xff
TRAILER:
        ds 0x4000-$,0xff

        ds 0x8000-$,0xff        ; bank B: the packer fills it, the T48 image carries both
