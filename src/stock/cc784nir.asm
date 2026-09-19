; ============================================================================
;  Color Cells CC784NIR LED sign - firmware source, reconstructed from EPROM
;  Assemble:  sjasmplus cc784nir.asm   (produces cc784nir.bin, 32768 bytes)
;  Byte-identical to the original M27C256B dump:
;      md5 c021af146a50b93a22d13535201b7eaa
;  FROZEN. Annotations may be added; code must not change. The patched
;  variant is ../patched/cc784nir.asm.
;  See CC784NIR_annotated.asm for the listing with addresses/hex and full notes.
; ============================================================================
        DEVICE NONE
        OUTPUT "cc784nir.bin"

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

; ---- RAM locations the reconstruction never named. Those with a real
;      name below are the ones whose purpose is established; VAR_xxxx is
;      an honest placeholder, not an abbreviation - rename as they are
;      traced. Listed so no bare hex address is left in the code.
MENU_MSG_PTR         equ 0x420a   ; message the editor is showing (set with MENU_MSG_FLAG)
VAR_420F             equ 0x420f
VAR_4213             equ 0x4213
VAR_4214             equ 0x4214
VAR_421B             equ 0x421b
VAR_421D             equ 0x421d
VAR_421E             equ 0x421e
VAR_421F             equ 0x421f
VAR_4220             equ 0x4220
VAR_4221             equ 0x4221
MENU_MSG_FLAG        equ 0x4224   ; FF = editor has a message to display
VAR_4226             equ 0x4226
VAR_4227             equ 0x4227
VAR_4229             equ 0x4229
VAR_4236             equ 0x4236
VAR_4241             equ 0x4241
VAR_4242             equ 0x4242
VAR_4243             equ 0x4243
VAR_4244             equ 0x4244
VAR_424C             equ 0x424c
VAR_425A             equ 0x425a
VAR_425E             equ 0x425e
VAR_4260             equ 0x4260
VAR_42D6             equ 0x42d6
VAR_42F6             equ 0x42f6
VAR_4316             equ 0x4316
VAR_4336             equ 0x4336
SHIFT_STATE          equ 0x4337   ; SHIFT latch, toggled by key 29 (see section 9)
VAR_4338             equ 0x4338
VAR_433B             equ 0x433b
VAR_4344             equ 0x4344
VAR_4358             equ 0x4358
VAR_435A             equ 0x435a
VAR_4360             equ 0x4360
VAR_4361             equ 0x4361
VAR_4362             equ 0x4362
VAR_4363             equ 0x4363
VAR_4364             equ 0x4364
VAR_4365             equ 0x4365
VAR_4377             equ 0x4377
VAR_4381             equ 0x4381
VAR_4387             equ 0x4387
VAR_438C             equ 0x438c
VAR_438F             equ 0x438f
VAR_4390             equ 0x4390
VAR_4391             equ 0x4391
VAR_4392             equ 0x4392
VAR_4395             equ 0x4395
VAR_4399             equ 0x4399
VAR_439A             equ 0x439a
VAR_439B             equ 0x439b
VAR_43A2             equ 0x43a2
VAR_43A3             equ 0x43a3
VAR_43A4             equ 0x43a4
VAR_43A5             equ 0x43a5
VAR_43CA             equ 0x43ca
VAR_43CD             equ 0x43cd
VAR_43CF             equ 0x43cf
VAR_43D2             equ 0x43d2
VAR_43D4             equ 0x43d4
VAR_43D6             equ 0x43d6
KEY_ECHO_TX          equ 0x43d7   ; non-zero = echo accepted keys on serial TX
VAR_43DC             equ 0x43dc
VAR_43DE             equ 0x43de

        org 0x0000

; ---- RESET: cold start: set SP, run init routines, EI, jump to main loop
RESET:
        LD SP,0x403f
        CALL init_vars
        CALL ir_init
        CALL ir_init2
        CALL init_vars3

L_000f:
        CALL init_render
        CALL init_vars2
        CALL init_sequence
        EI
        JP main_loop

; ---- pad to 0x0038, the Z80's fixed IM 1 interrupt vector
        ds 0x0038-$,0xff

; ---- INT_VECTOR: IM1 interrupt entry (periodic timer, ~1300 Hz)
INT_VECTOR:
        JP int_timer

; ---- pad to 0x0048, where the ID string sits
        ds 0x0048-$,0xff

; ---- data 0048-0057: 16-byte firmware ID, returned by query B4 '0'
ROM_ID:
        db "78409O1702930205"

; ---- pad to 0x0066, the Z80's fixed NMI vector
        ds 0x0066-$,0xff

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

; ---- int_timer: Timer ISR. Every 6th tick schedules tick6_service; every tick schedules the handler in TICK_VECTOR (IR decoder). Both are invoked by pushing their address so they run as the ISR returns.
int_timer:
        EX AF,AF'
        EXX
        LD A,(TICK6_COUNT)
        INC A
        CP 6
        JR nz,L_0082
        LD HL,0xc4
        PUSH HL
        XOR A

L_0082:
        LD (TICK6_COUNT),A
        LD A,(TICK1_COUNT)
        INC A
        CP 1
        JR nz,L_0092
        LD HL,(TICK_VECTOR)
        PUSH HL
        XOR A

L_0092:
        LD (TICK1_COUNT),A
        EX AF,AF'
        EXX
        EI
        RETI

; ---- main_loop: Main loop: if PKT_READY process packet, else init/render/effect step, then loop.
;      The PKT_READY test runs ONCE on entry - L_00a7 below never falls back
;      to 0x009A. Re-entry only happens via fx_end_of_channel (0x0F5E) at the
;      end of a display cycle, or the BA wait-for-key spin at 0x0A49. That is
;      why NETCC sets PKT_FLAG=0x80: deferred packets wait for the current
;      channel to finish, which can be many seconds.
main_loop:
        LD A,(PKT_READY)
        AND A
        JP nz,pkt_process
        CALL init_render
        CALL init_display_state

L_00a7:
        CALL render_next_char
        CALL effect_step
        ; LD A,(nn) sets no flags, so this JR tests effect_step's exit flags,
        ; not RENDER_DONE. A is loaded for whatever runs after the branch.
        LD A,(RENDER_DONE)
        JR nz,L_00a7
        XOR A
        LD (COL_COUNT),A
        LD HL,fx_none
        LD (PAUSE_FLAG),A
        LD (EFFECT_VECTOR),HL
        JR L_00a7
        db 0xc3,0xa7,0x00

; ---- tick6_service: Runs every 6 timer ticks: serial RX/TX bit engines, countdowns, display column refresh & flashing, then the RX byte consumer.
tick6_service:
        PUSH AF
        LD A,(IX+0)
        CP 0xaa
        JR nz,L_00d5
        LD A,(IY+0)
        CP 0x55
        JR nz,L_00d5
        POP AF
        RET

L_00d5:
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
        JR z,L_00e9
        LD (GEN_COUNTDOWN),HL

L_00e9:
        CALL rx_bit_engine
        CALL tx_bit_engine
        LD HL,(TICK_COUNTDOWN)
        LD A,H
        OR L
        JR z,L_00fa
        DEC HL
        LD (TICK_COUNTDOWN),HL

L_00fa:
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,L_0125
        LD A,(PAUSE_FLAG)
        AND A
        JR nz,L_0125
        LD A,(TINY_RENDER)
        AND A
        JP nz,L_124b
        LD A,(BLANK_TIMER)
        AND A
        JR z,L_0125
        DEC A
        LD (BLANK_TIMER),A
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        JP L_030d

L_0125:
        LD A,(DISP_ENABLE)
        AND A
        JP z,L_01ce
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,(EFFECT_ACTIVE)
        AND A
        JP z,L_01b9
        LD HL,(SEQ_PTR_SAVE)
        LD A,(DISP_FLAGS)
        LD B,A
        LD A,(FLASH_TIMER)
        LD C,A
        LD A,(ROW_INDEX)
        CPL
        AND 7
        DEC A
        OR C
        LD C,A
        PUSH IX
        LD IX,TICK_COUNTDOWN
        LD A,(IX+0)
        OR (IX+1)
        POP IX
        JR z,L_0164
        SET 5,C

L_0164:
        LD A,(ROW_DATA_LATCH)
        OUT (C),A
        LD A,B
        AND A
        JR z,L_0182
        BIT 0,B
        JR z,L_0174
        DEC B
        JR z,L_017f

L_0174:
        OTIR
        LD A,(DISP_FLAGS)
        BIT 0,A
        JR z,L_0182
        LD B,1

L_017f:
        LD A,(HL)
        OUT (C),A

L_0182:
        LD A,(FB_EXTRA_LEN)
        AND A
        JR z,L_018e
        LD B,A
        LD HL,FRAMEBUF
        OTIR

L_018e:
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x70
        OR 15
        LD (CTRL_LATCH),A
        OUT (PORT_STROBE),A
        LD A,(ROW_INDEX)
        CPL
        AND 7
        DEC A
        JR nz,L_01a5
        LD A,7

L_01a5:
        LD C,A
        LD A,(VAR_421F)
        OR C
        AND 0x8f
        LD C,A
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x70
        OR C
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A

L_01b9:
        LD A,(FLASH_TIMER)
        CP 0x48
        JR z,L_01c7
        LD A,0x48
        LD (FLASH_TIMER),A
        JR L_01cb

L_01c7:
        XOR A
        LD (DISP_ENABLE),A

L_01cb:
        JP L_030d

L_01ce:
        LD A,(ROW_INDEX)
        LD C,A
        INC A
        LD (ROW_INDEX),A
        CP 7
        JP c,L_0303
        LD A,0
        LD (ROW_INDEX),A
        LD A,(VAR_43CD)
        LD (BLANK_TIMER),A
        LD A,(VAR_4244)
        AND A
        JR z,L_01f3
        DEC A
        LD (VAR_4244),A
        JP L_0281

L_01f3:
        LD A,(EFFECT_PHASE)
        AND A
        JR z,L_022a
        LD HL,(FB_COL)
        LD DE,0x56
        CALL sub_0e2d
        LD DE,(FB_COLPTR)
        OR A
        SBC HL,DE
        JR z,L_0223
        LD HL,(FB_COL)
        CALL sub_0e16
        LD (FB_COL),HL
        LD DE,0x56
        CALL sub_0e2d
        LD DE,(FB_COLPTR)
        OR A
        SBC HL,DE
        JR nz,L_0237

L_0223:
        XOR A
        LD (EFFECT_PHASE),A
        JP L_0237

L_022a:
        LD HL,(SEQ_PTR_SAVE)
        LD DE,(FB_COL)
        OR A
        SBC HL,DE
        JP z,L_0281

L_0237:
        LD HL,(FB_COL)
        BIT 7,(HL)
        JR z,L_0242
        LD A,(HL)
        LD (VAR_421B),A

L_0242:
        LD A,(PAUSE_FLAG)
        AND A
        LD A,(VAR_421B)
        JR z,L_024f
        AND 0x10
        OR 0x8f

L_024f:
        LD (ROW_DATA_LATCH),A
        LD HL,(FB_COL)
        LD (SEQ_PTR_SAVE),HL
        LD HL,FB_COLPTR
        LD BC,(FB_COL)
        LD DE,0x56
        XOR A
        SBC HL,BC
        XOR A
        LD (DISP_FLAGS),HL
        EX DE,HL
        SBC HL,DE
        JP z,L_0275
        JP c,L_0275
        JP L_027e

L_0275:
        LD HL,0x56
        LD (DISP_FLAGS),HL
        LD HL,0

L_027e:
        LD (FB_EXTRA_LEN),HL

L_0281:
        LD A,(VAR_421D)
        INC A
        LD (VAR_421D),A
        CP 13
        JR nz,L_02a1
        XOR A
        LD (VAR_421D),A
        LD A,(VAR_421F)
        AND A
        JR z,L_029c
        XOR A
        LD (VAR_421F),A
        JR L_02a1

L_029c:
        LD A,0x80
        LD (VAR_421F),A

L_02a1:
        NOP

; ---- rx_consume: Pop a byte from RX_FIFO; in normal mode feed the packet parser (or if IR_CODE=A4/A5 handle keypad); packet start needs 0xB1 while idle
rx_consume:
        LD A,(MENU_ACTIVE)
        AND A
        JP nz,tick6_exit
        CALL rx_fifo_get
        JP nc,L_02ca
        LD A,(IR_CODE)
        CP 0xa4
        JP z,L_02c4
        CP 0xa5
        JP nz,tick6_exit
        LD A,0x20
        LD (RX_BYTE),A
        JP tick6_exit

L_02c4:
        LD (IR_KEY),A
        JP key_handler

L_02ca:
        LD A,(PKT_STATE)
        AND A
        JR z,L_02d6
        CALL pkt_feed_byte
        JP tick6_exit

L_02d6:
        LD A,(RX_BYTE)
        CP 0xb1
        JR nz,L_02f1
        LD A,(PKT_READY)
        AND A
        JR nz,tick6_exit
        LD A,0xff
        LD (PKT_STATE),A
        LD HL,pkt_st_addr
        LD (PKT_VECTOR),HL
        JP tick6_exit

L_02f1:
        LD A,(RX_BYTE)
        CP 1
        JP z,key_handler

; ---- tick6_exit
tick6_exit:
        LD A,(BEEP_TIMER)
        AND A
        JR z,L_0303
        DEC A
        LD (BEEP_TIMER),A

L_0303:
        LD A,0xff
        LD (DISP_ENABLE),A
        LD A,0x40
        LD (FLASH_TIMER),A

L_030d:
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- init_sequence: Init SEQ_LIST (0x68 bytes) etc.
init_sequence:
        XOR A
        LD (SEQ_IDX),A
        LD B,0x68
        LD HL,SEQ_LIST
        LD A,(HL)
        CP 0xff
        JR z,L_0336

L_0324:
        CP 0x65
        JR nc,L_0332
        INC HL
        LD A,(HL)
        DJNZ L_0324
        DEC HL
        LD (HL),0xff
        JP L_034d

L_0332:
        CP 0xff
        JR z,L_034d

L_0336:
        LD HL,SEQ_LIST
        LD A,0
        LD B,0x64

L_033d:
        LD (HL),A
        INC HL
        INC A
        DJNZ L_033d
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff

L_034d:
        LD HL,SEQ_LIST

L_0350:
        LD A,(HL)
        INC HL
        PUSH HL
        CP 0xff
        JR z,L_0366
        CALL chan_select
        OR A
        JP nz,pkt_process_end
        LD A,(HL)
        CP 3
        POP HL
        RET nz
        JP L_0350

L_0366:
        POP HL
        LD A,10
        LD (SEQ_IDX),A
        RET

; ---- init_display_state
init_display_state:
        LD A,(VAR_420F)
        INC A
        JP z,L_0410
        LD A,(MENU_FLAG)
        CP 0x64
        JP nc,L_0386
        LD E,A
        LD A,0xff
        LD (MENU_FLAG),A
        LD A,E
        JP L_03ae

L_0386:
        LD A,(SEQ_IDX)
        LD E,A
        CP 10
        LD A,0x64
        JR z,L_03ae
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JR nz,L_03a1
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        JP init_display_state

L_03a1:
        CP 0x65
        JR c,L_03a9
        LD A,0x64
        LD (HL),0x64

L_03a9:
        LD E,A
        INC HL
        LD (SEQ_PTR),HL

L_03ae:
        LD E,A
        PUSH DE
        CALL chan_select
        POP DE
        OR A
        JP nz,pkt_process_end
        LD A,(HL)
        CP 3
        JR z,L_03f8
        PUSH HL
        LD B,0
        LD C,A
        LD IX,CHAR_FLAGS
        ADD IX,BC
        BIT 1,(IX+0)
        JR z,L_03e6

L_03cd:
        INC HL
        LD A,(HL)
        CP 3
        JR nz,L_03d7
        POP HL
        JP L_03f8

L_03d7:
        LD B,0
        LD C,A
        LD IX,CHAR_FLAGS
        ADD IX,BC
        BIT 1,(IX+0)
        JR nz,L_03cd

L_03e6:
        POP HL
        LD (STORE_CURSOR),HL
        PUSH DE
        CALL chan_find
        POP DE
        LD A,E
        CP 0x64
        JR nz,L_03f7
        LD (CHAN_LOCK),A

L_03f7:
        RET

L_03f8:
        LD HL,(SEQ_PTR)
        LD A,(HL)
        CP 0xff
        JP nz,init_display_state
        DEC HL
        LD DE,SEQ_LIST
        OR A
        SBC HL,DE
        JP nz,init_display_state
        LD A,0x64
        JP L_03ae

L_0410:
        LD HL,VAR_43A5
        LD (STORE_CURSOR),HL
        CALL chan_find
        RET

; ---- chan_find: Locate channel marker (D0+n) in MSG_STORE
chan_find:
        LD HL,VAR_4260
        LD B,11
        LD A,0

L_0421:
        LD (HL),A
        INC HL
        DJNZ L_0421
        RET

; ---- chan_select: Select channel E: find/create its slot in MSG_STORE, set INS_PTR/STORE_CURSOR
chan_select:
        CP 0x64
        JR nz,L_0430
        LD HL,DEMO_MESSAGE
        JP L_046e

L_0430:
        LD DE,0xd0d0
        AND A
        JR z,L_0445
        LD B,A
        LD A,0xda

L_0439:
        INC E
        CP E
        JR nz,L_0443
        LD E,0xd0
        INC D
        CP D
        JR z,L_0470

L_0443:
        DJNZ L_0439

L_0445:
        LD IX,MSG_STORE
        LD BC,(STORE_SIZE)

L_044d:
        LD A,(IX+0)
        CP 0xda
        JR z,L_0470
        LD H,A
        LD L,(IX+1)
        OR A
        SBC HL,DE
        JR z,L_0467
        INC IX
        DEC BC
        LD A,C
        OR B
        JR nz,L_044d
        JP z,L_0470

L_0467:
        INC IX
        INC IX
        PUSH IX
        POP HL

L_046e:
        XOR A
        RET

L_0470:
        LD A,0xff
        RET

; ---- init_vars2
init_vars2:
        CALL sub_04e5
        CALL sub_050f
        LD HL,MSG_STORE
        LD A,0xd0
        LD D,0xd0
        LD E,A
        LD BC,(VAR_43DC)

L_0485:
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,0xda
        INC D
        CP D
        JR nz,L_0493
        LD D,0xd0
        INC E
        JR L_049a

