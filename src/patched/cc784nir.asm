; ============================================================================
;  Color Cells CC784NIR LED sign - PATCHED firmware source
;  Assemble:  sjasmplus cc784nir.asm   (produces cc784nir_patched.bin, 32768 B)
;             sjasmplus -DCC710 cc784nir.asm   (cc710_patched.bin: the 59-column panel)
;             -DLITE, alone or with -DCC710: an unmodified CC784-3A board (4 MHz,
;             2 K RAM, no IR): cc784lite.bin / cc710lite.bin, 16 K for a 27128
;  NOT byte-identical to the dump. The untouched reconstruction is
;  ../stock/cc784nir.asm; diff the two to see the patches.
;
;  The original firmware is copyright its owner (Color Cells / Innovative Sign
;  Technology, 1993, and successors). The patches, labels and comments are
;  MIT, see ../../LICENSE.
; ============================================================================
        DEVICE NONE

; Patched build: the stock reconstruction (../stock/cc784nir.asm) plus the
; patches in patched.md. Up to the tag patched-v39 the rest was kept
; identical to stock; after it the code is restructured freely and the git
; history is the changelog. Addresses differ from stock throughout.

    IFDEF LITE
    IFDEF CC710
        OUTPUT "cc710lite.bin"
    ELSE
        OUTPUT "cc784lite.bin"
    ENDIF
    ELSE
    IFDEF CC710
        OUTPUT "cc710_patched.bin"
    ELSE
        OUTPUT "cc784nir_patched.bin"
    ENDIF
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
CUR_COLOR            equ RAM_VARS+0x061   ; a color byte's low 7 bits: COLOR_FG, COLOR_FLASH, COLOR_BG
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
RAINBOW_IDX          equ RAM_VARS+0x07e   ; RAINBOW per-char color index 1..RAINBOW_N, 0 = off; bit 7 = P28 reverse
RAINBOW_REVERSE      equ 0x80
RAINBOW_N            equ 5           ; RAINBOW's colors, at most 7
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
NMI_COUNT            equ RAM_VARS+0x0c7   ; NMIs this second; magic_short_word also adds it to the random seed
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
IR_DEBOUNCE          equ RAM_VARS+0x0d6   ; key number | 0x40 seen once, awaiting its second frame; 0 none
TICK6_COUNT          equ RAM_VARS+0x0d7
GEN_COUNTDOWN        equ RAM_VARS+0x0d8   ; IR repeat/hold timer, counts down in tick6 (word)
IR_STATE_CNT         equ RAM_VARS+0x0da
IR_BITCNT            equ RAM_VARS+0x0db
IR_KEY               equ RAM_VARS+0x0dc   ; last seen key number | 0x40; 0 none
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
SEQ_END              equ SEQ_LIST+SEQ_LIST_LEN
IR_LEVEL             equ SEQ_END+0x00     ; the IR line as the decoder last saw it, for edge detection
IR_CELL              equ SEQ_END+0x01     ; the current cell's verdict: FF none yet, 0 or 1
IR_REJ               equ SEQ_END+0x02     ; remote frames dropped, by reason: four counters the stats query appends
IR_REJ_LEADER        equ SEQ_END+0x02     ; no start burst 10-23 ticks after the leader
IR_REJ_POS           equ SEQ_END+0x03     ; stray rises between the two positions or past the middle (ignored, not drops)
IR_REJ_CELL          equ SEQ_END+0x04     ; no rise in a cell after a 1
IR_REJ_BRIDGE        equ SEQ_END+0x05     ; a burst where a gap belongs: high through a cell's first two ticks after a 1, or a rise opening a cell after a 0
TERM_MODE            equ SEQ_END+0x06     ; FF: the editor was opened by B7 '1' and takes serial bytes as keys
EDIT_CLOSE           equ SEQ_END+0x07     ; FF: B7 '0' asks the open editor to close
; P20: the clock digits must survive a power cycle, so they live up here next
; to the store, out of reach of the stub's library copy (RAM_VARS+00..81).
CLK_H10              equ SEQ_END+0x08
CLK_H1               equ SEQ_END+0x09
CLK_M10              equ SEQ_END+0x0a
CLK_M1               equ SEQ_END+0x0b
CLK_SEC              equ SEQ_END+0x0c
CLK_PM               equ SEQ_END+0x0d
BOOT_COUNT           equ SEQ_END+0x0e     ; boots since RAM was last fresh
STORE_LIMIT          equ SEQ_END+0x0f
STORE_SIZE           equ SEQ_END+0x11
STORE_TEXT_LIMIT     equ SEQ_END+0x13     ; free text bytes; scan bound for store_repair
STORE_WARN_LIMIT     equ SEQ_END+0x15     ; STORE_END here trips the 100 KEYS LEFT warning
; P35: the configuration block. Battery-backed like the clock; its signature
; and sum are the RAM-validity test (was MY_ADDRESS against its complement).
CFG                  equ SEQ_END+0x17
CFG_SIG              equ CFG+0            ; CFG_MAGIC while the block is valid
MY_ADDRESS           equ CFG+1            ; written only by the editor's ADDRESS? dialog
CFG_FLAGS            equ CFG+2            ; bits 0-1 brightness, 2 muted, 3 mute pending, 4 quiet, 5 locked, 6 wrapped, 7 status
CFG_BRIGHT           equ 0x03             ; CFG_FLAGS bits 0-1: off, low, medium, full
CFG_MUTED_BIT        equ 2
CFG_MUTE_PEND_BIT    equ 3
CFG_WRAPPED_BIT      equ 6
CFG_MUTED            equ 1<<CFG_MUTED_BIT
CFG_QUIET            equ 0x10             ; the beeper stays silent
CFG_LOCKED           equ 0x20             ; remote keys are ignored
CFG_LIVE             equ 0x40             ; wrapped changes without a reseal
                                          ; bit 7, P41: a status report at each channel start and editor entry
CFG_HOLD             equ CFG+3            ; frames a PAUSE, HOLD, wipe or clock holds the panel
CFG_FLASH            equ CFG+4            ; frames per half period of the FLASH blink
CFG_SUM              equ CFG+5            ; 8-bit sum of the bytes before it
CFG_LEN              equ 6
CFG_MAGIC            equ 0xa5
STORE_GUARD          equ CFG+CFG_LEN      ; store_repair writes a space at MSG_STORE-1 every boot
MSG_STORE            equ STORE_GUARD+1
; ---- Top of RAM (patch 13). Everything at a fixed address sits in the last
;      272 bytes below RAM_TOP: on the stock 8 K chip 7Fxx aliases 5Fxx, so the
;      same build runs on either; only the store's ceiling is decided at boot.
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
; ---- OTA (ota.md): the boot stub's RAM, above the packet parser state,
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
STACK_TOP_2K         equ RAM_TOP-0x10 ; P51: LITE on a 2 K chip: the stack in the buffer's top half
PKT_MAX_FULL         equ 254         ; longest payload: PKT_BUF+255 is NMI_SEEN
PKT_MAX_2K           equ 128
; FLASH blink: frames per half period of CTRL_LATCH bit 7. Stock 13 = 2.4 Hz;
; 7 gave a visible ~5 Hz on the sign (2026-09-19), which is what proved bit 7
; is the blink clock. Change here to retune, nothing else references it.
FLASH_HALF_PERIOD    equ 13          ; P35: the default of CFG_FLASH
    IFDEF CC710
FRAME_COLS           equ 60          ; columns sent per row: the CC710 panel's 59 plus one that falls off the chain
    ELSE
FRAME_COLS           equ 86          ; columns sent per row: the panel's 84 plus two that fall off the chain
    ENDIF
    IFDEF LITE
CHANNELS             equ 10          ; message channels 0-9
TICK6_DIV            equ 1           ; 4 MHz: 1302 interrupts a second, the tick service on each
DISP_FRAC            equ 42          ; DISP_STRETCH counts sevenths of six interrupts: 42nds of one
BAUD_STEP_300        equ 30          ; BAUD_T fifths of a 1/6 interrupt, so 30 an interrupt;
BAUD_STEP_600        equ 30          ; 300 baud only
BAUD_STEP_1200       equ 30
BAUD_STEP_2560       equ 0           ; never matches BAUD_STEP
TWINKLE_DOTS         equ 24          ; what a 4-frame tick has time for at 4 MHz
STACK_SIZE           equ 126         ; a 2 K chip's stack fits above PKT_MAX_2K; peak use about 50
STACK_CANARY         equ 96
    ELSE
CHANNELS             equ 100         ; message channels 0-99
TICK6_DIV            equ 6           ; 8 MHz: 7812 interrupts a second
DISP_FRAC            equ 7           ; DISP_STRETCH counts sevenths of an interrupt
BAUD_STEP_300        equ 5
BAUD_STEP_600        equ 10
BAUD_STEP_1200       equ 20
BAUD_STEP_2560       equ 40          ; P52: the bit is exactly 3 interrupts (baud_bit)
TWINKLE_DOTS         equ 80          ; P49: random spots darkened each tick; about 30 land on lit pixels in plain text
STACK_SIZE           equ 160         ; P35: a boot-time canary measured 130 bytes at most (a 57-channel store fill)
STACK_CANARY         equ 128         ; bytes of CANARY laid at the stack's bottom at boot; the stats query counts those left
    ENDIF
RAM_TOP              equ 0x8000
RAM_ALT              equ 0x2000      ; the stock 8 K chip mirrors 6000 onto 4000
HOLD_FRAMES          equ 80          ; frames a PAUSE, HOLD, wipe or clock holds the panel (~1.3 s); P35: the default of CFG_HOLD
TWINKLE_TICK         equ 4           ; P49: frames a TWINKLE's dark pixels stay dark
GLIMMER_TICK         equ 3           ; P50: frames between a GLIMMER's row steps
GLIMMER_BAND         equ 0x07        ; P50: a stripe's dark rows; it rolls through 8 (7 rows and the unused bit 7)
BEEP_LEN             equ 150         ; beeper on for this many tick6 periods (~115 ms)
IR_REPEAT_DELAY      equ 1300        ; tick6 periods a held remote key waits before repeating (~1 s)
IR_REPEAT_TICKS      equ 300         ; ... and between repeats (~0.23 s)
IR_DEBOUNCE_WINDOW   equ 400         ; tick6 periods a lone first frame waits for its second or its release (~0.3 s)

; ---- Message store format ------------------------------------------------------
MARK_LO              equ 0xd0        ; channel markers are two bytes D0+tens, D0+units
MARK_HI              equ 0xda        ; the last marker byte value; alone, DA ends the store
TEXT_END             equ 0x03        ; ends a channel's text
CHAN_DEMO            equ CHANNELS    ; the pseudo-channel that plays DEMO_MESSAGE
SEQ_LIST_LEN         equ CHANNELS+4  ; SEQ_LIST: an entry per channel plus FF terminators

