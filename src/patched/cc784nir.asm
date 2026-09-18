; ============================================================================
;  Color Cells CC784NIR LED sign - PATCHED firmware source
;  Assemble:  sjasmplus cc784nir.asm   (produces cc784nir_patched.bin, 32768 B)
;  NOT byte-identical to the dump - 55 bytes differ. The untouched
;  reconstruction is ../stock/cc784nir.asm; diff the two to see the patches.
;  See CC784NIR_annotated.asm for the listing with addresses/hex and full notes.
; ============================================================================
        DEVICE NONE

; Patched build: the five fixes in CC784_firmware.md §11 are applied here.
; Every patch is size-neutral in place and the two spill-over subroutines sit
; at 0x3C21 in the 0xFF fill, so no stock address moves and the per-line
; address comments stay valid. Diff against ../stock/cc784nir.asm to see
; exactly what changed; everything else is kept identical on purpose.

        OUTPUT "cc784nir_patched.bin"

FRAMEBUF             equ 0x4040
FRAMEBUF_ROW1        equ 0x4096
FRAMEBUF_TINY        equ 0x40eb
FB_COLPTR            equ 0x4198
FB_COL               equ 0x419b
FB_TMP               equ 0x41a1
TXBUF                equ 0x41a2
EFFECT_TMP           equ 0x41f8
EFFECT_TMP2          equ 0x41fb
FLASH_TIMER          equ 0x41fd
TICK_COUNTDOWN       equ 0x41fe
CLK_H10              equ 0x4200
CLK_H1               equ 0x4201
CLK_M10              equ 0x4202
CLK_M1               equ 0x4203
CLK_SEC              equ 0x4204
CLK_PM               equ 0x4205
CLK_RUN              equ 0x4206
GLYPH_WIDTH          equ 0x4207
GLYPH_PTR            equ 0x4208
CUR_COLOUR           equ 0x420c
EFFECT_PHASE         equ 0x420d
CUR_CHAR             equ 0x420e
SEQ_PTR_SAVE         equ 0x4210
EFFECT_ACTIVE        equ 0x4212
MENU_ACTIVE          equ 0x4217
INS_PTR              equ 0x4218
RENDER_DONE          equ 0x421a
COL_COUNT            equ 0x421c
ROW_DATA_LATCH       equ 0x4222
RX_MSGFLAG           equ 0x4223
RX_LASTCMD           equ 0x4225
RX_BYTE              equ 0x4228
BEEP_TIMER           equ 0x422a
CTRL_LATCH_SHADOW    equ 0x422d
DISP_FLAGS           equ 0x4230
FB_EXTRA_LEN         equ 0x4232
STORE_END            equ 0x4234
PAUSE_FLAG           equ 0x423a
EFFECT_VECTOR        equ 0x423b
MENU_TEXT_PTR        equ 0x423d
ROW_INDEX            equ 0x4245
RX_BITMASK           equ 0x4246
RX_SHIFT             equ 0x4249
RX_TICKS             equ 0x424b
RX_FIFO              equ 0x424d
RX_COUNT             equ 0x4255
RX_TIMING_PTR        equ 0x4256
RX_STATE             equ 0x425c
CHAN_LOCK            equ 0x426a
SEQ_LIST             equ 0x426b
SEQ_PTR              equ 0x42d3
SEQ_IDX              equ 0x42d5
FONT_MODE            equ 0x4339
TINY_MODE            equ 0x433a
NMI_COUNT            equ 0x433c
STORE_TMP            equ 0x433e
MOVE_DST             equ 0x4340
MOVE_SRC             equ 0x4342
STORE_CURSOR         equ 0x4346
TX_BITIDX            equ 0x4348
TX_BITMASK           equ 0x4349
TX_PENDING           equ 0x434a
TX_TICKS             equ 0x434b
TX_SHIFT             equ 0x434c
TX_STATUS            equ 0x434d
TX_TIMING_PTR        equ 0x434e
DISP_ENABLE          equ 0x4359
MENU_FLAG            equ 0x435b
NMI_PER_SEC          equ 0x435d
ROW_PHASE            equ 0x435e
TINY_RENDER          equ 0x435f
TICK6_COUNT          equ 0x4379
TICK1_COUNT          equ 0x437a
GEN_COUNTDOWN        equ 0x4380
IR_STATE_CNT         equ 0x4382
IR_BITCNT            equ 0x4383
IR_KEY               equ 0x4384
IR_SHIFT             equ 0x4385
IR_CODE              equ 0x4386
TICK_VECTOR          equ 0x4388
MENU_CHAR            equ 0x4393
MENU_TMP             equ 0x4394
RND_SEED             equ 0x4396
MENU_TMP2            equ 0x4397
RND_VAL              equ 0x4398
CHAN_D10             equ 0x439c
CHAN_D1              equ 0x439d
MENU_ENTRY_BUF       equ 0x43c5
MY_ADDRESS           equ 0x43cb
MY_ADDRESS_INV       equ 0x43cc
BLANK_TIMER          equ 0x43ce
GLYPH_PTR2           equ 0x43d0
STORE_LIMIT          equ 0x43d8
STORE_SIZE           equ 0x43da
MSG_STORE            equ 0x43e2
PKT_READY            equ 0x5ef0
PKT_BUF              equ 0x5ef1
PKT_STATE            equ 0x5ff1
PKT_CKSUM            equ 0x5ff2
PKT_FLAG             equ 0x5ff3
PKT_LEN              equ 0x5ff4
PKT_VECTOR           equ 0x5ff5
PKT_ADDR             equ 0x5ff7
PKT_PTR              equ 0x5ff8
PKT_REMAIN           equ 0x5ffa
CTRL_LATCH           equ 0x8000

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
STACK_TOP            equ 0x5ef0      ; first PUSH lands at 0x5EEE
STORE_TOP            equ 0x5def
; ir_init derives these three from STORE_TOP; keep them in step or the store
; scans, the "100 KEYS LEFT" warning and the B4 '1' memory report disagree.
STORE_WARN           equ STORE_TOP-100            ; 0x5E8B stock
STORE_SIZE_INIT      equ STORE_TOP-MSG_STORE+1    ; 0x1B0E stock
STORE_TEXT_FREE      equ STORE_SIZE_INIT-301      ; 0x19E1 stock (301 = framing)

        org 0x0000

; ---- RESET: cold start: set SP, run init routines, EI, jump to main loop
RESET:
        LD SP,STACK_TOP                  ; 0000
        CALL init_vars                   ; 0003
        CALL ir_init                     ; 0006
        CALL ir_init2                    ; 0009
        CALL init_vars3                  ; 000c

L_000f:
        CALL init_render                 ; 000f
        CALL init_vars2                  ; 0012
        CALL init_sequence               ; 0015
        EI                               ; 0018
        JP main_loop                     ; 0019

; ---- data 001c-0037: unused
        ds 28,0xff

; ---- INT_VECTOR: IM1 interrupt entry (periodic timer, ~1300 Hz)
INT_VECTOR:
        JP int_timer                     ; 0038

; ---- data 003b-0047: unused
        ds 13,0xff

; ---- data 0048-0057: 16-byte firmware ID, returned by query B4 '0'
ROM_ID:
        db "78409O1702930205"   ; 0048

; ---- data 0058-0065: unused
        ds 14,0xff

; ---- NMI_VECTOR: NMI = real-time clock tick (mains frequency); calls clock_tick
NMI_VECTOR:
        PUSH AF                          ; 0066
        PUSH BC                          ; 0067
        PUSH DE                          ; 0068
        PUSH HL                          ; 0069
        CALL clock_tick                  ; 006a
        POP HL                           ; 006d
        POP DE                           ; 006e
        POP BC                           ; 006f
        POP AF                           ; 0070
        RETN                             ; 0071

; ---- int_timer: Timer ISR. Every 6th tick schedules tick6_service; every tick schedules the handler in TICK_VECTOR (IR decoder). Both are invoked by pushing their address so they run as the ISR returns.
int_timer:
        EX AF,AF'                        ; 0073
        EXX                              ; 0074
        LD A,(TICK6_COUNT)               ; 0075
        INC A                            ; 0078
        CP 6                             ; 0079
        JR nz,L_0082                     ; 007b
        LD HL,0xc4                       ; 007d
        PUSH HL                          ; 0080
        XOR A                            ; 0081

L_0082:
        LD (TICK6_COUNT),A               ; 0082
        LD A,(TICK1_COUNT)               ; 0085
        INC A                            ; 0088
        CP 1                             ; 0089
        JR nz,L_0092                     ; 008b
        LD HL,(TICK_VECTOR)              ; 008d
        PUSH HL                          ; 0090
        XOR A                            ; 0091

L_0092:
        LD (TICK1_COUNT),A               ; 0092
        EX AF,AF'                        ; 0095
        EXX                              ; 0096
        EI                               ; 0097
        RETI                             ; 0098

; ---- main_loop: Main loop: if PKT_READY process packet, else init/render/effect step, then loop.
;      The PKT_READY test runs ONCE on entry - L_00a7 below never falls back
;      to 0x009A. Re-entry only happens via fx_end_of_channel (0x0F5E) at the
;      end of a display cycle, or the BA wait-for-key spin at 0x0A49. That is
;      why NETCC sets PKT_FLAG=0x80: deferred packets wait for the current
;      channel to finish, which can be many seconds.
main_loop:
        LD A,(PKT_READY)                 ; 009a
        AND A                            ; 009d
        JP nz,pkt_process                ; 009e
        CALL init_render                 ; 00a1
        CALL init_display_state          ; 00a4

L_00a7:
        CALL render_next_char            ; 00a7
        CALL effect_step                 ; 00aa
        ; LD A,(nn) sets no flags, so this JR tests effect_step's exit flags,
        ; not RENDER_DONE. A is loaded for whatever runs after the branch.
        LD A,(RENDER_DONE)               ; 00ad
        JR nz,L_00a7                     ; 00b0
        XOR A                            ; 00b2
        LD (COL_COUNT),A                 ; 00b3
        LD HL,fx_none                    ; 00b6
        LD (PAUSE_FLAG),A                ; 00b9
        LD (EFFECT_VECTOR),HL            ; 00bc
        JR L_00a7                        ; 00bf
        db 0xc3,0xa7,0x00   ; 00c1

; ---- tick6_service: Runs every 6 timer ticks: serial RX/TX bit engines, countdowns, display column refresh & flashing, then the RX byte consumer.
tick6_service:
        PUSH AF                          ; 00c4
        LD A,(IX+0)                      ; 00c5
        CP 0xaa                          ; 00c8
        JR nz,L_00d5                     ; 00ca
        LD A,(IY+0)                      ; 00cc
        CP 0x55                          ; 00cf
        JR nz,L_00d5                     ; 00d1
        POP AF                           ; 00d3
        RET                              ; 00d4

L_00d5:
        PUSH BC                          ; 00d5
        PUSH DE                          ; 00d6
        PUSH HL                          ; 00d7
        PUSH IX                          ; 00d8
        PUSH IY                          ; 00da
        LD HL,(GEN_COUNTDOWN)            ; 00dc
        DEC HL                           ; 00df
        LD A,H                           ; 00e0
        AND L                            ; 00e1
        CP 0xff                          ; 00e2
        JR z,L_00e9                      ; 00e4
        LD (GEN_COUNTDOWN),HL            ; 00e6

L_00e9:
        CALL rx_bit_engine               ; 00e9
        CALL tx_bit_engine               ; 00ec
        LD HL,(TICK_COUNTDOWN)           ; 00ef
        LD A,H                           ; 00f2
        OR L                             ; 00f3
        JR z,L_00fa                      ; 00f4
        DEC HL                           ; 00f6
        LD (TICK_COUNTDOWN),HL           ; 00f7

L_00fa:
        LD A,(MENU_ACTIVE)               ; 00fa
        AND A                            ; 00fd
        JR nz,L_0125                     ; 00fe
        LD A,(PAUSE_FLAG)                ; 0100
        AND A                            ; 0103
        JR nz,L_0125                     ; 0104
        LD A,(TINY_RENDER)               ; 0106
        AND A                            ; 0109
        JP nz,L_124b                     ; 010a
        LD A,(BLANK_TIMER)               ; 010d
        AND A                            ; 0110
        JR z,L_0125                      ; 0111
        DEC A                            ; 0113
        LD (BLANK_TIMER),A               ; 0114
        LD A,(CTRL_LATCH_SHADOW)         ; 0117
        OR 15                            ; 011a
        LD (CTRL_LATCH_SHADOW),A         ; 011c
        LD (CTRL_LATCH),A                ; 011f
        JP L_030d                        ; 0122

L_0125:
        LD A,(DISP_ENABLE)               ; 0125
        AND A                            ; 0128
        JP z,L_01ce                      ; 0129
        LD A,(CTRL_LATCH_SHADOW)         ; 012c
        OR 15                            ; 012f
        LD (CTRL_LATCH_SHADOW),A         ; 0131
        LD (CTRL_LATCH),A                ; 0134
        LD A,(EFFECT_ACTIVE)             ; 0137
        AND A                            ; 013a
        JP z,L_01b9                      ; 013b
        LD HL,(SEQ_PTR_SAVE)             ; 013e
        LD A,(DISP_FLAGS)                ; 0141
        LD B,A                           ; 0144
        LD A,(FLASH_TIMER)               ; 0145
        LD C,A                           ; 0148
        LD A,(ROW_INDEX)                 ; 0149
        CPL                              ; 014c
        AND 7                            ; 014d
        DEC A                            ; 014f
        OR C                             ; 0150
        LD C,A                           ; 0151
        PUSH IX                          ; 0152
        LD IX,TICK_COUNTDOWN             ; 0154
        LD A,(IX+0)                      ; 0158
        OR (IX+1)                        ; 015b
        POP IX                           ; 015e
        JR z,L_0164                      ; 0160
        SET 5,C                          ; 0162

L_0164:
        LD A,(ROW_DATA_LATCH)            ; 0164
        OUT (C),A                        ; 0167
        LD A,B                           ; 0169
        AND A                            ; 016a
        JR z,L_0182                      ; 016b
        BIT 0,B                          ; 016d
        JR z,L_0174                      ; 016f
        DEC B                            ; 0171
        JR z,L_017f                      ; 0172

L_0174:
        OTIR                             ; 0174
        LD A,(DISP_FLAGS)                ; 0176
        BIT 0,A                          ; 0179
        JR z,L_0182                      ; 017b
        LD B,1                           ; 017d

L_017f:
        LD A,(HL)                        ; 017f
        OUT (C),A                        ; 0180

L_0182:
        LD A,(FB_EXTRA_LEN)              ; 0182
        AND A                            ; 0185
        JR z,L_018e                      ; 0186
        LD B,A                           ; 0188
        LD HL,FRAMEBUF                   ; 0189
        OTIR                             ; 018c

L_018e:
        LD A,(CTRL_LATCH_SHADOW)         ; 018e
        AND 0x70                         ; 0191
        OR 15                            ; 0193
        LD (CTRL_LATCH),A                ; 0195
        OUT (PORT_STROBE),A              ; 0198
        LD A,(ROW_INDEX)                 ; 019a
        CPL                              ; 019d
        AND 7                            ; 019e
        DEC A                            ; 01a0
        JR nz,L_01a5                     ; 01a1
        LD A,7                           ; 01a3

L_01a5:
        LD C,A                           ; 01a5
        LD A,(0x421f)                    ; 01a6
        OR C                             ; 01a9
        AND 0x8f                         ; 01aa
        LD C,A                           ; 01ac
        LD A,(CTRL_LATCH_SHADOW)         ; 01ad
        AND 0x70                         ; 01b0
        OR C                             ; 01b2
        LD (CTRL_LATCH_SHADOW),A         ; 01b3
        LD (CTRL_LATCH),A                ; 01b6

L_01b9:
        LD A,(FLASH_TIMER)               ; 01b9
        CP 0x48                          ; 01bc
        JR z,L_01c7                      ; 01be
        LD A,0x48                        ; 01c0
        LD (FLASH_TIMER),A               ; 01c2
        JR L_01cb                        ; 01c5

L_01c7:
        XOR A                            ; 01c7
        LD (DISP_ENABLE),A               ; 01c8

L_01cb:
        JP L_030d                        ; 01cb

L_01ce:
        LD A,(ROW_INDEX)                 ; 01ce
        LD C,A                           ; 01d1
        INC A                            ; 01d2
        LD (ROW_INDEX),A                 ; 01d3
        CP 7                             ; 01d6
        JP c,L_0303                      ; 01d8
        LD A,0                           ; 01db
        LD (ROW_INDEX),A                 ; 01dd
        LD A,(0x43cd)                    ; 01e0
        LD (BLANK_TIMER),A               ; 01e3
        LD A,(0x4244)                    ; 01e6
        AND A                            ; 01e9
        JR z,L_01f3                      ; 01ea
        DEC A                            ; 01ec
        LD (0x4244),A                    ; 01ed
        JP L_0281                        ; 01f0

L_01f3:
        LD A,(EFFECT_PHASE)              ; 01f3
        AND A                            ; 01f6
        JR z,L_022a                      ; 01f7
        LD HL,(FB_COL)                   ; 01f9
        LD DE,0x56                       ; 01fc
        CALL sub_0e2d                    ; 01ff
        LD DE,(FB_COLPTR)                ; 0202
        OR A                             ; 0206
        SBC HL,DE                        ; 0207
        JR z,L_0223                      ; 0209
        LD HL,(FB_COL)                   ; 020b
        CALL sub_0e16                    ; 020e
        LD (FB_COL),HL                   ; 0211
        LD DE,0x56                       ; 0214
        CALL sub_0e2d                    ; 0217
        LD DE,(FB_COLPTR)                ; 021a
        OR A                             ; 021e
        SBC HL,DE                        ; 021f
        JR nz,L_0237                     ; 0221

L_0223:
        XOR A                            ; 0223
        LD (EFFECT_PHASE),A              ; 0224
        JP L_0237                        ; 0227

L_022a:
        LD HL,(SEQ_PTR_SAVE)             ; 022a
        LD DE,(FB_COL)                   ; 022d
        OR A                             ; 0231
        SBC HL,DE                        ; 0232
        JP z,L_0281                      ; 0234

L_0237:
        LD HL,(FB_COL)                   ; 0237
        BIT 7,(HL)                       ; 023a
        JR z,L_0242                      ; 023c
        LD A,(HL)                        ; 023e
        LD (0x421b),A                    ; 023f

L_0242:
        LD A,(PAUSE_FLAG)                ; 0242
        AND A                            ; 0245
        LD A,(0x421b)                    ; 0246
        JR z,L_024f                      ; 0249
        AND 0x10                         ; 024b
        OR 0x8f                          ; 024d

L_024f:
        LD (ROW_DATA_LATCH),A            ; 024f
        LD HL,(FB_COL)                   ; 0252
        LD (SEQ_PTR_SAVE),HL             ; 0255
        LD HL,FB_COLPTR                  ; 0258
        LD BC,(FB_COL)                   ; 025b
        LD DE,0x56                       ; 025f
        XOR A                            ; 0262
        SBC HL,BC                        ; 0263
        XOR A                            ; 0265
        LD (DISP_FLAGS),HL               ; 0266
        EX DE,HL                         ; 0269
        SBC HL,DE                        ; 026a
        JP z,L_0275                      ; 026c
        JP c,L_0275                      ; 026f
        JP L_027e                        ; 0272

L_0275:
        LD HL,0x56                       ; 0275
        LD (DISP_FLAGS),HL               ; 0278
        LD HL,0                          ; 027b

L_027e:
        LD (FB_EXTRA_LEN),HL             ; 027e

L_0281:
        LD A,(0x421d)                    ; 0281
        INC A                            ; 0284
        LD (0x421d),A                    ; 0285
        CP 13                            ; 0288
        JR nz,L_02a1                     ; 028a
        XOR A                            ; 028c
        LD (0x421d),A                    ; 028d
        LD A,(0x421f)                    ; 0290
        AND A                            ; 0293
        JR z,L_029c                      ; 0294
        XOR A                            ; 0296
        LD (0x421f),A                    ; 0297
        JR L_02a1                        ; 029a

L_029c:
        LD A,0x80                        ; 029c
        LD (0x421f),A                    ; 029e

L_02a1:
        NOP                              ; 02a1

; ---- rx_consume: Pop a byte from RX_FIFO; in normal mode feed the packet parser (or if IR_CODE=A4/A5 handle keypad); packet start needs 0xB1 while idle
rx_consume:
        LD A,(MENU_ACTIVE)               ; 02a2
        AND A                            ; 02a5
        JP nz,tick6_exit                 ; 02a6
        CALL rx_fifo_get                 ; 02a9
        JP nc,L_02ca                     ; 02ac
        LD A,(IR_CODE)                   ; 02af
        CP 0xa4                          ; 02b2
        JP z,L_02c4                      ; 02b4
        CP 0xa5                          ; 02b7
        JP nz,tick6_exit                 ; 02b9
        LD A,0x20                        ; 02bc
        LD (RX_BYTE),A                   ; 02be
        JP tick6_exit                    ; 02c1

L_02c4:
        LD (IR_KEY),A                    ; 02c4
        JP key_handler                   ; 02c7

L_02ca:
        LD A,(PKT_STATE)                 ; 02ca
        AND A                            ; 02cd
        JR z,L_02d6                      ; 02ce
        CALL pkt_feed_byte               ; 02d0
        JP tick6_exit                    ; 02d3

L_02d6:
        LD A,(RX_BYTE)                   ; 02d6
        CP 0xb1                          ; 02d9
        JR nz,L_02f1                     ; 02db
        LD A,(PKT_READY)                 ; 02dd
        AND A                            ; 02e0
        JR nz,tick6_exit                 ; 02e1
        LD A,0xff                        ; 02e3
        LD (PKT_STATE),A                 ; 02e5
        LD HL,pkt_st_addr                ; 02e8
        LD (PKT_VECTOR),HL               ; 02eb
        JP tick6_exit                    ; 02ee

L_02f1:
        LD A,(RX_BYTE)                   ; 02f1
        CP 1                             ; 02f4
        JP z,key_handler                 ; 02f6

; ---- tick6_exit
tick6_exit:
        LD A,(BEEP_TIMER)                ; 02f9
        AND A                            ; 02fc
        JR z,L_0303                      ; 02fd
        DEC A                            ; 02ff
        LD (BEEP_TIMER),A                ; 0300

L_0303:
        LD A,0xff                        ; 0303
        LD (DISP_ENABLE),A               ; 0305
        LD A,0x40                        ; 0308
        LD (FLASH_TIMER),A               ; 030a

L_030d:
        POP IY                           ; 030d
        POP IX                           ; 030f
        POP HL                           ; 0311
        POP DE                           ; 0312
        POP BC                           ; 0313
        POP AF                           ; 0314
        RET                              ; 0315

; ---- init_sequence: Init SEQ_LIST (0x68 bytes) etc.
init_sequence:
        XOR A                            ; 0316
        LD (SEQ_IDX),A                   ; 0317
        LD B,0x68                        ; 031a
        LD HL,SEQ_LIST                   ; 031c
        LD A,(HL)                        ; 031f
        CP 0xff                          ; 0320
        JR z,L_0336                      ; 0322

L_0324:
        CP 0x65                          ; 0324
        JR nc,L_0332                     ; 0326
        INC HL                           ; 0328
        LD A,(HL)                        ; 0329
        DJNZ L_0324                      ; 032a
        DEC HL                           ; 032c
        LD (HL),0xff                     ; 032d
        JP L_034d                        ; 032f

L_0332:
        CP 0xff                          ; 0332
        JR z,L_034d                      ; 0334

L_0336:
        LD HL,SEQ_LIST                   ; 0336
        LD A,0                           ; 0339
        LD B,0x64                        ; 033b

L_033d:
        LD (HL),A                        ; 033d
        INC HL                           ; 033e
        INC A                            ; 033f
        DJNZ L_033d                      ; 0340
        LD (HL),0xff                     ; 0342
        INC HL                           ; 0344
        LD (HL),0xff                     ; 0345
        INC HL                           ; 0347
        LD (HL),0xff                     ; 0348
        INC HL                           ; 034a
        LD (HL),0xff                     ; 034b

L_034d:
        LD HL,SEQ_LIST                   ; 034d

L_0350:
        LD A,(HL)                        ; 0350
        INC HL                           ; 0351
        PUSH HL                          ; 0352
        CP 0xff                          ; 0353
        JR z,L_0366                      ; 0355
        CALL chan_select                 ; 0357
        OR A                             ; 035a
        JP nz,pkt_process_end            ; 035b
        LD A,(HL)                        ; 035e
        CP 3                             ; 035f
        POP HL                           ; 0361
        RET nz                           ; 0362
        JP L_0350                        ; 0363

L_0366:
        POP HL                           ; 0366
        LD A,10                          ; 0367
        LD (SEQ_IDX),A                   ; 0369
        RET                              ; 036c

; ---- init_display_state
init_display_state:
        LD A,(0x420f)                    ; 036d
        INC A                            ; 0370
        JP z,L_0410                      ; 0371
        LD A,(MENU_FLAG)                 ; 0374
        CP 0x64                          ; 0377
        JP nc,L_0386                     ; 0379
        LD E,A                           ; 037c
        LD A,0xff                        ; 037d
        LD (MENU_FLAG),A                 ; 037f
        LD A,E                           ; 0382
        JP L_03ae                        ; 0383

L_0386:
        LD A,(SEQ_IDX)                   ; 0386
        LD E,A                           ; 0389
        CP 10                            ; 038a
        LD A,0x64                        ; 038c
        JR z,L_03ae                      ; 038e
        LD HL,(SEQ_PTR)                  ; 0390
        LD A,(HL)                        ; 0393
        CP 0xff                          ; 0394
        JR nz,L_03a1                     ; 0396
        LD HL,SEQ_LIST                   ; 0398
        LD (SEQ_PTR),HL                  ; 039b
        JP init_display_state            ; 039e

L_03a1:
        CP 0x65                          ; 03a1
        JR c,L_03a9                      ; 03a3
        LD A,0x64                        ; 03a5
        LD (HL),0x64                     ; 03a7

L_03a9:
        LD E,A                           ; 03a9
        INC HL                           ; 03aa
        LD (SEQ_PTR),HL                  ; 03ab

L_03ae:
        LD E,A                           ; 03ae
        PUSH DE                          ; 03af
        CALL chan_select                 ; 03b0
        POP DE                           ; 03b3
        OR A                             ; 03b4
        JP nz,pkt_process_end            ; 03b5
        LD A,(HL)                        ; 03b8
        CP 3                             ; 03b9
        JR z,L_03f8                      ; 03bb
        PUSH HL                          ; 03bd
        LD B,0                           ; 03be
        LD C,A                           ; 03c0
        LD IX,0x372d                     ; 03c1
        ADD IX,BC                        ; 03c5
        BIT 1,(IX+0)                     ; 03c7
        JR z,L_03e6                      ; 03cb

L_03cd:
        INC HL                           ; 03cd
        LD A,(HL)                        ; 03ce
        CP 3                             ; 03cf
        JR nz,L_03d7                     ; 03d1
        POP HL                           ; 03d3
        JP L_03f8                        ; 03d4

L_03d7:
        LD B,0                           ; 03d7
        LD C,A                           ; 03d9
        LD IX,0x372d                     ; 03da
        ADD IX,BC                        ; 03de
        BIT 1,(IX+0)                     ; 03e0
        JR nz,L_03cd                     ; 03e4

L_03e6:
        POP HL                           ; 03e6
        LD (STORE_CURSOR),HL             ; 03e7
        PUSH DE                          ; 03ea
        CALL chan_find                   ; 03eb
        POP DE                           ; 03ee
        LD A,E                           ; 03ef
        CP 0x64                          ; 03f0
        JR nz,L_03f7                     ; 03f2
        LD (CHAN_LOCK),A                 ; 03f4

L_03f7:
        RET                              ; 03f7

L_03f8:
        LD HL,(SEQ_PTR)                  ; 03f8
        LD A,(HL)                        ; 03fb
        CP 0xff                          ; 03fc
        JP nz,init_display_state         ; 03fe
        DEC HL                           ; 0401
        LD DE,SEQ_LIST                   ; 0402
        OR A                             ; 0405
        SBC HL,DE                        ; 0406
        JP nz,init_display_state         ; 0408
        LD A,0x64                        ; 040b
        JP L_03ae                        ; 040d

L_0410:
        LD HL,0x43a5                     ; 0410
        LD (STORE_CURSOR),HL             ; 0413
        CALL chan_find                   ; 0416
        RET                              ; 0419

; ---- chan_find: Locate channel marker (D0+n) in MSG_STORE
chan_find:
        LD HL,0x4260                     ; 041a
        LD B,11                          ; 041d
        LD A,0                           ; 041f

L_0421:
        LD (HL),A                        ; 0421
        INC HL                           ; 0422
        DJNZ L_0421                      ; 0423
        RET                              ; 0425

; ---- chan_select: Select channel E: find/create its slot in MSG_STORE, set INS_PTR/STORE_CURSOR
chan_select:
        CP 0x64                          ; 0426
        JR nz,L_0430                     ; 0428
        LD HL,DEMO_MESSAGE               ; 042a
        JP L_046e                        ; 042d

L_0430:
        LD DE,0xd0d0                     ; 0430
        AND A                            ; 0433
        JR z,L_0445                      ; 0434
        LD B,A                           ; 0436
        LD A,0xda                        ; 0437

L_0439:
        INC E                            ; 0439
        CP E                             ; 043a
        JR nz,L_0443                     ; 043b
        LD E,0xd0                        ; 043d
        INC D                            ; 043f
        CP D                             ; 0440
        JR z,L_0470                      ; 0441

L_0443:
        DJNZ L_0439                      ; 0443

L_0445:
        LD IX,MSG_STORE                  ; 0445
        LD BC,(STORE_SIZE)               ; 0449

L_044d:
        LD A,(IX+0)                      ; 044d
        CP 0xda                          ; 0450
        JR z,L_0470                      ; 0452
        LD H,A                           ; 0454
        LD L,(IX+1)                      ; 0455
        OR A                             ; 0458
        SBC HL,DE                        ; 0459
        JR z,L_0467                      ; 045b
        INC IX                           ; 045d
        DEC BC                           ; 045f
        LD A,C                           ; 0460
        OR B                             ; 0461
        JR nz,L_044d                     ; 0462
        JP z,L_0470                      ; 0464

L_0467:
        INC IX                           ; 0467
        INC IX                           ; 0469
        PUSH IX                          ; 046b
        POP HL                           ; 046d

L_046e:
        XOR A                            ; 046e
        RET                              ; 046f

L_0470:
        LD A,0xff                        ; 0470
        RET                              ; 0472

; ---- init_vars2
init_vars2:
        CALL sub_04e5                    ; 0473
        CALL sub_050f                    ; 0476
        LD HL,MSG_STORE                  ; 0479
        LD A,0xd0                        ; 047c
        LD D,0xd0                        ; 047e
        LD E,A                           ; 0480
        LD BC,(0x43dc)                   ; 0481

L_0485:
        LD (HL),E                        ; 0485
        INC HL                           ; 0486
        LD (HL),D                        ; 0487
        LD A,0xda                        ; 0488
        INC D                            ; 048a
        CP D                             ; 048b
        JR nz,L_0493                     ; 048c
        LD D,0xd0                        ; 048e
        INC E                            ; 0490
        JR L_049a                        ; 0491

L_0493:
        CP E                             ; 0493
        JR nz,L_049a                     ; 0494
        DEC HL                           ; 0496
        JP L_04dc                        ; 0497

L_049a:
        DEC HL                           ; 049a
        DEC HL                           ; 049b
        LD (HL),0x20                     ; 049c
        INC HL                           ; 049e
        INC HL                           ; 049f
        INC HL                           ; 04a0
        LD A,(HL)                        ; 04a1
        CP 0xd0                          ; 04a2
        JP c,L_04ae                      ; 04a4
        CP 0xdb                          ; 04a7
        JP nc,L_04ae                     ; 04a9
        LD (HL),0x20                     ; 04ac

L_04ae:
        INC HL                           ; 04ae

L_04af:
        LD A,(HL)                        ; 04af
        CP 0xd0                          ; 04b0
        JP c,L_04bc                      ; 04b2
        CP 0xdb                          ; 04b5
        JP nc,L_04bc                     ; 04b7
        JR L_0485                        ; 04ba

L_04bc:
        INC HL                           ; 04bc
        DEC BC                           ; 04bd
        LD A,C                           ; 04be
        OR B                             ; 04bf
        JR z,L_04c5                      ; 04c0
        JP L_04af                        ; 04c2

L_04c5:
        LD A,0xda                        ; 04c5

L_04c7:
        LD (HL),E                        ; 04c7
        CP E                             ; 04c8
        JR z,L_04dc                      ; 04c9
        INC HL                           ; 04cb
        LD (HL),D                        ; 04cc
        INC HL                           ; 04cd
        LD (HL),3                        ; 04ce
        INC HL                           ; 04d0
        INC D                            ; 04d1
        CP D                             ; 04d2
        JR nz,L_04c7                     ; 04d3
        LD D,0xd0                        ; 04d5
        INC E                            ; 04d7
        CP E                             ; 04d8
        JR nz,L_04c7                     ; 04d9
        LD (HL),A                        ; 04db

L_04dc:
        PUSH HL                          ; 04dc
        CALL sub_0524                    ; 04dd
        POP HL                           ; 04e0
        LD A,0xda                        ; 04e1
        LD (HL),A                        ; 04e3
        RET                              ; 04e4

sub_04e5:
        LD HL,MSG_STORE                  ; 04e5
        LD BC,(STORE_SIZE)               ; 04e8
        LD IY,0x4363                     ; 04ec
        LD (IY+0),0                      ; 04f0
        LD D,0                           ; 04f4

L_04f6:
        LD E,(HL)                        ; 04f6
        LD IX,0x372d                     ; 04f7
        ADD IX,DE                        ; 04fb
        BIT 0,(IX+0)                     ; 04fd
        JR z,L_0508                      ; 0501
        LD (HL),0x3f                     ; 0503
        INC (IY+0)                       ; 0505

L_0508:
        INC HL                           ; 0508
        DEC BC                           ; 0509
        LD A,C                           ; 050a
        OR B                             ; 050b
        JR nz,L_04f6                     ; 050c
        RET                              ; 050e

sub_050f:
        LD HL,MSG_STORE                  ; 050f
        LD BC,(STORE_SIZE)               ; 0512

L_0516:
        LD A,(HL)                        ; 0516
        CP 3                             ; 0517
        JR nz,L_051d                     ; 0519
        LD (HL),0x20                     ; 051b