L_0493:
        CP E
        JR nz,L_049a
        DEC HL
        JP L_04dc

L_049a:
        DEC HL
        DEC HL
        LD (HL),0x20
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        CP 0xd0
        JP c,L_04ae
        CP 0xdb
        JP nc,L_04ae
        LD (HL),0x20

L_04ae:
        INC HL

L_04af:
        LD A,(HL)
        CP 0xd0
        JP c,L_04bc
        CP 0xdb
        JP nc,L_04bc
        JR L_0485

L_04bc:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR z,L_04c5
        JP L_04af

L_04c5:
        LD A,0xda

L_04c7:
        LD (HL),E
        CP E
        JR z,L_04dc
        INC HL
        LD (HL),D
        INC HL
        LD (HL),3
        INC HL
        INC D
        CP D
        JR nz,L_04c7
        LD D,0xd0
        INC E
        CP E
        JR nz,L_04c7
        LD (HL),A

L_04dc:
        PUSH HL
        CALL sub_0524
        POP HL
        LD A,0xda
        LD (HL),A
        RET

sub_04e5:
        LD HL,MSG_STORE
        LD BC,(STORE_SIZE)
        LD IY,VAR_4363
        LD (IY+0),0
        LD D,0

L_04f6:
        LD E,(HL)
        LD IX,CHAR_FLAGS
        ADD IX,DE
        BIT 0,(IX+0)
        JR z,L_0508
        LD (HL),0x3f
        INC (IY+0)

L_0508:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,L_04f6
        RET

sub_050f:
        LD HL,MSG_STORE
        LD BC,(STORE_SIZE)

L_0516:
        LD A,(HL)
        CP 3
        JR nz,L_051d
        LD (HL),0x20

L_051d:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,L_0516
        RET

sub_0524:
        LD IX,MSG_STORE+2
        LD BC,(STORE_SIZE)
        DEC BC
        DEC BC

L_052e:
        LD A,(IX+0)
        CP 0xd0
        JP c,L_0545
        CP 0xdb
        JP nc,L_0545
        LD (IX-1),3
        INC IX
        DEC BC
        LD A,C
        OR B
        RET z

L_0545:
        INC IX
        DEC BC
        LD A,C
        OR B
        JR nz,L_052e
        RET

; ---- init_vars3: NMI_PER_SEC = 60 -> NMI is a 60 Hz (mains) tick
init_vars3:
        LD A,0x3c
        LD (NMI_PER_SEC),A
        RET

; ---- init_vars: Power-on RAM init: copies the blocks out of INIT_DATA,
;      validates MY_ADDRESS/MY_ADDRESS_INV (resets it if corrupt)
init_vars:
        XOR A
        LD (TINY_RENDER),A
        LD (ROW_PHASE),A
        LD HL,MENU_ENTRY_BUF
        LD B,5

L_055f:
        LD (HL),A
        INC HL
        DJNZ L_055f
        LD (VAR_439B),A
        LD (VAR_4360),A
        LD (VAR_4364),A
        LD (VAR_4213),A
        LD (VAR_4361),A
        LD (VAR_43A2),A
        LD (MENU_TMP2),A
        LD (MENU_TMP),A
        LD (VAR_43A4),A
        LD (VAR_439A),A
        LD (VAR_4399),A
        LD (VAR_4395),A
        LD (VAR_4391),A
        LD (VAR_43A3),A
        LD (VAR_43D6),A
        LD (KEY_ECHO_TX),A
        LD (VAR_43CF),A
        LD (VAR_43CA),A
        LD (VAR_43CD),A
        LD (BLANK_TIMER),A
        LD (TICK6_COUNT),A
        LD A,0xff
        LD (MENU_FLAG),A
        LD A,0x20
        LD (MENU_CHAR),A
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
        JR z,L_05cc
        ; B5/B7: defaults to address 0 (which the menu itself refuses to set),
        ; and stores 0x00 in BOTH bytes - CPL(00)=FF != 00, so the pair never
        ; validates and this path re-runs on every single boot.
        LD A,0
        LD (MY_ADDRESS),A
        LD (MY_ADDRESS_INV),A

L_05cc:
        LD HL,INIT_DATA
        LD BC,10
        LD DE,FB_COLPTR
        LDIR
        LD HL,INIT_DATA+10               ; -> EFFECT_TMP
        LD DE,EFFECT_TMP
        LD BC,8
        LDIR
        LD HL,INIT_DATA+0x18             ; -> CLK_RUN..
        LD DE,CLK_RUN
        LD BC,0x5a
        LDIR
        LD HL,INIT_DATA+0x73             ; -> VAR_4336..
        LD DE,VAR_4336
        LD BC,0x24
        LDIR
        IM 1
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        RET

; ---- INIT_DATA: four RAM images that init_vars LDIRs into place, annotated
;      with the address each entry lands on. dw entries holding a ROM address
;      must stay symbolic - moving code before them would silently break the
;      serial engine. +12..+17 and +72 are copied nowhere: dead bytes.
INIT_DATA:
; -- +00 -> 4198 (FB_COLPTR), 10 bytes
        dw FRAMEBUF_ROW1      ; 4198 FB_COLPTR
        db 0x56               ; 419a 
        dw FRAMEBUF           ; 419b FB_COL
        db 0x95               ; 419d 
        db 0x40               ; 419e 
        db 0x01               ; 419f 
        db 0x01               ; 41a0 
        db 0x00               ; 41a1 FB_TMP
; -- +0a -> 41f8 (EFFECT_TMP), 8 bytes
        dw TXBUF              ; 41f8 EFFECT_TMP
        db 0x56               ; 41fa 
        dw 0x0000             ; 41fb EFFECT_TMP2
        db 0x00               ; 41fd FLASH_TIMER
        dw 0x0000             ; 41fe TICK_COUNTDOWN
        db 0x01,0x02,0x00,0x00,0x00,0x00   ; +12 dead
; -- +18 -> 4206 (CLK_RUN), 90 bytes
        db 0x01               ; 4206 CLK_RUN
        db 0x00               ; 4207 GLYPH_WIDTH
        dw 0x0000             ; 4208 GLYPH_PTR
        dw 0x0000             ; 420a MENU_MSG_PTR
        db 0x0f               ; 420c CUR_COLOUR
        db 0x00               ; 420d EFFECT_PHASE
        db 0x00               ; 420e CUR_CHAR
        db 0x00               ; 420f VAR_420F
        dw FRAMEBUF           ; 4210 SEQ_PTR_SAVE
        db 0x01               ; 4212 EFFECT_ACTIVE
        db 0x05               ; 4213 VAR_4213
        dw 0x0000             ; 4214 VAR_4214
        db 0x00               ; 4216 
        db 0x00               ; 4217 MENU_ACTIVE
        dw 0x0000             ; 4218 INS_PTR
        db 0x00               ; 421a RENDER_DONE
        db 0x00               ; 421b VAR_421B
        db 0x0f               ; 421c COL_COUNT
        db 0x00               ; 421d VAR_421D
        db 0x00               ; 421e VAR_421E
        db 0x0a               ; 421f VAR_421F
        db 0x00               ; 4220 VAR_4220
        db 0x00               ; 4221 VAR_4221
        db 0x00               ; 4222 ROW_DATA_LATCH
        db 0x0f               ; 4223 RX_MSGFLAG
        db 0x00               ; 4224 MENU_MSG_FLAG
        db 0x00               ; 4225 RX_LASTCMD
        db 0x00               ; 4226 VAR_4226
        db 0x00               ; 4227 VAR_4227
        db 0x00               ; 4228 RX_BYTE
        db 0x00               ; 4229 VAR_4229
        dw 0x0000             ; 422a BEEP_TIMER
        db 0x00               ; 422c 
        dw 0x0000             ; 422d CTRL_LATCH_SHADOW
        db 0x00               ; 422f 
        dw 0x5600             ; 4230 DISP_FLAGS
        dw 0x0000             ; 4232 FB_EXTRA_LEN
        dw 0xff00             ; 4234 STORE_END
        dw 0x005f             ; 4236 VAR_4236
        db 0x00               ; 4238 
        db 0x00               ; 4239 
        db 0x00               ; 423a PAUSE_FLAG
        dw 0x0000             ; 423b EFFECT_VECTOR
        dw 0x0000             ; 423d MENU_TEXT_PTR
        db 0x00               ; 423f 
        db 0x00               ; 4240 
        db 0x00               ; 4241 VAR_4241
        db 0x01               ; 4242 VAR_4242
        db 0x00               ; 4243 VAR_4243
        db 0x00               ; 4244 VAR_4244
        db 0x00               ; 4245 ROW_INDEX
        dw 0x0000             ; 4246 RX_BITMASK
        db 0x00               ; 4248 
        dw 0x0000             ; 4249 RX_SHIFT
        db 0x00               ; 424b RX_TICKS
        db 0x00               ; 424c VAR_424C
        dw 0x0000             ; 424d RX_FIFO
        db 0x00               ; 424f 
        db 0x00               ; 4250 
        db 0x00               ; 4251 
        db 0x00               ; 4252 
        db 0x00               ; 4253 
        db 0x00               ; 4254 
        db 0x00               ; 4255 RX_COUNT
        dw 0x4a00             ; 4256 RX_TIMING_PTR
        db 0x16               ; 4258 
        dw 0x164a             ; 4259 
        db 0x00               ; 425b 
        dw 0x2b00             ; 425c RX_STATE
        dw 0x2b16             ; 425e VAR_425E
        db 0x16   ; +72 dead
; -- +73 -> 4336 (VAR_4336), 36 bytes
        db 0x00               ; 4336 VAR_4336
        db 0x00               ; 4337 SHIFT_STATE
        db 0x00               ; 4338 VAR_4338
        db 0x00               ; 4339 FONT_MODE
        db 0x00               ; 433a TINY_MODE
        db 0x00               ; 433b VAR_433B
        dw 0x04b0             ; 433c NMI_COUNT
        dw 0x0000             ; 433e STORE_TMP
        dw 0x0000             ; 4340 MOVE_DST
        dw 0x0000             ; 4342 MOVE_SRC
        dw 0x0000             ; 4344 VAR_4344
        dw MSG_STORE          ; 4346 STORE_CURSOR
        db 0x00               ; 4348 TX_BITIDX
        db 0x01               ; 4349 TX_BITMASK
        db 0x00               ; 434a TX_PENDING
        db 0x00               ; 434b TX_TICKS
        db 0x00               ; 434c TX_SHIFT
        db 0x00               ; 434d TX_STATUS
        dw 0x1654             ; 434e TX_TIMING_PTR
        db 0x00               ; 4350 
        db 0x01               ; 4351 
        db 0x00               ; 4352 
        db 0x00               ; 4353 
        db 0x00               ; 4354 
        db 0x00               ; 4355 
        dw 0x1654             ; 4356 
        db 0xff               ; 4358 VAR_4358
        db 0xff               ; 4359 DISP_ENABLE

; ---- init_render: Reset render state for the current message
init_render:
        CALL clear_framebuf
        XOR A
        LD (VAR_439B),A
        LD (VAR_4360),A
        LD (TINY_RENDER),A
        LD (ROW_PHASE),A
        LD A,0xff
        LD (EFFECT_ACTIVE),A
        LD HL,FRAMEBUF
        LD (SEQ_PTR_SAVE),HL
        LD (FB_COL),HL
        LD HL,0
        LD (FB_EXTRA_LEN),HL
        LD HL,0x56
        LD (DISP_FLAGS),HL
        LD A,1
        LD (VAR_438C),A
        XOR A
        LD (RENDER_DONE),A
        LD (EFFECT_PHASE),A
        LD (VAR_4213),A
        LD (RENDER_DONE),A
        LD (VAR_421E),A
        LD (MENU_TMP),A
        LD (VAR_439A),A
        LD (MENU_TMP2),A
        LD (RND_VAL),A
        LD (PAUSE_FLAG),A
        LD (VAR_4244),A
        LD (VAR_43A2),A
        LD (VAR_43A3),A
        LD (VAR_43A4),A
        LD (VAR_43CD),A
        LD (VAR_433B),A
        LD (TINY_MODE),A
        LD (FONT_MODE),A
        LD (VAR_43D6),A
        LD A,0x8f
        LD (VAR_421B),A
        LD (ROW_DATA_LATCH),A
        LD (CUR_COLOUR),A
        LD HL,fx_none
        LD (EFFECT_VECTOR),HL
        LD HL,FRAMEBUF_ROW1
        LD (FB_COLPTR),HL
        LD HL,TXBUF
        LD (EFFECT_TMP),HL
        CALL clear_txbuf
        CALL clear_glyph_tmp
        LD HL,(STORE_LIMIT)
        LD (HL),0xda
        RET

sub_072a:
        LD A,(CUR_CHAR)
        CP 0x20
        JR z,L_0757
        XOR A
        LD (VAR_4338),A
        LD A,(CUR_CHAR)
        LD D,0
        LD E,A
        LD HL,CHAR_FLAGS
        ADD HL,DE
        BIT 1,(HL)
        JR nz,L_0776
        LD A,0xff
        LD (VAR_43A3),A
        LD A,(VAR_43A2)
        AND A
        JR z,L_0776
        LD (VAR_421E),A
        XOR A
        LD (VAR_43A2),A
        JR L_0776

L_0757:
        XOR A
        LD (VAR_421E),A
        LD A,(VAR_4338)
        AND A
        JR nz,L_0768
        LD A,1
        LD (VAR_4338),A
        JR L_0776

L_0768:
        LD A,(VAR_420F)
        INC A
        JR z,L_0776
        LD A,(CUR_COLOUR)
        AND 15
        LD (CUR_COLOUR),A

L_0776:
        RET

; ---- render_next_char: Fetch next byte from the message store at STORE_CURSOR and act on it: attribute bytes are dispatched, printable bytes are drawn via glyph_lookup
render_next_char:
        CALL sub_0968

sub_077a:
        CALL sub_072a
        CALL sub_0b14
        CALL sub_0996
        CALL sub_0a60
        CALL sub_0a53
        CALL sub_0a17
        CALL sub_09fe
        CALL sub_098c
        CP 0xbe
        JP z,attr_tiny
        AND 0xf0
        CP 0xa0
        JR nz,L_07a7
        LD A,(CUR_CHAR)
        AND 15
        LD (CUR_CHAR),A
        JR glyph_lookup

L_07a7:
        LD A,(CUR_CHAR)
        CP 0x17
        JR z,glyph_lookup
        BIT 7,A
        JP nz,L_07c5
        AND 0x60
        JP z,L_0ea8
        LD A,(CUR_CHAR)
        CP 0x5f
        JP z,L_1d90
        BIT 7,A
        JP z,glyph_lookup

L_07c5:
        CP 0x94
        JP c,attr_colour_speed
        CP 0xa0
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
        LD (GLYPH_PTR2),HL
        LD DE,7
        ADD HL,DE
        LD A,(HL)
        LD (GLYPH_WIDTH),A
        CALL clear_glyph_tmp
        LD A,(TINY_MODE)
        AND A
        JR nz,L_085c
        CALL draw_glyph
        CALL sub_0de3
        CALL sub_0d97
        LD A,(VAR_4213)
        CP 0xff
        JR nz,L_0826
        XOR A
        LD (VAR_4213),A
        LD A,0xff
        LD (VAR_4361),A

L_0826:
        LD A,(CUR_CHAR)
        AND 0xf0
        JR nz,L_085c
        LD HL,(GLYPH_PTR)
        LD DE,(GLYPH_PTR2)
        OR A
        SBC HL,DE
        JR nz,L_084d
        LD HL,(GLYPH_PTR)
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD B,0
        LD DE,VAR_42D6
        LDIR
        LD HL,VAR_42D6
        LD (GLYPH_PTR),HL

L_084d:
        LD A,(GLYPH_WIDTH)
        SLA A
        CP 0x20
        JP c,L_0859
        LD A,0x1f

L_0859:
        LD (GLYPH_WIDTH),A

L_085c:
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,L_0869
        LD A,(PAUSE_FLAG)
        AND A
        JP nz,L_08fc

L_0869:
        LD A,0
        LD (VAR_438C),A

sub_086e:
        LD A,(RENDER_DONE)
        AND A
        JR z,L_0887
        LD A,(CUR_CHAR)
        CP 0x20
        JR nz,L_0887
        LD DE,TBL_08F0
        LD (GLYPH_PTR),DE
        LD A,9
        LD (GLYPH_WIDTH),A

L_0887:
        LD DE,(GLYPH_PTR)
        LD HL,(FB_COLPTR)
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD A,(MENU_ACTIVE)
        AND A
        JR z,L_08a5
        LD A,15
        LD (CUR_COLOUR),A
        LD A,(TINY_MODE)
        AND A
        LD C,0
        JR nz,L_08b7

L_08a5:
        LD A,(VAR_4391)
        AND A
        JR z,L_08b3
        XOR A
        LD (VAR_4391),A
        LD A,0x10
        JR L_08b6

L_08b3:
        LD A,(VAR_421E)

L_08b6:
        LD C,A

L_08b7:
        PUSH BC
        LD A,(CUR_CHAR)
        CP 0x20
        LD C,0xf0
        JR z,L_08c3
        LD C,0xff

L_08c3:
        LD A,(CUR_COLOUR)
        AND C
        POP BC
        OR C
        SET 7,A
        LD (HL),A
        LD A,(VAR_439B)
        AND A
        CALL z,sub_0e16
        XOR A
        LD (VAR_439B),A

L_08d7:
        LD A,(DE)
        LD (HL),A
        INC DE
        CALL sub_0e16
        DJNZ L_08d7
        LD (FB_COLPTR),HL
        LD A,(MENU_ACTIVE)
        AND A
        LD A,0
        JR nz,L_08ec
        LD A,0xff

L_08ec:
        LD (EFFECT_PHASE),A
        RET

; ---- data 08f0-08fb:
TBL_08F0:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

L_08fc:
        LD HL,(EFFECT_TMP)
        LD A,(GLYPH_WIDTH)
        LD D,0
        LD E,A
        ADD HL,DE
        LD DE,EFFECT_TMP
        XOR A
        SBC HL,DE
        JP nc,L_0efc
        LD DE,(EFFECT_TMP)
        LD A,(VAR_421E)
        OR 0x8f
        LD (DE),A
        LD A,(VAR_439B)
        AND A
        LD A,0
        LD (VAR_439B),A
        JR nz,L_0925
        INC DE

L_0925:
        LD HL,(GLYPH_PTR)
        LD A,(GLYPH_WIDTH)
        LD B,0
        LD C,A
        LDIR
        LD (EFFECT_TMP),DE
        JP render_next_char