; ---- Message attribute bytes (the sign's own names, firmware.md §8) --------
ATTR_HALT            equ 0x06
ATTR_BEEP            equ 0x07
ATTR_RIGHT           equ 0x0f
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
ATTR_ALT             equ 0xb2        ; P46: the variant of the attribute after it: B2 BC = RANDBOW

ATTR_COLOR_BLACK       equ 0x80
ATTR_COLOR_DARK_GREEN  equ 0x81
ATTR_COLOR_MID_GREEN   equ 0x82
ATTR_COLOR_GREEN       equ 0x83
ATTR_COLOR_DARK_RED    equ 0x84
ATTR_COLOR_DARK_YELLOW equ 0x85
ATTR_COLOR_DARK_LIME   equ 0x86
ATTR_COLOR_LIME        equ 0x87
ATTR_COLOR_MID_RED     equ 0x88
ATTR_COLOR_DARK_ORANGE equ 0x89
ATTR_COLOR_MID_YELLOW  equ 0x8a
ATTR_COLOR_LEMON       equ 0x8b
ATTR_COLOR_RED         equ 0x8c
ATTR_COLOR_ORANGE      equ 0x8d
ATTR_COLOR_GOLD        equ 0x8e
ATTR_COLOR_YELLOW      equ 0x8f
ATTR_BGRND_BLACK       equ 0x90
ATTR_BGRND_RED         equ 0x91
ATTR_BGRND_GREEN       equ 0x92
ATTR_BGRND_YELLOW      equ 0x93

KEY_EURO             equ 0xb6
KEY_FUNC             equ 0xb7
KEY_DEL              equ 0x7f
KEY_SPEED            equ 0x02        ; editor command keys
KEY_SEQ              equ 0x04
KEY_CUR_LEFT         equ 0x08
KEY_PROG             equ 0x09
KEY_CUR_RIGHT        equ 0x0a
KEY_CUR_LEFT8        equ 0x0b
KEY_CUR_RIGHT8       equ 0x0c
KEY_ENTER            equ 0x0d
KEY_CLEAR            equ 0x0e
KEY_CLR_ALL          equ 0x03        ; SHIFT + CLEAR
KEY_TIME             equ 0x17        ; SHIFT + NORM
KEY_ADDRESS          equ 0x5e        ; FUNC + MAGIC
KEY_FIELD            equ 0xd1        ; P54: FUNC + PROG; a marker byte, which no key produces
KEY_UNSHIFT          equ 0xd2        ; P56: SHIFT off; it was 9F, the degree sign now
; P30: serial timing. An interrupt is 128 us plus the acknowledge latency, about
; 130 us; the 300-baud bit is 25.6 of them, kept in fifths as BAUD_T, and the
; faster rates step the same accumulator 10 or 20 fifths per interrupt. 2400
; is not offered: sampled once per interrupt, its bits are read within a third
; of a bit of their middles and long frames fail on the board. P52: 2560 is
; exactly 3 interrupts a bit, so every sample sits at the same point of its bit.
; baud_calibrate sets BAUD_T from the tick6 count per NMI second (1280 + s ticks
; -> (1280 + s) / 10); until then, or on a DC supply, it is the default.
BAUD_T_DEFAULT       equ 128
BAUD_CAL_LIMIT       equ 60          ; |s| beyond this (4.7 %) is a partial second or a stall: ignored
; P31: the NMI is the mains zero-cross on AC, or the add-in board's HC4060 Q9
; when BANK_REG bit 7 selects it through the board's '151 (hardware.md)
NMI_PER_SEC_MAINS    equ 60
NMI_PER_SEC_XTAL     equ 64
BANK_CLOCK_XTAL      equ 0x80        ; BANK_REG bit 7, its top bit; bits 0-2 are kept for a larger EEPROM's A14-A16
CLK_24H              equ 0x02        ; P32: CLK_PM bit 1 = 24-hour clock; bit 0 = PM
BAUD_IDLE_FRAMES     equ 62          ; display frames, about a second
IR_CODE_STOP         equ 0xa4        ; 0x80 | remote key 36, STOP/START
IR_CODE_SPACE        equ 0xa5        ; 0x80 | remote key 37, SPACE
IR_KEY_RELEASE       equ 0x3e        ; the key number of the frame sent on release
IR_CODE_RELEASE      equ 0x80|IR_KEY_RELEASE
IR_CODE_A            equ 0xaf        ; 0x80 | remote key 47, A: stock takes it as STOP/START leaving the editor
ASK_SEQ              equ 0x97        ; menu_ask_chan's answers past the channels: the SEQ key,
ASK_MAGIC            equ 0x98        ; the MAGIC key,
ASK_ALL              equ 0x99        ; A (all channels),
ASK_BLANK            equ 0x9a        ; ENTER with no digits,
ASK_MSGS             equ 0x9b        ; M (the message channels, P54)
CLK_STEP_COLON       equ 3           ; render_clock's steps: H10 and H1 are 1 and 2, then
CLK_STEP_M1          equ 5           ; the colon, M10, M1,
CLK_STEP_SPACE       equ 6           ; a space,
CLK_STEP_AMPM        equ 7           ; A or P,
CLK_STEP_M           equ 8           ; and M
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
COLOR_FG             equ 0x0f        ; its foreground
COLOR_BG             equ 0x60        ; its background
BGRND_BASE           equ 0x90        ; 90-93 background
GRAPH_BASE           equ 0xa0        ; A0-AF built-in graphics
SPEED_BASE           equ 0xf0        ; F0-F7 scroll speed
LATCH_TX             equ 0x10        ; CTRL_LATCH bit 4: serial TX
IR_BIT               equ 4           ; P36: PORT_IN bit of the IR receiver, on a '244 piggybacked on U12; bit 1 is the keypad's
PORT_IR              equ 1<<IR_BIT
LATCH_BLINK          equ 0x80        ; CTRL_LATCH bit 7: the FLASH blink clock
LATCH_PARK           equ 0x0f        ; CTRL_LATCH bits 0-3, the row code: 15 lights no row
LATCH_KEEP           equ 0x70        ; bits 4-6 (TX, the keypad rows) stay when a row is selected
ROWS                 equ 7           ; panel rows; ROW_INDEX 0-6
FONT_BOLD_BIT        equ 1           ; FONT_MODE bits
FONT_ITALIC_BIT      equ 2
FONT_BIG_BIT         equ 3
FONT_BOLD            equ 1<<FONT_BOLD_BIT
FONT_ITALIC          equ 1<<FONT_ITALIC_BIT|FONT_BOLD   ; ITALIC and BIG are drawn on the bold glyph
FONT_BIG             equ 1<<FONT_BIG_BIT|FONT_BOLD
FX_LEFT              equ 0           ; EFFECT_ID: the plain crawl, no staging
FX_PAUSE             equ 1
FX_UP                equ 2
FX_DOWN              equ 3
FX_RIGHT             equ 4
FX_HOLD              equ 5
FX_SCROLL            equ 4           ; added after B2: UP, DOWN, RIGHT scroll instead of wiping
FX_STEP_FRAMES       equ 3           ; frames each step of a wipe or scroll shows
SCROLL_IN            equ 96          ; a scroll's incoming page: this far up the ring
EURO_LO              equ 0x94        ; 94-9F: Euro characters after the four backgrounds
EURO_ROW_C           equ 0xc0        ; Euro rows C0-CF, DB-DF (D0-DA are markers), E0-EF
EURO_ROW_D           equ 0xd0
EURO_ROW_E           equ 0xe0
EURO_ROW_9           equ 0x90        ; 94-9F, after the backgrounds
GLYPH_ROW_C          equ 128         ; their glyph indexes: C0 is glyph 128, ...
GLYPH_ROW_E          equ 144
GLYPH_ROW_9          equ 160
GLYPH_ROW_D          equ 175
CANARY               equ 0x55        ; STACK_CANARY's fill byte
SEQ_EMPTY            equ 10          ; SEQ_ALL_EMPTY's value when every listed channel is empty
STALL_FRAMES         equ 3           ; frames without a pkt_poll that count as a renderer stall
CRAWL_LEAD           equ 8           ; P42: columns the plain crawl keeps in hand (~130 ms at full speed)
; P21: packet processing runs in the render loop and replies go out in the
; background, so their state cannot share renderer scratch. Just below the
; packet buffer, with the stack under it (P51).
STREAM_AREA          equ PKT_READY-STREAM_AREA_SIZE
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
IR_MASK              equ STREAM_AREA+32    ; PORT_IR; 0 from a start bit to the next frame end, which with IR_QUIET 0 skips the decoder
IR_QUIET             equ STREAM_AREA+33    ; P35: the line level (0 or PORT_IR) the IR decoder sleeps through, its handler skipped; FF = awake
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
RANDBOW_DECK         equ STREAM_AREA+56    ; P46: bit 7 = RANDBOW, bits 0..RAINBOW_N-1 = RAINBOW's colors not yet dealt this round
ALT_NEXT             equ STREAM_AREA+57    ; P46: the editor inserts this after a FUNC2 key's B2
ALT_FX               equ STREAM_AREA+58    ; P48: FF = the UP or DOWN (P53: or RIGHT) that follows scrolls instead of wiping
SPARKLE              equ STREAM_AREA+59    ; P49/P50: the page's hold twinkles (1) or glimmers (2); 0 = a plain hold
SPARKLE_RND          equ STREAM_AREA+60    ; P49: the holds' 16-bit xorshift state, never 0
STACK_INIT           equ STREAM_AREA+62    ; P51: ram_probe's choices: the stack's top and bottom,
STACK_BOT            equ STREAM_AREA+64    ;   and the longest payload the buffer takes
PKT_MAX              equ STREAM_AREA+66
PORT_SAMPLE          equ STREAM_AREA+67    ; P35: PORT_IN as the ISR read it this interrupt
    IFDEF LITE
STREAM_AREA_SIZE     equ 68
    ELSE
FIELD_RET            equ STREAM_AREA+68    ; P54: where the parent resumes after a field; 0 = no field open
FIELD_MARK           equ STREAM_AREA+70    ; P54: the open field's channel marker
FIELD_PENDING        equ STREAM_AREA+72    ; P54: editor: FUNC + PROG pressed, next key is the field's digit
STREAM_AREA_SIZE     equ 73
    ENDIF
STACK_TOP            equ STREAM_AREA       ; first PUSH lands two below; SP is STACK_INIT, set at boot
STORE_TOP            equ STACK_TOP-STACK_SIZE-1 ; with a 32 K chip (16 K usable)
STORE_TOP_8K         equ STORE_TOP-RAM_ALT ; with the stock 8 K chip
STORE_TOP_2K         equ STREAM_AREA-1-0x3800 ; P51: LITE on a 2 K chip, the stack moved up
; store_init derives the warning level, the text allowance (301 = framing) and
; the B4 '1' size from whichever ceiling the RAM test picks.

; ---- Wire protocol bytes (protocol.md) ---------------------------------
FRAME_START          equ 0xb1
ADDR_BROADCAST       equ 0x2a        ; '*': processed, never answered
REPLY_ACK            equ 0x06
REPLY_NAK            equ 0x15
REPLY_BUSY           equ 0x18        ; a good frame refused because the editor is open (patch 45)
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
CMD_CONFIG           equ 0xb6        ; B6 index mask value (patch 35); taken in the editor too
CMD_EDITOR           equ 0xb7        ; B7 '1' opens the editor as a serial terminal, B7 '0' closes it (patch 45)
DONE_BYTE            equ 0x04        ; sent after processing when the frame's flag was 81 (patch 16)

; ---- Boot stub and OTA (ota.md) ------------------------------------------
STUB_END             equ 0x0240      ; the stub owns 0000-023F; the app starts at the jump table here
EE_PAGE              equ 64          ; the EEPROM's write page
OTA_VERIFY           equ 1           ; OTA status bytes (ota.md §4); 0 is ok
OTA_TIMEOUT          equ 2
OTA_RANGE            equ 3
OTA_CRC              equ 4
OTA_ARGS             equ 5
APP_START            equ STUB_END
APP_INT              equ STUB_END+3
APP_NMI              equ STUB_END+6
STUB_STACK           equ PKT_READY
STUB_RAM             equ 0x4000      ; stub_lib runs here (FRAMEBUF: idle at boot and during pkt_process)
STUB_LIB_SIZE        equ stub_lib_end-stub_lib            ; the whole library, copied at boot
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
;  BOOT STUB 0000-00FF (ota.md §4). Byte-identical in both banks and
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
        LD BC,EE_PAGE
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
        LD A,OTA_TIMEOUT
        JR pw_done

pw_verify:
        POP HL
        POP DE
        PUSH DE
        PUSH HL
        LD B,EE_PAGE

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
        LD A,OTA_VERIFY

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
        LD BC,EE_PAGE
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

; ---- app_start: cold start: set SP, run init routines, EI, jump to main loop
app_start:
        LD SP,STACK_TOP_2K      ; the buffer's top half: idle until init_vars picks the stack
        CALL init_vars
        LD SP,(STACK_INIT)
        LD HL,0
        LD (IR_REJ),HL
        LD (IR_REJ+2),HL
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
int_rx_start:                   ; out of line, so the idle path below falls straight through
        CALL rx_start
        JR int_tx

int_rx_active:
        CALL rx_phase_run
        JR int_tx

int_timer:
        EX AF,AF'
        EXX
        IN A,(PORT_IN)          ; P35: one sample for the IR gate at the end and
        LD (PORT_SAMPLE),A      ; P52: the receiver, which then samples every bit at the same point
        LD E,A
        LD A,(RX_PHASE)         ; P30: the serial bit engines, every interrupt,
        AND A                   ; so 1200 baud fits; idle they cost a line poll
        JR nz,int_rx_active
        BIT 3,E
        JR nz,int_rx_start

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
        AND LATCH_KEEP
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
        OR LATCH_PARK
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        XOR A                   ; parked: nothing more to do until the next row arms it
        LD (LIT_LIMIT),A

int_lit_on:
        LD HL,DISP_COUNT
        DEC (HL)
        JR z,int_disp_due

int_tick6:
        LD HL,TICK6_COUNT       ; counted down: an interrupt that makes no mark
        DEC (HL)                ; has no service to start
        JR nz,int_vector

int_tick6_mark:
        LD (HL),TICK6_DIV
        LD HL,TICK6_CAL         ; P35: counted here, where the mark is made, so a late
        INC (HL)                ; service cannot shrink the calibration's second
        LD HL,SVC_DUE
        SET 0,(HL)

int_svc:
        LD HL,SVC_ACTIVE
        BIT 7,(HL)
        JR nz,int_vector        ; the running service picks the new mark up
        LD (HL),0xff
        LD HL,tick6_service     ; the address is pushed so the service runs as the ISR returns
        PUSH HL

int_vector:
    IFNDEF LITE                 ; no receiver, and its timing wants 128 us interrupts
        ASSERT IR_QUIET == IR_MASK+1
        LD A,(PORT_SAMPLE)      ; P35: the decoder waiting on the line sleeps while it reads
        LD HL,IR_MASK           ; the level in IR_QUIET: its handler, ~90 cycles an interrupt,
        AND (HL)                ; is skipped. P52: rx_start zeroes both, so none runs while
        INC HL                  ; serial bytes arrive (it costs the receiver late samples)
        XOR (HL)
        JR z,int_vector_done
        LD (HL),0xff            ; awake: FF matches no level
        LD HL,(TICK_VECTOR)
        PUSH HL
    ENDIF

int_vector_done:
        EX AF,AF'
        EXX
        EI
        RET                     ; RETI only matters to Z80 peripherals; the board has none

int_disp_due:
        LD A,(DISP_STRETCH)
        LD C,A
        LD A,(DISP_ACC)
        ADD A,C
        LD B,TICK6_DIV

int_disp_carry:
        CP DISP_FRAC
        JR c,int_disp_reload
        SUB DISP_FRAC
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
        LD HL,TICK6_COUNT
        DEC (HL)
        JR nz,int_svc
        JR int_tick6_mark

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
        JR z,row_phase_step
        LD A,(CFG_FLAGS)        ; P35: muted or brightness 0: the row stays dark
        AND CFG_BRIGHT|CFG_MUTED
        CP CFG_MUTED
        JR nc,row_phase_step
        AND A
        JR z,row_phase_step
        LD A,(FB_OUT_LEN)
        LD B,A
        LD HL,ROW_INDEX
        LD A,ROWS-1             ; the rows' port addresses run backwards: 6 - index
        SUB (HL)
        LD HL,ROW_PORT
        OR (HL)
        LD C,A
        LD HL,(FB_OUT_PTR)
        LD DE,(BEEP_TICKS)
        LD A,D
        OR E
        JR z,row_out_color
        SET 5,C                 ; the beeper's bit in the row port

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
        AND LATCH_KEEP
        OR LATCH_PARK
        LD (CTRL_LATCH),A
        EI
        OUT (PORT_STROBE),A
        LD HL,ROW_INDEX
        LD A,ROWS-1
        SUB (HL)
        JR nz,row_select
        LD A,ROWS               ; row 6's code is 7, not 0

row_select:
        LD HL,LATCH_BIT7
        OR (HL)
        LD C,A
        CALL latch_row_dim      ; P35: lit now at full brightness, else by the ISR

row_phase_step:
        LD A,(ROW_PORT)
        CP PORT_ROW0
        JR z,row_phase_done
        LD A,PORT_ROW0
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
    IFNDEF LITE
        LD A,PORT_IR            ; the remote decoder runs again (rx_start)
        LD (IR_MASK),A
    ENDIF
        LD HL,RX_IDLE           ; P30: frames since the last start bit, held at 255
        INC (HL)
        JR nz,frame_idle_gap
        DEC (HL)

frame_idle_gap:
        LD A,(HL)               ; P45: a second of silence ends any frame: the next
        CP BAUD_IDLE_FRAMES     ; byte is timed as a frame's B1 (rx_start)
        JR nz,frame_idle_held
        XOR A
        LD (PKT_STATE),A

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
        EX DE,HL
        LD HL,FRAMEBUF_END      ; the window runs to the ring's end, then wraps
        OR A
        SBC HL,DE
        LD (FB_OUT_LEN),HL
        EX DE,HL
        LD HL,FRAME_COLS
        SBC HL,DE               ; no borrow came out of the first
        JR z,frame_window_wrap
        JR nc,frame_set_extra

frame_window_wrap:
        LD HL,FRAME_COLS
        LD (FB_OUT_LEN),HL
        LD HL,0

frame_set_extra:
        LD (FB_EXTRA_LEN),HL

frame_bit7_tick:
        LD HL,FRAME_COUNT
        INC (HL)
        LD A,(CFG_FLASH)        ; P35
        CP (HL)
        JR nz,frame_done
        LD (HL),0
        LD A,(LATCH_BIT7)
        XOR LATCH_BLINK
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
        AND ~LATCH_KEEP & 0xff
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
        LD A,IR_CODE_RELEASE
        LD (IR_CODE),A

; ---- rx_consume: Pop a byte from RX_FIFO; in normal mode feed the packet parser (or if IR_CODE=A4/A5 handle keypad); packet start needs 0xB1 while idle
;      P30: runs once per display frame, so it drains the FIFO rather than taking
;      one byte: 62 bytes a second was enough for 300 baud only
rx_consume:
        LD A,(MENU_ACTIVE)
        AND A
        JR z,rx_take
        CALL rx_key_ready       ; P45: frames are parsed in the editor too; a
        JR z,tick6_exit         ; terminal key stays in the FIFO for editor_getkey
        CALL rx_fifo_get
        JR nc,rx_have_byte
        JR tick6_exit

rx_take:
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
        XOR A                   ; P45: the remote's editor takes no serial keys
        LD (TERM_MODE),A

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
        LD A,(RX_BYTE)
        CP FRAME_START
        JR nz,rx_consume        ; P45: a byte outside a frame is never a key
        LD A,0xff
        LD (PKT_STATE),A
        LD HL,pkt_st_addr
        LD (PKT_VECTOR),HL
        JR rx_consume

; ---- tick6_exit
tick6_exit:
tick6_arm_row:
        LD A,0xff
        LD (ROW_OUT_PENDING),A
        LD A,PORT_40_OUT
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
        LD A,SEQ_EMPTY
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
        DEC HL
        LD B,SEQ_LIST_LEN-CHANNELS
        JR seq_one_loop

    IFNDEF LITE
; ---- seq_list_messages (P54): SEQ_LIST = channels 0..89, then FF
seq_list_messages:
        CALL seq_list_default
        LD HL,SEQ_LIST+CHANNELS-11
        LD B,10
        JR seq_one_loop
    ENDIF

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
        CP SEQ_EMPTY
        LD A,CHAN_DEMO
        JR z,seq_open_channel
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JR nz,seq_clamp_entry
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        LD HL,CFG_FLAGS         ; P35: the sequence starts over
        SET CFG_WRAPPED_BIT,(HL)
        JR seq_pick

seq_clamp_entry:
        CP CHAN_DEMO+1
        JR c,seq_advance
        LD A,CHAN_DEMO
        LD (HL),CHAN_DEMO

seq_advance:
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
        LD A,(CFG_FLAGS)
        RLA
        RET nc
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

; ---- store_repair: every boot: bad bytes -> ?, stray 03 -> space (store_fix_bad_bytes), then re-sequence
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
        LD A,MARK_LO+CHANNELS/10 ; the tens byte past the last channel
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
        CALL store_fill

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
        LD E,' '
        CP TEXT_END             ; a stray 03: store_add_ends puts the real ones back
        JR z,fixbad_put
        CALL char_flags
        JR nc,fixbad_next
        LD E,'?'

fixbad_put:
        LD (HL),E

fixbad_next:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,fixbad_loop
        RET

store_add_ends:
        LD HL,MSG_STORE+2
        LD BC,(STORE_TMP)
        DEC BC
        DEC BC

addend_loop:
        LD A,(HL)
        CALL is_marker
        JR nc,addend_next
        DEC HL
        LD (HL),TEXT_END
        INC HL
        INC HL
        DEC BC
        LD A,C
        OR B
        RET z

addend_next:
        INC HL
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
        CALL ram_probe
        LD HL,(STACK_BOT)       ; P40: lay the canary at the stack's bottom
        LD A,CANARY
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

; ---- cfg_sum (P35): A = 8-bit sum of the block before CFG_SUM, HL -> CFG_SUM.
;      The live bit of CFG_FLAGS changes without a reseal and does not count.
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
        AND CFG_LIVE
        LD B,A
        LD A,C
        SUB B
        RET

; ---- chan_boundary: a new message starts: a pending mute takes effect and the
;      wrapped flag is cleared until the sequence starts over again
chan_boundary:
        LD HL,CFG_FLAGS
        RES CFG_WRAPPED_BIT,(HL)
        BIT CFG_MUTE_PEND_BIT,(HL)
        RET z
        RES CFG_MUTE_PEND_BIT,(HL)
        SET CFG_MUTED_BIT,(HL)

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
    IFNDEF LITE
        LD (FIELD_RET),HL       ; P54
    ENDIF
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
        RET

space_seen:
        XOR A
        LD (FLASH_BIT),A
        LD A,(PREV_SPACE)
        AND A
        JR nz,double_space
        LD A,1
        LD (PREV_SPACE),A
        RET

double_space:
        LD A,(TEST_MODE)
        INC A
        RET z
        LD A,(CUR_COLOR)
        AND COLOR_FG
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
        CALL attr_draw_check    ; returns CUR_CHAR in A, and the four checks after it keep it
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
        CP KEY_TIME             ; stored, it draws a glyph of its own
        JR z,glyph_lookup
        BIT 7,A
        JR nz,class_high
        AND 0x60                ; 00-1F: attributes
        JP z,attr_control
        LD A,(CUR_CHAR)
        CP ATTR_TIME
        JP z,render_clock
        JR glyph_lookup         ; bit 7 is clear on this path

class_high:
        CP EURO_LO
        JP c,attr_color_speed
        CP GRAPH_BASE
        JR c,glyph_lookup
        AND 0xf0
        CP EURO_ROW_C
        JR z,glyph_lookup
        CP EURO_ROW_E
        JR z,glyph_lookup
        CP EURO_ROW_D
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
        INC A
        JR nz,glyph_graphic_check
        LD (CLK_RENDER_STEP),A
        DEC A
        LD (CLK_RENDERED),A

glyph_graphic_check:
        LD A,(CUR_CHAR)
        AND 0xf0
        JR nz,glyph_place
        LD A,(GLYPH_WIDTH)
        ADD A,A                 ; a graphic is drawn at twice its width, 31 columns at most
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
        LD HL,WIDE_SPACE_GLYPH
        LD (GLYPH_PTR),HL
        LD A,9                  ; WIDE_SPACE_GLYPH's columns
        LD (GLYPH_WIDTH),A

blit_setup:
        LD DE,(GLYPH_PTR)
        LD HL,(FB_COLPTR)
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD A,(MENU_ACTIVE)
        AND A
        JR z,blit_flash_bit
        LD A,COLOR_DEFAULT & COLOR_FG ; the editor draws in yellow
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
        LD A,COLOR_FLASH
        JR blit_set_c

blit_use_flash:
        LD A,(FLASH_BIT)

blit_set_c:
        LD C,A

blit_color:
        LD A,(CUR_CHAR)
        CP ' '
        LD A,(CUR_COLOR)
        JR nz,blit_write_color
        AND 0xf0                ; a space shows only the background

blit_write_color:
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
        SUB 1
        SBC A,A                 ; FF unless the editor is drawing
        LD (SCROLLING),A
        RET

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
        LD A,(EFFECT_ID)
        CP FX_RIGHT+FX_SCROLL   ; P53: SCROLL RIGHT's page moves sideways, so
        LD A,COLOR_DEFAULT      ; it is staged in its colors (yellow once it rests)
        JR nz,stage_color
        LD A,(CUR_CHAR)
        CP ' '
        LD A,(CUR_COLOR)
        JR nz,stage_color
        AND 0xf0                ; a space shows only the background

stage_color:
        LD HL,FLASH_BIT
        OR (HL)
        SET 7,A
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
        CP EURO_ROW_C
        LD E,GLYPH_ROW_C
        JR z,glyph_base_sel
        CP EURO_ROW_D
        LD E,GLYPH_ROW_D
        JR z,glyph_base_sel
        CP EURO_ROW_E
        LD E,GLYPH_ROW_E
        JR z,glyph_base_sel
        CP EURO_ROW_9
        LD E,GLYPH_ROW_9
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
        LD A,ATTR_LEFT
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
        CP ATTR_HOLD
        RET nz
        POP HL
        JP fx_attr

; ---- attr_rainbow: BC starts the per-character color cycle
attr_rainbow:
        LD A,(CUR_CHAR)
        CP ATTR_ALT
        JR z,rainbow_alt
        CP ATTR_RAINBOW
        JR nz,rainbow_step
        XOR A

rainbow_set:
        LD (RANDBOW_DECK),A
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
        SUB RAINBOW_N
        JR nc,rainbow_mod5
        ADD A,RAINBOW_N+1       ; -N..-1 -> 1..N
        LD B,A
        LD A,(RND_SEED)         ; P28: bit 7 of the index is the direction, from
        AND RAINBOW_REVERSE     ; the generator's best bit
        OR B
        LD (RAINBOW_IDX),A
        LD (MAGIC_COLOR_SET),A ; any non-zero value means "set"

rainbow_next:
        POP HL
        JP render_next_char

rainbow_alt:                    ; P46: B2 BC is RANDBOW; a B2 before anything else is skipped
        LD HL,(STORE_CURSOR)
        LD A,(HL)
    IFNDEF LITE
        SUB '0'                 ; P54: B2 '0'-'9' shows channel 90-99 here
        CP 10
        JP c,field_open
        LD A,(HL)
    ENDIF
        CP ' '                  ; P57: B2 20: FLUSH
        JP z,rainbow_alt_flush
        LD C,1
        CP ATTR_PAUSE           ; P49: B2 19: TWINKLE; P50: B2 BB: GLIMMER;
        JR z,rainbow_alt_sparkle ; modifiers for the page's hold, not effects
        INC C
        CP ATTR_HOLD
        JR z,rainbow_alt_sparkle
        CP ATTR_RIGHT           ; P53: B2 0F: the RIGHT scroll
        JR z,rainbow_alt_fx
        AND 0xfe
        CP ATTR_UP              ; P48: B2 1A / B2 1B: the UP or DOWN scrolls
        JR nz,rainbow_alt_bc

rainbow_alt_fx:
        LD A,0xff
        LD (ALT_FX),A

rainbow_alt_bc:
        LD A,(HL)
        CP ATTR_RAINBOW
        LD A,ATTR_ALT
        RET nz
        INC HL
        LD (STORE_CURSOR),HL
        LD A,0x80               ; an empty deck: the first character deals a new one
        JR rainbow_set

rainbow_alt_sparkle:
        LD A,C
        LD (SPARKLE),A
        INC HL
        LD (STORE_CURSOR),HL
        JR rainbow_next

rainbow_step:
        LD A,(RAINBOW_IDX)
        AND A
        LD A,(CUR_CHAR)
        RET z
        CP ' '
        RET z
        CALL char_flags
        RET nz
        LD A,(RAINBOW_IDX)
        LD B,A
        LD A,(RANDBOW_DECK)
        RLCA
        JR c,randbow_deal
        LD A,B
        AND 7
        BIT 7,B
        JR nz,rainbow_back
        INC A                   ; forward: 1..N then round to 1
        CP RAINBOW_N+1
        JR c,rainbow_lookup
        LD A,1
        JR rainbow_lookup

rainbow_back:
        DEC A                   ; P28: reverse: N..1 then round to N
        JR nz,rainbow_lookup
        LD A,RAINBOW_N

rainbow_lookup:
        LD E,A
        LD D,0
        LD HL,RAINBOW_COLORS
        ADD HL,DE
        LD A,(HL)

rainbow_apply:
        AND 15
        LD (CUR_COLOR),A
        LD A,B
        AND RAINBOW_REVERSE     ; keep the direction with the new index
        OR E
        LD (RAINBOW_IDX),A
        LD A,(CUR_CHAR)
        RET

; ---- randbow_deal (P46): B = RAINBOW_IDX. RAINBOW's five colors dealt in a
;      shuffled order, a new deck when all five are out; a new deck never starts
;      with the color that ended the last, so no color shows twice in a row
randbow_deal:
        LD HL,RANDBOW_DECK
        LD A,(HL)
        AND (1 << RAINBOW_N)-1
        JR nz,randbow_draw
        LD (HL),0x80+(1 << RAINBOW_N)-1

randbow_draw:
        LD A,(RND_SEED)         ; 5x+1: a full period, so every color turns up
        LD C,A
        ADD A,A
        ADD A,A
        ADD A,C
        INC A
        LD (RND_SEED),A

randbow_mod5:
        SUB RAINBOW_N
        JR nc,randbow_mod5
        ADD A,RAINBOW_N
        LD E,A                  ; 0..N-1
        INC A
        XOR B
        AND 7
        JR z,randbow_draw       ; the color just shown
        LD C,E
        LD A,1

randbow_bit:
        DEC C
        JP m,randbow_take
        ADD A,A
        JR randbow_bit

randbow_take:
        AND (HL)
        JR z,randbow_draw       ; already dealt this round
        XOR (HL)
        LD (HL),A
        LD A,E
        INC A
        JR rainbow_lookup

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
        CP TEXT_END
        RET z
        JR remark_skip

remark_end:
        POP HL

render_next_char_jr4:
        JP render_next_char

; ---- attr_wait_check: BA WAIT: flush, then spin until SPACE or a packet
attr_wait_check:
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
        JR c,draw_bad_hex
        PUSH AF
        CALL fetch_char
        LD A,(CUR_CHAR)
        CALL hex_digit_value
        JR c,draw_pop_odd
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

; ---- hex_digit_value: A = value of ASCII hex digit, CY if not one
hex_digit_value:
        CP '0'
        JR c,hexval_bad
        CP '9'+1
        JR c,hexval_ok
        AND 0xdf                ; upper case
        CP 'A'
        JR c,hexval_bad
        CP 'F'+1
        JR nc,hexval_bad
        AND 15
        ADD A,9

hexval_ok:
        AND 15
        RET

hexval_bad:
        SCF
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
        LD A,FONT_BOLD
        LD (FONT_MODE),A
        LD A,(MAGIC_LAST_CHAR)
        LD HL,MAGIC_PUNCT
        LD BC,MAGIC_PUNCT_LEN
        CPIR
        JP z,magic_reseed
        LD A,' '
        LD (MAGIC_LAST_CHAR),A
        RET

magic_attr:
        CP ATTR_HOLD
        JR z,magic_effect_attr
        CP ATTR_RIGHT
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
        CP 0x20                 ; 00-1F: attributes
        RET c
        CP COLOR_BASE
        RET nc

magic_printable:
        LD A,(MAGIC_LAST_CHAR)
        CP ' '
        JR z,magic_word_start
        LD A,(CUR_CHAR)
        LD (MAGIC_LAST_CHAR),A
        RET

magic_word_start:
        LD A,(CUR_CHAR)
        LD (MAGIC_LAST_CHAR),A
        CP '$'
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
        LD B,8                  ; a word of 8 letters or more stays plain
        LD HL,(STORE_CURSOR)

magic_scan_word:
        LD A,(HL)
        AND 0x5f                ; upper case
        CP 'A'
        JR c,magic_short_word
        CP 'Z'+1
        JR nc,magic_short_word
        INC HL
        DJNZ magic_scan_word
        JR magic_font_normal

magic_short_word:
        LD A,B
        CP 6                    ; and one of 1 or 2: 3-7 letters may be bold or italic
        JR nc,magic_font_normal
        LD A,(RND_SEED)
        ADD A,(HL)
        LD HL,NMI_COUNT
        ADD A,(HL)
        LD (RND_SEED),A
        AND 3
        LD A,FONT_BOLD
        JR nz,magic_font_set
        LD A,FONT_ITALIC
        JR magic_font_set

magic_font_normal:
        XOR A

magic_font_set:
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
        JR magic_color_clear

magic_reseed:
        LD A,(NMI_COUNT)
        AND 3
        ADD A,2
        LD (RND_VAL),A

magic_color_check:
        LD A,(MAGIC_COLOR_SET)
        AND A
        JR z,magic_next_color

magic_color_clear:
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
        LD BC,MAGIC_CLASH_LEN
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
        AND COLOR_FG|COLOR_FLASH
        LD (CUR_COLOR),A

magic_reset_words:
        XOR A
        LD (MAGIC_WORD_COUNT),A

magic_ret:
        RET

; ---- unfetch_char: STORE_CURSOR back one byte
unfetch_char:
        LD HL,(STORE_CURSOR)
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        RET z
        ADD HL,DE
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
        AND FONT_BIG
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
        BIT FONT_BOLD_BIT,A
        RET z

bold_expand:
        LD DE,GLYPH_BUF
        CALL glyph_widen
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
        LD B,4
        LD A,0x7f

bold_scan_7f:                   ; three 7F in a row from one of the first four columns
        CP (HL)
        INC HL
        JR nz,bold_scan_next
        CP (HL)
        JR nz,bold_scan_next
        INC HL
        CP (HL)
        DEC HL
        JR z,bold_collapse

bold_scan_next:
        DJNZ bold_scan_7f
        RET

bold_collapse:                  ; HL = the second of the three
        LD D,H
        LD E,L
        DEC DE
        LD BC,0x1c
        LDIR
        LD HL,GLYPH_WIDTH
        DEC (HL)

bold_ret:
        RET

; ---- glyph_widen: the glyph into the buffer at DE, which becomes GLYPH_PTR, each
;      lit column OR-ed into the next as well. C = the columns written, DE -> the
;      zero written after them, A = 0.
glyph_widen:
        LD HL,(GLYPH_PTR)
        LD (GLYPH_PTR),DE
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD C,0

widen_loop:
        LD A,(HL)
        LD (DE),A
        INC HL
        AND A
        JR z,widen_next
        OR (HL)
        INC DE
        INC C
        LD (DE),A

widen_next:
        INC DE
        INC C
        DJNZ widen_loop
        XOR A
        LD (DE),A
        RET

; ---- glyph_italic: shear the glyph into GLYPH_BUF_ITALIC (width + 2)
glyph_italic:
        LD A,(FONT_MODE)
        BIT FONT_ITALIC_BIT,A
        RET z
        LD HL,(GLYPH_PTR)
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD DE,GLYPH_BUF_ITALIC
        LD B,0
        LDIR
        LD B,A
        EX DE,HL                ; the column after the last

italic_loop:
        LD A,(HL)
        AND 3
        INC HL
        INC HL
        OR (HL)                 ; rows 0-1 move two columns right
        LD (HL),A
        DEC HL
        DEC HL
        LD A,(HL)
        AND 12
        INC HL
        OR (HL)                 ; rows 2-3 one
        LD (HL),A
        DEC HL
        LD A,(HL)
        AND 0xf0
        LD (HL),A
        DEC HL
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
        BIT FONT_BIG_BIT,A
        RET z
        LD DE,GLYPH_BUF_BIG
        CALL glyph_widen
        DEC DE
        LD (DE),A
        DEC DE
        LD (DE),A
        LD A,C
        DEC A
        LD (GLYPH_WIDTH),A

big_ret:
        RET

; ---- fb_ptr_inc: HL++ inside the FRAMEBUF ring
        ASSERT (FRAMEBUF >> 8) == (FRAMEBUF_END >> 8)   ; the ring lies in one page
fb_ptr_inc:
        INC HL
        PUSH AF
        LD A,L
        CP FRAMEBUF_END & 0xff
        JR nz,fbinc_ret
        LD L,FRAMEBUF & 0xff

fbinc_ret:
        POP AF
        RET

; ---- fb_ptr_add: HL += DE inside the FRAMEBUF ring
fb_ptr_add:
        PUSH AF
        PUSH DE
        ADD HL,DE
        LD DE,-FRAMEBUF_END & 0xffff
        ADD HL,DE               ; CY: past the end, HL = how far; else add the end back
        LD DE,FRAMEBUF
        JR c,fbadd_ret
        LD E,FRAMEBUF_END & 0xff

fbadd_ret:
        ADD HL,DE
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

; ---- fx_show: the rows on, then A frames of them
fx_show:
        LD (FRAME_DELAY),A
        LD A,0xff
        LD (DISP_ON),A
        JR wait_frame_delay

; ---- wait_row6: spin until the display is on row 6
wait_row6:
        LD A,(ROW_INDEX)
        CP ROWS-1
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
;      character next, after any colors, waits for the full catch-up.
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
        DEC HL

crawl_peek:                     ; colors (80-93) go into the next glyph's column in the
        INC HL                  ; same render step: judge the byte after them
        LD A,(HL)
        AND 0xe0
        CP COLOR_BASE
        JR z,crawl_peek
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
        LD A,COLOR_DEFAULT & COLOR_FG
        LD (CUR_COLOR),A

fx_toggle_flush:
        LD HL,FLUSH_PENDING
        LD A,(HL)
        LD (HL),0
        INC A                   ; FF: the flush has run, no staging until the next effect
        JR z,fx_reset_stage
        LD A,FRAME_COLS
        CP A                    ; Z on both paths: render_loop tests it when this returns

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
        LD A,FONT_BOLD
        JR attr_set_font

attr_not_bold:
        CP ATTR_ITALIC
        JR nz,attr_not_italic
        LD A,FONT_ITALIC
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
        LD A,FONT_BIG

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
        DKEY ATTR_HALT, fx_halt
        DKEY ATTR_BEEP, fx_beep
    IFDEF LITE
        DKEY TEXT_END, fx_end_of_channel
    ELSE
        DKEY TEXT_END, field_close
    ENDIF
        DKEY ATTR_LEFT, fx_left
        DKEY ATTR_PAUSE, fx_pause
        DKEY ATTR_UP, fx_up
        DKEY ATTR_DOWN, fx_down
        DKEY ATTR_RIGHT, fx_right
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
        LD A,(CFG_FLAGS)
        AND CFG_QUIET
        RET nz
        PUSH HL
        LD HL,BEEP_LEN
        LD (BEEP_TICKS),HL
        POP HL
        RET

; ---- fx_end_of_channel
fx_end_of_channel:
        CALL effect_none
        CALL scroll_off_text
        LD SP,(STACK_INIT)
        JP main_loop

; ---- the movement attributes: 0F RIGHT (effect 4), 18 LEFT (plain crawl, no
;      staging), BB HOLD (5), 19 PAUSE (1), 1A UP (2), 1B DOWN (3); after B2 the
;      scrolls, effect + 4. The staged ones take the whole frame; all but HOLD
;      stop the window first.
fx_right:
        LD A,FX_RIGHT
        LD HL,fxv_right
        JR fx_alt

fx_pause:
        LD A,FX_PAUSE
        LD HL,fxv_pause
        JR fx_staged

fx_hold:
        LD A,FX_HOLD
        LD HL,fxv_hold
        JR fx_set

fx_up:
        LD A,FX_UP
        JR fx_vertical

fx_down:
        LD A,FX_DOWN

fx_vertical:
        LD HL,fxv_wipe_updown

fx_alt:
        LD C,A
        LD A,(ALT_FX)           ; P48: after B2, SCROLL UP (6) or SCROLL DOWN (7); P53: RIGHT (8)
        AND A
        LD A,C
        JR z,fx_staged
        XOR A
        LD (ALT_FX),A
        LD A,C
        ADD A,FX_SCROLL
        LD HL,fxv_scroll

fx_staged:
        LD C,A
        XOR A
        LD (SCROLLING),A
        LD A,C

fx_set:
        LD (EFFECT_ID),A
        LD (EFFECT_VECTOR),HL
        XOR A                   ; P49/P50: a modifier follows its effect
        LD (SPARKLE),A
        LD A,FRAME_COLS
        LD (COL_COUNT),A
        JR render_next_char_jr2

fx_left:
        CALL effect_none
        LD (COL_COUNT),A
        LD (SPARKLE),A
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
        LD B,FRAMEBUF_SIZE
        CALL fb_colors_range
        LD A,(WINDOW_COLOR)
        AND COLOR_FLASH
        OR COLOR_DEFAULT
        LD (WINDOW_COLOR),A
        LD (ROW_COLOR),A
        LD A,(MAGIC_MODE)
        AND A
        RET z
        LD A,COLOR_DEFAULT & COLOR_FG
        LD (CUR_COLOR),A
        RET

; ---- fb_colors_range (P53): the B bytes from HL, color bytes to 8F, flash kept
fb_colors_range:
        BIT 7,(HL)
        JR z,fbcol_next
        LD A,(HL)
        AND COLOR_FLASH
        OR COLOR_DEFAULT
        LD (HL),A

fbcol_next:
        INC HL
        DJNZ fb_colors_range
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
        AND COLOR_BG
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
        OR COLOR_FG
        LD (CUR_COLOR),A

back_set:
        XOR A
        LD (RAINBOW_IDX),A
        LD A,(CUR_CHAR)
        AND 3
        RRCA
        RRCA
        RRCA                    ; the background, bits 5-6
        LD L,A
        LD A,(CUR_COLOR)
        AND COLOR_FG
        OR L
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
        LD C,A
        AND 0xf0
        CP GRAPH_BASE
        JR nz,tinyg_check
        LD A,C
        AND 15
        LD (CUR_CHAR),A
        JR tinyg_lookup

tinyg_check:
        LD A,C
        AND 0x60
        JR z,tinyg_stop
        LD A,C
        CP ATTR_TIME
        JR z,tinyg_stop
        BIT 7,A
        JR z,tinyg_lookup
        CP EURO_LO
        JR c,tinyg_stop
        CP 0x9e                 ; TINY has no 9E, 9F or DB-DF
        JR c,tinyg_lookup
        AND 0xf0
        CP EURO_ROW_C
        JR z,tinyg_lookup
        CP EURO_ROW_E
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
        AND CFG_BRIGHT|CFG_MUTED ; when muted or at brightness 0
        CP CFG_MUTED
        JR nc,tiny_row_done
        AND A
        JR z,tiny_row_done

; ---- disp_blank_row: Send 0x8F (all off) to the current row
disp_blank_row:
        LD HL,ROW_INDEX
        LD A,ROWS-1
        SUB (HL)
        OR PORT_ROW0
        LD C,A
        LD HL,TXBUF             ; P7: see tiny_copy_frame
        LD B,FRAME_COLS
        LD A,COLOR_DEFAULT
        OUT (C),A
        OTIR
        OUT (PORT_STROBE),A
        LD HL,ROW_INDEX
        LD A,ROWS-1
        SUB (HL)
        JR nz,tiny_row_select
        LD A,ROWS               ; row 6's code is 7, not 0

tiny_row_select:
        LD HL,LATCH_BIT7
        OR (HL)
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
        CP ROWS
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
        LD A,1
        CALL fx_show
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
        LD BC,FRAMEBUF_SIZE*0x100+COLOR_DEFAULT
        CALL mem_fill
        CALL fxv_pointers
        LD A,(COL_COUNT)
        LD C,A
        LD B,0
        ADD HL,BC               ; both pointers to the last column
        EX DE,HL
        ADD HL,BC
        EX DE,HL
        LD B,A
        INC B

hold_wait_row:
        CALL wait_row6
        LD A,(HL)
        LD (DE),A
        DEC HL
        DEC DE
        LD A,1
        CALL fx_show
        DJNZ hold_wait_row
        JR fx_hold_done

; ---- fxv_pause: effect 1: copy the whole stage, then FRAME_DELAY 0x50
fxv_pause:
        CALL fxv_prepare
        CALL copy_cols

; ---- fx_hold_done: an effect has its frame up: hold it, then end the effect
fx_hold_done:
        XOR A
        LD (SCROLLING),A
        LD HL,SPARKLE           ; P49/P50: TWINKLE or GLIMMER holds instead
        LD A,(HL)
        LD (HL),0
        DEC A
        JP z,fxv_twinkle
        DEC A
        JP z,fxv_glimmer
        LD A,(CFG_HOLD)         ; P35
        LD (FRAME_DELAY),A
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
        CP FX_UP
        LD C,0x80
        JR z,wipev_start
        LD C,1

wipev_start:
        LD A,8                  ; passes

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
        INC A
        LD A,COLOR_DEFAULT
        JR nz,wipev_store
        LD A,(HL)

wipev_store:
        LD (DE),A
        INC HL
        INC DE
        DJNZ wipev_col
        LD A,FX_STEP_FRAMES
        CALL fx_show
        POP BC
        POP DE
        POP HL
        LD A,(EFFECT_ID)
        CP FX_UP
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

; ---- fxv_scroll (P48): effects 6 (SCROLL UP) and 7 (SCROLL DOWN): the staged page
;      pushes the panel's page out one row a step, in yellow (vertical motion shows
;      only pixels, so the color bytes stay out), then rests in its colors. The
;      outgoing page waits in GLYPH_BUF, the incoming one SCROLL_IN bytes up the ring.
;      P53: effect 8 (SCROLL RIGHT) shares the setup and goes to scroll_right.
fxv_scroll:
        LD HL,(FB_OUT_PTR)      ; the panel as it stands, unrolled from the ring
        LD DE,GLYPH_BUF
        LD BC,(FB_OUT_LEN)
        CALL scroll_copy
        LD HL,FRAMEBUF
        LD BC,(FB_EXTRA_LEN)
        CALL scroll_copy
        XOR A
        LD (DISP_ON),A
        CALL fxv_prepare
        LD A,(EFFECT_ID)
        CP FX_RIGHT+FX_SCROLL
        JR z,scroll_right
        LD A,(ROW_COLOR)        ; P53: the moving frames have no color bytes, so the
        AND COLOR_FLASH         ; row color is all they show: yellow, not what the last
        OR COLOR_DEFAULT        ; crawl left there
        LD (ROW_COLOR),A
        LD BC,SCROLL_IN
        EX DE,HL
        ADD HL,BC
        EX DE,HL
        CALL copy_cols
        LD C,1                  ; step 1..6; 7 is the page itself