L_051d:
        INC HL                           ; 051d
        DEC BC                           ; 051e
        LD A,C                           ; 051f
        OR B                             ; 0520
        JR nz,L_0516                     ; 0521
        RET                              ; 0523

sub_0524:
        LD IX,0x43e4                     ; 0524
        LD BC,(STORE_SIZE)               ; 0528
        DEC BC                           ; 052c
        DEC BC                           ; 052d

L_052e:
        LD A,(IX+0)                      ; 052e
        CP 0xd0                          ; 0531
        JP c,L_0545                      ; 0533
        CP 0xdb                          ; 0536
        JP nc,L_0545                     ; 0538
        LD (IX-1),3                      ; 053b
        INC IX                           ; 053f
        DEC BC                           ; 0541
        LD A,C                           ; 0542
        OR B                             ; 0543
        RET z                            ; 0544

L_0545:
        INC IX                           ; 0545
        DEC BC                           ; 0547
        LD A,C                           ; 0548
        OR B                             ; 0549
        JR nz,L_052e                     ; 054a
        RET                              ; 054c

; ---- init_vars3: NMI_PER_SEC = 60 -> NMI is a 60 Hz (mains) tick
init_vars3:
        LD A,0x3c                        ; 054d
        LD (NMI_PER_SEC),A               ; 054f
        RET                              ; 0552

; ---- init_vars: Power-on RAM init: copies data blocks from ROM (0x0601..), validates MY_ADDRESS/MY_ADDRESS_INV (resets to 0 if corrupt)
init_vars:
        XOR A                            ; 0553
        LD (TINY_RENDER),A               ; 0554
        LD (ROW_PHASE),A                 ; 0557
        LD HL,MENU_ENTRY_BUF             ; 055a
        LD B,5                           ; 055d