L_0937:
        SRL H
        RR L
        LD (EFFECT_TMP2),HL
        CALL sub_0cea
        RET

; ---- char_to_glyph: Map a character code to a font glyph index
;      (CHARSET_LOWER..CHARSET_GRAPHICS select upper/lower/tiny fonts)
char_to_glyph:
        PUSH AF
        AND 0xf0
        CP 0xc0
        LD DE,FONT+8*128
        JR z,L_0963
        CP 0xd0
        LD DE,FONT+8*175
        JR z,L_0963
        CP 0xe0
        LD DE,FONT+8*144
        JR z,L_0963
        CP 0x90
        LD DE,FONT+8*160
        JR z,L_0963
        POP AF
        RET

L_0963:
        POP AF
        AND 15
        EX DE,HL
        RET

sub_0968:
        PUSH HL
        PUSH AF
        LD HL,(STORE_CURSOR)
        LD A,(PAUSE_FLAG)
        AND A
        JR z,L_097d
        LD A,(VAR_4361)
        AND A
        JR z,L_097d
        LD A,0x18
        JR L_097e

L_097d:
        LD A,(HL)

L_097e:
        INC HL
        LD (STORE_CURSOR),HL
        LD (CUR_CHAR),A
        XOR A
        LD (VAR_4361),A
        POP AF
        POP HL
        RET

sub_098c:
        LD A,(CUR_CHAR)
        CP 0xbb
        RET nz
        POP HL
        JP L_0ef1

sub_0996:
        LD A,(CUR_CHAR)
        CP 0xbc
        JR nz,L_09b5
        LD A,(RENDER_DONE)
        AND A
        JR z,L_09a9
        LD A,(TBL_09F6+1)
        LD (CUR_COLOUR),A

L_09a9:
        LD A,1
        LD (VAR_43A4),A
        LD (MENU_TMP),A
        POP HL
        JP render_next_char

L_09b5:
        LD A,(VAR_43A4)
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
        LD A,(VAR_43A4)
        INC A
        AND 7
        JR nz,L_09d8
        LD A,1

L_09d8:
        LD E,A
        LD D,0
        LD HL,TBL_09F6
        ADD HL,DE
        LD A,(HL)
        CP 0xff
        JR nz,L_09e9
        LD E,1
        LD A,(TBL_09F6+1)

L_09e9:
        AND 15
        LD (CUR_COLOUR),A
        LD A,E
        LD (VAR_43A4),A
        LD A,(CUR_CHAR)
        RET

; ---- data 09f6-09fd:
TBL_09F6:
        db 0x00,0x8c,0x8d,0x8f,0x87,0x83,0xff,0xff

sub_09fe:
        LD A,(CUR_CHAR)
        CP 0xb0
        RET nz

L_0a04:
        CALL sub_0968
        LD A,(CUR_CHAR)

; ---- attr_remark: 0xB0: skip text until the next 0xB0 (hidden remark)
attr_remark:
        CP 0xb0
        JR z,L_0a13
        CP 3
        RET z
        JR L_0a04

L_0a13:
        POP HL
        JP render_next_char

sub_0a17:
        LD A,(CUR_CHAR)
        CP 0xba
        RET nz
        LD A,(COL_COUNT)
        AND A
        JR z,L_0a34
        LD HL,(EFFECT_TMP)
        LD DE,TXBUF
        XOR A
        SBC HL,DE
        JR z,L_0a34
        LD A,0x18
        LD (CUR_CHAR),A
        RET

L_0a34:
        CALL sub_1062
        XOR A
        LD (RX_BYTE),A
        LD (IR_CODE),A

L_0a3e:
        LD A,(RX_BYTE)
        CP 0x20
        JR nz,L_0a49
        POP HL
        JP render_next_char

L_0a49:
        LD A,(PKT_READY)
        AND A
        JP nz,pkt_process
        JP L_0a3e

sub_0a53:
        LD A,(CUR_CHAR)
        CP 0xb9
        RET nz
        LD (VAR_43D6),A
        POP HL
        JP render_next_char

sub_0a60:
        LD A,(CUR_CHAR)

; ---- attr_graphic: 0xB8: user-drawn graphic follows
attr_graphic:
        CP 0xb8
        JR z,L_0a70
        LD A,0
        LD (VAR_4360),A
        LD A,(CUR_CHAR)
        RET

L_0a70:
        LD A,(VAR_4360)
        LD (VAR_439B),A
        LD A,0xff
        LD (VAR_4360),A
        LD HL,VAR_4365
        PUSH HL
        PUSH HL
        LD B,0x10

L_0a82:
        LD (HL),0
        INC HL
        DJNZ L_0a82
        CALL clear_glyph_tmp
        POP HL
        LD C,0
        LD B,0x10

L_0a8f:
        CALL sub_0968
        LD A,(CUR_CHAR)
        CALL sub_0af4
        CP 0xff
        JR z,L_0ae2
        PUSH AF
        CALL sub_0968
        LD A,(CUR_CHAR)
        CALL sub_0af4
        CP 0xff
        JR z,L_0ae1
        RRD
        POP AF
        RRD
        INC HL
        INC C
        DJNZ L_0a8f

L_0ab3:
        POP HL
        LD (GLYPH_PTR),HL
        LD (GLYPH_PTR2),HL
        LD A,C
        AND A
        JP nz,L_0ac9
        XOR A
        LD (VAR_439B),A
        LD A,0x20
        LD (CUR_CHAR),A
        RET

L_0ac9:
        LD (GLYPH_WIDTH),A
        POP HL
        LD A,(PAUSE_FLAG)
        AND A
        JP z,L_085c
        CALL draw_glyph
        LD A,(GLYPH_WIDTH)
        DEC A
        LD (GLYPH_WIDTH),A
        JP L_085c

L_0ae1:
        POP AF

L_0ae2:
        LD A,(CUR_CHAR)
        CP 3
        JR nz,L_0aec
        CALL sub_0cea

L_0aec:
        LD A,0x2a
        LD (CUR_CHAR),A
        JP L_0ab3

sub_0af4:
        CP 0x30
        JP c,L_0b11
        CP 0x3a
        JP c,L_0b0e
        AND 0xdf
        CP 0x41
        JP c,L_0b11
        CP 0x47
        JP nc,L_0b11
        AND 15
        ADD A,9

L_0b0e:
        AND 15
        RET

L_0b11:
        LD A,0xff
        RET

sub_0b14:
        LD A,(MENU_ACTIVE)
        AND A
        RET nz
        LD A,(RENDER_DONE)
        AND A
        RET z
        LD A,(PAUSE_FLAG)
        AND A
        JR z,L_0b2e
        LD A,(CUR_CHAR)
        CP 0x20
        RET nz
        POP HL
        JP L_0efc

L_0b2e:
        LD A,(CUR_CHAR)
        CP 0x20
        JR nz,L_0b62
        LD HL,VAR_4395
        INC (HL)
        LD A,2
        LD (FONT_MODE),A
        LD A,(MENU_CHAR)
        CP 0x2e
        JP z,L_0c68
        CP 0x21
        JP z,L_0c68
        CP 0x3f
        JP z,L_0c68
        CP 0x3a
        JP z,L_0c68
        CP 0x2c
        JP z,L_0c68
        LD A,0x20
        LD (MENU_CHAR),A
        JP L_0cd3

L_0b62:
        CP 0xbb
        JR z,L_0b72
        CP 15
        JR z,L_0b72
        CP 0x19
        JR c,L_0bb7
        CP 0x1c
        JR nc,L_0bb7

L_0b72:
        XOR A
        LD (MENU_TMP2),A
        LD (MENU_TMP),A
        LD A,(VAR_4390)
        AND A
        RET nz
        LD A,0xff
        LD (VAR_4390),A
        LD A,(VAR_43A3)
        AND A
        RET z
        LD A,(CUR_CHAR)
        PUSH AF
        LD B,14

L_0b8e:
        PUSH BC
        LD A,0x20
        LD (CUR_CHAR),A
        XOR A
        LD (PAUSE_FLAG),A
        LD HL,fx_none
        LD (EFFECT_VECTOR),HL
        LD A,6
        LD (GLYPH_WIDTH),A
        LD HL,FONT+8*32
        LD (GLYPH_PTR),HL
        CALL sub_086e
        CALL effect_step
        POP BC
        DJNZ L_0b8e
        POP AF
        LD (CUR_CHAR),A
        RET

L_0bb7:
        XOR A
        LD (VAR_4390),A
        LD A,(CUR_CHAR)
        CP 0xb8
        JP z,L_0bd4
        AND 0xf0
        CP 0xa0
        JP z,L_0bd4
        CP 0x20
        JP c,L_0cd3
        CP 0x80
        JP nc,L_0cd3

L_0bd4:
        LD A,(MENU_CHAR)
        CP 0x20
        JR z,L_0be4
        LD A,(CUR_CHAR)
        LD (MENU_CHAR),A
        JP L_0cd3

L_0be4:
        LD A,(CUR_CHAR)
        LD (MENU_CHAR),A
        CP 0x24
        JR nz,L_0bf1
        LD (VAR_4391),A

L_0bf1:
        AND 0xf0
        CP 0xa0
        JP z,L_0c73
        LD A,(MENU_TMP2)
        AND A
        LD A,0
        LD (MENU_TMP2),A
        JR nz,L_0c42
        LD B,8
        LD HL,(STORE_CURSOR)

L_0c08:
        LD A,(HL)
        AND 0x5f
        CP 0x41
        JP c,L_0c1b
        CP 0x5b
        JP nc,L_0c1b
        INC HL
        DJNZ L_0c08
        JP L_0c3e

L_0c1b:
        LD A,B
        CP 6
        JP nc,L_0c3e
        LD A,(RND_SEED)
        ADD A,(HL)
        LD HL,(NMI_COUNT)
        ADD A,(HL)
        LD (RND_SEED),A
        AND 3
        JR z,L_0c37
        LD HL,FONT_MODE
        LD (HL),2
        JR L_0c42

L_0c37:
        LD HL,FONT_MODE
        LD (HL),6
        JR L_0c42

L_0c3e:
        XOR A
        LD (FONT_MODE),A

L_0c42:
        LD A,(VAR_4395)
        CP 3
        JP nc,L_0c73
        LD A,(RND_VAL)
        AND A
        JP z,L_0c68
        DEC A
        JP z,L_0c68
        LD (RND_VAL),A
        LD A,(MENU_TMP)
        AND A
        JR z,L_0ccf
        XOR A
        LD (MENU_TMP),A
        LD (RND_VAL),A
        JP L_0ccf

L_0c68:
        LD A,(NMI_COUNT)
        LD E,A
        AND 3
        ADD A,2
        LD (RND_VAL),A

L_0c73:
        LD A,(MENU_TMP)
        AND A
        JR z,L_0c83
        XOR A
        LD (MENU_TMP),A
        LD (RND_VAL),A
        JP L_0ccf

L_0c83:
        XOR A
        LD (VAR_43A4),A
        LD A,(VAR_4362)
        INC A
        LD E,A
        LD A,(NMI_COUNT)
        ADD A,E

L_0c90:
        AND 15
        LD (VAR_4362),A
        LD E,A
        LD D,0
        LD HL,TBL_0CD4+6
        ADD HL,DE
        LD A,(CUR_COLOUR)
        AND 15
        CP (HL)
        JR z,L_0cc0
        LD A,(CUR_COLOUR)
        LD E,A
        LD D,(HL)
        LD A,D
        LD HL,CUR_COLOUR
        RLD
        LD A,(HL)
        LD HL,TBL_0CD4
        LD BC,6
        OR A
        CPIR
        JP nz,L_0cc6
        LD A,E
        LD (CUR_COLOUR),A

L_0cc0:
        LD A,(VAR_4362)
        INC A
        JR L_0c90

L_0cc6:
        LD A,E
        AND 0x10
        OR D
        AND 0x1f
        LD (CUR_COLOUR),A

L_0ccf:
        XOR A
        LD (VAR_4395),A

L_0cd3:
        RET

; ---- data 0cd4-0ce9:
TBL_0CD4:
        db 0xf7,0x7f,0xfd,0xdf,0xcd,0xdc,0x07,0x0c,0x0f,0x03,0x0c,0x03,0x0d,0x03,0x0f,0x03
        db 0x0c,0x03,0x03,0x0c,0x0f,0x0c

sub_0cea:
        LD HL,(STORE_CURSOR)
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        JR z,L_0cfc
        LD HL,(STORE_CURSOR)
        DEC HL
        LD (STORE_CURSOR),HL

L_0cfc:
        RET

; ---- draw_glyph: Copy the glyph columns into FRAMEBUF at the current column
draw_glyph:
        LD A,(VAR_433B)
        AND A
        JR nz,L_0d36
        LD A,(PAUSE_FLAG)
        AND A
        JR z,L_0d2f
        LD A,(VAR_43D6)
        AND A
        JR z,L_0d36
        LD A,(FONT_MODE)
        AND 10
        JR nz,L_0d2f
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD B,0
        INC A
        LD (GLYPH_WIDTH),A
        LD HL,(GLYPH_PTR)
        LD DE,VAR_42D6
        LDIR
        LD HL,VAR_42D6
        LD (GLYPH_PTR),HL
        RET

L_0d2f:
        LD A,(FONT_MODE)
        BIT 1,A
        JR z,L_0d96

L_0d36:
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD HL,(GLYPH_PTR)
        LD DE,VAR_42D6
        LD C,0

L_0d42:
        LD A,(HL)
        LD (DE),A
        INC HL
        AND A
        JR z,L_0d4c
        OR (HL)
        INC DE
        INC C
        LD (DE),A

L_0d4c:
        INC DE
        INC C
        DJNZ L_0d42
        XOR A
        LD (DE),A
        LD A,C
        CP 2
        JR z,L_0d5b
        XOR A
        DEC DE
        LD (DE),A
        LD A,C

L_0d5b:
        LD (GLYPH_WIDTH),A
        LD HL,VAR_42D6
        LD (GLYPH_PTR),HL
        LD IX,VAR_42D6
        LD B,4

L_0d6a:
        LD A,(IX+0)
        CP 0x7f
        JR nz,L_0d7f
        LD A,(IX+1)
        CP 0x7f
        JR nz,L_0d7f
        LD A,(IX+2)
        CP 0x7f
        JR z,L_0d84

L_0d7f:
        INC IX
        DJNZ L_0d6a
        RET

L_0d84:
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

L_0d96:
        RET

sub_0d97:
        LD A,(FONT_MODE)
        BIT 2,A
        JR z,L_0de2
        LD HL,(GLYPH_PTR)
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD DE,VAR_42F6
        LD B,0
        LDIR
        LD B,A
        LD E,B
        LD D,0
        LD HL,VAR_42F6
        ADD HL,DE
        PUSH HL
        POP IX

L_0db7:
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
        JP p,L_0db7
        LD A,(GLYPH_WIDTH)
        INC A
        INC A
        LD (GLYPH_WIDTH),A
        LD HL,VAR_42F6
        LD (GLYPH_PTR),HL

L_0de2:
        RET

sub_0de3:
        LD A,(FONT_MODE)
        BIT 3,A
        JR z,L_0e15
        LD A,(GLYPH_WIDTH)
        LD B,A
        LD HL,(GLYPH_PTR)
        LD DE,VAR_4316
        LD C,0

L_0df6:
        LD A,(HL)
        LD (DE),A
        INC HL
        AND A
        JR z,L_0e00
        OR (HL)
        INC DE
        INC C
        LD (DE),A

L_0e00:
        INC DE
        INC C
        DJNZ L_0df6
        XOR A
        LD (DE),A
        DEC DE
        LD (DE),A
        DEC DE
        LD (DE),A
        LD A,C
        DEC A
        LD (GLYPH_WIDTH),A
        LD HL,VAR_4316
        LD (GLYPH_PTR),HL

L_0e15:
        RET

sub_0e16:
        INC HL
        PUSH AF
        PUSH DE
        PUSH HL
        LD DE,FB_COLPTR
        XOR A
        SBC HL,DE
        JP c,L_0e29
        LD HL,FRAMEBUF
        POP DE
        JR L_0e2a

L_0e29:
        POP HL

L_0e2a:
        POP DE
        POP AF
        RET

sub_0e2d:
        PUSH AF
        PUSH DE
        ADD HL,DE
        PUSH HL
        LD DE,FB_COLPTR
        XOR A
        SBC HL,DE
        JR c,L_0e40
        POP DE
        LD DE,FRAMEBUF
        ADD HL,DE
        JR L_0e41

L_0e40:
        POP HL

L_0e41:
        POP DE
        POP AF
        RET

; ---- effect_step: Called from main loop: jump to EFFECT_VECTOR (current movement effect handler)
effect_step:
        LD A,(VAR_4244)
        AND A
        JR nz,effect_step

L_0e4a:
        LD A,(EFFECT_PHASE)
        AND A
        JR nz,L_0e4a
        LD A,(PAUSE_FLAG)
        AND A
        RET z

L_0e55:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,L_0e55
        LD HL,(EFFECT_TMP2)
        LD A,L
        CP 0x2b
        JR z,L_0e68
        LD HL,(EFFECT_VECTOR)
        JP (HL)

L_0e68:
        LD HL,0
        LD (EFFECT_TMP2),HL

L_0e6e:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xba
        JR nz,L_0e7a
        XOR A
        LD (VAR_4244),A

L_0e7a:
        LD A,(PAUSE_FLAG)
        AND A
        JR z,L_0e9b
        LD A,(RENDER_DONE)
        AND A
        JR z,L_0e8b
        LD A,15
        LD (CUR_COLOUR),A

L_0e8b:
        LD A,(VAR_4242)
        CPL
        AND A
        LD (VAR_4242),A
        JR z,L_0e9b
        XOR A
        LD (VAR_4242),A
        LD A,0x56

L_0e9b:
        LD (COL_COUNT),A
        CALL clear_txbuf
        LD HL,TXBUF
        LD (EFFECT_TMP),HL
        RET

L_0ea8:
        LD A,(CUR_CHAR)

; ---- attr_dispatch: Attribute byte dispatcher: 11 normal,12 bold,13 italic,14 flash,10 large,1F magic,06 pause,07 beep,03 end,18 crawl,19 jump,1A wipe up,1B wipe down,0F wipe back,BB (extra effect)
attr_dispatch:
        CP 0x11
        JP nz,L_0eba
        XOR A
        LD (VAR_421E),A
        LD (FONT_MODE),A
        JP L_0ee1