scroll_step:
        CALL wait_row6
        LD IX,FRAMEBUF
        LD DE,GLYPH_BUF
        LD B,FRAME_COLS

scroll_col:
        LD A,(DE)
        CALL scroll_pixels
        LD H,A
        LD A,(IX+SCROLL_IN)
        CALL scroll_pixels
        LD L,A
        PUSH BC
        LD B,C
        LD A,(EFFECT_ID)
        RRA
        JR c,scroll_col_down
        LD A,H                  ; UP: incoming in H, outgoing x2 in L, both moved
        ADD A,A                 ; down the 15-bit pair k+1 times
        LD H,L
        LD L,A
        INC B

scroll_shift_up:
        SRL H
        RR L
        DJNZ scroll_shift_up
        LD A,L
        JR scroll_col_put

scroll_col_down:
        SLA L                   ; DOWN: outgoing in H, incoming x2 in L, moved up k times

scroll_shift_down:
        ADD HL,HL
        DJNZ scroll_shift_down
        LD A,H

scroll_col_put:
        POP BC
        AND 0x7f
        LD (IX+0),A
        INC IX
        INC DE
        DJNZ scroll_col
        LD A,FX_STEP_FRAMES
        CALL fx_show
        INC C
        LD A,C
        CP ROWS
        JR c,scroll_step
        CALL wait_row6
        LD HL,FRAMEBUF+SCROLL_IN
        LD DE,FRAMEBUF
        LD BC,FRAME_COLS
        LDIR
        JP fx_hold_done