L_055f:
        LD (HL),A                        ; 055f
        INC HL                           ; 0560
        DJNZ L_055f                      ; 0561
        LD (0x439b),A                    ; 0563
        LD (0x4360),A                    ; 0566
        LD (0x4364),A                    ; 0569
        LD (0x4213),A                    ; 056c
        LD (0x4361),A                    ; 056f
        LD (0x43a2),A                    ; 0572
        LD (MENU_TMP2),A                 ; 0575
        LD (MENU_TMP),A                  ; 0578
        LD (0x43a4),A                    ; 057b
        LD (0x439a),A                    ; 057e
        LD (0x4399),A                    ; 0581
        LD (0x4395),A                    ; 0584
        LD (0x4391),A                    ; 0587
        LD (0x43a3),A                    ; 058a
        LD (0x43d6),A                    ; 058d
        LD (0x43d7),A                    ; 0590
        LD (0x43cf),A                    ; 0593
        LD (0x43ca),A                    ; 0596
        LD (0x43cd),A                    ; 0599
        LD (BLANK_TIMER),A               ; 059c
        LD (TICK6_COUNT),A               ; 059f
        LD A,0xff                        ; 05a2
        LD (MENU_FLAG),A                 ; 05a4
        LD A,0x20                        ; 05a7
        LD (MENU_CHAR),A                 ; 05a9
        LD A,(NMI_COUNT)                 ; 05ac
        LD (RND_SEED),A                  ; 05af
        AND 3                            ; 05b2
        ADD A,3                          ; 05b4
        LD (RND_VAL),A                   ; 05b6
        LD A,(MY_ADDRESS)                ; 05b9
        LD C,A                           ; 05bc
        LD A,(MY_ADDRESS_INV)            ; 05bd
        CPL                              ; 05c0
        CP C                             ; 05c1
        JR z,L_05cc                      ; 05c2
        ; MY_ADDRESS_INV is MY_ADDRESS+1, so one 16-bit store does both:
        ; L=0x01 -> address 1 (NETCC's default), H=0xFE -> its complement.
        LD HL,0xfe01                     ; 05c4
        LD (MY_ADDRESS),HL               ; 05c7
        NOP                              ; 05ca
        NOP                              ; 05cb

L_05cc:
        LD HL,INIT_DATA                  ; 05cc
        LD BC,10                         ; 05cf
        LD DE,FB_COLPTR                  ; 05d2
        LDIR                             ; 05d5
        LD HL,0x060b                     ; 05d7
        LD DE,EFFECT_TMP                 ; 05da
        LD BC,8                          ; 05dd
        LDIR                             ; 05e0
        LD HL,0x0619                     ; 05e2
        LD DE,CLK_RUN                    ; 05e5
        LD BC,0x5a                       ; 05e8
        LDIR                             ; 05eb
        LD HL,0x0674                     ; 05ed
        LD DE,0x4336                     ; 05f0
        LD BC,0x24                       ; 05f3
        LDIR                             ; 05f6
        IM 1                             ; 05f8
        LD HL,SEQ_LIST                   ; 05fa
        LD (SEQ_PTR),HL                  ; 05fd
        RET                              ; 0600

; ---- data 0601-0697: RAM initialisation blocks copied by init_vars
INIT_DATA:
        db 0x96,0x40,0x56,0x40,0x40,0x95,0x40,0x01,0x01,0x00,0xa2,0x41,0x56,0x00,0x00,0x00   ; 0601
        db 0x00,0x00,0x01,0x02,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x0f,0x00   ; 0611
        db 0x00,0x00,0x40,0x40,0x01,0x05,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x0f,0x00   ; 0621
        db 0x00,0x0a,0x00,0x00,0x00,0x0f,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; 0631
        db 0x00,0x00,0x00,0x56,0x00,0x00,0x00,0xff,0x5f,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; 0641
        db 0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; 0651
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x4a,0x16,0x4a,0x16,0x00,0x00,0x2b   ; 0661
        db 0x16,0x2b,0x16,0x00,0x00,0x00,0x00,0x00,0x00,0xb0,0x04,0x00,0x00,0x00,0x00,0x00   ; 0671
        db 0x00,0x00,0x00,0xe2,0x43,0x00,0x01,0x00,0x00,0x00,0x00,0x54,0x16,0x00,0x01,0x00   ; 0681
        db 0x00,0x00,0x00,0x54,0x16,0xff,0xff   ; 0691

; ---- init_render: Reset render state for the current message
init_render:
        CALL clear_framebuf              ; 0698
        XOR A                            ; 069b
        LD (0x439b),A                    ; 069c
        LD (0x4360),A                    ; 069f
        LD (TINY_RENDER),A               ; 06a2
        LD (ROW_PHASE),A                 ; 06a5
        LD A,0xff                        ; 06a8
        LD (EFFECT_ACTIVE),A             ; 06aa
        LD HL,FRAMEBUF                   ; 06ad
        LD (SEQ_PTR_SAVE),HL             ; 06b0
        LD (FB_COL),HL                   ; 06b3
        LD HL,0                          ; 06b6
        LD (FB_EXTRA_LEN),HL             ; 06b9
        LD HL,0x56                       ; 06bc
        LD (DISP_FLAGS),HL               ; 06bf
        LD A,1                           ; 06c2
        LD (0x438c),A                    ; 06c4
        XOR A                            ; 06c7
        LD (RENDER_DONE),A               ; 06c8
        LD (EFFECT_PHASE),A              ; 06cb
        LD (0x4213),A                    ; 06ce
        LD (RENDER_DONE),A               ; 06d1
        LD (0x421e),A                    ; 06d4
        LD (MENU_TMP),A                  ; 06d7
        LD (0x439a),A                    ; 06da
        LD (MENU_TMP2),A                 ; 06dd
        LD (RND_VAL),A                   ; 06e0
        LD (PAUSE_FLAG),A                ; 06e3
        LD (0x4244),A                    ; 06e6
        LD (0x43a2),A                    ; 06e9
        LD (0x43a3),A                    ; 06ec
        LD (0x43a4),A                    ; 06ef
        LD (0x43cd),A                    ; 06f2
        LD (0x433b),A                    ; 06f5
        LD (TINY_MODE),A                 ; 06f8
        LD (FONT_MODE),A                 ; 06fb
        LD (0x43d6),A                    ; 06fe
        LD A,0x8f                        ; 0701
        LD (0x421b),A                    ; 0703
        LD (ROW_DATA_LATCH),A            ; 0706
        LD (CUR_COLOUR),A                ; 0709
        LD HL,fx_none                    ; 070c
        LD (EFFECT_VECTOR),HL            ; 070f
        LD HL,FRAMEBUF_ROW1              ; 0712
        LD (FB_COLPTR),HL                ; 0715
        LD HL,TXBUF                      ; 0718
        LD (EFFECT_TMP),HL               ; 071b
        CALL clear_txbuf                 ; 071e
        CALL clear_glyph_tmp             ; 0721
        LD HL,(STORE_LIMIT)              ; 0724
        LD (HL),0xda                     ; 0727
        RET                              ; 0729

sub_072a:
        LD A,(CUR_CHAR)                  ; 072a
        CP 0x20                          ; 072d
        JR z,L_0757                      ; 072f
        XOR A                            ; 0731
        LD (0x4338),A                    ; 0732
        LD A,(CUR_CHAR)                  ; 0735
        LD D,0                           ; 0738
        LD E,A                           ; 073a
        LD HL,0x372d                     ; 073b
        ADD HL,DE                        ; 073e
        BIT 1,(HL)                       ; 073f
        JR nz,L_0776                     ; 0741
        LD A,0xff                        ; 0743
        LD (0x43a3),A                    ; 0745
        LD A,(0x43a2)                    ; 0748
        AND A                            ; 074b
        JR z,L_0776                      ; 074c
        LD (0x421e),A                    ; 074e
        XOR A                            ; 0751
        LD (0x43a2),A                    ; 0752
        JR L_0776                        ; 0755

L_0757:
        XOR A                            ; 0757
        LD (0x421e),A                    ; 0758
        LD A,(0x4338)                    ; 075b
        AND A                            ; 075e
        JR nz,L_0768                     ; 075f
        LD A,1                           ; 0761
        LD (0x4338),A                    ; 0763
        JR L_0776                        ; 0766

L_0768:
        LD A,(0x420f)                    ; 0768
        INC A                            ; 076b
        JR z,L_0776                      ; 076c
        LD A,(CUR_COLOUR)                ; 076e
        AND 15                           ; 0771
        LD (CUR_COLOUR),A                ; 0773

L_0776:
        RET                              ; 0776

; ---- render_next_char: Fetch next byte from the message store at STORE_CURSOR and act on it: attribute bytes are dispatched, printable bytes are drawn via glyph_lookup
render_next_char:
        CALL sub_0968                    ; 0777

sub_077a:
        CALL sub_072a                    ; 077a
        CALL sub_0b14                    ; 077d
        CALL sub_0996                    ; 0780
        CALL sub_0a60                    ; 0783
        CALL sub_0a53                    ; 0786
        CALL sub_0a17                    ; 0789
        CALL sub_09fe                    ; 078c
        CALL sub_098c                    ; 078f
        CP 0xbe                          ; 0792
        JP z,attr_tiny                   ; 0794
        AND 0xf0                         ; 0797
        CP 0xa0                          ; 0799
        JR nz,L_07a7                     ; 079b
        LD A,(CUR_CHAR)                  ; 079d
        AND 15                           ; 07a0
        LD (CUR_CHAR),A                  ; 07a2
        JR glyph_lookup                  ; 07a5

L_07a7:
        LD A,(CUR_CHAR)                  ; 07a7
        CP 0x17                          ; 07aa
        JR z,glyph_lookup                ; 07ac
        BIT 7,A                          ; 07ae
        JP nz,L_07c5                     ; 07b0
        AND 0x60                         ; 07b3
        JP z,L_0ea8                      ; 07b5
        LD A,(CUR_CHAR)                  ; 07b8
        CP 0x5f                          ; 07bb
        JP z,L_1d90                      ; 07bd
        BIT 7,A                          ; 07c0
        JP z,glyph_lookup                ; 07c2

L_07c5:
        CP 0x94                          ; 07c5
        JP c,attr_colour_speed           ; 07c7
        CP 0xa0                          ; 07ca
        JR c,glyph_lookup                ; 07cc
        AND 0xf0                         ; 07ce
        CP 0xc0                          ; 07d0
        JR z,glyph_lookup                ; 07d2
        CP 0xe0                          ; 07d4
        JR z,glyph_lookup                ; 07d6
        CP 0xd0                          ; 07d8
        JP nz,attr_colour_speed          ; 07da

; ---- glyph_lookup: HL = FONT + 8*glyph_index(CUR_CHAR); GLYPH_WIDTH = byte 7 of the glyph
glyph_lookup:
        LD HL,FONT                       ; 07dd
        LD A,(CUR_CHAR)                  ; 07e0
        CALL char_to_glyph               ; 07e3
        LD E,A                           ; 07e6
        LD D,0                           ; 07e7
        SLA E                            ; 07e9
        RL D                             ; 07eb
        SLA E                            ; 07ed
        RL D                             ; 07ef
        SLA E                            ; 07f1
        RL D                             ; 07f3
        ADD HL,DE                        ; 07f5
        LD (GLYPH_PTR),HL                ; 07f6
        LD (GLYPH_PTR2),HL               ; 07f9
        LD DE,7                          ; 07fc
        ADD HL,DE                        ; 07ff
        LD A,(HL)                        ; 0800
        LD (GLYPH_WIDTH),A               ; 0801
        CALL clear_glyph_tmp             ; 0804
        LD A,(TINY_MODE)                 ; 0807
        AND A                            ; 080a
        JR nz,L_085c                     ; 080b
        CALL draw_glyph                  ; 080d
        CALL sub_0de3                    ; 0810
        CALL sub_0d97                    ; 0813
        LD A,(0x4213)                    ; 0816
        CP 0xff                          ; 0819
        JR nz,L_0826                     ; 081b
        XOR A                            ; 081d
        LD (0x4213),A                    ; 081e
        LD A,0xff                        ; 0821
        LD (0x4361),A                    ; 0823

L_0826:
        LD A,(CUR_CHAR)                  ; 0826
        AND 0xf0                         ; 0829
        JR nz,L_085c                     ; 082b
        LD HL,(GLYPH_PTR)                ; 082d
        LD DE,(GLYPH_PTR2)               ; 0830
        OR A                             ; 0834
        SBC HL,DE                        ; 0835
        JR nz,L_084d                     ; 0837
        LD HL,(GLYPH_PTR)                ; 0839
        LD A,(GLYPH_WIDTH)               ; 083c
        LD C,A                           ; 083f
        LD B,0                           ; 0840
        LD DE,0x42d6                     ; 0842
        LDIR                             ; 0845
        LD HL,0x42d6                     ; 0847
        LD (GLYPH_PTR),HL                ; 084a

L_084d:
        LD A,(GLYPH_WIDTH)               ; 084d
        SLA A                            ; 0850
        CP 0x20                          ; 0852
        JP c,L_0859                      ; 0854
        LD A,0x1f                        ; 0857

L_0859:
        LD (GLYPH_WIDTH),A               ; 0859

L_085c:
        LD A,(MENU_ACTIVE)               ; 085c
        AND A                            ; 085f
        JR nz,L_0869                     ; 0860
        LD A,(PAUSE_FLAG)                ; 0862
        AND A                            ; 0865
        JP nz,L_08fc                     ; 0866

L_0869:
        LD A,0                           ; 0869
        LD (0x438c),A                    ; 086b

sub_086e:
        LD A,(RENDER_DONE)               ; 086e
        AND A                            ; 0871
        JR z,L_0887                      ; 0872
        LD A,(CUR_CHAR)                  ; 0874
        CP 0x20                          ; 0877
        JR nz,L_0887                     ; 0879
        LD DE,TBL_08F0                   ; 087b
        LD (GLYPH_PTR),DE                ; 087e
        LD A,9                           ; 0882
        LD (GLYPH_WIDTH),A               ; 0884

L_0887:
        LD DE,(GLYPH_PTR)                ; 0887
        LD HL,(FB_COLPTR)                ; 088b
        LD A,(GLYPH_WIDTH)               ; 088e
        LD B,A                           ; 0891
        LD A,(MENU_ACTIVE)               ; 0892
        AND A                            ; 0895
        JR z,L_08a5                      ; 0896
        LD A,15                          ; 0898
        LD (CUR_COLOUR),A                ; 089a
        LD A,(TINY_MODE)                 ; 089d
        AND A                            ; 08a0
        LD C,0                           ; 08a1
        JR nz,L_08b7                     ; 08a3

L_08a5:
        LD A,(0x4391)                    ; 08a5
        AND A                            ; 08a8
        JR z,L_08b3                      ; 08a9
        XOR A                            ; 08ab
        LD (0x4391),A                    ; 08ac
        LD A,0x10                        ; 08af
        JR L_08b6                        ; 08b1

L_08b3:
        LD A,(0x421e)                    ; 08b3

L_08b6:
        LD C,A                           ; 08b6

L_08b7:
        PUSH BC                          ; 08b7
        LD A,(CUR_CHAR)                  ; 08b8
        CP 0x20                          ; 08bb
        LD C,0xf0                        ; 08bd
        JR z,L_08c3                      ; 08bf
        LD C,0xff                        ; 08c1

L_08c3:
        LD A,(CUR_COLOUR)                ; 08c3
        AND C                            ; 08c6
        POP BC                           ; 08c7
        OR C                             ; 08c8
        SET 7,A                          ; 08c9
        LD (HL),A                        ; 08cb
        LD A,(0x439b)                    ; 08cc
        AND A                            ; 08cf
        CALL z,sub_0e16                  ; 08d0
        XOR A                            ; 08d3
        LD (0x439b),A                    ; 08d4

L_08d7:
        LD A,(DE)                        ; 08d7
        LD (HL),A                        ; 08d8
        INC DE                           ; 08d9
        CALL sub_0e16                    ; 08da
        DJNZ L_08d7                      ; 08dd
        LD (FB_COLPTR),HL                ; 08df
        LD A,(MENU_ACTIVE)               ; 08e2
        AND A                            ; 08e5
        LD A,0                           ; 08e6
        JR nz,L_08ec                     ; 08e8
        LD A,0xff                        ; 08ea

L_08ec:
        LD (EFFECT_PHASE),A              ; 08ec
        RET                              ; 08ef

; ---- data 08f0-08fb: 
TBL_08F0:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; 08f0

L_08fc:
        LD HL,(EFFECT_TMP)               ; 08fc
        LD A,(GLYPH_WIDTH)               ; 08ff
        LD D,0                           ; 0902
        LD E,A                           ; 0904
        ADD HL,DE                        ; 0905
        LD DE,EFFECT_TMP                 ; 0906
        XOR A                            ; 0909
        SBC HL,DE                        ; 090a
        JP nc,L_0efc                     ; 090c
        LD DE,(EFFECT_TMP)               ; 090f
        LD A,(0x421e)                    ; 0913
        OR 0x8f                          ; 0916
        LD (DE),A                        ; 0918
        LD A,(0x439b)                    ; 0919
        AND A                            ; 091c
        LD A,0                           ; 091d
        LD (0x439b),A                    ; 091f
        JR nz,L_0925                     ; 0922
        INC DE                           ; 0924

L_0925:
        LD HL,(GLYPH_PTR)                ; 0925
        LD A,(GLYPH_WIDTH)               ; 0928
        LD B,0                           ; 092b
        LD C,A                           ; 092d
        LDIR                             ; 092e
        LD (EFFECT_TMP),DE               ; 0930
        JP render_next_char              ; 0934

L_0937:
        SRL H                            ; 0937
        RR L                             ; 0939
        LD (EFFECT_TMP2),HL              ; 093b
        CALL sub_0cea                    ; 093e
        RET                              ; 0941

; ---- char_to_glyph: Map a character code to a font glyph index (tables at 0x382d..0x392d select upper/lower/tiny fonts)
char_to_glyph:
        PUSH AF                          ; 0942
        AND 0xf0                         ; 0943
        CP 0xc0                          ; 0945
        LD DE,0x3535                     ; 0947
        JR z,L_0963                      ; 094a
        CP 0xd0                          ; 094c
        LD DE,0x36ad                     ; 094e
        JR z,L_0963                      ; 0951
        CP 0xe0                          ; 0953
        LD DE,0x35b5                     ; 0955
        JR z,L_0963                      ; 0958
        CP 0x90                          ; 095a
        LD DE,0x3635                     ; 095c
        JR z,L_0963                      ; 095f
        POP AF                           ; 0961
        RET                              ; 0962

L_0963:
        POP AF                           ; 0963
        AND 15                           ; 0964
        EX DE,HL                         ; 0966
        RET                              ; 0967

sub_0968:
        PUSH HL                          ; 0968
        PUSH AF                          ; 0969
        LD HL,(STORE_CURSOR)             ; 096a
        LD A,(PAUSE_FLAG)                ; 096d
        AND A                            ; 0970
        JR z,L_097d                      ; 0971
        LD A,(0x4361)                    ; 0973
        AND A                            ; 0976
        JR z,L_097d                      ; 0977
        LD A,0x18                        ; 0979
        JR L_097e                        ; 097b

L_097d:
        LD A,(HL)                        ; 097d

L_097e:
        INC HL                           ; 097e
        LD (STORE_CURSOR),HL             ; 097f
        LD (CUR_CHAR),A                  ; 0982
        XOR A                            ; 0985
        LD (0x4361),A                    ; 0986
        POP AF                           ; 0989
        POP HL                           ; 098a
        RET                              ; 098b

sub_098c:
        LD A,(CUR_CHAR)                  ; 098c
        CP 0xbb                          ; 098f
        RET nz                           ; 0991
        POP HL                           ; 0992
        JP L_0ef1                        ; 0993

sub_0996:
        LD A,(CUR_CHAR)                  ; 0996
        CP 0xbc                          ; 0999
        JR nz,L_09b5                     ; 099b
        LD A,(RENDER_DONE)               ; 099d
        AND A                            ; 09a0
        JR z,L_09a9                      ; 09a1
        LD A,(0x09f7)                    ; 09a3
        LD (CUR_COLOUR),A                ; 09a6

L_09a9:
        LD A,1                           ; 09a9
        LD (0x43a4),A                    ; 09ab
        LD (MENU_TMP),A                  ; 09ae
        POP HL                           ; 09b1
        JP render_next_char              ; 09b2

L_09b5:
        LD A,(0x43a4)                    ; 09b5
        AND A                            ; 09b8
        LD A,(CUR_CHAR)                  ; 09b9
        RET z                            ; 09bc
        CP 0x20                          ; 09bd
        RET z                            ; 09bf
        LD D,0                           ; 09c0
        LD E,A                           ; 09c2
        LD IX,0x372d                     ; 09c3
        ADD IX,DE                        ; 09c7
        BIT 1,(IX+0)                     ; 09c9
        RET nz                           ; 09cd
        LD A,(0x43a4)                    ; 09ce
        INC A                            ; 09d1
        AND 7                            ; 09d2
        JR nz,L_09d8                     ; 09d4
        LD A,1                           ; 09d6

L_09d8:
        LD E,A                           ; 09d8
        LD D,0                           ; 09d9
        LD HL,TBL_09F6                   ; 09db
        ADD HL,DE                        ; 09de
        LD A,(HL)                        ; 09df
        CP 0xff                          ; 09e0
        JR nz,L_09e9                     ; 09e2
        LD E,1                           ; 09e4
        LD A,(0x09f7)                    ; 09e6

L_09e9:
        AND 15                           ; 09e9
        LD (CUR_COLOUR),A                ; 09eb
        LD A,E                           ; 09ee
        LD (0x43a4),A                    ; 09ef
        LD A,(CUR_CHAR)                  ; 09f2
        RET                              ; 09f5

; ---- data 09f6-09fd: 
TBL_09F6:
        db 0x00,0x8c,0x8d,0x8f,0x87,0x83,0xff,0xff   ; 09f6

sub_09fe:
        LD A,(CUR_CHAR)                  ; 09fe
        CP 0xb0                          ; 0a01
        RET nz                           ; 0a03

L_0a04:
        CALL sub_0968                    ; 0a04
        LD A,(CUR_CHAR)                  ; 0a07

; ---- attr_remark: 0xB0: skip text until the next 0xB0 (hidden remark)
attr_remark:
        CP 0xb0                          ; 0a0a
        JR z,L_0a13                      ; 0a0c
        CP 3                             ; 0a0e
        RET z                            ; 0a10
        JR L_0a04                        ; 0a11

L_0a13:
        POP HL                           ; 0a13
        JP render_next_char              ; 0a14

sub_0a17:
        LD A,(CUR_CHAR)                  ; 0a17
        CP 0xba                          ; 0a1a
        RET nz                           ; 0a1c
        LD A,(COL_COUNT)                 ; 0a1d
        AND A                            ; 0a20
        JR z,L_0a34                      ; 0a21
        LD HL,(EFFECT_TMP)               ; 0a23
        LD DE,TXBUF                      ; 0a26
        XOR A                            ; 0a29
        SBC HL,DE                        ; 0a2a
        JR z,L_0a34                      ; 0a2c
        LD A,0x18                        ; 0a2e
        LD (CUR_CHAR),A                  ; 0a30
        RET                              ; 0a33

L_0a34:
        CALL sub_1062                    ; 0a34
        XOR A                            ; 0a37
        LD (RX_BYTE),A                   ; 0a38
        LD (IR_CODE),A                   ; 0a3b

L_0a3e:
        LD A,(RX_BYTE)                   ; 0a3e
        CP 0x20                          ; 0a41
        JR nz,L_0a49                     ; 0a43
        POP HL                           ; 0a45
        JP render_next_char              ; 0a46

L_0a49:
        LD A,(PKT_READY)                 ; 0a49
        AND A                            ; 0a4c
        JP nz,pkt_process                ; 0a4d
        JP L_0a3e                        ; 0a50

sub_0a53:
        LD A,(CUR_CHAR)                  ; 0a53
        CP 0xb9                          ; 0a56
        RET nz                           ; 0a58
        LD (0x43d6),A                    ; 0a59
        POP HL                           ; 0a5c
        JP render_next_char              ; 0a5d

sub_0a60:
        LD A,(CUR_CHAR)                  ; 0a60

; ---- attr_graphic: 0xB8: user-drawn graphic follows
attr_graphic:
        CP 0xb8                          ; 0a63
        JR z,L_0a70                      ; 0a65
        LD A,0                           ; 0a67
        LD (0x4360),A                    ; 0a69
        LD A,(CUR_CHAR)                  ; 0a6c
        RET                              ; 0a6f

L_0a70:
        LD A,(0x4360)                    ; 0a70
        LD (0x439b),A                    ; 0a73
        LD A,0xff                        ; 0a76
        LD (0x4360),A                    ; 0a78
        LD HL,0x4365                     ; 0a7b
        PUSH HL                          ; 0a7e
        PUSH HL                          ; 0a7f
        LD B,0x10                        ; 0a80

L_0a82:
        LD (HL),0                        ; 0a82
        INC HL                           ; 0a84
        DJNZ L_0a82                      ; 0a85
        CALL clear_glyph_tmp             ; 0a87
        POP HL                           ; 0a8a
        LD C,0                           ; 0a8b
        LD B,0x10                        ; 0a8d

L_0a8f:
        CALL sub_0968                    ; 0a8f
        LD A,(CUR_CHAR)                  ; 0a92
        CALL sub_0af4                    ; 0a95
        CP 0xff                          ; 0a98
        JR z,L_0ae2                      ; 0a9a
        PUSH AF                          ; 0a9c
        CALL sub_0968                    ; 0a9d
        LD A,(CUR_CHAR)                  ; 0aa0
        CALL sub_0af4                    ; 0aa3
        CP 0xff                          ; 0aa6
        JR z,L_0ae1                      ; 0aa8
        RRD                              ; 0aaa
        POP AF                           ; 0aac
        RRD                              ; 0aad
        INC HL                           ; 0aaf
        INC C                            ; 0ab0
        DJNZ L_0a8f                      ; 0ab1

L_0ab3:
        POP HL                           ; 0ab3
        LD (GLYPH_PTR),HL                ; 0ab4
        LD (GLYPH_PTR2),HL               ; 0ab7
        LD A,C                           ; 0aba
        AND A                            ; 0abb
        JP nz,L_0ac9                     ; 0abc
        XOR A                            ; 0abf
        LD (0x439b),A                    ; 0ac0
        LD A,0x20                        ; 0ac3
        LD (CUR_CHAR),A                  ; 0ac5
        RET                              ; 0ac8

L_0ac9:
        LD (GLYPH_WIDTH),A               ; 0ac9
        POP HL                           ; 0acc
        LD A,(PAUSE_FLAG)                ; 0acd
        AND A                            ; 0ad0
        JP z,L_085c                      ; 0ad1
        CALL draw_glyph                  ; 0ad4
        LD A,(GLYPH_WIDTH)               ; 0ad7
        DEC A                            ; 0ada
        LD (GLYPH_WIDTH),A               ; 0adb
        JP L_085c                        ; 0ade

L_0ae1:
        POP AF                           ; 0ae1

L_0ae2:
        LD A,(CUR_CHAR)                  ; 0ae2
        CP 3                             ; 0ae5
        JR nz,L_0aec                     ; 0ae7
        CALL sub_0cea                    ; 0ae9

L_0aec:
        LD A,0x2a                        ; 0aec
        LD (CUR_CHAR),A                  ; 0aee
        JP L_0ab3                        ; 0af1

sub_0af4:
        CP 0x30                          ; 0af4
        JP c,L_0b11                      ; 0af6
        CP 0x3a                          ; 0af9
        JP c,L_0b0e                      ; 0afb
        AND 0xdf                         ; 0afe
        CP 0x41                          ; 0b00
        JP c,L_0b11                      ; 0b02
        CP 0x47                          ; 0b05
        JP nc,L_0b11                     ; 0b07
        AND 15                           ; 0b0a
        ADD A,9                          ; 0b0c

L_0b0e:
        AND 15                           ; 0b0e
        RET                              ; 0b10

L_0b11:
        LD A,0xff                        ; 0b11
        RET                              ; 0b13

sub_0b14:
        LD A,(MENU_ACTIVE)               ; 0b14
        AND A                            ; 0b17
        RET nz                           ; 0b18
        LD A,(RENDER_DONE)               ; 0b19
        AND A                            ; 0b1c
        RET z                            ; 0b1d
        LD A,(PAUSE_FLAG)                ; 0b1e
        AND A                            ; 0b21
        JR z,L_0b2e                      ; 0b22
        LD A,(CUR_CHAR)                  ; 0b24
        CP 0x20                          ; 0b27
        RET nz                           ; 0b29
        POP HL                           ; 0b2a
        JP L_0efc                        ; 0b2b

L_0b2e:
        LD A,(CUR_CHAR)                  ; 0b2e
        CP 0x20                          ; 0b31
        JR nz,L_0b62                     ; 0b33
        LD HL,0x4395                     ; 0b35
        INC (HL)                         ; 0b38
        LD A,2                           ; 0b39
        LD (FONT_MODE),A                 ; 0b3b
        LD A,(MENU_CHAR)                 ; 0b3e
        CP 0x2e                          ; 0b41
        JP z,L_0c68                      ; 0b43
        CP 0x21                          ; 0b46
        JP z,L_0c68                      ; 0b48
        CP 0x3f                          ; 0b4b
        JP z,L_0c68                      ; 0b4d
        CP 0x3a                          ; 0b50
        JP z,L_0c68                      ; 0b52
        CP 0x2c                          ; 0b55
        JP z,L_0c68                      ; 0b57
        LD A,0x20                        ; 0b5a
        LD (MENU_CHAR),A                 ; 0b5c
        JP L_0cd3                        ; 0b5f

L_0b62:
        CP 0xbb                          ; 0b62
        JR z,L_0b72                      ; 0b64
        CP 15                            ; 0b66
        JR z,L_0b72                      ; 0b68
        CP 0x19                          ; 0b6a
        JR c,L_0bb7                      ; 0b6c
        CP 0x1c                          ; 0b6e
        JR nc,L_0bb7                     ; 0b70

L_0b72:
        XOR A                            ; 0b72
        LD (MENU_TMP2),A                 ; 0b73
        LD (MENU_TMP),A                  ; 0b76
        LD A,(0x4390)                    ; 0b79
        AND A                            ; 0b7c
        RET nz                           ; 0b7d
        LD A,0xff                        ; 0b7e
        LD (0x4390),A                    ; 0b80
        LD A,(0x43a3)                    ; 0b83
        AND A                            ; 0b86
        RET z                            ; 0b87
        LD A,(CUR_CHAR)                  ; 0b88
        PUSH AF                          ; 0b8b
        LD B,14                          ; 0b8c

L_0b8e:
        PUSH BC                          ; 0b8e
        LD A,0x20                        ; 0b8f
        LD (CUR_CHAR),A                  ; 0b91
        XOR A                            ; 0b94
        LD (PAUSE_FLAG),A                ; 0b95
        LD HL,fx_none                    ; 0b98
        LD (EFFECT_VECTOR),HL            ; 0b9b
        LD A,6                           ; 0b9e
        LD (GLYPH_WIDTH),A               ; 0ba0
        LD HL,0x3235                     ; 0ba3
        LD (GLYPH_PTR),HL                ; 0ba6
        CALL sub_086e                    ; 0ba9
        CALL effect_step                 ; 0bac
        POP BC                           ; 0baf
        DJNZ L_0b8e                      ; 0bb0
        POP AF                           ; 0bb2
        LD (CUR_CHAR),A                  ; 0bb3
        RET                              ; 0bb6

L_0bb7:
        XOR A                            ; 0bb7
        LD (0x4390),A                    ; 0bb8
        LD A,(CUR_CHAR)                  ; 0bbb
        CP 0xb8                          ; 0bbe
        JP z,L_0bd4                      ; 0bc0
        AND 0xf0                         ; 0bc3
        CP 0xa0                          ; 0bc5
        JP z,L_0bd4                      ; 0bc7
        CP 0x20                          ; 0bca
        JP c,L_0cd3                      ; 0bcc
        CP 0x80                          ; 0bcf
        JP nc,L_0cd3                     ; 0bd1

L_0bd4:
        LD A,(MENU_CHAR)                 ; 0bd4
        CP 0x20                          ; 0bd7
        JR z,L_0be4                      ; 0bd9
        LD A,(CUR_CHAR)                  ; 0bdb
        LD (MENU_CHAR),A                 ; 0bde
        JP L_0cd3                        ; 0be1

L_0be4:
        LD A,(CUR_CHAR)                  ; 0be4
        LD (MENU_CHAR),A                 ; 0be7
        CP 0x24                          ; 0bea
        JR nz,L_0bf1                     ; 0bec
        LD (0x4391),A                    ; 0bee

L_0bf1:
        AND 0xf0                         ; 0bf1
        CP 0xa0                          ; 0bf3
        JP z,L_0c73                      ; 0bf5
        LD A,(MENU_TMP2)                 ; 0bf8
        AND A                            ; 0bfb
        LD A,0                           ; 0bfc
        LD (MENU_TMP2),A                 ; 0bfe
        JR nz,L_0c42                     ; 0c01
        LD B,8                           ; 0c03
        LD HL,(STORE_CURSOR)             ; 0c05

L_0c08:
        LD A,(HL)                        ; 0c08
        AND 0x5f                         ; 0c09
        CP 0x41                          ; 0c0b
        JP c,L_0c1b                      ; 0c0d
        CP 0x5b                          ; 0c10
        JP nc,L_0c1b                     ; 0c12
        INC HL                           ; 0c15
        DJNZ L_0c08                      ; 0c16
        JP L_0c3e                        ; 0c18

L_0c1b:
        LD A,B                           ; 0c1b
        CP 6                             ; 0c1c
        JP nc,L_0c3e                     ; 0c1e
        LD A,(RND_SEED)                  ; 0c21
        ADD A,(HL)                       ; 0c24
        LD HL,(NMI_COUNT)                ; 0c25
        ADD A,(HL)                       ; 0c28
        LD (RND_SEED),A                  ; 0c29
        AND 3                            ; 0c2c
        JR z,L_0c37                      ; 0c2e
        LD HL,FONT_MODE                  ; 0c30
        LD (HL),2                        ; 0c33
        JR L_0c42                        ; 0c35

L_0c37:
        LD HL,FONT_MODE                  ; 0c37
        LD (HL),6                        ; 0c3a
        JR L_0c42                        ; 0c3c

L_0c3e:
        XOR A                            ; 0c3e
        LD (FONT_MODE),A                 ; 0c3f

L_0c42:
        LD A,(0x4395)                    ; 0c42
        CP 3                             ; 0c45
        JP nc,L_0c73                     ; 0c47
        LD A,(RND_VAL)                   ; 0c4a
        AND A                            ; 0c4d
        JP z,L_0c68                      ; 0c4e
        DEC A                            ; 0c51
        JP z,L_0c68                      ; 0c52
        LD (RND_VAL),A                   ; 0c55
        LD A,(MENU_TMP)                  ; 0c58
        AND A                            ; 0c5b
        JR z,L_0ccf                      ; 0c5c
        XOR A                            ; 0c5e
        LD (MENU_TMP),A                  ; 0c5f
        LD (RND_VAL),A                   ; 0c62
        JP L_0ccf                        ; 0c65

L_0c68:
        LD A,(NMI_COUNT)                 ; 0c68
        LD E,A                           ; 0c6b
        AND 3                            ; 0c6c
        ADD A,2                          ; 0c6e
        LD (RND_VAL),A                   ; 0c70

L_0c73:
        LD A,(MENU_TMP)                  ; 0c73
        AND A                            ; 0c76
        JR z,L_0c83                      ; 0c77
        XOR A                            ; 0c79
        LD (MENU_TMP),A                  ; 0c7a
        LD (RND_VAL),A                   ; 0c7d
        JP L_0ccf                        ; 0c80

L_0c83:
        XOR A                            ; 0c83
        LD (0x43a4),A                    ; 0c84
        LD A,(0x4362)                    ; 0c87
        INC A                            ; 0c8a
        LD E,A                           ; 0c8b
        LD A,(NMI_COUNT)                 ; 0c8c
        ADD A,E                          ; 0c8f

L_0c90:
        AND 15                           ; 0c90
        LD (0x4362),A                    ; 0c92
        LD E,A                           ; 0c95
        LD D,0                           ; 0c96
        LD HL,0x0cda                     ; 0c98
        ADD HL,DE                        ; 0c9b
        LD A,(CUR_COLOUR)                ; 0c9c
        AND 15                           ; 0c9f
        CP (HL)                          ; 0ca1
        JR z,L_0cc0                      ; 0ca2
        LD A,(CUR_COLOUR)                ; 0ca4
        LD E,A                           ; 0ca7
        LD D,(HL)                        ; 0ca8
        LD A,D                           ; 0ca9
        LD HL,CUR_COLOUR                 ; 0caa
        RLD                              ; 0cad
        LD A,(HL)                        ; 0caf
        LD HL,TBL_0CD4                   ; 0cb0
        LD BC,6                          ; 0cb3
        OR A                             ; 0cb6
        CPIR                             ; 0cb7
        JP nz,L_0cc6                     ; 0cb9
        LD A,E                           ; 0cbc
        LD (CUR_COLOUR),A                ; 0cbd

L_0cc0:
        LD A,(0x4362)                    ; 0cc0
        INC A                            ; 0cc3
        JR L_0c90                        ; 0cc4

L_0cc6:
        LD A,E                           ; 0cc6
        AND 0x10                         ; 0cc7
        OR D                             ; 0cc9
        AND 0x1f                         ; 0cca
        LD (CUR_COLOUR),A                ; 0ccc

L_0ccf:
        XOR A                            ; 0ccf
        LD (0x4395),A                    ; 0cd0

L_0cd3:
        RET                              ; 0cd3

; ---- data 0cd4-0ce9: 
TBL_0CD4:
        db 0xf7,0x7f,0xfd,0xdf,0xcd,0xdc,0x07,0x0c,0x0f,0x03,0x0c,0x03,0x0d,0x03,0x0f,0x03   ; 0cd4
        db 0x0c,0x03,0x03,0x0c,0x0f,0x0c   ; 0ce4

sub_0cea:
        LD HL,(STORE_CURSOR)             ; 0cea
        LD DE,MSG_STORE                  ; 0ced
        OR A                             ; 0cf0
        SBC HL,DE                        ; 0cf1
        JR z,L_0cfc                      ; 0cf3
        LD HL,(STORE_CURSOR)             ; 0cf5
        DEC HL                           ; 0cf8
        LD (STORE_CURSOR),HL             ; 0cf9

L_0cfc:
        RET                              ; 0cfc

; ---- draw_glyph: Copy the glyph columns into FRAMEBUF at the current column
draw_glyph:
        LD A,(0x433b)                    ; 0cfd
        AND A                            ; 0d00
        JR nz,L_0d36                     ; 0d01
        LD A,(PAUSE_FLAG)                ; 0d03
        AND A                            ; 0d06
        JR z,L_0d2f                      ; 0d07
        LD A,(0x43d6)                    ; 0d09
        AND A                            ; 0d0c
        JR z,L_0d36                      ; 0d0d
        LD A,(FONT_MODE)                 ; 0d0f
        AND 10                           ; 0d12
        JR nz,L_0d2f                     ; 0d14
        LD A,(GLYPH_WIDTH)               ; 0d16
        LD C,A                           ; 0d19
        LD B,0                           ; 0d1a
        INC A                            ; 0d1c
        LD (GLYPH_WIDTH),A               ; 0d1d
        LD HL,(GLYPH_PTR)                ; 0d20
        LD DE,0x42d6                     ; 0d23
        LDIR                             ; 0d26
        LD HL,0x42d6                     ; 0d28
        LD (GLYPH_PTR),HL                ; 0d2b
        RET                              ; 0d2e

L_0d2f:
        LD A,(FONT_MODE)                 ; 0d2f
        BIT 1,A                          ; 0d32
        JR z,L_0d96                      ; 0d34

L_0d36:
        LD A,(GLYPH_WIDTH)               ; 0d36
        LD B,A                           ; 0d39
        LD HL,(GLYPH_PTR)                ; 0d3a
        LD DE,0x42d6                     ; 0d3d
        LD C,0                           ; 0d40

L_0d42:
        LD A,(HL)                        ; 0d42
        LD (DE),A                        ; 0d43
        INC HL                           ; 0d44
        AND A                            ; 0d45
        JR z,L_0d4c                      ; 0d46
        OR (HL)                          ; 0d48
        INC DE                           ; 0d49
        INC C                            ; 0d4a
        LD (DE),A                        ; 0d4b

L_0d4c:
        INC DE                           ; 0d4c
        INC C                            ; 0d4d
        DJNZ L_0d42                      ; 0d4e
        XOR A                            ; 0d50
        LD (DE),A                        ; 0d51
        LD A,C                           ; 0d52
        CP 2                             ; 0d53
        JR z,L_0d5b                      ; 0d55
        XOR A                            ; 0d57
        DEC DE                           ; 0d58
        LD (DE),A                        ; 0d59
        LD A,C                           ; 0d5a

L_0d5b:
        LD (GLYPH_WIDTH),A               ; 0d5b
        LD HL,0x42d6                     ; 0d5e
        LD (GLYPH_PTR),HL                ; 0d61
        LD IX,0x42d6                     ; 0d64
        LD B,4                           ; 0d68

L_0d6a:
        LD A,(IX+0)                      ; 0d6a
        CP 0x7f                          ; 0d6d
        JR nz,L_0d7f                     ; 0d6f
        LD A,(IX+1)                      ; 0d71
        CP 0x7f                          ; 0d74
        JR nz,L_0d7f                     ; 0d76
        LD A,(IX+2)                      ; 0d78
        CP 0x7f                          ; 0d7b
        JR z,L_0d84                      ; 0d7d

L_0d7f:
        INC IX                           ; 0d7f
        DJNZ L_0d6a                      ; 0d81
        RET                              ; 0d83

L_0d84:
        PUSH IX                          ; 0d84
        POP HL                           ; 0d86
        LD D,H                           ; 0d87
        LD E,L                           ; 0d88
        INC HL                           ; 0d89
        LD BC,0x1c                       ; 0d8a
        LDIR                             ; 0d8d
        LD A,(GLYPH_WIDTH)               ; 0d8f
        DEC A                            ; 0d92
        LD (GLYPH_WIDTH),A               ; 0d93

L_0d96:
        RET                              ; 0d96

sub_0d97:
        LD A,(FONT_MODE)                 ; 0d97
        BIT 2,A                          ; 0d9a
        JR z,L_0de2                      ; 0d9c
        LD HL,(GLYPH_PTR)                ; 0d9e
        LD A,(GLYPH_WIDTH)               ; 0da1
        LD C,A                           ; 0da4
        LD DE,0x42f6                     ; 0da5
        LD B,0                           ; 0da8
        LDIR                             ; 0daa
        LD B,A                           ; 0dac
        LD E,B                           ; 0dad
        LD D,0                           ; 0dae
        LD HL,0x42f6                     ; 0db0
        ADD HL,DE                        ; 0db3
        PUSH HL                          ; 0db4
        POP IX                           ; 0db5

L_0db7:
        LD A,(HL)                        ; 0db7
        AND 3                            ; 0db8
        OR (IX+2)                        ; 0dba
        LD (IX+2),A                      ; 0dbd
        LD A,(HL)                        ; 0dc0
        AND 12                           ; 0dc1
        OR (IX+1)                        ; 0dc3
        LD (IX+1),A                      ; 0dc6
        LD A,(HL)                        ; 0dc9
        AND 0xf0                         ; 0dca
        LD (HL),A                        ; 0dcc
        DEC HL                           ; 0dcd
        DEC IX                           ; 0dce
        DEC B                            ; 0dd0
        JP p,L_0db7                      ; 0dd1
        LD A,(GLYPH_WIDTH)               ; 0dd4
        INC A                            ; 0dd7
        INC A                            ; 0dd8
        LD (GLYPH_WIDTH),A               ; 0dd9
        LD HL,0x42f6                     ; 0ddc
        LD (GLYPH_PTR),HL                ; 0ddf

L_0de2:
        RET                              ; 0de2

sub_0de3:
        LD A,(FONT_MODE)                 ; 0de3
        BIT 3,A                          ; 0de6
        JR z,L_0e15                      ; 0de8
        LD A,(GLYPH_WIDTH)               ; 0dea
        LD B,A                           ; 0ded
        LD HL,(GLYPH_PTR)                ; 0dee
        LD DE,0x4316                     ; 0df1
        LD C,0                           ; 0df4

L_0df6:
        LD A,(HL)                        ; 0df6
        LD (DE),A                        ; 0df7
        INC HL                           ; 0df8
        AND A                            ; 0df9
        JR z,L_0e00                      ; 0dfa
        OR (HL)                          ; 0dfc
        INC DE                           ; 0dfd
        INC C                            ; 0dfe
        LD (DE),A                        ; 0dff

L_0e00:
        INC DE                           ; 0e00
        INC C                            ; 0e01
        DJNZ L_0df6                      ; 0e02
        XOR A                            ; 0e04
        LD (DE),A                        ; 0e05
        DEC DE                           ; 0e06
        LD (DE),A                        ; 0e07
        DEC DE                           ; 0e08
        LD (DE),A                        ; 0e09
        LD A,C                           ; 0e0a
        DEC A                            ; 0e0b
        LD (GLYPH_WIDTH),A               ; 0e0c
        LD HL,0x4316                     ; 0e0f
        LD (GLYPH_PTR),HL                ; 0e12

L_0e15:
        RET                              ; 0e15

sub_0e16:
        INC HL                           ; 0e16
        PUSH AF                          ; 0e17
        PUSH DE                          ; 0e18
        PUSH HL                          ; 0e19
        LD DE,FB_COLPTR                  ; 0e1a
        XOR A                            ; 0e1d
        SBC HL,DE                        ; 0e1e
        JP c,L_0e29                      ; 0e20
        LD HL,FRAMEBUF                   ; 0e23
        POP DE                           ; 0e26
        JR L_0e2a                        ; 0e27

L_0e29:
        POP HL                           ; 0e29

L_0e2a:
        POP DE                           ; 0e2a
        POP AF                           ; 0e2b
        RET                              ; 0e2c

sub_0e2d:
        PUSH AF                          ; 0e2d
        PUSH DE                          ; 0e2e
        ADD HL,DE                        ; 0e2f
        PUSH HL                          ; 0e30
        LD DE,FB_COLPTR                  ; 0e31
        XOR A                            ; 0e34
        SBC HL,DE                        ; 0e35
        JR c,L_0e40                      ; 0e37
        POP DE                           ; 0e39
        LD DE,FRAMEBUF                   ; 0e3a
        ADD HL,DE                        ; 0e3d
        JR L_0e41                        ; 0e3e

L_0e40:
        POP HL                           ; 0e40

L_0e41:
        POP DE                           ; 0e41
        POP AF                           ; 0e42
        RET                              ; 0e43

; ---- effect_step: Called from main loop: jump to EFFECT_VECTOR (current movement effect handler)
effect_step:
        LD A,(0x4244)                    ; 0e44
        AND A                            ; 0e47
        JR nz,effect_step                ; 0e48

L_0e4a:
        LD A,(EFFECT_PHASE)              ; 0e4a
        AND A                            ; 0e4d
        JR nz,L_0e4a                     ; 0e4e
        LD A,(PAUSE_FLAG)                ; 0e50
        AND A                            ; 0e53
        RET z                            ; 0e54

L_0e55:
        LD A,(ROW_INDEX)                 ; 0e55
        CP 6                             ; 0e58
        JR nz,L_0e55                     ; 0e5a
        LD HL,(EFFECT_TMP2)              ; 0e5c
        LD A,L                           ; 0e5f
        CP 0x2b                          ; 0e60
        JR z,L_0e68                      ; 0e62
        LD HL,(EFFECT_VECTOR)            ; 0e64
        JP (HL)                          ; 0e67

L_0e68:
        LD HL,0                          ; 0e68
        LD (EFFECT_TMP2),HL              ; 0e6b

L_0e6e:
        LD HL,(STORE_CURSOR)             ; 0e6e
        LD A,(HL)                        ; 0e71
        CP 0xba                          ; 0e72
        JR nz,L_0e7a                     ; 0e74
        XOR A                            ; 0e76
        LD (0x4244),A                    ; 0e77

L_0e7a:
        LD A,(PAUSE_FLAG)                ; 0e7a
        AND A                            ; 0e7d
        JR z,L_0e9b                      ; 0e7e
        LD A,(RENDER_DONE)               ; 0e80
        AND A                            ; 0e83
        JR z,L_0e8b                      ; 0e84
        LD A,15                          ; 0e86
        LD (CUR_COLOUR),A                ; 0e88

L_0e8b:
        LD A,(0x4242)                    ; 0e8b
        CPL                              ; 0e8e
        AND A                            ; 0e8f
        LD (0x4242),A                    ; 0e90
        JR z,L_0e9b                      ; 0e93
        XOR A                            ; 0e95
        LD (0x4242),A                    ; 0e96
        LD A,0x56                        ; 0e99

L_0e9b:
        LD (COL_COUNT),A                 ; 0e9b
        CALL clear_txbuf                 ; 0e9e
        LD HL,TXBUF                      ; 0ea1
        LD (EFFECT_TMP),HL               ; 0ea4
        RET                              ; 0ea7

L_0ea8:
        LD A,(CUR_CHAR)                  ; 0ea8

; ---- attr_dispatch: Attribute byte dispatcher: 11 normal,12 bold,13 italic,14 flash,10 large,1F magic,06 pause,07 beep,03 end,18 crawl,19 jump,1A wipe up,1B wipe down,0F wipe back,BB (extra effect)
attr_dispatch:
        CP 0x11                          ; 0eab
        JP nz,L_0eba                     ; 0ead
        XOR A                            ; 0eb0
        LD (0x421e),A                    ; 0eb1
        LD (FONT_MODE),A                 ; 0eb4
        JP L_0ee1                        ; 0eb7

L_0eba:
        CP 0x12                          ; 0eba
        JP nz,L_0ec4                     ; 0ebc
        LD A,2                           ; 0ebf
        JP L_0ee1                        ; 0ec1

L_0ec4:
        CP 0x13                          ; 0ec4
        JP nz,L_0ece                     ; 0ec6
        LD A,6                           ; 0ec9
        JP L_0ee1                        ; 0ecb

L_0ece:
        CP 0x14                          ; 0ece
        JP nz,L_0edb                     ; 0ed0
        LD A,0x10                        ; 0ed3
        LD (0x43a2),A                    ; 0ed5
        JP render_next_char              ; 0ed8

L_0edb:
        CP 0x10                          ; 0edb
        JR nz,L_0eec                     ; 0edd
        LD A,10                          ; 0edf

L_0ee1:
        LD (FONT_MODE),A                 ; 0ee1
        LD A,0xff                        ; 0ee4
        LD (MENU_TMP2),A                 ; 0ee6
        JP render_next_char              ; 0ee9

L_0eec:
        CP 0x1f                          ; 0eec
        JP z,fx_magic                    ; 0eee

L_0ef1:
        LD A,(COL_COUNT)                 ; 0ef1
        AND A                            ; 0ef4
        JR z,L_0f0f                      ; 0ef5
        LD A,0xff                        ; 0ef7
        LD (0x4242),A                    ; 0ef9

L_0efc:
        LD HL,(EFFECT_TMP)               ; 0efc
        LD DE,EFFECT_TMP                 ; 0eff
        XOR A                            ; 0f02
        EX DE,HL                         ; 0f03
        SBC HL,DE                        ; 0f04
        LD A,0x56                        ; 0f06
        SUB L                            ; 0f08
        LD (COL_COUNT),A                 ; 0f09
        JP L_0937                        ; 0f0c

L_0f0f:
        LD A,(CUR_CHAR)                  ; 0f0f
        CP 6                             ; 0f12
        JP z,fx_pause                    ; 0f14
        CP 7                             ; 0f17
        JP z,fx_beep                     ; 0f19
        CP 3                             ; 0f1c
        JP z,fx_end_of_channel           ; 0f1e
        CP 0x18                          ; 0f21
        JP z,fx_crawl                    ; 0f23
        CP 0x19                          ; 0f26
        JP z,fx_jump                     ; 0f28
        CP 0x1a                          ; 0f2b
        JP z,fx_wipe_up                  ; 0f2d
        CP 0x1b                          ; 0f30
        JP z,fx_wipe_down                ; 0f32
        CP 15                            ; 0f35
        JP z,fx_wipe_back                ; 0f37
        CP 0xbb                          ; 0f3a
        JP z,fx_BB                       ; 0f3c
        JP render_next_char              ; 0f3f

; ---- fx_beep
fx_beep:
        CALL sub_0f48                    ; 0f42
        JP render_next_char              ; 0f45

sub_0f48:
        PUSH HL                          ; 0f48
        LD HL,0x96                       ; 0f49
        LD (TICK_COUNTDOWN),HL           ; 0f4c
        POP HL                           ; 0f4f
        RET                              ; 0f50

; ---- fx_end_of_channel
fx_end_of_channel:
        LD HL,fx_none                    ; 0f51
        LD (EFFECT_VECTOR),HL            ; 0f54
        XOR A                            ; 0f57
        LD (PAUSE_FLAG),A                ; 0f58
        CALL demo_scroll                 ; 0f5b
        LD SP,STACK_TOP                  ; 0f5e
        JP main_loop                     ; 0f61

; ---- fx_wipe_back
fx_wipe_back:
        XOR A                            ; 0f64
        LD (EFFECT_PHASE),A              ; 0f65
        LD A,0x56                        ; 0f68
        LD (COL_COUNT),A                 ; 0f6a
        LD A,4                           ; 0f6d
        LD HL,fx_scroll_in               ; 0f6f
        JP set_effect_vector             ; 0f72

; ---- fx_crawl
fx_crawl:
        XOR A                            ; 0f75
        LD (COL_COUNT),A                 ; 0f76
        LD HL,fx_none                    ; 0f79
        JP set_effect_vector             ; 0f7c

; ---- fx_BB
fx_BB:
        XOR A                            ; 0f7f
        LD A,0x56                        ; 0f80
        LD (COL_COUNT),A                 ; 0f82
        LD A,5                           ; 0f85
        LD HL,fx_fill_frame              ; 0f87
        JP set_effect_vector             ; 0f8a

; ---- fx_jump
fx_jump:
        XOR A                            ; 0f8d
        LD (EFFECT_PHASE),A              ; 0f8e
        LD A,0x56                        ; 0f91
        LD (COL_COUNT),A                 ; 0f93
        LD A,1                           ; 0f96
        LD HL,fx_scroll_copy             ; 0f98
        JP set_effect_vector             ; 0f9b

; ---- fx_wipe_up
fx_wipe_up:
        XOR A                            ; 0f9e
        LD (EFFECT_PHASE),A              ; 0f9f
        LD A,0x56                        ; 0fa2
        LD (COL_COUNT),A                 ; 0fa4
        LD A,2                           ; 0fa7
        LD HL,fx_138b                    ; 0fa9
        JP set_effect_vector             ; 0fac

; ---- fx_wipe_down
fx_wipe_down:
        XOR A                            ; 0faf
        LD (EFFECT_PHASE),A              ; 0fb0
        LD A,0x56                        ; 0fb3
        LD (COL_COUNT),A                 ; 0fb5
        LD A,3                           ; 0fb8
        LD HL,fx_138b                    ; 0fba
        JP set_effect_vector             ; 0fbd

; ---- set_effect_vector: HL -> EFFECT_VECTOR, A -> effect id
set_effect_vector:
        LD (PAUSE_FLAG),A                ; 0fc0
        LD (0x438c),A                    ; 0fc3
        LD (EFFECT_VECTOR),HL            ; 0fc6
        JP render_next_char              ; 0fc9

; ---- fx_magic
fx_magic:
        XOR A                            ; 0fcc
        LD (0x43a2),A                    ; 0fcd
        LD (MENU_TMP),A                  ; 0fd0
        LD (MENU_TMP2),A                 ; 0fd3
        LD (0x43a4),A                    ; 0fd6
        LD (0x4390),A                    ; 0fd9
        LD A,0xff                        ; 0fdc
        LD (RENDER_DONE),A               ; 0fde
        LD A,0x20                        ; 0fe1
        LD (MENU_CHAR),A                 ; 0fe3
        LD A,1                           ; 0fe6
        LD (0x4395),A                    ; 0fe8
        LD A,(NMI_COUNT)                 ; 0feb
        LD E,A                           ; 0fee
        AND 3                            ; 0fef
        ADD A,2                          ; 0ff1
        LD (RND_VAL),A                   ; 0ff3
        CALL sub_0ffc                    ; 0ff6
        JP render_next_char              ; 0ff9

sub_0ffc:
        LD A,(MENU_ACTIVE)               ; 0ffc
        AND A                            ; 0fff
        RET nz                           ; 1000
        LD A,(PAUSE_FLAG)                ; 1001
        AND A                            ; 1004
        RET nz                           ; 1005
        LD A,(0x4362)                    ; 1006
        INC A                            ; 1009
        AND 15                           ; 100a
        LD (0x4362),A                    ; 100c
        LD E,A                           ; 100f
        LD D,0                           ; 1010
        LD HL,0x0cda                     ; 1012
        ADD HL,DE                        ; 1015
        LD A,(HL)                        ; 1016
        AND 15                           ; 1017
        LD (CUR_COLOUR),A                ; 1019
        RET                              ; 101c

; ---- attr_restart: 0xBD
attr_restart:
        XOR A                            ; 101d
        LD (RENDER_DONE),A               ; 101e
        LD (MENU_TMP2),A                 ; 1021
        LD (MENU_TMP),A                  ; 1024
        LD (FONT_MODE),A                 ; 1027
        LD A,0x8f                        ; 102a
        LD (CUR_COLOUR),A                ; 102c
        JP render_next_char              ; 102f

; ---- fx_pause
fx_pause:
        XOR A                            ; 1032
        LD (EFFECT_PHASE),A              ; 1033
        LD A,(PAUSE_FLAG)                ; 1036
        AND A                            ; 1039
        JR nz,L_1042                     ; 103a

L_103c:
        LD A,(0x4244)                    ; 103c
        AND A                            ; 103f
        JR nz,L_103c                     ; 1040

L_1042:
        LD A,0x50                        ; 1042
        LD (0x4244),A                    ; 1044
        CALL sub_1062                    ; 1047
        LD HL,(STORE_CURSOR)             ; 104a
        LD A,(HL)                        ; 104d
        CP 0x18                          ; 104e
        JP z,fx_crawl                    ; 1050
        LD A,(PAUSE_FLAG)                ; 1053
        AND A                            ; 1056
        JP z,fx_crawl                    ; 1057
        LD A,0x56                        ; 105a
        LD (COL_COUNT),A                 ; 105c
        JP render_next_char              ; 105f

sub_1062:
        LD HL,FRAMEBUF                   ; 1062
        LD BC,0x0158                     ; 1065

L_1068:
        BIT 7,(HL)                       ; 1068
        JR z,L_1072                      ; 106a
        LD A,(HL)                        ; 106c
        AND 0x10                         ; 106d
        OR 0x8f                          ; 106f
        LD (HL),A                        ; 1071

L_1072:
        INC HL                           ; 1072
        DEC BC                           ; 1073
        LD A,C                           ; 1074
        OR B                             ; 1075
        JR nz,L_1068                     ; 1076
        LD A,(0x421b)                    ; 1078
        AND 0x10                         ; 107b
        OR 0x8f                          ; 107d
        LD (0x421b),A                    ; 107f
        LD (ROW_DATA_LATCH),A            ; 1082
        LD E,A                           ; 1085
        LD A,(RENDER_DONE)               ; 1086
        AND A                            ; 1089
        RET z                            ; 108a
        LD A,15                          ; 108b
        LD (CUR_COLOUR),A                ; 108d
        RET                              ; 1090

; ---- attr_colour_speed: 0x8x foreground colour, 0x9x background, 0xFx speed, 0xBD restart
attr_colour_speed:
        LD A,(CUR_CHAR)                  ; 1091
        AND 0xf0                         ; 1094
        CP 0x80                          ; 1096
        JP z,attr_fore_colour            ; 1098
        CP 0x90                          ; 109b
        JP z,attr_back_colour            ; 109d
        CP 0xf0                          ; 10a0
        JP z,attr_speed                  ; 10a2
        LD A,(CUR_CHAR)                  ; 10a5
        CP 0xbd                          ; 10a8
        JP z,attr_restart                ; 10aa
        JP render_next_char              ; 10ad

; ---- attr_fore_colour
attr_fore_colour:
        XOR A                            ; 10b0
        LD (0x43a4),A                    ; 10b1
        LD A,(RENDER_DONE)               ; 10b4
        AND A                            ; 10b7
        JR z,L_10c2                      ; 10b8
        LD A,(CUR_COLOUR)                ; 10ba
        AND 0xcf                         ; 10bd
        LD (CUR_COLOUR),A                ; 10bf

L_10c2:
        LD A,(CUR_CHAR)                  ; 10c2
        AND 15                           ; 10c5
        LD E,A                           ; 10c7
        LD A,(CUR_COLOUR)                ; 10c8
        AND 0x60                         ; 10cb
        OR E                             ; 10cd
        LD (CUR_COLOUR),A                ; 10ce
        LD A,0xff                        ; 10d1
        LD (MENU_TMP),A                  ; 10d3
        JP render_next_char              ; 10d6

; ---- attr_back_colour
attr_back_colour:
        LD A,(RENDER_DONE)               ; 10d9
        AND A                            ; 10dc
        JR z,L_10e7                      ; 10dd
        LD A,(CUR_COLOUR)                ; 10df
        OR 15                            ; 10e2
        LD (CUR_COLOUR),A                ; 10e4

L_10e7:
        XOR A                            ; 10e7
        LD (0x43a4),A                    ; 10e8
        LD HL,0                          ; 10eb
        LD DE,0x20                       ; 10ee
        LD A,(CUR_CHAR)                  ; 10f1
        AND 3                            ; 10f4
        JR z,L_10fc                      ; 10f6

L_10f8:
        ADD HL,DE                        ; 10f8
        DEC A                            ; 10f9
        JR nz,L_10f8                     ; 10fa

L_10fc:
        LD A,(CUR_COLOUR)                ; 10fc
        AND 15                           ; 10ff
        OR L                             ; 1101
        AND 0x6f                         ; 1102
        LD (CUR_COLOUR),A                ; 1104
        LD A,0xff                        ; 1107
        LD (MENU_TMP),A                  ; 1109
        JP render_next_char              ; 110c

; ---- attr_speed
attr_speed:
        LD A,(CUR_CHAR)                  ; 110f
        AND 7                            ; 1112
        LD (0x43cd),A                    ; 1114
        JP render_next_char              ; 1117

; ---- attr_tiny: 0xBE: switch to tiny (28-char) font mode and render
attr_tiny:
        CALL sub_114c                    ; 111a
        CALL clear_framebuf              ; 111d
        LD A,0xff                        ; 1120
        LD (TINY_RENDER),A               ; 1122
        LD A,0x8f                        ; 1125
        LD (FRAMEBUF_TINY),A             ; 1127

L_112a:
        CALL sub_1187                    ; 112a
        AND A                            ; 112d
        JR nz,L_113c                     ; 112e
        CALL sub_11fe                    ; 1130
        LD HL,(STORE_CURSOR)             ; 1133
        INC HL                           ; 1136
        LD (STORE_CURSOR),HL             ; 1137
        JR L_112a                        ; 113a

L_113c:
        CALL sub_1231                    ; 113c
        CALL clear_framebuf              ; 113f
        XOR A                            ; 1142
        LD (TINY_RENDER),A               ; 1143
        CALL init_render                 ; 1146
        JP L_00a7                        ; 1149

sub_114c:
        LD E,0                           ; 114c
        LD HL,FB_COL                     ; 114e
        LD B,0x56                        ; 1151

L_1153:
        BIT 7,(HL)                       ; 1153
        JR z,L_115a                      ; 1155
        LD A,(HL)                        ; 1157
        OR E                             ; 1158
        LD E,A                           ; 1159

L_115a:
        INC HL                           ; 115a
        DJNZ L_1153                      ; 115b
        LD A,E                           ; 115d
        AND A                            ; 115e
        RET z                            ; 115f
        LD B,14                          ; 1160

L_1162:
        PUSH BC                          ; 1162
        LD A,0x20                        ; 1163
        LD (CUR_CHAR),A                  ; 1165
        XOR A                            ; 1168
        LD (PAUSE_FLAG),A                ; 1169
        LD HL,fx_none                    ; 116c
        LD (EFFECT_VECTOR),HL            ; 116f
        LD A,6                           ; 1172
        LD (GLYPH_WIDTH),A               ; 1174
        LD HL,0x3235                     ; 1177
        LD (GLYPH_PTR),HL                ; 117a
        CALL sub_086e                    ; 117d
        CALL effect_step                 ; 1180
        POP BC                           ; 1183
        DJNZ L_1162                      ; 1184
        RET                              ; 1186

sub_1187:
        LD HL,(STORE_CURSOR)             ; 1187
        LD A,(HL)                        ; 118a
        LD (CUR_CHAR),A                  ; 118b
        AND 0xf0                         ; 118e
        CP 0xa0                          ; 1190
        JR nz,L_119e                     ; 1192
        LD A,(CUR_CHAR)                  ; 1194
        AND 15                           ; 1197
        LD (CUR_CHAR),A                  ; 1199
        JR L_11c7                        ; 119c

L_119e:
        LD A,(CUR_CHAR)                  ; 119e
        AND 0x60                         ; 11a1
        JP z,L_11fb                      ; 11a3
        LD A,(CUR_CHAR)                  ; 11a6
        CP 0x5f                          ; 11a9
        JP z,L_11fb                      ; 11ab
        BIT 7,A                          ; 11ae
        JP z,L_11c7                      ; 11b0
        CP 0x94                          ; 11b3
        JP c,L_11fb                      ; 11b5
        CP 0x9e                          ; 11b8
        JR c,L_11c7                      ; 11ba
        AND 0xf0                         ; 11bc
        CP 0xc0                          ; 11be
        JR z,L_11c7                      ; 11c0
        CP 0xe0                          ; 11c2
        JP nz,L_11fb                     ; 11c4

L_11c7:
        LD HL,FONT                       ; 11c7
        LD A,(CUR_CHAR)                  ; 11ca
        CALL char_to_glyph               ; 11cd
        LD E,A                           ; 11d0
        LD D,0                           ; 11d1
        SLA E                            ; 11d3
        RL D                             ; 11d5
        SLA E                            ; 11d7
        RL D                             ; 11d9
        SLA E                            ; 11db
        RL D                             ; 11dd
        ADD HL,DE                        ; 11df
        PUSH HL                          ; 11e0
        LD DE,7                          ; 11e1
        ADD HL,DE                        ; 11e4
        LD A,(HL)                        ; 11e5
        LD (GLYPH_WIDTH),A               ; 11e6
        POP HL                           ; 11e9

sub_11ea:
        LD DE,0x40ec                     ; 11ea
        LD B,0                           ; 11ed
        LD A,(GLYPH_WIDTH)               ; 11ef
        LD C,A                           ; 11f2
        LD A,0x8f                        ; 11f3
        LD (DE),A                        ; 11f5
        INC DE                           ; 11f6
        LDIR                             ; 11f7
        XOR A                            ; 11f9
        RET                              ; 11fa

L_11fb:
        LD A,0xff                        ; 11fb
        RET                              ; 11fd

sub_11fe:
        LD A,(GLYPH_WIDTH)               ; 11fe
        INC A                            ; 1201

L_1202:
        LD HL,0x4041                     ; 1202
        LD DE,FRAMEBUF                   ; 1205
        LD BC,0xbc                       ; 1208
        LDIR                             ; 120b
        PUSH AF                          ; 120d
        CALL sub_1216                    ; 120e
        POP AF                           ; 1211
        DEC A                            ; 1212
        JR nz,L_1202                     ; 1213
        RET                              ; 1215

sub_1216:
        LD HL,FRAMEBUF                   ; 1216
        LD DE,0x410a                     ; 1219
        LD BC,0x56                       ; 121c
        LD A,(ROW_PHASE)                 ; 121f
        AND A                            ; 1222
        JR nz,sub_1216                   ; 1223

L_1225:
        LDI                              ; 1225
        INC HL                           ; 1227
        JP pe,L_1225                     ; 1228
        LD A,0xff                        ; 122b
        LD (ROW_PHASE),A                 ; 122d
        RET                              ; 1230

sub_1231:
        LD B,0x1c                        ; 1231

L_1233:
        PUSH BC                          ; 1233
        LD A,0x20                        ; 1234
        LD (CUR_CHAR),A                  ; 1236
        LD A,5                           ; 1239
        LD (GLYPH_WIDTH),A               ; 123b
        LD HL,0x3235                     ; 123e
        CALL sub_11ea                    ; 1241
        CALL sub_11fe                    ; 1244
        POP BC                           ; 1247
        DJNZ L_1233                      ; 1248
        RET                              ; 124a

L_124b:
        LD A,(ROW_PHASE)                 ; 124b
        AND A                            ; 124e
        JR nz,L_125f                     ; 124f
        LD A,(CTRL_LATCH_SHADOW)         ; 1251
        OR 15                            ; 1254
        LD (CTRL_LATCH_SHADOW),A         ; 1256
        LD (CTRL_LATCH),A                ; 1259
        JP rx_consume                    ; 125c

L_125f:
        LD A,(DISP_ENABLE)               ; 125f
        AND A                            ; 1262
        JP z,disp_next_row               ; 1263
        LD A,(CTRL_LATCH_SHADOW)         ; 1266
        OR 15                            ; 1269
        LD (CTRL_LATCH_SHADOW),A         ; 126b
        LD (CTRL_LATCH),A                ; 126e

; ---- disp_blank_row: Send 0x8F (all off) to the current row
disp_blank_row:
        LD HL,0x410a                     ; 1271
        LD B,0x56                        ; 1274
        LD C,0x48                        ; 1276
        LD A,(ROW_INDEX)                 ; 1278
        CPL                              ; 127b
        AND 7                            ; 127c
        DEC A                            ; 127e
        OR C                             ; 127f
        LD C,A                           ; 1280
        RES 5,C                          ; 1281
        LD A,0x8f                        ; 1283
        OUT (C),A                        ; 1285
        OTIR                             ; 1287
        OUT (PORT_STROBE),A              ; 1289
        LD A,(ROW_INDEX)                 ; 128b
        CPL                              ; 128e
        AND 7                            ; 128f
        DEC A                            ; 1291
        JR nz,L_1296                     ; 1292
        LD A,7                           ; 1294

L_1296:
        LD C,A                           ; 1296
        LD A,(0x421f)                    ; 1297
        OR C                             ; 129a
        AND 0x8f                         ; 129b
        LD C,A                           ; 129d
        LD A,(CTRL_LATCH_SHADOW)         ; 129e
        AND 0x70                         ; 12a1
        OR C                             ; 12a3
        LD (CTRL_LATCH_SHADOW),A         ; 12a4
        LD (CTRL_LATCH),A                ; 12a7
        XOR A                            ; 12aa
        LD (DISP_ENABLE),A               ; 12ab
        JP L_030d                        ; 12ae

; ---- disp_next_row: ROW_INDEX = (ROW_INDEX+1) mod 7
disp_next_row:
        LD A,(ROW_INDEX)                 ; 12b1
        LD C,A                           ; 12b4
        INC A                            ; 12b5
        LD (ROW_INDEX),A                 ; 12b6
        CP 7                             ; 12b9
        JP c,L_0303                      ; 12bb
        LD A,0                           ; 12be
        LD (ROW_INDEX),A                 ; 12c0
        LD (ROW_PHASE),A                 ; 12c3
        JP rx_consume                    ; 12c6

; ---- fx_setup_scroll
fx_setup_scroll:
        CALL clear_framebuf              ; 12c9

sub_12cc:
        LD HL,FRAMEBUF_ROW1              ; 12cc
        LD (FB_COLPTR),HL                ; 12cf
        LD HL,0x56                       ; 12d2
        LD (DISP_FLAGS),HL               ; 12d5
        LD HL,0                          ; 12d8
        LD (FB_EXTRA_LEN),HL             ; 12db
        LD DE,FRAMEBUF                   ; 12de
        LD (FB_COL),DE                   ; 12e1
        LD (SEQ_PTR_SAVE),DE             ; 12e5
        LD HL,(EFFECT_TMP2)              ; 12e9
        ADD HL,DE                        ; 12ec
        LD DE,TXBUF                      ; 12ed
        EX DE,HL                         ; 12f0
        RET                              ; 12f1

; ---- fx_scroll_in
fx_scroll_in:
        LD A,0xff                        ; 12f2
        LD (EFFECT_ACTIVE),A             ; 12f4
        CALL fx_setup_scroll             ; 12f7
        LD A,(COL_COUNT)                 ; 12fa
        LD B,A                           ; 12fd

L_12fe:
        LD A,(ROW_INDEX)                 ; 12fe
        CP 6                             ; 1301
        JR nz,L_12fe                     ; 1303
        LD A,(HL)                        ; 1305
        LD (DE),A                        ; 1306
        INC HL                           ; 1307
        INC DE                           ; 1308
        LD A,0xff                        ; 1309
        LD (EFFECT_ACTIVE),A             ; 130b
        LD A,1                           ; 130e
        LD (0x4244),A                    ; 1310

L_1313:
        LD A,(0x4244)                    ; 1313
        AND A                            ; 1316
        JR nz,L_1313                     ; 1317
        DJNZ L_12fe                      ; 1319
        LD A,0x50                        ; 131b
        LD (0x4244),A                    ; 131d
        XOR A                            ; 1320
        LD (EFFECT_PHASE),A              ; 1321
        JP L_0e6e                        ; 1324

; ---- fx_none: effect handler: nothing (straight to render loop)
fx_none:
        JP L_0e6e                        ; 1327

; ---- fx_fill_frame: fill FRAMEBUF with 0x8F then continue
fx_fill_frame:
        LD HL,FRAMEBUF                   ; 132a
        LD BC,0x0158                     ; 132d

L_1330:
        LD (HL),0x8f                     ; 1330
        INC HL                           ; 1332
        DEC BC                           ; 1333
        LD A,C                           ; 1334
        OR B                             ; 1335
        JR nz,L_1330                     ; 1336
        CALL sub_12cc                    ; 1338
        LD A,(COL_COUNT)                 ; 133b
        PUSH HL                          ; 133e
        LD H,0                           ; 133f
        LD L,A                           ; 1341
        ADD HL,DE                        ; 1342
        POP DE                           ; 1343
        EX DE,HL                         ; 1344
        LD C,A                           ; 1345
        LD B,0                           ; 1346
        ADD HL,BC                        ; 1348
        LD B,A                           ; 1349
        INC B                            ; 134a

L_134b:
        LD A,(ROW_INDEX)                 ; 134b
        CP 6                             ; 134e
        JR nz,L_134b                     ; 1350
        LD A,(HL)                        ; 1352
        LD (DE),A                        ; 1353
        DEC HL                           ; 1354
        DEC DE                           ; 1355
        LD A,0xff                        ; 1356
        LD (EFFECT_ACTIVE),A             ; 1358
        LD A,1                           ; 135b
        LD (0x4244),A                    ; 135d

L_1360:
        LD A,(0x4244)                    ; 1360
        AND A                            ; 1363
        JR nz,L_1360                     ; 1364
        DJNZ L_134b                      ; 1366
        LD A,0x50                        ; 1368
        LD (0x4244),A                    ; 136a
        XOR A                            ; 136d
        LD (EFFECT_PHASE),A              ; 136e
        JP L_0e6e                        ; 1371

; ---- fx_scroll_copy
fx_scroll_copy:
        CALL fx_setup_scroll             ; 1374
        LD B,0                           ; 1377
        LD A,(COL_COUNT)                 ; 1379
        LD C,A                           ; 137c
        LDIR                             ; 137d
        LD A,0x50                        ; 137f
        LD (0x4244),A                    ; 1381
        XOR A                            ; 1384
        LD (EFFECT_PHASE),A              ; 1385
        JP L_0e6e                        ; 1388

; ---- fx_138b
fx_138b:
        LD A,0                           ; 138b
        LD (EFFECT_ACTIVE),A             ; 138d
        CALL fx_setup_scroll             ; 1390
        LD A,(COL_COUNT)                 ; 1393
        LD B,A                           ; 1396
        LD A,(PAUSE_FLAG)                ; 1397
        CP 2                             ; 139a
        LD C,0x80                        ; 139c
        JR z,L_13a2                      ; 139e
        LD C,1                           ; 13a0

L_13a2:
        LD A,8                           ; 13a2

L_13a4:
        PUSH AF                          ; 13a4
        PUSH HL                          ; 13a5
        PUSH DE                          ; 13a6
        PUSH BC                          ; 13a7

L_13a8:
        LD A,(ROW_INDEX)                 ; 13a8
        CP 6                             ; 13ab
        JR nz,L_13a8                     ; 13ad

L_13af:
        LD A,(HL)                        ; 13af
        BIT 7,A                          ; 13b0
        JR nz,L_13b7                     ; 13b2
        AND C                            ; 13b4
        JR L_13bf                        ; 13b5

L_13b7:
        LD A,C                           ; 13b7
        CP 0xff                          ; 13b8
        LD A,0x8f                        ; 13ba
        JR nz,L_13bf                     ; 13bc
        LD A,(HL)                        ; 13be

L_13bf:
        LD (DE),A                        ; 13bf
        INC HL                           ; 13c0
        INC DE                           ; 13c1
        DJNZ L_13af                      ; 13c2
        LD A,0xff                        ; 13c4
        LD (EFFECT_ACTIVE),A             ; 13c6
        LD A,3                           ; 13c9
        LD (0x4244),A                    ; 13cb

L_13ce:
        LD A,(0x4244)                    ; 13ce
        AND A                            ; 13d1
        JR nz,L_13ce                     ; 13d2
        POP BC                           ; 13d4
        POP DE                           ; 13d5
        POP HL                           ; 13d6
        LD A,(PAUSE_FLAG)                ; 13d7
        CP 2                             ; 13da
        JR nz,L_13e3                     ; 13dc
        SCF                              ; 13de
        RR C                             ; 13df
        JR L_13e6                        ; 13e1

L_13e3:
        SCF                              ; 13e3
        RL C                             ; 13e4

L_13e6:
        POP AF                           ; 13e6
        DEC A                            ; 13e7
        JR nz,L_13a4                     ; 13e8
        LD A,0x50                        ; 13ea
        LD (0x4244),A                    ; 13ec
        XOR A                            ; 13ef
        LD (EFFECT_PHASE),A              ; 13f0
        JP L_0e6e                        ; 13f3
        db 0xc9   ; 13f6

; ---- store_clear_all: Reset MSG_STORE: 100 empty channels D0..? then DA
store_clear_all:
        LD A,0xd0                        ; 13f7
        LD C,0xd0                        ; 13f9
        LD HL,MSG_STORE                  ; 13fb
        LD B,0x64                        ; 13fe

L_1400:
        LD (HL),A                        ; 1400
        INC HL                           ; 1401
        LD (HL),C                        ; 1402
        INC HL                           ; 1403
        LD (HL),3                        ; 1404
        INC HL                           ; 1406
        INC C                            ; 1407
        LD D,A                           ; 1408
        LD A,C                           ; 1409
        CP 0xda                          ; 140a
        JR nz,L_1411                     ; 140c
        LD C,0xd0                        ; 140e
        INC D                            ; 1410

L_1411:
        LD A,D                           ; 1411
        DJNZ L_1400                      ; 1412
        LD A,0xda                        ; 1414
        LD (HL),A                        ; 1416
        LD HL,SEQ_LIST                   ; 1417
        LD (HL),0xda                     ; 141a
        LD B,0x67                        ; 141c

L_141e:
        INC HL                           ; 141e
        LD (HL),0xff                     ; 141f
        DJNZ L_141e                      ; 1421
        RET                              ; 1423

; ---- ir_init: misnomer - this is the message-store init. Sets the store
;      ceiling and its three derived constants, writes the 0xDA store
;      terminator at the ceiling, then zeroes 0x5EF0..0x5FFF (PKT_READY,
;      PKT_BUF and the parser state, i.e. the whole top page of RAM).
;      0x43DE = ceiling-100, the "100 KEYS LEFT" trip point (used at 0x2601).
;      0x43DC = free text bytes, the scan bound used by init_vars2 at 0x0481.
ir_init:
        LD A,0xff                        ; 1424
        LD (RX_MSGFLAG),A                ; 1426
        LD HL,STORE_TOP                  ; 1429
        LD (STORE_LIMIT),HL              ; 142c
        LD (STORE_END),HL                ; 142f
        LD HL,STORE_WARN                 ; 1432
        LD (0x43de),HL                   ; 1435
        LD HL,STORE_TEXT_FREE            ; 1438
        LD (0x43dc),HL                   ; 143b
        LD HL,STORE_SIZE_INIT            ; 143e
        LD (STORE_SIZE),HL               ; 1441
        ; P1: the terminator no longer sits one below the area to be zeroed,
        ; so set HL/BC for the clear and write the 0xDA out of line. Same
        ; 9 bytes, so L_144d stays at 0x144D.
        LD BC,0x0110                     ; 1444
        LD HL,0x5ef0                     ; 1447
        CALL patch_store_term            ; 144a

L_144d:
        LD (HL),0                        ; 144d
        INC HL                           ; 144f
        DEC BC                           ; 1450
        LD A,C                           ; 1451
        OR B                             ; 1452
        JR nz,L_144d                     ; 1453
        LD HL,rx_st_wait_start           ; 1455
        LD (RX_STATE),HL                 ; 1458
        LD HL,rx_st_wait_start           ; 145b
        LD (0x425e),HL                   ; 145e
        XOR A                            ; 1461
        LD (RX_TICKS),A                  ; 1462
        LD (0x424c),A                    ; 1465
        RET                              ; 1468
        db 0xaa,"U"   ; 1469

; ---- ir_init2
ir_init2:
        PUSH AF                          ; 146b
        XOR A                            ; 146c
        LD (0x4377),A                    ; 146d
        LD (IR_CODE),A                   ; 1470
        LD (0x4387),A                    ; 1473
        LD (IR_KEY),A                    ; 1476
        LD (GEN_COUNTDOWN),A             ; 1479
        LD (0x4381),A                    ; 147c
        LD (TICK1_COUNT),A               ; 147f

; ---- ir_reset: IR decoder: reset state, wait for leader (port C0 bit1)
ir_reset:
        LD A,0x82                        ; 1482
        LD (IR_STATE_CNT),A              ; 1484
        LD A,6                           ; 1487
        LD (IR_BITCNT),A                 ; 1489
        XOR A                            ; 148c
        LD (IR_SHIFT),A                  ; 148d
        PUSH HL                          ; 1490
        LD HL,ir_st_idle                 ; 1491
        LD (TICK_VECTOR),HL              ; 1494
        POP HL                           ; 1497
        POP AF                           ; 1498
        RET                              ; 1499

; ---- ir_st_idle
ir_st_idle:
        PUSH AF                          ; 149a
        IN A,(PORT_IN)                   ; 149b
        BIT 1,A                          ; 149d
        JP nz,ir_reset                   ; 149f
        LD A,(IR_STATE_CNT)              ; 14a2
        DEC A                            ; 14a5
        JP nz,L_14b1                     ; 14a6
        PUSH HL                          ; 14a9
        LD HL,ir_st_leader               ; 14aa
        LD (TICK_VECTOR),HL              ; 14ad
        POP HL                           ; 14b0

L_14b1:
        LD (IR_STATE_CNT),A              ; 14b1
        POP AF                           ; 14b4
        RET                              ; 14b5

; ---- ir_st_leader
ir_st_leader:
        PUSH AF                          ; 14b6
        IN A,(PORT_IN)                   ; 14b7
        BIT 1,A                          ; 14b9
        JP z,L_14cb                      ; 14bb
        PUSH HL                          ; 14be
        LD HL,ir_st_leader2              ; 14bf
        LD (TICK_VECTOR),HL              ; 14c2
        POP HL                           ; 14c5
        LD A,4                           ; 14c6
        LD (IR_STATE_CNT),A              ; 14c8

L_14cb:
        POP AF                           ; 14cb
        RET                              ; 14cc

; ---- ir_st_leader2
ir_st_leader2:
        PUSH AF                          ; 14cd
        IN A,(PORT_IN)                   ; 14ce
        BIT 1,A                          ; 14d0
        JP nz,L_14e2                     ; 14d2
        PUSH HL                          ; 14d5
        LD HL,ir_st_leader3              ; 14d6
        LD (TICK_VECTOR),HL              ; 14d9
        POP HL                           ; 14dc
        LD A,0x15                        ; 14dd
        LD (IR_STATE_CNT),A              ; 14df

L_14e2:
        POP AF                           ; 14e2
        RET                              ; 14e3

; ---- ir_st_leader3
ir_st_leader3:
        PUSH AF                          ; 14e4
        LD A,(IR_STATE_CNT)              ; 14e5
        DEC A                            ; 14e8
        JR nz,L_14fc                     ; 14e9
        IN A,(PORT_IN)                   ; 14eb
        BIT 1,A                          ; 14ed
        JP z,ir_reset                    ; 14ef
        PUSH HL                          ; 14f2
        LD HL,ir_st_start                ; 14f3
        LD (TICK_VECTOR),HL              ; 14f6
        POP HL                           ; 14f9
        LD A,3                           ; 14fa

L_14fc:
        LD (IR_STATE_CNT),A              ; 14fc
        POP AF                           ; 14ff
        RET                              ; 1500

; ---- ir_st_start
ir_st_start:
        PUSH AF                          ; 1501
        LD A,(IR_STATE_CNT)              ; 1502
        DEC A                            ; 1505
        JP nz,L_151a                     ; 1506
        IN A,(PORT_IN)                   ; 1509
        BIT 1,A                          ; 150b
        JP nz,ir_reset                   ; 150d
        PUSH HL                          ; 1510
        LD HL,ir_st_bits                 ; 1511
        LD (TICK_VECTOR),HL              ; 1514
        POP HL                           ; 1517
        LD A,8                           ; 1518

L_151a:
        LD (IR_STATE_CNT),A              ; 151a
        POP AF                           ; 151d
        RET                              ; 151e

; ---- ir_st_bits: sample a data bit (port C0 bit1) into IR_SHIFT every 4 ticks
ir_st_bits:
        PUSH AF                          ; 151f
        LD A,(IR_STATE_CNT)              ; 1520
        DEC A                            ; 1523
        JP z,L_1540                      ; 1524
        CP 4                             ; 1527
        JP nz,L_155d                     ; 1529
        LD (IR_STATE_CNT),A              ; 152c
        PUSH HL                          ; 152f
        LD HL,IR_SHIFT                   ; 1530
        RRC (HL)                         ; 1533
        IN A,(PORT_IN)                   ; 1535
        AND 2                            ; 1537
        OR (HL)                          ; 1539
        LD (IR_SHIFT),A                  ; 153a
        POP HL                           ; 153d
        POP AF                           ; 153e
        RET                              ; 153f

L_1540:
        PUSH HL                          ; 1540
        LD A,(IR_SHIFT)                  ; 1541
        CPL                              ; 1544
        AND 2                            ; 1545
        LD L,A                           ; 1547
        IN A,(PORT_IN)                   ; 1548
        AND 2                            ; 154a
        CP L                             ; 154c
        POP HL                           ; 154d
        JP nz,ir_reset                   ; 154e
        LD A,(IR_BITCNT)                 ; 1551
        DEC A                            ; 1554
        LD (IR_BITCNT),A                 ; 1555
        JP z,L_1562                      ; 1558
        LD A,8                           ; 155b

L_155d:
        LD (IR_STATE_CNT),A              ; 155d
        POP AF                           ; 1560
        RET                              ; 1561

L_1562:
        LD A,(IR_SHIFT)                  ; 1562
        RRCA                             ; 1565
        RRCA                             ; 1566
        RRCA                             ; 1567
        RRCA                             ; 1568
        OR 0x80                          ; 1569
        LD (IR_CODE),A                   ; 156b
        JP ir_reset                      ; 156e

; ---- tx_send_byte: Queue byte A for bit-banged transmission; blocks until the previous byte is out
tx_send_byte:
        PUSH HL                          ; 1571
        PUSH DE                          ; 1572

L_1573:
        CALL tx_try_queue                ; 1573
        AND A                            ; 1576
        JR nz,L_1573                     ; 1577
        POP DE                           ; 1579
        POP HL                           ; 157a
        RET                              ; 157b

; ---- tx_try_queue
tx_try_queue:
        LD HL,TX_STATUS                  ; 157c
        BIT 1,(HL)                       ; 157f
        RET nz                           ; 1581
        LD (TX_PENDING),A                ; 1582
        SET 1,(HL)                       ; 1585
        XOR A                            ; 1587
        RET                              ; 1588

; ---- tx_bit_engine: Called every 6 ticks: shifts TX_SHIFT out on CTRL_LATCH bit 4 (1=start/space, 0=mark). Bit times from TX_TIMING table (4,4,5 ticks); state 9 = stop bits (10 ticks)
tx_bit_engine:
        LD HL,TX_STATUS                  ; 1589
        BIT 0,(HL)                       ; 158c
        JR nz,L_15b9                     ; 158e
        BIT 1,(HL)                       ; 1590
        RET z                            ; 1592
        LD A,(TX_PENDING)                ; 1593
        LD (TX_SHIFT),A                  ; 1596
        LD (HL),1                        ; 1599
        XOR A                            ; 159b
        LD (TX_BITIDX),A                 ; 159c
        INC A                            ; 159f
        LD (TX_BITMASK),A                ; 15a0
        LD HL,TX_TIMING                  ; 15a3
        LD (TX_TIMING_PTR),HL            ; 15a6
        LD A,(CTRL_LATCH_SHADOW)         ; 15a9
        OR 0x10                          ; 15ac
        LD (CTRL_LATCH_SHADOW),A         ; 15ae
        LD (CTRL_LATCH),A                ; 15b1
        LD A,(HL)                        ; 15b4
        LD (TX_TICKS),A                  ; 15b5
        RET                              ; 15b8

L_15b9:
        LD HL,TX_TICKS                   ; 15b9
        DEC (HL)                         ; 15bc
        RET nz                           ; 15bd
        LD HL,TX_BITIDX                  ; 15be
        INC (HL)                         ; 15c1
        LD A,(HL)                        ; 15c2
        CP 9                             ; 15c3
        JR z,L_15f2                      ; 15c5
        CP 10                            ; 15c7
        JR z,L_1603                      ; 15c9
        LD HL,TX_BITMASK                 ; 15cb
        LD E,(HL)                        ; 15ce
        SLA (HL)                         ; 15cf
        LD A,(TX_SHIFT)                  ; 15d1
        AND E                            ; 15d4
        LD A,(CTRL_LATCH_SHADOW)         ; 15d5
        JR nz,L_15de                     ; 15d8
        OR 0x10                          ; 15da
        JR L_15e0                        ; 15dc

L_15de:
        AND 0xef                         ; 15de

L_15e0:
        LD (CTRL_LATCH_SHADOW),A         ; 15e0
        LD (CTRL_LATCH),A                ; 15e3
        LD HL,(TX_TIMING_PTR)            ; 15e6
        INC HL                           ; 15e9
        LD (TX_TIMING_PTR),HL            ; 15ea
        LD A,(HL)                        ; 15ed
        LD (TX_TICKS),A                  ; 15ee
        RET                              ; 15f1

L_15f2:
        LD A,(CTRL_LATCH_SHADOW)         ; 15f2
        AND 0xef                         ; 15f5
        LD (CTRL_LATCH_SHADOW),A         ; 15f7
        LD (CTRL_LATCH),A                ; 15fa
        LD A,10                          ; 15fd
        LD (TX_TICKS),A                  ; 15ff
        RET                              ; 1602

L_1603:
        LD HL,TX_STATUS                  ; 1603
        RES 0,(HL)                       ; 1606
        RET                              ; 1608

; ---- rx_bit_engine: Called every 6 ticks: bit-banged receiver state machine on PORT_IN bit 3 (1 = space). Uses RX_TIMING table; assembled bytes go to RX_FIFO (8 deep, RX_COUNT)
rx_bit_engine:
        LD A,(RX_COUNT)                  ; 1609
        CP 8                             ; 160c
        JR nz,L_161c                     ; 160e
        LD HL,rx_st_wait_start           ; 1610
        LD (RX_STATE),HL                 ; 1613
        LD A,0                           ; 1616
        LD (RX_TICKS),A                  ; 1618
        RET                              ; 161b

L_161c:
        LD A,(RX_TICKS)                  ; 161c
        AND A                            ; 161f
        JR z,L_1627                      ; 1620
        DEC A                            ; 1622
        LD (RX_TICKS),A                  ; 1623
        RET nz                           ; 1626

L_1627:
        LD HL,(RX_STATE)                 ; 1627
        JP (HL)                          ; 162a

; ---- rx_st_wait_start
rx_st_wait_start:
        IN A,(PORT_IN)                   ; 162b
        BIT 3,A                          ; 162d
        RET z                            ; 162f
        LD HL,rx_st_sample_bit           ; 1630
        LD (RX_STATE),HL                 ; 1633
        LD HL,RX_TIMING                  ; 1636
        LD (RX_TIMING_PTR),HL            ; 1639
        LD A,(HL)                        ; 163c
        LD (RX_TICKS),A                  ; 163d
        LD A,1                           ; 1640
        LD (RX_BITMASK),A                ; 1642
        XOR A                            ; 1645
        LD (RX_SHIFT),A                  ; 1646
        RET                              ; 1649

; ---- data 164a-1653: ticks between RX bit samples (start,8 data,stop)
RX_TIMING:
        db 0x06,0x04,0x05,0x04,0x04,0x05,0x04,0x04,0x05,0x04   ; 164a

; ---- data 1654-165d: ticks per TX bit: start,8 data (4,4,5 pattern = 300 baud @ ~1300 Hz), stop = 10
TX_TIMING:
        db 0x04,0x04,0x05,0x04,0x04,0x05,0x04,0x04,0x05,0x0a   ; 1654

; ---- rx_st_sample_bit
rx_st_sample_bit:
        IN A,(PORT_IN)                   ; 165e
        BIT 3,A                          ; 1660
        LD A,0xff                        ; 1662
        JR z,L_1667                      ; 1664
        XOR A                            ; 1666

L_1667:
        LD E,A                           ; 1667
        LD A,(RX_SHIFT)                  ; 1668
        LD D,A                           ; 166b
        LD A,(RX_BITMASK)                ; 166c
        PUSH AF                          ; 166f
        CPL                              ; 1670
        AND D                            ; 1671
        LD D,A                           ; 1672
        POP AF                           ; 1673
        AND E                            ; 1674
        OR D                             ; 1675
        LD (RX_SHIFT),A                  ; 1676
        LD HL,(RX_TIMING_PTR)            ; 1679
        INC HL                           ; 167c
        LD (RX_TIMING_PTR),HL            ; 167d
        LD A,(HL)                        ; 1680
        LD (RX_TICKS),A                  ; 1681
        LD A,(RX_BITMASK)                ; 1684
        SLA A                            ; 1687
        LD (RX_BITMASK),A                ; 1689
        RET nc                           ; 168c
        LD HL,rx_st_stop_bit             ; 168d
        LD (RX_STATE),HL                 ; 1690
        RET                              ; 1693

; ---- rx_st_stop_bit: stop bit must read as mark else byte is dropped
rx_st_stop_bit:
        IN A,(PORT_IN)                   ; 1694
        BIT 3,A                          ; 1696
        JR nz,L_16b7                     ; 1698
        LD A,(RX_SHIFT)                  ; 169a
        AND A                            ; 169d
        LD A,(RX_COUNT)                  ; 169e
        CP 8                             ; 16a1
        JR z,L_16b7                      ; 16a3
        AND 7                            ; 16a5
        LD HL,RX_FIFO                    ; 16a7
        LD E,A                           ; 16aa
        LD D,0                           ; 16ab
        ADD HL,DE                        ; 16ad
        LD A,(RX_SHIFT)                  ; 16ae
        LD (HL),A                        ; 16b1
        LD A,E                           ; 16b2
        INC A                            ; 16b3
        LD (RX_COUNT),A                  ; 16b4

L_16b7:
        XOR A                            ; 16b7
        LD (RX_TICKS),A                  ; 16b8
        LD (RX_SHIFT),A                  ; 16bb
        LD HL,rx_st_wait_start           ; 16be
        LD (RX_STATE),HL                 ; 16c1
        RET                              ; 16c4

; ---- rx_fifo_get: Pop one byte from RX_FIFO into RX_BYTE. Returns NC with A=byte, or C if empty
rx_fifo_get:
        LD A,(RX_COUNT)                  ; 16c5
        AND A                            ; 16c8
        JR z,L_16e9                      ; 16c9
        LD HL,RX_FIFO                    ; 16cb
        LD A,(HL)                        ; 16ce
        LD (RX_BYTE),A                   ; 16cf
        LD A,(RX_COUNT)                  ; 16d2
        LD BC,8                          ; 16d5
        LD HL,0x424e                     ; 16d8
        LD DE,RX_FIFO                    ; 16db
        LDIR                             ; 16de
        DEC A                            ; 16e0
        LD (RX_COUNT),A                  ; 16e1
        LD A,(RX_BYTE)                   ; 16e4
        OR A                             ; 16e7
        RET                              ; 16e8

L_16e9:
        XOR A                            ; 16e9
        LD (RX_BYTE),A                   ; 16ea
        SCF                              ; 16ed
        RET                              ; 16ee

; ---- pkt_feed_byte: Feed RX_BYTE to the packet parser state in PKT_VECTOR
pkt_feed_byte:
        LD A,(RX_BYTE)                   ; 16ef
        LD HL,(PKT_VECTOR)               ; 16f2
        JP (HL)                          ; 16f5

; ---- pkt_st_addr: store address byte -> PKT_ADDR
pkt_st_addr:
        LD (PKT_ADDR),A                  ; 16f6
        LD HL,pkt_st_flag                ; 16f9
        LD (PKT_VECTOR),HL               ; 16fc
        RET                              ; 16ff

; ---- pkt_st_flag: store 3rd header byte -> PKT_FLAG (0x80 from PC)
pkt_st_flag:
        LD (PKT_FLAG),A                  ; 1700
        LD HL,pkt_st_len                 ; 1703
        LD (PKT_VECTOR),HL               ; 1706
        RET                              ; 1709

; ---- pkt_st_len: store length; reset checksum & PKT_PTR=PKT_BUF; len 0 goes straight to checksum state
pkt_st_len:
        LD (PKT_LEN),A                   ; 170a
        AND A                            ; 170d
        LD HL,pkt_st_data                ; 170e
        JR nz,L_1716                     ; 1711
        LD HL,pkt_st_cksum               ; 1713

L_1716:
        LD (PKT_VECTOR),HL               ; 1716
        XOR A                            ; 1719
        LD (PKT_CKSUM),A                 ; 171a
        LD HL,PKT_BUF                    ; 171d
        LD (PKT_PTR),HL                  ; 1720
        LD A,(PKT_LEN)                   ; 1723
        LD (PKT_REMAIN),A                ; 1726
        RET                              ; 1729

; ---- pkt_st_data: store payload byte, PKT_CKSUM += byte
pkt_st_data:
        LD HL,(PKT_PTR)                  ; 172a
        LD (HL),A                        ; 172d
        LD A,(PKT_CKSUM)                 ; 172e
        ADD A,(HL)                       ; 1731
        LD (PKT_CKSUM),A                 ; 1732
        LD A,(PKT_REMAIN)                ; 1735
        DEC A                            ; 1738
        JR z,L_1743                      ; 1739
        LD (PKT_REMAIN),A                ; 173b
        INC HL                           ; 173e
        LD (PKT_PTR),HL                  ; 173f
        RET                              ; 1742

L_1743:
        LD HL,pkt_st_cksum               ; 1743
        LD (PKT_VECTOR),HL               ; 1746
        RET                              ; 1749

; ---- pkt_st_cksum: E = computed - received. Broadcast (0x2A): no reply. Own address: send ACK 06 / NAK 15. If OK and len>0 set PKT_READY (PKT_FLAG==0x80 -> process immediately)
pkt_st_cksum:
        LD E,A                           ; 174a
        LD A,(PKT_CKSUM)                 ; 174b
        SUB E                            ; 174e
        LD E,A                           ; 174f
        LD A,(PKT_ADDR)                  ; 1750
        CP 0x2a                          ; 1753
        JR z,L_1769                      ; 1755
        LD D,A                           ; 1757
        LD A,(MY_ADDRESS)                ; 1758
        CP D                             ; 175b
        JR nz,L_1785                     ; 175c
        LD A,E                           ; 175e
        AND A                            ; 175f
        LD A,6                           ; 1760
        JR z,L_1766                      ; 1762
        LD A,0x15                        ; 1764

L_1766:
        CALL tx_send_byte                ; 1766

L_1769:
        LD A,E                           ; 1769
        AND A                            ; 176a
        JR nz,L_1785                     ; 176b
        LD A,(PKT_LEN)                   ; 176d
        AND A                            ; 1770
        JR z,L_1785                      ; 1771
        LD A,0xff                        ; 1773
        LD (PKT_READY),A                 ; 1775
        XOR A                            ; 1778
        LD (PKT_STATE),A                 ; 1779
        LD A,(PKT_FLAG)                  ; 177c
        CP 0x80                          ; 177f
        JP z,pkt_process                 ; 1781
        RET                              ; 1784

L_1785:
        XOR A                            ; 1785
        LD (PKT_READY),A                 ; 1786
        LD (PKT_STATE),A                 ; 1789
        RET                              ; 178c

; ---- tx_send_frame: Send reply frame: B1, MY_ADDRESS, then (HL)=len, len bytes, 8-bit sum of the data bytes
tx_send_frame:
        PUSH AF                          ; 178d
        PUSH BC                          ; 178e
        PUSH DE                          ; 178f
        PUSH HL                          ; 1790
        PUSH IX                          ; 1791
        PUSH IY                          ; 1793
        LD A,0xb1                        ; 1795
        CALL tx_send_byte                ; 1797
        LD A,(MY_ADDRESS)                ; 179a
        CALL tx_send_byte                ; 179d
        LD E,0                           ; 17a0
        LD A,(HL)                        ; 17a2
        LD B,A                           ; 17a3
        CALL tx_send_byte                ; 17a4
        INC HL                           ; 17a7

L_17a8:
        LD A,(HL)                        ; 17a8
        ADD A,E                          ; 17a9
        LD E,A                           ; 17aa
        LD A,(HL)                        ; 17ab
        CALL tx_send_byte                ; 17ac
        INC HL                           ; 17af
        DJNZ L_17a8                      ; 17b0
        LD A,E                           ; 17b2
        CALL tx_send_byte                ; 17b3
        POP IY                           ; 17b6
        POP IX                           ; 17b8
        POP HL                           ; 17ba
        POP DE                           ; 17bb
        POP BC                           ; 17bc
        POP AF                           ; 17bd
        RET                              ; 17be

; ---- rx_cmd_check
rx_cmd_check:
        CALL query_dispatch              ; 17bf
        LD A,(RX_LASTCMD)                ; 17c2
        AND A                            ; 17c5
        RET nz                           ; 17c6
        POP HL                           ; 17c7
        POP HL                           ; 17c8
        JP L_1ad5                        ; 17c9

; ---- query_dispatch: 0xB4 + '0'..'3' query handlers
query_dispatch:
        LD A,(RX_MSGFLAG)                ; 17cc
        AND A                            ; 17cf
        RET z                            ; 17d0
        LD A,(RX_LASTCMD)                ; 17d1
        CP 0xb4                          ; 17d4
        RET nz                           ; 17d6
        CALL menu_getchar                ; 17d7
        CP 0x30                          ; 17da
        JP z,query_0_romid               ; 17dc
        CP 0x31                          ; 17df
        JP z,query_1_memory              ; 17e1
        CP 0x32                          ; 17e4
        JP z,sub_17ef                    ; 17e6
        CP 0x33                          ; 17e9
        JP z,query_3_dump                ; 17eb
        RET                              ; 17ee

sub_17ef:
        RET                              ; 17ef

; ---- query_0_romid: B4 '0': reply with 16-byte ROM ID string
query_0_romid:
        PUSH AF                          ; 17f0
        PUSH BC                          ; 17f1
        PUSH DE                          ; 17f2
        PUSH HL                          ; 17f3
        PUSH IX                          ; 17f4
        PUSH IY                          ; 17f6
        LD HL,TXBUF                      ; 17f8
        LD (HL),0x10                     ; 17fb
        INC HL                           ; 17fd
        LD DE,0x48                       ; 17fe
        LD BC,3                          ; 1801
        EX DE,HL                         ; 1804
        LDIR                             ; 1805
        LD HL,0x4b                       ; 1807
        LD BC,3                          ; 180a
        LDIR                             ; 180d
        LD HL,0x4e                       ; 180f
        LD BC,6                          ; 1812
        LDIR                             ; 1815
        LD HL,0x54                       ; 1817
        LD BC,4                          ; 181a
        LDIR                             ; 181d
        LD HL,TXBUF                      ; 181f
        CALL tx_send_frame               ; 1822
        XOR A                            ; 1825
        LD (RX_LASTCMD),A                ; 1826
        POP IY                           ; 1829
        POP IX                           ; 182b
        POP HL                           ; 182d
        POP DE                           ; 182e
        POP BC                           ; 182f
        POP AF                           ; 1830
        RET                              ; 1831

; ---- query_1_memory: B4 '1': reply with two 5-digit ASCII numbers (STORE_SIZE, free bytes)
query_1_memory:
        PUSH AF                          ; 1832
        PUSH BC                          ; 1833
        PUSH DE                          ; 1834
        PUSH HL                          ; 1835
        PUSH IX                          ; 1836
        PUSH IY                          ; 1838
        CALL store_finalize              ; 183a
        LD HL,TXBUF                      ; 183d
        LD (HL),10                       ; 1840
        INC HL                           ; 1842
        PUSH HL                          ; 1843
        POP IX                           ; 1844
        LD HL,(STORE_SIZE)               ; 1846
        CALL bin_to_dec5                 ; 1849
        PUSH IX                          ; 184c
        LD HL,(STORE_LIMIT)              ; 184e
        LD DE,(STORE_END)                ; 1851
        OR A                             ; 1855
        SBC HL,DE                        ; 1856
        POP IX                           ; 1858
        CALL bin_to_dec5                 ; 185a
        LD HL,TXBUF                      ; 185d
        CALL tx_send_frame               ; 1860
        XOR A                            ; 1863
        LD (RX_LASTCMD),A                ; 1864
        POP IY                           ; 1867
        POP IX                           ; 1869
        POP HL                           ; 186b
        POP DE                           ; 186c
        POP BC                           ; 186d
        POP AF                           ; 186e
        RET                              ; 186f

; ---- query_3_dump: B4 '3': reply B1 addr <5-digit len> <MSG_STORE up to 0xDA> <cksum of data>
query_3_dump:
        PUSH AF                          ; 1870
        PUSH BC                          ; 1871
        PUSH DE                          ; 1872
        PUSH HL                          ; 1873
        PUSH IX                          ; 1874
        PUSH IY                          ; 1876
        LD A,0xb1                        ; 1878
        CALL tx_send_byte                ; 187a
        LD A,(MY_ADDRESS)                ; 187d
        CALL tx_send_byte                ; 1880
        LD HL,(STORE_END)                ; 1883
        INC HL                           ; 1886
        LD DE,MSG_STORE                  ; 1887
        OR A                             ; 188a
        SBC HL,DE                        ; 188b
        LD IX,TXBUF                      ; 188d
        CALL bin_to_dec5                 ; 1891
        LD HL,TXBUF                      ; 1894
        LD B,5                           ; 1897

L_1899:
        LD A,(HL)                        ; 1899
        CALL tx_send_byte                ; 189a
        INC HL                           ; 189d
        DJNZ L_1899                      ; 189e
        LD HL,MSG_STORE                  ; 18a0
        LD E,0                           ; 18a3

L_18a5:
        LD A,(HL)                        ; 18a5
        ADD A,E                          ; 18a6
        LD E,A                           ; 18a7
        LD A,(HL)                        ; 18a8
        CALL tx_send_byte                ; 18a9
        LD A,(HL)                        ; 18ac
        CP 0xda                          ; 18ad
        JP z,L_18b6                      ; 18af
        INC HL                           ; 18b2
        JP L_18a5                        ; 18b3

L_18b6:
        LD A,E                           ; 18b6
        CALL tx_send_byte                ; 18b7
        XOR A                            ; 18ba
        LD (RX_LASTCMD),A                ; 18bb
        POP IY                           ; 18be
        POP IX                           ; 18c0
        POP HL                           ; 18c2
        POP DE                           ; 18c3
        POP BC                           ; 18c4
        POP AF                           ; 18c5
        RET                              ; 18c6

; ---- bin_to_dec5: HL -> 5 ASCII digits at (IX) using table 10000,1000,100,10,1
bin_to_dec5:
        LD IY,DEC_TABLE                  ; 18c7

sub_18cb:
        LD B,0x2f                        ; 18cb
        LD E,(IY+0)                      ; 18cd
        LD D,(IY+1)                      ; 18d0
        BIT 7,D                          ; 18d3
        RET nz                           ; 18d5

L_18d6:
        INC B                            ; 18d6
        OR A                             ; 18d7
        SBC HL,DE                        ; 18d8
        JR nc,L_18d6                     ; 18da
        ADD HL,DE                        ; 18dc
        LD (IX+0),B                      ; 18dd
        INC IX                           ; 18e0
        INC IY                           ; 18e2
        INC IY                           ; 18e4
        JR sub_18cb                      ; 18e6

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
        LD A,(CLK_RUN)                   ; 18f4
        AND A                            ; 18f7
        RET z                            ; 18f8
        LD A,(NMI_COUNT)                 ; 18f9
        INC A                            ; 18fc
        LD (NMI_COUNT),A                 ; 18fd
        LD HL,NMI_PER_SEC                ; 1900
        CP (HL)                          ; 1903
        RET nz                           ; 1904
        LD A,0                           ; 1905
        LD (NMI_COUNT),A                 ; 1907
        LD HL,CLK_SEC                    ; 190a
        INC (HL)                         ; 190d
        LD A,(HL)                        ; 190e
        CP 0x3c                          ; 190f
        RET nz                           ; 1911
        LD (HL),0                        ; 1912
        DEC HL                           ; 1914
        INC (HL)                         ; 1915
        LD A,(HL)                        ; 1916
        CP 10                            ; 1917
        RET nz                           ; 1919
        LD (HL),0                        ; 191a
        DEC HL                           ; 191c
        INC (HL)                         ; 191d
        LD A,(HL)                        ; 191e
        CP 6                             ; 191f
        RET nz                           ; 1921
        LD (HL),0                        ; 1922
        DEC HL                           ; 1924
        INC (HL)                         ; 1925
        LD A,(HL)                        ; 1926
        CP 10                            ; 1927
        JR nz,L_1934                     ; 1929
        LD (HL),0                        ; 192b
        DEC HL                           ; 192d
        LD A,(HL)                        ; 192e
        INC A                            ; 192f
        AND 1                            ; 1930
        LD (HL),A                        ; 1932
        RET                              ; 1933

L_1934:
        DEC HL                           ; 1934
        CP 3                             ; 1935
        JP z,L_194a                      ; 1937
        CP 2                             ; 193a
        RET nz                           ; 193c
        LD A,(HL)                        ; 193d
        AND A                            ; 193e
        RET z                            ; 193f
        LD A,(CLK_PM)                    ; 1940
        INC A                            ; 1943
        AND 1                            ; 1944
        LD (CLK_PM),A                    ; 1946
        RET                              ; 1949

L_194a:
        LD A,(HL)                        ; 194a
        AND A                            ; 194b
        RET z                            ; 194c
        XOR A                            ; 194d
        LD (HL),A                        ; 194e
        INC A                            ; 194f
        INC HL                           ; 1950
        LD (HL),A                        ; 1951
        RET                              ; 1952

; ---- demo_scroll: scroll a space 14 times (used when blanking)
demo_scroll:
        LD B,14                          ; 1953
        LD A,0                           ; 1955
        LD (FONT_MODE),A                 ; 1957

L_195a:
        LD A,0x20                        ; 195a
        LD (CUR_CHAR),A                  ; 195c
        PUSH BC                          ; 195f
        CALL sub_077a                    ; 1960
        CALL effect_step                 ; 1963
        POP BC                           ; 1966
        DJNZ L_195a                      ; 1967
        RET                              ; 1969

; ---- keypad_scan: 8x8 matrix scan: row select via CTRL_LATCH high nibble, read PORT_IN bit 3; result -> RX_BYTE
keypad_scan:
        LD L,0                           ; 196a
        LD H,0xf0                        ; 196c
        LD A,(CTRL_LATCH_SHADOW)         ; 196e
        AND 0x8f                         ; 1971
        LD E,A                           ; 1973
        LD B,8                           ; 1974

L_1976:
        LD A,H                           ; 1976
        ADD A,0x10                       ; 1977
        LD H,A                           ; 1979
        OR E                             ; 197a
        LD (CTRL_LATCH),A                ; 197b
        IN A,(PORT_IN)                   ; 197e
        BIT 3,A                          ; 1980
        JR z,L_198d                      ; 1982
        LD A,8                           ; 1984
        ADD A,L                          ; 1986
        LD L,A                           ; 1987
        DJNZ L_1976                      ; 1988
        XOR A                            ; 198a
        JR L_1994                        ; 198b

L_198d:
        AND 7                            ; 198d
        ADD A,L                          ; 198f
        JR nz,L_1994                     ; 1990
        LD A,0x1e                        ; 1992

L_1994:
        LD (RX_BYTE),A                   ; 1994
        AND A                            ; 1997
        RET                              ; 1998

; ---- clear_framebuf: FRAMEBUF (344 bytes) = 0x80
clear_framebuf:
        PUSH HL                          ; 1999
        PUSH BC                          ; 199a
        LD HL,FRAMEBUF                   ; 199b
        LD BC,0x0158                     ; 199e

L_19a1:
        LD (HL),0x80                     ; 19a1
        INC HL                           ; 19a3
        DEC BC                           ; 19a4
        LD A,C                           ; 19a5
        OR B                             ; 19a6
        JR nz,L_19a1                     ; 19a7
        POP BC                           ; 19a9
        POP HL                           ; 19aa
        RET                              ; 19ab

; ---- clear_txbuf: zero 0x56 bytes at TXBUF
clear_txbuf:
        PUSH HL                          ; 19ac
        PUSH BC                          ; 19ad
        LD HL,TXBUF                      ; 19ae
        LD B,0x56                        ; 19b1

L_19b3:
        LD (HL),0                        ; 19b3
        INC HL                           ; 19b5
        DJNZ L_19b3                      ; 19b6
        POP BC                           ; 19b8
        POP HL                           ; 19b9
        RET                              ; 19ba

; ---- clear_glyph_tmp
clear_glyph_tmp:
        PUSH HL                          ; 19bb
        PUSH BC                          ; 19bc
        LD HL,0x42d6                     ; 19bd
        LD B,0x60                        ; 19c0

L_19c2:
        LD (HL),0                        ; 19c2
        INC HL                           ; 19c4
        DJNZ L_19c2                      ; 19c5
        POP BC                           ; 19c7
        POP HL                           ; 19c8
        RET                              ; 19c9

; ---- menu_enter: Enter the on-sign editor/menu (MENU_ACTIVE=FF), SP reset
menu_enter:
        LD SP,STACK_TOP                  ; 19ca
        LD A,0xff                        ; 19cd
        LD (MENU_ACTIVE),A               ; 19cf
        EI                               ; 19d2
        CALL init_render                 ; 19d3
        XOR A                            ; 19d6
        LD (RX_BYTE),A                   ; 19d7
        LD (0x4229),A                    ; 19da
        LD (0x4226),A                    ; 19dd
        LD (0x4227),A                    ; 19e0
        LD (BEEP_TIMER),A                ; 19e3
        LD (RX_LASTCMD),A                ; 19e6
        LD (0x43d7),A                    ; 19e9
        CALL menu_getchar                ; 19ec
        PUSH AF                          ; 19ef
        LD A,0                           ; 19f0
        LD (0x43d7),A                    ; 19f2
        POP AF                           ; 19f5
        LD HL,MY_ADDRESS                 ; 19f6
        CP (HL)                          ; 19f9
        JR z,L_1a0d                      ; 19fa
        CP 0x2a                          ; 19fc
        JR z,L_1a0d                      ; 19fe
        JP RESET                         ; 1a00

; ---- key_handler: Handle a key / IR code: menu navigation (ADDRESS?, TIME?, PROG MSG?, SEQ MSG? ...)
key_handler:
        LD A,0xff                        ; 1a03
        LD (0x4358),A                    ; 1a05
        LD A,1                           ; 1a08
        LD (0x43d7),A                    ; 1a0a

L_1a0d:
        LD SP,STACK_TOP                  ; 1a0d
        LD A,0xff                        ; 1a10
        LD (MENU_ACTIVE),A               ; 1a12
        EI                               ; 1a15
        CALL init_render                 ; 1a16
        LD A,(IR_CODE)                   ; 1a19
        CP 0xa4                          ; 1a1c
        JR nz,L_1a40                     ; 1a1e
        CALL sub_0f48                    ; 1a20

L_1a23:
        LD A,0xfe                        ; 1a23
        LD (IR_CODE),A                   ; 1a25
        LD HL,0x01a0                     ; 1a28
        LD (GEN_COUNTDOWN),HL            ; 1a2b

L_1a2e:
        LD A,(IR_CODE)                   ; 1a2e
        CP 0xa4                          ; 1a31
        JR z,L_1a23                      ; 1a33
        CP 0xfe                          ; 1a35
        JR nz,L_1a40                     ; 1a37
        LD HL,(GEN_COUNTDOWN)            ; 1a39
        LD A,H                           ; 1a3c
        OR L                             ; 1a3d
        JR nz,L_1a2e                     ; 1a3e

L_1a40:
        CALL ir_init2                    ; 1a40
        XOR A                            ; 1a43
        LD (RX_BYTE),A                   ; 1a44
        LD (0x4229),A                    ; 1a47
        LD (0x4226),A                    ; 1a4a
        LD (0x4227),A                    ; 1a4d
        LD (BEEP_TIMER),A                ; 1a50
        LD (0x435a),A                    ; 1a53
        LD A,(0x420f)                    ; 1a56
        INC A                            ; 1a59
        JR nz,L_1a69                     ; 1a5a
        XOR A                            ; 1a5c
        LD (0x420f),A                    ; 1a5d
        CALL chan_select                 ; 1a60
        LD (STORE_CURSOR),HL             ; 1a63
        CALL chan_find                   ; 1a66

L_1a69:
        LD HL,(STORE_CURSOR)             ; 1a69
        LD A,(HL)                        ; 1a6c
        CP 0xd0                          ; 1a6d
        JP c,L_1a8e                      ; 1a6f
        CP 0xdb                          ; 1a72
        JP nc,L_1a8e                     ; 1a74
        DEC HL                           ; 1a77
        DEC HL                           ; 1a78
        LD A,(HL)                        ; 1a79
        CP 0xd0                          ; 1a7a
        JP c,L_1a8b                      ; 1a7c
        CP 0xdb                          ; 1a7f
        JP nc,L_1a8b                     ; 1a81
        DEC HL                           ; 1a84
        LD (STORE_CURSOR),HL             ; 1a85
        JP L_1aaf                        ; 1a88

L_1a8b:
        LD (STORE_CURSOR),HL             ; 1a8b

L_1a8e:
        PUSH HL                          ; 1a8e
        LD DE,MSG_STORE                  ; 1a8f
        OR A                             ; 1a92
        SBC HL,DE                        ; 1a93
        PUSH HL                          ; 1a95
        POP BC                           ; 1a96
        POP HL                           ; 1a97
        DEC HL                           ; 1a98

L_1a99:
        LD A,(HL)                        ; 1a99
        CP 0xd0                          ; 1a9a
        JP c,L_1aa6                      ; 1a9c
        CP 0xdb                          ; 1a9f
        JP nc,L_1aa6                     ; 1aa1
        JR L_1ab0                        ; 1aa4

L_1aa6:
        DEC HL                           ; 1aa6
        DEC BC                           ; 1aa7
        LD A,C                           ; 1aa8
        OR B                             ; 1aa9
        JR nz,L_1a99                     ; 1aaa
        JP pkt_process_end               ; 1aac

L_1aaf:
        INC HL                           ; 1aaf

L_1ab0:
        INC HL                           ; 1ab0
        LD (INS_PTR),HL                  ; 1ab1
        CALL store_finalize              ; 1ab4
        XOR A                            ; 1ab7
        LD (0x43cf),A                    ; 1ab8
        LD (0x43ca),A                    ; 1abb
        LD (0x4221),A                    ; 1abe
        LD (0x4220),A                    ; 1ac1
        LD (FB_TMP),A                    ; 1ac4
        LD (0x4241),A                    ; 1ac7
        LD (0x4224),A                    ; 1aca
        LD A,0xff                        ; 1acd
        LD (0x4392),A                    ; 1acf

; ---- editor_loop: Editor main loop: get key, dispatch
editor_loop:
        CALL editor_redraw               ; 1ad2

L_1ad5:
        CALL menu_getchar                ; 1ad5
        CALL sub_263c                    ; 1ad8
        LD A,(RX_LASTCMD)                ; 1adb
        LD (CUR_CHAR),A                  ; 1ade
        CP 0x1d                          ; 1ae1
        LD A,0                           ; 1ae3
        JR z,L_1af0                      ; 1ae5
        LD (0x4220),A                    ; 1ae7
        LD (FB_TMP),A                    ; 1aea
        LD (0x43ca),A                    ; 1aed

L_1af0:
        LD (0x4241),A                    ; 1af0
        LD A,(0x4243)                    ; 1af3
        OR A                             ; 1af6
        JP nz,L_220d                     ; 1af7
        LD A,(0x4336)                    ; 1afa
        BIT 7,A                          ; 1afd
        JP nz,L_223a                     ; 1aff
        LD A,(RX_LASTCMD)                ; 1b02
        CP 0x1f                          ; 1b05
        CALL z,sub_1b91                  ; 1b07
        XOR A                            ; 1b0a
        LD (0x4392),A                    ; 1b0b
        LD A,(RX_LASTCMD)                ; 1b0e
        CP 1                             ; 1b11
        JP z,L_1ad5                      ; 1b13
        CP 3                             ; 1b16
        JP z,L_20c4                      ; 1b18
        CP 5                             ; 1b1b
        JP z,L_2087                      ; 1b1d
        CP 0x7f                          ; 1b20
        JP z,L_2482                      ; 1b22
        CP 0x1d                          ; 1b25
        JP z,L_2465                      ; 1b27
        CP 10                            ; 1b2a
        JP z,L_24f4                      ; 1b2c
        CP 12                            ; 1b2f
        JP z,L_250f                      ; 1b31
        CP 8                             ; 1b34
        JP z,L_2522                      ; 1b36
        CP 11                            ; 1b39
        JP z,L_2552                      ; 1b3b
        CP 14                            ; 1b3e
        JP z,L_20eb                      ; 1b40
        CP 0xb6                          ; 1b43
        JP z,L_2184                      ; 1b45
        CP 0x5e                          ; 1b48
        JP z,L_1f3a                      ; 1b4a
        CP 0x1c                          ; 1b4d
        JP z,L_216c                      ; 1b4f
        CP 0x1e                          ; 1b52
        JP z,L_21b4                      ; 1b54
        CP 0x15                          ; 1b57
        JP z,L_21cc                      ; 1b59
        CP 0x16                          ; 1b5c
        JP z,L_21ec                      ; 1b5e
        CP 0x17                          ; 1b61
        JP z,L_1d01                      ; 1b63
        CP 2                             ; 1b66
        JP z,L_219c                      ; 1b68
        CP 0xb3                          ; 1b6b
        JP z,L_2046                      ; 1b6d
        CP 0xb7                          ; 1b70
        JP z,L_21e4                      ; 1b72
        CP 9                             ; 1b75
        JP z,L_220d                      ; 1b77
        CP 4                             ; 1b7a
        JP z,L_223a                      ; 1b7c
        CP 13                            ; 1b7f
        JP z,L_1c5c                      ; 1b81
        CP 0x9f                          ; 1b84
        JP z,editor_loop                 ; 1b86
        CP 0xb1                          ; 1b89
        JP z,L_1c5c                      ; 1b8b
        JP L_2580                        ; 1b8e

sub_1b91:
        LD A,(CHAN_LOCK)                 ; 1b91
        OR A                             ; 1b94
        JP nz,L_1b9d                     ; 1b95
        LD A,(0x4392)                    ; 1b98
        AND A                            ; 1b9b
        RET z                            ; 1b9c

L_1b9d:
        LD A,0                           ; 1b9d

L_1b9f:
        LD E,A                           ; 1b9f
        PUSH DE                          ; 1ba0
        CALL chan_select                 ; 1ba1
        POP DE                           ; 1ba4
        AND A                            ; 1ba5
        JP nz,pkt_process_end            ; 1ba6
        LD A,(HL)                        ; 1ba9
        CP 3                             ; 1baa
        JR z,L_1c12                      ; 1bac
        LD B,0                           ; 1bae
        LD C,A                           ; 1bb0
        LD IX,0x372d                     ; 1bb1
        ADD IX,BC                        ; 1bb5
        BIT 1,(IX+0)                     ; 1bb7
        JR z,L_1bd8                      ; 1bbb

L_1bbd:
        INC HL                           ; 1bbd
        LD A,(HL)                        ; 1bbe
        CP 3                             ; 1bbf
        JR nz,L_1bc7                     ; 1bc1
        LD A,E                           ; 1bc3
        JP L_1bf2                        ; 1bc4

L_1bc7:
        LD B,0                           ; 1bc7
        LD C,A                           ; 1bc9
        LD IX,0x372d                     ; 1bca
        ADD IX,BC                        ; 1bce
        BIT 1,(IX+0)                     ; 1bd0
        JR z,L_1bd8                      ; 1bd4
        JR L_1bbd                        ; 1bd6

L_1bd8:
        LD A,E                           ; 1bd8
        INC A                            ; 1bd9
        CP 0x64                          ; 1bda
        JR nz,L_1b9f                     ; 1bdc
        CALL init_render                 ; 1bde
        LD HL,(FB_COL)                   ; 1be1
        LD (FB_COLPTR),HL                ; 1be4

L_1be7:
        LD HL,0x2ffe                     ; 1be7
        CALL sub_1e32                    ; 1bea
        CP 0x64                          ; 1bed
        JP nc,L_1be7                     ; 1bef

L_1bf2:
        LD (0x438f),A                    ; 1bf2
        CALL chan_select                 ; 1bf5
        AND A                            ; 1bf8
        JP nz,pkt_process_end            ; 1bf9
        LD (INS_PTR),HL                  ; 1bfc
        DEC HL                           ; 1bff
        LD (STORE_CURSOR),HL             ; 1c00
        CALL sub_20f8                    ; 1c03
        LD A,0x1f                        ; 1c06
        LD (RX_LASTCMD),A                ; 1c08
        LD A,(0x438f)                    ; 1c0b
        LD E,A                           ; 1c0e
        JP L_1c1a                        ; 1c0f

L_1c12:
        LD (INS_PTR),HL                  ; 1c12
        DEC HL                           ; 1c15
        DEC HL                           ; 1c16
        LD (STORE_CURSOR),HL             ; 1c17

L_1c1a:
        PUSH DE                          ; 1c1a
        CALL chan_find                   ; 1c1b
        POP DE                           ; 1c1e
        LD A,E                           ; 1c1f
        CP 0x64                          ; 1c20
        JR nz,L_1c27                     ; 1c22
        LD (CHAN_LOCK),A                 ; 1c24

L_1c27:
        LD HL,SEQ_LIST                   ; 1c27
        LD (HL),E                        ; 1c2a
        INC HL                           ; 1c2b
        LD B,0x67                        ; 1c2c

L_1c2e:
        LD (HL),0xff                     ; 1c2e
        INC HL                           ; 1c30
        DJNZ L_1c2e                      ; 1c31
        LD A,E                           ; 1c33
        LD (0x4399),A                    ; 1c34
        RET                              ; 1c37

; ---- store_finalize: Fix up MSG_STORE terminators after an edit
store_finalize:
        LD A,0xda                        ; 1c38
        LD HL,MSG_STORE                  ; 1c3a
        LD BC,(STORE_SIZE)               ; 1c3d
        INC BC                           ; 1c41
        CPIR                             ; 1c42
        LD A,B                           ; 1c44
        OR C                             ; 1c45
        JP z,pkt_process_end             ; 1c46
        DEC HL                           ; 1c49
        LD (STORE_END),HL                ; 1c4a
        RET                              ; 1c4d

L_1c4e:
        LD A,0xff                        ; 1c4e
        LD (0x4224),A                    ; 1c50
        LD HL,0x3046                     ; 1c53
        LD (0x420a),HL                   ; 1c56
        JP editor_loop                   ; 1c59

L_1c5c:
        XOR A                            ; 1c5c
        LD (0x4336),A                    ; 1c5d
        LD (0x4243),A                    ; 1c60
        LD A,(0x43d7)                    ; 1c63
        AND A                            ; 1c66
        JR z,L_1c6f                      ; 1c67
        CALL tx_send_byte                ; 1c69
        JP L_1c9f                        ; 1c6c

L_1c6f:
        LD A,(IR_CODE)                   ; 1c6f
        CP 0xbe                          ; 1c72
        JR z,L_1c9f                      ; 1c74
        CP 0xa4                          ; 1c76
        JR z,L_1c7e                      ; 1c78
        CP 0xaf                          ; 1c7a
        JR nz,L_1c6f                     ; 1c7c

L_1c7e:
        LD A,0xff                        ; 1c7e
        LD (IR_CODE),A                   ; 1c80
        LD HL,0x028a                     ; 1c83
        LD (GEN_COUNTDOWN),HL            ; 1c86

L_1c89:
        LD A,(IR_CODE)                   ; 1c89
        CP 0xa4                          ; 1c8c
        JR z,L_1c7e                      ; 1c8e
        CP 0xaf                          ; 1c90
        JR z,L_1c7e                      ; 1c92
        CP 0xff                          ; 1c94
        JR nz,L_1c9f                     ; 1c96
        LD HL,(GEN_COUNTDOWN)            ; 1c98
        LD A,H                           ; 1c9b
        OR L                             ; 1c9c
        JR nz,L_1c89                     ; 1c9d

L_1c9f:
        LD A,0xff                        ; 1c9f
        LD (MENU_FLAG),A                 ; 1ca1
        LD A,(0x435a)                    ; 1ca4
        AND A                            ; 1ca7
        JP nz,L_1cee                     ; 1ca8
        LD HL,(INS_PTR)                  ; 1cab
        DEC HL                           ; 1cae
        DEC HL                           ; 1caf
        LD B,2                           ; 1cb0
        CALL ascii_dec_to_bin            ; 1cb2
        LD E,A                           ; 1cb5
        LD HL,SEQ_LIST                   ; 1cb6
        CP (HL)                          ; 1cb9
        JP z,L_1cee                      ; 1cba
        LD A,0x64                        ; 1cbd
        CP (HL)                          ; 1cbf
        JP nz,L_1cc7                     ; 1cc0
        LD A,E                           ; 1cc3
        JP L_1ce3                        ; 1cc4

L_1cc7:
        LD B,0x68                        ; 1cc7

L_1cc9:
        LD A,(HL)                        ; 1cc9
        CP E                             ; 1cca
        JP z,L_1cea                      ; 1ccb
        CP 0xff                          ; 1cce
        JR z,L_1cd5                      ; 1cd0
        INC HL                           ; 1cd2
        DJNZ L_1cc9                      ; 1cd3

L_1cd5:
        LD A,E                           ; 1cd5
        LD HL,0x42d1                     ; 1cd6
        LD (HL),0xff                     ; 1cd9
        LD DE,0x42d2                     ; 1cdb
        LD BC,0x67                       ; 1cde
        LDDR                             ; 1ce1

L_1ce3:
        LD HL,SEQ_LIST                   ; 1ce3
        LD (HL),A                        ; 1ce6
        JP L_1cee                        ; 1ce7

L_1cea:
        LD E,A                           ; 1cea
        LD (MENU_FLAG),A                 ; 1ceb

L_1cee:
        LD SP,STACK_TOP                  ; 1cee
        XOR A                            ; 1cf1
        LD (MENU_ACTIVE),A               ; 1cf2
        LD (0x433b),A                    ; 1cf5
        LD HL,SEQ_LIST                   ; 1cf8
        LD (SEQ_PTR),HL                  ; 1cfb
        JP L_000f                        ; 1cfe

L_1d01:
        CALL init_render                 ; 1d01
        LD HL,(FB_COL)                   ; 1d04
        LD (FB_COLPTR),HL                ; 1d07
        LD HL,0x301a                     ; 1d0a
        LD (MENU_TEXT_PTR),HL            ; 1d0d
        CALL menu_show_text              ; 1d10
        XOR A                            ; 1d13
        LD (CLK_RUN),A                   ; 1d14
        LD HL,CLK_H10                    ; 1d17
        LD B,4                           ; 1d1a

L_1d1c:
        PUSH BC                          ; 1d1c
        PUSH HL                          ; 1d1d

L_1d1e:
        CALL menu_getchar                ; 1d1e
        LD (CUR_CHAR),A                  ; 1d21
        CP 0x3a                          ; 1d24
        JR nc,L_1d1e                     ; 1d26
        CP 0x30                          ; 1d28
        JR c,L_1d1e                      ; 1d2a
        PUSH AF                          ; 1d2c
        CALL glyph_lookup                ; 1d2d
        POP AF                           ; 1d30
        AND 15                           ; 1d31
        POP HL                           ; 1d33
        LD (HL),A                        ; 1d34
        INC HL                           ; 1d35
        POP BC                           ; 1d36
        DJNZ L_1d1c                      ; 1d37
        LD A,(CLK_H10)                   ; 1d39
        AND 1                            ; 1d3c
        LD (CLK_H10),A                   ; 1d3e
        OR A                             ; 1d41
        JR z,L_1d50                      ; 1d42
        LD A,(CLK_H1)                    ; 1d44
        CP 3                             ; 1d47
        JR c,L_1d50                      ; 1d49
        LD A,2                           ; 1d4b
        LD (CLK_H1),A                    ; 1d4d

L_1d50:
        LD A,0x50                        ; 1d50
        LD (0x4244),A                    ; 1d52

L_1d55:
        LD A,(0x4244)                    ; 1d55
        AND A                            ; 1d58
        JR nz,L_1d55                     ; 1d59
        CALL init_render                 ; 1d5b
        LD HL,(FB_COL)                   ; 1d5e
        LD (FB_COLPTR),HL                ; 1d61
        LD HL,0x3025                     ; 1d64
        LD (MENU_TEXT_PTR),HL            ; 1d67
        CALL menu_show_text              ; 1d6a

L_1d6d:
        CALL menu_getchar                ; 1d6d
        RES 5,A                          ; 1d70
        CP 0x59                          ; 1d72
        JR nz,L_1d7a                     ; 1d74
        LD A,0                           ; 1d76
        JR L_1d80                        ; 1d78

L_1d7a:
        CP 0x4e                          ; 1d7a
        JR nz,L_1d6d                     ; 1d7c
        LD A,0xff                        ; 1d7e

L_1d80:
        LD (CLK_PM),A                    ; 1d80
        LD A,0                           ; 1d83
        LD (NMI_COUNT),A                 ; 1d85
        LD A,0xff                        ; 1d88
        LD (CLK_RUN),A                   ; 1d8a
        JP L_206a                        ; 1d8d

L_1d90:
        LD A,(MENU_ACTIVE)               ; 1d90
        AND A                            ; 1d93
        JP nz,glyph_lookup               ; 1d94
        LD A,(PAUSE_FLAG)                ; 1d97
        AND A                            ; 1d9a
        JR z,L_1da2                      ; 1d9b
        LD HL,FONT_MODE                  ; 1d9d
        RES 2,(HL)                       ; 1da0

L_1da2:
        LD A,(0x4213)                    ; 1da2
        LD HL,(0x4214)                   ; 1da5
        AND A                            ; 1da8
        JR nz,L_1dc2                     ; 1da9
        LD HL,CLK_H10                    ; 1dab
        LD A,(HL)                        ; 1dae
        AND A                            ; 1daf
        LD A,(0x4213)                    ; 1db0
        JR nz,L_1dc2                     ; 1db3
        LD A,(0x4213)                    ; 1db5
        INC A                            ; 1db8
        LD (0x4213),A                    ; 1db9
        INC HL                           ; 1dbc
        LD (0x4214),HL                   ; 1dbd
        JR L_1d90                        ; 1dc0

L_1dc2:
        INC A                            ; 1dc2
        LD (0x4213),A                    ; 1dc3
        CP 3                             ; 1dc6
        JR nz,L_1dd2                     ; 1dc8
        LD A,0x3a                        ; 1dca
        LD (CUR_CHAR),A                  ; 1dcc
        JP L_1e0c                        ; 1dcf

L_1dd2:
        CP 6                             ; 1dd2
        JR nz,L_1dde                     ; 1dd4
        LD A,0x20                        ; 1dd6
        LD (CUR_CHAR),A                  ; 1dd8
        JP L_1e0c                        ; 1ddb

L_1dde:
        CP 7                             ; 1dde
        JR nz,L_1df2                     ; 1de0
        LD A,(CLK_PM)                    ; 1de2
        AND 1                            ; 1de5
        LD A,0x41                        ; 1de7
        JR z,L_1ded                      ; 1de9
        LD A,0x50                        ; 1deb

L_1ded:
        LD (CUR_CHAR),A                  ; 1ded
        JR L_1e0c                        ; 1df0

L_1df2:
        CP 8                             ; 1df2
        JR nz,L_1dfd                     ; 1df4
        LD A,0x4d                        ; 1df6
        LD (CUR_CHAR),A                  ; 1df8
        JR L_1e1a                        ; 1dfb

L_1dfd:
        LD A,(HL)                        ; 1dfd
        AND 15                           ; 1dfe
        OR 0x30                          ; 1e00
        LD (CUR_CHAR),A                  ; 1e02
        INC HL                           ; 1e05
        LD A,(0x4213)                    ; 1e06
        LD (0x4214),HL                   ; 1e09

L_1e0c:
        CALL sub_0cea                    ; 1e0c
        LD A,(CUR_CHAR)                  ; 1e0f
        JP glyph_lookup                  ; 1e12
        LD A,0x20                        ; 1e15
        LD (CUR_CHAR),A                  ; 1e17

L_1e1a:
        LD A,0xff                        ; 1e1a
        LD (0x4213),A                    ; 1e1c
        LD A,(CUR_CHAR)                  ; 1e1f
        JP glyph_lookup                  ; 1e22

sub_1e25:
        PUSH AF                          ; 1e25
        PUSH BC                          ; 1e26
        PUSH DE                          ; 1e27
        PUSH HL                          ; 1e28
        PUSH IX                          ; 1e29
        PUSH IY                          ; 1e2b
        LD (0x43d4),HL                   ; 1e2d
        JR L_1e40                        ; 1e30

sub_1e32:
        PUSH AF                          ; 1e32
        PUSH BC                          ; 1e33
        PUSH DE                          ; 1e34
        PUSH HL                          ; 1e35
        PUSH IX                          ; 1e36
        PUSH IY                          ; 1e38
        LD (0x43d4),HL                   ; 1e3a
        JP L_1f14                        ; 1e3d

L_1e40:
        LD HL,(INS_PTR)                  ; 1e40
        DEC HL                           ; 1e43
        LD A,(HL)                        ; 1e44
        CP 0xda                          ; 1e45
        JR nz,L_1e4d                     ; 1e47
        LD A,0x44                        ; 1e49
        JR L_1e51                        ; 1e4b

L_1e4d:
        AND 15                           ; 1e4d
        OR 0x30                          ; 1e4f

L_1e51:
        LD (CHAN_D1),A                   ; 1e51
        DEC HL                           ; 1e54
        LD A,(HL)                        ; 1e55
        CP 0xda                          ; 1e56
        JR nz,L_1e5e                     ; 1e58
        LD A,0x44                        ; 1e5a
        JR L_1e62                        ; 1e5c

L_1e5e:
        AND 15                           ; 1e5e
        OR 0x30                          ; 1e60

L_1e62:
        LD (CHAN_D10),A                  ; 1e62

L_1e65:
        CALL init_render                 ; 1e65
        LD HL,(FB_COL)                   ; 1e68
        LD (FB_COLPTR),HL                ; 1e6b
        LD HL,(0x43d4)                   ; 1e6e
        LD (MENU_TEXT_PTR),HL            ; 1e71
        CALL menu_show_text              ; 1e74
        LD B,2                           ; 1e77
        LD HL,CHAN_D10                   ; 1e79

L_1e7c:
        LD A,(HL)                        ; 1e7c
        LD (CUR_CHAR),A                  ; 1e7d
        PUSH HL                          ; 1e80
        PUSH BC                          ; 1e81
        CALL glyph_lookup                ; 1e82
        POP BC                           ; 1e85
        POP HL                           ; 1e86
        INC HL                           ; 1e87
        DJNZ L_1e7c                      ; 1e88

L_1e8a:
        CALL menu_getchar                ; 1e8a
        LD (CUR_CHAR),A                  ; 1e8d
        CP 4                             ; 1e90
        JP z,L_1f32                      ; 1e92
        CP 8                             ; 1e95
        JR z,L_1eeb                      ; 1e97
        CP 9                             ; 1e99
        JR z,L_1eeb                      ; 1e9b
        CP 13                            ; 1e9d
        JR z,L_1f1f                      ; 1e9f
        CP 14                            ; 1ea1
        JR z,L_1f14                      ; 1ea3
        CP 0x1f                          ; 1ea5
        JP z,L_1f36                      ; 1ea7
        CP 0x7f                          ; 1eaa
        JR z,L_1eda                      ; 1eac
        CP 0x41                          ; 1eae
        JR z,L_1f2a                      ; 1eb0
        CP 0x61                          ; 1eb2
        JR z,L_1f2a                      ; 1eb4
        CP 0x44                          ; 1eb6
        JR z,L_1f2e                      ; 1eb8
        CP 0x64                          ; 1eba
        JR z,L_1f2e                      ; 1ebc
        LD A,(CUR_CHAR)                  ; 1ebe
        CALL is_digit                    ; 1ec1
        JP nc,L_1e8a                     ; 1ec4
        LD IX,CHAN_D10                   ; 1ec7
        LD A,(IX+1)                      ; 1ecb
        LD (IX+0),A                      ; 1ece
        LD A,(CUR_CHAR)                  ; 1ed1
        LD (IX+1),A                      ; 1ed4
        JP L_1e65                        ; 1ed7

L_1eda:
        LD IX,CHAN_D10                   ; 1eda
        LD A,(IX+0)                      ; 1ede
        LD (IX+1),A                      ; 1ee1
        LD (IX+0),0x30                   ; 1ee4
        JP L_1e65                        ; 1ee8

L_1eeb:
        LD A,(CHAN_D10)                  ; 1eeb
        OR 0x20                          ; 1eee
        CP 0x64                          ; 1ef0
        JR z,L_1f2e                      ; 1ef2
        LD A,(CHAN_D1)                   ; 1ef4
        OR 0x20                          ; 1ef7
        CP 0x64                          ; 1ef9
        JR z,L_1f2e                      ; 1efb
        LD B,2                           ; 1efd
        LD HL,CHAN_D10                   ; 1eff
        CALL ascii_dec_to_bin            ; 1f02

L_1f05:
        LD (0x43d2),A                    ; 1f05
        POP IY                           ; 1f08
        POP IX                           ; 1f0a
        POP HL                           ; 1f0c
        POP DE                           ; 1f0d
        POP BC                           ; 1f0e
        POP AF                           ; 1f0f
        LD A,(0x43d2)                    ; 1f10
        RET                              ; 1f13

L_1f14:
        LD A,0x20                        ; 1f14
        LD (CHAN_D10),A                  ; 1f16
        LD (CHAN_D1),A                   ; 1f19
        JP L_1e65                        ; 1f1c

L_1f1f:
        LD A,(CHAN_D1)                   ; 1f1f
        CP 0x20                          ; 1f22
        JR nz,L_1eeb                     ; 1f24
        LD A,0x9a                        ; 1f26
        JR L_1f05                        ; 1f28

L_1f2a:
        LD A,0x99                        ; 1f2a
        JR L_1f05                        ; 1f2c

L_1f2e:
        LD A,0x64                        ; 1f2e
        JR L_1f05                        ; 1f30

L_1f32:
        LD A,0x97                        ; 1f32
        JR L_1f05                        ; 1f34

L_1f36:
        LD A,0x98                        ; 1f36
        JR L_1f05                        ; 1f38

L_1f3a:
        CALL init_render                 ; 1f3a
        LD HL,(FB_COL)                   ; 1f3d
        LD (FB_COLPTR),HL                ; 1f40
        LD HL,MENU_STRINGS               ; 1f43
        LD (MENU_TEXT_PTR),HL            ; 1f46
        CALL menu_show_text              ; 1f49
        LD H,0                           ; 1f4c
        LD A,(MY_ADDRESS)                ; 1f4e
        CP 0                             ; 1f51
        JR z,L_1f59                      ; 1f53
        CP 0x2a                          ; 1f55
        JR nz,L_1f5b                     ; 1f57

L_1f59:
        LD A,1                           ; 1f59

L_1f5b:
        LD L,A                           ; 1f5b
        LD IX,MENU_ENTRY_BUF             ; 1f5c
        LD IY,0x18ec                     ; 1f60
        CALL sub_18cb                    ; 1f64
        LD HL,MENU_ENTRY_BUF             ; 1f67
        LD B,3                           ; 1f6a

L_1f6c:
        LD A,(HL)                        ; 1f6c
        CP 0x30                          ; 1f6d
        JR nz,L_1f79                     ; 1f6f
        LD A,B                           ; 1f71
        CP 1                             ; 1f72
        JR z,L_1f79                      ; 1f74
        INC HL                           ; 1f76
        DJNZ L_1f6c                      ; 1f77

L_1f79:
        LD A,(HL)                        ; 1f79
        CALL is_digit                    ; 1f7a
        JP c,L_1f83                      ; 1f7d
        LD A,0x30                        ; 1f80
        LD (HL),A                        ; 1f82

L_1f83:
        LD (CUR_CHAR),A                  ; 1f83
        PUSH HL                          ; 1f86
        PUSH BC                          ; 1f87
        CALL glyph_lookup                ; 1f88
        POP BC                           ; 1f8b
        POP HL                           ; 1f8c
        INC HL                           ; 1f8d
        DJNZ L_1f79                      ; 1f8e
        LD HL,MENU_ENTRY_BUF             ; 1f90
        LD B,0                           ; 1f93
        PUSH HL                          ; 1f95
        PUSH BC                          ; 1f96

L_1f97:
        CALL menu_getchar                ; 1f97
        LD (CUR_CHAR),A                  ; 1f9a
        POP BC                           ; 1f9d
        POP HL                           ; 1f9e
        CP 8                             ; 1f9f
        JR z,L_1fd8                      ; 1fa1
        CP 13                            ; 1fa3
        JR z,L_1fd8                      ; 1fa5
        LD A,B                           ; 1fa7
        CP 3                             ; 1fa8
        JP z,menu_addr_invalid           ; 1faa
        INC B                            ; 1fad
        LD A,(CUR_CHAR)                  ; 1fae
        CALL is_digit                    ; 1fb1
        JP nc,menu_addr_invalid          ; 1fb4
        LD (HL),A                        ; 1fb7
        INC HL                           ; 1fb8
        PUSH HL                          ; 1fb9
        PUSH BC                          ; 1fba
        LD A,B                           ; 1fbb
        CP 1                             ; 1fbc
        JR nz,L_1fd2                     ; 1fbe
        CALL clear_framebuf              ; 1fc0
        LD HL,(FB_COL)                   ; 1fc3
        LD (FB_COLPTR),HL                ; 1fc6
        LD HL,MENU_STRINGS               ; 1fc9
        LD (MENU_TEXT_PTR),HL            ; 1fcc
        CALL menu_show_text              ; 1fcf

L_1fd2:
        CALL glyph_lookup                ; 1fd2
        JP L_1f97                        ; 1fd5

L_1fd8:
        LD A,B                           ; 1fd8
        CP 0                             ; 1fd9
        JR nz,L_1fdf                     ; 1fdb
        LD B,3                           ; 1fdd

L_1fdf:
        LD HL,MENU_ENTRY_BUF             ; 1fdf
        CALL ascii_dec_to_bin            ; 1fe2
        JP c,menu_addr_invalid           ; 1fe5
        CP 0x2a                          ; 1fe8
        JP z,menu_addr_invalid           ; 1fea
        CP 0                             ; 1fed
        JP z,menu_addr_invalid           ; 1fef
        LD (MY_ADDRESS),A                ; 1ff2
        CPL                              ; 1ff5
        LD (MY_ADDRESS_INV),A            ; 1ff6
        JP L_2173                        ; 1ff9

; ---- ascii_dec_to_bin: Convert B ASCII digits at (HL) to binary in A (C set if invalid)
ascii_dec_to_bin:
        PUSH BC                          ; 1ffc
        LD IX,0x2026                     ; 1ffd
        DEC B                            ; 2001
        LD E,B                           ; 2002
        LD D,0                           ; 2003
        ADD IX,DE                        ; 2005
        XOR A                            ; 2007
        POP BC                           ; 2008

L_2009:
        PUSH BC                          ; 2009
        LD E,A                           ; 200a
        LD A,(HL)                        ; 200b
        AND 15                           ; 200c
        LD B,A                           ; 200e
        CP 0                             ; 200f
        LD A,E                           ; 2011
        JR z,L_201b                      ; 2012

L_2014:
        ADD A,(IX+0)                     ; 2014
        JR c,L_2023                      ; 2017
        DJNZ L_2014                      ; 2019

L_201b:
        INC HL                           ; 201b
        DEC IX                           ; 201c
        POP BC                           ; 201e
        DJNZ L_2009                      ; 201f
        OR A                             ; 2021
        RET                              ; 2022

L_2023:
        POP BC                           ; 2023
        SCF                              ; 2024
        RET                              ; 2025
        db 0x01,0x0a,"d"   ; 2026

; ---- is_digit: C set if A is ASCII 0-9
is_digit:
        CP 0x3a                          ; 2029
        JR nc,L_2033                     ; 202b
        CP 0x30                          ; 202d
        JR c,L_2033                      ; 202f
        SCF                              ; 2031
        RET                              ; 2032

L_2033:
        OR A                             ; 2033
        RET                              ; 2034

; ---- menu_addr_invalid
menu_addr_invalid:
        LD A,0xff                        ; 2035
        LD (0x4224),A                    ; 2037
        LD HL,0x3046                     ; 203a
        LD (0x420a),HL                   ; 203d
        CALL editor_redraw               ; 2040
        JP L_1f3a                        ; 2043

L_2046:
        LD HL,(STORE_CURSOR)             ; 2046

L_2049:
        LD A,(HL)                        ; 2049
        CP 3                             ; 204a
        JR z,L_2051                      ; 204c
        INC HL                           ; 204e
        JR L_2049                        ; 204f

L_2051:
        DEC HL                           ; 2051
        LD (STORE_CURSOR),HL             ; 2052
        LD HL,(STORE_CURSOR)             ; 2055
        LD A,(HL)                        ; 2058
        CP 0xd0                          ; 2059
        JP c,editor_loop                 ; 205b
        CP 0xdb                          ; 205e
        JP nc,editor_loop                ; 2060
        DEC HL                           ; 2063
        LD (STORE_CURSOR),HL             ; 2064
        JP L_2087                        ; 2067

L_206a:
        LD HL,(STORE_CURSOR)             ; 206a
        LD A,(HL)                        ; 206d
        CP 0xd0                          ; 206e
        JP c,editor_loop                 ; 2070
        CP 0xdb                          ; 2073
        JP nc,editor_loop                ; 2075
        JP L_2087                        ; 2078

; ---- data 207b-2086: 
STR_TOP_OF_MSG:
        db "TOP OF MSG ",0x00   ; 207b

L_2087:
        CALL init_render                 ; 2087
        LD HL,(FB_COL)                   ; 208a
        LD (FB_COLPTR),HL                ; 208d
        LD HL,STR_TOP_OF_MSG             ; 2090
        LD (MENU_TEXT_PTR),HL            ; 2093
        CALL menu_show_text              ; 2096
        LD B,2                           ; 2099
        LD HL,(STORE_CURSOR)             ; 209b

L_209e:
        LD A,(HL)                        ; 209e
        CP 0xda                          ; 209f
        JR nz,L_20a7                     ; 20a1
        LD A,0x44                        ; 20a3
        JR L_20b4                        ; 20a5

L_20a7:
        AND 15                           ; 20a7
        OR 0x30                          ; 20a9
        CALL is_digit                    ; 20ab
        JP c,L_20b4                      ; 20ae
        LD A,0x30                        ; 20b1
        LD (HL),A                        ; 20b3

L_20b4:
        LD (CUR_CHAR),A                  ; 20b4
        PUSH HL                          ; 20b7
        PUSH BC                          ; 20b8
        CALL glyph_lookup                ; 20b9
        POP BC                           ; 20bc
        POP HL                           ; 20bd
        INC HL                           ; 20be
        DJNZ L_209e                      ; 20bf
        JP L_1ad5                        ; 20c1

L_20c4:
        CALL init_render                 ; 20c4
        LD HL,(FB_COL)                   ; 20c7
        LD (FB_COLPTR),HL                ; 20ca
        LD HL,0x300d                     ; 20cd
        LD (MENU_TEXT_PTR),HL            ; 20d0
        CALL menu_show_text              ; 20d3
        CALL menu_getchar                ; 20d6
        AND 0x5f                         ; 20d9
        CP 0x59                          ; 20db
        JP nz,editor_loop                ; 20dd
        CALL store_clear_all             ; 20e0
        CALL store_finalize              ; 20e3
        LD A,0                           ; 20e6
        JP L_2219                        ; 20e8

L_20eb:
        LD A,(CHAN_LOCK)                 ; 20eb
        OR A                             ; 20ee
        JP nz,L_206a                     ; 20ef
        CALL sub_20f8                    ; 20f2
        JP L_2087                        ; 20f5

sub_20f8:
        LD HL,(STORE_CURSOR)             ; 20f8
        LD DE,MSG_STORE                  ; 20fb
        OR A                             ; 20fe
        SBC HL,DE                        ; 20ff
        PUSH HL                          ; 2101
        POP BC                           ; 2102
        CP 0xd0                          ; 2103
        LD HL,(STORE_CURSOR)             ; 2105

L_2108:
        LD A,(HL)                        ; 2108
        CP 0xd0                          ; 2109
        JP c,L_2115                      ; 210b
        CP 0xdb                          ; 210e
        JP nc,L_2115                     ; 2110
        JR L_211f                        ; 2113

L_2115:
        DEC HL                           ; 2115
        DEC BC                           ; 2116
        LD A,B                           ; 2117
        OR C                             ; 2118
        JP z,pkt_process_end             ; 2119
        JP L_2108                        ; 211c

L_211f:
        INC HL                           ; 211f
        LD A,(HL)                        ; 2120
        CP 0xd0                          ; 2121
        JP c,L_212d                      ; 2123
        CP 0xdb                          ; 2126
        JP nc,L_212d                     ; 2128
        JR L_212e                        ; 212b

L_212d:
        DEC HL                           ; 212d

L_212e:
        LD (STORE_CURSOR),HL             ; 212e
        INC HL                           ; 2131
        LD (MOVE_DST),HL                 ; 2132
        EX DE,HL                         ; 2135
        LD HL,(STORE_LIMIT)              ; 2136
        OR A                             ; 2139
        SBC HL,DE                        ; 213a
        PUSH HL                          ; 213c
        POP BC                           ; 213d
        INC BC                           ; 213e
        EX DE,HL                         ; 213f
        LD A,3                           ; 2140
        CPIR                             ; 2142
        LD A,B                           ; 2144
        OR C                             ; 2145
        JP z,pkt_process_end             ; 2146
        DEC HL                           ; 2149
        LD (MOVE_SRC),HL                 ; 214a
        LD DE,(STORE_LIMIT)              ; 214d
        EX DE,HL                         ; 2151
        OR A                             ; 2152
        SBC HL,DE                        ; 2153
        LD B,H                           ; 2155
        LD C,L                           ; 2156
        INC BC                           ; 2157
        LD HL,(MOVE_SRC)                 ; 2158
        LD DE,(MOVE_DST)                 ; 215b
        LDIR                             ; 215f
        CALL store_finalize              ; 2161
        LD HL,(STORE_CURSOR)             ; 2164
        DEC HL                           ; 2167
        LD (STORE_CURSOR),HL             ; 2168
        RET                              ; 216b

L_216c:
        LD A,(0x4358)                    ; 216c
        CPL                              ; 216f
        LD (0x4358),A                    ; 2170

L_2173:
        LD HL,(STORE_CURSOR)             ; 2173
        LD A,(HL)                        ; 2176
        CP 0xd0                          ; 2177
        JP c,editor_loop                 ; 2179
        CP 0xdb                          ; 217c
        JP nc,editor_loop                ; 217e
        JP L_2087                        ; 2181

L_2184:
        LD A,(0x4364)                    ; 2184
        CPL                              ; 2187
        LD (0x4364),A                    ; 2188
        LD HL,(STORE_CURSOR)             ; 218b
        LD A,(HL)                        ; 218e
        CP 0xd0                          ; 218f
        JP c,editor_loop                 ; 2191
        CP 0xdb                          ; 2194
        JP nc,editor_loop                ; 2196
        JP L_2087                        ; 2199

L_219c:
        LD HL,(STORE_CURSOR)             ; 219c
        LD A,(HL)                        ; 219f
        CP 3                             ; 21a0
        JP z,editor_loop                 ; 21a2
        LD A,(CHAN_LOCK)                 ; 21a5
        OR A                             ; 21a8
        JP nz,L_1c4e                     ; 21a9
        LD A,0xff                        ; 21ac
        LD (0x43cf),A                    ; 21ae
        JP editor_loop                   ; 21b1

L_21b4:
        LD HL,(STORE_CURSOR)             ; 21b4
        LD A,(HL)                        ; 21b7
        CP 3                             ; 21b8
        JP z,editor_loop                 ; 21ba
        LD A,(CHAN_LOCK)                 ; 21bd
        OR A                             ; 21c0
        JP nz,L_1c4e                     ; 21c1
        LD A,0xff                        ; 21c4
        LD (0x4221),A                    ; 21c6
        JP editor_loop                   ; 21c9

L_21cc:
        LD HL,(STORE_CURSOR)             ; 21cc
        LD A,(HL)                        ; 21cf
        CP 3                             ; 21d0
        JP z,editor_loop                 ; 21d2
        LD A,(CHAN_LOCK)                 ; 21d5
        OR A                             ; 21d8
        JP nz,L_1c4e                     ; 21d9
        LD A,0xff                        ; 21dc
        LD (0x4220),A                    ; 21de
        JP editor_loop                   ; 21e1

L_21e4:
        LD A,0xff                        ; 21e4
        LD (0x43ca),A                    ; 21e6
        JP editor_loop                   ; 21e9

L_21ec:
        LD HL,(STORE_CURSOR)             ; 21ec
        LD A,(HL)                        ; 21ef
        CP 3                             ; 21f0
        JP z,editor_loop                 ; 21f2
        LD A,(CHAN_LOCK)                 ; 21f5
        OR A                             ; 21f8
        JP nz,L_1c4e                     ; 21f9
        LD A,0xff                        ; 21fc
        LD (FB_TMP),A                    ; 21fe
        JP editor_loop                   ; 2201
        CP 0x30                          ; 2204
        JR nz,L_220b                     ; 2206
        LD A,0x39                        ; 2208
        RET                              ; 220a

L_220b:
        DEC A                            ; 220b
        RET                              ; 220c

L_220d:
        LD HL,0x302f                     ; 220d
        CALL sub_1e25                    ; 2210
        CP 0x65                          ; 2213
        JP nc,L_220d                     ; 2215
        LD E,A                           ; 2218

L_2219:
        PUSH DE                          ; 2219
        CALL chan_select                 ; 221a
        POP DE                           ; 221d
        OR A                             ; 221e
        JP nz,pkt_process_end            ; 221f
        LD (INS_PTR),HL                  ; 2222
        DEC HL                           ; 2225
        DEC HL                           ; 2226
        LD (STORE_CURSOR),HL             ; 2227
        PUSH DE                          ; 222a
        CALL chan_find                   ; 222b
        POP DE                           ; 222e
        LD A,E                           ; 222f
        CP 0x64                          ; 2230
        JR nz,L_2237                     ; 2232
        LD (CHAN_LOCK),A                 ; 2234

L_2237:
        JP L_2087                        ; 2237

L_223a:
        LD A,0xff                        ; 223a
        LD (0x435a),A                    ; 223c
        LD HL,SEQ_LIST                   ; 223f
        LD B,0x68                        ; 2242
        LD A,0xff                        ; 2244

L_2246:
        LD (HL),A                        ; 2246
        INC HL                           ; 2247
        DJNZ L_2246                      ; 2248
        LD (0x4336),A                    ; 224a
        LD HL,SEQ_LIST                   ; 224d
        LD (SEQ_PTR),HL                  ; 2250
        LD B,0x67                        ; 2253

L_2255:
        PUSH BC                          ; 2255
        LD HL,0x303b                     ; 2256
        LD A,B                           ; 2259
        CP 0x67                          ; 225a
        JR z,L_2263                      ; 225c
        CALL sub_1e32                    ; 225e
        JR L_2266                        ; 2261

L_2263:
        CALL sub_1e25                    ; 2263

L_2266:
        POP BC                           ; 2266
        CP 0x98                          ; 2267
        JR z,L_22a5                      ; 2269
        CP 0x97                          ; 226b
        JR z,L_228f                      ; 226d
        CP 0x99                          ; 226f
        JR z,L_22ef                      ; 2271
        CP 0x9a                          ; 2273
        JP z,L_1c5c                      ; 2275
        LD HL,(SEQ_PTR)                  ; 2278
        LD (HL),A                        ; 227b
        INC HL                           ; 227c
        LD (SEQ_PTR),HL                  ; 227d
        DJNZ L_2255                      ; 2280
        LD HL,0x3078                     ; 2282
        INC HL                           ; 2285
        LD (MENU_TEXT_PTR),HL            ; 2286
        CALL menu_show_text              ; 2289
        CALL sub_2a21                    ; 228c

L_228f:
        LD A,0                           ; 228f
        LD (0x4336),A                    ; 2291
        LD HL,(STORE_CURSOR)             ; 2294
        LD A,(HL)                        ; 2297
        CP 0xd0                          ; 2298
        JP c,editor_loop                 ; 229a
        CP 0xdb                          ; 229d
        JP nc,editor_loop                ; 229f
        JP L_2087                        ; 22a2

L_22a5:
        CALL menu_getchar                ; 22a5
        CP 0x12                          ; 22a8
        JR z,L_22a5                      ; 22aa
        CP 0x43                          ; 22ac
        JR z,L_22b5                      ; 22ae
        CP 0x63                          ; 22b0
        JP nz,L_228f                     ; 22b2

L_22b5:
        LD A,0xff                        ; 22b5
        LD (0x420f),A                    ; 22b7
        LD HL,0x3c09                     ; 22ba
        LD DE,0x43a5                     ; 22bd

L_22c0:
        LD A,(HL)                        ; 22c0
        LD (DE),A                        ; 22c1
        CP 3                             ; 22c2
        JR z,L_22ca                      ; 22c4
        INC HL                           ; 22c6
        INC DE                           ; 22c7
        JR L_22c0                        ; 22c8

L_22ca:
        PUSH DE                          ; 22ca
        LD DE,0                          ; 22cb
        LD BC,0x4000                     ; 22ce
        LD HL,0                          ; 22d1

L_22d4:
        LD A,(DE)                        ; 22d4
        PUSH DE                          ; 22d5
        LD D,0                           ; 22d6
        LD E,A                           ; 22d8
        ADD HL,DE                        ; 22d9
        POP DE                           ; 22da
        INC DE                           ; 22db
        DEC BC                           ; 22dc
        LD A,C                           ; 22dd
        OR B                             ; 22de
        JR nz,L_22d4                     ; 22df
        POP DE                           ; 22e1
        CALL sub_2a41                    ; 22e2
        INC DE                           ; 22e5
        INC DE                           ; 22e6
        INC DE                           ; 22e7
        INC DE                           ; 22e8
        LD A,3                           ; 22e9
        LD (DE),A                        ; 22eb
        JP L_1c5c                        ; 22ec

L_22ef:
        LD HL,SEQ_LIST                   ; 22ef
        LD A,0                           ; 22f2
        LD B,0x64                        ; 22f4

L_22f6:
        LD (HL),A                        ; 22f6
        INC HL                           ; 22f7
        INC A                            ; 22f8
        DJNZ L_22f6                      ; 22f9
        LD (HL),0xff                     ; 22fb
        INC HL                           ; 22fd
        LD (HL),0xff                     ; 22fe
        INC HL                           ; 2300
        LD (HL),0xff                     ; 2301
        INC HL                           ; 2303
        LD (HL),0xff                     ; 2304
        JP L_1c5c                        ; 2306

; ---- menu_getchar
menu_getchar:
        CALL editor_getkey               ; 2309
        LD A,(RX_LASTCMD)                ; 230c
        AND A                            ; 230f
        JR z,menu_getchar                ; 2310
        RET                              ; 2312

; ---- editor_getkey: Editor key source: echoes the previous key on the serial TX, then takes a key from the serial RX FIFO if present, else from the IR decoder (IR_CODE). So the on-sign editor can be driven from a serial terminal as well as the remote.
editor_getkey:
        LD A,(0x43d7)                    ; 2313
        AND A                            ; 2316
        JR z,L_231c                      ; 2317
        CALL tx_send_byte                ; 2319

L_231c:
        CALL rx_fifo_get                 ; 231c
        JP c,L_233f                      ; 231f
        AND A                            ; 2322
        JR z,L_233f                      ; 2323
        XOR A                            ; 2325
        LD (0x4364),A                    ; 2326
        LD A,(0x4226)                    ; 2329
        LD (0x4227),A                    ; 232c
        LD A,(RX_LASTCMD)                ; 232f
        LD (0x4226),A                    ; 2332
        LD A,(RX_BYTE)                   ; 2335
        LD (RX_LASTCMD),A                ; 2338
        LD (0x43d7),A                    ; 233b
        RET                              ; 233e

L_233f:
        LD A,(IR_CODE)                   ; 233f
        AND A                            ; 2342
        JR z,L_237d                      ; 2343
        AND 0x3f                         ; 2345
        LD (0x4387),A                    ; 2347
        XOR A                            ; 234a
        LD (IR_CODE),A                   ; 234b
        LD A,(0x4387)                    ; 234e
        CP 0x3e                          ; 2351
        JR z,L_2376                      ; 2353
        LD C,A                           ; 2355
        LD A,(IR_KEY)                    ; 2356
        CP C                             ; 2359
        JR nz,L_2384                     ; 235a
        LD A,(0x4377)                    ; 235c
        AND A                            ; 235f
        JR nz,L_2393                     ; 2360
        CP 0x24                          ; 2362
        JR z,L_237d                      ; 2364
        LD HL,(GEN_COUNTDOWN)            ; 2366
        LD A,H                           ; 2369
        OR L                             ; 236a
        JR nz,L_237d                     ; 236b
        LD HL,0x012c                     ; 236d
        LD (GEN_COUNTDOWN),HL            ; 2370
        JP L_23a3                        ; 2373

L_2376:
        XOR A                            ; 2376
        LD (IR_KEY),A                    ; 2377
        LD (0x4377),A                    ; 237a

L_237d:
        XOR A                            ; 237d
        LD (0x4229),A                    ; 237e
        JP L_2418                        ; 2381

L_2384:
        LD A,(0x4387)                    ; 2384
        LD (IR_KEY),A                    ; 2387
        LD (0x4377),A                    ; 238a
        XOR A                            ; 238d
        LD (IR_CODE),A                   ; 238e
        JR L_237d                        ; 2391

L_2393:
        LD A,(0x4387)                    ; 2393
        LD (IR_KEY),A                    ; 2396
        LD HL,0x0514                     ; 2399
        LD (GEN_COUNTDOWN),HL            ; 239c
        XOR A                            ; 239f
        LD (0x4377),A                    ; 23a0

L_23a3:
        LD A,(0x4387)                    ; 23a3
        CP 0x1d                          ; 23a6
        JR nz,L_23c1                     ; 23a8
        CALL sub_0f48                    ; 23aa
        LD A,(0x4337)                    ; 23ad
        CPL                              ; 23b0
        LD (0x4337),A                    ; 23b1
        AND A                            ; 23b4
        LD A,0x1d                        ; 23b5
        JR nz,L_23bb                     ; 23b7
        LD A,0x9f                        ; 23b9

L_23bb:
        LD (0x4229),A                    ; 23bb
        JP L_2408                        ; 23be

L_23c1:
        LD HL,IR_KEY_TABLE               ; 23c1
        LD D,0                           ; 23c4
        LD E,A                           ; 23c6
        ADD HL,DE                        ; 23c7
        LD A,(HL)                        ; 23c8
        LD (RX_BYTE),A                   ; 23c9
        LD A,(0x4364)                    ; 23cc
        LD HL,CHARSET_GRAPHICS           ; 23cf
        OR A                             ; 23d2
        JR nz,L_23f5                     ; 23d3
        LD A,(0x4337)                    ; 23d5
        LD HL,CHARSET_LOWER              ; 23d8
        AND A                            ; 23db
        JR z,L_23ec                      ; 23dc
        LD HL,CHARSET_UPPER2             ; 23de
        LD A,(0x4358)                    ; 23e1
        AND A                            ; 23e4
        JR z,L_23f5                      ; 23e5
        LD HL,CHARSET_LOWER2             ; 23e7
        JR L_23f5                        ; 23ea

L_23ec:
        LD A,(0x4358)                    ; 23ec
        AND A                            ; 23ef
        JR z,L_23f5                      ; 23f0
        LD HL,CHARSET_UPPER              ; 23f2

L_23f5:
        LD A,(RX_BYTE)                   ; 23f5
        LD E,A                           ; 23f8
        LD D,0                           ; 23f9
        ADD HL,DE                        ; 23fb
        LD A,(HL)                        ; 23fc
        LD (0x4229),A                    ; 23fd
        LD A,0                           ; 2400
        LD (0x4337),A                    ; 2402
        CALL sub_0f48                    ; 2405

L_2408:
        XOR A                            ; 2408
        LD (0x4364),A                    ; 2409
        LD A,(0x4226)                    ; 240c
        LD (0x4227),A                    ; 240f
        LD A,(RX_LASTCMD)                ; 2412
        LD (0x4226),A                    ; 2415

L_2418:
        LD A,(0x4229)                    ; 2418
        LD (RX_LASTCMD),A                ; 241b
        XOR A                            ; 241e
        LD (0x43d7),A                    ; 241f
        LD A,(RX_LASTCMD)                ; 2422
        AND A                            ; 2425
        RET                              ; 2426

; ---- data 2427-2464: IR/keypad code -> character map
IR_KEY_TABLE:
        db 0x0f,0x33,0x0c,0x0b,0x0d,0x09,0x0a,0x0e,0x03,0x3f,0x3c,0x3b,0x3d,0x39,0x3a,0x3e   ; 2427
        db 0x2f,0x13,0x2c,0x2b,0x2d,0x29,0x2a,0x2e,0x24,0x23,0x1c,0x1b,0x1d,0x1d,0x1a,0x22   ; 2437
        db 0x31,0x30,0x37,0x36,0x35,0x08,0x32,0x34,0x01,0x00,0x07,0x06,0x05,0x38,0x02,0x04   ; 2447
        db 0x11,0x10,0x17,0x16,0x15,0x28,0x12,0x14,0x21,0x20,0x27,0x26,0x25,0x18   ; 2457

L_2465:
        LD HL,(STORE_CURSOR)             ; 2465
        LD A,(HL)                        ; 2468
        CP 3                             ; 2469
        JP z,editor_loop                 ; 246b
        LD A,(0x4337)                    ; 246e
        OR A                             ; 2471
        JR z,L_247f                      ; 2472
        LD A,0xff                        ; 2474
        LD (0x4241),A                    ; 2476
        LD HL,0x2f9b                     ; 2479
        LD (0x420a),HL                   ; 247c

L_247f:
        JP editor_loop                   ; 247f

L_2482:
        LD A,(CHAN_LOCK)                 ; 2482
        OR A                             ; 2485
        JP nz,L_206a                     ; 2486
        LD A,(CTRL_LATCH_SHADOW)         ; 2489
        OR 15                            ; 248c
        LD (CTRL_LATCH_SHADOW),A         ; 248e
        LD (CTRL_LATCH),A                ; 2491
        LD HL,(STORE_CURSOR)             ; 2494
        LD A,(HL)                        ; 2497
        CP 3                             ; 2498
        JP z,editor_loop                 ; 249a
        CP 0xd0                          ; 249d
        JP c,L_24aa                      ; 249f
        CP 0xdb                          ; 24a2
        JP nc,L_24aa                     ; 24a4
        JP L_2087                        ; 24a7

L_24aa:
        LD A,0                           ; 24aa
        LD (EFFECT_ACTIVE),A             ; 24ac
        LD HL,(STORE_END)                ; 24af
        DEC HL                           ; 24b2
        LD (STORE_END),HL                ; 24b3
        CALL sub_0cea                    ; 24b6
        LD HL,(STORE_CURSOR)             ; 24b9
        INC HL                           ; 24bc
        LD (MOVE_DST),HL                 ; 24bd
        INC HL                           ; 24c0
        LD (MOVE_SRC),HL                 ; 24c1
        LD DE,(STORE_LIMIT)              ; 24c4
        EX DE,HL                         ; 24c8
        OR A                             ; 24c9
        SBC HL,DE                        ; 24ca
        LD B,H                           ; 24cc
        LD C,L                           ; 24cd
        LD HL,(MOVE_SRC)                 ; 24ce
        LD DE,(MOVE_DST)                 ; 24d1
        LDIR                             ; 24d5
        LD A,0xff                        ; 24d7
        LD (EFFECT_ACTIVE),A             ; 24d9
        LD HL,(STORE_CURSOR)             ; 24dc
        LD A,(HL)                        ; 24df
        CP 0xd0                          ; 24e0
        JP c,editor_loop                 ; 24e2
        CP 0xdb                          ; 24e5
        JP nc,editor_loop                ; 24e7
        DEC HL                           ; 24ea
        LD (STORE_CURSOR),HL             ; 24eb
        JP L_2087                        ; 24ee
        db 0xc3,0xd2,0x1a   ; 24f1

L_24f4:
        LD HL,(STORE_CURSOR)             ; 24f4
        LD A,(HL)                        ; 24f7
        CP 3                             ; 24f8
        JR z,L_250c                      ; 24fa
        INC HL                           ; 24fc
        LD A,(HL)                        ; 24fd
        CP 0xd0                          ; 24fe
        JP c,L_2509                      ; 2500
        CP 0xdb                          ; 2503
        JP nc,L_2509                     ; 2505
        INC HL                           ; 2508

L_2509:
        LD (STORE_CURSOR),HL             ; 2509

L_250c:
        JP editor_loop                   ; 250c

L_250f:
        LD B,8                           ; 250f
        LD HL,(STORE_CURSOR)             ; 2511

L_2514:
        LD A,(HL)                        ; 2514
        CP 3                             ; 2515
        JR z,L_251f                      ; 2517
        INC HL                           ; 2519
        LD (STORE_CURSOR),HL             ; 251a
        DJNZ L_2514                      ; 251d

L_251f:
        JP editor_loop                   ; 251f

L_2522:
        LD IX,(STORE_CURSOR)             ; 2522
        LD A,(IX+0)                      ; 2526
        CP 0xd0                          ; 2529
        JP c,L_2536                      ; 252b
        CP 0xdb                          ; 252e
        JP nc,L_2536                     ; 2530
        JP L_2087                        ; 2533

L_2536:
        DEC IX                           ; 2536
        LD (STORE_CURSOR),IX             ; 2538
        LD A,(IX+0)                      ; 253c
        CP 0xd0                          ; 253f
        JP c,editor_loop                 ; 2541
        CP 0xdb                          ; 2544
        JP nc,editor_loop                ; 2546
        DEC IX                           ; 2549
        LD (STORE_CURSOR),IX             ; 254b
        JP L_2087                        ; 254f

L_2552:
        LD B,8                           ; 2552
        LD HL,(STORE_CURSOR)             ; 2554
        LD A,(HL)                        ; 2557
        CP 0xd0                          ; 2558
        JP c,L_2565                      ; 255a
        CP 0xdb                          ; 255d
        JP nc,L_2565                     ; 255f
        JP L_2087                        ; 2562

L_2565:
        DEC HL                           ; 2565
        LD (STORE_CURSOR),HL             ; 2566
        LD A,(HL)                        ; 2569
        CP 0xd0                          ; 256a
        JP c,L_2552                      ; 256c
        CP 0xdb                          ; 256f
        JP nc,L_2552                     ; 2571
        DEC HL                           ; 2574
        LD (STORE_CURSOR),HL             ; 2575
        JP L_2087                        ; 2578
        DJNZ L_2565                      ; 257b
        JP editor_loop                   ; 257d

L_2580:
        LD (CUR_CHAR),A                  ; 2580
        LD A,(CHAN_LOCK)                 ; 2583
        OR A                             ; 2586
        JP nz,L_206a                     ; 2587
        LD HL,(STORE_CURSOR)             ; 258a
        LD A,(HL)                        ; 258d
        CP 3                             ; 258e
        JP z,L_2615                      ; 2590
        CP 0xd0                          ; 2593
        JP c,L_25a1                      ; 2595
        CP 0xdb                          ; 2598
        JP nc,L_25a1                     ; 259a
        INC HL                           ; 259d
        LD (STORE_CURSOR),HL             ; 259e

L_25a1:
        LD A,(CTRL_LATCH_SHADOW)         ; 25a1
        OR 15                            ; 25a4
        LD (CTRL_LATCH_SHADOW),A         ; 25a6
        LD (CTRL_LATCH),A                ; 25a9
        LD A,0                           ; 25ac
        LD (EFFECT_ACTIVE),A             ; 25ae
        LD HL,(STORE_END)                ; 25b1
        INC HL                           ; 25b4
        LD (STORE_TMP),HL                ; 25b5
        LD DE,(STORE_LIMIT)              ; 25b8
        OR A                             ; 25bc
        SBC HL,DE                        ; 25bd
        LD A,H                           ; 25bf
        OR L                             ; 25c0
        JR nz,L_25d1                     ; 25c1
        LD A,0xff                        ; 25c3
        LD (0x4224),A                    ; 25c5
        LD HL,0x3057                     ; 25c8
        LD (0x420a),HL                   ; 25cb
        JP editor_loop                   ; 25ce

L_25d1:
        LD HL,(STORE_TMP)                ; 25d1
        LD (STORE_END),HL                ; 25d4
        CALL store_make_room             ; 25d7
        LD HL,(STORE_LIMIT)              ; 25da
        LD (MOVE_DST),HL                 ; 25dd
        DEC HL                           ; 25e0
        LD (MOVE_SRC),HL                 ; 25e1
        LD DE,(STORE_CURSOR)             ; 25e4
        OR A                             ; 25e8
        SBC HL,DE                        ; 25e9
        LD B,H                           ; 25eb
        LD C,L                           ; 25ec
        LD HL,(MOVE_SRC)                 ; 25ed
        LD DE,(MOVE_DST)                 ; 25f0
        INC BC                           ; 25f4
        LDDR                             ; 25f5
        LD HL,(STORE_CURSOR)             ; 25f7
        LD A,(CUR_CHAR)                  ; 25fa
        LD (HL),A                        ; 25fd
        LD HL,(STORE_END)                ; 25fe
        LD DE,(0x43de)                   ; 2601
        OR A                             ; 2605
        SBC HL,DE                        ; 2606
        JR nz,L_2615                     ; 2608
        LD A,0xff                        ; 260a
        LD (0x4224),A                    ; 260c
        LD HL,0x3067                     ; 260f
        LD (0x420a),HL                   ; 2612

L_2615:
        JP editor_loop                   ; 2615

; ---- store_make_room
store_make_room:
        LD HL,(STORE_CURSOR)             ; 2618
        LD DE,(STORE_LIMIT)              ; 261b
        INC HL                           ; 261f
        LD (STORE_CURSOR),HL             ; 2620
        OR A                             ; 2623
        SBC HL,DE                        ; 2624
        JR nz,L_263b                     ; 2626
        LD A,(MENU_ACTIVE)               ; 2628
        AND A                            ; 262b
        JR nz,L_2636                     ; 262c
        LD HL,MSG_STORE                  ; 262e
        LD (STORE_CURSOR),HL             ; 2631
        JR L_263b                        ; 2634

L_2636:
        LD A,0xff                        ; 2636
        LD (0x4236),A                    ; 2638

L_263b:
        RET                              ; 263b

sub_263c:
        CALL sub_264c                    ; 263c
        CALL sub_26d1                    ; 263f
        CALL sub_2661                    ; 2642
        CALL editor_key_to_attr          ; 2645
        CALL rx_cmd_check                ; 2648
        RET                              ; 264b

sub_264c:
        LD A,(0x4221)                    ; 264c
        OR A                             ; 264f
        RET z                            ; 2650
        LD A,(RX_LASTCMD)                ; 2651
        AND 15                           ; 2654
        OR 0xa0                          ; 2656
        LD (RX_LASTCMD),A                ; 2658
        LD A,0                           ; 265b
        LD (0x4221),A                    ; 265d
        RET                              ; 2660

sub_2661:
        LD A,(0x43cf)                    ; 2661
        AND A                            ; 2664
        RET z                            ; 2665
        LD A,(RX_LASTCMD)                ; 2666
        AND 7                            ; 2669
        OR 0xf0                          ; 266b
        LD (RX_LASTCMD),A                ; 266d
        XOR A                            ; 2670
        LD (0x43cf),A                    ; 2671
        RET                              ; 2674

; ---- editor_key_to_attr: Translate editor function keys to message bytes: 1E->B8 graphic,11->B9 thin,19->BA wait,14->B0 remark,12->06 pause,15->BC rainbow, 8F.. colours etc.
editor_key_to_attr:
        LD A,(0x43ca)                    ; 2675
        AND A                            ; 2678
        RET z                            ; 2679
        XOR A                            ; 267a
        LD (0x43ca),A                    ; 267b
        LD A,(RX_LASTCMD)                ; 267e
        LD C,0xb8                        ; 2681
        CP 0x1e                          ; 2683
        JR z,L_26cc                      ; 2685
        INC C                            ; 2687
        CP 0x11                          ; 2688
        JR z,L_26cc                      ; 268a
        INC C                            ; 268c
        CP 0x19                          ; 268d
        JR z,L_26cc                      ; 268f
        LD C,0xb0                        ; 2691
        CP 0x14                          ; 2693
        JR z,L_26cc                      ; 2695
        LD C,6                           ; 2697
        CP 0x12                          ; 2699
        JR z,L_26cc                      ; 269b
        LD C,0xbc                        ; 269d
        CP 0x15                          ; 269f
        JR z,L_26cc                      ; 26a1
        CP 0x8f                          ; 26a3
        JR z,L_26cc                      ; 26a5
        LD C,0x3f                        ; 26a7
        CP 0x51                          ; 26a9
        JR z,L_26cc                      ; 26ab
        CP 0x71                          ; 26ad
        JR z,L_26cc                      ; 26af
        LD C,0x21                        ; 26b1
        CP 0x58                          ; 26b3
        JR z,L_26cc                      ; 26b5
        CP 0x78                          ; 26b7
        JR z,L_26cc                      ; 26b9
        LD C,0x5e                        ; 26bb
        CP 0x1f                          ; 26bd
        JR z,L_26cc                      ; 26bf
        LD C,0xbe                        ; 26c1
        CP 0x10                          ; 26c3
        JR z,L_26cc                      ; 26c5
        POP HL                           ; 26c7
        POP HL                           ; 26c8
        JP L_206a                        ; 26c9

L_26cc:
        LD A,C                           ; 26cc
        LD (RX_LASTCMD),A                ; 26cd
        RET                              ; 26d0

sub_26d1:
        LD A,(0x4220)                    ; 26d1
        AND A                            ; 26d4
        JR nz,L_26de                     ; 26d5
        LD A,(FB_TMP)                    ; 26d7
        AND A                            ; 26da
        JR nz,L_26fb                     ; 26db
        RET                              ; 26dd

L_26de:
        LD A,(RX_LASTCMD)                ; 26de
        AND 15                           ; 26e1
        DEC A                            ; 26e3
        CP 10                            ; 26e4
        JR c,L_26ea                      ; 26e6
        LD A,2                           ; 26e8

L_26ea:
        NOP                              ; 26ea
        LD HL,FG_IDX_TABLE               ; 26eb
        LD C,A                           ; 26ee
        LD B,0                           ; 26ef
        ADD HL,BC                        ; 26f1
        LD A,(HL)                        ; 26f2
        LD (RX_LASTCMD),A                ; 26f3
        XOR A                            ; 26f6
        LD (0x4220),A                    ; 26f7
        RET                              ; 26fa

L_26fb:
        LD A,(RX_LASTCMD)                ; 26fb
        AND 7                            ; 26fe
        DEC A                            ; 2700
        CP 6                             ; 2701
        JR c,L_2707                      ; 2703
        LD A,5                           ; 2705

L_2707:
        NOP                              ; 2707
        LD HL,BG_IDX_TABLE               ; 2708
        LD C,A                           ; 270b
        LD B,0                           ; 270c
        ADD HL,BC                        ; 270e
        LD A,(HL)                        ; 270f
        LD (RX_LASTCMD),A                ; 2710
        XOR A                            ; 2713
        LD (FB_TMP),A                    ; 2714
        RET                              ; 2717

; ---- data 2718-2721: cmd 15 n: foreground colour codes (Red,Orange,Yellow,Lime,Green,84,8E,Black,8B,81)
FG_IDX_TABLE:
        db 0x8c,0x8d,0x8f,0x87,0x83,0x84,0x8e,0x80,0x8b,0x81   ; 2718

; ---- data 2722-2727: cmd 16 n: background colour codes
BG_IDX_TABLE:
        db 0x91,0x93,0x93,0x93,0x92,0x90   ; 2722

; ---- editor_redraw: Redraw the editor view of the current message
editor_redraw:
        CALL clear_txbuf                 ; 2728
        CALL init_render                 ; 272b
        XOR A                            ; 272e
        LD (EFFECT_ACTIVE),A             ; 272f
        LD A,(CTRL_LATCH_SHADOW)         ; 2732
        OR 15                            ; 2735
        LD (CTRL_LATCH_SHADOW),A         ; 2737
        LD (CTRL_LATCH),A                ; 273a
        LD A,(0x4243)                    ; 273d
        AND A                            ; 2740
        JP nz,L_28f3                     ; 2741
        LD A,(0x4336)                    ; 2744
        BIT 7,A                          ; 2747
        JP nz,L_28f3                     ; 2749
        LD A,(0x4399)                    ; 274c
        AND A                            ; 274f
        JP nz,L_28f3                     ; 2750
        LD HL,(STORE_CURSOR)             ; 2753
        LD A,(HL)                        ; 2756
        CP 0xd0                          ; 2757
        JP c,L_2764                      ; 2759
        CP 0xdb                          ; 275c
        JP nc,L_2764                     ; 275e
        JP L_28f3                        ; 2761

L_2764:
        LD DE,0x15                       ; 2764
        OR A                             ; 2767
        SBC HL,DE                        ; 2768
        LD (0x4344),HL                   ; 276a
        LD DE,(INS_PTR)                  ; 276d
        OR A                             ; 2771
        SBC HL,DE                        ; 2772
        JR nc,L_277a                     ; 2774
        EX DE,HL                         ; 2776
        LD (0x4344),HL                   ; 2777

L_277a:
        LD HL,(INS_PTR)                  ; 277a
        LD (0x425a),HL                   ; 277d

L_2780:
        LD HL,(0x425a)                   ; 2780
        LD A,(HL)                        ; 2783
        LD (CUR_CHAR),A                  ; 2784
        LD A,0xff                        ; 2787
        LD (TINY_MODE),A                 ; 2789
        LD A,(CUR_CHAR)                  ; 278c
        CP 0x20                          ; 278f
        JR nz,L_27a4                     ; 2791
        LD A,(0x439a)                    ; 2793
        AND A                            ; 2796
        JP z,L_28b0                      ; 2797
        XOR A                            ; 279a
        LD (0x433b),A                    ; 279b
        LD (FONT_MODE),A                 ; 279e
        JP L_28b0                        ; 27a1

L_27a4:
        BIT 7,A                          ; 27a4
        JP nz,L_27b0                     ; 27a6
        AND 0x60                         ; 27a9
        JR z,L_27d3                      ; 27ab
        JP L_28b0                        ; 27ad

L_27b0:
        LD A,(CUR_CHAR)                  ; 27b0
        CP 0x94                          ; 27b3
        JP c,L_27d3                      ; 27b5
        CP 0x9f                          ; 27b8
        JP c,L_28b0                      ; 27ba
        AND 0xf0                         ; 27bd
        CP 0xc0                          ; 27bf
        JP z,L_28b0                      ; 27c1
        CP 0xe0                          ; 27c4
        JP z,L_28b0                      ; 27c6
        CP 0xd0                          ; 27c9
        JP z,L_28b0                      ; 27cb
        CP 0xa0                          ; 27ce
        JP z,L_28b0                      ; 27d0

L_27d3:
        LD A,(CUR_CHAR)                  ; 27d3
        CP 0x15                          ; 27d6
        JP z,L_28b0                      ; 27d8
        CP 0x16                          ; 27db
        JP z,L_28b0                      ; 27dd
        CP 0xbd                          ; 27e0
        JR nz,L_27eb                     ; 27e2
        XOR A                            ; 27e4
        LD (0x439a),A                    ; 27e5
        LD A,(CUR_CHAR)                  ; 27e8

L_27eb:
        CP 15                            ; 27eb
        JP z,L_2869                      ; 27ed
        CP 0x19                          ; 27f0
        JP z,L_2869                      ; 27f2
        CP 0x1a                          ; 27f5
        JP z,L_2869                      ; 27f7
        CP 0x1b                          ; 27fa
        JP z,L_2869                      ; 27fc
        CP 0x18                          ; 27ff
        JP z,L_2878                      ; 2801
        CP 0x11                          ; 2804
        JP nz,L_2812                     ; 2806
        XOR A                            ; 2809
        LD (0x421e),A                    ; 280a
        LD (FONT_MODE),A                 ; 280d
        JR L_287d                        ; 2810

L_2812:
        CP 0x14                          ; 2812
        JP nz,L_281e                     ; 2814
        LD A,0x10                        ; 2817
        LD (0x43a2),A                    ; 2819
        JR L_287d                        ; 281c

L_281e:
        CP 0x13                          ; 281e
        JP nz,L_282a                     ; 2820
        LD A,0x64                        ; 2823
        LD (FONT_MODE),A                 ; 2825
        JR L_287d                        ; 2828

L_282a:
        CP 0x12                          ; 282a
        JP nz,L_2837                     ; 282c
        XOR A                            ; 282f
        SET 1,A                          ; 2830
        LD (FONT_MODE),A                 ; 2832
        JR L_287d                        ; 2835

L_2837:
        CP 0x10                          ; 2837
        JP nz,L_2847                     ; 2839
        XOR A                            ; 283c
        SET 1,A                          ; 283d
        SET 3,A                          ; 283f
        LD (FONT_MODE),A                 ; 2841
        JP L_287d                        ; 2844

L_2847:
        CP 0xb9                          ; 2847
        JP nz,L_2858                     ; 2849
        LD A,0xff                        ; 284c
        LD (0x43d6),A                    ; 284e
        XOR A                            ; 2851
        LD (0x433b),A                    ; 2852
        JP L_287d                        ; 2855

L_2858:
        CP 0x1f                          ; 2858
        JP nz,L_287d                     ; 285a
        XOR A                            ; 285d
        LD (FONT_MODE),A                 ; 285e
        LD A,0xff                        ; 2861
        LD (0x439a),A                    ; 2863
        JP L_287d                        ; 2866

L_2869:
        LD A,(0x43d6)                    ; 2869
        AND A                            ; 286c
        JP nz,L_287d                     ; 286d
        LD A,0xff                        ; 2870
        LD (0x433b),A                    ; 2872
        JP L_287d                        ; 2875

L_2878:
        LD A,0                           ; 2878
        LD (0x433b),A                    ; 287a

L_287d:
        LD HL,(0x425a)                   ; 287d
        LD DE,(0x4344)                   ; 2880
        OR A                             ; 2884
        EX DE,HL                         ; 2885
        SBC HL,DE                        ; 2886
        EX DE,HL                         ; 2888
        JP c,L_2892                      ; 2889
        JP z,L_2892                      ; 288c
        JP L_28e0                        ; 288f

L_2892:
        LD HL,0x2d62                     ; 2892
        LD A,(CUR_CHAR)                  ; 2895
        LD E,A                           ; 2898
        LD D,0                           ; 2899
        SLA E                            ; 289b
        RL D                             ; 289d
        ADD HL,DE                        ; 289f
        LD E,(HL)                        ; 28a0
        INC HL                           ; 28a1
        LD D,(HL)                        ; 28a2
        LD (MENU_TEXT_PTR),DE            ; 28a3
        CALL menu_show_text              ; 28a7
        LD A,(CUR_CHAR)                  ; 28aa
        JP L_28e0                        ; 28ad

L_28b0:
        LD HL,(0x425a)                   ; 28b0
        LD DE,(0x4344)                   ; 28b3
        OR A                             ; 28b7
        EX DE,HL                         ; 28b8
        SBC HL,DE                        ; 28b9
        EX DE,HL                         ; 28bb
        JP c,L_28c5                      ; 28bc
        JP z,L_28c5                      ; 28bf
        JP L_28e0                        ; 28c2

L_28c5:
        XOR A                            ; 28c5
        LD (TINY_MODE),A                 ; 28c6
        LD A,(CUR_CHAR)                  ; 28c9
        AND 0xf0                         ; 28cc
        CP 0xa0                          ; 28ce
        LD A,(CUR_CHAR)                  ; 28d0
        JR nz,L_28da                     ; 28d3
        AND 15                           ; 28d5
        LD (CUR_CHAR),A                  ; 28d7

L_28da:
        CALL sub_072a                    ; 28da
        CALL glyph_lookup                ; 28dd

L_28e0:
        LD HL,(0x425a)                   ; 28e0
        INC HL                           ; 28e3
        LD (0x425a),HL                   ; 28e4
        LD DE,(STORE_CURSOR)             ; 28e7
        EX DE,HL                         ; 28eb
        OR A                             ; 28ec
        SBC HL,DE                        ; 28ed
        EX DE,HL                         ; 28ef
        JP nc,L_2780                     ; 28f0

L_28f3:
        LD A,0xff                        ; 28f3
        LD (TINY_MODE),A                 ; 28f5
        LD A,(0x4221)                    ; 28f8
        AND A                            ; 28fb
        JR z,L_2904                      ; 28fc
        LD HL,0x2fe3                     ; 28fe
        JP L_2988                        ; 2901

L_2904:
        LD A,(0x4220)                    ; 2904
        OR A                             ; 2907
        JR z,L_2910                      ; 2908
        LD HL,0x2f52                     ; 290a
        JP L_2988                        ; 290d

L_2910:
        LD A,(FB_TMP)                    ; 2910
        OR A                             ; 2913
        JR z,L_291c                      ; 2914
        LD HL,0x2f59                     ; 2916
        JP L_2988                        ; 2919

L_291c:
        LD A,(0x43ca)                    ; 291c
        OR A                             ; 291f
        JR z,L_2928                      ; 2920
        LD HL,0x2f83                     ; 2922
        JP L_2988                        ; 2925

L_2928:
        LD A,(0x4364)                    ; 2928
        OR A                             ; 292b
        JR z,L_2934                      ; 292c
        LD HL,0x2f89                     ; 292e
        JP L_2988                        ; 2931

L_2934:
        LD A,(0x43cf)                    ; 2934
        OR A                             ; 2937
        JP z,L_2941                      ; 2938
        LD HL,0x2fdb                     ; 293b
        JP L_2988                        ; 293e

L_2941:
        LD A,(0x4399)                    ; 2941
        OR A                             ; 2944
        JP z,L_298e                      ; 2945
        XOR A                            ; 2948
        LD (0x4399),A                    ; 2949
        CALL init_render                 ; 294c
        LD HL,(FB_COL)                   ; 294f
        LD (FB_COLPTR),HL                ; 2952
        LD HL,STR_MAGIC_MSG              ; 2955
        LD (MENU_TEXT_PTR),HL            ; 2958
        CALL menu_show_text              ; 295b
        LD B,2                           ; 295e
        LD HL,(INS_PTR)                  ; 2960
        DEC HL                           ; 2963
        DEC HL                           ; 2964

L_2965:
        LD A,(HL)                        ; 2965
        AND 15                           ; 2966
        OR 0x30                          ; 2968
        LD (CUR_CHAR),A                  ; 296a
        PUSH HL                          ; 296d
        PUSH BC                          ; 296e
        CALL glyph_lookup                ; 296f
        POP BC                           ; 2972
        POP HL                           ; 2973
        INC HL                           ; 2974
        DJNZ L_2965                      ; 2975
        JR L_298e                        ; 2977

; ---- data 2979-2987: 
STR_MAGIC_MSG:
        db "    MAGIC MSG ",0x00   ; 2979

L_2988:
        LD (MENU_TEXT_PTR),HL            ; 2988
        CALL menu_show_text              ; 298b

L_298e:
        LD A,(0x4241)                    ; 298e
        AND A                            ; 2991
        JR z,L_299d                      ; 2992
        LD HL,(0x420a)                   ; 2994
        LD (MENU_TEXT_PTR),HL            ; 2997
        CALL menu_show_text              ; 299a

L_299d:
        LD A,(0x4224)                    ; 299d
        OR A                             ; 29a0
        JR z,L_29ad                      ; 29a1
        LD HL,(0x420a)                   ; 29a3
        INC HL                           ; 29a6
        LD (MENU_TEXT_PTR),HL            ; 29a7
        CALL menu_show_text              ; 29aa

L_29ad:
        CALL sub_2a21                    ; 29ad
        LD A,(0x4224)                    ; 29b0
        OR A                             ; 29b3
        JR z,L_29d3                      ; 29b4
        CALL sub_29d9                    ; 29b6
        LD A,0                           ; 29b9
        LD (0x4224),A                    ; 29bb
        LD HL,(STORE_CURSOR)             ; 29be
        LD A,(HL)                        ; 29c1
        CP 0xd0                          ; 29c2
        JP c,L_29d0                      ; 29c4
        CP 0xdb                          ; 29c7
        JP nc,L_29d0                     ; 29c9
        POP HL                           ; 29cc
        JP L_2087                        ; 29cd

L_29d0:
        JP editor_redraw                 ; 29d0

L_29d3:
        LD A,0xff                        ; 29d3
        LD (EFFECT_ACTIVE),A             ; 29d5
        RET                              ; 29d8

sub_29d9:
        LD A,0xff                        ; 29d9
        LD (EFFECT_ACTIVE),A             ; 29db

L_29de:
        LD A,(ROW_INDEX)                 ; 29de
        CP 3                             ; 29e1
        JR nz,L_29de                     ; 29e3

L_29e5:
        LD A,(ROW_INDEX)                 ; 29e5
        CP 2                             ; 29e8
        JR nz,L_29e5                     ; 29ea
        LD A,0x50                        ; 29ec
        LD (0x4244),A                    ; 29ee

L_29f1:
        LD A,(0x4244)                    ; 29f1
        AND A                            ; 29f4
        JR nz,L_29f1                     ; 29f5
        RET                              ; 29f7

; ---- menu_show_text: Render the NUL-terminated string at MENU_TEXT_PTR in tiny font
menu_show_text:
        LD HL,(MENU_TEXT_PTR)            ; 29f8
        LD A,(TINY_MODE)                 ; 29fb
        PUSH AF                          ; 29fe
        LD A,(CUR_CHAR)                  ; 29ff
        PUSH AF                          ; 2a02
        LD A,0xff                        ; 2a03
        LD (TINY_MODE),A                 ; 2a05

L_2a08:
        LD A,(HL)                        ; 2a08
        INC HL                           ; 2a09
        OR A                             ; 2a0a
        JR z,L_2a18                      ; 2a0b
        LD (CUR_CHAR),A                  ; 2a0d
        PUSH HL                          ; 2a10
        CALL glyph_lookup                ; 2a11
        POP HL                           ; 2a14
        JP L_2a08                        ; 2a15

L_2a18:
        POP AF                           ; 2a18
        LD (CUR_CHAR),A                  ; 2a19
        POP AF                           ; 2a1c
        LD (TINY_MODE),A                 ; 2a1d
        RET                              ; 2a20

sub_2a21:
        LD HL,(FB_COLPTR)                ; 2a21
        LD DE,0x56                       ; 2a24
        XOR A                            ; 2a27
        SBC HL,DE                        ; 2a28
        LD (FB_COL),HL                   ; 2a2a
        LD DE,FRAMEBUF                   ; 2a2d
        XOR A                            ; 2a30
        SBC HL,DE                        ; 2a31
        JP nc,L_2a3d                     ; 2a33
        LD DE,FB_COLPTR                  ; 2a36
        ADD HL,DE                        ; 2a39
        LD (FB_COL),HL                   ; 2a3a

L_2a3d:
        RET                              ; 2a3d

; ---- pkt_process_end
pkt_process_end:
        JP RESET                         ; 2a3e

sub_2a41:
        PUSH DE                          ; 2a41
        LD B,2                           ; 2a42
        LD C,H                           ; 2a44

L_2a45:
        LD A,C                           ; 2a45
        SRL A                            ; 2a46
        SRL A                            ; 2a48
        SRL A                            ; 2a4a
        SRL A                            ; 2a4c
        CALL nibble_to_hex               ; 2a4e
        LD (DE),A                        ; 2a51
        INC DE                           ; 2a52
        LD A,C                           ; 2a53
        AND 15                           ; 2a54
        CALL nibble_to_hex               ; 2a56
        LD (DE),A                        ; 2a59
        INC DE                           ; 2a5a
        LD C,L                           ; 2a5b
        DJNZ L_2a45                      ; 2a5c
        POP DE                           ; 2a5e
        RET                              ; 2a5f

; ---- nibble_to_hex: A = ASCII hex digit for low nibble
nibble_to_hex:
        OR 0x30                          ; 2a60
        CP 0x3a                          ; 2a62
        RET c                            ; 2a64
        ADD A,7                          ; 2a65
        RET                              ; 2a67

; ---- pkt_process: Process a received packet: wait for TX idle, DI, walk PKT_BUF byte by byte. Bytes in IGNORE_TABLE are skipped; command bytes dispatch (02 speed,03 clear all,04 sequence,09 channel,0D end,0E delete channel text,15 fg idx,16 bg idx,17 time,1E A0-colour,B3 append,B4 query); anything else is inserted as message text
pkt_process:
        LD A,(TX_STATUS)                 ; 2a68
        AND 3                            ; 2a6b
        JR nz,pkt_process                ; 2a6d
        DI                               ; 2a6f
        LD SP,STACK_TOP                  ; 2a70
        LD A,(CTRL_LATCH_SHADOW)         ; 2a73
        OR 15                            ; 2a76
        LD (CTRL_LATCH_SHADOW),A         ; 2a78
        LD (CTRL_LATCH),A                ; 2a7b
        LD HL,(STORE_CURSOR)             ; 2a7e
        LD A,(HL)                        ; 2a81
        CP 0xd0                          ; 2a82
        JP c,L_2a90                      ; 2a84
        CP 0xdb                          ; 2a87
        JP nc,L_2a90                     ; 2a89
        DEC HL                           ; 2a8c
        LD (STORE_CURSOR),HL             ; 2a8d

L_2a90:
        PUSH HL                          ; 2a90
        LD DE,MSG_STORE                  ; 2a91
        OR A                             ; 2a94
        SBC HL,DE                        ; 2a95
        PUSH HL                          ; 2a97
        POP BC                           ; 2a98
        POP HL                           ; 2a99
        DEC HL                           ; 2a9a

L_2a9b:
        LD A,(HL)                        ; 2a9b
        CP 0xd0                          ; 2a9c
        JP c,L_2aa8                      ; 2a9e
        CP 0xdb                          ; 2aa1
        JP nc,L_2aa8                     ; 2aa3
        JR L_2ab1                        ; 2aa6

L_2aa8:
        DEC HL                           ; 2aa8
        DEC BC                           ; 2aa9
        LD A,C                           ; 2aaa
        OR B                             ; 2aab
        JR nz,L_2a9b                     ; 2aac
        JP pkt_process_end               ; 2aae

L_2ab1:
        LD (STORE_CURSOR),HL             ; 2ab1
        INC HL                           ; 2ab4
        LD (INS_PTR),HL                  ; 2ab5
        CALL store_finalize              ; 2ab8
        LD A,(PKT_LEN)                   ; 2abb
        AND A                            ; 2abe
        JP z,pkt_process_done            ; 2abf
        LD B,A                           ; 2ac2
        LD HL,PKT_BUF                    ; 2ac3

L_2ac6:
        LD A,(HL)                        ; 2ac6
        PUSH HL                          ; 2ac7
        PUSH BC                          ; 2ac8
        LD (CUR_CHAR),A                  ; 2ac9
        CALL is_ignored_byte             ; 2acc
        AND A                            ; 2acf
        JP z,L_2b61                      ; 2ad0
        CP 2                             ; 2ad3
        JP z,cmd_02_speed                ; 2ad5
        CP 3                             ; 2ad8
        JP z,cmd_03_clear_all            ; 2ada
        CP 4                             ; 2add
        JP z,cmd_04_sequence             ; 2adf
        CP 9                             ; 2ae2
        JP z,cmd_09_channel              ; 2ae4
        CP 13                            ; 2ae7
        JP z,pkt_process_done            ; 2ae9
        CP 14                            ; 2aec
        JP z,cmd_0E_delete_text          ; 2aee
        CP 0x15                          ; 2af1
        JP z,cmd_15_fore_idx             ; 2af3
        CP 0x16                          ; 2af6
        JP z,cmd_16_back_idx             ; 2af8
        CP 0x17                          ; 2afb
        JP z,cmd_17_set_time             ; 2afd
        CP 0x1e                          ; 2b00
        JP z,cmd_1E_colour_A0            ; 2b02
        CP 0xb3                          ; 2b05
        JP z,cmd_B3_append               ; 2b07
        CP 0xb4                          ; 2b0a
        JP z,cmd_B4_query                ; 2b0c

; ---- pkt_insert_text: Insert CUR_CHAR at STORE_CURSOR (shifts the store up; refuses when CHAN_LOCK or memory full)
pkt_insert_text:
        LD A,(CHAN_LOCK)                 ; 2b0f
        OR A                             ; 2b12
        JP nz,L_2b61                     ; 2b13
        LD HL,(STORE_CURSOR)             ; 2b16
        LD A,(HL)                        ; 2b19
        CP 3                             ; 2b1a
        JR nz,L_2b22                     ; 2b1c
        DEC HL                           ; 2b1e
        LD (STORE_CURSOR),HL             ; 2b1f

L_2b22:
        LD HL,(STORE_END)                ; 2b22
        INC HL                           ; 2b25
        LD (STORE_TMP),HL                ; 2b26
        LD DE,(STORE_LIMIT)              ; 2b29
        OR A                             ; 2b2d
        SBC HL,DE                        ; 2b2e
        LD A,H                           ; 2b30
        OR L                             ; 2b31
        JR z,L_2b61                      ; 2b32
        LD HL,(STORE_TMP)                ; 2b34
        LD (STORE_END),HL                ; 2b37
        CALL store_make_room             ; 2b3a
        LD HL,(STORE_END)                ; 2b3d
        LD (MOVE_DST),HL                 ; 2b40
        DEC HL                           ; 2b43
        LD (MOVE_SRC),HL                 ; 2b44
        LD DE,(STORE_CURSOR)             ; 2b47
        OR A                             ; 2b4b
        SBC HL,DE                        ; 2b4c
        LD B,H                           ; 2b4e
        LD C,L                           ; 2b4f
        LD HL,(MOVE_SRC)                 ; 2b50
        LD DE,(MOVE_DST)                 ; 2b53
        INC BC                           ; 2b57
        LDDR                             ; 2b58
        LD HL,(STORE_CURSOR)             ; 2b5a
        LD A,(CUR_CHAR)                  ; 2b5d
        LD (HL),A                        ; 2b60

L_2b61:
        POP BC                           ; 2b61
        POP HL                           ; 2b62
        INC HL                           ; 2b63
        DEC B                            ; 2b64
        JP nz,L_2ac6                     ; 2b65

; ---- pkt_process_done: clear PKT_READY/PKT_STATE, re-init and return to main loop
pkt_process_done:
        LD SP,STACK_TOP                  ; 2b68
        XOR A                            ; 2b6b
        LD (PKT_READY),A                 ; 2b6c
        LD (PKT_STATE),A                 ; 2b6f
        LD (MENU_ACTIVE),A               ; 2b72
        LD (0x433b),A                    ; 2b75
        LD HL,SEQ_LIST                   ; 2b78
        LD (SEQ_PTR),HL                  ; 2b7b
        ; B2: cmd_17_set_time clears CLK_RUN before fetching its five argument
        ; bytes; a short packet exits here through pkt_next_byte and the clock
        ; never restarts. Restoring it on the way out covers every early exit.
        CALL patch_clk_restore           ; 2b7e
        JP L_000f                        ; 2b81

sub_2b84:
        LD B,0x55                        ; 2b84
        XOR A                            ; 2b86

L_2b87:
        OUT (PORT_40_OUT),A              ; 2b87
        DJNZ L_2b87                      ; 2b89
        OUT (PORT_STROBE),A              ; 2b8b
        RET                              ; 2b8d

; ---- cmd_03_clear_all
cmd_03_clear_all:
        CALL store_clear_all             ; 2b8e
        CALL store_finalize              ; 2b91
        JP L_2cba                        ; 2b94

; ---- cmd_0E_delete_text: delete existing text of the selected channel (from INS_PTR to its 0x03 terminator)
cmd_0E_delete_text:
        LD A,(CHAN_LOCK)                 ; 2b97
        OR A                             ; 2b9a
        JP nz,L_2b61                     ; 2b9b
        LD HL,(INS_PTR)                  ; 2b9e
        DEC HL                           ; 2ba1
        LD (STORE_CURSOR),HL             ; 2ba2
        INC HL                           ; 2ba5
        LD (MOVE_DST),HL                 ; 2ba6
        EX DE,HL                         ; 2ba9
        LD HL,(STORE_LIMIT)              ; 2baa
        OR A                             ; 2bad
        SBC HL,DE                        ; 2bae
        PUSH HL                          ; 2bb0
        POP BC                           ; 2bb1
        INC BC                           ; 2bb2
        EX DE,HL                         ; 2bb3
        LD A,3                           ; 2bb4
        CPIR                             ; 2bb6
        LD A,B                           ; 2bb8
        OR C                             ; 2bb9
        JP z,L_2b61                      ; 2bba
        DEC HL                           ; 2bbd
        LD (MOVE_SRC),HL                 ; 2bbe
        LD DE,(STORE_LIMIT)              ; 2bc1
        EX DE,HL                         ; 2bc5
        OR A                             ; 2bc6
        SBC HL,DE                        ; 2bc7
        LD B,H                           ; 2bc9
        LD C,L                           ; 2bca
        INC BC                           ; 2bcb
        LD HL,(MOVE_SRC)                 ; 2bcc
        LD DE,(MOVE_DST)                 ; 2bcf
        LDIR                             ; 2bd3
        CALL store_finalize              ; 2bd5
        JP L_2b61                        ; 2bd8

; ---- cmd_B4_query: B4 n: '0' rom id, '1' memory, '2' nop, '3' dump
;      B1: the EI below plus the query -> tx_send_frame -> tx_send_byte ->
;      tx_try_queue chain (~40 bytes deep) leaves too little of the stock
;      64-byte stack for an interrupt frame + tick6_service + rx_consume.
;      Fixed by the relocated stack below; nothing here changes.
cmd_B4_query:
        CALL clear_framebuf              ; 2bdb
        CALL sub_2b84                    ; 2bde
        EI                               ; 2be1
        CALL pkt_next_byte               ; 2be2
        CP 0x30                          ; 2be5
        CALL z,query_0_romid             ; 2be7
        CP 0x31                          ; 2bea
        CALL z,query_1_memory            ; 2bec
        CP 0x32                          ; 2bef
        CALL z,sub_17ef                  ; 2bf1
        CP 0x33                          ; 2bf4
        CALL z,query_3_dump              ; 2bf6

L_2bf9:
        LD A,(TX_STATUS)                 ; 2bf9
        AND 3                            ; 2bfc
        JR nz,L_2bf9                     ; 2bfe
        DI                               ; 2c00
        JP z,L_2b61                      ; 2c01

; ---- cmd_1E_colour_A0: 1E n -> insert 0xA0|(n&15)
cmd_1E_colour_A0:
        CALL pkt_next_byte               ; 2c04
        AND 15                           ; 2c07
        OR 0xa0                          ; 2c09
        LD (CUR_CHAR),A                  ; 2c0b
        JP pkt_insert_text               ; 2c0e

; ---- cmd_15_fore_idx: 15 n -> insert FG_IDX_TABLE[n]
cmd_15_fore_idx:
        CALL pkt_next_byte               ; 2c11
        LD HL,FG_IDX_TABLE               ; 2c14
        LD C,A                           ; 2c17
        LD B,0                           ; 2c18
        ADD HL,BC                        ; 2c1a
        LD A,(HL)                        ; 2c1b
        LD (CUR_CHAR),A                  ; 2c1c
        JP pkt_insert_text               ; 2c1f

; ---- cmd_16_back_idx: 16 n -> insert BG_IDX_TABLE[n]
cmd_16_back_idx:
        CALL pkt_next_byte               ; 2c22
        LD HL,BG_IDX_TABLE               ; 2c25
        LD C,A                           ; 2c28
        LD B,0                           ; 2c29
        ADD HL,BC                        ; 2c2b
        LD A,(HL)                        ; 2c2c
        LD (CUR_CHAR),A                  ; 2c2d
        JP pkt_insert_text               ; 2c30

; ---- cmd_17_set_time: 17 h h m m a: 4 ASCII digits -> CLK_H10..CLK_M1, a=Y/y -> AM else PM.
;      B2: CLK_RUN is cleared here but restored only at 0x2C59, and every
;      pkt_next_byte below can jump straight to pkt_process_done on a short
;      packet - NETCC's "status query" 17 32 does exactly that and stops the
;      clock. Fixed in pkt_process_done below.
;      Unlike the menu's time editor (0x1D14..0x1D8A) this path does not reset
;      NMI_COUNT, so the new time starts up to one second out of phase.
cmd_17_set_time:
        XOR A                            ; 2c33
        LD (CLK_RUN),A                   ; 2c34
        LD HL,CLK_H10                    ; 2c37
        LD B,4                           ; 2c3a

L_2c3c:
        CALL pkt_next_byte               ; 2c3c
        LD (CUR_CHAR),A                  ; 2c3f
        AND 15                           ; 2c42
        LD (HL),A                        ; 2c44
        INC HL                           ; 2c45
        DJNZ L_2c3c                      ; 2c46
        CALL pkt_next_byte               ; 2c48
        AND 0x5f                         ; 2c4b
        CP 0x59                          ; 2c4d
        LD A,0xff                        ; 2c4f
        JR nz,L_2c54                     ; 2c51
        XOR A                            ; 2c53

L_2c54:
        LD (CLK_PM),A                    ; 2c54
        LD A,0xff                        ; 2c57
        LD (CLK_RUN),A                   ; 2c59
        JP L_2b61                        ; 2c5c

; ---- pkt_next_byte: Fetch next payload byte (A); if none left, jump to pkt_process_done
pkt_next_byte:
        POP IX                           ; 2c5f
        POP DE                           ; 2c61
        POP IY                           ; 2c62
        INC IY                           ; 2c64
        DEC D                            ; 2c66
        JP z,pkt_process_done            ; 2c67
        LD A,(IY+0)                      ; 2c6a
        PUSH IY                          ; 2c6d
        PUSH DE                          ; 2c6f
        PUSH IX                          ; 2c70
        RET                              ; 2c72

; ---- cmd_02_speed: 02 n -> insert 0xF0|(n&7)
cmd_02_speed:
        CALL pkt_next_byte               ; 2c73
        AND 7                            ; 2c76
        OR 0xf0                          ; 2c78
        LD (CUR_CHAR),A                  ; 2c7a
        JP pkt_insert_text               ; 2c7d

; ---- cmd_B3_append: B3: move STORE_CURSOR to end of current channel
cmd_B3_append:
        LD HL,(STORE_CURSOR)             ; 2c80

L_2c83:
        LD A,(HL)                        ; 2c83
        CP 3                             ; 2c84
        JR z,L_2c8b                      ; 2c86
        INC HL                           ; 2c88
        JR L_2c83                        ; 2c89

L_2c8b:
        DEC HL                           ; 2c8b
        LD (STORE_CURSOR),HL             ; 2c8c
        LD A,(HL)                        ; 2c8f
        CP 0xd0                          ; 2c90
        JP c,L_2b61                      ; 2c92
        CP 0xdb                          ; 2c95
        JP nc,L_2b61                     ; 2c97
        DEC HL                           ; 2c9a
        LD (STORE_CURSOR),HL             ; 2c9b
        JP L_2b61                        ; 2c9e

; ---- cmd_09_channel: 09 d d: select channel (2 ASCII digits, 0-99) ; channel 100 sets CHAN_LOCK
cmd_09_channel:
        CALL pkt_next_byte               ; 2ca1
        AND 15                           ; 2ca4
        LD (CHAN_D10),A                  ; 2ca6
        CALL pkt_next_byte               ; 2ca9
        AND 15                           ; 2cac
        LD (CHAN_D1),A                   ; 2cae
        LD B,2                           ; 2cb1
        LD HL,CHAN_D10                   ; 2cb3
        CALL ascii_dec_to_bin            ; 2cb6
        LD E,A                           ; 2cb9

L_2cba:
        PUSH DE                          ; 2cba
        CALL chan_select                 ; 2cbb
        POP DE                           ; 2cbe
        LD (INS_PTR),HL                  ; 2cbf
        DEC HL                           ; 2cc2
        DEC HL                           ; 2cc3
        LD (STORE_CURSOR),HL             ; 2cc4
        PUSH DE                          ; 2cc7
        CALL chan_find                   ; 2cc8
        POP DE                           ; 2ccb
        LD A,E                           ; 2ccc
        CP 0x64                          ; 2ccd
        JR nz,L_2cd4                     ; 2ccf
        LD (CHAN_LOCK),A                 ; 2cd1

L_2cd4:
        JP L_2b61                        ; 2cd4

; ---- cmd_04_sequence: 04 dd dd ... [D|d]: rebuild SEQ_LIST from 2-digit channel numbers
cmd_04_sequence:
        LD HL,SEQ_LIST                   ; 2cd7
        LD A,0                           ; 2cda
        LD B,0x64                        ; 2cdc

L_2cde:
        LD (HL),A                        ; 2cde
        INC HL                           ; 2cdf
        INC A                            ; 2ce0
        DJNZ L_2cde                      ; 2ce1
        LD (HL),0xff                     ; 2ce3
        INC HL                           ; 2ce5
        LD (HL),0xff                     ; 2ce6
        INC HL                           ; 2ce8
        LD (HL),0xff                     ; 2ce9
        INC HL                           ; 2ceb
        LD (HL),0xff                     ; 2cec
        LD HL,SEQ_LIST                   ; 2cee
        LD (SEQ_PTR),HL                  ; 2cf1
        LD B,0x67                        ; 2cf4

L_2cf6:
        CALL pkt_next_byte               ; 2cf6
        CP 0x44                          ; 2cf9
        JR z,L_2d3e                      ; 2cfb
        CP 0x64                          ; 2cfd
        JR z,L_2d3e                      ; 2cff
        LD (CUR_CHAR),A                  ; 2d01
        CP 0x3a                          ; 2d04
        JP nc,L_2b61                     ; 2d06
        CP 0x30                          ; 2d09
        JP c,L_2b61                      ; 2d0b
        AND 15                           ; 2d0e
        LD (CHAN_D10),A                  ; 2d10
        CALL pkt_next_byte               ; 2d13
        CP 0x44                          ; 2d16
        JR z,L_2d3e                      ; 2d18
        CP 0x64                          ; 2d1a
        JR z,L_2d3e                      ; 2d1c
        LD (CUR_CHAR),A                  ; 2d1e
        CP 0x3a                          ; 2d21
        JP nc,L_2b61                     ; 2d23
        CP 0x30                          ; 2d26
        JP c,L_2b61                      ; 2d28
        AND 15                           ; 2d2b
        LD (CHAN_D1),A                   ; 2d2d
        PUSH BC                          ; 2d30
        PUSH HL                          ; 2d31
        LD B,2                           ; 2d32
        LD HL,CHAN_D10                   ; 2d34
        CALL ascii_dec_to_bin            ; 2d37
        POP HL                           ; 2d3a
        POP BC                           ; 2d3b
        JR L_2d40                        ; 2d3c

L_2d3e:
        LD A,0x64                        ; 2d3e

L_2d40:
        LD (HL),A                        ; 2d40
        INC HL                           ; 2d41
        LD A,0xff                        ; 2d42
        LD (HL),A                        ; 2d44
        DJNZ L_2cf6                      ; 2d45
        JP L_2b61                        ; 2d47

; ---- is_ignored_byte: Z (A=0) if A is in IGNORE_TABLE: 00 01 05 08 0A 0B 0C 1C 1D 7F
is_ignored_byte:
        LD HL,IGNORE_TABLE               ; 2d4a
        LD BC,10                         ; 2d4d
        CPIR                             ; 2d50
        DEC HL                           ; 2d52
        CP (HL)                          ; 2d53
        RET nz                           ; 2d54
        XOR A                            ; 2d55
        RET                              ; 2d56

; ---- data 2d57-2d60: payload bytes silently ignored by the parser
IGNORE_TABLE:
        db 0x00,0x01,0x05,0x08,0x0a,0x0b,0x0c,0x1c,0x1d,0x7f   ; 2d57

; ---- data 2d61-2ff2: 16-bit pointers/data for big glyphs & graphics (0x2E00-0x2FF0)
GLYPH_PTR_TABLE:
        db 0x00,0x00,0x00,0xdb,0x2f,0x00,0x00,0xf3,0x2e,0x3b,0x30,0x00,0x00,0xc8,0x2f,0x52   ; 2d61
        db 0x2e,0x00,0x00,0x2f,0x30,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x59   ; 2d71
        db 0x2e,0x95,0x2f,0x60,0x2f,0x67,0x2f,0xe2,0x2e,0xeb,0x2e,0x52,0x2f,0x59,0x2f,0x00   ; 2d81
        db 0x00,0xfa,0x2e,0xb9,0x2f,0xcf,0x2f,0xd4,0x2f,0x00,0x00,0x9b,0x2f,0xe3,0x2f,0xeb   ; 2d91
        db 0x2f,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x31,0x00,0x00   ; 2da1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x32,0x00,0x00   ; 2db1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x33,0x00,0x00   ; 2dc1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x34,0x00,0x00   ; 2dd1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x35,0x00,0x00   ; 2de1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x36,0x00,0x00   ; 2df1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x37,0x00,0x00   ; 2e01
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x38,0x00,0x00   ; 2e11
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x39,0x00,0x00   ; 2e21
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x31,0x30,0x00,0x00   ; 2e31
        db 0x00,0x54,0x4f,0x50,0x20,0x44,0x45,0x4d,0x4f,0x20,0x4d,0x53,0x47,0x20,0x00,0x00   ; 2e41
        db 0x00,0x15,0x42,0x45,0x45,0x50,0x16,0x00,0x15,0x52,0x49,0x47,0x48,0x54,0x16,0x00   ; 2e51
        db 0x00,0x88,0x30,0x90,0x30,0x98,0x30,0xa0,0x30,0xa8,0x30,0xb0,0x30,0xb8,0x30,0xc0   ; 2e61
        db 0x30,0xc7,0x30,0xcf,0x30,0xd7,0x30,0xdf,0x30,0xe7,0x30,0xed,0x30,0xf6,0x30,0xfd   ; 2e71
        db 0x30,0xa2,0x2e,0xaa,0x2e,0xba,0x2e,0xb2,0x2e,0xa2,0x2e,0xaa,0x2e,0xba,0x2e,0xb2   ; 2e81
        db 0x2e,0xa2,0x2e,0xaa,0x2e,0xba,0x2e,0xb2,0x2e,0xa2,0x2e,0xaa,0x2e,0xba,0x2e,0xb2   ; 2e91
        db 0x2e,0x15,0x42,0x2d,0x42,0x4c,0x4b,0x16,0x00,0x15,0x42,0x2d,0x52,0x45,0x44,0x16   ; 2ea1
        db 0x00,0x15,0x42,0x2d,0x59,0x45,0x4c,0x16,0x00,0x15,0x42,0x2d,0x47,0x52,0x45,0x16   ; 2eb1
        db 0x00,0x8f,0x2f,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; 2ec1
        db 0x00,0x6e,0x2f,0x75,0x2f,0x7c,0x2f,0xc1,0x2f,0xa3,0x2f,0xad,0x2f,0x2e,0x31,0x00   ; 2ed1
        db 0x00,0x15,0x49,0x54,0x41,0x4c,0x49,0x43,0x16,0x00,0x15,0x46,0x4c,0x41,0x53,0x48   ; 2ee1
        db 0x16,0x00,0x15,0x45,0x4e,0x44,0x16,0x00,0x00,0x15,0x4c,0x45,0x46,0x54,0x16,0x00   ; 2ef1
        db 0x00,0xa2,0x2d,0xb2,0x2d,0xc2,0x2d,0xd2,0x2d,0xe2,0x2d,0xf2,0x2d,0x02,0x2e,0x12   ; 2f01
        db 0x2e,0x22,0x2e,0x32,0x2e,0x42,0x2e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; 2f11
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; 2f21
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   ; 2f31
        db 0x00,0x06,0x31,0x0b,0x31,0x10,0x31,0x15,0x31,0x1a,0x31,0x1f,0x31,0x24,0x31,0x29   ; 2f41
        db 0x31,0x15,0x43,0x4f,0x4c,0x4f,0x52,0x00,0x15,0x42,0x47,0x52,0x4e,0x44,0x00,0x15   ; 2f51
        db 0x4e,0x4f,0x52,0x4d,0x16,0x00,0x15,0x42,0x4f,0x4c,0x44,0x16,0x00,0x15,0x44,0x52   ; 2f61
        db 0x41,0x57,0x16,0x00,0x15,0x54,0x48,0x49,0x4e,0x16,0x00,0x15,0x57,0x41,0x49,0x54   ; 2f71
        db 0x16,0x00,0x15,0x46,0x55,0x4e,0x43,0x00,0x15,0x45,0x55,0x52,0x4f,0x00,0x15,0x52   ; 2f81
        db 0x45,0x4d,0x16,0x00,0x15,0x42,0x49,0x47,0x16,0x00,0x15,0x53,0x48,0x49,0x46,0x54   ; 2f91
        db 0x16,0x00,0x15,0x52,0x41,0x49,0x4e,0x42,0x4f,0x57,0x16,0x00,0x15,0x4d,0x41,0x47   ; 2fa1
        db 0x49,0x43,0x20,0x4f,0x46,0x46,0x16,0x00,0x15,0x50,0x41,0x55,0x53,0x45,0x16,0x00   ; 2fb1
        db 0x15,0x48,0x4f,0x4c,0x44,0x16,0x00,0x15,0x48,0x41,0x4c,0x54,0x16,0x00,0x15,0x55   ; 2fc1
        db 0x50,0x16,0x00,0x15,0x44,0x4f,0x57,0x4e,0x16,0x00,0x15,0x53,0x50,0x45,0x45,0x44   ; 2fd1
        db 0x20,0x00,0x15,0x47,0x52,0x41,0x50,0x48,0x20,0x00,0x15,0x4d,0x41,0x47,0x49,0x43   ; 2fe1
        db 0x16,0x00   ; 2ff1

; ---- data 2ff3-3134: NUL-terminated menu prompts and the 16 foreground colour names in code order 0x80..0x8F (BLACK,D-GRE,M-GRE,GREEN,D-RED,D-YEL,D-LIM,LIME,M-RED,D-ORA,M-YEL,LEMON,RED,ORANGE,GOLD,YELLOW), speeds S0..S7, TINY
MENU_STRINGS:
        db " ADDRESS? ",0x00   ; 2ff3
        db " FULL!! MSG# ?",0x00   ; 2ffe
        db " CLR ALL Y/N",0x00   ; 300d
        db " TIME?    ",0x00   ; 301a
        db " AM? Y/N ",0x00   ; 3025
        db " PROG MSG? ",0x00   ; 302f
        db " SEQ MSG? ",0x00   ; 303b
        db 0x03,"    INVALID    ",0x00   ; 3046
        db 0x0a," MEMORY FULL  ",0x00   ; 3057
        db 0x05," 100 KEYS LEFT ",0x00   ; 3067
        db 0x03," SEQUENCE FULL",0x00   ; 3078
        db 0x15,"BLACK",0x16,0x00   ; 3088
        db 0x15,"D-GRE",0x16,0x00   ; 3090
        db 0x15,"M-GRE",0x16,0x00   ; 3098
        db 0x15,"GREEN",0x16,0x00   ; 30a0
        db 0x15,"D-RED",0x16,0x00   ; 30a8
        db 0x15,"D-YEL",0x16,0x00   ; 30b0
        db 0x15,"D-LIM",0x16,0x00   ; 30b8
        db 0x15,"LIME",0x16,0x00   ; 30c0
        db 0x15,"M-RED",0x16,0x00   ; 30c7
        db 0x15,"D-ORA",0x16,0x00   ; 30cf
        db 0x15,"M-YEL",0x16,0x00   ; 30d7
        db 0x15,"LEMON",0x16,0x00   ; 30df
        db 0x15,"RED",0x16,0x00   ; 30e7
        db 0x15,"ORANGE",0x16,0x00   ; 30ed
        db 0x15,"GOLD",0x16,0x00   ; 30f6
        db 0x15,"YELLOW",0x16,0x00   ; 30fd
        db 0x15,"S0",0x16,0x00   ; 3106
        db 0x15,"S1",0x16,0x00   ; 310b
        db 0x15,"S2",0x16,0x00   ; 3110
        db 0x15,"S3",0x16,0x00   ; 3115
        db 0x15,"S4",0x16,0x00   ; 311a
        db 0x15,"S5",0x16,0x00   ; 311f
        db 0x15,"S6",0x16,0x00   ; 3124
        db 0x15,"S7",0x16,0x00   ; 3129
        db 0x15,"TINY",0x16,0x00   ; 312e

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
        db 0x07,0x07,0x07,0x02,0x07,0x07,0x02,0x02           ; glyph 191 width 2
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x02           ; glyph 192 width 2
        db 0x02,0x02,0x02,0x02,0x02,0x00,0x00,0x00           ; glyph 193 width 0
        db 0x02,0x02,0x02,0x02,0x07,0x07,0x07,0x02           ; glyph 194 width 2
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 195 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 196 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 197 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 198 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 199 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 200 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 201 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 202 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 203 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 204 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 205 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 206 width 0
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02           ; glyph 207 width 2
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02           ; glyph 208 width 2
        db 0x02,0x02,0x02,0x02,0x00,0x00,0x00,0x00           ; glyph 209 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07           ; glyph 210 width 7
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 211 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 212 width 0
        db 0x02,0x07,0x07,0x07,0x07,0x07,0x07,0x07           ; glyph 213 width 7
        db 0x00,0x02,0x02,0x02,0x02,0x02,0x02,0x07           ; glyph 214 width 7
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 215 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 216 width 0
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02           ; glyph 217 width 2
        db 0x02,0x02,0x02,0x07,0x00,0x00,0x00,0x00           ; glyph 218 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 219 width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 220 width 0
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02           ; glyph 221 width 2
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07           ; glyph 222 width 7

; ---- data 382d-386c: glyph-order character lists used by char_to_glyph (lower-case font)
CHARSET_LOWER:
        db "kf",0x12,"pa",0x0e,0x11,0x1e," ",0x7f,")%zwyt"   ; 382d
        db "ni",0x1f,"hd",0x09,0x1a,0x19,"0",0x1d,"2586k",0x00   ; 383d
        db "lgvmq",0x04,0x10,0x14,".",0x1c,"(*+9xs"   ; 384d
        db "ojbce",0x0d,0x07,0x15,0x08,0x0a,"1473ur"   ; 385d

; ---- data 386d-38ac: 
CHARSET_UPPER:
        db "KF",0x12,"PA",0x0e,0x11,0x1e," ",0x7f,")%ZWYT"   ; 386d
        db "NI",0x1f,"HD",0x09,0x1a,0x19,"0",0x1d,"2586K",0x00   ; 387d
        db "LGVMQ",0x04,0x10,0x14,".",0x1c,"(*+9XS"   ; 388d
        db "OJBCE",0x0d,0x07,0x15,0x08,0x0a,"1473UR"   ; 389d

; ---- data 38ad-38ec: 
CHARSET_UPPER2:
        db "KF",0x18,"PA",0x03,0x17,"_ ",0x7f,"&'ZWYT"   ; 38ad
        db "NI",0xbd,"HD",0x02,0x1b,0x19,"0",0x1d,"2586K",0x00   ; 38bd
        db "LGVMQ",0xbb,0x13,0x14,":",0xb6,"$#-9XS"   ; 38cd
        db "OJBCE",0xb7,0x0f,0x16,0x0b,0x0c,"1473UR"   ; 38dd

; ---- data 38ed-392c: 
CHARSET_LOWER2:
        db "kf",0x18,"pa",0x03,0x17,"_ ",0x7f,"&'zwyt"   ; 38ed
        db "ni",0xbd,"hd",0x02,0x1b,0x19,"0",0x1d,"2586k",0x00   ; 38fd
        db "lgvmq",0xbb,0x13,0x14,":",0xb6,"$#-9xs"   ; 390d
        db "ojbce",0xb7,0x0f,0x16,0x0b,0x0c,"1473ur"   ; 391d

; ---- data 392d-396e: graphic / extended characters 0x94-0x9D, 0xC0-0xCF, 0xE0-0xEF
CHARSET_GRAPHICS:
        db 0xca,0xc5,0x12,0xcf,0xc0,0xde,0x11,0x1e,0x9e,0x7f,0x9d,0x96,0xed,0xe6,0xe8,0xe3   ; 392d
        db 0xcd,0xc8,0x1f,0xc7,0xc3,0xdc,0x1a,0x19,0x9b,0x1d,0x98,0xef,0xea,0x94,0xca,0x00   ; 393d
        db 0xcb,0xc6,0xe5,0xcc,0xe0,0xdd,0x10,0x14,0x9c,0x1c,0x9a,0x95,0xec,0xeb,0xe7,0xe2   ; 394d
        db 0xce,0xc9,0xc1,0xc2,0xc4,0xdf,0x07,0x15,0x08,0x0a,0x97,0xee,0xe9,0x99,0xe4,0xe1   ; 395d
        db 0xda,0xda   ; 396d

; ---- data 396f-3c20: built-in demonstration message (contains control codes 10,11,12,13,14,BC,BE,8x colours,A2-AB graphics)
DEMO_MESSAGE:
        db "THE ",0x12,0x14,"ULTIMATE ",0x11,0x8c,"INFRARED ",0xbc,"REMOTE CONTROL MULTI-"   ; 398f
        db "COLOR DISPLAY..... ",0x10,"** MAGIC ** ",0x11,"AUTOMATIC COLOR CHANGING....."
        db "PLUS.....",0xbc,0x14,"RAINBOW ",0x11,"PROGRAMMING IN ",0x10,"10 ",0x11,"VIBRANT"
        db " COLORS ",0x8c,"llllllllll ",0x83,"llllllllll ",0x8f,"llllllllll ",0x8d,"llllll" ; 3a2f
        db "llll ",0x87,"llllllllll ",0xbc,">>>>> NETWORKABLE <<<<< INCLUDES PC FLOPPY DISK"
        db " & CABLE .....",0x12,"8K ",0x11,"MEMORY .....",0x83,0x12,"100 ",0x11,0xbc,"MEMORY"
        db " BANKS ..... ",0x10,"14 ",0x11,"CHARACTERS OR ",0xbe,"28 TINY CHARACTERS ",0xbc
        db "..... PROGRAMS ",0x10,"47 ",0x13,"EUROPEAN ",0x11,"CHARACTERS ..... ",0x12
        db "8 ",0x11,"SPEEDS ....UPPER & lower FONTS ..... ",0x10,"36 SPECIAL FUNCTIONS "
        db 0x11,".....INCLUDING...... CLOCK _",0x14,"  FLASH ",0x11,".....BEEP ",0x07,0x07
        db " ",0x07,"..... ",0x12,"BOLD ...... ",0x13,"ITALIC ",0x11,".....",0x14,"AND ...." ; 3b9f
        db ". CUSTOM GRAPHICS ",0xa2,0xa3,0xa5,0xaa,0xab,"..... OR YOUR OWN LOGO..... "
        db 0xbe,"TINY PRICE          ",0x10,"LARGE  IMPACT!!",0x03,0xdb,"CURRENT TEST  "
        db 0x10,0x17,0x17,0x17,0x17,0x17,0x17,0x17," ",0x03   ; 3c1f

; ============================================================================
;  Patch spill-over. 0x3C21..0x7FFF is 0xFF in the dump; code placed here
;  cannot shift any stock address.
; ============================================================================

; ---- patch_store_term: write the 0xDA store terminator at STORE_LIMIT.
;      Called from ir_init, which needs HL/BC left pointing at the RAM page
;      it is about to clear.
patch_store_term:
        PUSH HL
        LD HL,(STORE_LIMIT)
        LD (HL),0xda
        POP HL
        RET

; ---- patch_clk_restore: restart the clock, then tail into sub_2b84.
;      Replaces the CALL sub_2b84 in pkt_process_done so a packet that ends
;      mid-cmd_17 cannot leave CLK_RUN at 0. The menu's own time editor does
;      the same thing at 0x1D8A.
patch_clk_restore:
        LD A,0xff
        LD (CLK_RUN),A
        JP sub_2b84


        ds 0x8000-$,0xff        ; unused upper half of the 27C256