L_0eba:
        CP 0x12
        JP nz,L_0ec4
        LD A,2
        JP L_0ee1

L_0ec4:
        CP 0x13
        JP nz,L_0ece
        LD A,6
        JP L_0ee1

L_0ece:
        CP 0x14
        JP nz,L_0edb
        LD A,0x10
        LD (VAR_43A2),A
        JP render_next_char

L_0edb:
        CP 0x10
        JR nz,L_0eec
        LD A,10

L_0ee1:
        LD (FONT_MODE),A
        LD A,0xff
        LD (MENU_TMP2),A
        JP render_next_char

L_0eec:
        CP 0x1f
        JP z,fx_magic

L_0ef1:
        LD A,(COL_COUNT)
        AND A
        JR z,L_0f0f
        LD A,0xff
        LD (VAR_4242),A

L_0efc:
        LD HL,(EFFECT_TMP)
        LD DE,EFFECT_TMP
        XOR A
        EX DE,HL
        SBC HL,DE
        LD A,0x56
        SUB L
        LD (COL_COUNT),A
        JP L_0937

L_0f0f:
        LD A,(CUR_CHAR)
        CP 6
        JP z,fx_pause
        CP 7
        JP z,fx_beep
        CP 3
        JP z,fx_end_of_channel
        CP 0x18
        JP z,fx_crawl
        CP 0x19
        JP z,fx_jump
        CP 0x1a
        JP z,fx_wipe_up
        CP 0x1b
        JP z,fx_wipe_down
        CP 15
        JP z,fx_wipe_back
        CP 0xbb
        JP z,fx_BB
        JP render_next_char

; ---- fx_beep
fx_beep:
        CALL sub_0f48
        JP render_next_char

sub_0f48:
        PUSH HL
        LD HL,0x96
        LD (TICK_COUNTDOWN),HL
        POP HL
        RET

; ---- fx_end_of_channel
fx_end_of_channel:
        LD HL,fx_none
        LD (EFFECT_VECTOR),HL
        XOR A
        LD (PAUSE_FLAG),A
        CALL demo_scroll
        LD SP,0x403f
        JP main_loop

; ---- fx_wipe_back
fx_wipe_back:
        XOR A
        LD (EFFECT_PHASE),A
        LD A,0x56
        LD (COL_COUNT),A
        LD A,4
        LD HL,fx_scroll_in
        JP set_effect_vector

; ---- fx_crawl
fx_crawl:
        XOR A
        LD (COL_COUNT),A
        LD HL,fx_none
        JP set_effect_vector

; ---- fx_BB
fx_BB:
        XOR A
        LD A,0x56
        LD (COL_COUNT),A
        LD A,5
        LD HL,fx_fill_frame
        JP set_effect_vector

; ---- fx_jump
fx_jump:
        XOR A
        LD (EFFECT_PHASE),A
        LD A,0x56
        LD (COL_COUNT),A
        LD A,1
        LD HL,fx_scroll_copy
        JP set_effect_vector

; ---- fx_wipe_up
fx_wipe_up:
        XOR A
        LD (EFFECT_PHASE),A
        LD A,0x56
        LD (COL_COUNT),A
        LD A,2
        LD HL,fx_138b
        JP set_effect_vector

; ---- fx_wipe_down
fx_wipe_down:
        XOR A
        LD (EFFECT_PHASE),A
        LD A,0x56
        LD (COL_COUNT),A
        LD A,3
        LD HL,fx_138b
        JP set_effect_vector

; ---- set_effect_vector: HL -> EFFECT_VECTOR, A -> effect id
set_effect_vector:
        LD (PAUSE_FLAG),A
        LD (VAR_438C),A
        LD (EFFECT_VECTOR),HL
        JP render_next_char

; ---- fx_magic
fx_magic:
        XOR A
        LD (VAR_43A2),A
        LD (MENU_TMP),A
        LD (MENU_TMP2),A
        LD (VAR_43A4),A
        LD (VAR_4390),A
        LD A,0xff
        LD (RENDER_DONE),A
        LD A,0x20
        LD (MENU_CHAR),A
        LD A,1
        LD (VAR_4395),A
        LD A,(NMI_COUNT)
        LD E,A
        AND 3
        ADD A,2
        LD (RND_VAL),A
        CALL sub_0ffc
        JP render_next_char

sub_0ffc:
        LD A,(MENU_ACTIVE)
        AND A
        RET nz
        LD A,(PAUSE_FLAG)
        AND A
        RET nz
        LD A,(VAR_4362)
        INC A
        AND 15
        LD (VAR_4362),A
        LD E,A
        LD D,0
        LD HL,TBL_0CD4+6
        ADD HL,DE
        LD A,(HL)
        AND 15
        LD (CUR_COLOUR),A
        RET

; ---- attr_restart: 0xBD
attr_restart:
        XOR A
        LD (RENDER_DONE),A
        LD (MENU_TMP2),A
        LD (MENU_TMP),A
        LD (FONT_MODE),A
        LD A,0x8f
        LD (CUR_COLOUR),A
        JP render_next_char

; ---- fx_pause
fx_pause:
        XOR A
        LD (EFFECT_PHASE),A
        LD A,(PAUSE_FLAG)
        AND A
        JR nz,L_1042

L_103c:
        LD A,(VAR_4244)
        AND A
        JR nz,L_103c

L_1042:
        LD A,0x50
        LD (VAR_4244),A
        CALL sub_1062
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0x18
        JP z,fx_crawl
        LD A,(PAUSE_FLAG)
        AND A
        JP z,fx_crawl
        LD A,0x56
        LD (COL_COUNT),A
        JP render_next_char

sub_1062:
        LD HL,FRAMEBUF
        LD BC,0x0158

L_1068:
        BIT 7,(HL)
        JR z,L_1072
        LD A,(HL)
        AND 0x10
        OR 0x8f
        LD (HL),A

L_1072:
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,L_1068
        LD A,(VAR_421B)
        AND 0x10
        OR 0x8f
        LD (VAR_421B),A
        LD (ROW_DATA_LATCH),A
        LD E,A
        LD A,(RENDER_DONE)
        AND A
        RET z
        LD A,15
        LD (CUR_COLOUR),A
        RET

; ---- attr_colour_speed: 0x8x foreground colour, 0x9x background, 0xFx speed, 0xBD restart
attr_colour_speed:
        LD A,(CUR_CHAR)
        AND 0xf0
        CP 0x80
        JP z,attr_fore_colour
        CP 0x90
        JP z,attr_back_colour
        CP 0xf0
        JP z,attr_speed
        LD A,(CUR_CHAR)
        CP 0xbd
        JP z,attr_restart
        JP render_next_char

; ---- attr_fore_colour
attr_fore_colour:
        XOR A
        LD (VAR_43A4),A
        LD A,(RENDER_DONE)
        AND A
        JR z,L_10c2
        LD A,(CUR_COLOUR)
        AND 0xcf
        LD (CUR_COLOUR),A

L_10c2:
        LD A,(CUR_CHAR)
        AND 15
        LD E,A
        LD A,(CUR_COLOUR)
        AND 0x60
        OR E
        LD (CUR_COLOUR),A
        LD A,0xff
        LD (MENU_TMP),A
        JP render_next_char

; ---- attr_back_colour
attr_back_colour:
        LD A,(RENDER_DONE)
        AND A
        JR z,L_10e7
        LD A,(CUR_COLOUR)
        OR 15
        LD (CUR_COLOUR),A

L_10e7:
        XOR A
        LD (VAR_43A4),A
        LD HL,0
        LD DE,0x20
        LD A,(CUR_CHAR)
        AND 3
        JR z,L_10fc

L_10f8:
        ADD HL,DE
        DEC A
        JR nz,L_10f8

L_10fc:
        LD A,(CUR_COLOUR)
        AND 15
        OR L
        AND 0x6f
        LD (CUR_COLOUR),A
        LD A,0xff
        LD (MENU_TMP),A
        JP render_next_char

; ---- attr_speed
attr_speed:
        LD A,(CUR_CHAR)
        AND 7
        LD (VAR_43CD),A
        JP render_next_char

; ---- attr_tiny: 0xBE: switch to tiny (28-char) font mode and render
attr_tiny:
        CALL sub_114c
        CALL clear_framebuf
        LD A,0xff
        LD (TINY_RENDER),A
        LD A,0x8f
        LD (FRAMEBUF_TINY),A

L_112a:
        CALL sub_1187
        AND A
        JR nz,L_113c
        CALL sub_11fe
        LD HL,(STORE_CURSOR)
        INC HL
        LD (STORE_CURSOR),HL
        JR L_112a

L_113c:
        CALL sub_1231
        CALL clear_framebuf
        XOR A
        LD (TINY_RENDER),A
        CALL init_render
        JP L_00a7

sub_114c:
        LD E,0
        LD HL,FB_COL
        LD B,0x56

L_1153:
        BIT 7,(HL)
        JR z,L_115a
        LD A,(HL)
        OR E
        LD E,A

L_115a:
        INC HL
        DJNZ L_1153
        LD A,E
        AND A
        RET z
        LD B,14

L_1162:
        PUSH BC
        LD A,0x20
        LD (CUR_CHAR),A
        XOR A
        LD (PAUSE_FLAG),A
        LD HL,fx_none
        LD (EFFECT_VECTOR),HL
        LD A,6
        LD (GLYPH_WIDTH),A
        LD HL,FONT+8*32
        LD (GLYPH_PTR),HL
        CALL sub_086e
        CALL effect_step
        POP BC
        DJNZ L_1162
        RET

sub_1187:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        LD (CUR_CHAR),A
        AND 0xf0
        CP 0xa0
        JR nz,L_119e
        LD A,(CUR_CHAR)
        AND 15
        LD (CUR_CHAR),A
        JR L_11c7

L_119e:
        LD A,(CUR_CHAR)
        AND 0x60
        JP z,L_11fb
        LD A,(CUR_CHAR)
        CP 0x5f
        JP z,L_11fb
        BIT 7,A
        JP z,L_11c7
        CP 0x94
        JP c,L_11fb
        CP 0x9e
        JR c,L_11c7
        AND 0xf0
        CP 0xc0
        JR z,L_11c7
        CP 0xe0
        JP nz,L_11fb

L_11c7:
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

sub_11ea:
        LD DE,FRAMEBUF_TINY+1
        LD B,0
        LD A,(GLYPH_WIDTH)
        LD C,A
        LD A,0x8f
        LD (DE),A
        INC DE
        LDIR
        XOR A
        RET

L_11fb:
        LD A,0xff
        RET

sub_11fe:
        LD A,(GLYPH_WIDTH)
        INC A

L_1202:
        LD HL,FRAMEBUF+1
        LD DE,FRAMEBUF
        LD BC,0xbc
        LDIR
        PUSH AF
        CALL sub_1216
        POP AF
        DEC A
        JR nz,L_1202
        RET

sub_1216:
        LD HL,FRAMEBUF
        LD DE,FRAMEBUF_TINY+31
        LD BC,0x56
        LD A,(ROW_PHASE)
        AND A
        JR nz,sub_1216

L_1225:
        LDI
        INC HL
        JP pe,L_1225
        LD A,0xff
        LD (ROW_PHASE),A
        RET

sub_1231:
        LD B,0x1c

L_1233:
        PUSH BC
        LD A,0x20
        LD (CUR_CHAR),A
        LD A,5
        LD (GLYPH_WIDTH),A
        LD HL,FONT+8*32
        CALL sub_11ea
        CALL sub_11fe
        POP BC
        DJNZ L_1233
        RET

L_124b:
        LD A,(ROW_PHASE)
        AND A
        JR nz,L_125f
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        JP rx_consume

L_125f:
        LD A,(DISP_ENABLE)
        AND A
        JP z,disp_next_row
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A

; ---- disp_blank_row: Send 0x8F (all off) to the current row
disp_blank_row:
        LD HL,FRAMEBUF_TINY+31
        LD B,0x56
        LD C,0x48
        LD A,(ROW_INDEX)
        CPL
        AND 7
        DEC A
        OR C
        LD C,A
        RES 5,C
        LD A,0x8f
        OUT (C),A
        OTIR
        OUT (PORT_STROBE),A
        LD A,(ROW_INDEX)
        CPL
        AND 7
        DEC A
        JR nz,L_1296
        LD A,7

L_1296:
        LD C,A
        LD A,(VAR_421F)
        OR C
        AND 0x8f
        LD C,A
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x70
        OR C
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        XOR A
        LD (DISP_ENABLE),A
        JP L_030d

; ---- disp_next_row: ROW_INDEX = (ROW_INDEX+1) mod 7
disp_next_row:
        LD A,(ROW_INDEX)
        LD C,A
        INC A
        LD (ROW_INDEX),A
        CP 7
        JP c,L_0303
        LD A,0
        LD (ROW_INDEX),A
        LD (ROW_PHASE),A
        JP rx_consume

; ---- fx_setup_scroll
fx_setup_scroll:
        CALL clear_framebuf

sub_12cc:
        LD HL,FRAMEBUF_ROW1
        LD (FB_COLPTR),HL
        LD HL,0x56
        LD (DISP_FLAGS),HL
        LD HL,0
        LD (FB_EXTRA_LEN),HL
        LD DE,FRAMEBUF
        LD (FB_COL),DE
        LD (SEQ_PTR_SAVE),DE
        LD HL,(EFFECT_TMP2)
        ADD HL,DE
        LD DE,TXBUF
        EX DE,HL
        RET

; ---- fx_scroll_in
fx_scroll_in:
        LD A,0xff
        LD (EFFECT_ACTIVE),A
        CALL fx_setup_scroll
        LD A,(COL_COUNT)
        LD B,A

L_12fe:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,L_12fe
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,0xff
        LD (EFFECT_ACTIVE),A
        LD A,1
        LD (VAR_4244),A

L_1313:
        LD A,(VAR_4244)
        AND A
        JR nz,L_1313
        DJNZ L_12fe
        LD A,0x50
        LD (VAR_4244),A
        XOR A
        LD (EFFECT_PHASE),A
        JP L_0e6e

; ---- fx_none: effect handler: nothing (straight to render loop)
fx_none:
        JP L_0e6e

; ---- fx_fill_frame: fill FRAMEBUF with 0x8F then continue
fx_fill_frame:
        LD HL,FRAMEBUF
        LD BC,0x0158

L_1330:
        LD (HL),0x8f
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,L_1330
        CALL sub_12cc
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

L_134b:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,L_134b
        LD A,(HL)
        LD (DE),A
        DEC HL
        DEC DE
        LD A,0xff
        LD (EFFECT_ACTIVE),A
        LD A,1
        LD (VAR_4244),A

L_1360:
        LD A,(VAR_4244)
        AND A
        JR nz,L_1360
        DJNZ L_134b
        LD A,0x50
        LD (VAR_4244),A
        XOR A
        LD (EFFECT_PHASE),A
        JP L_0e6e

; ---- fx_scroll_copy
fx_scroll_copy:
        CALL fx_setup_scroll
        LD B,0
        LD A,(COL_COUNT)
        LD C,A
        LDIR
        LD A,0x50
        LD (VAR_4244),A
        XOR A
        LD (EFFECT_PHASE),A
        JP L_0e6e

; ---- fx_138b
fx_138b:
        LD A,0
        LD (EFFECT_ACTIVE),A
        CALL fx_setup_scroll
        LD A,(COL_COUNT)
        LD B,A
        LD A,(PAUSE_FLAG)
        CP 2
        LD C,0x80
        JR z,L_13a2
        LD C,1

L_13a2:
        LD A,8

L_13a4:
        PUSH AF
        PUSH HL
        PUSH DE
        PUSH BC

L_13a8:
        LD A,(ROW_INDEX)
        CP 6
        JR nz,L_13a8

L_13af:
        LD A,(HL)
        BIT 7,A
        JR nz,L_13b7
        AND C
        JR L_13bf

L_13b7:
        LD A,C
        CP 0xff
        LD A,0x8f
        JR nz,L_13bf
        LD A,(HL)

L_13bf:
        LD (DE),A
        INC HL
        INC DE
        DJNZ L_13af
        LD A,0xff
        LD (EFFECT_ACTIVE),A
        LD A,3
        LD (VAR_4244),A

L_13ce:
        LD A,(VAR_4244)
        AND A
        JR nz,L_13ce
        POP BC
        POP DE
        POP HL
        LD A,(PAUSE_FLAG)
        CP 2
        JR nz,L_13e3
        SCF
        RR C
        JR L_13e6

L_13e3:
        SCF
        RL C

L_13e6:
        POP AF
        DEC A
        JR nz,L_13a4
        LD A,0x50
        LD (VAR_4244),A
        XOR A
        LD (EFFECT_PHASE),A
        JP L_0e6e
        db 0xc9

; ---- store_clear_all: Reset MSG_STORE: 100 empty channels D0..? then DA
store_clear_all:
        LD A,0xd0
        LD C,0xd0
        LD HL,MSG_STORE
        LD B,0x64

L_1400:
        LD (HL),A
        INC HL
        LD (HL),C
        INC HL
        LD (HL),3
        INC HL
        INC C
        LD D,A
        LD A,C
        CP 0xda
        JR nz,L_1411
        LD C,0xd0
        INC D

L_1411:
        LD A,D
        DJNZ L_1400
        LD A,0xda
        LD (HL),A
        LD HL,SEQ_LIST
        LD (HL),0xda
        LD B,0x67

L_141e:
        INC HL
        LD (HL),0xff
        DJNZ L_141e
        RET

; ---- ir_init: misnomer - this is the message-store init. Sets the store
;      ceiling and its three derived constants, writes the 0xDA store
;      terminator at the ceiling, then zeroes 0x5EF0..0x5FFF (PKT_READY,
;      PKT_BUF and the parser state, i.e. the whole top page of RAM).
;      0x43DE = ceiling-100, the "100 KEYS LEFT" trip point (used at 0x2601).
;      0x43DC = free text bytes, the scan bound used by init_vars2 at 0x0481.
ir_init:
        LD A,0xff
        LD (RX_MSGFLAG),A
        LD HL,0x5eef
        LD (STORE_LIMIT),HL
        LD (STORE_END),HL
        LD HL,0x5e8b
        LD (VAR_43DE),HL
        LD HL,0x19e1
        LD (VAR_43DC),HL
        LD HL,0x1b0e
        LD (STORE_SIZE),HL
        LD HL,0x5eef
        LD (HL),0xda
        INC HL
        LD BC,0x0110