; ---- scroll_right (P53): step k shows the incoming page's last k columns, then the
;      outgoing page's first FRAME_COLS-k, one step a frame. Each step is built in the
;      hidden half and flipped in with its ROW_COLOR just after a frame end, so every
;      row moves at once. TXBUF is widened in place to the whole incoming frame, with
;      the row color both pages start in just below it: that byte ends the scan for the
;      color in force at the left edge and goes where the pages meet, so the outgoing
;      page keeps its start color.
scroll_right:
        LD A,(ROW_COLOR)
        LD (TXBUF-1),A
        LD HL,GLYPH_BUF         ; the panel's page shown until the first flip
        LD DE,FRAMEBUF
        LD BC,FRAME_COLS
        LDIR
        LD A,(COL_COUNT)
        AND A
        JR z,scroll_right_wide
        LD C,A
        LD B,0
        LD HL,TXBUF-1
        ADD HL,BC               ; the text's last column
        LD DE,(STAGE_OFFSET)
        PUSH DE
        EX DE,HL
        ADD HL,DE               ; and where it goes, centered
        EX DE,HL
        LDDR
        POP BC
        LD B,C                  ; the left margin, cleared
        INC B
        LD HL,TXBUF
        JR scroll_right_clear

scroll_right_margin:
        LD (HL),0
        INC HL

scroll_right_clear:
        DJNZ scroll_right_margin

scroll_right_wide:
        LD C,1

scroll_right_step:
        PUSH BC
        LD A,FRAME_COLS
        SUB C
        LD E,A
        LD D,0
        LD HL,TXBUF
        ADD HL,DE
        PUSH DE
        PUSH HL
        CALL fb_back
        LD B,0
        LDIR                    ; the incoming page's last k columns at the left
        POP HL
        POP BC                  ; what is left of the outgoing page
        PUSH HL
        LD A,B
        OR C
        JR z,scroll_right_edge
        DEC DE
        LD A,(DE)               ; an unlit column where the pages meet takes
        AND A                   ; the outgoing page's start color
        JP m,scroll_right_join
        JR nz,scroll_right_out

scroll_right_join:
        LD A,(TXBUF-1)
        LD (DE),A

scroll_right_out:
        INC DE
        LD HL,GLYPH_BUF
        LDIR

scroll_right_edge:
        POP HL

scroll_right_color:
        DEC HL
        LD A,(HL)
        OR A
        JP p,scroll_right_color
        POP BC
        PUSH BC
        LD D,A
        LD A,C
        CP FRAME_COLS
        LD A,D
        JR nz,scroll_right_show
        AND COLOR_FLASH         ; the last step is the page at rest: yellow, as
        OR COLOR_DEFAULT        ; every page that stands still
        PUSH AF
        CALL fb_back
        EX DE,HL
        LD B,FRAME_COLS
        CALL fb_colors_range
        POP AF

scroll_right_show:
        PUSH AF
        LD A,1
        CALL fx_show
        CALL fb_flip
        POP AF
        LD (ROW_COLOR),A
        POP BC
        INC C
        LD A,C
        CP FRAME_COLS+1
        JR c,scroll_right_step
        LD HL,TXBUF             ; the staged page yellow too, for the holds
        LD B,FRAME_COLS
        CALL fb_colors_range
        LD HL,(FB_OUT_PTR)      ; back to the front half and the usual pointers
        LD DE,FRAMEBUF
        LD BC,FRAME_COLS
        LDIR
        CALL fxv_pointers
        LD A,(COL_COUNT)        ; and TXBUF back as staged
        AND A
        JR z,fx_hold_done_jr1
        LD C,A
        LD B,0
        LD HL,(STAGE_OFFSET)
        LD DE,TXBUF
        ADD HL,DE
        LDIR

fx_hold_done_jr1:
        JP fx_hold_done

; ---- fxv_twinkle (P49): TWINKLE's hold: the page held CFG_HOLD frames; every
;      TWINKLE_TICK frames a fresh TWINKLE_DOTS random spots in the text go dark
fxv_twinkle:
        CALL sparkle_init       ; frames are built in the hidden half and flipped in
        CALL twinkle_seed
        LD A,(CFG_HOLD)

twinkle_tick:
        PUSH AF
        LD A,TWINKLE_TICK       ; counted from here: the dots take a good part of a frame
        LD (FRAME_DELAY),A
        CALL page_back
        LD C,TWINKLE_DOTS

twinkle_dot:
        LD HL,(STAGE_OFFSET)
        LD A,L
        ADD A,A
        NEG
        ADD A,FRAME_COLS        ; the text's width: it is centered
        CALL twinkle_pick       ; leaves D = 0
        LD E,A
        ADD HL,DE
        CALL fb_back
        ADD HL,DE
        BIT 7,(HL)              ; a color byte has no pixels
        JR nz,twinkle_next
        LD A,ROWS               ; one of the column's rows
        CALL twinkle_pick
        LD B,A
        INC B
        LD A,0x80

twinkle_bit:
        RLCA
        DJNZ twinkle_bit
        CPL
        AND (HL)
        LD (HL),A

twinkle_next:
        DEC C
        JR nz,twinkle_dot
        CALL wait_frame_delay   ; no wait_row6: it ends just after row 6 and would add a frame
        CALL fb_flip
        POP AF
        SUB TWINKLE_TICK
        JR nc,twinkle_tick

sparkle_end:
        CALL twinkle_page
        JP fx_done

; ---- fxv_glimmer (P50): GLIMMER's hold: the page held CFG_HOLD frames, with dark
;      diagonal stripes rolling through it, up or down at random
fxv_glimmer:
        CALL sparkle_init
        CALL twinkle_seed
        LD A,2
        CALL twinkle_pick
        RRCA
        LD C,A                  ; bit 7: the stripes slant the other way
        LD A,2
        CALL twinkle_pick
        NEG
        AND 6
        INC A
        OR C
        LD E,A                  ; rolls a tick: 1 is a row down, 7 a row up
        LD D,GLIMMER_BAND
        LD A,(CFG_HOLD)

glimmer_tick:
        PUSH AF
        LD A,GLIMMER_TICK
        LD (FRAME_DELAY),A
        PUSH DE
        CALL page_back
        CALL fb_back
        EX DE,HL
        POP DE
        LD B,FRAME_COLS
        LD A,D

glimmer_col:
        BIT 7,(HL)              ; a color byte takes no column on the panel
        JR nz,glimmer_next
        LD C,A
        CPL
        AND (HL)
        LD (HL),A
        LD A,C
        RLCA                    ; a row lower each column to the right
        BIT 7,E
        JR z,glimmer_next
        RRCA                    ; or a row higher
        RRCA

glimmer_next:
        INC HL
        DJNZ glimmer_col
        LD A,E
        AND 7
        LD B,A

glimmer_roll:
        RLC D
        DJNZ glimmer_roll
        PUSH DE
        CALL wait_frame_delay
        CALL fb_flip
        POP DE
        POP AF
        SUB GLIMMER_TICK
        JR nc,glimmer_tick
        JR sparkle_end