L_144d:
        LD (HL),0
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,L_144d
        LD HL,rx_st_wait_start
        LD (RX_STATE),HL
        LD HL,rx_st_wait_start
        LD (VAR_425E),HL
        XOR A
        LD (RX_TICKS),A
        LD (VAR_424C),A
        RET
        db 0xaa,"U"

; ---- ir_init2
ir_init2:
        PUSH AF
        XOR A
        LD (VAR_4377),A
        LD (IR_CODE),A
        LD (VAR_4387),A
        LD (IR_KEY),A
        LD (GEN_COUNTDOWN),A
        LD (VAR_4381),A
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
        JP nz,L_14b1
        PUSH HL
        LD HL,ir_st_leader
        LD (TICK_VECTOR),HL
        POP HL

L_14b1:
        LD (IR_STATE_CNT),A
        POP AF
        RET

; ---- ir_st_leader
ir_st_leader:
        PUSH AF
        IN A,(PORT_IN)
        BIT 1,A
        JP z,L_14cb
        PUSH HL
        LD HL,ir_st_leader2
        LD (TICK_VECTOR),HL
        POP HL
        LD A,4
        LD (IR_STATE_CNT),A

L_14cb:
        POP AF
        RET

; ---- ir_st_leader2
ir_st_leader2:
        PUSH AF
        IN A,(PORT_IN)
        BIT 1,A
        JP nz,L_14e2
        PUSH HL
        LD HL,ir_st_leader3
        LD (TICK_VECTOR),HL
        POP HL
        LD A,0x15
        LD (IR_STATE_CNT),A

L_14e2:
        POP AF
        RET

; ---- ir_st_leader3
ir_st_leader3:
        PUSH AF
        LD A,(IR_STATE_CNT)
        DEC A
        JR nz,L_14fc
        IN A,(PORT_IN)
        BIT 1,A
        JP z,ir_reset
        PUSH HL
        LD HL,ir_st_start
        LD (TICK_VECTOR),HL
        POP HL
        LD A,3

L_14fc:
        LD (IR_STATE_CNT),A
        POP AF
        RET

; ---- ir_st_start
ir_st_start:
        PUSH AF
        LD A,(IR_STATE_CNT)
        DEC A
        JP nz,L_151a
        IN A,(PORT_IN)
        BIT 1,A
        JP nz,ir_reset
        PUSH HL
        LD HL,ir_st_bits
        LD (TICK_VECTOR),HL
        POP HL
        LD A,8

L_151a:
        LD (IR_STATE_CNT),A
        POP AF
        RET

; ---- ir_st_bits: sample a data bit (port C0 bit1) into IR_SHIFT every 4 ticks
ir_st_bits:
        PUSH AF
        LD A,(IR_STATE_CNT)
        DEC A
        JP z,L_1540
        CP 4
        JP nz,L_155d
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

L_1540:
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
        JP z,L_1562
        LD A,8

L_155d:
        LD (IR_STATE_CNT),A
        POP AF
        RET

L_1562:
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

L_1573:
        CALL tx_try_queue
        AND A
        JR nz,L_1573
        POP DE
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

; ---- tx_bit_engine: Called every 6 ticks: shifts TX_SHIFT out on CTRL_LATCH bit 4 (1=start/space, 0=mark). Bit times from TX_TIMING table (4,4,5 ticks); state 9 = stop bits (10 ticks)
tx_bit_engine:
        LD HL,TX_STATUS
        BIT 0,(HL)
        JR nz,L_15b9
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
        OR 0x10
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,(HL)
        LD (TX_TICKS),A
        RET

L_15b9:
        LD HL,TX_TICKS
        DEC (HL)
        RET nz
        LD HL,TX_BITIDX
        INC (HL)
        LD A,(HL)
        CP 9
        JR z,L_15f2
        CP 10
        JR z,L_1603
        LD HL,TX_BITMASK
        LD E,(HL)
        SLA (HL)
        LD A,(TX_SHIFT)
        AND E
        LD A,(CTRL_LATCH_SHADOW)
        JR nz,L_15de
        OR 0x10
        JR L_15e0

L_15de:
        AND 0xef

L_15e0:
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD HL,(TX_TIMING_PTR)
        INC HL
        LD (TX_TIMING_PTR),HL
        LD A,(HL)
        LD (TX_TICKS),A
        RET

L_15f2:
        LD A,(CTRL_LATCH_SHADOW)
        AND 0xef
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,10
        LD (TX_TICKS),A
        RET

L_1603:
        LD HL,TX_STATUS
        RES 0,(HL)
        RET

; ---- rx_bit_engine: Called every 6 ticks: bit-banged receiver state machine on PORT_IN bit 3 (1 = space). Uses RX_TIMING table; assembled bytes go to RX_FIFO (8 deep, RX_COUNT)
rx_bit_engine:
        LD A,(RX_COUNT)
        CP 8
        JR nz,L_161c
        LD HL,rx_st_wait_start
        LD (RX_STATE),HL
        LD A,0
        LD (RX_TICKS),A
        RET

L_161c:
        LD A,(RX_TICKS)
        AND A
        JR z,L_1627
        DEC A
        LD (RX_TICKS),A
        RET nz

L_1627:
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
        JR z,L_1667
        XOR A

L_1667:
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
        JR nz,L_16b7
        LD A,(RX_SHIFT)
        AND A
        LD A,(RX_COUNT)
        CP 8
        JR z,L_16b7
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

L_16b7:
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
        JR z,L_16e9
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

L_16e9:
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
        JR nz,L_1716
        LD HL,pkt_st_cksum

L_1716:
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
        LD HL,(PKT_PTR)
        LD (HL),A
        LD A,(PKT_CKSUM)
        ADD A,(HL)
        LD (PKT_CKSUM),A
        LD A,(PKT_REMAIN)
        DEC A
        JR z,L_1743
        LD (PKT_REMAIN),A
        INC HL
        LD (PKT_PTR),HL
        RET

L_1743:
        LD HL,pkt_st_cksum
        LD (PKT_VECTOR),HL
        RET

; ---- pkt_st_cksum: E = computed - received. Broadcast (0x2A): no reply. Own address: send ACK 06 / NAK 15. If OK and len>0 set PKT_READY (PKT_FLAG==0x80 -> process immediately)
pkt_st_cksum:
        LD E,A
        LD A,(PKT_CKSUM)
        SUB E
        LD E,A
        LD A,(PKT_ADDR)
        CP 0x2a
        JR z,L_1769
        LD D,A
        LD A,(MY_ADDRESS)
        CP D
        JR nz,L_1785
        LD A,E
        AND A
        LD A,6
        JR z,L_1766
        LD A,0x15

L_1766:
        CALL tx_send_byte

L_1769:
        LD A,E
        AND A
        JR nz,L_1785
        LD A,(PKT_LEN)
        AND A
        JR z,L_1785
        LD A,0xff
        LD (PKT_READY),A
        XOR A
        LD (PKT_STATE),A
        LD A,(PKT_FLAG)
        CP 0x80
        JP z,pkt_process
        RET

L_1785:
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

L_17a8:
        LD A,(HL)
        ADD A,E
        LD E,A
        LD A,(HL)
        CALL tx_send_byte
        INC HL
        DJNZ L_17a8
        LD A,E
        CALL tx_send_byte
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- rx_cmd_check
rx_cmd_check:
        CALL query_dispatch
        LD A,(RX_LASTCMD)
        AND A
        RET nz
        POP HL
        POP HL
        JP L_1ad5

; ---- query_dispatch: 0xB4 + '0'..'3' query handlers
query_dispatch:
        LD A,(RX_MSGFLAG)
        AND A
        RET z
        LD A,(RX_LASTCMD)
        CP 0xb4
        RET nz
        CALL menu_getchar
        CP 0x30
        JP z,query_0_romid
        CP 0x31
        JP z,query_1_memory
        CP 0x32
        JP z,sub_17ef
        CP 0x33
        JP z,query_3_dump
        RET

sub_17ef:
        RET

; ---- query_0_romid: B4 '0': reply with 16-byte ROM ID string
query_0_romid:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD HL,TXBUF
        LD (HL),0x10
        INC HL
        LD DE,0x48
        LD BC,3
        EX DE,HL
        LDIR
        LD HL,0x4b
        LD BC,3
        LDIR
        LD HL,0x4e
        LD BC,6
        LDIR
        LD HL,0x54
        LD BC,4
        LDIR
        LD HL,TXBUF
        CALL tx_send_frame
        XOR A
        LD (RX_LASTCMD),A
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- query_1_memory: B4 '1': reply with two 5-digit ASCII numbers (STORE_SIZE, free bytes)
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
        LD (RX_LASTCMD),A
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; ---- query_3_dump: B4 '3': reply B1 addr <5-digit len> <MSG_STORE up to 0xDA> <cksum of data>
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

L_1899:
        LD A,(HL)
        CALL tx_send_byte
        INC HL
        DJNZ L_1899
        LD HL,MSG_STORE
        LD E,0

L_18a5:
        LD A,(HL)
        ADD A,E
        LD E,A
        LD A,(HL)
        CALL tx_send_byte
        LD A,(HL)
        CP 0xda
        JP z,L_18b6
        INC HL
        JP L_18a5

L_18b6:
        LD A,E
        CALL tx_send_byte
        XOR A
        LD (RX_LASTCMD),A
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

sub_18cb:
        LD B,0x2f
        LD E,(IY+0)
        LD D,(IY+1)
        BIT 7,D
        RET nz

L_18d6:
        INC B
        OR A
        SBC HL,DE
        JR nc,L_18d6
        ADD HL,DE
        LD (IX+0),B
        INC IX
        INC IY
        INC IY
        JR sub_18cb

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
        JR nz,L_1934
        LD (HL),0
        DEC HL
        LD A,(HL)
        INC A
        AND 1
        LD (HL),A
        RET

L_1934:
        DEC HL
        CP 3
        JP z,L_194a
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

L_194a:
        LD A,(HL)
        AND A
        RET z
        XOR A
        LD (HL),A
        INC A
        INC HL
        LD (HL),A
        RET

; ---- demo_scroll: scroll a space 14 times (used when blanking)
demo_scroll:
        LD B,14
        LD A,0
        LD (FONT_MODE),A

L_195a:
        LD A,0x20
        LD (CUR_CHAR),A
        PUSH BC
        CALL sub_077a
        CALL effect_step
        POP BC
        DJNZ L_195a
        RET

; ---- keypad_scan: 8x8 matrix scan: row select via CTRL_LATCH high nibble, read PORT_IN bit 3; result -> RX_BYTE
keypad_scan:
        LD L,0
        LD H,0xf0
        LD A,(CTRL_LATCH_SHADOW)
        AND 0x8f
        LD E,A
        LD B,8

L_1976:
        LD A,H
        ADD A,0x10
        LD H,A
        OR E
        LD (CTRL_LATCH),A
        IN A,(PORT_IN)
        BIT 3,A
        JR z,L_198d
        LD A,8
        ADD A,L
        LD L,A
        DJNZ L_1976
        XOR A
        JR L_1994

L_198d:
        AND 7
        ADD A,L
        JR nz,L_1994
        LD A,0x1e

L_1994:
        LD (RX_BYTE),A
        AND A
        RET

; ---- clear_framebuf: FRAMEBUF (344 bytes) = 0x80
clear_framebuf:
        PUSH HL
        PUSH BC
        LD HL,FRAMEBUF
        LD BC,0x0158

L_19a1:
        LD (HL),0x80
        INC HL
        DEC BC
        LD A,C
        OR B
        JR nz,L_19a1
        POP BC
        POP HL
        RET

; ---- clear_txbuf: zero 0x56 bytes at TXBUF
clear_txbuf:
        PUSH HL
        PUSH BC
        LD HL,TXBUF
        LD B,0x56

L_19b3:
        LD (HL),0
        INC HL
        DJNZ L_19b3
        POP BC
        POP HL
        RET

; ---- clear_glyph_tmp
clear_glyph_tmp:
        PUSH HL
        PUSH BC
        LD HL,VAR_42D6
        LD B,0x60

L_19c2:
        LD (HL),0
        INC HL
        DJNZ L_19c2
        POP BC
        POP HL
        RET

; ---- menu_enter: Enter the on-sign editor/menu (MENU_ACTIVE=FF), SP reset
menu_enter:
        LD SP,0x403f
        LD A,0xff
        LD (MENU_ACTIVE),A
        EI
        CALL init_render
        XOR A
        LD (RX_BYTE),A
        LD (VAR_4229),A
        LD (VAR_4226),A
        LD (VAR_4227),A
        LD (BEEP_TIMER),A
        LD (RX_LASTCMD),A
        LD (KEY_ECHO_TX),A
        CALL menu_getchar
        PUSH AF
        LD A,0
        LD (KEY_ECHO_TX),A
        POP AF
        LD HL,MY_ADDRESS
        CP (HL)
        JR z,L_1a0d
        CP 0x2a
        JR z,L_1a0d
        JP RESET

; ---- key_handler: Handle a key / IR code: menu navigation (ADDRESS?, TIME?, PROG MSG?, SEQ MSG? ...)
key_handler:
        LD A,0xff
        LD (VAR_4358),A
        LD A,1
        LD (KEY_ECHO_TX),A

L_1a0d:
        LD SP,0x403f
        LD A,0xff
        LD (MENU_ACTIVE),A
        EI
        CALL init_render
        LD A,(IR_CODE)
        CP 0xa4
        JR nz,L_1a40
        CALL sub_0f48

L_1a23:
        LD A,0xfe
        LD (IR_CODE),A
        LD HL,0x01a0
        LD (GEN_COUNTDOWN),HL

L_1a2e:
        LD A,(IR_CODE)
        CP 0xa4
        JR z,L_1a23
        CP 0xfe
        JR nz,L_1a40
        LD HL,(GEN_COUNTDOWN)
        LD A,H
        OR L
        JR nz,L_1a2e

L_1a40:
        CALL ir_init2
        XOR A
        LD (RX_BYTE),A
        LD (VAR_4229),A
        LD (VAR_4226),A
        LD (VAR_4227),A
        LD (BEEP_TIMER),A
        LD (VAR_435A),A
        LD A,(VAR_420F)
        INC A
        JR nz,L_1a69
        XOR A
        LD (VAR_420F),A
        CALL chan_select
        LD (STORE_CURSOR),HL
        CALL chan_find

L_1a69:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,L_1a8e
        CP 0xdb
        JP nc,L_1a8e
        DEC HL
        DEC HL
        LD A,(HL)
        CP 0xd0
        JP c,L_1a8b
        CP 0xdb
        JP nc,L_1a8b
        DEC HL
        LD (STORE_CURSOR),HL
        JP L_1aaf

L_1a8b:
        LD (STORE_CURSOR),HL

L_1a8e:
        PUSH HL
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        PUSH HL
        POP BC
        POP HL
        DEC HL

L_1a99:
        LD A,(HL)
        CP 0xd0
        JP c,L_1aa6
        CP 0xdb
        JP nc,L_1aa6
        JR L_1ab0

L_1aa6:
        DEC HL
        DEC BC
        LD A,C
        OR B
        JR nz,L_1a99
        JP pkt_process_end

L_1aaf:
        INC HL

L_1ab0:
        INC HL
        LD (INS_PTR),HL
        CALL store_finalize
        XOR A
        LD (VAR_43CF),A
        LD (VAR_43CA),A
        LD (VAR_4221),A
        LD (VAR_4220),A
        LD (FB_TMP),A
        LD (VAR_4241),A
        LD (MENU_MSG_FLAG),A
        LD A,0xff
        LD (VAR_4392),A

; ---- editor_loop: Editor main loop: get key, dispatch
editor_loop:
        CALL editor_redraw

L_1ad5:
        CALL menu_getchar
        CALL sub_263c
        LD A,(RX_LASTCMD)
        LD (CUR_CHAR),A
        CP 0x1d
        LD A,0
        JR z,L_1af0
        LD (VAR_4220),A
        LD (FB_TMP),A
        LD (VAR_43CA),A

L_1af0:
        LD (VAR_4241),A
        LD A,(VAR_4243)
        OR A
        JP nz,L_220d
        LD A,(VAR_4336)
        BIT 7,A
        JP nz,L_223a
        LD A,(RX_LASTCMD)
        CP 0x1f
        CALL z,sub_1b91
        XOR A
        LD (VAR_4392),A
        LD A,(RX_LASTCMD)
        CP 1
        JP z,L_1ad5
        CP 3
        JP z,L_20c4
        CP 5
        JP z,L_2087
        CP 0x7f
        JP z,L_2482
        CP 0x1d
        JP z,L_2465
        CP 10
        JP z,L_24f4
        CP 12
        JP z,L_250f
        CP 8
        JP z,L_2522
        CP 11
        JP z,L_2552
        CP 14
        JP z,L_20eb
        CP 0xb6
        JP z,L_2184
        CP 0x5e
        JP z,L_1f3a
        CP 0x1c
        JP z,L_216c
        CP 0x1e
        JP z,L_21b4
        CP 0x15
        JP z,L_21cc
        CP 0x16
        JP z,L_21ec
        CP 0x17
        JP z,L_1d01
        CP 2
        JP z,L_219c
        CP 0xb3
        JP z,L_2046
        CP 0xb7
        JP z,L_21e4
        CP 9
        JP z,L_220d
        CP 4
        JP z,L_223a
        CP 13
        JP z,L_1c5c
        CP 0x9f
        JP z,editor_loop
        CP 0xb1
        JP z,L_1c5c
        JP L_2580

sub_1b91:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_1b9d
        LD A,(VAR_4392)
        AND A
        RET z

L_1b9d:
        LD A,0

L_1b9f:
        LD E,A
        PUSH DE
        CALL chan_select
        POP DE
        AND A
        JP nz,pkt_process_end
        LD A,(HL)
        CP 3
        JR z,L_1c12
        LD B,0
        LD C,A
        LD IX,CHAR_FLAGS
        ADD IX,BC
        BIT 1,(IX+0)
        JR z,L_1bd8

L_1bbd:
        INC HL
        LD A,(HL)
        CP 3
        JR nz,L_1bc7
        LD A,E
        JP L_1bf2

L_1bc7:
        LD B,0
        LD C,A
        LD IX,CHAR_FLAGS
        ADD IX,BC
        BIT 1,(IX+0)
        JR z,L_1bd8
        JR L_1bbd

L_1bd8:
        LD A,E
        INC A
        CP 0x64
        JR nz,L_1b9f
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL

L_1be7:
        LD HL,MENU_STR_MSG_FULL
        CALL sub_1e32
        CP 0x64
        JP nc,L_1be7

L_1bf2:
        LD (VAR_438F),A
        CALL chan_select
        AND A
        JP nz,pkt_process_end
        LD (INS_PTR),HL
        DEC HL
        LD (STORE_CURSOR),HL
        CALL sub_20f8
        LD A,0x1f
        LD (RX_LASTCMD),A
        LD A,(VAR_438F)
        LD E,A
        JP L_1c1a

L_1c12:
        LD (INS_PTR),HL
        DEC HL
        DEC HL
        LD (STORE_CURSOR),HL

L_1c1a:
        PUSH DE
        CALL chan_find
        POP DE
        LD A,E
        CP 0x64
        JR nz,L_1c27
        LD (CHAN_LOCK),A

L_1c27:
        LD HL,SEQ_LIST
        LD (HL),E
        INC HL
        LD B,0x67

L_1c2e:
        LD (HL),0xff
        INC HL
        DJNZ L_1c2e
        LD A,E
        LD (VAR_4399),A
        RET

; ---- store_finalize: Fix up MSG_STORE terminators after an edit
store_finalize:
        LD A,0xda
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

L_1c4e:
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_INVALID
        LD (MENU_MSG_PTR),HL
        JP editor_loop

L_1c5c:
        XOR A
        LD (VAR_4336),A
        LD (VAR_4243),A
        LD A,(KEY_ECHO_TX)
        AND A
        JR z,L_1c6f
        CALL tx_send_byte
        JP L_1c9f

L_1c6f:
        LD A,(IR_CODE)
        CP 0xbe
        JR z,L_1c9f
        CP 0xa4
        JR z,L_1c7e
        CP 0xaf
        JR nz,L_1c6f

L_1c7e:
        LD A,0xff
        LD (IR_CODE),A
        LD HL,0x028a
        LD (GEN_COUNTDOWN),HL

L_1c89:
        LD A,(IR_CODE)
        CP 0xa4
        JR z,L_1c7e
        CP 0xaf
        JR z,L_1c7e
        CP 0xff
        JR nz,L_1c9f
        LD HL,(GEN_COUNTDOWN)
        LD A,H
        OR L
        JR nz,L_1c89

L_1c9f:
        LD A,0xff
        LD (MENU_FLAG),A
        LD A,(VAR_435A)
        AND A
        JP nz,L_1cee
        LD HL,(INS_PTR)
        DEC HL
        DEC HL
        LD B,2
        CALL ascii_dec_to_bin
        LD E,A
        LD HL,SEQ_LIST
        CP (HL)
        JP z,L_1cee
        LD A,0x64
        CP (HL)
        JP nz,L_1cc7
        LD A,E
        JP L_1ce3

L_1cc7:
        LD B,0x68

L_1cc9:
        LD A,(HL)
        CP E
        JP z,L_1cea
        CP 0xff
        JR z,L_1cd5
        INC HL
        DJNZ L_1cc9

L_1cd5:
        LD A,E
        LD HL,SEQ_LIST+102
        LD (HL),0xff
        LD DE,SEQ_LIST+103
        LD BC,0x67
        LDDR

L_1ce3:
        LD HL,SEQ_LIST
        LD (HL),A
        JP L_1cee

L_1cea:
        LD E,A
        LD (MENU_FLAG),A

L_1cee:
        LD SP,0x403f
        XOR A
        LD (MENU_ACTIVE),A
        LD (VAR_433B),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        JP L_000f

L_1d01:
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

L_1d1c:
        PUSH BC
        PUSH HL

L_1d1e:
        CALL menu_getchar
        LD (CUR_CHAR),A
        CP 0x3a
        JR nc,L_1d1e
        CP 0x30
        JR c,L_1d1e
        PUSH AF
        CALL glyph_lookup
        POP AF
        AND 15
        POP HL
        LD (HL),A
        INC HL
        POP BC
        DJNZ L_1d1c
        LD A,(CLK_H10)
        AND 1
        LD (CLK_H10),A
        OR A
        JR z,L_1d50
        LD A,(CLK_H1)
        CP 3
        JR c,L_1d50
        LD A,2
        LD (CLK_H1),A

L_1d50:
        LD A,0x50
        LD (VAR_4244),A

L_1d55:
        LD A,(VAR_4244)
        AND A
        JR nz,L_1d55
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STR_AM_PM
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

L_1d6d:
        CALL menu_getchar
        RES 5,A
        CP 0x59
        JR nz,L_1d7a
        LD A,0
        JR L_1d80

L_1d7a:
        CP 0x4e
        JR nz,L_1d6d
        LD A,0xff

L_1d80:
        LD (CLK_PM),A
        LD A,0
        LD (NMI_COUNT),A
        LD A,0xff
        LD (CLK_RUN),A
        JP L_206a

L_1d90:
        LD A,(MENU_ACTIVE)
        AND A
        JP nz,glyph_lookup
        LD A,(PAUSE_FLAG)
        AND A
        JR z,L_1da2
        LD HL,FONT_MODE
        RES 2,(HL)

L_1da2:
        LD A,(VAR_4213)
        LD HL,(VAR_4214)
        AND A
        JR nz,L_1dc2
        LD HL,CLK_H10
        LD A,(HL)
        AND A
        LD A,(VAR_4213)
        JR nz,L_1dc2
        LD A,(VAR_4213)
        INC A
        LD (VAR_4213),A
        INC HL
        LD (VAR_4214),HL
        JR L_1d90

L_1dc2:
        INC A
        LD (VAR_4213),A
        CP 3
        JR nz,L_1dd2
        LD A,0x3a
        LD (CUR_CHAR),A
        JP L_1e0c

L_1dd2:
        CP 6
        JR nz,L_1dde
        LD A,0x20
        LD (CUR_CHAR),A
        JP L_1e0c

L_1dde:
        CP 7
        JR nz,L_1df2
        LD A,(CLK_PM)
        AND 1
        LD A,0x41
        JR z,L_1ded
        LD A,0x50

L_1ded:
        LD (CUR_CHAR),A
        JR L_1e0c

L_1df2:
        CP 8
        JR nz,L_1dfd
        LD A,0x4d
        LD (CUR_CHAR),A
        JR L_1e1a

L_1dfd:
        LD A,(HL)
        AND 15
        OR 0x30
        LD (CUR_CHAR),A
        INC HL
        LD A,(VAR_4213)
        LD (VAR_4214),HL

L_1e0c:
        CALL sub_0cea
        LD A,(CUR_CHAR)
        JP glyph_lookup
        LD A,0x20
        LD (CUR_CHAR),A

L_1e1a:
        LD A,0xff
        LD (VAR_4213),A
        LD A,(CUR_CHAR)
        JP glyph_lookup

sub_1e25:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD (VAR_43D4),HL
        JR L_1e40

sub_1e32:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
        PUSH IY
        LD (VAR_43D4),HL
        JP L_1f14

L_1e40:
        LD HL,(INS_PTR)
        DEC HL
        LD A,(HL)
        CP 0xda
        JR nz,L_1e4d
        LD A,0x44
        JR L_1e51

L_1e4d:
        AND 15
        OR 0x30

L_1e51:
        LD (CHAN_D1),A
        DEC HL
        LD A,(HL)
        CP 0xda
        JR nz,L_1e5e
        LD A,0x44
        JR L_1e62

L_1e5e:
        AND 15
        OR 0x30

L_1e62:
        LD (CHAN_D10),A

L_1e65:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,(VAR_43D4)
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        LD B,2
        LD HL,CHAN_D10

L_1e7c:
        LD A,(HL)
        LD (CUR_CHAR),A
        PUSH HL
        PUSH BC
        CALL glyph_lookup
        POP BC
        POP HL
        INC HL
        DJNZ L_1e7c

L_1e8a:
        CALL menu_getchar
        LD (CUR_CHAR),A
        CP 4
        JP z,L_1f32
        CP 8
        JR z,L_1eeb
        CP 9
        JR z,L_1eeb
        CP 13
        JR z,L_1f1f
        CP 14
        JR z,L_1f14
        CP 0x1f
        JP z,L_1f36
        CP 0x7f
        JR z,L_1eda
        CP 0x41
        JR z,L_1f2a
        CP 0x61
        JR z,L_1f2a
        CP 0x44
        JR z,L_1f2e
        CP 0x64
        JR z,L_1f2e
        LD A,(CUR_CHAR)
        CALL is_digit
        JP nc,L_1e8a
        LD IX,CHAN_D10
        LD A,(IX+1)
        LD (IX+0),A
        LD A,(CUR_CHAR)
        LD (IX+1),A
        JP L_1e65

L_1eda:
        LD IX,CHAN_D10
        LD A,(IX+0)
        LD (IX+1),A
        LD (IX+0),0x30
        JP L_1e65

L_1eeb:
        LD A,(CHAN_D10)
        OR 0x20
        CP 0x64
        JR z,L_1f2e
        LD A,(CHAN_D1)
        OR 0x20
        CP 0x64
        JR z,L_1f2e
        LD B,2
        LD HL,CHAN_D10
        CALL ascii_dec_to_bin

L_1f05:
        LD (VAR_43D2),A
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        LD A,(VAR_43D2)
        RET

L_1f14:
        LD A,0x20
        LD (CHAN_D10),A
        LD (CHAN_D1),A
        JP L_1e65

L_1f1f:
        LD A,(CHAN_D1)
        CP 0x20
        JR nz,L_1eeb
        LD A,0x9a
        JR L_1f05

L_1f2a:
        LD A,0x99
        JR L_1f05

L_1f2e:
        LD A,0x64
        JR L_1f05

L_1f32:
        LD A,0x97
        JR L_1f05

L_1f36:
        LD A,0x98
        JR L_1f05

L_1f3a:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STRINGS
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        LD H,0
        LD A,(MY_ADDRESS)
        CP 0
        JR z,L_1f59
        CP 0x2a
        JR nz,L_1f5b

L_1f59:
        LD A,1

L_1f5b:
        LD L,A
        LD IX,MENU_ENTRY_BUF
        LD IY,DEC_TABLE+4
        CALL sub_18cb
        LD HL,MENU_ENTRY_BUF
        LD B,3

L_1f6c:
        LD A,(HL)
        CP 0x30
        JR nz,L_1f79
        LD A,B
        CP 1
        JR z,L_1f79
        INC HL
        DJNZ L_1f6c

L_1f79:
        LD A,(HL)
        CALL is_digit
        JP c,L_1f83
        LD A,0x30
        LD (HL),A

L_1f83:
        LD (CUR_CHAR),A
        PUSH HL
        PUSH BC
        CALL glyph_lookup
        POP BC
        POP HL
        INC HL
        DJNZ L_1f79
        LD HL,MENU_ENTRY_BUF
        LD B,0
        PUSH HL
        PUSH BC

L_1f97:
        CALL menu_getchar
        LD (CUR_CHAR),A
        POP BC
        POP HL
        CP 8
        JR z,L_1fd8
        CP 13
        JR z,L_1fd8
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
        JR nz,L_1fd2
        CALL clear_framebuf
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STRINGS
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

L_1fd2:
        CALL glyph_lookup
        JP L_1f97

L_1fd8:
        LD A,B
        CP 0
        JR nz,L_1fdf
        LD B,3

L_1fdf:
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
        JP L_2173

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

L_2009:
        PUSH BC
        LD E,A
        LD A,(HL)
        AND 15
        LD B,A
        CP 0
        LD A,E
        JR z,L_201b

L_2014:
        ADD A,(IX+0)
        JR c,L_2023
        DJNZ L_2014

L_201b:
        INC HL
        DEC IX
        POP BC
        DJNZ L_2009
        OR A
        RET

L_2023:
        POP BC
        SCF
        RET
; ---- POW10_BYTES: place values 1, 10, 100 for ascii_dec_to_bin
POW10_BYTES:
        db 0x01,0x0a,"d"

; ---- is_digit: C set if A is ASCII 0-9
is_digit:
        CP 0x3a
        JR nc,L_2033
        CP 0x30
        JR c,L_2033
        SCF
        RET

L_2033:
        OR A
        RET

; ---- menu_addr_invalid
menu_addr_invalid:
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_INVALID
        LD (MENU_MSG_PTR),HL
        CALL editor_redraw
        JP L_1f3a

L_2046:
        LD HL,(STORE_CURSOR)

L_2049:
        LD A,(HL)
        CP 3
        JR z,L_2051
        INC HL
        JR L_2049

L_2051:
        DEC HL
        LD (STORE_CURSOR),HL
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,editor_loop
        CP 0xdb
        JP nc,editor_loop
        DEC HL
        LD (STORE_CURSOR),HL
        JP L_2087

L_206a:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,editor_loop
        CP 0xdb
        JP nc,editor_loop
        JP L_2087

; ---- data 207b-2086:
STR_TOP_OF_MSG:
        db "TOP OF MSG ",0x00

L_2087:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,STR_TOP_OF_MSG
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        LD B,2
        LD HL,(STORE_CURSOR)

L_209e:
        LD A,(HL)
        CP 0xda
        JR nz,L_20a7
        LD A,0x44
        JR L_20b4

L_20a7:
        AND 15
        OR 0x30
        CALL is_digit
        JP c,L_20b4
        LD A,0x30
        LD (HL),A

L_20b4:
        LD (CUR_CHAR),A
        PUSH HL
        PUSH BC
        CALL glyph_lookup
        POP BC
        POP HL
        INC HL
        DJNZ L_209e
        JP L_1ad5

L_20c4:
        CALL init_render
        LD HL,(FB_COL)
        LD (FB_COLPTR),HL
        LD HL,MENU_STR_CLR_ALL
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        CALL menu_getchar
        AND 0x5f
        CP 0x59
        JP nz,editor_loop
        CALL store_clear_all
        CALL store_finalize
        LD A,0
        JP L_2219

L_20eb:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_206a
        CALL sub_20f8
        JP L_2087

sub_20f8:
        LD HL,(STORE_CURSOR)
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        PUSH HL
        POP BC
        CP 0xd0
        LD HL,(STORE_CURSOR)

L_2108:
        LD A,(HL)
        CP 0xd0
        JP c,L_2115
        CP 0xdb
        JP nc,L_2115
        JR L_211f

L_2115:
        DEC HL
        DEC BC
        LD A,B
        OR C
        JP z,pkt_process_end
        JP L_2108

L_211f:
        INC HL
        LD A,(HL)
        CP 0xd0
        JP c,L_212d
        CP 0xdb
        JP nc,L_212d
        JR L_212e

L_212d:
        DEC HL

L_212e:
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

L_216c:
        LD A,(VAR_4358)
        CPL
        LD (VAR_4358),A

L_2173:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,editor_loop
        CP 0xdb
        JP nc,editor_loop
        JP L_2087

L_2184:
        LD A,(VAR_4364)
        CPL
        LD (VAR_4364),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,editor_loop
        CP 0xdb
        JP nc,editor_loop
        JP L_2087

L_219c:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_1c4e
        LD A,0xff
        LD (VAR_43CF),A
        JP editor_loop

L_21b4:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_1c4e
        LD A,0xff
        LD (VAR_4221),A
        JP editor_loop

L_21cc:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_1c4e
        LD A,0xff
        LD (VAR_4220),A
        JP editor_loop

L_21e4:
        LD A,0xff
        LD (VAR_43CA),A
        JP editor_loop

L_21ec:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,editor_loop
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_1c4e
        LD A,0xff
        LD (FB_TMP),A
        JP editor_loop
        CP 0x30
        JR nz,L_220b
        LD A,0x39
        RET

L_220b:
        DEC A
        RET

L_220d:
        LD HL,MENU_STR_PROG_MSG
        CALL sub_1e25
        CP 0x65
        JP nc,L_220d
        LD E,A

L_2219:
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
        CALL chan_find
        POP DE
        LD A,E
        CP 0x64
        JR nz,L_2237
        LD (CHAN_LOCK),A

L_2237:
        JP L_2087

L_223a:
        LD A,0xff
        LD (VAR_435A),A
        LD HL,SEQ_LIST
        LD B,0x68
        LD A,0xff

L_2246:
        LD (HL),A
        INC HL
        DJNZ L_2246
        LD (VAR_4336),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        LD B,0x67

L_2255:
        PUSH BC
        LD HL,MENU_STR_SEQ_MSG
        LD A,B
        CP 0x67
        JR z,L_2263
        CALL sub_1e32
        JR L_2266

L_2263:
        CALL sub_1e25

L_2266:
        POP BC
        CP 0x98
        JR z,L_22a5
        CP 0x97
        JR z,L_228f
        CP 0x99
        JR z,L_22ef
        CP 0x9a
        JP z,L_1c5c
        LD HL,(SEQ_PTR)
        LD (HL),A
        INC HL
        LD (SEQ_PTR),HL
        DJNZ L_2255
        LD HL,MENU_STR_SEQ_FULL
        INC HL
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text
        CALL sub_2a21

L_228f:
        LD A,0
        LD (VAR_4336),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,editor_loop
        CP 0xdb
        JP nc,editor_loop
        JP L_2087

L_22a5:
        CALL menu_getchar
        CP 0x12
        JR z,L_22a5
        CP 0x43
        JR z,L_22b5
        CP 0x63
        JP nz,L_228f

L_22b5:
        LD A,0xff
        LD (VAR_420F),A
        LD HL,TEST_MESSAGE
        LD DE,VAR_43A5

L_22c0:
        LD A,(HL)
        LD (DE),A
        CP 3
        JR z,L_22ca
        INC HL
        INC DE
        JR L_22c0

L_22ca:
        PUSH DE
        LD DE,0
        LD BC,0x4000
        LD HL,0

L_22d4:
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
        JR nz,L_22d4
        POP DE
        CALL sub_2a41
        INC DE
        INC DE
        INC DE
        INC DE
        LD A,3
        LD (DE),A
        JP L_1c5c

L_22ef:
        LD HL,SEQ_LIST
        LD A,0
        LD B,0x64

L_22f6:
        LD (HL),A
        INC HL
        INC A
        DJNZ L_22f6
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        INC HL
        LD (HL),0xff
        JP L_1c5c

; ---- menu_getchar
menu_getchar:
        CALL editor_getkey
        LD A,(RX_LASTCMD)
        AND A
        JR z,menu_getchar
        RET