; ---- sparkle_init: the effect's last frame, up in the front half, into the back
;      too, so the columns around the text (HOLD's fill) match
sparkle_init:
        LD HL,FRAMEBUF
        LD DE,FRAMEBUF_ROW1
        LD BC,FRAME_COLS
        LDIR
        RET

; ---- page_back: the staged page into the hidden half (DE = its start + offset)
page_back:
        CALL fb_back
        LD HL,(STAGE_OFFSET)
        ADD HL,DE
        EX DE,HL
        LD HL,TXBUF
        JR copy_cols

; ---- fb_back: DE = the framebuffer half the panel is not showing
fb_back:
        LD DE,FRAMEBUF
        LD A,(FB_OUT_PTR)       ; FRAMEBUF's low byte is 0
        AND A
        RET nz
        LD E,FRAME_COLS
        RET

; ---- fb_flip: show the hidden half; just after a frame end, so no row pass is split
fb_flip:
        CALL fb_back
        LD (FB_OUT_PTR),DE
        LD (FB_COL),DE          ; the frame end resets FB_OUT_PTR to FB_COL
        RET

; ---- twinkle_page: the staged page up again
twinkle_page:
        CALL fxv_pointers

; ---- copy_cols: the COL_COUNT staged columns, HL to DE. Here, so the emulator's
;      sparkle gates see the page copy between twinkle_page and twinkle_seed.
copy_cols:
        LD A,(COL_COUNT)
        LD C,A
        LD B,0
        LDIR
        RET

; ---- twinkle_seed: SPARKLE_RND = a nonzero seed from R and RND_SEED
twinkle_seed:
        LD A,R
        LD HL,RND_SEED
        ADD A,(HL)
        LD (HL),A
        LD H,A
        LD A,R
        OR 1
        LD L,A
        LD (SPARKLE_RND),HL
        RET

; ---- twinkle_pick: A = n -> A = a random 0..n-1, the high byte of the next SPARKLE_RND * n
twinkle_pick:
        PUSH HL
        PUSH BC
        LD E,A
        LD D,0
        LD HL,(SPARKLE_RND)     ; xorshift 7,9,8: an 8-bit generator reaches only
                                ; 256 spots, each pick fixed by the one before
        LD A,H
        RRA
        LD A,L
        RRA
        XOR H
        LD H,A
        LD A,L
        RRA
        LD A,H
        RRA
        XOR L
        LD L,A
        XOR H
        LD H,A
        LD (SPARKLE_RND),HL
        LD L,D
        LD B,8

twinkle_mul:
        ADD HL,HL
        JR nc,twinkle_mul_next
        ADD HL,DE

twinkle_mul_next:
        DJNZ twinkle_mul
        LD A,H
        POP BC
        POP HL
        RET

; ---- scroll_copy: LDIR that copies nothing for BC = 0
scroll_copy:
        LD A,B
        OR C
        RET z
        LDIR
        RET

; ---- scroll_pixels: A = a column's pixels; a color byte has none
scroll_pixels:
        OR A
        RET p
        XOR A
        RET

; ---- store_clear_all: Reset MSG_STORE: 100 empty channels D0..? then DA
store_clear_all:
        LD HL,MSG_STORE
        LD DE,MARK_LO*0x100+MARK_LO
        CALL store_fill
        LD A,MARK_HI            ; not a channel: init_sequence loads the default
        JP seq_list_one

; ---- store_fill: from HL, the empty channels from marker E (tens), D (units)
;      to the last, then the DA, which HL is left on
store_fill:
        LD (HL),E
        LD A,E
        CP MARK_LO+CHANNELS/10  ; the tens byte past the last channel
        JR z,fill_end
        INC HL
        LD (HL),D
        INC HL
        LD (HL),TEXT_END
        INC HL
        INC D
        LD A,D
        CP MARK_HI
        JR nz,store_fill
        LD D,MARK_LO
        INC E
        JR store_fill

fill_end:
        LD (HL),MARK_HI
        RET

; ---- ram_probe (P13, P51): which chip, from where it mirrors FRAMEBUF ->
;      STORE_LIMIT, STACK_INIT, STACK_BOT and PKT_MAX. FRAMEBUF is scratch at
;      boot (the stub's library copy, cleared by init_render).
ram_probe:
        LD HL,STACK_TOP
        LD (STACK_INIT),HL
        LD A,PKT_MAX_FULL
        LD (PKT_MAX),A
        LD HL,FRAMEBUF+RAM_ALT
        CALL ram_mirrors
        LD HL,STORE_TOP
        JR nz,ram_probe_done    ; 16 K
    IFDEF LITE
        LD HL,FRAMEBUF+0x0800
        CALL ram_mirrors
        LD HL,STORE_TOP_8K
        JR nz,ram_probe_done
        ASSERT PKT_BUF+PKT_MAX_2K <= STACK_TOP_2K-STACK_SIZE
        LD HL,STACK_TOP_2K      ; 2 K: the stack moves into the buffer's top half
        LD (STACK_INIT),HL
        LD A,PKT_MAX_2K
        LD (PKT_MAX),A
        LD HL,STORE_TOP_2K
    ELSE
        LD HL,STORE_TOP_8K
    ENDIF

ram_probe_done:
        LD (STORE_LIMIT),HL
        LD HL,(STACK_INIT)
        LD DE,-STACK_SIZE
        ADD HL,DE
        LD (STACK_BOT),HL
        RET

; ---- ram_mirrors: HL = an address -> Z if it mirrors FRAMEBUF. The byte at
;      HL is put back: on a larger chip it is in the store.
ram_mirrors:
        LD C,(HL)
        LD A,0x55
        LD (FRAMEBUF),A
        CPL
        LD (HL),A
        LD A,(FRAMEBUF)
        LD (HL),C
        CP 0xaa                 ; 55 complemented: HL's write landed in FRAMEBUF
        RET

; ---- store_init: message-store init. From ram_probe's ceiling, sets its
;      three derived constants, writes the 0xDA store terminator at the
;      ceiling, then clears PKT_READY and the parser state (the buffer may
;      hold the stack, P51).
;      0x43DE = ceiling-100, the "100 KEYS LEFT" trip point (used at 0x2601).
;      0x43DC = free text bytes, the scan bound used by store_repair at 0x0481.
store_init:
        LD HL,(STORE_LIMIT)
        LD (STORE_END),HL
        PUSH HL
        LD DE,-100 & 0xffff     ; the warning starts 100 bytes short of the top
        ADD HL,DE
        LD (STORE_WARN_LIMIT),HL
        POP HL
        LD DE,-(MSG_STORE-1) & 0xffff
        ADD HL,DE               ; size = top - MSG_STORE + 1
        LD (STORE_SIZE),HL
        LD DE,-(CHANNELS*3+1) & 0xffff ; the empty channels' framing
        ADD HL,DE
        LD (STORE_TEXT_LIMIT),HL
        LD HL,(STORE_LIMIT)
        LD (HL),MARK_HI
        XOR A
        LD (PKT_READY),A
        LD HL,NMI_SEEN
        LD B,NMI_VEC-NMI_SEEN   ; stop short of the boot stub's bytes

store_init_zero_page:
        LD (HL),A
        INC HL
        DJNZ store_init_zero_page
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
        DEC A
        LD (IR_QUIET),A         ; P36: awake; a gate left set by the leader wait would cost the next frame

; ---- ir_reset: IR decoder: reset state, wait for leader (port C0 IR_BIT)
ir_reset:
        LD A,8                  ; quiet ticks before a leader counts: 1 ms, where no
        LD (IR_STATE_CNT),A     ; gap inside a frame but the leader's exceeds 0.8 ms (was 130)
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
        LD A,PORT_IR
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
        XOR A
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
        LD A,PORT_IR
        LD (IR_QUIET),A         ; P35: a line that stays high (a receiver unplugged) parks the decoder here
        JR ir_leader2_ret

ir_leader2_fell:
        PUSH HL
        LD HL,ir_st_leader3
        LD (TICK_VECTOR),HL
        POP HL
        XOR A
        LD (IR_LEVEL),A         ; low
        LD A,24
        LD (IR_STATE_CNT),A

ir_leader2_ret:
        POP AF
        RET

; ---- ir_st_leader3: the gap after the leader. The start burst's rise must come
;      10 to 23 ticks after the leader fell (2300 us nominal): later is no start at
;      all. A rise within two ticks of the fall is the leader resuming after a
;      dropout and is waited out again; any other early rise is a stray burst and
;      is ignored. From the start rise on the cells are clocked by the line's rises
;      (ir_st_bits), so neither the interrupt period nor the receiver's stretch
;      accumulates over the frame.
ir_st_leader3:
        PUSH AF
        PUSH HL
        LD HL,IR_STATE_CNT
        DEC (HL)
        JR z,ir_rej_leader      ; 24 ticks and no start burst
        IN A,(PORT_IN)
        AND PORT_IR
        LD HL,IR_LEVEL
        CP (HL)
        LD (HL),A
        JR z,ir_pop_ret         ; no edge
        AND A
        JR z,ir_pop_ret         ; a fall
        LD A,(IR_STATE_CNT)
        CP 22
        JR nc,ir_leader_again   ; a rise within two ticks of the fall
        CP 15
        JR nc,ir_stray_rise     ; a rise before tick 10
        LD A,7                  ; the start cell is decoded like a data cell and
        LD (IR_BITCNT),A        ; falls off the bottom of IR_SHIFT at the sixth shift
        LD A,0x20               ; "a 1 came before": the start cell may open with a rise
        LD (IR_SHIFT),A
        LD HL,ir_st_bits
        LD (TICK_VECTOR),HL
        JR ir_cell_start

ir_leader_again:
        LD HL,ir_st_leader2
        LD (TICK_VECTOR),HL
        JR ir_pop_ret

ir_rej_leader:
        LD HL,IR_REJ_LEADER
        JR ir_rej_count

ir_stray_rise:              ; counted in IR_REJ_POS but not fatal: the cell keeps waiting for its edge
        LD HL,IR_REJ_POS
        INC (HL)
        JR ir_pop_ret

ir_rej_cell:
        LD HL,IR_REJ_CELL
        JR ir_rej_count

ir_rej_bridge:
        LD HL,IR_REJ_BRIDGE

ir_rej_count:
        INC (HL)
        LD HL,STAT_IR_BAD       ; P40: a frame dropped after its leader
        INC (HL)
        POP HL
        JP ir_reset

ir_pop_ret:
        POP HL
        POP AF
        RET

; ---- ir_st_bits: a cell is 8 ticks counted down in IR_STATE_CNT. A rise seen
;      at count 8-6 opens the cell (a 1), one at 4-2 is its middle (a 0), and
;      either restarts the count, so every cell is timed from its own edge. A 1
;      after a 0 has no rise of its own (the bursts merge), and after a 1 every
;      cell has one: a cell without a rise is checked against the bit before it,
;      and so is one that opens with a rise. Only rises are trusted: the receiver
;      stretches every burst's end by about 250 us, and a rise in a cell that has
;      had its burst is ignored (a dropout's end). Drops are counted by reason in IR_REJ.
ir_st_bits:
        PUSH AF
        PUSH HL
        IN A,(PORT_IN)
        AND PORT_IR
        LD HL,IR_LEVEL
        CP (HL)
        LD (HL),A
        JR z,ir_cell_steady
        AND A
        JR z,ir_cell_tick       ; a fall
        LD A,(IR_CELL)
        INC A
        JR nz,ir_cell_tick      ; the cell has had its burst: a dropout's end, or noise
        LD A,(IR_STATE_CNT)
        CP 6
        JR nc,ir_cell_start
        CP 5
        JR z,ir_stray_rise      ; between the two positions: a stray burst
        CP 2
        JR c,ir_stray_rise      ; count 1: past the middle
        XOR A                   ; the middle: a 0
        LD (IR_CELL),A
        LD A,3
        JR ir_cell_set

ir_cell_start:
        LD HL,IR_SHIFT          ; after a 0 the bursts merge: a 1 cannot open with a rise
        BIT 5,(HL)              ; (a burst where the gap belongs; letting it pass reads a
        JR z,ir_rej_bridge      ; 0 as a 1 when it runs on into the real burst)
        LD A,1
        LD (IR_CELL),A
        LD A,7

ir_cell_set:
        LD (IR_STATE_CNT),A
        JR ir_cell_tick

ir_cell_steady:                 ; no edge: a 1's burst has ended before the cell's first
        AND A                   ; tick, so a line high through its first two was bridged by noise
        JR z,ir_cell_tick
        LD A,(IR_STATE_CNT)
        CP 7
        JR nz,ir_cell_tick
        LD HL,IR_SHIFT          ; after any 1: a rise-opened 1 may itself be a 0 faked by
        BIT 5,(HL)              ; a burst at its start that ran on into the real one
        JR nz,ir_rej_bridge

ir_cell_tick:
        LD HL,IR_STATE_CNT
        DEC (HL)
        JR nz,ir_pop_ret
        LD HL,IR_SHIFT
        LD A,(IR_CELL)
        INC A
        JR nz,ir_cell_known
        BIT 5,(HL)              ; no rise: a 1 merged with the 0 before it
        JR nz,ir_rej_cell
        LD A,2

ir_cell_known:
        DEC A
        RRCA
        RRCA
        RRCA                    ; bit 0 -> bit 5: the code arrives least significant bit first
        SRL (HL)
        OR (HL)
        LD (HL),A
        LD A,0xff
        LD (IR_CELL),A
        LD A,8
        LD (IR_STATE_CNT),A
        LD HL,IR_BITCNT
        DEC (HL)
        JP nz,ir_pop_ret

ir_frame_done:
        LD HL,STAT_IR_OK        ; P40
        INC (HL)
        POP HL
        LD A,(CFG_FLAGS)        ; P35: a locked sign drops the key here, before
        AND CFG_LOCKED          ; either consumer sees it
        JR nz,ir_done
        LD A,(IR_SHIFT)
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
        CALL baud_bit
        ADD A,C
        LD (TX_ACC),A
        LD HL,TX_BITIDX
        INC (HL)
        LD A,(HL)
        CP 9                    ; the start bit and eight data bits are out
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
        JR tx_mark

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
        CALL baud_bit
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

; ---- baud_bit (P52): A = the bit time in BAUD_STEP units: 3 interrupts at
;      2560, else BAUD_T. Flags and A only.
baud_bit:
        LD A,(BAUD_STEP)
        CP BAUD_STEP_2560
        LD A,3*BAUD_STEP_2560
        RET z
        LD A,(BAUD_T)
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
    IFNDEF LITE
        LD (IR_MASK),A          ; P52: the remote decoder off until the next frame end
        LD (IR_QUIET),A
    ENDIF
        LD A,8
        LD (RX_BITS),A
        LD A,(RX_IDLE)
        CP BAUD_IDLE_FRAMES
        LD A,0
        LD (RX_IDLE),A
        JR c,rx_start_timed
    IFNDEF LITE                 ; 300 baud only: nothing to time
        LD A,(MENU_ACTIVE)      ; P45: a terminal's keys come seconds apart and need
        LD B,A                  ; not start like B1: the rate stays as B7 '1' set it
        LD A,(TERM_MODE)
        AND B
        JR nz,rx_start_timed
        LD A,1
        LD (RX_PHASE),A
        RET
    ENDIF

rx_start_timed:
        CALL baud_bit
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
        JP nz,rx_sample_tick
        LD A,(PORT_SAMPLE)      ; phase 1: how long is the start pulse
        BIT 3,A
        JR z,rx_measured
        LD HL,RX_WIDTH
        INC (HL)
        RET nz
        DEC (HL)                ; held at 255
        RET

rx_measured:
        LD A,(RX_WIDTH)
        AND A
        JR z,rx_abort           ; noise
        LD C,BAUD_STEP_2560     ; P52: 1-4 interrupts
        CP 5
        JR c,rx_rate
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
        LD A,(RX_WIDTH)         ; now is width + 1.5 interrupts after the edge on
        LD H,0                  ; average, the pulse's end half an interrupt before
        LD L,A                  ; (P52). HL = width + 1 in BAUD_STEP units + T/2:
        LD D,H                  ; whole bits the pulse covered (the start bit and
        LD E,L                  ; leading 0 bits), remainder to the next middle
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
        LD E,A                  ; 1 interrupt
        CALL baud_bit
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
        LD A,(BAUD_STEP)
        SRL A
        LD E,A
        LD A,C
        SUB L                   ; to the next bit's middle from the pulse's end,
        SUB E                   ; less the half interrupt since; if past, the next interrupt
        JR nc,rx_acc_set
        XOR A

rx_acc_set:
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
        INC A                   ; P52: a middle exactly half an interrupt away is taken
        LD B,A                  ; now: the board's interrupts run late, never early
        LD A,(RX_ACC)
        SUB C
        JR c,rx_sample_now
        CP B
        JR c,rx_sample_now      ; within half an interrupt of the middle
        LD (RX_ACC),A
        RET

rx_sample_now:
        LD C,A
        CALL baud_bit
        ADD A,C
        LD (RX_ACC),A
        LD A,(RX_BITS)
        AND A
        JR z,rx_stop_sample
        DEC A
        LD (RX_BITS),A
        LD A,(PORT_SAMPLE)
        AND 8                   ; space is a 0 bit:
        SUB 1                   ; CY for mark
        LD HL,RX_SHIFT
        RR (HL)                 ; bits arrive LSB first: in at the top
        RET

rx_stop_sample:
        LD A,(PORT_SAMPLE)
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
        OR LATCH_PARK
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        XOR A                   ; P35: a row code still waiting for the ISR goes with the
        LD (LATCH_PENDING),A    ; row, or a late service's next pass would light it mid-shift
        EI
        RET

latch_row:
        DI
        LD A,(CTRL_LATCH_SHADOW)
        AND LATCH_KEEP
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
        AND CFG_BRIGHT
        CP CFG_BRIGHT
        JR z,latch_row          ; full: LIT_LIMIT is 0 (cmd_B6_config clears it)
    IFDEF LITE                  ; a tick per interrupt: the single pass dark, the double lit
        BIT 3,B                 ; strobe to interrupt (level 2) or interrupt to blank (1)
        RET z
        CP 2
        LD A,1
        JR nz,lit_set
        LD (LIT_COUNT),A
        LD (LIT_LIMIT),A
        JR latch_row
    ELSE
        BIT 3,B
        JR z,lit_set
        LD B,A
        ADD A,A
        ADD A,B
    ENDIF

lit_set:
        LD (LIT_LIMIT),A
        LD A,C
        LD (LATCH_PENDING),A
        RET

; ---- rx_fifo_get: Pop one byte from RX_FIFO into RX_BYTE. Returns NC with A=byte, or C if empty
rx_fifo_get:
        DI                      ; P30: the ISR appends to the FIFO
        LD HL,RX_COUNT
        LD A,(HL)
        AND A
        JR z,rx_fifo_empty
        DEC (HL)
        LD HL,RX_FIFO+1
        LD DE,RX_FIFO
        LD A,(DE)
        LD BC,7
        LDIR
        EI
        LD (RX_BYTE),A
        OR A
        RET

rx_fifo_empty:
        EI
        XOR A
        LD (RX_BYTE),A
        SCF
        RET

; ---- rx_key_ready (P45): Z if the FIFO's head is a key for the editor: it was
;      opened by B7 '1', no frame is being parsed and the head is not a B1
rx_key_ready:
        LD A,(TERM_MODE)
        AND A
        JR z,rx_key_no
        LD A,(PKT_STATE)
        AND A
        JR nz,rx_key_no
        LD A,(RX_COUNT)
        AND A
        JR z,rx_key_no
        LD A,(RX_FIFO)
        CP FRAME_START
        JR z,rx_key_no
        CP A
        RET

rx_key_no:
        OR 1
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
        AND 0xfe                ; P45: 80 or 81, else this was no header: look for
        CP 0x80                 ; the next B1, which may be this very byte
        JR nz,pkt_flag_bad
        LD HL,pkt_st_len
        LD (PKT_VECTOR),HL
        RET

pkt_flag_bad:
        LD A,(PKT_FLAG)
        LD HL,pkt_st_addr
        CP FRAME_START
        JR z,pkt_flag_restart
        XOR A
        LD (PKT_STATE),A

pkt_flag_restart:
        LD (PKT_VECTOR),HL
        RET

; ---- pkt_st_len: store length; reset checksum & PKT_PTR=PKT_BUF; len 0 goes straight to checksum state
pkt_st_len:
        LD (PKT_LEN),A
        LD HL,PKT_LEN
        LD A,(PKT_MAX)
        CP (HL)
        JR nc,pkt_len_fits
        LD A,0xff               ; P51: longer than the buffer: parse it, keep nothing
        LD (PKT_DISCARD),A

pkt_len_fits:
        LD A,(HL)
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
        LD A,REPLY_NAK
        JR nz,pkt_send_reply
        LD A,(MENU_ACTIVE)      ; P45: while the editor is open only B7 and B6 are
        AND A                   ; taken; anything else is answered BUSY and dropped
        LD A,REPLY_ACK
        JR z,pkt_send_reply
        LD A,(PKT_BUF)
        SUB CMD_CONFIG          ; B6 or B7
        CP CMD_EDITOR-CMD_CONFIG+1
        LD A,REPLY_ACK
        JR c,pkt_send_reply
        LD A,REPLY_BUSY

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
        LD A,(PKT_BUF)
        CP CMD_EDITOR
        JR z,pkt_editor
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,pkt_in_editor
        DEC A
        LD (PKT_READY),A        ; P21: the render loop picks it up at its next step
        INC A
        LD (PKT_STATE),A
        RET

pkt_discard:
        XOR A
        LD (PKT_READY),A

pkt_discard_frame:
        XOR A
        LD (PKT_STATE),A
        RET

; ---- pkt_in_editor: a B6 is applied here, since packets wait for the render loop;
;      anything else was answered BUSY
pkt_in_editor:
        LD A,(PKT_BUF)
        CP CMD_CONFIG
        JR nz,pkt_discard
        LD A,(PKT_LEN)
        CP 4
        JR nz,pkt_discard
        LD A,(PKT_BUF+1)
        LD C,A
        LD HL,(PKT_BUF+2)
        LD B,H
        LD H,L
        CALL cfg_write
        JR pkt_discard

; ---- pkt_editor (P45): B7 '1' opens the editor as a serial terminal (or makes the
;      open one take serial keys), B7 '0' closes it as STOP would. ACK only, no DONE.
pkt_editor:
        LD A,(PKT_BUF+1)
        CP '0'
        JR z,pkt_editor_close
        CP '1'
        JR nz,pkt_discard
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,pkt_editor_term
        LD A,(TEST_MODE)        ; P43: no editor during an update
        INC A
        JR z,pkt_discard
        XOR A
        LD (PKT_STATE),A
        DEC A
        LD (TERM_MODE),A
        JP key_handler          ; resets the stack, as a STOP key does

pkt_editor_term:
        LD (TERM_MODE),A
        JR pkt_discard

pkt_editor_close:
        LD A,(MENU_ACTIVE)
        LD (EDIT_CLOSE),A       ; nothing when the editor is shut
        JR pkt_discard

; ---- tx_send_frame: Send reply frame: B1, MY_ADDRESS, then (HL)=len, len bytes, 8-bit sum of the data bytes
tx_send_frame:                  ; ota_reply, its one caller, keeps nothing
        LD A,FRAME_START
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

; ---- bin_to_dec5: HL -> 5 ASCII digits at DE, which advances (10000,1000,100,10,1)
bin_to_dec5:
        LD BC,DEC_TABLE

; ---- bin_to_dec_bc: digits from the place-value table at BC
bin_to_dec_bc:
        PUSH DE
        LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        RLA
        JR c,dec_end            ; FFFF ends the table
        LD A,'0'-1

dec_digit_loop:
        INC A
        AND A
        SBC HL,DE
        JR nc,dec_digit_loop
        ADD HL,DE
        POP DE
        LD (DE),A
        INC DE
        JR bin_to_dec_bc

dec_end:
        POP DE
        RET

; ---- clock_tick: NMI: NMI_COUNT to NMI_PER_SEC -> seconds -> minutes -> hours (12h, CLK_PM toggles)
clock_tick:
        LD A,(CLK_RUN)
        AND A
        RET z
        LD HL,NMI_COUNT
        INC (HL)
        LD A,(NMI_PER_SEC)
        CP (HL)
        RET nz
        LD (HL),0
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
        CP 60
        RET nz
        LD (HL),0
        DEC HL                  ; CLK_M1
        INC (HL)
        LD A,(HL)
        CP 10
        RET nz
        LD (HL),0
        DEC HL                  ; CLK_M10
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
        XOR A
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

; ---- rainbow_alt_flush (P57): the crawl pushes the panel's text off, as at a
;      message's end, in the font in force after it; staged pages are shown whole anyway
rainbow_alt_flush:
        INC HL
        LD (STORE_CURSOR),HL
        LD A,(EFFECT_ID)
        AND A
        JR nz,flush_done
        LD A,(FONT_MODE)
        PUSH AF
        CALL scroll_off_text
        POP AF
        LD (FONT_MODE),A

flush_done:
        POP HL
        JP render_next_char

; ---- clear_framebuf: the column ring = 0x80
        ASSERT FRAMEBUF_SIZE < 256
clear_framebuf:
        PUSH HL
        PUSH BC
        LD HL,FRAMEBUF
        LD BC,FRAMEBUF_SIZE*0x100+0x80
        JR fill_pop

; ---- clear_txbuf: zero the staging frame at TXBUF
clear_txbuf:
        PUSH HL
        PUSH BC
        LD HL,TXBUF
        LD BC,FRAME_COLS*0x100
        JR fill_pop

; ---- clear_glyph_tmp: zero the three glyph buffers
clear_glyph_tmp:
        PUSH HL
        PUSH BC
        LD HL,GLYPH_BUF
        LD BC,0x6000

fill_pop:
        CALL mem_fill
        POP BC
        POP HL
        RET

; ---- mem_fill: B bytes from HL = C
mem_fill:
        LD (HL),C
        INC HL
        DJNZ mem_fill
        RET

; ---- key_handler: Handle a key / IR code: menu navigation (ADDRESS?, TIME?, PROG MSG?, SEQ MSG? ...)
key_handler:
        LD A,0xff
        LD (CAPS_LOCK),A
        XOR A
        LD (KEY_ECHO_TX),A

editor_start:
        LD SP,(STACK_INIT)
        XOR A
        LD (SVC_ACTIVE),A       ; P26: entered from rx_consume inside the service
        LD (EDIT_CLOSE),A
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
        LD A,0xfe               ; no key's code: STOP's next frame overwrites it
        LD (IR_CODE),A
        LD HL,0x01a0            ; ~0.3 s with no frame: STOP is up
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
        LD HL,ALT_NEXT          ; P46: a FUNC2 attribute's second byte, after its B2
        LD A,(HL)
        LD (HL),0
        LD (EDIT_KEY),A
        AND A
        JR nz,editor_have_key
        CALL menu_getchar
        CALL editor_translate_key

editor_have_key:
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
        DKEY 1, editor_next_key ; a terminal's 01 (opens a keypad CC784's editor): nothing
        DKEY KEY_CLR_ALL, menu_clear_all
        DKEY 5, show_top_of_msg ; a terminal's 05; no remote key gives it
        DKEY KEY_DEL, editor_delete
        DKEY KEY_SHIFT, editor_key_shift
        DKEY KEY_CUR_RIGHT, cursor_right
        DKEY KEY_CUR_RIGHT8, cursor_right_8
        DKEY KEY_CUR_LEFT, cursor_left
        DKEY KEY_CUR_LEFT8, cursor_left_8
        DKEY KEY_CLEAR, editor_clear_msg
        DKEY KEY_EURO, editor_toggle_euro
        DKEY KEY_ADDRESS, menu_address
        DKEY KEY_CASE, editor_toggle_caps
        DKEY ATTR_GRAPH, editor_key_graph
        DKEY ATTR_COLOR, editor_key_color
        DKEY ATTR_BGRND, editor_key_bgrnd
        DKEY KEY_TIME, menu_time
        DKEY KEY_SPEED, editor_key_speed
        DKEY CMD_APPEND, editor_goto_end ; a terminal's B3: to the text's end, as APPEND
        DKEY KEY_FUNC, editor_key_func
    IFNDEF LITE
        DKEY KEY_FIELD, editor_key_field
    ENDIF
        DKEY KEY_PROG, menu_prog_msg
        DKEY KEY_SEQ, menu_seq_msg
        DKEY KEY_ENTER, editor_exit
        DKEY KEY_UNSHIFT, editor_loop
        DKEY FRAME_START, editor_exit    ; a terminal's B1, a frame's first byte
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
        LD A,ATTR_MAGIC
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
        LD HL,MENU_STR_INVALID
        CALL menu_msg
        JP editor_loop

; ---- menu_msg: the editor's next redraw shows the message at HL
menu_msg:
        LD (MENU_MSG_PTR),HL
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        RET

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
        CP IR_CODE_RELEASE
        JR z,exit_add_to_seq
        CP IR_CODE_STOP
        JR z,exit_key_held
        CP IR_CODE_A
        JR nz,exit_wait_release

exit_key_held:
        LD A,0xff
        LD (IR_CODE),A
        LD HL,0x028a            ; ~0.5 s with no frame: the key is up
        LD (GEN_COUNTDOWN),HL

exit_held_poll:
        LD A,(IR_CODE)
        CP IR_CODE_STOP
        JR z,exit_key_held
        CP IR_CODE_A
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
        LD HL,SEQ_END-2
        LD (HL),0xff
        LD DE,SEQ_END-1
        LD BC,SEQ_LIST_LEN-1
        LDDR

exit_seq_first:
        LD HL,SEQ_LIST
        LD (HL),A
        JR exit_to_display

exit_seq_found:
        LD E,A
        LD (NEXT_CHAN),A

exit_to_display:
        LD SP,(STACK_INIT)
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
        RES FONT_ITALIC_BIT,(HL)

clock_step:
        LD A,(CLK_RENDER_STEP)
        LD HL,(CLK_RENDER_PTR)
        AND A
        JR nz,clock_next_step
        LD HL,CLK_H10
        LD A,(CLK_PM)
        AND CLK_24H             ; P32: 24-hour keeps the leading zero
        OR (HL)
        LD A,0                  ; the step
        JR nz,clock_next_step
        INC A
        LD (CLK_RENDER_STEP),A
        INC HL
        LD (CLK_RENDER_PTR),HL
        JR render_clock

clock_next_step:
        INC A
        LD (CLK_RENDER_STEP),A
        CP CLK_STEP_COLON
        JR nz,clock_not_colon
        LD A,':'
        JR clock_emit_a

clock_not_colon:
        CP CLK_STEP_SPACE
        JR nz,clock_not_space
        LD A,' '
        JR clock_emit_a

clock_not_space:
        CP CLK_STEP_AMPM
        JR nz,clock_not_ampm
        LD A,(CLK_PM)
        AND 1                   ; PM
        LD A,'A'
        JR z,clock_emit_a
        LD A,'P'
        JR clock_emit_a

clock_not_ampm:
        CP CLK_STEP_M
        JR nz,clock_digit
        LD A,'M'
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
        CP CLK_STEP_M1
        JR nz,clock_emit
        LD A,(CLK_PM)
        AND CLK_24H             ; P32: 24-hour ends at the last minute digit:
        JR z,clock_emit         ; no space, no AM or PM

clock_emit_last:
        LD A,0xff
        LD (CLK_RENDER_STEP),A
        JR glyph_lookup_jr15

clock_emit_a:
        LD (CUR_CHAR),A

clock_emit:
        CALL unfetch_char

glyph_lookup_jr15:
        JP glyph_lookup

; ---- menu_ask_chan_cur: ask for a channel number, prefilled from INS_PTR
menu_ask_chan_cur:
        LD (ASK_CHAN_PROMPT),HL
        JR askchan_prefill

; ---- menu_ask_chan: ask for a channel number; returns 0-99, 64 demo,
;      ASK_SEQ, ASK_MAGIC, ASK_ALL, ASK_BLANK or ASK_MSGS
menu_ask_chan:                  ; the callers keep nothing in the registers
        LD (ASK_CHAN_PROMPT),HL
        JP askchan_clear

askchan_prefill:
        LD HL,(INS_PTR)
        DEC HL
        CALL mark_digit
        LD (CHAN_D1),A
        DEC HL
        CALL mark_digit
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
        DKEY KEY_SEQ, askchan_seq_key
        DKEY KEY_CUR_LEFT, askchan_accept
        DKEY KEY_PROG, askchan_accept
        DKEY KEY_ENTER, askchan_enter
        DKEY KEY_CLEAR, askchan_clear
        DKEY ATTR_MAGIC, askchan_magic_key
        DKEY KEY_DEL, askchan_backspace
        DKEY 'A', askchan_all
        DKEY 'a', askchan_all
    IFNDEF LITE
        DKEY 'M', askchan_msgs
        DKEY 'm', askchan_msgs
    ENDIF
        DKEY 'D', askchan_demo
        DKEY 'd', askchan_demo
        db 0xff
        CALL is_digit           ; A is still the key
        JR nc,askchan_key
        LD HL,CHAN_D1
        LD C,(HL)
        LD (HL),A
        DEC HL                  ; CHAN_D10
        LD (HL),C
        JR askchan_show

askchan_backspace:
        LD HL,CHAN_D10
        LD A,(HL)
        LD (HL),'0'
        INC HL
        LD (HL),A
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
        CP CHANNELS
        JR nc,askchan_clear     ; no such channel: ask again

askchan_return:
        RET

askchan_clear:
        LD A,' '
        LD (CHAN_D10),A
        LD (CHAN_D1),A
        JP askchan_show

askchan_enter:
        LD A,(CHAN_D1)
        CP ' '
        JR nz,askchan_accept
        LD A,ASK_BLANK
        RET

askchan_all:
        LD A,ASK_ALL
        RET

askchan_demo:
        LD A,CHAN_DEMO
        RET

askchan_seq_key:
        LD A,ASK_SEQ
        RET

askchan_magic_key:
        LD A,ASK_MAGIC
        RET

    IFNDEF LITE
askchan_msgs:
        LD A,ASK_MSGS
        RET
    ENDIF

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
        LD DE,MENU_ENTRY_BUF
        LD BC,DEC_TABLE+4
        CALL bin_to_dec_bc
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
        CP KEY_CUR_LEFT
        JR z,addr_enter
        CP KEY_ENTER
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

; ---- ascii_dec_to_bin: B ASCII digits at HL to binary in A; CY if past 255 (C lost)
ascii_dec_to_bin:
        XOR A

a2b_digit_loop:
        LD C,A
        ADD A,A
        RET c
        ADD A,A
        RET c
        ADD A,C
        RET c
        ADD A,A                 ; x 10
        RET c
        LD C,A
        LD A,(HL)
        AND 15
        ADD A,C
        RET c
        INC HL
        DJNZ a2b_digit_loop
        RET

; ---- mark_digit: A = the marker byte at HL as a digit, or D for the demo's DA
mark_digit:
        LD A,(HL)
        CP MARK_HI
        LD A,'D'
        RET z
        LD A,(HL)
        AND 15
        OR '0'
        RET

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
        LD HL,MENU_STR_INVALID
        CALL menu_msg
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
        CALL mark_digit
        CP 'D'
        JR z,top_emit
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
        JR nz,editor_loop_jr12
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

    IFNDEF LITE
editor_key_field:
        LD DE,FIELD_PENDING
        JR editor_set_pending
    ENDIF

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
        CP ASK_MAGIC
        JR z,seqmenu_done       ; P29: MAGIC used to open the factory test prompt
        CP ASK_SEQ
        JR z,seqmenu_done
        CP ASK_ALL
        JR z,seqmenu_all
    IFNDEF LITE
        CP ASK_MSGS
        JR z,seqmenu_msgs
    ENDIF
        CP ASK_BLANK
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

    IFNDEF LITE
seqmenu_msgs:
        CALL seq_list_messages
        JR editor_exit_jr17
    ENDIF

seqmenu_all:
        CALL seq_list_default

editor_exit_jr17:
        JP editor_exit

; ---- menu_getchar
menu_getchar:
        LD A,(EDIT_CLOSE)
        AND A
        JR nz,editor_close
        CALL editor_getkey
        LD A,(EDIT_KEY)
        AND A
        JR z,menu_getchar
        RET

editor_close:                   ; P45: B7 '0' leaves as STOP does, from any prompt
        LD A,0xff               ; (the time prompt stops the clock)
        LD (CLK_RUN),A
        XOR A
        LD (SEQ_MENU_ACTIVE),A
        JP exit_add_to_seq

; ---- editor_getkey: Editor key source: echoes the previous key on the serial TX, then takes a key from the serial RX FIFO if present, else from the IR decoder (IR_CODE). So the on-sign editor can be driven from a serial terminal as well as the remote.
editor_getkey:
        LD A,(KEY_ECHO_TX)
        AND A
        JR z,getkey_serial
        CALL tx_send_byte

getkey_serial:
        CALL rx_key_ready       ; P45: only with B7 '1', and never a frame's byte:
        JR nz,getkey_ir         ; rx_consume parses those, and leaves a key's head alone
        CALL rx_fifo_get
        LD C,A                  ; RX_BYTE is rx_consume's too
        AND A
        JR z,getkey_ir
        XOR A
        LD (EURO_STATE),A
        LD A,C
        LD (EDIT_KEY),A
        LD (KEY_ECHO_TX),A
        RET

getkey_ir:
        LD A,(IR_CODE)
        AND A
        JR z,getkey_none
        AND 0x3f
        LD (IR_KEYNUM),A
        LD HL,IR_CODE
        LD (HL),0
        CP IR_KEY_RELEASE
        JR z,getkey_released
        OR 0x40                 ; a seen key carries bit 6: idle 0 is not key 0
        LD C,A
        LD A,(IR_KEY)
        CP C
        JR nz,getkey_other_key
        LD A,(IR_DEBOUNCE)
        AND A
        JR nz,getkey_accept
        LD HL,(GEN_COUNTDOWN)
        LD A,H
        OR L
        JR nz,getkey_none
        LD HL,IR_REPEAT_TICKS
        LD (GEN_COUNTDOWN),HL
        JR getkey_check_shift

getkey_released:
        CALL getkey_pending     ; a first frame still waiting for its second: the
        JR nz,getkey_release_clear   ; release within the window confirms it
        LD A,(IR_KEY)
        AND 0x3f
        LD (IR_KEYNUM),A
        LD A,IR_CODE_RELEASE    ; editor_exit waits for the release code itself
        LD (IR_CODE),A
        XOR A
        LD (IR_KEY),A
        LD (IR_DEBOUNCE),A
        JR getkey_check_shift

getkey_release_clear:
        XOR A
        LD (IR_KEY),A
        LD (IR_DEBOUNCE),A

getkey_none:
        XOR A
        LD (IR_KEY_CHAR),A
        JP getkey_return

; ---- getkey_pending: Z = a lone first frame is waiting and its window is open
getkey_pending:
        LD A,(IR_DEBOUNCE)
        AND A
        JR z,getkey_pending_no
        LD HL,(GEN_COUNTDOWN)
        LD A,H
        OR L
        JR z,getkey_pending_no
        XOR A
        RET

getkey_pending_no:
        OR 1
        RET

getkey_other_key:
        CALL getkey_pending     ; two different keys inside one window: one of
        JR z,getkey_release_clear    ; them was mis-decoded, so neither counts

getkey_first_frame:
        LD A,(IR_KEYNUM)
        OR 0x40
        LD (IR_KEY),A
        LD (IR_DEBOUNCE),A
        LD HL,IR_DEBOUNCE_WINDOW
        LD (GEN_COUNTDOWN),HL
        XOR A
        LD (IR_CODE),A
        JR getkey_none

getkey_accept:
        LD A,(IR_KEYNUM)
        OR 0x40
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
        LD A,KEY_SHIFT
        JR nz,getkey_shift_code
        LD A,KEY_UNSHIFT

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
        XOR A
        LD (KEY_ECHO_TX),A
        LD A,(IR_KEY_CHAR)
        LD (EDIT_KEY),A
        AND A
        RET

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
        LD A,(HL)               ; P46: a variant's B2 goes with it
        CP ATTR_ALT
        JR z,delete_do
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
        LD A,(HL)               ; P46: a variant's B2 is passed over: the cursor
        CP ATTR_ALT             ; never rests on it
        JR nz,cursor_right_store
        INC HL

cursor_right_store:
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
        LD A,(HL)               ; P46: past a variant's B2 too
        CP ATTR_ALT
        JR nz,cursor_left_set
        DEC HL

cursor_left_set:
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
        JR nz,insert_shift
        LD HL,MENU_STR_MEM_FULL
        CALL menu_msg

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
        LD HL,MENU_STR_100_KEYS
        CALL menu_msg

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
    IFNDEF LITE
        CALL apply_field_prefix
    ENDIF
        JR editor_key_to_attr

    IFNDEF LITE
; ---- apply_field_prefix (P54): FUNC PROG n -> B2 '0'+n; any other key cancels
apply_field_prefix:
        LD HL,FIELD_PENDING
        LD A,(HL)
        OR A
        RET z
        LD (HL),0
        LD A,(EDIT_KEY)
        CALL is_digit
        JR nc,field_prefix_cancel
        LD (ALT_NEXT),A
        LD A,ATTR_ALT
        LD (EDIT_KEY),A
        RET

field_prefix_cancel:
        POP HL                  ; editor_translate_key's return, then ours
        POP HL
        JP editor_reshow
    ENDIF

; ---- apply_graph_prefix: GRAPH n -> A0|n
apply_graph_prefix:
        LD HL,GRAPH_PENDING
        LD BC,0x0f00+GRAPH_BASE
        JR prefix_apply

; ---- apply_speed_prefix: SPEED n -> F0|(n&7)
apply_speed_prefix:
        LD HL,SPEED_PENDING
        LD BC,0x0700+SPEED_BASE

prefix_apply:                   ; the flag at HL set: the key masked with B, OR C
        LD A,(HL)
        OR A
        RET z
        LD (HL),0
        LD A,(EDIT_KEY)
        AND B
        OR C
        LD (EDIT_KEY),A
        RET

; ---- editor_key_to_attr: FUNC (B7) second functions: GRAPH->B8 DRAW, NORM->B9 THIN,
;      PAUSE->BA WAIT, FLASH->B0 REM, BOLD->06 HALT, COLOR->BC RAINBOW, Q->?, X->!, C->,,
;      MAGIC->5E (ADDRESS? menu), BIG->BE TINY; anything else cancels
editor_key_to_attr:
        LD A,(FUNC_PENDING)
        AND A
        RET z
        LD B,A                  ; FF FUNC, 2 FUNC2
        LD A,(EDIT_KEY)
        CP KEY_SHIFT            ; P46: SHIFT after FUNC makes it FUNC2, the shift
        JR nz,func_lookup       ; itself undone; in FUNC2 it shifts the next key (P48)
        INC B
        RET nz
        LD A,2
        LD (FUNC_PENDING),A
        XOR A
        LD (SHIFT_STATE),A
        RET

func_lookup:
        XOR A
        LD (FUNC_PENDING),A
        LD A,(EDIT_KEY)
        LD HL,FUNC_TABLE
        INC B
        JR z,func_search
        LD HL,FUNC2_TABLE

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

func_cancel:                    ; P47: one return address since editor_translate_key jumps here
        POP HL                  ; (stock CALLed; a second POP lifted SP into PKT_READY/PKT_BUF)
        JP editor_reshow

func_store:
        LD A,B                  ; a FUNC2 attribute is B2 and its second byte
        AND A
        LD A,(HL)
        JR nz,func_store_alt
        CP ' '                  ; P57: FUNC SPACE is B2 20, FLUSH
        JR nz,func_store_key

func_store_alt:
        LD (ALT_NEXT),A
        LD A,ATTR_ALT

func_store_key:
        LD (EDIT_KEY),A
        RET

; ---- apply_color_prefix: COLOR n -> FG_IDX_TABLE, BGRND n -> BG_IDX_TABLE
apply_color_prefix:             ; editor_have_key clears both flags: the key is no longer SHIFT
        LD A,(COLOR_PENDING)
        AND A
        JR nz,prefix_fore
        LD A,(BGRND_PENDING)
        AND A
        RET z
        LD A,(EDIT_KEY)
        AND 7
        DEC A
        LD HL,BG_IDX_TABLE
        CP BG_COLORS
        JR c,prefix_lookup
        LD A,BG_COLORS-1
        JR prefix_lookup

prefix_fore:
        LD A,(EDIT_KEY)
        AND 15
        DEC A
        LD HL,FG_IDX_TABLE
        CP FG_COLORS
        JR c,prefix_lookup
        LD A,2

prefix_lookup:
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (EDIT_KEY),A
        RET

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
        LD DE,0x15              ; the view starts 21 bytes before the cursor
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
        LD A,0xff
        LD (TINY_MODE),A
        LD HL,(REDRAW_PTR)
        LD A,(HL)
        LD (CUR_CHAR),A
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
        AND 0x60                ; 00-1F: attributes
        JR z,redraw_attr
        JR redraw_char_check_jr18

redraw_high:
        CP EURO_LO
        JR c,redraw_attr
        CP GRAPH_BASE           ; P56: 9F is a character
        JR c,redraw_char_check_jr18
        AND 0xf0
        CP EURO_ROW_C
        JR z,redraw_char_check_jr18
        CP EURO_ROW_E
        JR z,redraw_char_check_jr18
        CP EURO_ROW_D
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
        CP ATTR_RIGHT
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
        LD A,0x64               ; bit 2 (the other bits are stock's and unread)
        JR redraw_set_font

redraw_not_italic:
        CP ATTR_BOLD
        JR nz,redraw_not_bold
        LD A,FONT_BOLD
        JR redraw_set_font

redraw_not_bold:
        CP ATTR_BIG
        JR nz,redraw_not_big
        LD A,FONT_BIG

redraw_set_font:
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
        JP c,redraw_next

redraw_show_label:
        LD A,(CUR_CHAR)
        AND 0xf8
        CP SPEED_BASE
        JR z,redraw_speed_label
        LD HL,(REDRAW_PTR)
        DEC HL
        LD A,(HL)
        CP ATTR_ALT
        LD A,(CUR_CHAR)
        JR nz,label_key
        XOR 0x40                ; P46: after B2 the variant's label (B2 itself has none)

label_key:
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

redraw_label_digit:
        CALL glyph_put_next
        LD HL,STR_CLOSE
        CALL menu_show_text
        JR redraw_next

redraw_char_check:
        CALL redraw_in_window
        JR c,redraw_next
        LD HL,(REDRAW_PTR)
        DEC HL
        LD A,(HL)
        CP ATTR_ALT
        JR nz,redraw_char
        LD A,(CUR_CHAR)
        CP ' '                  ; P57: FLUSH
        JR z,redraw_show_label
    IFNDEF LITE                 ; P54: a digit after B2 is a field: <F0>-<F9>
        CALL is_digit
        JR nc,redraw_char
        LD HL,STR_F
        CALL show_label
        LD A,(CUR_CHAR)
        JR redraw_label_digit
    ENDIF

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
        JP nc,redraw_loop

redraw_status:
        LD A,0xff
        LD (TINY_MODE),A
        LD HL,STATUS_FLAGS
        LD B,(STATUS_FLAGS_END-STATUS_FLAGS)/4

status_scan:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(DE)               ; the flag
        LD E,(HL)
        INC HL
        LD D,(HL)               ; its label
        INC HL
        OR A
        JR nz,status_found
        DJNZ status_scan
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

status_found:
        EX DE,HL
        CP 2                    ; only FUNC_PENDING is ever 2
        JR nz,status_show
        LD HL,STR_FUNC2

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
        JP wait_frame_delay

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
        LD DE,-(FRAMEBUF+FRAME_COLS) & 0xffff
        ADD HL,DE               ; CY: no wrap, HL = the offset into the ring
        LD DE,FRAMEBUF
        JR c,rewind_set
        LD E,FRAMEBUF_END & 0xff

rewind_set:
        ADD HL,DE
        LD (FB_COL),HL
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
        RRCA
        JR nc,pkt_entry_nodone
        LD A,(PKT_ADDR)
        CP ADDR_BROADCAST
        JR z,pkt_entry_nodone
        LD A,0xff
        LD (PKT_DONE_WANT),A

pkt_entry_nodone:
    IFNDEF LITE
        CALL field_park
    ENDIF
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
        ADD HL,DE
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
    IFDEF LITE
        DKEY CMD_OTA, pkt_done_pop      ; an EPROM: nothing to write
    ELSE
        DKEY CMD_OTA, cmd_B5_ota
    ENDIF
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
    IFNDEF LITE
        CALL field_resume
    ENDIF
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
        LD SP,(STACK_INIT)
        LD A,0xff
        LD (PKT_RESTART),A      ; left set: the emulator reads which exit was taken
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        CALL shift_chain_clear
        JP restart_display

    IFNDEF LITE
; ---- field_open (P54): A = the digit; the renderer goes on in channel 90+A and
;      field_close brings it back. Not inside a field, nothing if missing.
field_open:
        INC HL
        LD (STORE_CURSOR),HL
        ADD A,MARK_LO
        LD E,A
        LD A,(FIELD_RET+1)
        OR A
        JR nz,field_next
        PUSH HL
        LD HL,(STORE_END)       ; 90-99 sit at the store's end: scan back from it
        LD BC,MSG_STORE
        OR A
        SBC HL,BC
        LD B,H
        LD C,L
        LD HL,(STORE_END)

field_scan:
        LD A,E
        CPDR
        JR nz,field_none
        LD A,(HL)
        CP MARK_LO+9            ; the tens byte of 90-99
        JR z,field_found
        LD A,B
        OR C
        JR nz,field_scan

field_none:
        POP HL
        JR field_next

field_found:
        LD (FIELD_MARK),HL
        INC HL
        INC HL
        LD (STORE_CURSOR),HL
        POP HL
        LD (FIELD_RET),HL

field_next:
        POP HL                  ; attr_rainbow's return, as rainbow_next
        JP render_next_char

; ---- field_close (P54): a 03 ends the field and the parent goes on, or ends the channel
field_close:
        LD HL,(FIELD_RET)
        LD A,H
        OR A
        JP z,fx_end_of_channel
        LD (STORE_CURSOR),HL
        LD HL,0
        LD (FIELD_RET),HL
        JP render_next_char

; ---- field_park (P54): inside a field the packet sees the parent's position, so
;      its usual checks keep or shift that; FIELD_RET holds the field's meanwhile
field_park:
        LD HL,(FIELD_RET)
        LD A,H
        OR A
        RET z
        LD DE,(STORE_CURSOR)
        LD (STORE_CURSOR),HL
        LD (FIELD_RET),DE
        RET

; ---- field_resume (P54): STORE_CURSOR is the parent's position as kept or shifted;
;      the field goes on where it was, moved with a lower edit, or ends if it changed
field_resume:
        LD HL,(FIELD_RET)
        LD A,H
        OR A
        RET z
        EX DE,HL
        LD HL,(PKT_LOW_EDIT)
        OR A
        SBC HL,DE
        JR nc,resume_swap       ; nothing moved under the field
        LD HL,(PKT_LOW_EDIT)
        LD BC,(FIELD_MARK)
        OR A
        SBC HL,BC
        JR nc,resume_drop       ; the field's own text changed
        LD HL,(STORE_END)
        LD BC,(PKT_SAVE_END)
        OR A
        SBC HL,BC
        PUSH HL
        ADD HL,DE
        EX DE,HL
        POP HL
        LD BC,(FIELD_MARK)
        ADD HL,BC
        LD (FIELD_MARK),HL

resume_swap:
        LD HL,(STORE_CURSOR)
        LD (FIELD_RET),HL
        LD (STORE_CURSOR),DE
        RET

resume_drop:
        LD HL,0
        LD (FIELD_RET),HL
        RET
    ENDIF

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
        CALL dispatch
        DKEY QUERY_ROMID, pq_romid
        DKEY QUERY_MEMORY, pq_memory
        DKEY QUERY_DUMP, pq_dump
        DKEY QUERY_STATS, pq_stats
        DKEY QUERY_CONFIG, pq_config
        DKEY QUERY_SEQ, pq_seq
        db 0xff
        JP pkt_done_pop

pq_romid:
        LD HL,ROM_ID
        LD BC,16
        JR pq_reply

pq_memory:
        CALL store_finalize
        LD DE,PKT_BUF+3
        LD HL,(STORE_SIZE)
        CALL bin_to_dec5
        LD HL,(STORE_LIMIT)
        LD BC,(STORE_END)
        OR A
        SBC HL,BC
        CALL bin_to_dec5
        LD A,(PKT_MAX)          ; P51: the longest payload a frame may carry
        LD L,A
        LD H,0
        CALL bin_to_dec5
        LD HL,PKT_BUF+3
        LD BC,15

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
        LD DE,PKT_BUF+2
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
        ASSERT BAUD_STEP == BAUD_T+1 && BAUD_CAL_LAST == BAUD_T+2
        LD DE,PKT_BUF+3         ; P30: the serial timing state, for the bench:
        LD HL,BAUD_T            ; BAUD_T, BAUD_STEP, BAUD_CAL_LAST
        LD BC,3
        LDIR
        LD A,(NMI_SEEN)
        LD (DE),A
        INC DE
        LD A,(NMI_PER_SEC)      ; P40: 60 mains, 64 the add-in board's crystal
        LD (DE),A
        INC DE
        LD A,(BOOT_COUNT)
        LD (DE),A
        INC DE
        LD HL,(STACK_BOT)
        LD A,CANARY
        LD B,STACK_CANARY

pq_canary:
        CP (HL)
        JR nz,pq_canary_end
        INC HL
        DJNZ pq_canary

pq_canary_end:
        LD A,STACK_CANARY
        SUB B
        LD (DE),A
        INC DE
        LD HL,STATS
        LD BC,STATS_LEN
        LDIR
        LD HL,IR_REJ            ; then the remote's drop reasons
        LD BC,4
        LDIR
        LD HL,PKT_BUF+3
        LD BC,7+STATS_LEN+4
        JP pq_reply

; ---- cmd_B5_ota: OTA commands (ota.md §6). B5 must be the first payload
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
        CALL dispatch
        DKEY 'I', ota_info
        DKEY 'C', ota_crc
        DKEY 'B', ota_begin
        DKEY 'W', ota_write
        DKEY 'F', ota_finish
        DKEY 'K', ota_confirm
        DKEY 'R', RESET
        db 0xff

ota_bad_args:
        LD A,OTA_ARGS

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
        LD (HL),22              ; ROM_BANK, two 10-byte trailers, OTA_FEATURES
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
        CP 43                   ; 42 pages at most: 84 bytes of CRCs fill TXBUF
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
        LD BC,EE_PAGE
        LD DE,0
        CALL ROM_CRC16
        POP BC
        RET

; ---- ota_fetch_page: HL = address in the idle bank -> 64 bytes at OTA_PAGE_BUF, HL = the buffer
ota_fetch_page:
        LD DE,OTA_PAGE_BUF
        LD BC,EE_PAGE
        LD A,(OTA_IDLE)
        CALL ota_copy
        LD HL,OTA_PAGE_BUF
        RET

; ---- ota_erase_buf: OTA_PAGE_BUF = 64 x FF, HL = the buffer
ota_erase_buf:
        LD HL,OTA_PAGE_BUF
        LD B,EE_PAGE

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
        LD BC,EE_PAGE
        LDIR
        LD A,(PKT_BUF+2)
        LD (OTA_PAGE_BUF+5),A
        LD A,(PKT_BUF+3)
        LD (OTA_PAGE_BUF+4),A
        LD A,(ROM_BANK)
        JR ota_seal_write

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
        LD A,(OTA_IDLE)
        JR ota_write_page

; ---- ota_seal_write: the CRC of OTA_PAGE_BUF's first 8 bytes into its next two,
;      then the page written as bank A's trailer and the status replied
ota_seal_write:
        PUSH AF
        LD HL,OTA_PAGE_BUF
        LD BC,8
        LD DE,0
        CALL ROM_CRC16
        LD (OTA_PAGE_BUF+8),DE
        POP AF

ota_write_page:
        LD B,A
        LD HL,OTA_PAGE_BUF
        LD DE,TRAILER
        CALL clock_bank         ; P31: the writer's NMI sync needs the source on
        CALL lib_page_writer

ota_status_jr21:
        JR ota_status_jr22

; ---- ota_write: 'W' page crc data[64k] -> pages page..page+k-1 of the idle bank
ota_write:
        LD A,(PKT_LEN)
        SUB 5                   ; B5 'W' page crc16: the rest is page data
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
        CP STUB_END/EE_PAGE
        LD B,A
        LD A,OTA_RANGE
        JR c,ota_status_jr21         ; the stub is never written over the air
        LD A,C
        DEC A
        ADD A,B
        LD A,OTA_RANGE
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
        LD A,OTA_CRC
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
        LD BC,EE_PAGE           ; both on to the next page
        ADD HL,BC
        EX DE,HL
        ADD HL,BC
        EX DE,HL
        POP BC
        OR A
        JR nz,ota_status_jr21
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
        LD BC,EE_PAGE
        CALL ROM_CRC16
        EXX
        LD BC,EE_PAGE
        ADD HL,BC
        LD A,H
        CP TRAILER >> 8         ; the image ends where the trailer page starts
        JR nz,ota_finish_next
        LD A,L
        CP TRAILER & 0xff
        JR z,ota_finish_done

ota_finish_next:
        EXX
        JR ota_finish_loop

ota_finish_done:
        EXX
        LD HL,(PKT_BUF+3)
        OR A
        SBC HL,DE
        LD A,OTA_CRC
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
        LD A,(OTA_IDLE)
        JP ota_seal_write

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

; ---- cmd_B6_config (P35): B6 index mask value -> the configuration block: only
;      the bits in mask take value's. The signature, the address and the sum are
;      not writable; CFG_FLAGS keeps its live bit.
cmd_B6_config:
        CALL pkt_next_byte
        LD C,A
        CALL pkt_next_byte
        LD H,A                  ; pkt_next_byte keeps BC and HL, not DE
        CALL pkt_next_byte
        LD B,A
        CALL cfg_write
        JR pkt_next_jr19

; ---- cfg_write: byte C of the block takes value B's bits where mask H has them
cfg_write:
        LD A,C
        CP CFG_FLAGS-CFG
        RET c
        CP CFG_LEN-1
        RET nc
        LD C,H
        LD HL,CFG
        LD E,A
        LD D,0
        ADD HL,DE
        CP CFG_FLAGS-CFG
        JR nz,cfg_merge
        LD A,C
        AND ~CFG_LIVE & 0xff
        LD C,A
        XOR A
        LD (LIT_LIMIT),A        ; a brightness change: latch_row_dim re-arms, or not at full
        LD (LATCH_PENDING),A

cfg_merge:
        LD A,(HL)
        XOR B
        AND C
        XOR (HL)
        LD (HL),A
        JP cfg_seal

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

; ---- cmd_09_channel: 09 d [d]: select a channel by one ASCII digit or two;
;      the second is taken only if it is a digit and the pair is a channel
cmd_09_channel:
        CALL pkt_next_byte
        AND 15
        LD E,A
        LD A,D                  ; D = bytes left, the one at IY included
        DEC A
        JR z,cmd09_one
        LD A,(IY+1)
        SUB '0'
        CP 10
        JR nc,cmd09_one
        LD C,A
        LD A,E
        ADD A,A
        ADD A,A
        ADD A,E
        ADD A,A
        ADD A,C
        CP CHANNELS
        JR nc,cmd09_one
        LD C,A                  ; pkt_next_byte returns the loop's count in DE
        CALL pkt_next_byte
        LD E,C

cmd09_one:
        LD A,E                  ; chan_open takes the channel in A and E

select_chan_common:
        CALL chan_open
        JR pkt_next_jr19

; ---- cmd_04_sequence: 04 dd dd ... [D|d]: rebuild SEQ_LIST from 2-digit channel
;      numbers, or 1-digit ones with ten channels
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
        CALL is_digit
    IFDEF LITE
        JR nc,pkt_next_jr19
    ELSE
        JR nc,seq_messages
    ENDIF
        AND 15
    IF CHANNELS <= 10
        JR seq_pair_store
    ENDIF
        LD C,A                  ; the tens
        CALL pkt_next_byte
        CP 'D'
        JR z,seq_pair_demo
        CP 'd'
        JR z,seq_pair_demo
        CALL is_digit
        JR nc,pkt_next_jr19
        AND 15
        LD E,A
        LD A,C
        ADD A,A
        ADD A,A
        ADD A,C
        ADD A,A
        ADD A,E
        JR seq_pair_store

seq_pair_demo:
        LD A,CHAN_DEMO

seq_pair_store:
        LD (HL),A
        INC HL
        LD A,0xff
        LD (HL),A
        DJNZ seq_pair_loop
        JR pkt_next_jr19

    IFNDEF LITE
seq_messages:                   ; P54: 'M' is 00-89, leaving 90-99 to the fields
        AND 0xdf
        CP 'M'
        CALL z,seq_list_messages
        JP pkt_next
    ENDIF

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

; ---- is_plain_byte: Z if A is message text (neither ignored nor a command)
is_plain_byte:
        CP ' '
        JR c,plain_lookup
        CP KEY_DEL              ; 7F, past printable ASCII
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
        OR 1
        RET

; ---- data: 16-byte firmware ID, returned by query B4 '0' (0048 in stock)
ROM_ID:
        db "78409O1702930205"

; ---- CFG_DEFAULTS: the block after a RAM loss, the sum computed at boot
CFG_DEFAULTS:
        db CFG_MAGIC, 1         ; signature, address 1 (NETCC's default)
        db 0x03                 ; full brightness, beeper on, remote unlocked, no status reports
        db HOLD_FRAMES, FLASH_HALF_PERIOD

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
        db 0x00                ; LATCH_BIT7: 00 or LATCH_BLINK, OR-ed into the row code as it is
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

; ---- MAGIC_CLASH_PAIRS: (old<<4 | new) foreground pairs too alike to follow each
;      other in MAGIC mode: yellow/lime, yellow/orange, red/orange
MAGIC_CLASH_PAIRS:
        db 0xf7,0x7f,0xfd,0xdf,0xcd,0xdc
MAGIC_CLASH_LEN      equ $-MAGIC_CLASH_PAIRS
; ---- MAGIC_PUNCT: a word ending in one of these changes the color in MAGIC mode
MAGIC_PUNCT:
        db ".!?:,"
MAGIC_PUNCT_LEN      equ $-MAGIC_PUNCT
; ---- MAGIC_COLOR_CYCLE: the 16 foregrounds MAGIC mode walks through
MAGIC_COLOR_CYCLE:
        db 0x07,0x0c,0x0f,0x03,0x0c,0x03,0x0d,0x03,0x0f,0x03
        db 0x0c,0x03,0x03,0x0c,0x0f,0x0c

; ---- data 18e8-18f3: 10000,1000,100,10,1,-1 for bin_to_dec5
DEC_TABLE:
        dw 0x2710
        dw 0x03e8
        dw 0x0064
        dw 0x000a
        dw 0x0001
        dw 0xffff

; ---- data 2427-2464: IR/keypad code -> character map
IR_KEY_TABLE:
        db 0x0f,0x33,0x0c,0x0b,0x0d,0x09,0x0a,0x0e,0x03,0x3f,0x3c,0x3b,0x3d,0x39,0x3a,0x3e
        db 0x2f,0x13,0x2c,0x2b,0x2d,0x29,0x2a,0x2e,0x24,0x23,0x1c,0x1b,0x1d,0x19,0x1a,0x22   ; P36: 1D is SHIFT, caught before the table: its entry finds the keypad's SHIFT
        db 0x31,0x30,0x37,0x36,0x35,0x08,0x32,0x34,0x01,0x00,0x07,0x06,0x05,0x38,0x02,0x04
        db 0x11,0x10,0x17,0x16,0x15,0x28,0x12,0x14,0x21,0x20,0x27,0x26,0x25,0x18

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
        db 0x43, ','            ; P46: the remote has no comma key
        db 0x63, ','
        db 0x44, 0x9f           ; P56: the degree sign
        db 0x64, 0x9f
        db ATTR_MAGIC, KEY_ADDRESS
        db ATTR_BIG, ATTR_TINY
    IFNDEF LITE
        db KEY_PROG, KEY_FIELD  ; P54
    ENDIF
        db ' ', ' '             ; P57: FLUSH, B2 20 (func_store)
        db 0xff

; ---- FUNC2_TABLE (P46): key, the attribute that follows B2
FUNC2_TABLE:
        db ATTR_COLOR, ATTR_RAINBOW
        db 0x8f, ATTR_RAINBOW
        db ATTR_UP, ATTR_UP         ; P48
        db ATTR_DOWN, ATTR_DOWN
        db ATTR_PAUSE, ATTR_PAUSE   ; P49
        db ATTR_HOLD, ATTR_HOLD     ; P50
        db ATTR_RIGHT, ATTR_RIGHT   ; P53
        db 0xff

; ---- RAINBOW_COLORS: per-character cycle red, orange, yellow, lime, green: entries
;      1-RAINBOW_N are FG_IDX_TABLE's first entries, and entry 0 (off) is never read
RAINBOW_COLORS       equ FG_IDX_TABLE-1
; ---- data 2718-2721: cmd 15 n: foreground color codes (Red,Orange,Yellow,Lime,Green,Dark red,Gold,Black,Lemon,Dark green)
FG_IDX_TABLE:
        db ATTR_COLOR_RED,ATTR_COLOR_ORANGE,ATTR_COLOR_YELLOW,ATTR_COLOR_LIME,ATTR_COLOR_GREEN
        db ATTR_COLOR_DARK_RED,ATTR_COLOR_GOLD,ATTR_COLOR_BLACK,ATTR_COLOR_LEMON,ATTR_COLOR_DARK_GREEN
FG_COLORS            equ $-FG_IDX_TABLE

; ---- data 2722-2727: cmd 16 n: background color codes
BG_IDX_TABLE:
        db ATTR_BGRND_RED,ATTR_BGRND_YELLOW,ATTR_BGRND_YELLOW,ATTR_BGRND_YELLOW,ATTR_BGRND_GREEN,ATTR_BGRND_BLACK
BG_COLORS            equ $-BG_IDX_TABLE

; ---- STATUS_FLAGS: the status line's flags and labels, the first one set is shown
STATUS_FLAGS:
        dw GRAPH_PENDING,STR_GRAPH
        dw COLOR_PENDING,STR_COLOR
        dw BGRND_PENDING,STR_BGRND
        dw FUNC_PENDING,STR_FUNC
        dw EURO_STATE,STR_EURO
        dw SPEED_PENDING,STR_SPEED
    IFNDEF LITE
        dw FIELD_PENDING,STR_FIELD
    ENDIF
STATUS_FLAGS_END:

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
        db 0x0f,"W-RIGHT",0x16,0x00         ; P53
        db ATTR_BIG,"BIG",0x16,0x00
        db ATTR_NORM,"NORM",0x16,0x00
        db ATTR_BOLD,"BOLD",0x16,0x00
        db ATTR_ITALIC,"ITALIC",0x16,0x00
        db ATTR_FLASH,"FLASH",0x16,0x00
        db ATTR_LEFT,"LEFT",0x16,0x00
        db ATTR_PAUSE,"PAUSE",0x16,0x00
        db ATTR_UP,"W-UP",0x16,0x00          ; P48: W- wipes, S- scrolls
        db ATTR_DOWN,"W-DOWN",0x16,0x00
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
        db ATTR_RAINBOW^0x40,"RANDBOW",0x16,0x00   ; P46: B2 BC; a variant's key is its attribute ^ 40
        db ATTR_UP^0x40,"S-UP",0x16,0x00
        db ATTR_DOWN^0x40,"S-DOWN",0x16,0x00
        db 0x0f^0x40,"S-RIGHT",0x16,0x00     ; P53
        db ATTR_PAUSE^0x40,"TWINKLE",0x16,0x00
        db ATTR_HOLD^0x40,"GLIMMER",0x16,0x00
        db ' '^0x40,"FLUSH",0x16,0x00         ; P57
        db ATTR_MAGIC_OFF,"MAGIC OFF",0x16,0x00
        db ATTR_TINY,"TINY",0x16,0x00
        db 0xff
; ---- the status line's labels and the SHIFT indicator (through MENU_MSG_PTR)
    IFNDEF LITE
STR_F:
        db "F",0x00
STR_FIELD:
        db "FIELD ",0x00
    ENDIF
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
STR_FUNC2:
        db "FUNC2",0x00
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
        db 5,5,5,5,5,5,5,5,5,5,5,5,5,5,2,3   ; glyphs 160-175
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
        db 0x02,0x05,0x02                         ; glyph 175: 9F, the degree sign (P55)
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
        db 0xfe,0xfa,0xff,0xfe,0xaa,0x80,0xaa,0xfe                                           ; char 00-1f
; ---- WIDE_SPACE_GLYPH: 9-column blank for spaces in MAGIC mode; also the 5 and 6
;      blank columns the TINY push-offs blit. Shares the zeros of characters 20-7f
WIDE_SPACE_GLYPH:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00                                           ; char 20-3f
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; char 40-7f
        db 0xaa,0xaa,0xaa,0xaa,0xaa,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xbb,0xff,0x2a,0xab   ; char 80-bf (P55: 9F printable)
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
DEMO_MESSAGE:                   ; P57: hand-colored italic, MAGIC, the model in a twinkling scroll
        db ATTR_ITALIC,ATTR_COLOR_RED,"C",ATTR_COLOR_ORANGE,"O",ATTR_COLOR_LIME,"L",ATTR_COLOR_YELLOW,"O",ATTR_COLOR_GREEN,"R"
        db ATTR_MAGIC,ATTR_ITALIC," CELLS",ATTR_ALT,ATTR_UP,ATTR_BOLD,ATTR_ALT,ATTR_PAUSE
    IFDEF CC710
        db "CC710"
    ELSE
        db "CC784"
    ENDIF
        db ATTR_LEFT,ATTR_RAINBOW,ATTR_NORM,ATTR_FLASH,"MULTI-COLOR ",ATTR_NORM,"DISPLAY"
        db ATTR_TINY,"TINY PRICE",ATTR_BIG,"LARGE IMPACT!",TEXT_END,0xdb

; ---- ota_updating_msg: what the panel shows from B5 'B' to the reboot, via the
;      test-mode buffer (28 bytes max). PAUSE, THIN, the word, WAIT: parked until
;      a key. Last thing before the trailer, so editing it moves nothing else.
ota_updating_msg:
        db 0x19,0xb9,">FW ^<",0xba,0x03     ; ^ is the up-arrow glyph; fits 59 columns

; ---- trailer page 3FC0-3FFF (ota.md §3): magic, sequence number, state
;      and image CRC, filled in by tools/cc784_ota.py pack. Erased in the build.
        ds 0x3fc0-$,0xff
TRAILER:
        ds 0x4000-$,0xff
    IFNDEF LITE                 ; LITE: one 16 K image for a 27128
        ds 0x8000-$,0xff        ; bank B: the packer fills it, the T48 image carries both
    ENDIF