; ---- editor_getkey: Editor key source: echoes the previous key on the serial TX, then takes a key from the serial RX FIFO if present, else from the IR decoder (IR_CODE). So the on-sign editor can be driven from a serial terminal as well as the remote.
editor_getkey:
        LD A,(KEY_ECHO_TX)
        AND A
        JR z,L_231c
        CALL tx_send_byte

L_231c:
        CALL rx_fifo_get
        JP c,L_233f
        AND A
        JR z,L_233f
        XOR A
        LD (VAR_4364),A
        LD A,(VAR_4226)
        LD (VAR_4227),A
        LD A,(RX_LASTCMD)
        LD (VAR_4226),A
        LD A,(RX_BYTE)
        LD (RX_LASTCMD),A
        LD (KEY_ECHO_TX),A
        RET

L_233f:
        LD A,(IR_CODE)
        AND A
        JR z,L_237d
        AND 0x3f
        LD (VAR_4387),A
        XOR A
        LD (IR_CODE),A
        LD A,(VAR_4387)
        CP 0x3e
        JR z,L_2376
        LD C,A
        LD A,(IR_KEY)
        CP C
        JR nz,L_2384
        LD A,(VAR_4377)
        AND A
        JR nz,L_2393
        CP 0x24
        JR z,L_237d
        LD HL,(GEN_COUNTDOWN)
        LD A,H
        OR L
        JR nz,L_237d
        LD HL,0x012c
        LD (GEN_COUNTDOWN),HL
        JP L_23a3

L_2376:
        XOR A
        LD (IR_KEY),A
        LD (VAR_4377),A

L_237d:
        XOR A
        LD (VAR_4229),A
        JP L_2418

L_2384:
        LD A,(VAR_4387)
        LD (IR_KEY),A
        LD (VAR_4377),A
        XOR A
        LD (IR_CODE),A
        JR L_237d

L_2393:
        LD A,(VAR_4387)
        LD (IR_KEY),A
        LD HL,0x0514
        LD (GEN_COUNTDOWN),HL
        XOR A
        LD (VAR_4377),A

L_23a3:
        LD A,(VAR_4387)
        CP 0x1d
        JR nz,L_23c1
        CALL sub_0f48
        LD A,(SHIFT_STATE)
        CPL
        LD (SHIFT_STATE),A
        AND A
        LD A,0x1d
        JR nz,L_23bb
        LD A,0x9f

L_23bb:
        LD (VAR_4229),A
        JP L_2408

L_23c1:
        LD HL,IR_KEY_TABLE
        LD D,0
        LD E,A
        ADD HL,DE
        LD A,(HL)
        LD (RX_BYTE),A
        LD A,(VAR_4364)
        LD HL,CHARSET_GRAPHICS
        OR A
        JR nz,L_23f5
        LD A,(SHIFT_STATE)
        LD HL,CHARSET_LOWER
        AND A
        JR z,L_23ec
        LD HL,CHARSET_UPPER2
        LD A,(VAR_4358)
        AND A
        JR z,L_23f5
        LD HL,CHARSET_LOWER2
        JR L_23f5

L_23ec:
        LD A,(VAR_4358)
        AND A
        JR z,L_23f5
        LD HL,CHARSET_UPPER

L_23f5:
        LD A,(RX_BYTE)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(HL)
        LD (VAR_4229),A
        LD A,0
        LD (SHIFT_STATE),A
        CALL sub_0f48

L_2408:
        XOR A
        LD (VAR_4364),A
        LD A,(VAR_4226)
        LD (VAR_4227),A
        LD A,(RX_LASTCMD)
        LD (VAR_4226),A

L_2418:
        LD A,(VAR_4229)
        LD (RX_LASTCMD),A
        XOR A
        LD (KEY_ECHO_TX),A
        LD A,(RX_LASTCMD)
        AND A
        RET

; ---- data 2427-2464: IR/keypad code -> character map
IR_KEY_TABLE:
        db 0x0f,0x33,0x0c,0x0b,0x0d,0x09,0x0a,0x0e,0x03,0x3f,0x3c,0x3b,0x3d,0x39,0x3a,0x3e
        db 0x2f,0x13,0x2c,0x2b,0x2d,0x29,0x2a,0x2e,0x24,0x23,0x1c,0x1b,0x1d,0x1d,0x1a,0x22
        db 0x31,0x30,0x37,0x36,0x35,0x08,0x32,0x34,0x01,0x00,0x07,0x06,0x05,0x38,0x02,0x04
        db 0x11,0x10,0x17,0x16,0x15,0x28,0x12,0x14,0x21,0x20,0x27,0x26,0x25,0x18

L_2465:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,editor_loop
        LD A,(SHIFT_STATE)
        OR A
        JR z,L_247f
        LD A,0xff
        LD (VAR_4241),A
        LD HL,STR_SHIFT
        LD (MENU_MSG_PTR),HL

L_247f:
        JP editor_loop

L_2482:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_206a
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,editor_loop
        CP 0xd0
        JP c,L_24aa
        CP 0xdb
        JP nc,L_24aa
        JP L_2087

L_24aa:
        LD A,0
        LD (EFFECT_ACTIVE),A
        LD HL,(STORE_END)
        DEC HL
        LD (STORE_END),HL
        CALL sub_0cea
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
        LD (EFFECT_ACTIVE),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,editor_loop
        CP 0xdb
        JP nc,editor_loop
        DEC HL
        LD (STORE_CURSOR),HL
        JP L_2087
        db 0xc3,0xd2,0x1a

L_24f4:
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JR z,L_250c
        INC HL
        LD A,(HL)
        CP 0xd0
        JP c,L_2509
        CP 0xdb
        JP nc,L_2509
        INC HL

L_2509:
        LD (STORE_CURSOR),HL

L_250c:
        JP editor_loop

L_250f:
        LD B,8
        LD HL,(STORE_CURSOR)

L_2514:
        LD A,(HL)
        CP 3
        JR z,L_251f
        INC HL
        LD (STORE_CURSOR),HL
        DJNZ L_2514

L_251f:
        JP editor_loop

L_2522:
        LD IX,(STORE_CURSOR)
        LD A,(IX+0)
        CP 0xd0
        JP c,L_2536
        CP 0xdb
        JP nc,L_2536
        JP L_2087

L_2536:
        DEC IX
        LD (STORE_CURSOR),IX
        LD A,(IX+0)
        CP 0xd0
        JP c,editor_loop
        CP 0xdb
        JP nc,editor_loop
        DEC IX
        LD (STORE_CURSOR),IX
        JP L_2087

L_2552:
        LD B,8
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,L_2565
        CP 0xdb
        JP nc,L_2565
        JP L_2087

L_2565:
        DEC HL
        LD (STORE_CURSOR),HL
        LD A,(HL)
        CP 0xd0
        JP c,L_2552
        CP 0xdb
        JP nc,L_2552
        DEC HL
        LD (STORE_CURSOR),HL
        JP L_2087
        DJNZ L_2565
        JP editor_loop

L_2580:
        LD (CUR_CHAR),A
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_206a
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JP z,L_2615
        CP 0xd0
        JP c,L_25a1
        CP 0xdb
        JP nc,L_25a1
        INC HL
        LD (STORE_CURSOR),HL

L_25a1:
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,0
        LD (EFFECT_ACTIVE),A
        LD HL,(STORE_END)
        INC HL
        LD (STORE_TMP),HL
        LD DE,(STORE_LIMIT)
        OR A
        SBC HL,DE
        LD A,H
        OR L
        JR nz,L_25d1
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_MEM_FULL
        LD (MENU_MSG_PTR),HL
        JP editor_loop

L_25d1:
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
        LD DE,(VAR_43DE)
        OR A
        SBC HL,DE
        JR nz,L_2615
        LD A,0xff
        LD (MENU_MSG_FLAG),A
        LD HL,MENU_STR_100_KEYS
        LD (MENU_MSG_PTR),HL

L_2615:
        JP editor_loop

; ---- store_make_room
store_make_room:
        LD HL,(STORE_CURSOR)
        LD DE,(STORE_LIMIT)
        INC HL
        LD (STORE_CURSOR),HL
        OR A
        SBC HL,DE
        JR nz,L_263b
        LD A,(MENU_ACTIVE)
        AND A
        JR nz,L_2636
        LD HL,MSG_STORE
        LD (STORE_CURSOR),HL
        JR L_263b

L_2636:
        LD A,0xff
        LD (VAR_4236),A

L_263b:
        RET

sub_263c:
        CALL sub_264c
        CALL sub_26d1
        CALL sub_2661
        CALL editor_key_to_attr
        CALL rx_cmd_check
        RET

sub_264c:
        LD A,(VAR_4221)
        OR A
        RET z
        LD A,(RX_LASTCMD)
        AND 15
        OR 0xa0
        LD (RX_LASTCMD),A
        LD A,0
        LD (VAR_4221),A
        RET

sub_2661:
        LD A,(VAR_43CF)
        AND A
        RET z
        LD A,(RX_LASTCMD)
        AND 7
        OR 0xf0
        LD (RX_LASTCMD),A
        XOR A
        LD (VAR_43CF),A
        RET

; ---- editor_key_to_attr: Translate editor function keys to message bytes: 1E->B8 graphic,11->B9 thin,19->BA wait,14->B0 remark,12->06 pause,15->BC rainbow, 8F.. colours etc.
editor_key_to_attr:
        LD A,(VAR_43CA)
        AND A
        RET z
        XOR A
        LD (VAR_43CA),A
        LD A,(RX_LASTCMD)
        LD C,0xb8
        CP 0x1e
        JR z,L_26cc
        INC C
        CP 0x11
        JR z,L_26cc
        INC C
        CP 0x19
        JR z,L_26cc
        LD C,0xb0
        CP 0x14
        JR z,L_26cc
        LD C,6
        CP 0x12
        JR z,L_26cc
        LD C,0xbc
        CP 0x15
        JR z,L_26cc
        CP 0x8f
        JR z,L_26cc
        LD C,0x3f
        CP 0x51
        JR z,L_26cc
        CP 0x71
        JR z,L_26cc
        LD C,0x21
        CP 0x58
        JR z,L_26cc
        CP 0x78
        JR z,L_26cc
        LD C,0x5e
        CP 0x1f
        JR z,L_26cc
        LD C,0xbe
        CP 0x10
        JR z,L_26cc
        POP HL
        POP HL
        JP L_206a

L_26cc:
        LD A,C
        LD (RX_LASTCMD),A
        RET

sub_26d1:
        LD A,(VAR_4220)
        AND A
        JR nz,L_26de
        LD A,(FB_TMP)
        AND A
        JR nz,L_26fb
        RET

L_26de:
        LD A,(RX_LASTCMD)
        AND 15
        DEC A
        CP 10
        JR c,L_26ea
        LD A,2

L_26ea:
        NOP
        LD HL,FG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (RX_LASTCMD),A
        XOR A
        LD (VAR_4220),A
        RET

L_26fb:
        LD A,(RX_LASTCMD)
        AND 7
        DEC A
        CP 6
        JR c,L_2707
        LD A,5

L_2707:
        NOP
        LD HL,BG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (RX_LASTCMD),A
        XOR A
        LD (FB_TMP),A
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
        LD (EFFECT_ACTIVE),A
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD A,(VAR_4243)
        AND A
        JP nz,L_28f3
        LD A,(VAR_4336)
        BIT 7,A
        JP nz,L_28f3
        LD A,(VAR_4399)
        AND A
        JP nz,L_28f3
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,L_2764
        CP 0xdb
        JP nc,L_2764
        JP L_28f3

L_2764:
        LD DE,0x15
        OR A
        SBC HL,DE
        LD (VAR_4344),HL
        LD DE,(INS_PTR)
        OR A
        SBC HL,DE
        JR nc,L_277a
        EX DE,HL
        LD (VAR_4344),HL

L_277a:
        LD HL,(INS_PTR)
        LD (VAR_425A),HL

L_2780:
        LD HL,(VAR_425A)
        LD A,(HL)
        LD (CUR_CHAR),A
        LD A,0xff
        LD (TINY_MODE),A
        LD A,(CUR_CHAR)
        CP 0x20
        JR nz,L_27a4
        LD A,(VAR_439A)
        AND A
        JP z,L_28b0
        XOR A
        LD (VAR_433B),A
        LD (FONT_MODE),A
        JP L_28b0

L_27a4:
        BIT 7,A
        JP nz,L_27b0
        AND 0x60
        JR z,L_27d3
        JP L_28b0

L_27b0:
        LD A,(CUR_CHAR)
        CP 0x94
        JP c,L_27d3
        CP 0x9f
        JP c,L_28b0
        AND 0xf0
        CP 0xc0
        JP z,L_28b0
        CP 0xe0
        JP z,L_28b0
        CP 0xd0
        JP z,L_28b0
        CP 0xa0
        JP z,L_28b0

L_27d3:
        LD A,(CUR_CHAR)
        CP 0x15
        JP z,L_28b0
        CP 0x16
        JP z,L_28b0
        CP 0xbd
        JR nz,L_27eb
        XOR A
        LD (VAR_439A),A
        LD A,(CUR_CHAR)

L_27eb:
        CP 15
        JP z,L_2869
        CP 0x19
        JP z,L_2869
        CP 0x1a
        JP z,L_2869
        CP 0x1b
        JP z,L_2869
        CP 0x18
        JP z,L_2878
        CP 0x11
        JP nz,L_2812
        XOR A
        LD (VAR_421E),A
        LD (FONT_MODE),A
        JR L_287d

L_2812:
        CP 0x14
        JP nz,L_281e
        LD A,0x10
        LD (VAR_43A2),A
        JR L_287d

L_281e:
        CP 0x13
        JP nz,L_282a
        LD A,0x64
        LD (FONT_MODE),A
        JR L_287d

L_282a:
        CP 0x12
        JP nz,L_2837
        XOR A
        SET 1,A
        LD (FONT_MODE),A
        JR L_287d

L_2837:
        CP 0x10
        JP nz,L_2847
        XOR A
        SET 1,A
        SET 3,A
        LD (FONT_MODE),A
        JP L_287d

L_2847:
        CP 0xb9
        JP nz,L_2858
        LD A,0xff
        LD (VAR_43D6),A
        XOR A
        LD (VAR_433B),A
        JP L_287d

L_2858:
        CP 0x1f
        JP nz,L_287d
        XOR A
        LD (FONT_MODE),A
        LD A,0xff
        LD (VAR_439A),A
        JP L_287d

L_2869:
        LD A,(VAR_43D6)
        AND A
        JP nz,L_287d
        LD A,0xff
        LD (VAR_433B),A
        JP L_287d

L_2878:
        LD A,0
        LD (VAR_433B),A

L_287d:
        LD HL,(VAR_425A)
        LD DE,(VAR_4344)
        OR A
        EX DE,HL
        SBC HL,DE
        EX DE,HL
        JP c,L_2892
        JP z,L_2892
        JP L_28e0

L_2892:
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
        JP L_28e0

L_28b0:
        LD HL,(VAR_425A)
        LD DE,(VAR_4344)
        OR A
        EX DE,HL
        SBC HL,DE
        EX DE,HL
        JP c,L_28c5
        JP z,L_28c5
        JP L_28e0

L_28c5:
        XOR A
        LD (TINY_MODE),A
        LD A,(CUR_CHAR)
        AND 0xf0
        CP 0xa0
        LD A,(CUR_CHAR)
        JR nz,L_28da
        AND 15
        LD (CUR_CHAR),A

L_28da:
        CALL sub_072a
        CALL glyph_lookup

L_28e0:
        LD HL,(VAR_425A)
        INC HL
        LD (VAR_425A),HL
        LD DE,(STORE_CURSOR)
        EX DE,HL
        OR A
        SBC HL,DE
        EX DE,HL
        JP nc,L_2780

L_28f3:
        LD A,0xff
        LD (TINY_MODE),A
        LD A,(VAR_4221)
        AND A
        JR z,L_2904
        LD HL,STR_GRAPH
        JP L_2988

L_2904:
        LD A,(VAR_4220)
        OR A
        JR z,L_2910
        LD HL,STR_COLOR
        JP L_2988

L_2910:
        LD A,(FB_TMP)
        OR A
        JR z,L_291c
        LD HL,STR_BGRND
        JP L_2988

L_291c:
        LD A,(VAR_43CA)
        OR A
        JR z,L_2928
        LD HL,STR_FUNC
        JP L_2988

L_2928:
        LD A,(VAR_4364)
        OR A
        JR z,L_2934
        LD HL,STR_EURO
        JP L_2988

L_2934:
        LD A,(VAR_43CF)
        OR A
        JP z,L_2941
        LD HL,STR_SPEED
        JP L_2988

L_2941:
        LD A,(VAR_4399)
        OR A
        JP z,L_298e
        XOR A
        LD (VAR_4399),A
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

L_2965:
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
        DJNZ L_2965
        JR L_298e

; ---- data 2979-2987:
STR_MAGIC_MSG:
        db "    MAGIC MSG ",0x00

L_2988:
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

L_298e:
        LD A,(VAR_4241)
        AND A
        JR z,L_299d
        LD HL,(MENU_MSG_PTR)
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

L_299d:
        LD A,(MENU_MSG_FLAG)
        OR A
        JR z,L_29ad
        LD HL,(MENU_MSG_PTR)
        INC HL
        LD (MENU_TEXT_PTR),HL
        CALL menu_show_text

L_29ad:
        CALL sub_2a21
        LD A,(MENU_MSG_FLAG)
        OR A
        JR z,L_29d3
        CALL sub_29d9
        LD A,0
        LD (MENU_MSG_FLAG),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,L_29d0
        CP 0xdb
        JP nc,L_29d0
        POP HL
        JP L_2087

L_29d0:
        JP editor_redraw

L_29d3:
        LD A,0xff
        LD (EFFECT_ACTIVE),A
        RET

sub_29d9:
        LD A,0xff
        LD (EFFECT_ACTIVE),A

L_29de:
        LD A,(ROW_INDEX)
        CP 3
        JR nz,L_29de

L_29e5:
        LD A,(ROW_INDEX)
        CP 2
        JR nz,L_29e5
        LD A,0x50
        LD (VAR_4244),A

L_29f1:
        LD A,(VAR_4244)
        AND A
        JR nz,L_29f1
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

L_2a08:
        LD A,(HL)
        INC HL
        OR A
        JR z,L_2a18
        LD (CUR_CHAR),A
        PUSH HL
        CALL glyph_lookup
        POP HL
        JP L_2a08

L_2a18:
        POP AF
        LD (CUR_CHAR),A
        POP AF
        LD (TINY_MODE),A
        RET

sub_2a21:
        LD HL,(FB_COLPTR)
        LD DE,0x56
        XOR A
        SBC HL,DE
        LD (FB_COL),HL
        LD DE,FRAMEBUF
        XOR A
        SBC HL,DE
        JP nc,L_2a3d
        LD DE,FB_COLPTR
        ADD HL,DE
        LD (FB_COL),HL

L_2a3d:
        RET

; ---- pkt_process_end
pkt_process_end:
        JP RESET

sub_2a41:
        PUSH DE
        LD B,2
        LD C,H

L_2a45:
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
        DJNZ L_2a45
        POP DE
        RET

; ---- nibble_to_hex: A = ASCII hex digit for low nibble
nibble_to_hex:
        OR 0x30
        CP 0x3a
        RET c
        ADD A,7
        RET

; ---- pkt_process: Process a received packet: wait for TX idle, DI, walk PKT_BUF byte by byte. Bytes in IGNORE_TABLE are skipped; command bytes dispatch (02 speed,03 clear all,04 sequence,09 channel,0D end,0E delete channel text,15 fg idx,16 bg idx,17 time,1E A0-colour,B3 append,B4 query); anything else is inserted as message text
pkt_process:
        LD A,(TX_STATUS)
        AND 3
        JR nz,pkt_process
        DI
        LD SP,0x403f
        LD A,(CTRL_LATCH_SHADOW)
        OR 15
        LD (CTRL_LATCH_SHADOW),A
        LD (CTRL_LATCH),A
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 0xd0
        JP c,L_2a90
        CP 0xdb
        JP nc,L_2a90
        DEC HL
        LD (STORE_CURSOR),HL

L_2a90:
        PUSH HL
        LD DE,MSG_STORE
        OR A
        SBC HL,DE
        PUSH HL
        POP BC
        POP HL
        DEC HL

L_2a9b:
        LD A,(HL)
        CP 0xd0
        JP c,L_2aa8
        CP 0xdb
        JP nc,L_2aa8
        JR L_2ab1

L_2aa8:
        DEC HL
        DEC BC
        LD A,C
        OR B
        JR nz,L_2a9b
        JP pkt_process_end

L_2ab1:
        LD (STORE_CURSOR),HL
        INC HL
        LD (INS_PTR),HL
        CALL store_finalize
        LD A,(PKT_LEN)
        AND A
        JP z,pkt_process_done
        LD B,A
        LD HL,PKT_BUF

L_2ac6:
        LD A,(HL)
        PUSH HL
        PUSH BC
        LD (CUR_CHAR),A
        CALL is_ignored_byte
        AND A
        JP z,L_2b61
        CP 2
        JP z,cmd_02_speed
        CP 3
        JP z,cmd_03_clear_all
        CP 4
        JP z,cmd_04_sequence
        CP 9
        JP z,cmd_09_channel
        CP 13
        JP z,pkt_process_done
        CP 14
        JP z,cmd_0E_delete_text
        CP 0x15
        JP z,cmd_15_fore_idx
        CP 0x16
        JP z,cmd_16_back_idx
        CP 0x17
        JP z,cmd_17_set_time
        CP 0x1e
        JP z,cmd_1E_colour_A0
        CP 0xb3
        JP z,cmd_B3_append
        CP 0xb4
        JP z,cmd_B4_query

; ---- pkt_insert_text: Insert CUR_CHAR at STORE_CURSOR (shifts the store up; refuses when CHAN_LOCK or memory full)
pkt_insert_text:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_2b61
        LD HL,(STORE_CURSOR)
        LD A,(HL)
        CP 3
        JR nz,L_2b22
        DEC HL
        ; B6: assembler typo - opcode 0x32 (LD (nn),A) where 0x22 (LD (nn),HL)
        ; was meant. A is 3 here (the CP above matched), so instead of backing
        ; the cursor off the 0x03 terminator it stamps 0x03 into the cursor's
        ; low byte and the next insert lands at a random spot in the channel.
        LD (STORE_CURSOR),A

L_2b22:
        LD HL,(STORE_END)
        INC HL
        LD (STORE_TMP),HL
        LD DE,(STORE_LIMIT)
        OR A
        SBC HL,DE
        LD A,H
        OR L
        JR z,L_2b61
        LD HL,(STORE_TMP)
        LD (STORE_END),HL
        CALL store_make_room
        ; B7: the tail is shifted from STORE_LIMIT rather than STORE_END, so
        ; every inserted byte moves the whole remaining store (~6.9 KB) with
        ; interrupts off instead of just the live text. STORE_END was bumped
        ; at 0x2B37, so it is already the new end-of-store and everything
        ; above it is dead space.
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

L_2b61:
        POP BC
        POP HL
        INC HL
        DEC B
        JP nz,L_2ac6

; ---- pkt_process_done: clear PKT_READY/PKT_STATE, re-init and return to main loop
pkt_process_done:
        LD SP,0x403f
        XOR A
        LD (PKT_READY),A
        LD (PKT_STATE),A
        LD (MENU_ACTIVE),A
        LD (VAR_433B),A
        LD HL,SEQ_LIST
        LD (SEQ_PTR),HL
        CALL sub_2b84
        JP L_000f

sub_2b84:
        LD B,0x55
        XOR A

L_2b87:
        OUT (PORT_40_OUT),A
        DJNZ L_2b87
        OUT (PORT_STROBE),A
        RET

; ---- cmd_03_clear_all
cmd_03_clear_all:
        CALL store_clear_all
        CALL store_finalize
        JP L_2cba

; ---- cmd_0E_delete_text: delete existing text of the selected channel (from INS_PTR to its 0x03 terminator)
cmd_0E_delete_text:
        LD A,(CHAN_LOCK)
        OR A
        JP nz,L_2b61
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
        JP z,L_2b61
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
        JP L_2b61

; ---- cmd_B4_query: B4 n: '0' rom id, '1' memory, '2' nop, '3' dump
;      B1: the EI below plus the query -> tx_send_frame -> tx_send_byte ->
;      tx_try_queue chain (~40 bytes deep) leaves too little of the stock
;      64-byte stack for an interrupt frame + tick6_service + rx_consume.
;      Fixed by the relocated stack in the patched build.
cmd_B4_query:
        CALL clear_framebuf
        CALL sub_2b84
        EI
        CALL pkt_next_byte
        CP 0x30
        CALL z,query_0_romid
        CP 0x31
        CALL z,query_1_memory
        CP 0x32
        CALL z,sub_17ef
        CP 0x33
        CALL z,query_3_dump

L_2bf9:
        LD A,(TX_STATUS)
        AND 3
        JR nz,L_2bf9
        DI
        JP z,L_2b61

; ---- cmd_1E_colour_A0: 1E n -> insert 0xA0|(n&15)
cmd_1E_colour_A0:
        CALL pkt_next_byte
        AND 15
        OR 0xa0
        LD (CUR_CHAR),A
        JP pkt_insert_text

; ---- cmd_15_fore_idx: 15 n -> insert FG_IDX_TABLE[n]
cmd_15_fore_idx:
        CALL pkt_next_byte
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
        LD HL,BG_IDX_TABLE
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(HL)
        LD (CUR_CHAR),A
        JP pkt_insert_text

; ---- cmd_17_set_time: 17 h h m m a: 4 ASCII digits -> CLK_H10..CLK_M1, a=Y/y -> AM else PM.
;      B2: CLK_RUN is cleared here but restored only at 0x2C59, and every
;      pkt_next_byte below can jump straight to pkt_process_done on a short
;      packet - NETCC's "status query" 17 32 does exactly that and stops the
;      clock. Fixed in pkt_process_done in the patched build.
;      Unlike the menu's time editor (0x1D14..0x1D8A) this path does not reset
;      NMI_COUNT, so the new time starts up to one second out of phase.
cmd_17_set_time:
        XOR A
        LD (CLK_RUN),A
        LD HL,CLK_H10
        LD B,4

L_2c3c:
        CALL pkt_next_byte
        LD (CUR_CHAR),A
        AND 15
        LD (HL),A
        INC HL
        DJNZ L_2c3c
        CALL pkt_next_byte
        AND 0x5f
        CP 0x59
        LD A,0xff
        JR nz,L_2c54
        XOR A

L_2c54:
        LD (CLK_PM),A
        LD A,0xff
        LD (CLK_RUN),A
        JP L_2b61

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
        OR 0xf0
        LD (CUR_CHAR),A
        JP pkt_insert_text

; ---- cmd_B3_append: B3: move STORE_CURSOR to end of current channel
cmd_B3_append:
        LD HL,(STORE_CURSOR)

L_2c83:
        LD A,(HL)
        CP 3
        JR z,L_2c8b
        INC HL
        JR L_2c83

L_2c8b:
        DEC HL
        LD (STORE_CURSOR),HL
        LD A,(HL)
        CP 0xd0
        JP c,L_2b61
        CP 0xdb
        JP nc,L_2b61
        DEC HL
        LD (STORE_CURSOR),HL
        JP L_2b61

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

L_2cba:
        PUSH DE
        CALL chan_select
        POP DE
        LD (INS_PTR),HL
        DEC HL
        DEC HL
        LD (STORE_CURSOR),HL
        PUSH DE
        CALL chan_find
        POP DE
        LD A,E
        CP 0x64
        JR nz,L_2cd4
        LD (CHAN_LOCK),A

L_2cd4:
        JP L_2b61

; ---- cmd_04_sequence: 04 dd dd ... [D|d]: rebuild SEQ_LIST from 2-digit channel numbers
cmd_04_sequence:
        LD HL,SEQ_LIST
        LD A,0
        LD B,0x64

L_2cde:
        LD (HL),A
        INC HL
        INC A
        DJNZ L_2cde
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

L_2cf6:
        CALL pkt_next_byte
        CP 0x44
        JR z,L_2d3e
        CP 0x64
        JR z,L_2d3e
        LD (CUR_CHAR),A
        CP 0x3a
        JP nc,L_2b61
        CP 0x30
        JP c,L_2b61
        AND 15
        LD (CHAN_D10),A
        CALL pkt_next_byte
        CP 0x44
        JR z,L_2d3e
        CP 0x64
        JR z,L_2d3e
        LD (CUR_CHAR),A
        CP 0x3a
        JP nc,L_2b61
        CP 0x30
        JP c,L_2b61
        AND 15
        LD (CHAN_D1),A
        PUSH BC
        PUSH HL
        LD B,2
        LD HL,CHAN_D10
        CALL ascii_dec_to_bin
        POP HL
        POP BC
        JR L_2d40

L_2d3e:
        LD A,0x64

L_2d40:
        LD (HL),A
        INC HL
        LD A,0xff
        LD (HL),A
        DJNZ L_2cf6
        JP L_2b61

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
STR_TOP_MSG_1:
        db "TOP OF MSG  1",0x00,0x00,0x00
STR_TOP_MSG_2:
        db "TOP OF MSG  2",0x00,0x00,0x00
STR_TOP_MSG_3:
        db "TOP OF MSG  3",0x00,0x00,0x00
STR_TOP_MSG_4:
        db "TOP OF MSG  4",0x00,0x00,0x00
STR_TOP_MSG_5:
        db "TOP OF MSG  5",0x00,0x00,0x00
STR_TOP_MSG_6:
        db "TOP OF MSG  6",0x00,0x00,0x00
STR_TOP_MSG_7:
        db "TOP OF MSG  7",0x00,0x00,0x00
STR_TOP_MSG_8:
        db "TOP OF MSG  8",0x00,0x00,0x00
STR_TOP_MSG_9:
        db "TOP OF MSG  9",0x00,0x00,0x00
STR_TOP_MSG_10:
        db "TOP OF MSG 10",0x00,0x00,0x00
STR_TOP_DEMO:
        db "TOP DEMO MSG ",0x00,0x00,0x00
STR_BEEP:
        db 0x15,"BEEP",0x16,0x00
STR_RIGHT:
        db 0x15,"RIGHT",0x16,0x00
        db 0x00

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

; ---- MSG_TOP_TABLE: indexed by "TOP OF MSG n"; 0000 = no label
MSG_TOP_TABLE:
        dw STR_TOP_MSG_1           ; 00  TOP OF MSG  1
        dw STR_TOP_MSG_2           ; 01  TOP OF MSG  2
        dw STR_TOP_MSG_3           ; 02  TOP OF MSG  3
        dw STR_TOP_MSG_4           ; 03  TOP OF MSG  4
        dw STR_TOP_MSG_5           ; 04  TOP OF MSG  5
        dw STR_TOP_MSG_6           ; 05  TOP OF MSG  6
        dw STR_TOP_MSG_7           ; 06  TOP OF MSG  7
        dw STR_TOP_MSG_8           ; 07  TOP OF MSG  8
        dw STR_TOP_MSG_9           ; 08  TOP OF MSG  9
        dw STR_TOP_MSG_10          ; 09  TOP OF MSG 10
        dw STR_TOP_DEMO            ; 0a  TOP DEMO MSG
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
STR_C_BLACK:
        db 0x15,"BLACK",0x16,0x00
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
STR_SPEED_0:
        db 0x15,"S0",0x16,0x00
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
;      sub_04e5 (substitutes 0x3F for the character), bit 1 by the message
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


; ---- data 382d-386c: glyph-order character lists used by char_to_glyph (lower-case font)
CHARSET_LOWER:
        db "kf",0x12,"pa",0x0e,0x11,0x1e," ",0x7f,")%zwyt"
        db "ni",0x1f,"hd",0x09,0x1a,0x19,"0",0x1d,"2586k",0x00
        db "lgvmq",0x04,0x10,0x14,".",0x1c,"(*+9xs"
        db "ojbce",0x0d,0x07,0x15,0x08,0x0a,"1473ur"

; ---- data 386d-38ac:
CHARSET_UPPER:
        db "KF",0x12,"PA",0x0e,0x11,0x1e," ",0x7f,")%ZWYT"
        db "NI",0x1f,"HD",0x09,0x1a,0x19,"0",0x1d,"2586K",0x00
        db "LGVMQ",0x04,0x10,0x14,".",0x1c,"(*+9XS"
        db "OJBCE",0x0d,0x07,0x15,0x08,0x0a,"1473UR"

; ---- data 38ad-38ec:
CHARSET_UPPER2:
        db "KF",0x18,"PA",0x03,0x17,"_ ",0x7f,"&'ZWYT"
        db "NI",0xbd,"HD",0x02,0x1b,0x19,"0",0x1d,"2586K",0x00
        db "LGVMQ",0xbb,0x13,0x14,":",0xb6,"$#-9XS"
        db "OJBCE",0xb7,0x0f,0x16,0x0b,0x0c,"1473UR"

; ---- data 38ed-392c:
CHARSET_LOWER2:
        db "kf",0x18,"pa",0x03,0x17,"_ ",0x7f,"&'zwyt"
        db "ni",0xbd,"hd",0x02,0x1b,0x19,"0",0x1d,"2586k",0x00
        db "lgvmq",0xbb,0x13,0x14,":",0xb6,"$#-9xs"
        db "ojbce",0xb7,0x0f,0x16,0x0b,0x0c,"1473ur"

; ---- data 392d-396e: graphic / extended characters 0x94-0x9D, 0xC0-0xCF, 0xE0-0xEF
CHARSET_GRAPHICS:
        db 0xca,0xc5,0x12,0xcf,0xc0,0xde,0x11,0x1e,0x9e,0x7f,0x9d,0x96,0xed,0xe6,0xe8,0xe3
        db 0xcd,0xc8,0x1f,0xc7,0xc3,0xdc,0x1a,0x19,0x9b,0x1d,0x98,0xef,0xea,0x94,0xca,0x00
        db 0xcb,0xc6,0xe5,0xcc,0xe0,0xdd,0x10,0x14,0x9c,0x1c,0x9a,0x95,0xec,0xeb,0xe7,0xe2
        db 0xce,0xc9,0xc1,0xc2,0xc4,0xdf,0x07,0x15,0x08,0x0a,0x97,0xee,0xe9,0x99,0xe4,0xe1
        db 0xda,0xda

; ---- data 396f-3c20: built-in demonstration message (contains control codes 10,11,12,13,14,BC,BE,8x colours,A2-AB graphics)
DEMO_MESSAGE:
        db "THE ",0x12,0x14,"ULTIMATE ",0x11,0x8c,"INFRARED ",0xbc,"REMOTE CONTROL MULTI-"
        db "COLOR DISPLAY..... ",0x10,"** MAGIC ** ",0x11,"AUTOMATIC COLOR CHANGING....."
        db "PLUS.....",0xbc,0x14,"RAINBOW ",0x11,"PROGRAMMING IN ",0x10,"10 ",0x11,"VIBRANT"
        db " COLORS ",0x8c,"llllllllll ",0x83,"llllllllll ",0x8f,"llllllllll ",0x8d,"llllll"
        db "llll ",0x87,"llllllllll ",0xbc,">>>>> NETWORKABLE <<<<< INCLUDES PC FLOPPY DISK"
        db " & CABLE .....",0x12,"8K ",0x11,"MEMORY .....",0x83,0x12,"100 ",0x11,0xbc,"MEMORY"
        db " BANKS ..... ",0x10,"14 ",0x11,"CHARACTERS OR ",0xbe,"28 TINY CHARACTERS ",0xbc
        db "..... PROGRAMS ",0x10,"47 ",0x13,"EUROPEAN ",0x11,"CHARACTERS ..... ",0x12
        db "8 ",0x11,"SPEEDS ....UPPER & lower FONTS ..... ",0x10,"36 SPECIAL FUNCTIONS "
        db 0x11,".....INCLUDING...... CLOCK _",0x14,"  FLASH ",0x11,".....BEEP ",0x07,0x07
        db " ",0x07,"..... ",0x12,"BOLD ...... ",0x13,"ITALIC ",0x11,".....",0x14,"AND ...."
        db ". CUSTOM GRAPHICS ",0xa2,0xa3,0xa5,0xaa,0xab,"..... OR YOUR OWN LOGO..... "
        db 0xbe,"TINY PRICE          ",0x10,"LARGE  IMPACT!!",0x03,0xdb

; ---- TEST_MESSAGE: built-in test pattern (L_22b5). Sits inside the demo
;      text block but is a separate message with its own 0x03 terminator.
TEST_MESSAGE:
        db "CURRENT TEST  "
        db 0x10,0x17,0x17,0x17,0x17,0x17,0x17,0x17," ",0x03

        ds 0x8000-$,0xff        ; unused upper half of the 27C256
