; ============================================================================
;  Color Cells CC784NIR LED sign - firmware disassembly (EPROM M27C256B)
;  Reverse engineered from the ROM image; annotations by analysis, see notes.
;
;  MEMORY MAP
;    0000-3BFF  ROM (rest of the 32K device is 0xFF)
;    4000-5FFF  RAM (8K). 403F = initial SP (stack grows down from 403F)
;    8000       write-only control latch (CTRL_LATCH). bit4 = serial TX data
;               (1 = space/start bit, 0 = mark/idle), low nibble = display row
;               select / blanking (OR 0F blanks), high bits = keypad row select.
;  I/O PORTS
;    IN  C0     bit1 = IR receiver, bit3 = serial RX (1 = space/start bit)
;    OUT 48-4F  LED column data, one port per display row (OTIR of 0x56 bytes)
;    OUT 80     strobe/latch after a row write
;    OUT 40     used once in pkt_process_done (display reset?)
;  SERIAL: 300 baud bit-banged, 8N1 (rx), ~8N2 (tx), driven from the ~1300 Hz
;    timer interrupt (every 6th tick). See rx_bit_engine / tx_bit_engine.
;  PACKET: B1 addr flag len payload... cksum(sum of payload). See pkt_st_*.
;  REPLY : 06 ACK / 15 NAK; query replies via tx_send_frame.
;  MESSAGE STORE (43E2..): channel markers D0+n, 03 terminates a channel,
;    DA terminates the store. Attribute/colour bytes are stored inline.
; ============================================================================

; ---- RAM / memory-mapped symbols ----
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

        org 0x0000


; ----------------------------------------------------------------
; RESET
; cold start: set SP, run init routines, EI, jump to main loop
RESET:
0000  31 3f 40       LD SP,0x403f                     
0003  cd 53 05       CALL init_vars                   ; 0553
0006  cd 24 14       CALL ir_init                     ; 1424
0009  cd 6b 14       CALL ir_init2                    ; 146b
000c  cd 4d 05       CALL init_vars3                  ; 054d

L_000f:
000f  cd 98 06       CALL init_render                 ; 0698
0012  cd 73 04       CALL init_vars2                  ; 0473
0015  cd 16 03       CALL init_sequence               ; 0316
0018  fb             EI                               
0019  c3 9a 00       JP main_loop                     ; 009a

; ---------------- data: unused (001c-0037) unused
        db 0xff x 28

; ----------------------------------------------------------------
; INT_VECTOR
; IM1 interrupt entry (periodic timer, ~1300 Hz)
INT_VECTOR:
0038  c3 73 00       JP int_timer                     ; 0073

; ---------------- data: unused (003b-0047) unused
        db 0xff x 13

; ---------------- data: ROM_ID (0048-0057) 16-byte firmware ID, returned by query B4 '0'
ROM_ID:
        db "78409O1702930205"                                                  ; 0048

; ---------------- data: unused (0058-0065) unused
        db 0xff x 14

; ----------------------------------------------------------------
; NMI_VECTOR
; NMI = real-time clock tick (mains frequency); calls clock_tick
NMI_VECTOR:
0066  f5             PUSH AF                          
0067  c5             PUSH BC                          
0068  d5             PUSH DE                          
0069  e5             PUSH HL                          
006a  cd f4 18       CALL clock_tick                  ; 18f4
006d  e1             POP HL                           
006e  d1             POP DE                           
006f  c1             POP BC                           
0070  f1             POP AF                           
0071  ed 45          RETN                             

; ----------------------------------------------------------------
; int_timer
; Timer ISR. Every 6th tick schedules tick6_service; every tick schedules the handler in TICK_VECTOR
; (IR decoder). Both are invoked by pushing their address so they run as the ISR returns.
int_timer:
0073  08             EX AF,AF'                        
0074  d9             EXX                              
0075  3a 79 43       LD A,(TICK6_COUNT)               ; 4379
0078  3c             INC A                            
0079  fe 06          CP 6                             
007b  20 05          JR nz,L_0082                     ; 0082
007d  21 c4 00       LD HL,0xc4                       
0080  e5             PUSH HL                          
0081  af             XOR A                            

L_0082:
0082  32 79 43       LD (TICK6_COUNT),A               ; 4379
0085  3a 7a 43       LD A,(TICK1_COUNT)               ; 437a
0088  3c             INC A                            
0089  fe 01          CP 1                             
008b  20 05          JR nz,L_0092                     ; 0092
008d  2a 88 43       LD HL,(TICK_VECTOR)              ; 4388
0090  e5             PUSH HL                          
0091  af             XOR A                            

L_0092:
0092  32 7a 43       LD (TICK1_COUNT),A               ; 437a
0095  08             EX AF,AF'                        
0096  d9             EXX                              
0097  fb             EI                               
0098  ed 4d          RETI                             

; ----------------------------------------------------------------
; main_loop
; Main loop: if PKT_READY process packet, else init/render/effect step, then loop.
main_loop:
009a  3a f0 5e       LD A,(PKT_READY)                 ; 5ef0
009d  a7             AND A                            
009e  c2 68 2a       JP nz,pkt_process                ; 2a68
00a1  cd 98 06       CALL init_render                 ; 0698
00a4  cd 6d 03       CALL init_display_state          ; 036d

L_00a7:
00a7  cd 77 07       CALL render_next_char            ; 0777
00aa  cd 44 0e       CALL effect_step                 ; 0e44
00ad  3a 1a 42       LD A,(RENDER_DONE)               ; 421a
00b0  20 f5          JR nz,L_00a7                     ; 00a7
00b2  af             XOR A                            
00b3  32 1c 42       LD (COL_COUNT),A                 ; 421c
00b6  21 27 13       LD HL,fx_none                    ; 1327
00b9  32 3a 42       LD (PAUSE_FLAG),A                ; 423a
00bc  22 3b 42       LD (EFFECT_VECTOR),HL            ; 423b
00bf  18 e6          JR L_00a7                        ; 00a7
00c1  db 0xc3,0xa7,0x00

; ----------------------------------------------------------------
; tick6_service
; Runs every 6 timer ticks: serial RX/TX bit engines, countdowns, display column refresh & flashing,
; then the RX byte consumer.
tick6_service:
00c4  f5             PUSH AF                          
00c5  dd 7e 00       LD A,(IX)                        
00c8  fe aa          CP 0xaa                          
00ca  20 09          JR nz,L_00d5                     ; 00d5
00cc  fd 7e 00       LD A,(IY)                        
00cf  fe 55          CP 0x55                          
00d1  20 02          JR nz,L_00d5                     ; 00d5
00d3  f1             POP AF                           
00d4  c9             RET                              

L_00d5:
00d5  c5             PUSH BC                          
00d6  d5             PUSH DE                          
00d7  e5             PUSH HL                          
00d8  dd e5          PUSH IX                          
00da  fd e5          PUSH IY                          
00dc  2a 80 43       LD HL,(GEN_COUNTDOWN)            ; 4380
00df  2b             DEC HL                           
00e0  7c             LD A,H                           
00e1  a5             AND L                            
00e2  fe ff          CP 0xff                          
00e4  28 03          JR z,L_00e9                      ; 00e9
00e6  22 80 43       LD (GEN_COUNTDOWN),HL            ; 4380

L_00e9:
00e9  cd 09 16       CALL rx_bit_engine               ; 1609
00ec  cd 89 15       CALL tx_bit_engine               ; 1589
00ef  2a fe 41       LD HL,(TICK_COUNTDOWN)           ; 41fe
00f2  7c             LD A,H                           
00f3  b5             OR L                             
00f4  28 04          JR z,L_00fa                      ; 00fa
00f6  2b             DEC HL                           
00f7  22 fe 41       LD (TICK_COUNTDOWN),HL           ; 41fe

L_00fa:
00fa  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
00fd  a7             AND A                            
00fe  20 25          JR nz,L_0125                     ; 0125
0100  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0103  a7             AND A                            
0104  20 1f          JR nz,L_0125                     ; 0125
0106  3a 5f 43       LD A,(TINY_RENDER)               ; 435f
0109  a7             AND A                            
010a  c2 4b 12       JP nz,L_124b                     ; 124b
010d  3a ce 43       LD A,(BLANK_TIMER)               ; 43ce
0110  a7             AND A                            
0111  28 12          JR z,L_0125                      ; 0125
0113  3d             DEC A                            
0114  32 ce 43       LD (BLANK_TIMER),A               ; 43ce
0117  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
011a  f6 0f          OR 15                            
011c  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
011f  32 00 80       LD (CTRL_LATCH),A                ; 8000
0122  c3 0d 03       JP L_030d                        ; 030d

L_0125:
0125  3a 59 43       LD A,(DISP_ENABLE)               ; 4359
0128  a7             AND A                            
0129  ca ce 01       JP z,L_01ce                      ; 01ce
012c  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
012f  f6 0f          OR 15                            
0131  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
0134  32 00 80       LD (CTRL_LATCH),A                ; 8000
0137  3a 12 42       LD A,(EFFECT_ACTIVE)             ; 4212
013a  a7             AND A                            
013b  ca b9 01       JP z,L_01b9                      ; 01b9
013e  2a 10 42       LD HL,(SEQ_PTR_SAVE)             ; 4210
0141  3a 30 42       LD A,(DISP_FLAGS)                ; 4230
0144  47             LD B,A                           
0145  3a fd 41       LD A,(FLASH_TIMER)               ; 41fd
0148  4f             LD C,A                           
0149  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
014c  2f             CPL                              
014d  e6 07          AND 7                            
014f  3d             DEC A                            
0150  b1             OR C                             
0151  4f             LD C,A                           
0152  dd e5          PUSH IX                          
0154  dd 21 fe 41    LD IX,TICK_COUNTDOWN             ; 41fe
0158  dd 7e 00       LD A,(IX)                        
015b  dd b6 01       OR (IX+1)                        
015e  dd e1          POP IX                           
0160  28 02          JR z,L_0164                      ; 0164
0162  cb e9          SET 5,C                          

L_0164:
0164  3a 22 42       LD A,(ROW_DATA_LATCH)            ; 4222
0167  ed 79          OUT (C),A                        
0169  78             LD A,B                           
016a  a7             AND A                            
016b  28 15          JR z,L_0182                      ; 0182
016d  cb 40          BIT 0,B                          
016f  28 03          JR z,L_0174                      ; 0174
0171  05             DEC B                            
0172  28 0b          JR z,L_017f                      ; 017f

L_0174:
0174  ed b3          OTIR                             
0176  3a 30 42       LD A,(DISP_FLAGS)                ; 4230
0179  cb 47          BIT 0,A                          
017b  28 05          JR z,L_0182                      ; 0182
017d  06 01          LD B,1                           

L_017f:
017f  7e             LD A,(HL)                        
0180  ed 79          OUT (C),A                        

L_0182:
0182  3a 32 42       LD A,(FB_EXTRA_LEN)              ; 4232
0185  a7             AND A                            
0186  28 06          JR z,L_018e                      ; 018e
0188  47             LD B,A                           
0189  21 40 40       LD HL,FRAMEBUF                   ; 4040
018c  ed b3          OTIR                             

L_018e:
018e  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
0191  e6 70          AND 0x70                         
0193  f6 0f          OR 15                            
0195  32 00 80       LD (CTRL_LATCH),A                ; 8000
0198  d3 80          OUT (PORT_STROBE),A              
019a  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
019d  2f             CPL                              
019e  e6 07          AND 7                            
01a0  3d             DEC A                            
01a1  20 02          JR nz,L_01a5                     ; 01a5
01a3  3e 07          LD A,7                           

L_01a5:
01a5  4f             LD C,A                           
01a6  3a 1f 42       LD A,(0x421f)                    
01a9  b1             OR C                             
01aa  e6 8f          AND 0x8f                         
01ac  4f             LD C,A                           
01ad  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
01b0  e6 70          AND 0x70                         
01b2  b1             OR C                             
01b3  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
01b6  32 00 80       LD (CTRL_LATCH),A                ; 8000

L_01b9:
01b9  3a fd 41       LD A,(FLASH_TIMER)               ; 41fd
01bc  fe 48          CP 0x48                          
01be  28 07          JR z,L_01c7                      ; 01c7
01c0  3e 48          LD A,0x48                        
01c2  32 fd 41       LD (FLASH_TIMER),A               ; 41fd
01c5  18 04          JR L_01cb                        ; 01cb

L_01c7:
01c7  af             XOR A                            
01c8  32 59 43       LD (DISP_ENABLE),A               ; 4359

L_01cb:
01cb  c3 0d 03       JP L_030d                        ; 030d

L_01ce:
01ce  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
01d1  4f             LD C,A                           
01d2  3c             INC A                            
01d3  32 45 42       LD (ROW_INDEX),A                 ; 4245
01d6  fe 07          CP 7                             
01d8  da 03 03       JP c,L_0303                      ; 0303
01db  3e 00          LD A,0                           
01dd  32 45 42       LD (ROW_INDEX),A                 ; 4245
01e0  3a cd 43       LD A,(0x43cd)                    
01e3  32 ce 43       LD (BLANK_TIMER),A               ; 43ce
01e6  3a 44 42       LD A,(0x4244)                    
01e9  a7             AND A                            
01ea  28 07          JR z,L_01f3                      ; 01f3
01ec  3d             DEC A                            
01ed  32 44 42       LD (0x4244),A                    
01f0  c3 81 02       JP L_0281                        ; 0281

L_01f3:
01f3  3a 0d 42       LD A,(EFFECT_PHASE)              ; 420d
01f6  a7             AND A                            
01f7  28 31          JR z,L_022a                      ; 022a
01f9  2a 9b 41       LD HL,(FB_COL)                   ; 419b
01fc  11 56 00       LD DE,0x56                       
01ff  cd 2d 0e       CALL sub_0e2d                    ; 0e2d
0202  ed 5b 98 41    LD DE,(FB_COLPTR)                ; 4198
0206  b7             OR A                             
0207  ed 52          SBC HL,DE                        
0209  28 18          JR z,L_0223                      ; 0223
020b  2a 9b 41       LD HL,(FB_COL)                   ; 419b
020e  cd 16 0e       CALL sub_0e16                    ; 0e16
0211  22 9b 41       LD (FB_COL),HL                   ; 419b
0214  11 56 00       LD DE,0x56                       
0217  cd 2d 0e       CALL sub_0e2d                    ; 0e2d
021a  ed 5b 98 41    LD DE,(FB_COLPTR)                ; 4198
021e  b7             OR A                             
021f  ed 52          SBC HL,DE                        
0221  20 14          JR nz,L_0237                     ; 0237

L_0223:
0223  af             XOR A                            
0224  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
0227  c3 37 02       JP L_0237                        ; 0237

L_022a:
022a  2a 10 42       LD HL,(SEQ_PTR_SAVE)             ; 4210
022d  ed 5b 9b 41    LD DE,(FB_COL)                   ; 419b
0231  b7             OR A                             
0232  ed 52          SBC HL,DE                        
0234  ca 81 02       JP z,L_0281                      ; 0281

L_0237:
0237  2a 9b 41       LD HL,(FB_COL)                   ; 419b
023a  cb 7e          BIT 7,(HL)                       
023c  28 04          JR z,L_0242                      ; 0242
023e  7e             LD A,(HL)                        
023f  32 1b 42       LD (0x421b),A                    

L_0242:
0242  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0245  a7             AND A                            
0246  3a 1b 42       LD A,(0x421b)                    
0249  28 04          JR z,L_024f                      ; 024f
024b  e6 10          AND 0x10                         
024d  f6 8f          OR 0x8f                          

L_024f:
024f  32 22 42       LD (ROW_DATA_LATCH),A            ; 4222
0252  2a 9b 41       LD HL,(FB_COL)                   ; 419b
0255  22 10 42       LD (SEQ_PTR_SAVE),HL             ; 4210
0258  21 98 41       LD HL,FB_COLPTR                  ; 4198
025b  ed 4b 9b 41    LD BC,(FB_COL)                   ; 419b
025f  11 56 00       LD DE,0x56                       
0262  af             XOR A                            
0263  ed 42          SBC HL,BC                        
0265  af             XOR A                            
0266  22 30 42       LD (DISP_FLAGS),HL               ; 4230
0269  eb             EX DE,HL                         
026a  ed 52          SBC HL,DE                        
026c  ca 75 02       JP z,L_0275                      ; 0275
026f  da 75 02       JP c,L_0275                      ; 0275
0272  c3 7e 02       JP L_027e                        ; 027e

L_0275:
0275  21 56 00       LD HL,0x56                       
0278  22 30 42       LD (DISP_FLAGS),HL               ; 4230
027b  21 00 00       LD HL,0                          

L_027e:
027e  22 32 42       LD (FB_EXTRA_LEN),HL             ; 4232

L_0281:
0281  3a 1d 42       LD A,(0x421d)                    
0284  3c             INC A                            
0285  32 1d 42       LD (0x421d),A                    
0288  fe 0d          CP 13                            
028a  20 15          JR nz,L_02a1                     ; 02a1
028c  af             XOR A                            
028d  32 1d 42       LD (0x421d),A                    
0290  3a 1f 42       LD A,(0x421f)                    
0293  a7             AND A                            
0294  28 06          JR z,L_029c                      ; 029c
0296  af             XOR A                            
0297  32 1f 42       LD (0x421f),A                    
029a  18 05          JR L_02a1                        ; 02a1

L_029c:
029c  3e 80          LD A,0x80                        
029e  32 1f 42       LD (0x421f),A                    

L_02a1:
02a1  00             NOP                              

; ----------------------------------------------------------------
; rx_consume
; Pop a byte from RX_FIFO; in normal mode feed the packet parser (or if IR_CODE=A4/A5 handle keypad);
; packet start needs 0xB1 while idle
rx_consume:
02a2  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
02a5  a7             AND A                            
02a6  c2 f9 02       JP nz,tick6_exit                 ; 02f9
02a9  cd c5 16       CALL rx_fifo_get                 ; 16c5
02ac  d2 ca 02       JP nc,L_02ca                     ; 02ca
02af  3a 86 43       LD A,(IR_CODE)                   ; 4386
02b2  fe a4          CP 0xa4                          
02b4  ca c4 02       JP z,L_02c4                      ; 02c4
02b7  fe a5          CP 0xa5                          
02b9  c2 f9 02       JP nz,tick6_exit                 ; 02f9
02bc  3e 20          LD A,0x20                        
02be  32 28 42       LD (RX_BYTE),A                   ; 4228
02c1  c3 f9 02       JP tick6_exit                    ; 02f9

L_02c4:
02c4  32 84 43       LD (IR_KEY),A                    ; 4384
02c7  c3 03 1a       JP key_handler                   ; 1a03

L_02ca:
02ca  3a f1 5f       LD A,(PKT_STATE)                 ; 5ff1
02cd  a7             AND A                            
02ce  28 06          JR z,L_02d6                      ; 02d6
02d0  cd ef 16       CALL pkt_feed_byte               ; 16ef
02d3  c3 f9 02       JP tick6_exit                    ; 02f9

L_02d6:
02d6  3a 28 42       LD A,(RX_BYTE)                   ; 4228
02d9  fe b1          CP 0xb1                          
02db  20 14          JR nz,L_02f1                     ; 02f1
02dd  3a f0 5e       LD A,(PKT_READY)                 ; 5ef0
02e0  a7             AND A                            
02e1  20 16          JR nz,tick6_exit                 ; 02f9
02e3  3e ff          LD A,0xff                        
02e5  32 f1 5f       LD (PKT_STATE),A                 ; 5ff1
02e8  21 f6 16       LD HL,pkt_st_addr                ; 16f6
02eb  22 f5 5f       LD (PKT_VECTOR),HL               ; 5ff5
02ee  c3 f9 02       JP tick6_exit                    ; 02f9

L_02f1:
02f1  3a 28 42       LD A,(RX_BYTE)                   ; 4228
02f4  fe 01          CP 1                             
02f6  ca 03 1a       JP z,key_handler                 ; 1a03

; ----------------------------------------------------------------
; tick6_exit
tick6_exit:
02f9  3a 2a 42       LD A,(BEEP_TIMER)                ; 422a
02fc  a7             AND A                            
02fd  28 04          JR z,L_0303                      ; 0303
02ff  3d             DEC A                            
0300  32 2a 42       LD (BEEP_TIMER),A                ; 422a

L_0303:
0303  3e ff          LD A,0xff                        
0305  32 59 43       LD (DISP_ENABLE),A               ; 4359
0308  3e 40          LD A,0x40                        
030a  32 fd 41       LD (FLASH_TIMER),A               ; 41fd

L_030d:
030d  fd e1          POP IY                           
030f  dd e1          POP IX                           
0311  e1             POP HL                           
0312  d1             POP DE                           
0313  c1             POP BC                           
0314  f1             POP AF                           
0315  c9             RET                              

; ----------------------------------------------------------------
; init_sequence
; Init SEQ_LIST (0x68 bytes) etc.
init_sequence:
0316  af             XOR A                            
0317  32 d5 42       LD (SEQ_IDX),A                   ; 42d5
031a  06 68          LD B,0x68                        
031c  21 6b 42       LD HL,SEQ_LIST                   ; 426b
031f  7e             LD A,(HL)                        
0320  fe ff          CP 0xff                          
0322  28 12          JR z,L_0336                      ; 0336

L_0324:
0324  fe 65          CP 0x65                          
0326  30 0a          JR nc,L_0332                     ; 0332
0328  23             INC HL                           
0329  7e             LD A,(HL)                        
032a  10 f8          DJNZ L_0324                      ; 0324
032c  2b             DEC HL                           
032d  36 ff          LD (HL),0xff                     
032f  c3 4d 03       JP L_034d                        ; 034d

L_0332:
0332  fe ff          CP 0xff                          
0334  28 17          JR z,L_034d                      ; 034d

L_0336:
0336  21 6b 42       LD HL,SEQ_LIST                   ; 426b
0339  3e 00          LD A,0                           
033b  06 64          LD B,0x64                        

L_033d:
033d  77             LD (HL),A                        
033e  23             INC HL                           
033f  3c             INC A                            
0340  10 fb          DJNZ L_033d                      ; 033d
0342  36 ff          LD (HL),0xff                     
0344  23             INC HL                           
0345  36 ff          LD (HL),0xff                     
0347  23             INC HL                           
0348  36 ff          LD (HL),0xff                     
034a  23             INC HL                           
034b  36 ff          LD (HL),0xff                     

L_034d:
034d  21 6b 42       LD HL,SEQ_LIST                   ; 426b

L_0350:
0350  7e             LD A,(HL)                        
0351  23             INC HL                           
0352  e5             PUSH HL                          
0353  fe ff          CP 0xff                          
0355  28 0f          JR z,L_0366                      ; 0366
0357  cd 26 04       CALL chan_select                 ; 0426
035a  b7             OR A                             
035b  c2 3e 2a       JP nz,pkt_process_end            ; 2a3e
035e  7e             LD A,(HL)                        
035f  fe 03          CP 3                             
0361  e1             POP HL                           
0362  c0             RET nz                           
0363  c3 50 03       JP L_0350                        ; 0350

L_0366:
0366  e1             POP HL                           
0367  3e 0a          LD A,10                          
0369  32 d5 42       LD (SEQ_IDX),A                   ; 42d5
036c  c9             RET                              

; ----------------------------------------------------------------
; init_display_state
init_display_state:
036d  3a 0f 42       LD A,(0x420f)                    
0370  3c             INC A                            
0371  ca 10 04       JP z,L_0410                      ; 0410
0374  3a 5b 43       LD A,(MENU_FLAG)                 ; 435b
0377  fe 64          CP 0x64                          
0379  d2 86 03       JP nc,L_0386                     ; 0386
037c  5f             LD E,A                           
037d  3e ff          LD A,0xff                        
037f  32 5b 43       LD (MENU_FLAG),A                 ; 435b
0382  7b             LD A,E                           
0383  c3 ae 03       JP L_03ae                        ; 03ae

L_0386:
0386  3a d5 42       LD A,(SEQ_IDX)                   ; 42d5
0389  5f             LD E,A                           
038a  fe 0a          CP 10                            
038c  3e 64          LD A,0x64                        
038e  28 1e          JR z,L_03ae                      ; 03ae
0390  2a d3 42       LD HL,(SEQ_PTR)                  ; 42d3
0393  7e             LD A,(HL)                        
0394  fe ff          CP 0xff                          
0396  20 09          JR nz,L_03a1                     ; 03a1
0398  21 6b 42       LD HL,SEQ_LIST                   ; 426b
039b  22 d3 42       LD (SEQ_PTR),HL                  ; 42d3
039e  c3 6d 03       JP init_display_state            ; 036d

L_03a1:
03a1  fe 65          CP 0x65                          
03a3  38 04          JR c,L_03a9                      ; 03a9
03a5  3e 64          LD A,0x64                        
03a7  36 64          LD (HL),0x64                     

L_03a9:
03a9  5f             LD E,A                           
03aa  23             INC HL                           
03ab  22 d3 42       LD (SEQ_PTR),HL                  ; 42d3

L_03ae:
03ae  5f             LD E,A                           
03af  d5             PUSH DE                          
03b0  cd 26 04       CALL chan_select                 ; 0426
03b3  d1             POP DE                           
03b4  b7             OR A                             
03b5  c2 3e 2a       JP nz,pkt_process_end            ; 2a3e
03b8  7e             LD A,(HL)                        
03b9  fe 03          CP 3                             
03bb  28 3b          JR z,L_03f8                      ; 03f8
03bd  e5             PUSH HL                          
03be  06 00          LD B,0                           
03c0  4f             LD C,A                           
03c1  dd 21 2d 37    LD IX,0x372d                     
03c5  dd 09          ADD IX,BC                        
03c7  dd cb 00 4e    BIT 1,(IX)                       
03cb  28 19          JR z,L_03e6                      ; 03e6

L_03cd:
03cd  23             INC HL                           
03ce  7e             LD A,(HL)                        
03cf  fe 03          CP 3                             
03d1  20 04          JR nz,L_03d7                     ; 03d7
03d3  e1             POP HL                           
03d4  c3 f8 03       JP L_03f8                        ; 03f8

L_03d7:
03d7  06 00          LD B,0                           
03d9  4f             LD C,A                           
03da  dd 21 2d 37    LD IX,0x372d                     
03de  dd 09          ADD IX,BC                        
03e0  dd cb 00 4e    BIT 1,(IX)                       
03e4  20 e7          JR nz,L_03cd                     ; 03cd

L_03e6:
03e6  e1             POP HL                           
03e7  22 46 43       LD (STORE_CURSOR),HL             ; 4346
03ea  d5             PUSH DE                          
03eb  cd 1a 04       CALL chan_find                   ; 041a
03ee  d1             POP DE                           
03ef  7b             LD A,E                           
03f0  fe 64          CP 0x64                          
03f2  20 03          JR nz,L_03f7                     ; 03f7
03f4  32 6a 42       LD (CHAN_LOCK),A                 ; 426a

L_03f7:
03f7  c9             RET                              

L_03f8:
03f8  2a d3 42       LD HL,(SEQ_PTR)                  ; 42d3
03fb  7e             LD A,(HL)                        
03fc  fe ff          CP 0xff                          
03fe  c2 6d 03       JP nz,init_display_state         ; 036d
0401  2b             DEC HL                           
0402  11 6b 42       LD DE,SEQ_LIST                   ; 426b
0405  b7             OR A                             
0406  ed 52          SBC HL,DE                        
0408  c2 6d 03       JP nz,init_display_state         ; 036d
040b  3e 64          LD A,0x64                        
040d  c3 ae 03       JP L_03ae                        ; 03ae

L_0410:
0410  21 a5 43       LD HL,0x43a5                     
0413  22 46 43       LD (STORE_CURSOR),HL             ; 4346
0416  cd 1a 04       CALL chan_find                   ; 041a
0419  c9             RET                              

; ----------------------------------------------------------------
; chan_find
; Locate channel marker (D0+n) in MSG_STORE
chan_find:
041a  21 60 42       LD HL,0x4260                     
041d  06 0b          LD B,11                          
041f  3e 00          LD A,0                           

L_0421:
0421  77             LD (HL),A                        
0422  23             INC HL                           
0423  10 fc          DJNZ L_0421                      ; 0421
0425  c9             RET                              

; ----------------------------------------------------------------
; chan_select
; Select channel E: find/create its slot in MSG_STORE, set INS_PTR/STORE_CURSOR
chan_select:
0426  fe 64          CP 0x64                          
0428  20 06          JR nz,L_0430                     ; 0430
042a  21 6f 39       LD HL,DEMO_MESSAGE               ; 396f
042d  c3 6e 04       JP L_046e                        ; 046e

L_0430:
0430  11 d0 d0       LD DE,0xd0d0                     
0433  a7             AND A                            
0434  28 0f          JR z,L_0445                      ; 0445
0436  47             LD B,A                           
0437  3e da          LD A,0xda                        

L_0439:
0439  1c             INC E                            
043a  bb             CP E                             
043b  20 06          JR nz,L_0443                     ; 0443
043d  1e d0          LD E,0xd0                        
043f  14             INC D                            
0440  ba             CP D                             
0441  28 2d          JR z,L_0470                      ; 0470

L_0443:
0443  10 f4          DJNZ L_0439                      ; 0439

L_0445:
0445  dd 21 e2 43    LD IX,MSG_STORE                  ; 43e2
0449  ed 4b da 43    LD BC,(STORE_SIZE)               ; 43da

L_044d:
044d  dd 7e 00       LD A,(IX)                        
0450  fe da          CP 0xda                          
0452  28 1c          JR z,L_0470                      ; 0470
0454  67             LD H,A                           
0455  dd 6e 01       LD L,(IX+1)                      
0458  b7             OR A                             
0459  ed 52          SBC HL,DE                        
045b  28 0a          JR z,L_0467                      ; 0467
045d  dd 23          INC IX                           
045f  0b             DEC BC                           
0460  79             LD A,C                           
0461  b0             OR B                             
0462  20 e9          JR nz,L_044d                     ; 044d
0464  ca 70 04       JP z,L_0470                      ; 0470

L_0467:
0467  dd 23          INC IX                           
0469  dd 23          INC IX                           
046b  dd e5          PUSH IX                          
046d  e1             POP HL                           

L_046e:
046e  af             XOR A                            
046f  c9             RET                              

L_0470:
0470  3e ff          LD A,0xff                        
0472  c9             RET                              

; ----------------------------------------------------------------
; init_vars2
init_vars2:
0473  cd e5 04       CALL sub_04e5                    ; 04e5
0476  cd 0f 05       CALL sub_050f                    ; 050f
0479  21 e2 43       LD HL,MSG_STORE                  ; 43e2
047c  3e d0          LD A,0xd0                        
047e  16 d0          LD D,0xd0                        
0480  5f             LD E,A                           
0481  ed 4b dc 43    LD BC,(0x43dc)                   

L_0485:
0485  73             LD (HL),E                        
0486  23             INC HL                           
0487  72             LD (HL),D                        
0488  3e da          LD A,0xda                        
048a  14             INC D                            
048b  ba             CP D                             
048c  20 05          JR nz,L_0493                     ; 0493
048e  16 d0          LD D,0xd0                        
0490  1c             INC E                            
0491  18 07          JR L_049a                        ; 049a

L_0493:
0493  bb             CP E                             
0494  20 04          JR nz,L_049a                     ; 049a
0496  2b             DEC HL                           
0497  c3 dc 04       JP L_04dc                        ; 04dc

L_049a:
049a  2b             DEC HL                           
049b  2b             DEC HL                           
049c  36 20          LD (HL),0x20                     
049e  23             INC HL                           
049f  23             INC HL                           
04a0  23             INC HL                           
04a1  7e             LD A,(HL)                        
04a2  fe d0          CP 0xd0                          
04a4  da ae 04       JP c,L_04ae                      ; 04ae
04a7  fe db          CP 0xdb                          
04a9  d2 ae 04       JP nc,L_04ae                     ; 04ae
04ac  36 20          LD (HL),0x20                     

L_04ae:
04ae  23             INC HL                           

L_04af:
04af  7e             LD A,(HL)                        
04b0  fe d0          CP 0xd0                          
04b2  da bc 04       JP c,L_04bc                      ; 04bc
04b5  fe db          CP 0xdb                          
04b7  d2 bc 04       JP nc,L_04bc                     ; 04bc
04ba  18 c9          JR L_0485                        ; 0485

L_04bc:
04bc  23             INC HL                           
04bd  0b             DEC BC                           
04be  79             LD A,C                           
04bf  b0             OR B                             
04c0  28 03          JR z,L_04c5                      ; 04c5
04c2  c3 af 04       JP L_04af                        ; 04af

L_04c5:
04c5  3e da          LD A,0xda                        

L_04c7:
04c7  73             LD (HL),E                        
04c8  bb             CP E                             
04c9  28 11          JR z,L_04dc                      ; 04dc
04cb  23             INC HL                           
04cc  72             LD (HL),D                        
04cd  23             INC HL                           
04ce  36 03          LD (HL),3                        
04d0  23             INC HL                           
04d1  14             INC D                            
04d2  ba             CP D                             
04d3  20 f2          JR nz,L_04c7                     ; 04c7
04d5  16 d0          LD D,0xd0                        
04d7  1c             INC E                            
04d8  bb             CP E                             
04d9  20 ec          JR nz,L_04c7                     ; 04c7
04db  77             LD (HL),A                        

L_04dc:
04dc  e5             PUSH HL                          
04dd  cd 24 05       CALL sub_0524                    ; 0524
04e0  e1             POP HL                           
04e1  3e da          LD A,0xda                        
04e3  77             LD (HL),A                        
04e4  c9             RET                              

sub_04e5:
04e5  21 e2 43       LD HL,MSG_STORE                  ; 43e2
04e8  ed 4b da 43    LD BC,(STORE_SIZE)               ; 43da
04ec  fd 21 63 43    LD IY,0x4363                     
04f0  fd 36 00 00    LD (IY),0                        
04f4  16 00          LD D,0                           

L_04f6:
04f6  5e             LD E,(HL)                        
04f7  dd 21 2d 37    LD IX,0x372d                     
04fb  dd 19          ADD IX,DE                        
04fd  dd cb 00 46    BIT 0,(IX)                       
0501  28 05          JR z,L_0508                      ; 0508
0503  36 3f          LD (HL),0x3f                     
0505  fd 34 00       INC (IY)                         

L_0508:
0508  23             INC HL                           
0509  0b             DEC BC                           
050a  79             LD A,C                           
050b  b0             OR B                             
050c  20 e8          JR nz,L_04f6                     ; 04f6
050e  c9             RET                              

sub_050f:
050f  21 e2 43       LD HL,MSG_STORE                  ; 43e2
0512  ed 4b da 43    LD BC,(STORE_SIZE)               ; 43da

L_0516:
0516  7e             LD A,(HL)                        
0517  fe 03          CP 3                             
0519  20 02          JR nz,L_051d                     ; 051d
051b  36 20          LD (HL),0x20                     

L_051d:
051d  23             INC HL                           
051e  0b             DEC BC                           
051f  79             LD A,C                           
0520  b0             OR B                             
0521  20 f3          JR nz,L_0516                     ; 0516
0523  c9             RET                              

sub_0524:
0524  dd 21 e4 43    LD IX,0x43e4                     
0528  ed 4b da 43    LD BC,(STORE_SIZE)               ; 43da
052c  0b             DEC BC                           
052d  0b             DEC BC                           

L_052e:
052e  dd 7e 00       LD A,(IX)                        
0531  fe d0          CP 0xd0                          
0533  da 45 05       JP c,L_0545                      ; 0545
0536  fe db          CP 0xdb                          
0538  d2 45 05       JP nc,L_0545                     ; 0545
053b  dd 36 ff 03    LD (IX-1),3                      
053f  dd 23          INC IX                           
0541  0b             DEC BC                           
0542  79             LD A,C                           
0543  b0             OR B                             
0544  c8             RET z                            

L_0545:
0545  dd 23          INC IX                           
0547  0b             DEC BC                           
0548  79             LD A,C                           
0549  b0             OR B                             
054a  20 e2          JR nz,L_052e                     ; 052e
054c  c9             RET                              

; ----------------------------------------------------------------
; init_vars3
; NMI_PER_SEC = 60 -> NMI is a 60 Hz (mains) tick
init_vars3:
054d  3e 3c          LD A,0x3c                        
054f  32 5d 43       LD (NMI_PER_SEC),A               ; 435d
0552  c9             RET                              

; ----------------------------------------------------------------
; init_vars
; Power-on RAM init: copies data blocks from ROM (0x0601..), validates MY_ADDRESS/MY_ADDRESS_INV
; (resets to 0 if corrupt)
init_vars:
0553  af             XOR A                            
0554  32 5f 43       LD (TINY_RENDER),A               ; 435f
0557  32 5e 43       LD (ROW_PHASE),A                 ; 435e
055a  21 c5 43       LD HL,MENU_ENTRY_BUF             ; 43c5
055d  06 05          LD B,5                           

L_055f:
055f  77             LD (HL),A                        
0560  23             INC HL                           
0561  10 fc          DJNZ L_055f                      ; 055f
0563  32 9b 43       LD (0x439b),A                    
0566  32 60 43       LD (0x4360),A                    
0569  32 64 43       LD (0x4364),A                    
056c  32 13 42       LD (0x4213),A                    
056f  32 61 43       LD (0x4361),A                    
0572  32 a2 43       LD (0x43a2),A                    
0575  32 97 43       LD (MENU_TMP2),A                 ; 4397
0578  32 94 43       LD (MENU_TMP),A                  ; 4394
057b  32 a4 43       LD (0x43a4),A                    
057e  32 9a 43       LD (0x439a),A                    
0581  32 99 43       LD (0x4399),A                    
0584  32 95 43       LD (0x4395),A                    
0587  32 91 43       LD (0x4391),A                    
058a  32 a3 43       LD (0x43a3),A                    
058d  32 d6 43       LD (0x43d6),A                    
0590  32 d7 43       LD (0x43d7),A                    
0593  32 cf 43       LD (0x43cf),A                    
0596  32 ca 43       LD (0x43ca),A                    
0599  32 cd 43       LD (0x43cd),A                    
059c  32 ce 43       LD (BLANK_TIMER),A               ; 43ce
059f  32 79 43       LD (TICK6_COUNT),A               ; 4379
05a2  3e ff          LD A,0xff                        
05a4  32 5b 43       LD (MENU_FLAG),A                 ; 435b
05a7  3e 20          LD A,0x20                        
05a9  32 93 43       LD (MENU_CHAR),A                 ; 4393
05ac  3a 3c 43       LD A,(NMI_COUNT)                 ; 433c
05af  32 96 43       LD (RND_SEED),A                  ; 4396
05b2  e6 03          AND 3                            
05b4  c6 03          ADD A,3                          
05b6  32 98 43       LD (RND_VAL),A                   ; 4398
05b9  3a cb 43       LD A,(MY_ADDRESS)                ; 43cb
05bc  4f             LD C,A                           
05bd  3a cc 43       LD A,(MY_ADDRESS_INV)            ; 43cc
05c0  2f             CPL                              
05c1  b9             CP C                             
05c2  28 08          JR z,L_05cc                      ; 05cc
05c4  3e 00          LD A,0                           
05c6  32 cb 43       LD (MY_ADDRESS),A                ; 43cb
05c9  32 cc 43       LD (MY_ADDRESS_INV),A            ; 43cc

L_05cc:
05cc  21 01 06       LD HL,INIT_DATA                  ; 0601
05cf  01 0a 00       LD BC,10                         
05d2  11 98 41       LD DE,FB_COLPTR                  ; 4198
05d5  ed b0          LDIR                             
05d7  21 0b 06       LD HL,0x060b                     
05da  11 f8 41       LD DE,EFFECT_TMP                 ; 41f8
05dd  01 08 00       LD BC,8                          
05e0  ed b0          LDIR                             
05e2  21 19 06       LD HL,0x0619                     
05e5  11 06 42       LD DE,CLK_RUN                    ; 4206
05e8  01 5a 00       LD BC,0x5a                       
05eb  ed b0          LDIR                             
05ed  21 74 06       LD HL,0x0674                     
05f0  11 36 43       LD DE,0x4336                     
05f3  01 24 00       LD BC,0x24                       
05f6  ed b0          LDIR                             
05f8  ed 56          IM 1                             
05fa  21 6b 42       LD HL,SEQ_LIST                   ; 426b
05fd  22 d3 42       LD (SEQ_PTR),HL                  ; 42d3
0600  c9             RET                              

; ---------------- data: INIT_DATA (0601-0697) RAM initialisation blocks copied by init_vars
INIT_DATA:
        db 0x96,0x40,0x56,0x40,0x40,0x95,0x40,0x01,0x01,0x00,0xa2,0x41,0x56,0x00,0x00,0x00 ; 0601
        db 0x00,0x00,0x01,0x02,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x0f,0x00 ; 0611
        db 0x00,0x00,0x40,0x40,0x01,0x05,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x0f,0x00 ; 0621
        db 0x00,0x0a,0x00,0x00,0x00,0x0f,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 0631
        db 0x00,0x00,0x00,0x56,0x00,0x00,0x00,0xff,0x5f,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 0641
        db 0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 0651
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x4a,0x16,0x4a,0x16,0x00,0x00,0x2b ; 0661
        db 0x16,0x2b,0x16,0x00,0x00,0x00,0x00,0x00,0x00,0xb0,0x04,0x00,0x00,0x00,0x00,0x00 ; 0671
        db 0x00,0x00,0x00,0xe2,0x43,0x00,0x01,0x00,0x00,0x00,0x00,0x54,0x16,0x00,0x01,0x00 ; 0681
        db 0x00,0x00,0x00,0x54,0x16,0xff,0xff                                  ; 0691

; ----------------------------------------------------------------
; init_render
; Reset render state for the current message
init_render:
0698  cd 99 19       CALL clear_framebuf              ; 1999
069b  af             XOR A                            
069c  32 9b 43       LD (0x439b),A                    
069f  32 60 43       LD (0x4360),A                    
06a2  32 5f 43       LD (TINY_RENDER),A               ; 435f
06a5  32 5e 43       LD (ROW_PHASE),A                 ; 435e
06a8  3e ff          LD A,0xff                        
06aa  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
06ad  21 40 40       LD HL,FRAMEBUF                   ; 4040
06b0  22 10 42       LD (SEQ_PTR_SAVE),HL             ; 4210
06b3  22 9b 41       LD (FB_COL),HL                   ; 419b
06b6  21 00 00       LD HL,0                          
06b9  22 32 42       LD (FB_EXTRA_LEN),HL             ; 4232
06bc  21 56 00       LD HL,0x56                       
06bf  22 30 42       LD (DISP_FLAGS),HL               ; 4230
06c2  3e 01          LD A,1                           
06c4  32 8c 43       LD (0x438c),A                    
06c7  af             XOR A                            
06c8  32 1a 42       LD (RENDER_DONE),A               ; 421a
06cb  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
06ce  32 13 42       LD (0x4213),A                    
06d1  32 1a 42       LD (RENDER_DONE),A               ; 421a
06d4  32 1e 42       LD (0x421e),A                    
06d7  32 94 43       LD (MENU_TMP),A                  ; 4394
06da  32 9a 43       LD (0x439a),A                    
06dd  32 97 43       LD (MENU_TMP2),A                 ; 4397
06e0  32 98 43       LD (RND_VAL),A                   ; 4398
06e3  32 3a 42       LD (PAUSE_FLAG),A                ; 423a
06e6  32 44 42       LD (0x4244),A                    
06e9  32 a2 43       LD (0x43a2),A                    
06ec  32 a3 43       LD (0x43a3),A                    
06ef  32 a4 43       LD (0x43a4),A                    
06f2  32 cd 43       LD (0x43cd),A                    
06f5  32 3b 43       LD (0x433b),A                    
06f8  32 3a 43       LD (TINY_MODE),A                 ; 433a
06fb  32 39 43       LD (FONT_MODE),A                 ; 4339
06fe  32 d6 43       LD (0x43d6),A                    
0701  3e 8f          LD A,0x8f                        
0703  32 1b 42       LD (0x421b),A                    
0706  32 22 42       LD (ROW_DATA_LATCH),A            ; 4222
0709  32 0c 42       LD (CUR_COLOUR),A                ; 420c
070c  21 27 13       LD HL,fx_none                    ; 1327
070f  22 3b 42       LD (EFFECT_VECTOR),HL            ; 423b
0712  21 96 40       LD HL,FRAMEBUF_ROW1              ; 4096
0715  22 98 41       LD (FB_COLPTR),HL                ; 4198
0718  21 a2 41       LD HL,TXBUF                      ; 41a2
071b  22 f8 41       LD (EFFECT_TMP),HL               ; 41f8
071e  cd ac 19       CALL clear_txbuf                 ; 19ac
0721  cd bb 19       CALL clear_glyph_tmp             ; 19bb
0724  2a d8 43       LD HL,(STORE_LIMIT)              ; 43d8
0727  36 da          LD (HL),0xda                     
0729  c9             RET                              

sub_072a:
072a  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
072d  fe 20          CP 0x20                          
072f  28 26          JR z,L_0757                      ; 0757
0731  af             XOR A                            
0732  32 38 43       LD (0x4338),A                    
0735  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0738  16 00          LD D,0                           
073a  5f             LD E,A                           
073b  21 2d 37       LD HL,0x372d                     
073e  19             ADD HL,DE                        
073f  cb 4e          BIT 1,(HL)                       
0741  20 33          JR nz,L_0776                     ; 0776
0743  3e ff          LD A,0xff                        
0745  32 a3 43       LD (0x43a3),A                    
0748  3a a2 43       LD A,(0x43a2)                    
074b  a7             AND A                            
074c  28 28          JR z,L_0776                      ; 0776
074e  32 1e 42       LD (0x421e),A                    
0751  af             XOR A                            
0752  32 a2 43       LD (0x43a2),A                    
0755  18 1f          JR L_0776                        ; 0776

L_0757:
0757  af             XOR A                            
0758  32 1e 42       LD (0x421e),A                    
075b  3a 38 43       LD A,(0x4338)                    
075e  a7             AND A                            
075f  20 07          JR nz,L_0768                     ; 0768
0761  3e 01          LD A,1                           
0763  32 38 43       LD (0x4338),A                    
0766  18 0e          JR L_0776                        ; 0776

L_0768:
0768  3a 0f 42       LD A,(0x420f)                    
076b  3c             INC A                            
076c  28 08          JR z,L_0776                      ; 0776
076e  3a 0c 42       LD A,(CUR_COLOUR)                ; 420c
0771  e6 0f          AND 15                           
0773  32 0c 42       LD (CUR_COLOUR),A                ; 420c

L_0776:
0776  c9             RET                              

; ----------------------------------------------------------------
; render_next_char
; Fetch next byte from the message store at STORE_CURSOR and act on it: attribute bytes are
; dispatched, printable bytes are drawn via glyph_lookup
render_next_char:
0777  cd 68 09       CALL sub_0968                    ; 0968

sub_077a:
077a  cd 2a 07       CALL sub_072a                    ; 072a
077d  cd 14 0b       CALL sub_0b14                    ; 0b14
0780  cd 96 09       CALL sub_0996                    ; 0996
0783  cd 60 0a       CALL sub_0a60                    ; 0a60
0786  cd 53 0a       CALL sub_0a53                    ; 0a53
0789  cd 17 0a       CALL sub_0a17                    ; 0a17
078c  cd fe 09       CALL sub_09fe                    ; 09fe
078f  cd 8c 09       CALL sub_098c                    ; 098c
0792  fe be          CP 0xbe                          
0794  ca 1a 11       JP z,attr_tiny                   ; 111a
0797  e6 f0          AND 0xf0                         
0799  fe a0          CP 0xa0                          
079b  20 0a          JR nz,L_07a7                     ; 07a7
079d  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
07a0  e6 0f          AND 15                           
07a2  32 0e 42       LD (CUR_CHAR),A                  ; 420e
07a5  18 36          JR glyph_lookup                  ; 07dd

L_07a7:
07a7  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
07aa  fe 17          CP 0x17                          
07ac  28 2f          JR z,glyph_lookup                ; 07dd
07ae  cb 7f          BIT 7,A                          
07b0  c2 c5 07       JP nz,L_07c5                     ; 07c5
07b3  e6 60          AND 0x60                         
07b5  ca a8 0e       JP z,L_0ea8                      ; 0ea8
07b8  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
07bb  fe 5f          CP 0x5f                          
07bd  ca 90 1d       JP z,L_1d90                      ; 1d90
07c0  cb 7f          BIT 7,A                          
07c2  ca dd 07       JP z,glyph_lookup                ; 07dd

L_07c5:
07c5  fe 94          CP 0x94                          
07c7  da 91 10       JP c,attr_colour_speed           ; 1091
07ca  fe a0          CP 0xa0                          
07cc  38 0f          JR c,glyph_lookup                ; 07dd
07ce  e6 f0          AND 0xf0                         
07d0  fe c0          CP 0xc0                          
07d2  28 09          JR z,glyph_lookup                ; 07dd
07d4  fe e0          CP 0xe0                          
07d6  28 05          JR z,glyph_lookup                ; 07dd
07d8  fe d0          CP 0xd0                          
07da  c2 91 10       JP nz,attr_colour_speed          ; 1091

; ----------------------------------------------------------------
; glyph_lookup
; HL = FONT + 8*glyph_index(CUR_CHAR); GLYPH_WIDTH = byte 7 of the glyph
glyph_lookup:
07dd  21 35 31       LD HL,FONT                       ; 3135
07e0  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
07e3  cd 42 09       CALL char_to_glyph               ; 0942
07e6  5f             LD E,A                           
07e7  16 00          LD D,0                           
07e9  cb 23          SLA E                            
07eb  cb 12          RL D                             
07ed  cb 23          SLA E                            
07ef  cb 12          RL D                             
07f1  cb 23          SLA E                            
07f3  cb 12          RL D                             
07f5  19             ADD HL,DE                        
07f6  22 08 42       LD (GLYPH_PTR),HL                ; 4208
07f9  22 d0 43       LD (GLYPH_PTR2),HL               ; 43d0
07fc  11 07 00       LD DE,7                          
07ff  19             ADD HL,DE                        
0800  7e             LD A,(HL)                        
0801  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
0804  cd bb 19       CALL clear_glyph_tmp             ; 19bb
0807  3a 3a 43       LD A,(TINY_MODE)                 ; 433a
080a  a7             AND A                            
080b  20 4f          JR nz,L_085c                     ; 085c
080d  cd fd 0c       CALL draw_glyph                  ; 0cfd
0810  cd e3 0d       CALL sub_0de3                    ; 0de3
0813  cd 97 0d       CALL sub_0d97                    ; 0d97
0816  3a 13 42       LD A,(0x4213)                    
0819  fe ff          CP 0xff                          
081b  20 09          JR nz,L_0826                     ; 0826
081d  af             XOR A                            
081e  32 13 42       LD (0x4213),A                    
0821  3e ff          LD A,0xff                        
0823  32 61 43       LD (0x4361),A                    

L_0826:
0826  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0829  e6 f0          AND 0xf0                         
082b  20 2f          JR nz,L_085c                     ; 085c
082d  2a 08 42       LD HL,(GLYPH_PTR)                ; 4208
0830  ed 5b d0 43    LD DE,(GLYPH_PTR2)               ; 43d0
0834  b7             OR A                             
0835  ed 52          SBC HL,DE                        
0837  20 14          JR nz,L_084d                     ; 084d
0839  2a 08 42       LD HL,(GLYPH_PTR)                ; 4208
083c  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
083f  4f             LD C,A                           
0840  06 00          LD B,0                           
0842  11 d6 42       LD DE,0x42d6                     
0845  ed b0          LDIR                             
0847  21 d6 42       LD HL,0x42d6                     
084a  22 08 42       LD (GLYPH_PTR),HL                ; 4208

L_084d:
084d  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0850  cb 27          SLA A                            
0852  fe 20          CP 0x20                          
0854  da 59 08       JP c,L_0859                      ; 0859
0857  3e 1f          LD A,0x1f                        

L_0859:
0859  32 07 42       LD (GLYPH_WIDTH),A               ; 4207

L_085c:
085c  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
085f  a7             AND A                            
0860  20 07          JR nz,L_0869                     ; 0869
0862  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0865  a7             AND A                            
0866  c2 fc 08       JP nz,L_08fc                     ; 08fc

L_0869:
0869  3e 00          LD A,0                           
086b  32 8c 43       LD (0x438c),A                    

sub_086e:
086e  3a 1a 42       LD A,(RENDER_DONE)               ; 421a
0871  a7             AND A                            
0872  28 13          JR z,L_0887                      ; 0887
0874  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0877  fe 20          CP 0x20                          
0879  20 0c          JR nz,L_0887                     ; 0887
087b  11 f0 08       LD DE,TBL_08F0                   ; 08f0
087e  ed 53 08 42    LD (GLYPH_PTR),DE                ; 4208
0882  3e 09          LD A,9                           
0884  32 07 42       LD (GLYPH_WIDTH),A               ; 4207

L_0887:
0887  ed 5b 08 42    LD DE,(GLYPH_PTR)                ; 4208
088b  2a 98 41       LD HL,(FB_COLPTR)                ; 4198
088e  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0891  47             LD B,A                           
0892  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
0895  a7             AND A                            
0896  28 0d          JR z,L_08a5                      ; 08a5
0898  3e 0f          LD A,15                          
089a  32 0c 42       LD (CUR_COLOUR),A                ; 420c
089d  3a 3a 43       LD A,(TINY_MODE)                 ; 433a
08a0  a7             AND A                            
08a1  0e 00          LD C,0                           
08a3  20 12          JR nz,L_08b7                     ; 08b7

L_08a5:
08a5  3a 91 43       LD A,(0x4391)                    
08a8  a7             AND A                            
08a9  28 08          JR z,L_08b3                      ; 08b3
08ab  af             XOR A                            
08ac  32 91 43       LD (0x4391),A                    
08af  3e 10          LD A,0x10                        
08b1  18 03          JR L_08b6                        ; 08b6

L_08b3:
08b3  3a 1e 42       LD A,(0x421e)                    

L_08b6:
08b6  4f             LD C,A                           

L_08b7:
08b7  c5             PUSH BC                          
08b8  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
08bb  fe 20          CP 0x20                          
08bd  0e f0          LD C,0xf0                        
08bf  28 02          JR z,L_08c3                      ; 08c3
08c1  0e ff          LD C,0xff                        

L_08c3:
08c3  3a 0c 42       LD A,(CUR_COLOUR)                ; 420c
08c6  a1             AND C                            
08c7  c1             POP BC                           
08c8  b1             OR C                             
08c9  cb ff          SET 7,A                          
08cb  77             LD (HL),A                        
08cc  3a 9b 43       LD A,(0x439b)                    
08cf  a7             AND A                            
08d0  cc 16 0e       CALL z,sub_0e16                  ; 0e16
08d3  af             XOR A                            
08d4  32 9b 43       LD (0x439b),A                    

L_08d7:
08d7  1a             LD A,(DE)                        
08d8  77             LD (HL),A                        
08d9  13             INC DE                           
08da  cd 16 0e       CALL sub_0e16                    ; 0e16
08dd  10 f8          DJNZ L_08d7                      ; 08d7
08df  22 98 41       LD (FB_COLPTR),HL                ; 4198
08e2  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
08e5  a7             AND A                            
08e6  3e 00          LD A,0                           
08e8  20 02          JR nz,L_08ec                     ; 08ec
08ea  3e ff          LD A,0xff                        

L_08ec:
08ec  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
08ef  c9             RET                              

; ---------------- data: TBL_08F0 (08f0-08fb) 
TBL_08F0:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00         ; 08f0

L_08fc:
08fc  2a f8 41       LD HL,(EFFECT_TMP)               ; 41f8
08ff  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0902  16 00          LD D,0                           
0904  5f             LD E,A                           
0905  19             ADD HL,DE                        
0906  11 f8 41       LD DE,EFFECT_TMP                 ; 41f8
0909  af             XOR A                            
090a  ed 52          SBC HL,DE                        
090c  d2 fc 0e       JP nc,L_0efc                     ; 0efc
090f  ed 5b f8 41    LD DE,(EFFECT_TMP)               ; 41f8
0913  3a 1e 42       LD A,(0x421e)                    
0916  f6 8f          OR 0x8f                          
0918  12             LD (DE),A                        
0919  3a 9b 43       LD A,(0x439b)                    
091c  a7             AND A                            
091d  3e 00          LD A,0                           
091f  32 9b 43       LD (0x439b),A                    
0922  20 01          JR nz,L_0925                     ; 0925
0924  13             INC DE                           

L_0925:
0925  2a 08 42       LD HL,(GLYPH_PTR)                ; 4208
0928  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
092b  06 00          LD B,0                           
092d  4f             LD C,A                           
092e  ed b0          LDIR                             
0930  ed 53 f8 41    LD (EFFECT_TMP),DE               ; 41f8
0934  c3 77 07       JP render_next_char              ; 0777

L_0937:
0937  cb 3c          SRL H                            
0939  cb 1d          RR L                             
093b  22 fb 41       LD (EFFECT_TMP2),HL              ; 41fb
093e  cd ea 0c       CALL sub_0cea                    ; 0cea
0941  c9             RET                              

; ----------------------------------------------------------------
; char_to_glyph
; Map a character code to a font glyph index (tables at 0x382d..0x392d select upper/lower/tiny fonts)
char_to_glyph:
0942  f5             PUSH AF                          
0943  e6 f0          AND 0xf0                         
0945  fe c0          CP 0xc0                          
0947  11 35 35       LD DE,0x3535                     
094a  28 17          JR z,L_0963                      ; 0963
094c  fe d0          CP 0xd0                          
094e  11 ad 36       LD DE,0x36ad                     
0951  28 10          JR z,L_0963                      ; 0963
0953  fe e0          CP 0xe0                          
0955  11 b5 35       LD DE,0x35b5                     
0958  28 09          JR z,L_0963                      ; 0963
095a  fe 90          CP 0x90                          
095c  11 35 36       LD DE,0x3635                     
095f  28 02          JR z,L_0963                      ; 0963
0961  f1             POP AF                           
0962  c9             RET                              

L_0963:
0963  f1             POP AF                           
0964  e6 0f          AND 15                           
0966  eb             EX DE,HL                         
0967  c9             RET                              

sub_0968:
0968  e5             PUSH HL                          
0969  f5             PUSH AF                          
096a  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
096d  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0970  a7             AND A                            
0971  28 0a          JR z,L_097d                      ; 097d
0973  3a 61 43       LD A,(0x4361)                    
0976  a7             AND A                            
0977  28 04          JR z,L_097d                      ; 097d
0979  3e 18          LD A,0x18                        
097b  18 01          JR L_097e                        ; 097e

L_097d:
097d  7e             LD A,(HL)                        

L_097e:
097e  23             INC HL                           
097f  22 46 43       LD (STORE_CURSOR),HL             ; 4346
0982  32 0e 42       LD (CUR_CHAR),A                  ; 420e
0985  af             XOR A                            
0986  32 61 43       LD (0x4361),A                    
0989  f1             POP AF                           
098a  e1             POP HL                           
098b  c9             RET                              

sub_098c:
098c  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
098f  fe bb          CP 0xbb                          
0991  c0             RET nz                           
0992  e1             POP HL                           
0993  c3 f1 0e       JP L_0ef1                        ; 0ef1

sub_0996:
0996  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0999  fe bc          CP 0xbc                          
099b  20 18          JR nz,L_09b5                     ; 09b5
099d  3a 1a 42       LD A,(RENDER_DONE)               ; 421a
09a0  a7             AND A                            
09a1  28 06          JR z,L_09a9                      ; 09a9
09a3  3a f7 09       LD A,(0x09f7)                    
09a6  32 0c 42       LD (CUR_COLOUR),A                ; 420c

L_09a9:
09a9  3e 01          LD A,1                           
09ab  32 a4 43       LD (0x43a4),A                    
09ae  32 94 43       LD (MENU_TMP),A                  ; 4394
09b1  e1             POP HL                           
09b2  c3 77 07       JP render_next_char              ; 0777

L_09b5:
09b5  3a a4 43       LD A,(0x43a4)                    
09b8  a7             AND A                            
09b9  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
09bc  c8             RET z                            
09bd  fe 20          CP 0x20                          
09bf  c8             RET z                            
09c0  16 00          LD D,0                           
09c2  5f             LD E,A                           
09c3  dd 21 2d 37    LD IX,0x372d                     
09c7  dd 19          ADD IX,DE                        
09c9  dd cb 00 4e    BIT 1,(IX)                       
09cd  c0             RET nz                           
09ce  3a a4 43       LD A,(0x43a4)                    
09d1  3c             INC A                            
09d2  e6 07          AND 7                            
09d4  20 02          JR nz,L_09d8                     ; 09d8
09d6  3e 01          LD A,1                           

L_09d8:
09d8  5f             LD E,A                           
09d9  16 00          LD D,0                           
09db  21 f6 09       LD HL,TBL_09F6                   ; 09f6
09de  19             ADD HL,DE                        
09df  7e             LD A,(HL)                        
09e0  fe ff          CP 0xff                          
09e2  20 05          JR nz,L_09e9                     ; 09e9
09e4  1e 01          LD E,1                           
09e6  3a f7 09       LD A,(0x09f7)                    

L_09e9:
09e9  e6 0f          AND 15                           
09eb  32 0c 42       LD (CUR_COLOUR),A                ; 420c
09ee  7b             LD A,E                           
09ef  32 a4 43       LD (0x43a4),A                    
09f2  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
09f5  c9             RET                              

; ---------------- data: TBL_09F6 (09f6-09fd) 
TBL_09F6:
        db 0x00,0x8c,0x8d,0x8f,0x87,0x83,0xff,0xff                             ; 09f6

sub_09fe:
09fe  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0a01  fe b0          CP 0xb0                          
0a03  c0             RET nz                           

L_0a04:
0a04  cd 68 09       CALL sub_0968                    ; 0968
0a07  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e

; ----------------------------------------------------------------
; attr_remark
; 0xB0: skip text until the next 0xB0 (hidden remark)
attr_remark:
0a0a  fe b0          CP 0xb0                          
0a0c  28 05          JR z,L_0a13                      ; 0a13
0a0e  fe 03          CP 3                             
0a10  c8             RET z                            
0a11  18 f1          JR L_0a04                        ; 0a04

L_0a13:
0a13  e1             POP HL                           
0a14  c3 77 07       JP render_next_char              ; 0777

sub_0a17:
0a17  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0a1a  fe ba          CP 0xba                          
0a1c  c0             RET nz                           
0a1d  3a 1c 42       LD A,(COL_COUNT)                 ; 421c
0a20  a7             AND A                            
0a21  28 11          JR z,L_0a34                      ; 0a34
0a23  2a f8 41       LD HL,(EFFECT_TMP)               ; 41f8
0a26  11 a2 41       LD DE,TXBUF                      ; 41a2
0a29  af             XOR A                            
0a2a  ed 52          SBC HL,DE                        
0a2c  28 06          JR z,L_0a34                      ; 0a34
0a2e  3e 18          LD A,0x18                        
0a30  32 0e 42       LD (CUR_CHAR),A                  ; 420e
0a33  c9             RET                              

L_0a34:
0a34  cd 62 10       CALL sub_1062                    ; 1062
0a37  af             XOR A                            
0a38  32 28 42       LD (RX_BYTE),A                   ; 4228
0a3b  32 86 43       LD (IR_CODE),A                   ; 4386

L_0a3e:
0a3e  3a 28 42       LD A,(RX_BYTE)                   ; 4228
0a41  fe 20          CP 0x20                          
0a43  20 04          JR nz,L_0a49                     ; 0a49
0a45  e1             POP HL                           
0a46  c3 77 07       JP render_next_char              ; 0777

L_0a49:
0a49  3a f0 5e       LD A,(PKT_READY)                 ; 5ef0
0a4c  a7             AND A                            
0a4d  c2 68 2a       JP nz,pkt_process                ; 2a68
0a50  c3 3e 0a       JP L_0a3e                        ; 0a3e

sub_0a53:
0a53  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0a56  fe b9          CP 0xb9                          
0a58  c0             RET nz                           
0a59  32 d6 43       LD (0x43d6),A                    
0a5c  e1             POP HL                           
0a5d  c3 77 07       JP render_next_char              ; 0777

sub_0a60:
0a60  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e

; ----------------------------------------------------------------
; attr_graphic
; 0xB8: user-drawn graphic follows
attr_graphic:
0a63  fe b8          CP 0xb8                          
0a65  28 09          JR z,L_0a70                      ; 0a70
0a67  3e 00          LD A,0                           
0a69  32 60 43       LD (0x4360),A                    
0a6c  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0a6f  c9             RET                              

L_0a70:
0a70  3a 60 43       LD A,(0x4360)                    
0a73  32 9b 43       LD (0x439b),A                    
0a76  3e ff          LD A,0xff                        
0a78  32 60 43       LD (0x4360),A                    
0a7b  21 65 43       LD HL,0x4365                     
0a7e  e5             PUSH HL                          
0a7f  e5             PUSH HL                          
0a80  06 10          LD B,0x10                        

L_0a82:
0a82  36 00          LD (HL),0                        
0a84  23             INC HL                           
0a85  10 fb          DJNZ L_0a82                      ; 0a82
0a87  cd bb 19       CALL clear_glyph_tmp             ; 19bb
0a8a  e1             POP HL                           
0a8b  0e 00          LD C,0                           
0a8d  06 10          LD B,0x10                        

L_0a8f:
0a8f  cd 68 09       CALL sub_0968                    ; 0968
0a92  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0a95  cd f4 0a       CALL sub_0af4                    ; 0af4
0a98  fe ff          CP 0xff                          
0a9a  28 46          JR z,L_0ae2                      ; 0ae2
0a9c  f5             PUSH AF                          
0a9d  cd 68 09       CALL sub_0968                    ; 0968
0aa0  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0aa3  cd f4 0a       CALL sub_0af4                    ; 0af4
0aa6  fe ff          CP 0xff                          
0aa8  28 37          JR z,L_0ae1                      ; 0ae1
0aaa  ed 67          RRD                              
0aac  f1             POP AF                           
0aad  ed 67          RRD                              
0aaf  23             INC HL                           
0ab0  0c             INC C                            
0ab1  10 dc          DJNZ L_0a8f                      ; 0a8f

L_0ab3:
0ab3  e1             POP HL                           
0ab4  22 08 42       LD (GLYPH_PTR),HL                ; 4208
0ab7  22 d0 43       LD (GLYPH_PTR2),HL               ; 43d0
0aba  79             LD A,C                           
0abb  a7             AND A                            
0abc  c2 c9 0a       JP nz,L_0ac9                     ; 0ac9
0abf  af             XOR A                            
0ac0  32 9b 43       LD (0x439b),A                    
0ac3  3e 20          LD A,0x20                        
0ac5  32 0e 42       LD (CUR_CHAR),A                  ; 420e
0ac8  c9             RET                              

L_0ac9:
0ac9  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
0acc  e1             POP HL                           
0acd  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0ad0  a7             AND A                            
0ad1  ca 5c 08       JP z,L_085c                      ; 085c
0ad4  cd fd 0c       CALL draw_glyph                  ; 0cfd
0ad7  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0ada  3d             DEC A                            
0adb  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
0ade  c3 5c 08       JP L_085c                        ; 085c

L_0ae1:
0ae1  f1             POP AF                           

L_0ae2:
0ae2  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0ae5  fe 03          CP 3                             
0ae7  20 03          JR nz,L_0aec                     ; 0aec
0ae9  cd ea 0c       CALL sub_0cea                    ; 0cea

L_0aec:
0aec  3e 2a          LD A,0x2a                        
0aee  32 0e 42       LD (CUR_CHAR),A                  ; 420e
0af1  c3 b3 0a       JP L_0ab3                        ; 0ab3

sub_0af4:
0af4  fe 30          CP 0x30                          
0af6  da 11 0b       JP c,L_0b11                      ; 0b11
0af9  fe 3a          CP 0x3a                          
0afb  da 0e 0b       JP c,L_0b0e                      ; 0b0e
0afe  e6 df          AND 0xdf                         
0b00  fe 41          CP 0x41                          
0b02  da 11 0b       JP c,L_0b11                      ; 0b11
0b05  fe 47          CP 0x47                          
0b07  d2 11 0b       JP nc,L_0b11                     ; 0b11
0b0a  e6 0f          AND 15                           
0b0c  c6 09          ADD A,9                          

L_0b0e:
0b0e  e6 0f          AND 15                           
0b10  c9             RET                              

L_0b11:
0b11  3e ff          LD A,0xff                        
0b13  c9             RET                              

sub_0b14:
0b14  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
0b17  a7             AND A                            
0b18  c0             RET nz                           
0b19  3a 1a 42       LD A,(RENDER_DONE)               ; 421a
0b1c  a7             AND A                            
0b1d  c8             RET z                            
0b1e  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0b21  a7             AND A                            
0b22  28 0a          JR z,L_0b2e                      ; 0b2e
0b24  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0b27  fe 20          CP 0x20                          
0b29  c0             RET nz                           
0b2a  e1             POP HL                           
0b2b  c3 fc 0e       JP L_0efc                        ; 0efc

L_0b2e:
0b2e  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0b31  fe 20          CP 0x20                          
0b33  20 2d          JR nz,L_0b62                     ; 0b62
0b35  21 95 43       LD HL,0x4395                     
0b38  34             INC (HL)                         
0b39  3e 02          LD A,2                           
0b3b  32 39 43       LD (FONT_MODE),A                 ; 4339
0b3e  3a 93 43       LD A,(MENU_CHAR)                 ; 4393
0b41  fe 2e          CP 0x2e                          
0b43  ca 68 0c       JP z,L_0c68                      ; 0c68
0b46  fe 21          CP 0x21                          
0b48  ca 68 0c       JP z,L_0c68                      ; 0c68
0b4b  fe 3f          CP 0x3f                          
0b4d  ca 68 0c       JP z,L_0c68                      ; 0c68
0b50  fe 3a          CP 0x3a                          
0b52  ca 68 0c       JP z,L_0c68                      ; 0c68
0b55  fe 2c          CP 0x2c                          
0b57  ca 68 0c       JP z,L_0c68                      ; 0c68
0b5a  3e 20          LD A,0x20                        
0b5c  32 93 43       LD (MENU_CHAR),A                 ; 4393
0b5f  c3 d3 0c       JP L_0cd3                        ; 0cd3

L_0b62:
0b62  fe bb          CP 0xbb                          
0b64  28 0c          JR z,L_0b72                      ; 0b72
0b66  fe 0f          CP 15                            
0b68  28 08          JR z,L_0b72                      ; 0b72
0b6a  fe 19          CP 0x19                          
0b6c  38 49          JR c,L_0bb7                      ; 0bb7
0b6e  fe 1c          CP 0x1c                          
0b70  30 45          JR nc,L_0bb7                     ; 0bb7

L_0b72:
0b72  af             XOR A                            
0b73  32 97 43       LD (MENU_TMP2),A                 ; 4397
0b76  32 94 43       LD (MENU_TMP),A                  ; 4394
0b79  3a 90 43       LD A,(0x4390)                    
0b7c  a7             AND A                            
0b7d  c0             RET nz                           
0b7e  3e ff          LD A,0xff                        
0b80  32 90 43       LD (0x4390),A                    
0b83  3a a3 43       LD A,(0x43a3)                    
0b86  a7             AND A                            
0b87  c8             RET z                            
0b88  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0b8b  f5             PUSH AF                          
0b8c  06 0e          LD B,14                          

L_0b8e:
0b8e  c5             PUSH BC                          
0b8f  3e 20          LD A,0x20                        
0b91  32 0e 42       LD (CUR_CHAR),A                  ; 420e
0b94  af             XOR A                            
0b95  32 3a 42       LD (PAUSE_FLAG),A                ; 423a
0b98  21 27 13       LD HL,fx_none                    ; 1327
0b9b  22 3b 42       LD (EFFECT_VECTOR),HL            ; 423b
0b9e  3e 06          LD A,6                           
0ba0  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
0ba3  21 35 32       LD HL,0x3235                     
0ba6  22 08 42       LD (GLYPH_PTR),HL                ; 4208
0ba9  cd 6e 08       CALL sub_086e                    ; 086e
0bac  cd 44 0e       CALL effect_step                 ; 0e44
0baf  c1             POP BC                           
0bb0  10 dc          DJNZ L_0b8e                      ; 0b8e
0bb2  f1             POP AF                           
0bb3  32 0e 42       LD (CUR_CHAR),A                  ; 420e
0bb6  c9             RET                              

L_0bb7:
0bb7  af             XOR A                            
0bb8  32 90 43       LD (0x4390),A                    
0bbb  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0bbe  fe b8          CP 0xb8                          
0bc0  ca d4 0b       JP z,L_0bd4                      ; 0bd4
0bc3  e6 f0          AND 0xf0                         
0bc5  fe a0          CP 0xa0                          
0bc7  ca d4 0b       JP z,L_0bd4                      ; 0bd4
0bca  fe 20          CP 0x20                          
0bcc  da d3 0c       JP c,L_0cd3                      ; 0cd3
0bcf  fe 80          CP 0x80                          
0bd1  d2 d3 0c       JP nc,L_0cd3                     ; 0cd3

L_0bd4:
0bd4  3a 93 43       LD A,(MENU_CHAR)                 ; 4393
0bd7  fe 20          CP 0x20                          
0bd9  28 09          JR z,L_0be4                      ; 0be4
0bdb  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0bde  32 93 43       LD (MENU_CHAR),A                 ; 4393
0be1  c3 d3 0c       JP L_0cd3                        ; 0cd3

L_0be4:
0be4  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0be7  32 93 43       LD (MENU_CHAR),A                 ; 4393
0bea  fe 24          CP 0x24                          
0bec  20 03          JR nz,L_0bf1                     ; 0bf1
0bee  32 91 43       LD (0x4391),A                    

L_0bf1:
0bf1  e6 f0          AND 0xf0                         
0bf3  fe a0          CP 0xa0                          
0bf5  ca 73 0c       JP z,L_0c73                      ; 0c73
0bf8  3a 97 43       LD A,(MENU_TMP2)                 ; 4397
0bfb  a7             AND A                            
0bfc  3e 00          LD A,0                           
0bfe  32 97 43       LD (MENU_TMP2),A                 ; 4397
0c01  20 3f          JR nz,L_0c42                     ; 0c42
0c03  06 08          LD B,8                           
0c05  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346

L_0c08:
0c08  7e             LD A,(HL)                        
0c09  e6 5f          AND 0x5f                         
0c0b  fe 41          CP 0x41                          
0c0d  da 1b 0c       JP c,L_0c1b                      ; 0c1b
0c10  fe 5b          CP 0x5b                          
0c12  d2 1b 0c       JP nc,L_0c1b                     ; 0c1b
0c15  23             INC HL                           
0c16  10 f0          DJNZ L_0c08                      ; 0c08
0c18  c3 3e 0c       JP L_0c3e                        ; 0c3e

L_0c1b:
0c1b  78             LD A,B                           
0c1c  fe 06          CP 6                             
0c1e  d2 3e 0c       JP nc,L_0c3e                     ; 0c3e
0c21  3a 96 43       LD A,(RND_SEED)                  ; 4396
0c24  86             ADD A,(HL)                       
0c25  2a 3c 43       LD HL,(NMI_COUNT)                ; 433c
0c28  86             ADD A,(HL)                       
0c29  32 96 43       LD (RND_SEED),A                  ; 4396
0c2c  e6 03          AND 3                            
0c2e  28 07          JR z,L_0c37                      ; 0c37
0c30  21 39 43       LD HL,FONT_MODE                  ; 4339
0c33  36 02          LD (HL),2                        
0c35  18 0b          JR L_0c42                        ; 0c42

L_0c37:
0c37  21 39 43       LD HL,FONT_MODE                  ; 4339
0c3a  36 06          LD (HL),6                        
0c3c  18 04          JR L_0c42                        ; 0c42

L_0c3e:
0c3e  af             XOR A                            
0c3f  32 39 43       LD (FONT_MODE),A                 ; 4339

L_0c42:
0c42  3a 95 43       LD A,(0x4395)                    
0c45  fe 03          CP 3                             
0c47  d2 73 0c       JP nc,L_0c73                     ; 0c73
0c4a  3a 98 43       LD A,(RND_VAL)                   ; 4398
0c4d  a7             AND A                            
0c4e  ca 68 0c       JP z,L_0c68                      ; 0c68
0c51  3d             DEC A                            
0c52  ca 68 0c       JP z,L_0c68                      ; 0c68
0c55  32 98 43       LD (RND_VAL),A                   ; 4398
0c58  3a 94 43       LD A,(MENU_TMP)                  ; 4394
0c5b  a7             AND A                            
0c5c  28 71          JR z,L_0ccf                      ; 0ccf
0c5e  af             XOR A                            
0c5f  32 94 43       LD (MENU_TMP),A                  ; 4394
0c62  32 98 43       LD (RND_VAL),A                   ; 4398
0c65  c3 cf 0c       JP L_0ccf                        ; 0ccf

L_0c68:
0c68  3a 3c 43       LD A,(NMI_COUNT)                 ; 433c
0c6b  5f             LD E,A                           
0c6c  e6 03          AND 3                            
0c6e  c6 02          ADD A,2                          
0c70  32 98 43       LD (RND_VAL),A                   ; 4398

L_0c73:
0c73  3a 94 43       LD A,(MENU_TMP)                  ; 4394
0c76  a7             AND A                            
0c77  28 0a          JR z,L_0c83                      ; 0c83
0c79  af             XOR A                            
0c7a  32 94 43       LD (MENU_TMP),A                  ; 4394
0c7d  32 98 43       LD (RND_VAL),A                   ; 4398
0c80  c3 cf 0c       JP L_0ccf                        ; 0ccf

L_0c83:
0c83  af             XOR A                            
0c84  32 a4 43       LD (0x43a4),A                    
0c87  3a 62 43       LD A,(0x4362)                    
0c8a  3c             INC A                            
0c8b  5f             LD E,A                           
0c8c  3a 3c 43       LD A,(NMI_COUNT)                 ; 433c
0c8f  83             ADD A,E                          

L_0c90:
0c90  e6 0f          AND 15                           
0c92  32 62 43       LD (0x4362),A                    
0c95  5f             LD E,A                           
0c96  16 00          LD D,0                           
0c98  21 da 0c       LD HL,0x0cda                     
0c9b  19             ADD HL,DE                        
0c9c  3a 0c 42       LD A,(CUR_COLOUR)                ; 420c
0c9f  e6 0f          AND 15                           
0ca1  be             CP (HL)                          
0ca2  28 1c          JR z,L_0cc0                      ; 0cc0
0ca4  3a 0c 42       LD A,(CUR_COLOUR)                ; 420c
0ca7  5f             LD E,A                           
0ca8  56             LD D,(HL)                        
0ca9  7a             LD A,D                           
0caa  21 0c 42       LD HL,CUR_COLOUR                 ; 420c
0cad  ed 6f          RLD                              
0caf  7e             LD A,(HL)                        
0cb0  21 d4 0c       LD HL,TBL_0CD4                   ; 0cd4
0cb3  01 06 00       LD BC,6                          
0cb6  b7             OR A                             
0cb7  ed b1          CPIR                             
0cb9  c2 c6 0c       JP nz,L_0cc6                     ; 0cc6
0cbc  7b             LD A,E                           
0cbd  32 0c 42       LD (CUR_COLOUR),A                ; 420c

L_0cc0:
0cc0  3a 62 43       LD A,(0x4362)                    
0cc3  3c             INC A                            
0cc4  18 ca          JR L_0c90                        ; 0c90

L_0cc6:
0cc6  7b             LD A,E                           
0cc7  e6 10          AND 0x10                         
0cc9  b2             OR D                             
0cca  e6 1f          AND 0x1f                         
0ccc  32 0c 42       LD (CUR_COLOUR),A                ; 420c

L_0ccf:
0ccf  af             XOR A                            
0cd0  32 95 43       LD (0x4395),A                    

L_0cd3:
0cd3  c9             RET                              

; ---------------- data: TBL_0CD4 (0cd4-0ce9) 
TBL_0CD4:
        db 0xf7,0x7f,0xfd,0xdf,0xcd,0xdc,0x07,0x0c,0x0f,0x03,0x0c,0x03,0x0d,0x03,0x0f,0x03 ; 0cd4
        db 0x0c,0x03,0x03,0x0c,0x0f,0x0c                                       ; 0ce4

sub_0cea:
0cea  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
0ced  11 e2 43       LD DE,MSG_STORE                  ; 43e2
0cf0  b7             OR A                             
0cf1  ed 52          SBC HL,DE                        
0cf3  28 07          JR z,L_0cfc                      ; 0cfc
0cf5  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
0cf8  2b             DEC HL                           
0cf9  22 46 43       LD (STORE_CURSOR),HL             ; 4346

L_0cfc:
0cfc  c9             RET                              

; ----------------------------------------------------------------
; draw_glyph
; Copy the glyph columns into FRAMEBUF at the current column
draw_glyph:
0cfd  3a 3b 43       LD A,(0x433b)                    
0d00  a7             AND A                            
0d01  20 33          JR nz,L_0d36                     ; 0d36
0d03  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0d06  a7             AND A                            
0d07  28 26          JR z,L_0d2f                      ; 0d2f
0d09  3a d6 43       LD A,(0x43d6)                    
0d0c  a7             AND A                            
0d0d  28 27          JR z,L_0d36                      ; 0d36
0d0f  3a 39 43       LD A,(FONT_MODE)                 ; 4339
0d12  e6 0a          AND 10                           
0d14  20 19          JR nz,L_0d2f                     ; 0d2f
0d16  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0d19  4f             LD C,A                           
0d1a  06 00          LD B,0                           
0d1c  3c             INC A                            
0d1d  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
0d20  2a 08 42       LD HL,(GLYPH_PTR)                ; 4208
0d23  11 d6 42       LD DE,0x42d6                     
0d26  ed b0          LDIR                             
0d28  21 d6 42       LD HL,0x42d6                     
0d2b  22 08 42       LD (GLYPH_PTR),HL                ; 4208
0d2e  c9             RET                              

L_0d2f:
0d2f  3a 39 43       LD A,(FONT_MODE)                 ; 4339
0d32  cb 4f          BIT 1,A                          
0d34  28 60          JR z,L_0d96                      ; 0d96

L_0d36:
0d36  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0d39  47             LD B,A                           
0d3a  2a 08 42       LD HL,(GLYPH_PTR)                ; 4208
0d3d  11 d6 42       LD DE,0x42d6                     
0d40  0e 00          LD C,0                           

L_0d42:
0d42  7e             LD A,(HL)                        
0d43  12             LD (DE),A                        
0d44  23             INC HL                           
0d45  a7             AND A                            
0d46  28 04          JR z,L_0d4c                      ; 0d4c
0d48  b6             OR (HL)                          
0d49  13             INC DE                           
0d4a  0c             INC C                            
0d4b  12             LD (DE),A                        

L_0d4c:
0d4c  13             INC DE                           
0d4d  0c             INC C                            
0d4e  10 f2          DJNZ L_0d42                      ; 0d42
0d50  af             XOR A                            
0d51  12             LD (DE),A                        
0d52  79             LD A,C                           
0d53  fe 02          CP 2                             
0d55  28 04          JR z,L_0d5b                      ; 0d5b
0d57  af             XOR A                            
0d58  1b             DEC DE                           
0d59  12             LD (DE),A                        
0d5a  79             LD A,C                           

L_0d5b:
0d5b  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
0d5e  21 d6 42       LD HL,0x42d6                     
0d61  22 08 42       LD (GLYPH_PTR),HL                ; 4208
0d64  dd 21 d6 42    LD IX,0x42d6                     
0d68  06 04          LD B,4                           

L_0d6a:
0d6a  dd 7e 00       LD A,(IX)                        
0d6d  fe 7f          CP 0x7f                          
0d6f  20 0e          JR nz,L_0d7f                     ; 0d7f
0d71  dd 7e 01       LD A,(IX+1)                      
0d74  fe 7f          CP 0x7f                          
0d76  20 07          JR nz,L_0d7f                     ; 0d7f
0d78  dd 7e 02       LD A,(IX+2)                      
0d7b  fe 7f          CP 0x7f                          
0d7d  28 05          JR z,L_0d84                      ; 0d84

L_0d7f:
0d7f  dd 23          INC IX                           
0d81  10 e7          DJNZ L_0d6a                      ; 0d6a
0d83  c9             RET                              

L_0d84:
0d84  dd e5          PUSH IX                          
0d86  e1             POP HL                           
0d87  54             LD D,H                           
0d88  5d             LD E,L                           
0d89  23             INC HL                           
0d8a  01 1c 00       LD BC,0x1c                       
0d8d  ed b0          LDIR                             
0d8f  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0d92  3d             DEC A                            
0d93  32 07 42       LD (GLYPH_WIDTH),A               ; 4207

L_0d96:
0d96  c9             RET                              

sub_0d97:
0d97  3a 39 43       LD A,(FONT_MODE)                 ; 4339
0d9a  cb 57          BIT 2,A                          
0d9c  28 44          JR z,L_0de2                      ; 0de2
0d9e  2a 08 42       LD HL,(GLYPH_PTR)                ; 4208
0da1  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0da4  4f             LD C,A                           
0da5  11 f6 42       LD DE,0x42f6                     
0da8  06 00          LD B,0                           
0daa  ed b0          LDIR                             
0dac  47             LD B,A                           
0dad  58             LD E,B                           
0dae  16 00          LD D,0                           
0db0  21 f6 42       LD HL,0x42f6                     
0db3  19             ADD HL,DE                        
0db4  e5             PUSH HL                          
0db5  dd e1          POP IX                           

L_0db7:
0db7  7e             LD A,(HL)                        
0db8  e6 03          AND 3                            
0dba  dd b6 02       OR (IX+2)                        
0dbd  dd 77 02       LD (IX+2),A                      
0dc0  7e             LD A,(HL)                        
0dc1  e6 0c          AND 12                           
0dc3  dd b6 01       OR (IX+1)                        
0dc6  dd 77 01       LD (IX+1),A                      
0dc9  7e             LD A,(HL)                        
0dca  e6 f0          AND 0xf0                         
0dcc  77             LD (HL),A                        
0dcd  2b             DEC HL                           
0dce  dd 2b          DEC IX                           
0dd0  05             DEC B                            
0dd1  f2 b7 0d       JP p,L_0db7                      ; 0db7
0dd4  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0dd7  3c             INC A                            
0dd8  3c             INC A                            
0dd9  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
0ddc  21 f6 42       LD HL,0x42f6                     
0ddf  22 08 42       LD (GLYPH_PTR),HL                ; 4208

L_0de2:
0de2  c9             RET                              

sub_0de3:
0de3  3a 39 43       LD A,(FONT_MODE)                 ; 4339
0de6  cb 5f          BIT 3,A                          
0de8  28 2b          JR z,L_0e15                      ; 0e15
0dea  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
0ded  47             LD B,A                           
0dee  2a 08 42       LD HL,(GLYPH_PTR)                ; 4208
0df1  11 16 43       LD DE,0x4316                     
0df4  0e 00          LD C,0                           

L_0df6:
0df6  7e             LD A,(HL)                        
0df7  12             LD (DE),A                        
0df8  23             INC HL                           
0df9  a7             AND A                            
0dfa  28 04          JR z,L_0e00                      ; 0e00
0dfc  b6             OR (HL)                          
0dfd  13             INC DE                           
0dfe  0c             INC C                            
0dff  12             LD (DE),A                        

L_0e00:
0e00  13             INC DE                           
0e01  0c             INC C                            
0e02  10 f2          DJNZ L_0df6                      ; 0df6
0e04  af             XOR A                            
0e05  12             LD (DE),A                        
0e06  1b             DEC DE                           
0e07  12             LD (DE),A                        
0e08  1b             DEC DE                           
0e09  12             LD (DE),A                        
0e0a  79             LD A,C                           
0e0b  3d             DEC A                            
0e0c  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
0e0f  21 16 43       LD HL,0x4316                     
0e12  22 08 42       LD (GLYPH_PTR),HL                ; 4208

L_0e15:
0e15  c9             RET                              

sub_0e16:
0e16  23             INC HL                           
0e17  f5             PUSH AF                          
0e18  d5             PUSH DE                          
0e19  e5             PUSH HL                          
0e1a  11 98 41       LD DE,FB_COLPTR                  ; 4198
0e1d  af             XOR A                            
0e1e  ed 52          SBC HL,DE                        
0e20  da 29 0e       JP c,L_0e29                      ; 0e29
0e23  21 40 40       LD HL,FRAMEBUF                   ; 4040
0e26  d1             POP DE                           
0e27  18 01          JR L_0e2a                        ; 0e2a

L_0e29:
0e29  e1             POP HL                           

L_0e2a:
0e2a  d1             POP DE                           
0e2b  f1             POP AF                           
0e2c  c9             RET                              

sub_0e2d:
0e2d  f5             PUSH AF                          
0e2e  d5             PUSH DE                          
0e2f  19             ADD HL,DE                        
0e30  e5             PUSH HL                          
0e31  11 98 41       LD DE,FB_COLPTR                  ; 4198
0e34  af             XOR A                            
0e35  ed 52          SBC HL,DE                        
0e37  38 07          JR c,L_0e40                      ; 0e40
0e39  d1             POP DE                           
0e3a  11 40 40       LD DE,FRAMEBUF                   ; 4040
0e3d  19             ADD HL,DE                        
0e3e  18 01          JR L_0e41                        ; 0e41

L_0e40:
0e40  e1             POP HL                           

L_0e41:
0e41  d1             POP DE                           
0e42  f1             POP AF                           
0e43  c9             RET                              

; ----------------------------------------------------------------
; effect_step
; Called from main loop: jump to EFFECT_VECTOR (current movement effect handler)
effect_step:
0e44  3a 44 42       LD A,(0x4244)                    
0e47  a7             AND A                            
0e48  20 fa          JR nz,effect_step                ; 0e44

L_0e4a:
0e4a  3a 0d 42       LD A,(EFFECT_PHASE)              ; 420d
0e4d  a7             AND A                            
0e4e  20 fa          JR nz,L_0e4a                     ; 0e4a
0e50  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0e53  a7             AND A                            
0e54  c8             RET z                            

L_0e55:
0e55  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
0e58  fe 06          CP 6                             
0e5a  20 f9          JR nz,L_0e55                     ; 0e55
0e5c  2a fb 41       LD HL,(EFFECT_TMP2)              ; 41fb
0e5f  7d             LD A,L                           
0e60  fe 2b          CP 0x2b                          
0e62  28 04          JR z,L_0e68                      ; 0e68
0e64  2a 3b 42       LD HL,(EFFECT_VECTOR)            ; 423b
0e67  e9             JP (HL)                          

L_0e68:
0e68  21 00 00       LD HL,0                          
0e6b  22 fb 41       LD (EFFECT_TMP2),HL              ; 41fb

L_0e6e:
0e6e  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
0e71  7e             LD A,(HL)                        
0e72  fe ba          CP 0xba                          
0e74  20 04          JR nz,L_0e7a                     ; 0e7a
0e76  af             XOR A                            
0e77  32 44 42       LD (0x4244),A                    

L_0e7a:
0e7a  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
0e7d  a7             AND A                            
0e7e  28 1b          JR z,L_0e9b                      ; 0e9b
0e80  3a 1a 42       LD A,(RENDER_DONE)               ; 421a
0e83  a7             AND A                            
0e84  28 05          JR z,L_0e8b                      ; 0e8b
0e86  3e 0f          LD A,15                          
0e88  32 0c 42       LD (CUR_COLOUR),A                ; 420c

L_0e8b:
0e8b  3a 42 42       LD A,(0x4242)                    
0e8e  2f             CPL                              
0e8f  a7             AND A                            
0e90  32 42 42       LD (0x4242),A                    
0e93  28 06          JR z,L_0e9b                      ; 0e9b
0e95  af             XOR A                            
0e96  32 42 42       LD (0x4242),A                    
0e99  3e 56          LD A,0x56                        

L_0e9b:
0e9b  32 1c 42       LD (COL_COUNT),A                 ; 421c
0e9e  cd ac 19       CALL clear_txbuf                 ; 19ac
0ea1  21 a2 41       LD HL,TXBUF                      ; 41a2
0ea4  22 f8 41       LD (EFFECT_TMP),HL               ; 41f8
0ea7  c9             RET                              

L_0ea8:
0ea8  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e

; ----------------------------------------------------------------
; attr_dispatch
; Attribute byte dispatcher: 11 normal,12 bold,13 italic,14 flash,10 large,1F magic,06 pause,07
; beep,03 end,18 crawl,19 jump,1A wipe up,1B wipe down,0F wipe back,BB (extra effect)
attr_dispatch:
0eab  fe 11          CP 0x11                          
0ead  c2 ba 0e       JP nz,L_0eba                     ; 0eba
0eb0  af             XOR A                            
0eb1  32 1e 42       LD (0x421e),A                    
0eb4  32 39 43       LD (FONT_MODE),A                 ; 4339
0eb7  c3 e1 0e       JP L_0ee1                        ; 0ee1

L_0eba:
0eba  fe 12          CP 0x12                          
0ebc  c2 c4 0e       JP nz,L_0ec4                     ; 0ec4
0ebf  3e 02          LD A,2                           
0ec1  c3 e1 0e       JP L_0ee1                        ; 0ee1

L_0ec4:
0ec4  fe 13          CP 0x13                          
0ec6  c2 ce 0e       JP nz,L_0ece                     ; 0ece
0ec9  3e 06          LD A,6                           
0ecb  c3 e1 0e       JP L_0ee1                        ; 0ee1

L_0ece:
0ece  fe 14          CP 0x14                          
0ed0  c2 db 0e       JP nz,L_0edb                     ; 0edb
0ed3  3e 10          LD A,0x10                        
0ed5  32 a2 43       LD (0x43a2),A                    
0ed8  c3 77 07       JP render_next_char              ; 0777

L_0edb:
0edb  fe 10          CP 0x10                          
0edd  20 0d          JR nz,L_0eec                     ; 0eec
0edf  3e 0a          LD A,10                          

L_0ee1:
0ee1  32 39 43       LD (FONT_MODE),A                 ; 4339
0ee4  3e ff          LD A,0xff                        
0ee6  32 97 43       LD (MENU_TMP2),A                 ; 4397
0ee9  c3 77 07       JP render_next_char              ; 0777

L_0eec:
0eec  fe 1f          CP 0x1f                          
0eee  ca cc 0f       JP z,fx_magic                    ; 0fcc

L_0ef1:
0ef1  3a 1c 42       LD A,(COL_COUNT)                 ; 421c
0ef4  a7             AND A                            
0ef5  28 18          JR z,L_0f0f                      ; 0f0f
0ef7  3e ff          LD A,0xff                        
0ef9  32 42 42       LD (0x4242),A                    

L_0efc:
0efc  2a f8 41       LD HL,(EFFECT_TMP)               ; 41f8
0eff  11 f8 41       LD DE,EFFECT_TMP                 ; 41f8
0f02  af             XOR A                            
0f03  eb             EX DE,HL                         
0f04  ed 52          SBC HL,DE                        
0f06  3e 56          LD A,0x56                        
0f08  95             SUB L                            
0f09  32 1c 42       LD (COL_COUNT),A                 ; 421c
0f0c  c3 37 09       JP L_0937                        ; 0937

L_0f0f:
0f0f  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
0f12  fe 06          CP 6                             
0f14  ca 32 10       JP z,fx_pause                    ; 1032
0f17  fe 07          CP 7                             
0f19  ca 42 0f       JP z,fx_beep                     ; 0f42
0f1c  fe 03          CP 3                             
0f1e  ca 51 0f       JP z,fx_end_of_channel           ; 0f51
0f21  fe 18          CP 0x18                          
0f23  ca 75 0f       JP z,fx_crawl                    ; 0f75
0f26  fe 19          CP 0x19                          
0f28  ca 8d 0f       JP z,fx_jump                     ; 0f8d
0f2b  fe 1a          CP 0x1a                          
0f2d  ca 9e 0f       JP z,fx_wipe_up                  ; 0f9e
0f30  fe 1b          CP 0x1b                          
0f32  ca af 0f       JP z,fx_wipe_down                ; 0faf
0f35  fe 0f          CP 15                            
0f37  ca 64 0f       JP z,fx_wipe_back                ; 0f64
0f3a  fe bb          CP 0xbb                          
0f3c  ca 7f 0f       JP z,fx_BB                       ; 0f7f
0f3f  c3 77 07       JP render_next_char              ; 0777

; ----------------------------------------------------------------
; fx_beep
fx_beep:
0f42  cd 48 0f       CALL sub_0f48                    ; 0f48
0f45  c3 77 07       JP render_next_char              ; 0777

sub_0f48:
0f48  e5             PUSH HL                          
0f49  21 96 00       LD HL,0x96                       
0f4c  22 fe 41       LD (TICK_COUNTDOWN),HL           ; 41fe
0f4f  e1             POP HL                           
0f50  c9             RET                              

; ----------------------------------------------------------------
; fx_end_of_channel
fx_end_of_channel:
0f51  21 27 13       LD HL,fx_none                    ; 1327
0f54  22 3b 42       LD (EFFECT_VECTOR),HL            ; 423b
0f57  af             XOR A                            
0f58  32 3a 42       LD (PAUSE_FLAG),A                ; 423a
0f5b  cd 53 19       CALL demo_scroll                 ; 1953
0f5e  31 3f 40       LD SP,0x403f                     
0f61  c3 9a 00       JP main_loop                     ; 009a

; ----------------------------------------------------------------
; fx_wipe_back
fx_wipe_back:
0f64  af             XOR A                            
0f65  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
0f68  3e 56          LD A,0x56                        
0f6a  32 1c 42       LD (COL_COUNT),A                 ; 421c
0f6d  3e 04          LD A,4                           
0f6f  21 f2 12       LD HL,fx_scroll_in               ; 12f2
0f72  c3 c0 0f       JP set_effect_vector             ; 0fc0

; ----------------------------------------------------------------
; fx_crawl
fx_crawl:
0f75  af             XOR A                            
0f76  32 1c 42       LD (COL_COUNT),A                 ; 421c
0f79  21 27 13       LD HL,fx_none                    ; 1327
0f7c  c3 c0 0f       JP set_effect_vector             ; 0fc0

; ----------------------------------------------------------------
; fx_BB
fx_BB:
0f7f  af             XOR A                            
0f80  3e 56          LD A,0x56                        
0f82  32 1c 42       LD (COL_COUNT),A                 ; 421c
0f85  3e 05          LD A,5                           
0f87  21 2a 13       LD HL,fx_fill_frame              ; 132a
0f8a  c3 c0 0f       JP set_effect_vector             ; 0fc0

; ----------------------------------------------------------------
; fx_jump
fx_jump:
0f8d  af             XOR A                            
0f8e  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
0f91  3e 56          LD A,0x56                        
0f93  32 1c 42       LD (COL_COUNT),A                 ; 421c
0f96  3e 01          LD A,1                           
0f98  21 74 13       LD HL,fx_scroll_copy             ; 1374
0f9b  c3 c0 0f       JP set_effect_vector             ; 0fc0

; ----------------------------------------------------------------
; fx_wipe_up
fx_wipe_up:
0f9e  af             XOR A                            
0f9f  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
0fa2  3e 56          LD A,0x56                        
0fa4  32 1c 42       LD (COL_COUNT),A                 ; 421c
0fa7  3e 02          LD A,2                           
0fa9  21 8b 13       LD HL,fx_138b                    ; 138b
0fac  c3 c0 0f       JP set_effect_vector             ; 0fc0

; ----------------------------------------------------------------
; fx_wipe_down
fx_wipe_down:
0faf  af             XOR A                            
0fb0  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
0fb3  3e 56          LD A,0x56                        
0fb5  32 1c 42       LD (COL_COUNT),A                 ; 421c
0fb8  3e 03          LD A,3                           
0fba  21 8b 13       LD HL,fx_138b                    ; 138b
0fbd  c3 c0 0f       JP set_effect_vector             ; 0fc0

; ----------------------------------------------------------------
; set_effect_vector
; HL -> EFFECT_VECTOR, A -> effect id
set_effect_vector:
0fc0  32 3a 42       LD (PAUSE_FLAG),A                ; 423a
0fc3  32 8c 43       LD (0x438c),A                    
0fc6  22 3b 42       LD (EFFECT_VECTOR),HL            ; 423b
0fc9  c3 77 07       JP render_next_char              ; 0777

; ----------------------------------------------------------------
; fx_magic
fx_magic:
0fcc  af             XOR A                            
0fcd  32 a2 43       LD (0x43a2),A                    
0fd0  32 94 43       LD (MENU_TMP),A                  ; 4394
0fd3  32 97 43       LD (MENU_TMP2),A                 ; 4397
0fd6  32 a4 43       LD (0x43a4),A                    
0fd9  32 90 43       LD (0x4390),A                    
0fdc  3e ff          LD A,0xff                        
0fde  32 1a 42       LD (RENDER_DONE),A               ; 421a
0fe1  3e 20          LD A,0x20                        
0fe3  32 93 43       LD (MENU_CHAR),A                 ; 4393
0fe6  3e 01          LD A,1                           
0fe8  32 95 43       LD (0x4395),A                    
0feb  3a 3c 43       LD A,(NMI_COUNT)                 ; 433c
0fee  5f             LD E,A                           
0fef  e6 03          AND 3                            
0ff1  c6 02          ADD A,2                          
0ff3  32 98 43       LD (RND_VAL),A                   ; 4398
0ff6  cd fc 0f       CALL sub_0ffc                    ; 0ffc
0ff9  c3 77 07       JP render_next_char              ; 0777

sub_0ffc:
0ffc  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
0fff  a7             AND A                            
1000  c0             RET nz                           
1001  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
1004  a7             AND A                            
1005  c0             RET nz                           
1006  3a 62 43       LD A,(0x4362)                    
1009  3c             INC A                            
100a  e6 0f          AND 15                           
100c  32 62 43       LD (0x4362),A                    
100f  5f             LD E,A                           
1010  16 00          LD D,0                           
1012  21 da 0c       LD HL,0x0cda                     
1015  19             ADD HL,DE                        
1016  7e             LD A,(HL)                        
1017  e6 0f          AND 15                           
1019  32 0c 42       LD (CUR_COLOUR),A                ; 420c
101c  c9             RET                              

; ----------------------------------------------------------------
; attr_restart
; 0xBD
attr_restart:
101d  af             XOR A                            
101e  32 1a 42       LD (RENDER_DONE),A               ; 421a
1021  32 97 43       LD (MENU_TMP2),A                 ; 4397
1024  32 94 43       LD (MENU_TMP),A                  ; 4394
1027  32 39 43       LD (FONT_MODE),A                 ; 4339
102a  3e 8f          LD A,0x8f                        
102c  32 0c 42       LD (CUR_COLOUR),A                ; 420c
102f  c3 77 07       JP render_next_char              ; 0777

; ----------------------------------------------------------------
; fx_pause
fx_pause:
1032  af             XOR A                            
1033  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
1036  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
1039  a7             AND A                            
103a  20 06          JR nz,L_1042                     ; 1042

L_103c:
103c  3a 44 42       LD A,(0x4244)                    
103f  a7             AND A                            
1040  20 fa          JR nz,L_103c                     ; 103c

L_1042:
1042  3e 50          LD A,0x50                        
1044  32 44 42       LD (0x4244),A                    
1047  cd 62 10       CALL sub_1062                    ; 1062
104a  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
104d  7e             LD A,(HL)                        
104e  fe 18          CP 0x18                          
1050  ca 75 0f       JP z,fx_crawl                    ; 0f75
1053  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
1056  a7             AND A                            
1057  ca 75 0f       JP z,fx_crawl                    ; 0f75
105a  3e 56          LD A,0x56                        
105c  32 1c 42       LD (COL_COUNT),A                 ; 421c
105f  c3 77 07       JP render_next_char              ; 0777

sub_1062:
1062  21 40 40       LD HL,FRAMEBUF                   ; 4040
1065  01 58 01       LD BC,0x0158                     

L_1068:
1068  cb 7e          BIT 7,(HL)                       
106a  28 06          JR z,L_1072                      ; 1072
106c  7e             LD A,(HL)                        
106d  e6 10          AND 0x10                         
106f  f6 8f          OR 0x8f                          
1071  77             LD (HL),A                        

L_1072:
1072  23             INC HL                           
1073  0b             DEC BC                           
1074  79             LD A,C                           
1075  b0             OR B                             
1076  20 f0          JR nz,L_1068                     ; 1068
1078  3a 1b 42       LD A,(0x421b)                    
107b  e6 10          AND 0x10                         
107d  f6 8f          OR 0x8f                          
107f  32 1b 42       LD (0x421b),A                    
1082  32 22 42       LD (ROW_DATA_LATCH),A            ; 4222
1085  5f             LD E,A                           
1086  3a 1a 42       LD A,(RENDER_DONE)               ; 421a
1089  a7             AND A                            
108a  c8             RET z                            
108b  3e 0f          LD A,15                          
108d  32 0c 42       LD (CUR_COLOUR),A                ; 420c
1090  c9             RET                              

; ----------------------------------------------------------------
; attr_colour_speed
; 0x8x foreground colour, 0x9x background, 0xFx speed, 0xBD restart
attr_colour_speed:
1091  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
1094  e6 f0          AND 0xf0                         
1096  fe 80          CP 0x80                          
1098  ca b0 10       JP z,attr_fore_colour            ; 10b0
109b  fe 90          CP 0x90                          
109d  ca d9 10       JP z,attr_back_colour            ; 10d9
10a0  fe f0          CP 0xf0                          
10a2  ca 0f 11       JP z,attr_speed                  ; 110f
10a5  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
10a8  fe bd          CP 0xbd                          
10aa  ca 1d 10       JP z,attr_restart                ; 101d
10ad  c3 77 07       JP render_next_char              ; 0777

; ----------------------------------------------------------------
; attr_fore_colour
attr_fore_colour:
10b0  af             XOR A                            
10b1  32 a4 43       LD (0x43a4),A                    
10b4  3a 1a 42       LD A,(RENDER_DONE)               ; 421a
10b7  a7             AND A                            
10b8  28 08          JR z,L_10c2                      ; 10c2
10ba  3a 0c 42       LD A,(CUR_COLOUR)                ; 420c
10bd  e6 cf          AND 0xcf                         
10bf  32 0c 42       LD (CUR_COLOUR),A                ; 420c

L_10c2:
10c2  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
10c5  e6 0f          AND 15                           
10c7  5f             LD E,A                           
10c8  3a 0c 42       LD A,(CUR_COLOUR)                ; 420c
10cb  e6 60          AND 0x60                         
10cd  b3             OR E                             
10ce  32 0c 42       LD (CUR_COLOUR),A                ; 420c
10d1  3e ff          LD A,0xff                        
10d3  32 94 43       LD (MENU_TMP),A                  ; 4394
10d6  c3 77 07       JP render_next_char              ; 0777

; ----------------------------------------------------------------
; attr_back_colour
attr_back_colour:
10d9  3a 1a 42       LD A,(RENDER_DONE)               ; 421a
10dc  a7             AND A                            
10dd  28 08          JR z,L_10e7                      ; 10e7
10df  3a 0c 42       LD A,(CUR_COLOUR)                ; 420c
10e2  f6 0f          OR 15                            
10e4  32 0c 42       LD (CUR_COLOUR),A                ; 420c

L_10e7:
10e7  af             XOR A                            
10e8  32 a4 43       LD (0x43a4),A                    
10eb  21 00 00       LD HL,0                          
10ee  11 20 00       LD DE,0x20                       
10f1  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
10f4  e6 03          AND 3                            
10f6  28 04          JR z,L_10fc                      ; 10fc

L_10f8:
10f8  19             ADD HL,DE                        
10f9  3d             DEC A                            
10fa  20 fc          JR nz,L_10f8                     ; 10f8

L_10fc:
10fc  3a 0c 42       LD A,(CUR_COLOUR)                ; 420c
10ff  e6 0f          AND 15                           
1101  b5             OR L                             
1102  e6 6f          AND 0x6f                         
1104  32 0c 42       LD (CUR_COLOUR),A                ; 420c
1107  3e ff          LD A,0xff                        
1109  32 94 43       LD (MENU_TMP),A                  ; 4394
110c  c3 77 07       JP render_next_char              ; 0777

; ----------------------------------------------------------------
; attr_speed
attr_speed:
110f  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
1112  e6 07          AND 7                            
1114  32 cd 43       LD (0x43cd),A                    
1117  c3 77 07       JP render_next_char              ; 0777

; ----------------------------------------------------------------
; attr_tiny
; 0xBE: switch to tiny (28-char) font mode and render
attr_tiny:
111a  cd 4c 11       CALL sub_114c                    ; 114c
111d  cd 99 19       CALL clear_framebuf              ; 1999
1120  3e ff          LD A,0xff                        
1122  32 5f 43       LD (TINY_RENDER),A               ; 435f
1125  3e 8f          LD A,0x8f                        
1127  32 eb 40       LD (FRAMEBUF_TINY),A             ; 40eb

L_112a:
112a  cd 87 11       CALL sub_1187                    ; 1187
112d  a7             AND A                            
112e  20 0c          JR nz,L_113c                     ; 113c
1130  cd fe 11       CALL sub_11fe                    ; 11fe
1133  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
1136  23             INC HL                           
1137  22 46 43       LD (STORE_CURSOR),HL             ; 4346
113a  18 ee          JR L_112a                        ; 112a

L_113c:
113c  cd 31 12       CALL sub_1231                    ; 1231
113f  cd 99 19       CALL clear_framebuf              ; 1999
1142  af             XOR A                            
1143  32 5f 43       LD (TINY_RENDER),A               ; 435f
1146  cd 98 06       CALL init_render                 ; 0698
1149  c3 a7 00       JP L_00a7                        ; 00a7

sub_114c:
114c  1e 00          LD E,0                           
114e  21 9b 41       LD HL,FB_COL                     ; 419b
1151  06 56          LD B,0x56                        

L_1153:
1153  cb 7e          BIT 7,(HL)                       
1155  28 03          JR z,L_115a                      ; 115a
1157  7e             LD A,(HL)                        
1158  b3             OR E                             
1159  5f             LD E,A                           

L_115a:
115a  23             INC HL                           
115b  10 f6          DJNZ L_1153                      ; 1153
115d  7b             LD A,E                           
115e  a7             AND A                            
115f  c8             RET z                            
1160  06 0e          LD B,14                          

L_1162:
1162  c5             PUSH BC                          
1163  3e 20          LD A,0x20                        
1165  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1168  af             XOR A                            
1169  32 3a 42       LD (PAUSE_FLAG),A                ; 423a
116c  21 27 13       LD HL,fx_none                    ; 1327
116f  22 3b 42       LD (EFFECT_VECTOR),HL            ; 423b
1172  3e 06          LD A,6                           
1174  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
1177  21 35 32       LD HL,0x3235                     
117a  22 08 42       LD (GLYPH_PTR),HL                ; 4208
117d  cd 6e 08       CALL sub_086e                    ; 086e
1180  cd 44 0e       CALL effect_step                 ; 0e44
1183  c1             POP BC                           
1184  10 dc          DJNZ L_1162                      ; 1162
1186  c9             RET                              

sub_1187:
1187  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
118a  7e             LD A,(HL)                        
118b  32 0e 42       LD (CUR_CHAR),A                  ; 420e
118e  e6 f0          AND 0xf0                         
1190  fe a0          CP 0xa0                          
1192  20 0a          JR nz,L_119e                     ; 119e
1194  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
1197  e6 0f          AND 15                           
1199  32 0e 42       LD (CUR_CHAR),A                  ; 420e
119c  18 29          JR L_11c7                        ; 11c7

L_119e:
119e  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
11a1  e6 60          AND 0x60                         
11a3  ca fb 11       JP z,L_11fb                      ; 11fb
11a6  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
11a9  fe 5f          CP 0x5f                          
11ab  ca fb 11       JP z,L_11fb                      ; 11fb
11ae  cb 7f          BIT 7,A                          
11b0  ca c7 11       JP z,L_11c7                      ; 11c7
11b3  fe 94          CP 0x94                          
11b5  da fb 11       JP c,L_11fb                      ; 11fb
11b8  fe 9e          CP 0x9e                          
11ba  38 0b          JR c,L_11c7                      ; 11c7
11bc  e6 f0          AND 0xf0                         
11be  fe c0          CP 0xc0                          
11c0  28 05          JR z,L_11c7                      ; 11c7
11c2  fe e0          CP 0xe0                          
11c4  c2 fb 11       JP nz,L_11fb                     ; 11fb

L_11c7:
11c7  21 35 31       LD HL,FONT                       ; 3135
11ca  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
11cd  cd 42 09       CALL char_to_glyph               ; 0942
11d0  5f             LD E,A                           
11d1  16 00          LD D,0                           
11d3  cb 23          SLA E                            
11d5  cb 12          RL D                             
11d7  cb 23          SLA E                            
11d9  cb 12          RL D                             
11db  cb 23          SLA E                            
11dd  cb 12          RL D                             
11df  19             ADD HL,DE                        
11e0  e5             PUSH HL                          
11e1  11 07 00       LD DE,7                          
11e4  19             ADD HL,DE                        
11e5  7e             LD A,(HL)                        
11e6  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
11e9  e1             POP HL                           

sub_11ea:
11ea  11 ec 40       LD DE,0x40ec                     
11ed  06 00          LD B,0                           
11ef  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
11f2  4f             LD C,A                           
11f3  3e 8f          LD A,0x8f                        
11f5  12             LD (DE),A                        
11f6  13             INC DE                           
11f7  ed b0          LDIR                             
11f9  af             XOR A                            
11fa  c9             RET                              

L_11fb:
11fb  3e ff          LD A,0xff                        
11fd  c9             RET                              

sub_11fe:
11fe  3a 07 42       LD A,(GLYPH_WIDTH)               ; 4207
1201  3c             INC A                            

L_1202:
1202  21 41 40       LD HL,0x4041                     
1205  11 40 40       LD DE,FRAMEBUF                   ; 4040
1208  01 bc 00       LD BC,0xbc                       
120b  ed b0          LDIR                             
120d  f5             PUSH AF                          
120e  cd 16 12       CALL sub_1216                    ; 1216
1211  f1             POP AF                           
1212  3d             DEC A                            
1213  20 ed          JR nz,L_1202                     ; 1202
1215  c9             RET                              

sub_1216:
1216  21 40 40       LD HL,FRAMEBUF                   ; 4040
1219  11 0a 41       LD DE,0x410a                     
121c  01 56 00       LD BC,0x56                       
121f  3a 5e 43       LD A,(ROW_PHASE)                 ; 435e
1222  a7             AND A                            
1223  20 f1          JR nz,sub_1216                   ; 1216

L_1225:
1225  ed a0          LDI                              
1227  23             INC HL                           
1228  ea 25 12       JP pe,L_1225                     ; 1225
122b  3e ff          LD A,0xff                        
122d  32 5e 43       LD (ROW_PHASE),A                 ; 435e
1230  c9             RET                              

sub_1231:
1231  06 1c          LD B,0x1c                        

L_1233:
1233  c5             PUSH BC                          
1234  3e 20          LD A,0x20                        
1236  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1239  3e 05          LD A,5                           
123b  32 07 42       LD (GLYPH_WIDTH),A               ; 4207
123e  21 35 32       LD HL,0x3235                     
1241  cd ea 11       CALL sub_11ea                    ; 11ea
1244  cd fe 11       CALL sub_11fe                    ; 11fe
1247  c1             POP BC                           
1248  10 e9          DJNZ L_1233                      ; 1233
124a  c9             RET                              

L_124b:
124b  3a 5e 43       LD A,(ROW_PHASE)                 ; 435e
124e  a7             AND A                            
124f  20 0e          JR nz,L_125f                     ; 125f
1251  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
1254  f6 0f          OR 15                            
1256  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
1259  32 00 80       LD (CTRL_LATCH),A                ; 8000
125c  c3 a2 02       JP rx_consume                    ; 02a2

L_125f:
125f  3a 59 43       LD A,(DISP_ENABLE)               ; 4359
1262  a7             AND A                            
1263  ca b1 12       JP z,disp_next_row               ; 12b1
1266  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
1269  f6 0f          OR 15                            
126b  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
126e  32 00 80       LD (CTRL_LATCH),A                ; 8000

; ----------------------------------------------------------------
; disp_blank_row
; Send 0x8F (all off) to the current row
disp_blank_row:
1271  21 0a 41       LD HL,0x410a                     
1274  06 56          LD B,0x56                        
1276  0e 48          LD C,0x48                        
1278  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
127b  2f             CPL                              
127c  e6 07          AND 7                            
127e  3d             DEC A                            
127f  b1             OR C                             
1280  4f             LD C,A                           
1281  cb a9          RES 5,C                          
1283  3e 8f          LD A,0x8f                        
1285  ed 79          OUT (C),A                        
1287  ed b3          OTIR                             
1289  d3 80          OUT (PORT_STROBE),A              
128b  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
128e  2f             CPL                              
128f  e6 07          AND 7                            
1291  3d             DEC A                            
1292  20 02          JR nz,L_1296                     ; 1296
1294  3e 07          LD A,7                           

L_1296:
1296  4f             LD C,A                           
1297  3a 1f 42       LD A,(0x421f)                    
129a  b1             OR C                             
129b  e6 8f          AND 0x8f                         
129d  4f             LD C,A                           
129e  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
12a1  e6 70          AND 0x70                         
12a3  b1             OR C                             
12a4  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
12a7  32 00 80       LD (CTRL_LATCH),A                ; 8000
12aa  af             XOR A                            
12ab  32 59 43       LD (DISP_ENABLE),A               ; 4359
12ae  c3 0d 03       JP L_030d                        ; 030d

; ----------------------------------------------------------------
; disp_next_row
; ROW_INDEX = (ROW_INDEX+1) mod 7
disp_next_row:
12b1  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
12b4  4f             LD C,A                           
12b5  3c             INC A                            
12b6  32 45 42       LD (ROW_INDEX),A                 ; 4245
12b9  fe 07          CP 7                             
12bb  da 03 03       JP c,L_0303                      ; 0303
12be  3e 00          LD A,0                           
12c0  32 45 42       LD (ROW_INDEX),A                 ; 4245
12c3  32 5e 43       LD (ROW_PHASE),A                 ; 435e
12c6  c3 a2 02       JP rx_consume                    ; 02a2

; ----------------------------------------------------------------
; fx_setup_scroll
fx_setup_scroll:
12c9  cd 99 19       CALL clear_framebuf              ; 1999

sub_12cc:
12cc  21 96 40       LD HL,FRAMEBUF_ROW1              ; 4096
12cf  22 98 41       LD (FB_COLPTR),HL                ; 4198
12d2  21 56 00       LD HL,0x56                       
12d5  22 30 42       LD (DISP_FLAGS),HL               ; 4230
12d8  21 00 00       LD HL,0                          
12db  22 32 42       LD (FB_EXTRA_LEN),HL             ; 4232
12de  11 40 40       LD DE,FRAMEBUF                   ; 4040
12e1  ed 53 9b 41    LD (FB_COL),DE                   ; 419b
12e5  ed 53 10 42    LD (SEQ_PTR_SAVE),DE             ; 4210
12e9  2a fb 41       LD HL,(EFFECT_TMP2)              ; 41fb
12ec  19             ADD HL,DE                        
12ed  11 a2 41       LD DE,TXBUF                      ; 41a2
12f0  eb             EX DE,HL                         
12f1  c9             RET                              

; ----------------------------------------------------------------
; fx_scroll_in
fx_scroll_in:
12f2  3e ff          LD A,0xff                        
12f4  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
12f7  cd c9 12       CALL fx_setup_scroll             ; 12c9
12fa  3a 1c 42       LD A,(COL_COUNT)                 ; 421c
12fd  47             LD B,A                           

L_12fe:
12fe  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
1301  fe 06          CP 6                             
1303  20 f9          JR nz,L_12fe                     ; 12fe
1305  7e             LD A,(HL)                        
1306  12             LD (DE),A                        
1307  23             INC HL                           
1308  13             INC DE                           
1309  3e ff          LD A,0xff                        
130b  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
130e  3e 01          LD A,1                           
1310  32 44 42       LD (0x4244),A                    

L_1313:
1313  3a 44 42       LD A,(0x4244)                    
1316  a7             AND A                            
1317  20 fa          JR nz,L_1313                     ; 1313
1319  10 e3          DJNZ L_12fe                      ; 12fe
131b  3e 50          LD A,0x50                        
131d  32 44 42       LD (0x4244),A                    
1320  af             XOR A                            
1321  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
1324  c3 6e 0e       JP L_0e6e                        ; 0e6e

; ----------------------------------------------------------------
; fx_none
; effect handler: nothing (straight to render loop)
fx_none:
1327  c3 6e 0e       JP L_0e6e                        ; 0e6e

; ----------------------------------------------------------------
; fx_fill_frame
; fill FRAMEBUF with 0x8F then continue
fx_fill_frame:
132a  21 40 40       LD HL,FRAMEBUF                   ; 4040
132d  01 58 01       LD BC,0x0158                     

L_1330:
1330  36 8f          LD (HL),0x8f                     
1332  23             INC HL                           
1333  0b             DEC BC                           
1334  79             LD A,C                           
1335  b0             OR B                             
1336  20 f8          JR nz,L_1330                     ; 1330
1338  cd cc 12       CALL sub_12cc                    ; 12cc
133b  3a 1c 42       LD A,(COL_COUNT)                 ; 421c
133e  e5             PUSH HL                          
133f  26 00          LD H,0                           
1341  6f             LD L,A                           
1342  19             ADD HL,DE                        
1343  d1             POP DE                           
1344  eb             EX DE,HL                         
1345  4f             LD C,A                           
1346  06 00          LD B,0                           
1348  09             ADD HL,BC                        
1349  47             LD B,A                           
134a  04             INC B                            

L_134b:
134b  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
134e  fe 06          CP 6                             
1350  20 f9          JR nz,L_134b                     ; 134b
1352  7e             LD A,(HL)                        
1353  12             LD (DE),A                        
1354  2b             DEC HL                           
1355  1b             DEC DE                           
1356  3e ff          LD A,0xff                        
1358  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
135b  3e 01          LD A,1                           
135d  32 44 42       LD (0x4244),A                    

L_1360:
1360  3a 44 42       LD A,(0x4244)                    
1363  a7             AND A                            
1364  20 fa          JR nz,L_1360                     ; 1360
1366  10 e3          DJNZ L_134b                      ; 134b
1368  3e 50          LD A,0x50                        
136a  32 44 42       LD (0x4244),A                    
136d  af             XOR A                            
136e  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
1371  c3 6e 0e       JP L_0e6e                        ; 0e6e

; ----------------------------------------------------------------
; fx_scroll_copy
fx_scroll_copy:
1374  cd c9 12       CALL fx_setup_scroll             ; 12c9
1377  06 00          LD B,0                           
1379  3a 1c 42       LD A,(COL_COUNT)                 ; 421c
137c  4f             LD C,A                           
137d  ed b0          LDIR                             
137f  3e 50          LD A,0x50                        
1381  32 44 42       LD (0x4244),A                    
1384  af             XOR A                            
1385  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
1388  c3 6e 0e       JP L_0e6e                        ; 0e6e

; ----------------------------------------------------------------
; fx_138b
fx_138b:
138b  3e 00          LD A,0                           
138d  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
1390  cd c9 12       CALL fx_setup_scroll             ; 12c9
1393  3a 1c 42       LD A,(COL_COUNT)                 ; 421c
1396  47             LD B,A                           
1397  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
139a  fe 02          CP 2                             
139c  0e 80          LD C,0x80                        
139e  28 02          JR z,L_13a2                      ; 13a2
13a0  0e 01          LD C,1                           

L_13a2:
13a2  3e 08          LD A,8                           

L_13a4:
13a4  f5             PUSH AF                          
13a5  e5             PUSH HL                          
13a6  d5             PUSH DE                          
13a7  c5             PUSH BC                          

L_13a8:
13a8  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
13ab  fe 06          CP 6                             
13ad  20 f9          JR nz,L_13a8                     ; 13a8

L_13af:
13af  7e             LD A,(HL)                        
13b0  cb 7f          BIT 7,A                          
13b2  20 03          JR nz,L_13b7                     ; 13b7
13b4  a1             AND C                            
13b5  18 08          JR L_13bf                        ; 13bf

L_13b7:
13b7  79             LD A,C                           
13b8  fe ff          CP 0xff                          
13ba  3e 8f          LD A,0x8f                        
13bc  20 01          JR nz,L_13bf                     ; 13bf
13be  7e             LD A,(HL)                        

L_13bf:
13bf  12             LD (DE),A                        
13c0  23             INC HL                           
13c1  13             INC DE                           
13c2  10 eb          DJNZ L_13af                      ; 13af
13c4  3e ff          LD A,0xff                        
13c6  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
13c9  3e 03          LD A,3                           
13cb  32 44 42       LD (0x4244),A                    

L_13ce:
13ce  3a 44 42       LD A,(0x4244)                    
13d1  a7             AND A                            
13d2  20 fa          JR nz,L_13ce                     ; 13ce
13d4  c1             POP BC                           
13d5  d1             POP DE                           
13d6  e1             POP HL                           
13d7  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
13da  fe 02          CP 2                             
13dc  20 05          JR nz,L_13e3                     ; 13e3
13de  37             SCF                              
13df  cb 19          RR C                             
13e1  18 03          JR L_13e6                        ; 13e6

L_13e3:
13e3  37             SCF                              
13e4  cb 11          RL C                             

L_13e6:
13e6  f1             POP AF                           
13e7  3d             DEC A                            
13e8  20 ba          JR nz,L_13a4                     ; 13a4
13ea  3e 50          LD A,0x50                        
13ec  32 44 42       LD (0x4244),A                    
13ef  af             XOR A                            
13f0  32 0d 42       LD (EFFECT_PHASE),A              ; 420d
13f3  c3 6e 0e       JP L_0e6e                        ; 0e6e
13f6  db 0xc9

; ----------------------------------------------------------------
; store_clear_all
; Reset MSG_STORE: 100 empty channels D0..? then DA
store_clear_all:
13f7  3e d0          LD A,0xd0                        
13f9  0e d0          LD C,0xd0                        
13fb  21 e2 43       LD HL,MSG_STORE                  ; 43e2
13fe  06 64          LD B,0x64                        

L_1400:
1400  77             LD (HL),A                        
1401  23             INC HL                           
1402  71             LD (HL),C                        
1403  23             INC HL                           
1404  36 03          LD (HL),3                        
1406  23             INC HL                           
1407  0c             INC C                            
1408  57             LD D,A                           
1409  79             LD A,C                           
140a  fe da          CP 0xda                          
140c  20 03          JR nz,L_1411                     ; 1411
140e  0e d0          LD C,0xd0                        
1410  14             INC D                            

L_1411:
1411  7a             LD A,D                           
1412  10 ec          DJNZ L_1400                      ; 1400
1414  3e da          LD A,0xda                        
1416  77             LD (HL),A                        
1417  21 6b 42       LD HL,SEQ_LIST                   ; 426b
141a  36 da          LD (HL),0xda                     
141c  06 67          LD B,0x67                        

L_141e:
141e  23             INC HL                           
141f  36 ff          LD (HL),0xff                     
1421  10 fb          DJNZ L_141e                      ; 141e
1423  c9             RET                              

; ----------------------------------------------------------------
; ir_init
ir_init:
1424  3e ff          LD A,0xff                        
1426  32 23 42       LD (RX_MSGFLAG),A                ; 4223
1429  21 ef 5e       LD HL,0x5eef                     
142c  22 d8 43       LD (STORE_LIMIT),HL              ; 43d8
142f  22 34 42       LD (STORE_END),HL                ; 4234
1432  21 8b 5e       LD HL,0x5e8b                     
1435  22 de 43       LD (0x43de),HL                   
1438  21 e1 19       LD HL,0x19e1                     
143b  22 dc 43       LD (0x43dc),HL                   
143e  21 0e 1b       LD HL,0x1b0e                     
1441  22 da 43       LD (STORE_SIZE),HL               ; 43da
1444  21 ef 5e       LD HL,0x5eef                     
1447  36 da          LD (HL),0xda                     
1449  23             INC HL                           
144a  01 10 01       LD BC,0x0110                     

L_144d:
144d  36 00          LD (HL),0                        
144f  23             INC HL                           
1450  0b             DEC BC                           
1451  79             LD A,C                           
1452  b0             OR B                             
1453  20 f8          JR nz,L_144d                     ; 144d
1455  21 2b 16       LD HL,rx_st_wait_start           ; 162b
1458  22 5c 42       LD (RX_STATE),HL                 ; 425c
145b  21 2b 16       LD HL,rx_st_wait_start           ; 162b
145e  22 5e 42       LD (0x425e),HL                   
1461  af             XOR A                            
1462  32 4b 42       LD (RX_TICKS),A                  ; 424b
1465  32 4c 42       LD (0x424c),A                    
1468  c9             RET                              
1469  db 0xaa,"U"

; ----------------------------------------------------------------
; ir_init2
ir_init2:
146b  f5             PUSH AF                          
146c  af             XOR A                            
146d  32 77 43       LD (0x4377),A                    
1470  32 86 43       LD (IR_CODE),A                   ; 4386
1473  32 87 43       LD (0x4387),A                    
1476  32 84 43       LD (IR_KEY),A                    ; 4384
1479  32 80 43       LD (GEN_COUNTDOWN),A             ; 4380
147c  32 81 43       LD (0x4381),A                    
147f  32 7a 43       LD (TICK1_COUNT),A               ; 437a

; ----------------------------------------------------------------
; ir_reset
; IR decoder: reset state, wait for leader (port C0 bit1)
ir_reset:
1482  3e 82          LD A,0x82                        
1484  32 82 43       LD (IR_STATE_CNT),A              ; 4382
1487  3e 06          LD A,6                           
1489  32 83 43       LD (IR_BITCNT),A                 ; 4383
148c  af             XOR A                            
148d  32 85 43       LD (IR_SHIFT),A                  ; 4385
1490  e5             PUSH HL                          
1491  21 9a 14       LD HL,ir_st_idle                 ; 149a
1494  22 88 43       LD (TICK_VECTOR),HL              ; 4388
1497  e1             POP HL                           
1498  f1             POP AF                           
1499  c9             RET                              

; ----------------------------------------------------------------
; ir_st_idle
ir_st_idle:
149a  f5             PUSH AF                          
149b  db c0          IN A,(PORT_IN)                   
149d  cb 4f          BIT 1,A                          
149f  c2 82 14       JP nz,ir_reset                   ; 1482
14a2  3a 82 43       LD A,(IR_STATE_CNT)              ; 4382
14a5  3d             DEC A                            
14a6  c2 b1 14       JP nz,L_14b1                     ; 14b1
14a9  e5             PUSH HL                          
14aa  21 b6 14       LD HL,ir_st_leader               ; 14b6
14ad  22 88 43       LD (TICK_VECTOR),HL              ; 4388
14b0  e1             POP HL                           

L_14b1:
14b1  32 82 43       LD (IR_STATE_CNT),A              ; 4382
14b4  f1             POP AF                           
14b5  c9             RET                              

; ----------------------------------------------------------------
; ir_st_leader
ir_st_leader:
14b6  f5             PUSH AF                          
14b7  db c0          IN A,(PORT_IN)                   
14b9  cb 4f          BIT 1,A                          
14bb  ca cb 14       JP z,L_14cb                      ; 14cb
14be  e5             PUSH HL                          
14bf  21 cd 14       LD HL,ir_st_leader2              ; 14cd
14c2  22 88 43       LD (TICK_VECTOR),HL              ; 4388
14c5  e1             POP HL                           
14c6  3e 04          LD A,4                           
14c8  32 82 43       LD (IR_STATE_CNT),A              ; 4382

L_14cb:
14cb  f1             POP AF                           
14cc  c9             RET                              

; ----------------------------------------------------------------
; ir_st_leader2
ir_st_leader2:
14cd  f5             PUSH AF                          
14ce  db c0          IN A,(PORT_IN)                   
14d0  cb 4f          BIT 1,A                          
14d2  c2 e2 14       JP nz,L_14e2                     ; 14e2
14d5  e5             PUSH HL                          
14d6  21 e4 14       LD HL,ir_st_leader3              ; 14e4
14d9  22 88 43       LD (TICK_VECTOR),HL              ; 4388
14dc  e1             POP HL                           
14dd  3e 15          LD A,0x15                        
14df  32 82 43       LD (IR_STATE_CNT),A              ; 4382

L_14e2:
14e2  f1             POP AF                           
14e3  c9             RET                              

; ----------------------------------------------------------------
; ir_st_leader3
ir_st_leader3:
14e4  f5             PUSH AF                          
14e5  3a 82 43       LD A,(IR_STATE_CNT)              ; 4382
14e8  3d             DEC A                            
14e9  20 11          JR nz,L_14fc                     ; 14fc
14eb  db c0          IN A,(PORT_IN)                   
14ed  cb 4f          BIT 1,A                          
14ef  ca 82 14       JP z,ir_reset                    ; 1482
14f2  e5             PUSH HL                          
14f3  21 01 15       LD HL,ir_st_start                ; 1501
14f6  22 88 43       LD (TICK_VECTOR),HL              ; 4388
14f9  e1             POP HL                           
14fa  3e 03          LD A,3                           

L_14fc:
14fc  32 82 43       LD (IR_STATE_CNT),A              ; 4382
14ff  f1             POP AF                           
1500  c9             RET                              

; ----------------------------------------------------------------
; ir_st_start
ir_st_start:
1501  f5             PUSH AF                          
1502  3a 82 43       LD A,(IR_STATE_CNT)              ; 4382
1505  3d             DEC A                            
1506  c2 1a 15       JP nz,L_151a                     ; 151a
1509  db c0          IN A,(PORT_IN)                   
150b  cb 4f          BIT 1,A                          
150d  c2 82 14       JP nz,ir_reset                   ; 1482
1510  e5             PUSH HL                          
1511  21 1f 15       LD HL,ir_st_bits                 ; 151f
1514  22 88 43       LD (TICK_VECTOR),HL              ; 4388
1517  e1             POP HL                           
1518  3e 08          LD A,8                           

L_151a:
151a  32 82 43       LD (IR_STATE_CNT),A              ; 4382
151d  f1             POP AF                           
151e  c9             RET                              

; ----------------------------------------------------------------
; ir_st_bits
; sample a data bit (port C0 bit1) into IR_SHIFT every 4 ticks
ir_st_bits:
151f  f5             PUSH AF                          
1520  3a 82 43       LD A,(IR_STATE_CNT)              ; 4382
1523  3d             DEC A                            
1524  ca 40 15       JP z,L_1540                      ; 1540
1527  fe 04          CP 4                             
1529  c2 5d 15       JP nz,L_155d                     ; 155d
152c  32 82 43       LD (IR_STATE_CNT),A              ; 4382
152f  e5             PUSH HL                          
1530  21 85 43       LD HL,IR_SHIFT                   ; 4385
1533  cb 0e          RRC (HL)                         
1535  db c0          IN A,(PORT_IN)                   
1537  e6 02          AND 2                            
1539  b6             OR (HL)                          
153a  32 85 43       LD (IR_SHIFT),A                  ; 4385
153d  e1             POP HL                           
153e  f1             POP AF                           
153f  c9             RET                              

L_1540:
1540  e5             PUSH HL                          
1541  3a 85 43       LD A,(IR_SHIFT)                  ; 4385
1544  2f             CPL                              
1545  e6 02          AND 2                            
1547  6f             LD L,A                           
1548  db c0          IN A,(PORT_IN)                   
154a  e6 02          AND 2                            
154c  bd             CP L                             
154d  e1             POP HL                           
154e  c2 82 14       JP nz,ir_reset                   ; 1482
1551  3a 83 43       LD A,(IR_BITCNT)                 ; 4383
1554  3d             DEC A                            
1555  32 83 43       LD (IR_BITCNT),A                 ; 4383
1558  ca 62 15       JP z,L_1562                      ; 1562
155b  3e 08          LD A,8                           

L_155d:
155d  32 82 43       LD (IR_STATE_CNT),A              ; 4382
1560  f1             POP AF                           
1561  c9             RET                              

L_1562:
1562  3a 85 43       LD A,(IR_SHIFT)                  ; 4385
1565  0f             RRCA                             
1566  0f             RRCA                             
1567  0f             RRCA                             
1568  0f             RRCA                             
1569  f6 80          OR 0x80                          
156b  32 86 43       LD (IR_CODE),A                   ; 4386
156e  c3 82 14       JP ir_reset                      ; 1482

; ----------------------------------------------------------------
; tx_send_byte
; Queue byte A for bit-banged transmission; blocks until the previous byte is out
tx_send_byte:
1571  e5             PUSH HL                          
1572  d5             PUSH DE                          

L_1573:
1573  cd 7c 15       CALL tx_try_queue                ; 157c
1576  a7             AND A                            
1577  20 fa          JR nz,L_1573                     ; 1573
1579  d1             POP DE                           
157a  e1             POP HL                           
157b  c9             RET                              

; ----------------------------------------------------------------
; tx_try_queue
tx_try_queue:
157c  21 4d 43       LD HL,TX_STATUS                  ; 434d
157f  cb 4e          BIT 1,(HL)                       
1581  c0             RET nz                           
1582  32 4a 43       LD (TX_PENDING),A                ; 434a
1585  cb ce          SET 1,(HL)                       
1587  af             XOR A                            
1588  c9             RET                              

; ----------------------------------------------------------------
; tx_bit_engine
; Called every 6 ticks: shifts TX_SHIFT out on CTRL_LATCH bit 4 (1=start/space, 0=mark). Bit times
; from TX_TIMING table (4,4,5 ticks); state 9 = stop bits (10 ticks)
tx_bit_engine:
1589  21 4d 43       LD HL,TX_STATUS                  ; 434d
158c  cb 46          BIT 0,(HL)                       
158e  20 29          JR nz,L_15b9                     ; 15b9
1590  cb 4e          BIT 1,(HL)                       
1592  c8             RET z                            
1593  3a 4a 43       LD A,(TX_PENDING)                ; 434a
1596  32 4c 43       LD (TX_SHIFT),A                  ; 434c
1599  36 01          LD (HL),1                        
159b  af             XOR A                            
159c  32 48 43       LD (TX_BITIDX),A                 ; 4348
159f  3c             INC A                            
15a0  32 49 43       LD (TX_BITMASK),A                ; 4349
15a3  21 54 16       LD HL,TX_TIMING                  ; 1654
15a6  22 4e 43       LD (TX_TIMING_PTR),HL            ; 434e
15a9  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
15ac  f6 10          OR 0x10                          
15ae  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
15b1  32 00 80       LD (CTRL_LATCH),A                ; 8000
15b4  7e             LD A,(HL)                        
15b5  32 4b 43       LD (TX_TICKS),A                  ; 434b
15b8  c9             RET                              

L_15b9:
15b9  21 4b 43       LD HL,TX_TICKS                   ; 434b
15bc  35             DEC (HL)                         
15bd  c0             RET nz                           
15be  21 48 43       LD HL,TX_BITIDX                  ; 4348
15c1  34             INC (HL)                         
15c2  7e             LD A,(HL)                        
15c3  fe 09          CP 9                             
15c5  28 2b          JR z,L_15f2                      ; 15f2
15c7  fe 0a          CP 10                            
15c9  28 38          JR z,L_1603                      ; 1603
15cb  21 49 43       LD HL,TX_BITMASK                 ; 4349
15ce  5e             LD E,(HL)                        
15cf  cb 26          SLA (HL)                         
15d1  3a 4c 43       LD A,(TX_SHIFT)                  ; 434c
15d4  a3             AND E                            
15d5  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
15d8  20 04          JR nz,L_15de                     ; 15de
15da  f6 10          OR 0x10                          
15dc  18 02          JR L_15e0                        ; 15e0

L_15de:
15de  e6 ef          AND 0xef                         

L_15e0:
15e0  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
15e3  32 00 80       LD (CTRL_LATCH),A                ; 8000
15e6  2a 4e 43       LD HL,(TX_TIMING_PTR)            ; 434e
15e9  23             INC HL                           
15ea  22 4e 43       LD (TX_TIMING_PTR),HL            ; 434e
15ed  7e             LD A,(HL)                        
15ee  32 4b 43       LD (TX_TICKS),A                  ; 434b
15f1  c9             RET                              

L_15f2:
15f2  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
15f5  e6 ef          AND 0xef                         
15f7  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
15fa  32 00 80       LD (CTRL_LATCH),A                ; 8000
15fd  3e 0a          LD A,10                          
15ff  32 4b 43       LD (TX_TICKS),A                  ; 434b
1602  c9             RET                              

L_1603:
1603  21 4d 43       LD HL,TX_STATUS                  ; 434d
1606  cb 86          RES 0,(HL)                       
1608  c9             RET                              

; ----------------------------------------------------------------
; rx_bit_engine
; Called every 6 ticks: bit-banged receiver state machine on PORT_IN bit 3 (1 = space). Uses RX_TIMING
; table; assembled bytes go to RX_FIFO (8 deep, RX_COUNT)
rx_bit_engine:
1609  3a 55 42       LD A,(RX_COUNT)                  ; 4255
160c  fe 08          CP 8                             
160e  20 0c          JR nz,L_161c                     ; 161c
1610  21 2b 16       LD HL,rx_st_wait_start           ; 162b
1613  22 5c 42       LD (RX_STATE),HL                 ; 425c
1616  3e 00          LD A,0                           
1618  32 4b 42       LD (RX_TICKS),A                  ; 424b
161b  c9             RET                              

L_161c:
161c  3a 4b 42       LD A,(RX_TICKS)                  ; 424b
161f  a7             AND A                            
1620  28 05          JR z,L_1627                      ; 1627
1622  3d             DEC A                            
1623  32 4b 42       LD (RX_TICKS),A                  ; 424b
1626  c0             RET nz                           

L_1627:
1627  2a 5c 42       LD HL,(RX_STATE)                 ; 425c
162a  e9             JP (HL)                          

; ----------------------------------------------------------------
; rx_st_wait_start
rx_st_wait_start:
162b  db c0          IN A,(PORT_IN)                   
162d  cb 5f          BIT 3,A                          
162f  c8             RET z                            
1630  21 5e 16       LD HL,rx_st_sample_bit           ; 165e
1633  22 5c 42       LD (RX_STATE),HL                 ; 425c
1636  21 4a 16       LD HL,RX_TIMING                  ; 164a
1639  22 56 42       LD (RX_TIMING_PTR),HL            ; 4256
163c  7e             LD A,(HL)                        
163d  32 4b 42       LD (RX_TICKS),A                  ; 424b
1640  3e 01          LD A,1                           
1642  32 46 42       LD (RX_BITMASK),A                ; 4246
1645  af             XOR A                            
1646  32 49 42       LD (RX_SHIFT),A                  ; 4249
1649  c9             RET                              

; ---------------- data: RX_TIMING (164a-1653) ticks between RX bit samples (start,8 data,stop)
RX_TIMING:
        db 0x06,0x04,0x05,0x04,0x04,0x05,0x04,0x04,0x05,0x04                   ; 164a

; ---------------- data: TX_TIMING (1654-165d) ticks per TX bit: start,8 data (4,4,5 pattern = 300 baud @ ~1300 Hz), stop = 10
TX_TIMING:
        db 0x04,0x04,0x05,0x04,0x04,0x05,0x04,0x04,0x05,0x0a                   ; 1654

; ----------------------------------------------------------------
; rx_st_sample_bit
rx_st_sample_bit:
165e  db c0          IN A,(PORT_IN)                   
1660  cb 5f          BIT 3,A                          
1662  3e ff          LD A,0xff                        
1664  28 01          JR z,L_1667                      ; 1667
1666  af             XOR A                            

L_1667:
1667  5f             LD E,A                           
1668  3a 49 42       LD A,(RX_SHIFT)                  ; 4249
166b  57             LD D,A                           
166c  3a 46 42       LD A,(RX_BITMASK)                ; 4246
166f  f5             PUSH AF                          
1670  2f             CPL                              
1671  a2             AND D                            
1672  57             LD D,A                           
1673  f1             POP AF                           
1674  a3             AND E                            
1675  b2             OR D                             
1676  32 49 42       LD (RX_SHIFT),A                  ; 4249
1679  2a 56 42       LD HL,(RX_TIMING_PTR)            ; 4256
167c  23             INC HL                           
167d  22 56 42       LD (RX_TIMING_PTR),HL            ; 4256
1680  7e             LD A,(HL)                        
1681  32 4b 42       LD (RX_TICKS),A                  ; 424b
1684  3a 46 42       LD A,(RX_BITMASK)                ; 4246
1687  cb 27          SLA A                            
1689  32 46 42       LD (RX_BITMASK),A                ; 4246
168c  d0             RET nc                           
168d  21 94 16       LD HL,rx_st_stop_bit             ; 1694
1690  22 5c 42       LD (RX_STATE),HL                 ; 425c
1693  c9             RET                              

; ----------------------------------------------------------------
; rx_st_stop_bit
; stop bit must read as mark else byte is dropped
rx_st_stop_bit:
1694  db c0          IN A,(PORT_IN)                   
1696  cb 5f          BIT 3,A                          
1698  20 1d          JR nz,L_16b7                     ; 16b7
169a  3a 49 42       LD A,(RX_SHIFT)                  ; 4249
169d  a7             AND A                            
169e  3a 55 42       LD A,(RX_COUNT)                  ; 4255
16a1  fe 08          CP 8                             
16a3  28 12          JR z,L_16b7                      ; 16b7
16a5  e6 07          AND 7                            
16a7  21 4d 42       LD HL,RX_FIFO                    ; 424d
16aa  5f             LD E,A                           
16ab  16 00          LD D,0                           
16ad  19             ADD HL,DE                        
16ae  3a 49 42       LD A,(RX_SHIFT)                  ; 4249
16b1  77             LD (HL),A                        
16b2  7b             LD A,E                           
16b3  3c             INC A                            
16b4  32 55 42       LD (RX_COUNT),A                  ; 4255

L_16b7:
16b7  af             XOR A                            
16b8  32 4b 42       LD (RX_TICKS),A                  ; 424b
16bb  32 49 42       LD (RX_SHIFT),A                  ; 4249
16be  21 2b 16       LD HL,rx_st_wait_start           ; 162b
16c1  22 5c 42       LD (RX_STATE),HL                 ; 425c
16c4  c9             RET                              

; ----------------------------------------------------------------
; rx_fifo_get
; Pop one byte from RX_FIFO into RX_BYTE. Returns NC with A=byte, or C if empty
rx_fifo_get:
16c5  3a 55 42       LD A,(RX_COUNT)                  ; 4255
16c8  a7             AND A                            
16c9  28 1e          JR z,L_16e9                      ; 16e9
16cb  21 4d 42       LD HL,RX_FIFO                    ; 424d
16ce  7e             LD A,(HL)                        
16cf  32 28 42       LD (RX_BYTE),A                   ; 4228
16d2  3a 55 42       LD A,(RX_COUNT)                  ; 4255
16d5  01 08 00       LD BC,8                          
16d8  21 4e 42       LD HL,0x424e                     
16db  11 4d 42       LD DE,RX_FIFO                    ; 424d
16de  ed b0          LDIR                             
16e0  3d             DEC A                            
16e1  32 55 42       LD (RX_COUNT),A                  ; 4255
16e4  3a 28 42       LD A,(RX_BYTE)                   ; 4228
16e7  b7             OR A                             
16e8  c9             RET                              

L_16e9:
16e9  af             XOR A                            
16ea  32 28 42       LD (RX_BYTE),A                   ; 4228
16ed  37             SCF                              
16ee  c9             RET                              

; ----------------------------------------------------------------
; pkt_feed_byte
; Feed RX_BYTE to the packet parser state in PKT_VECTOR
pkt_feed_byte:
16ef  3a 28 42       LD A,(RX_BYTE)                   ; 4228
16f2  2a f5 5f       LD HL,(PKT_VECTOR)               ; 5ff5
16f5  e9             JP (HL)                          

; ----------------------------------------------------------------
; pkt_st_addr
; store address byte -> PKT_ADDR
pkt_st_addr:
16f6  32 f7 5f       LD (PKT_ADDR),A                  ; 5ff7
16f9  21 00 17       LD HL,pkt_st_flag                ; 1700
16fc  22 f5 5f       LD (PKT_VECTOR),HL               ; 5ff5
16ff  c9             RET                              

; ----------------------------------------------------------------
; pkt_st_flag
; store 3rd header byte -> PKT_FLAG (0x80 from PC)
pkt_st_flag:
1700  32 f3 5f       LD (PKT_FLAG),A                  ; 5ff3
1703  21 0a 17       LD HL,pkt_st_len                 ; 170a
1706  22 f5 5f       LD (PKT_VECTOR),HL               ; 5ff5
1709  c9             RET                              

; ----------------------------------------------------------------
; pkt_st_len
; store length; reset checksum & PKT_PTR=PKT_BUF; len 0 goes straight to checksum state
pkt_st_len:
170a  32 f4 5f       LD (PKT_LEN),A                   ; 5ff4
170d  a7             AND A                            
170e  21 2a 17       LD HL,pkt_st_data                ; 172a
1711  20 03          JR nz,L_1716                     ; 1716
1713  21 4a 17       LD HL,pkt_st_cksum               ; 174a

L_1716:
1716  22 f5 5f       LD (PKT_VECTOR),HL               ; 5ff5
1719  af             XOR A                            
171a  32 f2 5f       LD (PKT_CKSUM),A                 ; 5ff2
171d  21 f1 5e       LD HL,PKT_BUF                    ; 5ef1
1720  22 f8 5f       LD (PKT_PTR),HL                  ; 5ff8
1723  3a f4 5f       LD A,(PKT_LEN)                   ; 5ff4
1726  32 fa 5f       LD (PKT_REMAIN),A                ; 5ffa
1729  c9             RET                              

; ----------------------------------------------------------------
; pkt_st_data
; store payload byte, PKT_CKSUM += byte
pkt_st_data:
172a  2a f8 5f       LD HL,(PKT_PTR)                  ; 5ff8
172d  77             LD (HL),A                        
172e  3a f2 5f       LD A,(PKT_CKSUM)                 ; 5ff2
1731  86             ADD A,(HL)                       
1732  32 f2 5f       LD (PKT_CKSUM),A                 ; 5ff2
1735  3a fa 5f       LD A,(PKT_REMAIN)                ; 5ffa
1738  3d             DEC A                            
1739  28 08          JR z,L_1743                      ; 1743
173b  32 fa 5f       LD (PKT_REMAIN),A                ; 5ffa
173e  23             INC HL                           
173f  22 f8 5f       LD (PKT_PTR),HL                  ; 5ff8
1742  c9             RET                              

L_1743:
1743  21 4a 17       LD HL,pkt_st_cksum               ; 174a
1746  22 f5 5f       LD (PKT_VECTOR),HL               ; 5ff5
1749  c9             RET                              

; ----------------------------------------------------------------
; pkt_st_cksum
; E = computed - received. Broadcast (0x2A): no reply. Own address: send ACK 06 / NAK 15. If OK and
; len>0 set PKT_READY (PKT_FLAG==0x80 -> process immediately)
pkt_st_cksum:
174a  5f             LD E,A                           
174b  3a f2 5f       LD A,(PKT_CKSUM)                 ; 5ff2
174e  93             SUB E                            
174f  5f             LD E,A                           
1750  3a f7 5f       LD A,(PKT_ADDR)                  ; 5ff7
1753  fe 2a          CP 0x2a                          
1755  28 12          JR z,L_1769                      ; 1769
1757  57             LD D,A                           
1758  3a cb 43       LD A,(MY_ADDRESS)                ; 43cb
175b  ba             CP D                             
175c  20 27          JR nz,L_1785                     ; 1785
175e  7b             LD A,E                           
175f  a7             AND A                            
1760  3e 06          LD A,6                           
1762  28 02          JR z,L_1766                      ; 1766
1764  3e 15          LD A,0x15                        

L_1766:
1766  cd 71 15       CALL tx_send_byte                ; 1571

L_1769:
1769  7b             LD A,E                           
176a  a7             AND A                            
176b  20 18          JR nz,L_1785                     ; 1785
176d  3a f4 5f       LD A,(PKT_LEN)                   ; 5ff4
1770  a7             AND A                            
1771  28 12          JR z,L_1785                      ; 1785
1773  3e ff          LD A,0xff                        
1775  32 f0 5e       LD (PKT_READY),A                 ; 5ef0
1778  af             XOR A                            
1779  32 f1 5f       LD (PKT_STATE),A                 ; 5ff1
177c  3a f3 5f       LD A,(PKT_FLAG)                  ; 5ff3
177f  fe 80          CP 0x80                          
1781  ca 68 2a       JP z,pkt_process                 ; 2a68
1784  c9             RET                              

L_1785:
1785  af             XOR A                            
1786  32 f0 5e       LD (PKT_READY),A                 ; 5ef0
1789  32 f1 5f       LD (PKT_STATE),A                 ; 5ff1
178c  c9             RET                              

; ----------------------------------------------------------------
; tx_send_frame
; Send reply frame: B1, MY_ADDRESS, then (HL)=len, len bytes, 8-bit sum of the data bytes
tx_send_frame:
178d  f5             PUSH AF                          
178e  c5             PUSH BC                          
178f  d5             PUSH DE                          
1790  e5             PUSH HL                          
1791  dd e5          PUSH IX                          
1793  fd e5          PUSH IY                          
1795  3e b1          LD A,0xb1                        
1797  cd 71 15       CALL tx_send_byte                ; 1571
179a  3a cb 43       LD A,(MY_ADDRESS)                ; 43cb
179d  cd 71 15       CALL tx_send_byte                ; 1571
17a0  1e 00          LD E,0                           
17a2  7e             LD A,(HL)                        
17a3  47             LD B,A                           
17a4  cd 71 15       CALL tx_send_byte                ; 1571
17a7  23             INC HL                           

L_17a8:
17a8  7e             LD A,(HL)                        
17a9  83             ADD A,E                          
17aa  5f             LD E,A                           
17ab  7e             LD A,(HL)                        
17ac  cd 71 15       CALL tx_send_byte                ; 1571
17af  23             INC HL                           
17b0  10 f6          DJNZ L_17a8                      ; 17a8
17b2  7b             LD A,E                           
17b3  cd 71 15       CALL tx_send_byte                ; 1571
17b6  fd e1          POP IY                           
17b8  dd e1          POP IX                           
17ba  e1             POP HL                           
17bb  d1             POP DE                           
17bc  c1             POP BC                           
17bd  f1             POP AF                           
17be  c9             RET                              

; ----------------------------------------------------------------
; rx_cmd_check
rx_cmd_check:
17bf  cd cc 17       CALL query_dispatch              ; 17cc
17c2  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
17c5  a7             AND A                            
17c6  c0             RET nz                           
17c7  e1             POP HL                           
17c8  e1             POP HL                           
17c9  c3 d5 1a       JP L_1ad5                        ; 1ad5

; ----------------------------------------------------------------
; query_dispatch
; 0xB4 + '0'..'3' query handlers
query_dispatch:
17cc  3a 23 42       LD A,(RX_MSGFLAG)                ; 4223
17cf  a7             AND A                            
17d0  c8             RET z                            
17d1  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
17d4  fe b4          CP 0xb4                          
17d6  c0             RET nz                           
17d7  cd 09 23       CALL menu_getchar                ; 2309
17da  fe 30          CP 0x30                          
17dc  ca f0 17       JP z,query_0_romid               ; 17f0
17df  fe 31          CP 0x31                          
17e1  ca 32 18       JP z,query_1_memory              ; 1832
17e4  fe 32          CP 0x32                          
17e6  ca ef 17       JP z,sub_17ef                    ; 17ef
17e9  fe 33          CP 0x33                          
17eb  ca 70 18       JP z,query_3_dump                ; 1870
17ee  c9             RET                              

sub_17ef:
17ef  c9             RET                              

; ----------------------------------------------------------------
; query_0_romid
; B4 '0': reply with 16-byte ROM ID string
query_0_romid:
17f0  f5             PUSH AF                          
17f1  c5             PUSH BC                          
17f2  d5             PUSH DE                          
17f3  e5             PUSH HL                          
17f4  dd e5          PUSH IX                          
17f6  fd e5          PUSH IY                          
17f8  21 a2 41       LD HL,TXBUF                      ; 41a2
17fb  36 10          LD (HL),0x10                     
17fd  23             INC HL                           
17fe  11 48 00       LD DE,0x48                       
1801  01 03 00       LD BC,3                          
1804  eb             EX DE,HL                         
1805  ed b0          LDIR                             
1807  21 4b 00       LD HL,0x4b                       
180a  01 03 00       LD BC,3                          
180d  ed b0          LDIR                             
180f  21 4e 00       LD HL,0x4e                       
1812  01 06 00       LD BC,6                          
1815  ed b0          LDIR                             
1817  21 54 00       LD HL,0x54                       
181a  01 04 00       LD BC,4                          
181d  ed b0          LDIR                             
181f  21 a2 41       LD HL,TXBUF                      ; 41a2
1822  cd 8d 17       CALL tx_send_frame               ; 178d
1825  af             XOR A                            
1826  32 25 42       LD (RX_LASTCMD),A                ; 4225
1829  fd e1          POP IY                           
182b  dd e1          POP IX                           
182d  e1             POP HL                           
182e  d1             POP DE                           
182f  c1             POP BC                           
1830  f1             POP AF                           
1831  c9             RET                              

; ----------------------------------------------------------------
; query_1_memory
; B4 '1': reply with two 5-digit ASCII numbers (STORE_SIZE, free bytes)
query_1_memory:
1832  f5             PUSH AF                          
1833  c5             PUSH BC                          
1834  d5             PUSH DE                          
1835  e5             PUSH HL                          
1836  dd e5          PUSH IX                          
1838  fd e5          PUSH IY                          
183a  cd 38 1c       CALL store_finalize              ; 1c38
183d  21 a2 41       LD HL,TXBUF                      ; 41a2
1840  36 0a          LD (HL),10                       
1842  23             INC HL                           
1843  e5             PUSH HL                          
1844  dd e1          POP IX                           
1846  2a da 43       LD HL,(STORE_SIZE)               ; 43da
1849  cd c7 18       CALL bin_to_dec5                 ; 18c7
184c  dd e5          PUSH IX                          
184e  2a d8 43       LD HL,(STORE_LIMIT)              ; 43d8
1851  ed 5b 34 42    LD DE,(STORE_END)                ; 4234
1855  b7             OR A                             
1856  ed 52          SBC HL,DE                        
1858  dd e1          POP IX                           
185a  cd c7 18       CALL bin_to_dec5                 ; 18c7
185d  21 a2 41       LD HL,TXBUF                      ; 41a2
1860  cd 8d 17       CALL tx_send_frame               ; 178d
1863  af             XOR A                            
1864  32 25 42       LD (RX_LASTCMD),A                ; 4225
1867  fd e1          POP IY                           
1869  dd e1          POP IX                           
186b  e1             POP HL                           
186c  d1             POP DE                           
186d  c1             POP BC                           
186e  f1             POP AF                           
186f  c9             RET                              

; ----------------------------------------------------------------
; query_3_dump
; B4 '3': reply B1 addr <5-digit len> <MSG_STORE up to 0xDA> <cksum of data>
query_3_dump:
1870  f5             PUSH AF                          
1871  c5             PUSH BC                          
1872  d5             PUSH DE                          
1873  e5             PUSH HL                          
1874  dd e5          PUSH IX                          
1876  fd e5          PUSH IY                          
1878  3e b1          LD A,0xb1                        
187a  cd 71 15       CALL tx_send_byte                ; 1571
187d  3a cb 43       LD A,(MY_ADDRESS)                ; 43cb
1880  cd 71 15       CALL tx_send_byte                ; 1571
1883  2a 34 42       LD HL,(STORE_END)                ; 4234
1886  23             INC HL                           
1887  11 e2 43       LD DE,MSG_STORE                  ; 43e2
188a  b7             OR A                             
188b  ed 52          SBC HL,DE                        
188d  dd 21 a2 41    LD IX,TXBUF                      ; 41a2
1891  cd c7 18       CALL bin_to_dec5                 ; 18c7
1894  21 a2 41       LD HL,TXBUF                      ; 41a2
1897  06 05          LD B,5                           

L_1899:
1899  7e             LD A,(HL)                        
189a  cd 71 15       CALL tx_send_byte                ; 1571
189d  23             INC HL                           
189e  10 f9          DJNZ L_1899                      ; 1899
18a0  21 e2 43       LD HL,MSG_STORE                  ; 43e2
18a3  1e 00          LD E,0                           

L_18a5:
18a5  7e             LD A,(HL)                        
18a6  83             ADD A,E                          
18a7  5f             LD E,A                           
18a8  7e             LD A,(HL)                        
18a9  cd 71 15       CALL tx_send_byte                ; 1571
18ac  7e             LD A,(HL)                        
18ad  fe da          CP 0xda                          
18af  ca b6 18       JP z,L_18b6                      ; 18b6
18b2  23             INC HL                           
18b3  c3 a5 18       JP L_18a5                        ; 18a5

L_18b6:
18b6  7b             LD A,E                           
18b7  cd 71 15       CALL tx_send_byte                ; 1571
18ba  af             XOR A                            
18bb  32 25 42       LD (RX_LASTCMD),A                ; 4225
18be  fd e1          POP IY                           
18c0  dd e1          POP IX                           
18c2  e1             POP HL                           
18c3  d1             POP DE                           
18c4  c1             POP BC                           
18c5  f1             POP AF                           
18c6  c9             RET                              

; ----------------------------------------------------------------
; bin_to_dec5
; HL -> 5 ASCII digits at (IX) using table 10000,1000,100,10,1
bin_to_dec5:
18c7  fd 21 e8 18    LD IY,DEC_TABLE                  ; 18e8

sub_18cb:
18cb  06 2f          LD B,0x2f                        
18cd  fd 5e 00       LD E,(IY)                        
18d0  fd 56 01       LD D,(IY+1)                      
18d3  cb 7a          BIT 7,D                          
18d5  c0             RET nz                           

L_18d6:
18d6  04             INC B                            
18d7  b7             OR A                             
18d8  ed 52          SBC HL,DE                        
18da  30 fa          JR nc,L_18d6                     ; 18d6
18dc  19             ADD HL,DE                        
18dd  dd 70 00       LD (IX),B                        
18e0  dd 23          INC IX                           
18e2  fd 23          INC IY                           
18e4  fd 23          INC IY                           
18e6  18 e3          JR sub_18cb                      ; 18cb

; ---------------- data: DEC_TABLE (18e8-18f3) 10000,1000,100,10,1,-1 for bin_to_dec5
DEC_TABLE:
        dw 0x2710
        dw 0x03e8
        dw 0x0064
        dw 0x000a
        dw 0x0001
        dw 0xffff

; ----------------------------------------------------------------
; clock_tick
; NMI: NMI_COUNT to NMI_PER_SEC -> seconds -> minutes -> hours (12h, CLK_PM toggles)
clock_tick:
18f4  3a 06 42       LD A,(CLK_RUN)                   ; 4206
18f7  a7             AND A                            
18f8  c8             RET z                            
18f9  3a 3c 43       LD A,(NMI_COUNT)                 ; 433c
18fc  3c             INC A                            
18fd  32 3c 43       LD (NMI_COUNT),A                 ; 433c
1900  21 5d 43       LD HL,NMI_PER_SEC                ; 435d
1903  be             CP (HL)                          
1904  c0             RET nz                           
1905  3e 00          LD A,0                           
1907  32 3c 43       LD (NMI_COUNT),A                 ; 433c
190a  21 04 42       LD HL,CLK_SEC                    ; 4204
190d  34             INC (HL)                         
190e  7e             LD A,(HL)                        
190f  fe 3c          CP 0x3c                          
1911  c0             RET nz                           
1912  36 00          LD (HL),0                        
1914  2b             DEC HL                           
1915  34             INC (HL)                         
1916  7e             LD A,(HL)                        
1917  fe 0a          CP 10                            
1919  c0             RET nz                           
191a  36 00          LD (HL),0                        
191c  2b             DEC HL                           
191d  34             INC (HL)                         
191e  7e             LD A,(HL)                        
191f  fe 06          CP 6                             
1921  c0             RET nz                           
1922  36 00          LD (HL),0                        
1924  2b             DEC HL                           
1925  34             INC (HL)                         
1926  7e             LD A,(HL)                        
1927  fe 0a          CP 10                            
1929  20 09          JR nz,L_1934                     ; 1934
192b  36 00          LD (HL),0                        
192d  2b             DEC HL                           
192e  7e             LD A,(HL)                        
192f  3c             INC A                            
1930  e6 01          AND 1                            
1932  77             LD (HL),A                        
1933  c9             RET                              

L_1934:
1934  2b             DEC HL                           
1935  fe 03          CP 3                             
1937  ca 4a 19       JP z,L_194a                      ; 194a
193a  fe 02          CP 2                             
193c  c0             RET nz                           
193d  7e             LD A,(HL)                        
193e  a7             AND A                            
193f  c8             RET z                            
1940  3a 05 42       LD A,(CLK_PM)                    ; 4205
1943  3c             INC A                            
1944  e6 01          AND 1                            
1946  32 05 42       LD (CLK_PM),A                    ; 4205
1949  c9             RET                              

L_194a:
194a  7e             LD A,(HL)                        
194b  a7             AND A                            
194c  c8             RET z                            
194d  af             XOR A                            
194e  77             LD (HL),A                        
194f  3c             INC A                            
1950  23             INC HL                           
1951  77             LD (HL),A                        
1952  c9             RET                              

; ----------------------------------------------------------------
; demo_scroll
; scroll a space 14 times (used when blanking)
demo_scroll:
1953  06 0e          LD B,14                          
1955  3e 00          LD A,0                           
1957  32 39 43       LD (FONT_MODE),A                 ; 4339

L_195a:
195a  3e 20          LD A,0x20                        
195c  32 0e 42       LD (CUR_CHAR),A                  ; 420e
195f  c5             PUSH BC                          
1960  cd 7a 07       CALL sub_077a                    ; 077a
1963  cd 44 0e       CALL effect_step                 ; 0e44
1966  c1             POP BC                           
1967  10 f1          DJNZ L_195a                      ; 195a
1969  c9             RET                              

; ----------------------------------------------------------------
; keypad_scan
; 8x8 matrix scan: row select via CTRL_LATCH high nibble, read PORT_IN bit 3; result -> RX_BYTE
keypad_scan:
196a  2e 00          LD L,0                           
196c  26 f0          LD H,0xf0                        
196e  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
1971  e6 8f          AND 0x8f                         
1973  5f             LD E,A                           
1974  06 08          LD B,8                           

L_1976:
1976  7c             LD A,H                           
1977  c6 10          ADD A,0x10                       
1979  67             LD H,A                           
197a  b3             OR E                             
197b  32 00 80       LD (CTRL_LATCH),A                ; 8000
197e  db c0          IN A,(PORT_IN)                   
1980  cb 5f          BIT 3,A                          
1982  28 09          JR z,L_198d                      ; 198d
1984  3e 08          LD A,8                           
1986  85             ADD A,L                          
1987  6f             LD L,A                           
1988  10 ec          DJNZ L_1976                      ; 1976
198a  af             XOR A                            
198b  18 07          JR L_1994                        ; 1994

L_198d:
198d  e6 07          AND 7                            
198f  85             ADD A,L                          
1990  20 02          JR nz,L_1994                     ; 1994
1992  3e 1e          LD A,0x1e                        

L_1994:
1994  32 28 42       LD (RX_BYTE),A                   ; 4228
1997  a7             AND A                            
1998  c9             RET                              

; ----------------------------------------------------------------
; clear_framebuf
; FRAMEBUF (344 bytes) = 0x80
clear_framebuf:
1999  e5             PUSH HL                          
199a  c5             PUSH BC                          
199b  21 40 40       LD HL,FRAMEBUF                   ; 4040
199e  01 58 01       LD BC,0x0158                     

L_19a1:
19a1  36 80          LD (HL),0x80                     
19a3  23             INC HL                           
19a4  0b             DEC BC                           
19a5  79             LD A,C                           
19a6  b0             OR B                             
19a7  20 f8          JR nz,L_19a1                     ; 19a1
19a9  c1             POP BC                           
19aa  e1             POP HL                           
19ab  c9             RET                              

; ----------------------------------------------------------------
; clear_txbuf
; zero 0x56 bytes at TXBUF
clear_txbuf:
19ac  e5             PUSH HL                          
19ad  c5             PUSH BC                          
19ae  21 a2 41       LD HL,TXBUF                      ; 41a2
19b1  06 56          LD B,0x56                        

L_19b3:
19b3  36 00          LD (HL),0                        
19b5  23             INC HL                           
19b6  10 fb          DJNZ L_19b3                      ; 19b3
19b8  c1             POP BC                           
19b9  e1             POP HL                           
19ba  c9             RET                              

; ----------------------------------------------------------------
; clear_glyph_tmp
clear_glyph_tmp:
19bb  e5             PUSH HL                          
19bc  c5             PUSH BC                          
19bd  21 d6 42       LD HL,0x42d6                     
19c0  06 60          LD B,0x60                        

L_19c2:
19c2  36 00          LD (HL),0                        
19c4  23             INC HL                           
19c5  10 fb          DJNZ L_19c2                      ; 19c2
19c7  c1             POP BC                           
19c8  e1             POP HL                           
19c9  c9             RET                              

; ----------------------------------------------------------------
; menu_enter
; Enter the on-sign editor/menu (MENU_ACTIVE=FF), SP reset
menu_enter:
19ca  31 3f 40       LD SP,0x403f                     
19cd  3e ff          LD A,0xff                        
19cf  32 17 42       LD (MENU_ACTIVE),A               ; 4217
19d2  fb             EI                               
19d3  cd 98 06       CALL init_render                 ; 0698
19d6  af             XOR A                            
19d7  32 28 42       LD (RX_BYTE),A                   ; 4228
19da  32 29 42       LD (0x4229),A                    
19dd  32 26 42       LD (0x4226),A                    
19e0  32 27 42       LD (0x4227),A                    
19e3  32 2a 42       LD (BEEP_TIMER),A                ; 422a
19e6  32 25 42       LD (RX_LASTCMD),A                ; 4225
19e9  32 d7 43       LD (0x43d7),A                    
19ec  cd 09 23       CALL menu_getchar                ; 2309
19ef  f5             PUSH AF                          
19f0  3e 00          LD A,0                           
19f2  32 d7 43       LD (0x43d7),A                    
19f5  f1             POP AF                           
19f6  21 cb 43       LD HL,MY_ADDRESS                 ; 43cb
19f9  be             CP (HL)                          
19fa  28 11          JR z,L_1a0d                      ; 1a0d
19fc  fe 2a          CP 0x2a                          
19fe  28 0d          JR z,L_1a0d                      ; 1a0d
1a00  c3 00 00       JP RESET                         ; 0000

; ----------------------------------------------------------------
; key_handler
; Handle a key / IR code: menu navigation (ADDRESS?, TIME?, PROG MSG?, SEQ MSG? ...)
key_handler:
1a03  3e ff          LD A,0xff                        
1a05  32 58 43       LD (0x4358),A                    
1a08  3e 01          LD A,1                           
1a0a  32 d7 43       LD (0x43d7),A                    

L_1a0d:
1a0d  31 3f 40       LD SP,0x403f                     
1a10  3e ff          LD A,0xff                        
1a12  32 17 42       LD (MENU_ACTIVE),A               ; 4217
1a15  fb             EI                               
1a16  cd 98 06       CALL init_render                 ; 0698
1a19  3a 86 43       LD A,(IR_CODE)                   ; 4386
1a1c  fe a4          CP 0xa4                          
1a1e  20 20          JR nz,L_1a40                     ; 1a40
1a20  cd 48 0f       CALL sub_0f48                    ; 0f48

L_1a23:
1a23  3e fe          LD A,0xfe                        
1a25  32 86 43       LD (IR_CODE),A                   ; 4386
1a28  21 a0 01       LD HL,0x01a0                     
1a2b  22 80 43       LD (GEN_COUNTDOWN),HL            ; 4380

L_1a2e:
1a2e  3a 86 43       LD A,(IR_CODE)                   ; 4386
1a31  fe a4          CP 0xa4                          
1a33  28 ee          JR z,L_1a23                      ; 1a23
1a35  fe fe          CP 0xfe                          
1a37  20 07          JR nz,L_1a40                     ; 1a40
1a39  2a 80 43       LD HL,(GEN_COUNTDOWN)            ; 4380
1a3c  7c             LD A,H                           
1a3d  b5             OR L                             
1a3e  20 ee          JR nz,L_1a2e                     ; 1a2e

L_1a40:
1a40  cd 6b 14       CALL ir_init2                    ; 146b
1a43  af             XOR A                            
1a44  32 28 42       LD (RX_BYTE),A                   ; 4228
1a47  32 29 42       LD (0x4229),A                    
1a4a  32 26 42       LD (0x4226),A                    
1a4d  32 27 42       LD (0x4227),A                    
1a50  32 2a 42       LD (BEEP_TIMER),A                ; 422a
1a53  32 5a 43       LD (0x435a),A                    
1a56  3a 0f 42       LD A,(0x420f)                    
1a59  3c             INC A                            
1a5a  20 0d          JR nz,L_1a69                     ; 1a69
1a5c  af             XOR A                            
1a5d  32 0f 42       LD (0x420f),A                    
1a60  cd 26 04       CALL chan_select                 ; 0426
1a63  22 46 43       LD (STORE_CURSOR),HL             ; 4346
1a66  cd 1a 04       CALL chan_find                   ; 041a

L_1a69:
1a69  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
1a6c  7e             LD A,(HL)                        
1a6d  fe d0          CP 0xd0                          
1a6f  da 8e 1a       JP c,L_1a8e                      ; 1a8e
1a72  fe db          CP 0xdb                          
1a74  d2 8e 1a       JP nc,L_1a8e                     ; 1a8e
1a77  2b             DEC HL                           
1a78  2b             DEC HL                           
1a79  7e             LD A,(HL)                        
1a7a  fe d0          CP 0xd0                          
1a7c  da 8b 1a       JP c,L_1a8b                      ; 1a8b
1a7f  fe db          CP 0xdb                          
1a81  d2 8b 1a       JP nc,L_1a8b                     ; 1a8b
1a84  2b             DEC HL                           
1a85  22 46 43       LD (STORE_CURSOR),HL             ; 4346
1a88  c3 af 1a       JP L_1aaf                        ; 1aaf

L_1a8b:
1a8b  22 46 43       LD (STORE_CURSOR),HL             ; 4346

L_1a8e:
1a8e  e5             PUSH HL                          
1a8f  11 e2 43       LD DE,MSG_STORE                  ; 43e2
1a92  b7             OR A                             
1a93  ed 52          SBC HL,DE                        
1a95  e5             PUSH HL                          
1a96  c1             POP BC                           
1a97  e1             POP HL                           
1a98  2b             DEC HL                           

L_1a99:
1a99  7e             LD A,(HL)                        
1a9a  fe d0          CP 0xd0                          
1a9c  da a6 1a       JP c,L_1aa6                      ; 1aa6
1a9f  fe db          CP 0xdb                          
1aa1  d2 a6 1a       JP nc,L_1aa6                     ; 1aa6
1aa4  18 0a          JR L_1ab0                        ; 1ab0

L_1aa6:
1aa6  2b             DEC HL                           
1aa7  0b             DEC BC                           
1aa8  79             LD A,C                           
1aa9  b0             OR B                             
1aaa  20 ed          JR nz,L_1a99                     ; 1a99
1aac  c3 3e 2a       JP pkt_process_end               ; 2a3e

L_1aaf:
1aaf  23             INC HL                           

L_1ab0:
1ab0  23             INC HL                           
1ab1  22 18 42       LD (INS_PTR),HL                  ; 4218
1ab4  cd 38 1c       CALL store_finalize              ; 1c38
1ab7  af             XOR A                            
1ab8  32 cf 43       LD (0x43cf),A                    
1abb  32 ca 43       LD (0x43ca),A                    
1abe  32 21 42       LD (0x4221),A                    
1ac1  32 20 42       LD (0x4220),A                    
1ac4  32 a1 41       LD (FB_TMP),A                    ; 41a1
1ac7  32 41 42       LD (0x4241),A                    
1aca  32 24 42       LD (0x4224),A                    
1acd  3e ff          LD A,0xff                        
1acf  32 92 43       LD (0x4392),A                    

; ----------------------------------------------------------------
; editor_loop
; Editor main loop: get key, dispatch
editor_loop:
1ad2  cd 28 27       CALL editor_redraw               ; 2728

L_1ad5:
1ad5  cd 09 23       CALL menu_getchar                ; 2309
1ad8  cd 3c 26       CALL sub_263c                    ; 263c
1adb  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
1ade  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1ae1  fe 1d          CP 0x1d                          
1ae3  3e 00          LD A,0                           
1ae5  28 09          JR z,L_1af0                      ; 1af0
1ae7  32 20 42       LD (0x4220),A                    
1aea  32 a1 41       LD (FB_TMP),A                    ; 41a1
1aed  32 ca 43       LD (0x43ca),A                    

L_1af0:
1af0  32 41 42       LD (0x4241),A                    
1af3  3a 43 42       LD A,(0x4243)                    
1af6  b7             OR A                             
1af7  c2 0d 22       JP nz,L_220d                     ; 220d
1afa  3a 36 43       LD A,(0x4336)                    
1afd  cb 7f          BIT 7,A                          
1aff  c2 3a 22       JP nz,L_223a                     ; 223a
1b02  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
1b05  fe 1f          CP 0x1f                          
1b07  cc 91 1b       CALL z,sub_1b91                  ; 1b91
1b0a  af             XOR A                            
1b0b  32 92 43       LD (0x4392),A                    
1b0e  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
1b11  fe 01          CP 1                             
1b13  ca d5 1a       JP z,L_1ad5                      ; 1ad5
1b16  fe 03          CP 3                             
1b18  ca c4 20       JP z,L_20c4                      ; 20c4
1b1b  fe 05          CP 5                             
1b1d  ca 87 20       JP z,L_2087                      ; 2087
1b20  fe 7f          CP 0x7f                          
1b22  ca 82 24       JP z,L_2482                      ; 2482
1b25  fe 1d          CP 0x1d                          
1b27  ca 65 24       JP z,L_2465                      ; 2465
1b2a  fe 0a          CP 10                            
1b2c  ca f4 24       JP z,L_24f4                      ; 24f4
1b2f  fe 0c          CP 12                            
1b31  ca 0f 25       JP z,L_250f                      ; 250f
1b34  fe 08          CP 8                             
1b36  ca 22 25       JP z,L_2522                      ; 2522
1b39  fe 0b          CP 11                            
1b3b  ca 52 25       JP z,L_2552                      ; 2552
1b3e  fe 0e          CP 14                            
1b40  ca eb 20       JP z,L_20eb                      ; 20eb
1b43  fe b6          CP 0xb6                          
1b45  ca 84 21       JP z,L_2184                      ; 2184
1b48  fe 5e          CP 0x5e                          
1b4a  ca 3a 1f       JP z,L_1f3a                      ; 1f3a
1b4d  fe 1c          CP 0x1c                          
1b4f  ca 6c 21       JP z,L_216c                      ; 216c
1b52  fe 1e          CP 0x1e                          
1b54  ca b4 21       JP z,L_21b4                      ; 21b4
1b57  fe 15          CP 0x15                          
1b59  ca cc 21       JP z,L_21cc                      ; 21cc
1b5c  fe 16          CP 0x16                          
1b5e  ca ec 21       JP z,L_21ec                      ; 21ec
1b61  fe 17          CP 0x17                          
1b63  ca 01 1d       JP z,L_1d01                      ; 1d01
1b66  fe 02          CP 2                             
1b68  ca 9c 21       JP z,L_219c                      ; 219c
1b6b  fe b3          CP 0xb3                          
1b6d  ca 46 20       JP z,L_2046                      ; 2046
1b70  fe b7          CP 0xb7                          
1b72  ca e4 21       JP z,L_21e4                      ; 21e4
1b75  fe 09          CP 9                             
1b77  ca 0d 22       JP z,L_220d                      ; 220d
1b7a  fe 04          CP 4                             
1b7c  ca 3a 22       JP z,L_223a                      ; 223a
1b7f  fe 0d          CP 13                            
1b81  ca 5c 1c       JP z,L_1c5c                      ; 1c5c
1b84  fe 9f          CP 0x9f                          
1b86  ca d2 1a       JP z,editor_loop                 ; 1ad2
1b89  fe b1          CP 0xb1                          
1b8b  ca 5c 1c       JP z,L_1c5c                      ; 1c5c
1b8e  c3 80 25       JP L_2580                        ; 2580

sub_1b91:
1b91  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
1b94  b7             OR A                             
1b95  c2 9d 1b       JP nz,L_1b9d                     ; 1b9d
1b98  3a 92 43       LD A,(0x4392)                    
1b9b  a7             AND A                            
1b9c  c8             RET z                            

L_1b9d:
1b9d  3e 00          LD A,0                           

L_1b9f:
1b9f  5f             LD E,A                           
1ba0  d5             PUSH DE                          
1ba1  cd 26 04       CALL chan_select                 ; 0426
1ba4  d1             POP DE                           
1ba5  a7             AND A                            
1ba6  c2 3e 2a       JP nz,pkt_process_end            ; 2a3e
1ba9  7e             LD A,(HL)                        
1baa  fe 03          CP 3                             
1bac  28 64          JR z,L_1c12                      ; 1c12
1bae  06 00          LD B,0                           
1bb0  4f             LD C,A                           
1bb1  dd 21 2d 37    LD IX,0x372d                     
1bb5  dd 09          ADD IX,BC                        
1bb7  dd cb 00 4e    BIT 1,(IX)                       
1bbb  28 1b          JR z,L_1bd8                      ; 1bd8

L_1bbd:
1bbd  23             INC HL                           
1bbe  7e             LD A,(HL)                        
1bbf  fe 03          CP 3                             
1bc1  20 04          JR nz,L_1bc7                     ; 1bc7
1bc3  7b             LD A,E                           
1bc4  c3 f2 1b       JP L_1bf2                        ; 1bf2

L_1bc7:
1bc7  06 00          LD B,0                           
1bc9  4f             LD C,A                           
1bca  dd 21 2d 37    LD IX,0x372d                     
1bce  dd 09          ADD IX,BC                        
1bd0  dd cb 00 4e    BIT 1,(IX)                       
1bd4  28 02          JR z,L_1bd8                      ; 1bd8
1bd6  18 e5          JR L_1bbd                        ; 1bbd

L_1bd8:
1bd8  7b             LD A,E                           
1bd9  3c             INC A                            
1bda  fe 64          CP 0x64                          
1bdc  20 c1          JR nz,L_1b9f                     ; 1b9f
1bde  cd 98 06       CALL init_render                 ; 0698
1be1  2a 9b 41       LD HL,(FB_COL)                   ; 419b
1be4  22 98 41       LD (FB_COLPTR),HL                ; 4198

L_1be7:
1be7  21 fe 2f       LD HL,0x2ffe                     
1bea  cd 32 1e       CALL sub_1e32                    ; 1e32
1bed  fe 64          CP 0x64                          
1bef  d2 e7 1b       JP nc,L_1be7                     ; 1be7

L_1bf2:
1bf2  32 8f 43       LD (0x438f),A                    
1bf5  cd 26 04       CALL chan_select                 ; 0426
1bf8  a7             AND A                            
1bf9  c2 3e 2a       JP nz,pkt_process_end            ; 2a3e
1bfc  22 18 42       LD (INS_PTR),HL                  ; 4218
1bff  2b             DEC HL                           
1c00  22 46 43       LD (STORE_CURSOR),HL             ; 4346
1c03  cd f8 20       CALL sub_20f8                    ; 20f8
1c06  3e 1f          LD A,0x1f                        
1c08  32 25 42       LD (RX_LASTCMD),A                ; 4225
1c0b  3a 8f 43       LD A,(0x438f)                    
1c0e  5f             LD E,A                           
1c0f  c3 1a 1c       JP L_1c1a                        ; 1c1a

L_1c12:
1c12  22 18 42       LD (INS_PTR),HL                  ; 4218
1c15  2b             DEC HL                           
1c16  2b             DEC HL                           
1c17  22 46 43       LD (STORE_CURSOR),HL             ; 4346

L_1c1a:
1c1a  d5             PUSH DE                          
1c1b  cd 1a 04       CALL chan_find                   ; 041a
1c1e  d1             POP DE                           
1c1f  7b             LD A,E                           
1c20  fe 64          CP 0x64                          
1c22  20 03          JR nz,L_1c27                     ; 1c27
1c24  32 6a 42       LD (CHAN_LOCK),A                 ; 426a

L_1c27:
1c27  21 6b 42       LD HL,SEQ_LIST                   ; 426b
1c2a  73             LD (HL),E                        
1c2b  23             INC HL                           
1c2c  06 67          LD B,0x67                        

L_1c2e:
1c2e  36 ff          LD (HL),0xff                     
1c30  23             INC HL                           
1c31  10 fb          DJNZ L_1c2e                      ; 1c2e
1c33  7b             LD A,E                           
1c34  32 99 43       LD (0x4399),A                    
1c37  c9             RET                              

; ----------------------------------------------------------------
; store_finalize
; Fix up MSG_STORE terminators after an edit
store_finalize:
1c38  3e da          LD A,0xda                        
1c3a  21 e2 43       LD HL,MSG_STORE                  ; 43e2
1c3d  ed 4b da 43    LD BC,(STORE_SIZE)               ; 43da
1c41  03             INC BC                           
1c42  ed b1          CPIR                             
1c44  78             LD A,B                           
1c45  b1             OR C                             
1c46  ca 3e 2a       JP z,pkt_process_end             ; 2a3e
1c49  2b             DEC HL                           
1c4a  22 34 42       LD (STORE_END),HL                ; 4234
1c4d  c9             RET                              

L_1c4e:
1c4e  3e ff          LD A,0xff                        
1c50  32 24 42       LD (0x4224),A                    
1c53  21 46 30       LD HL,0x3046                     
1c56  22 0a 42       LD (0x420a),HL                   
1c59  c3 d2 1a       JP editor_loop                   ; 1ad2

L_1c5c:
1c5c  af             XOR A                            
1c5d  32 36 43       LD (0x4336),A                    
1c60  32 43 42       LD (0x4243),A                    
1c63  3a d7 43       LD A,(0x43d7)                    
1c66  a7             AND A                            
1c67  28 06          JR z,L_1c6f                      ; 1c6f
1c69  cd 71 15       CALL tx_send_byte                ; 1571
1c6c  c3 9f 1c       JP L_1c9f                        ; 1c9f

L_1c6f:
1c6f  3a 86 43       LD A,(IR_CODE)                   ; 4386
1c72  fe be          CP 0xbe                          
1c74  28 29          JR z,L_1c9f                      ; 1c9f
1c76  fe a4          CP 0xa4                          
1c78  28 04          JR z,L_1c7e                      ; 1c7e
1c7a  fe af          CP 0xaf                          
1c7c  20 f1          JR nz,L_1c6f                     ; 1c6f

L_1c7e:
1c7e  3e ff          LD A,0xff                        
1c80  32 86 43       LD (IR_CODE),A                   ; 4386
1c83  21 8a 02       LD HL,0x028a                     
1c86  22 80 43       LD (GEN_COUNTDOWN),HL            ; 4380

L_1c89:
1c89  3a 86 43       LD A,(IR_CODE)                   ; 4386
1c8c  fe a4          CP 0xa4                          
1c8e  28 ee          JR z,L_1c7e                      ; 1c7e
1c90  fe af          CP 0xaf                          
1c92  28 ea          JR z,L_1c7e                      ; 1c7e
1c94  fe ff          CP 0xff                          
1c96  20 07          JR nz,L_1c9f                     ; 1c9f
1c98  2a 80 43       LD HL,(GEN_COUNTDOWN)            ; 4380
1c9b  7c             LD A,H                           
1c9c  b5             OR L                             
1c9d  20 ea          JR nz,L_1c89                     ; 1c89

L_1c9f:
1c9f  3e ff          LD A,0xff                        
1ca1  32 5b 43       LD (MENU_FLAG),A                 ; 435b
1ca4  3a 5a 43       LD A,(0x435a)                    
1ca7  a7             AND A                            
1ca8  c2 ee 1c       JP nz,L_1cee                     ; 1cee
1cab  2a 18 42       LD HL,(INS_PTR)                  ; 4218
1cae  2b             DEC HL                           
1caf  2b             DEC HL                           
1cb0  06 02          LD B,2                           
1cb2  cd fc 1f       CALL ascii_dec_to_bin            ; 1ffc
1cb5  5f             LD E,A                           
1cb6  21 6b 42       LD HL,SEQ_LIST                   ; 426b
1cb9  be             CP (HL)                          
1cba  ca ee 1c       JP z,L_1cee                      ; 1cee
1cbd  3e 64          LD A,0x64                        
1cbf  be             CP (HL)                          
1cc0  c2 c7 1c       JP nz,L_1cc7                     ; 1cc7
1cc3  7b             LD A,E                           
1cc4  c3 e3 1c       JP L_1ce3                        ; 1ce3

L_1cc7:
1cc7  06 68          LD B,0x68                        

L_1cc9:
1cc9  7e             LD A,(HL)                        
1cca  bb             CP E                             
1ccb  ca ea 1c       JP z,L_1cea                      ; 1cea
1cce  fe ff          CP 0xff                          
1cd0  28 03          JR z,L_1cd5                      ; 1cd5
1cd2  23             INC HL                           
1cd3  10 f4          DJNZ L_1cc9                      ; 1cc9

L_1cd5:
1cd5  7b             LD A,E                           
1cd6  21 d1 42       LD HL,0x42d1                     
1cd9  36 ff          LD (HL),0xff                     
1cdb  11 d2 42       LD DE,0x42d2                     
1cde  01 67 00       LD BC,0x67                       
1ce1  ed b8          LDDR                             

L_1ce3:
1ce3  21 6b 42       LD HL,SEQ_LIST                   ; 426b
1ce6  77             LD (HL),A                        
1ce7  c3 ee 1c       JP L_1cee                        ; 1cee

L_1cea:
1cea  5f             LD E,A                           
1ceb  32 5b 43       LD (MENU_FLAG),A                 ; 435b

L_1cee:
1cee  31 3f 40       LD SP,0x403f                     
1cf1  af             XOR A                            
1cf2  32 17 42       LD (MENU_ACTIVE),A               ; 4217
1cf5  32 3b 43       LD (0x433b),A                    
1cf8  21 6b 42       LD HL,SEQ_LIST                   ; 426b
1cfb  22 d3 42       LD (SEQ_PTR),HL                  ; 42d3
1cfe  c3 0f 00       JP L_000f                        ; 000f

L_1d01:
1d01  cd 98 06       CALL init_render                 ; 0698
1d04  2a 9b 41       LD HL,(FB_COL)                   ; 419b
1d07  22 98 41       LD (FB_COLPTR),HL                ; 4198
1d0a  21 1a 30       LD HL,0x301a                     
1d0d  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
1d10  cd f8 29       CALL menu_show_text              ; 29f8
1d13  af             XOR A                            
1d14  32 06 42       LD (CLK_RUN),A                   ; 4206
1d17  21 00 42       LD HL,CLK_H10                    ; 4200
1d1a  06 04          LD B,4                           

L_1d1c:
1d1c  c5             PUSH BC                          
1d1d  e5             PUSH HL                          

L_1d1e:
1d1e  cd 09 23       CALL menu_getchar                ; 2309
1d21  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1d24  fe 3a          CP 0x3a                          
1d26  30 f6          JR nc,L_1d1e                     ; 1d1e
1d28  fe 30          CP 0x30                          
1d2a  38 f2          JR c,L_1d1e                      ; 1d1e
1d2c  f5             PUSH AF                          
1d2d  cd dd 07       CALL glyph_lookup                ; 07dd
1d30  f1             POP AF                           
1d31  e6 0f          AND 15                           
1d33  e1             POP HL                           
1d34  77             LD (HL),A                        
1d35  23             INC HL                           
1d36  c1             POP BC                           
1d37  10 e3          DJNZ L_1d1c                      ; 1d1c
1d39  3a 00 42       LD A,(CLK_H10)                   ; 4200
1d3c  e6 01          AND 1                            
1d3e  32 00 42       LD (CLK_H10),A                   ; 4200
1d41  b7             OR A                             
1d42  28 0c          JR z,L_1d50                      ; 1d50
1d44  3a 01 42       LD A,(CLK_H1)                    ; 4201
1d47  fe 03          CP 3                             
1d49  38 05          JR c,L_1d50                      ; 1d50
1d4b  3e 02          LD A,2                           
1d4d  32 01 42       LD (CLK_H1),A                    ; 4201

L_1d50:
1d50  3e 50          LD A,0x50                        
1d52  32 44 42       LD (0x4244),A                    

L_1d55:
1d55  3a 44 42       LD A,(0x4244)                    
1d58  a7             AND A                            
1d59  20 fa          JR nz,L_1d55                     ; 1d55
1d5b  cd 98 06       CALL init_render                 ; 0698
1d5e  2a 9b 41       LD HL,(FB_COL)                   ; 419b
1d61  22 98 41       LD (FB_COLPTR),HL                ; 4198
1d64  21 25 30       LD HL,0x3025                     
1d67  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
1d6a  cd f8 29       CALL menu_show_text              ; 29f8

L_1d6d:
1d6d  cd 09 23       CALL menu_getchar                ; 2309
1d70  cb af          RES 5,A                          
1d72  fe 59          CP 0x59                          
1d74  20 04          JR nz,L_1d7a                     ; 1d7a
1d76  3e 00          LD A,0                           
1d78  18 06          JR L_1d80                        ; 1d80

L_1d7a:
1d7a  fe 4e          CP 0x4e                          
1d7c  20 ef          JR nz,L_1d6d                     ; 1d6d
1d7e  3e ff          LD A,0xff                        

L_1d80:
1d80  32 05 42       LD (CLK_PM),A                    ; 4205
1d83  3e 00          LD A,0                           
1d85  32 3c 43       LD (NMI_COUNT),A                 ; 433c
1d88  3e ff          LD A,0xff                        
1d8a  32 06 42       LD (CLK_RUN),A                   ; 4206
1d8d  c3 6a 20       JP L_206a                        ; 206a

L_1d90:
1d90  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
1d93  a7             AND A                            
1d94  c2 dd 07       JP nz,glyph_lookup               ; 07dd
1d97  3a 3a 42       LD A,(PAUSE_FLAG)                ; 423a
1d9a  a7             AND A                            
1d9b  28 05          JR z,L_1da2                      ; 1da2
1d9d  21 39 43       LD HL,FONT_MODE                  ; 4339
1da0  cb 96          RES 2,(HL)                       

L_1da2:
1da2  3a 13 42       LD A,(0x4213)                    
1da5  2a 14 42       LD HL,(0x4214)                   
1da8  a7             AND A                            
1da9  20 17          JR nz,L_1dc2                     ; 1dc2
1dab  21 00 42       LD HL,CLK_H10                    ; 4200
1dae  7e             LD A,(HL)                        
1daf  a7             AND A                            
1db0  3a 13 42       LD A,(0x4213)                    
1db3  20 0d          JR nz,L_1dc2                     ; 1dc2
1db5  3a 13 42       LD A,(0x4213)                    
1db8  3c             INC A                            
1db9  32 13 42       LD (0x4213),A                    
1dbc  23             INC HL                           
1dbd  22 14 42       LD (0x4214),HL                   
1dc0  18 ce          JR L_1d90                        ; 1d90

L_1dc2:
1dc2  3c             INC A                            
1dc3  32 13 42       LD (0x4213),A                    
1dc6  fe 03          CP 3                             
1dc8  20 08          JR nz,L_1dd2                     ; 1dd2
1dca  3e 3a          LD A,0x3a                        
1dcc  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1dcf  c3 0c 1e       JP L_1e0c                        ; 1e0c

L_1dd2:
1dd2  fe 06          CP 6                             
1dd4  20 08          JR nz,L_1dde                     ; 1dde
1dd6  3e 20          LD A,0x20                        
1dd8  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1ddb  c3 0c 1e       JP L_1e0c                        ; 1e0c

L_1dde:
1dde  fe 07          CP 7                             
1de0  20 10          JR nz,L_1df2                     ; 1df2
1de2  3a 05 42       LD A,(CLK_PM)                    ; 4205
1de5  e6 01          AND 1                            
1de7  3e 41          LD A,0x41                        
1de9  28 02          JR z,L_1ded                      ; 1ded
1deb  3e 50          LD A,0x50                        

L_1ded:
1ded  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1df0  18 1a          JR L_1e0c                        ; 1e0c

L_1df2:
1df2  fe 08          CP 8                             
1df4  20 07          JR nz,L_1dfd                     ; 1dfd
1df6  3e 4d          LD A,0x4d                        
1df8  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1dfb  18 1d          JR L_1e1a                        ; 1e1a

L_1dfd:
1dfd  7e             LD A,(HL)                        
1dfe  e6 0f          AND 15                           
1e00  f6 30          OR 0x30                          
1e02  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1e05  23             INC HL                           
1e06  3a 13 42       LD A,(0x4213)                    
1e09  22 14 42       LD (0x4214),HL                   

L_1e0c:
1e0c  cd ea 0c       CALL sub_0cea                    ; 0cea
1e0f  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
1e12  c3 dd 07       JP glyph_lookup                  ; 07dd
1e15  3e 20          LD A,0x20                        
1e17  32 0e 42       LD (CUR_CHAR),A                  ; 420e

L_1e1a:
1e1a  3e ff          LD A,0xff                        
1e1c  32 13 42       LD (0x4213),A                    
1e1f  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
1e22  c3 dd 07       JP glyph_lookup                  ; 07dd

sub_1e25:
1e25  f5             PUSH AF                          
1e26  c5             PUSH BC                          
1e27  d5             PUSH DE                          
1e28  e5             PUSH HL                          
1e29  dd e5          PUSH IX                          
1e2b  fd e5          PUSH IY                          
1e2d  22 d4 43       LD (0x43d4),HL                   
1e30  18 0e          JR L_1e40                        ; 1e40

sub_1e32:
1e32  f5             PUSH AF                          
1e33  c5             PUSH BC                          
1e34  d5             PUSH DE                          
1e35  e5             PUSH HL                          
1e36  dd e5          PUSH IX                          
1e38  fd e5          PUSH IY                          
1e3a  22 d4 43       LD (0x43d4),HL                   
1e3d  c3 14 1f       JP L_1f14                        ; 1f14

L_1e40:
1e40  2a 18 42       LD HL,(INS_PTR)                  ; 4218
1e43  2b             DEC HL                           
1e44  7e             LD A,(HL)                        
1e45  fe da          CP 0xda                          
1e47  20 04          JR nz,L_1e4d                     ; 1e4d
1e49  3e 44          LD A,0x44                        
1e4b  18 04          JR L_1e51                        ; 1e51

L_1e4d:
1e4d  e6 0f          AND 15                           
1e4f  f6 30          OR 0x30                          

L_1e51:
1e51  32 9d 43       LD (CHAN_D1),A                   ; 439d
1e54  2b             DEC HL                           
1e55  7e             LD A,(HL)                        
1e56  fe da          CP 0xda                          
1e58  20 04          JR nz,L_1e5e                     ; 1e5e
1e5a  3e 44          LD A,0x44                        
1e5c  18 04          JR L_1e62                        ; 1e62

L_1e5e:
1e5e  e6 0f          AND 15                           
1e60  f6 30          OR 0x30                          

L_1e62:
1e62  32 9c 43       LD (CHAN_D10),A                  ; 439c

L_1e65:
1e65  cd 98 06       CALL init_render                 ; 0698
1e68  2a 9b 41       LD HL,(FB_COL)                   ; 419b
1e6b  22 98 41       LD (FB_COLPTR),HL                ; 4198
1e6e  2a d4 43       LD HL,(0x43d4)                   
1e71  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
1e74  cd f8 29       CALL menu_show_text              ; 29f8
1e77  06 02          LD B,2                           
1e79  21 9c 43       LD HL,CHAN_D10                   ; 439c

L_1e7c:
1e7c  7e             LD A,(HL)                        
1e7d  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1e80  e5             PUSH HL                          
1e81  c5             PUSH BC                          
1e82  cd dd 07       CALL glyph_lookup                ; 07dd
1e85  c1             POP BC                           
1e86  e1             POP HL                           
1e87  23             INC HL                           
1e88  10 f2          DJNZ L_1e7c                      ; 1e7c

L_1e8a:
1e8a  cd 09 23       CALL menu_getchar                ; 2309
1e8d  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1e90  fe 04          CP 4                             
1e92  ca 32 1f       JP z,L_1f32                      ; 1f32
1e95  fe 08          CP 8                             
1e97  28 52          JR z,L_1eeb                      ; 1eeb
1e99  fe 09          CP 9                             
1e9b  28 4e          JR z,L_1eeb                      ; 1eeb
1e9d  fe 0d          CP 13                            
1e9f  28 7e          JR z,L_1f1f                      ; 1f1f
1ea1  fe 0e          CP 14                            
1ea3  28 6f          JR z,L_1f14                      ; 1f14
1ea5  fe 1f          CP 0x1f                          
1ea7  ca 36 1f       JP z,L_1f36                      ; 1f36
1eaa  fe 7f          CP 0x7f                          
1eac  28 2c          JR z,L_1eda                      ; 1eda
1eae  fe 41          CP 0x41                          
1eb0  28 78          JR z,L_1f2a                      ; 1f2a
1eb2  fe 61          CP 0x61                          
1eb4  28 74          JR z,L_1f2a                      ; 1f2a
1eb6  fe 44          CP 0x44                          
1eb8  28 74          JR z,L_1f2e                      ; 1f2e
1eba  fe 64          CP 0x64                          
1ebc  28 70          JR z,L_1f2e                      ; 1f2e
1ebe  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
1ec1  cd 29 20       CALL is_digit                    ; 2029
1ec4  d2 8a 1e       JP nc,L_1e8a                     ; 1e8a
1ec7  dd 21 9c 43    LD IX,CHAN_D10                   ; 439c
1ecb  dd 7e 01       LD A,(IX+1)                      
1ece  dd 77 00       LD (IX),A                        
1ed1  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
1ed4  dd 77 01       LD (IX+1),A                      
1ed7  c3 65 1e       JP L_1e65                        ; 1e65

L_1eda:
1eda  dd 21 9c 43    LD IX,CHAN_D10                   ; 439c
1ede  dd 7e 00       LD A,(IX)                        
1ee1  dd 77 01       LD (IX+1),A                      
1ee4  dd 36 00 30    LD (IX),0x30                     
1ee8  c3 65 1e       JP L_1e65                        ; 1e65

L_1eeb:
1eeb  3a 9c 43       LD A,(CHAN_D10)                  ; 439c
1eee  f6 20          OR 0x20                          
1ef0  fe 64          CP 0x64                          
1ef2  28 3a          JR z,L_1f2e                      ; 1f2e
1ef4  3a 9d 43       LD A,(CHAN_D1)                   ; 439d
1ef7  f6 20          OR 0x20                          
1ef9  fe 64          CP 0x64                          
1efb  28 31          JR z,L_1f2e                      ; 1f2e
1efd  06 02          LD B,2                           
1eff  21 9c 43       LD HL,CHAN_D10                   ; 439c
1f02  cd fc 1f       CALL ascii_dec_to_bin            ; 1ffc

L_1f05:
1f05  32 d2 43       LD (0x43d2),A                    
1f08  fd e1          POP IY                           
1f0a  dd e1          POP IX                           
1f0c  e1             POP HL                           
1f0d  d1             POP DE                           
1f0e  c1             POP BC                           
1f0f  f1             POP AF                           
1f10  3a d2 43       LD A,(0x43d2)                    
1f13  c9             RET                              

L_1f14:
1f14  3e 20          LD A,0x20                        
1f16  32 9c 43       LD (CHAN_D10),A                  ; 439c
1f19  32 9d 43       LD (CHAN_D1),A                   ; 439d
1f1c  c3 65 1e       JP L_1e65                        ; 1e65

L_1f1f:
1f1f  3a 9d 43       LD A,(CHAN_D1)                   ; 439d
1f22  fe 20          CP 0x20                          
1f24  20 c5          JR nz,L_1eeb                     ; 1eeb
1f26  3e 9a          LD A,0x9a                        
1f28  18 db          JR L_1f05                        ; 1f05

L_1f2a:
1f2a  3e 99          LD A,0x99                        
1f2c  18 d7          JR L_1f05                        ; 1f05

L_1f2e:
1f2e  3e 64          LD A,0x64                        
1f30  18 d3          JR L_1f05                        ; 1f05

L_1f32:
1f32  3e 97          LD A,0x97                        
1f34  18 cf          JR L_1f05                        ; 1f05

L_1f36:
1f36  3e 98          LD A,0x98                        
1f38  18 cb          JR L_1f05                        ; 1f05

L_1f3a:
1f3a  cd 98 06       CALL init_render                 ; 0698
1f3d  2a 9b 41       LD HL,(FB_COL)                   ; 419b
1f40  22 98 41       LD (FB_COLPTR),HL                ; 4198
1f43  21 f3 2f       LD HL,MENU_STRINGS               ; 2ff3
1f46  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
1f49  cd f8 29       CALL menu_show_text              ; 29f8
1f4c  26 00          LD H,0                           
1f4e  3a cb 43       LD A,(MY_ADDRESS)                ; 43cb
1f51  fe 00          CP 0                             
1f53  28 04          JR z,L_1f59                      ; 1f59
1f55  fe 2a          CP 0x2a                          
1f57  20 02          JR nz,L_1f5b                     ; 1f5b

L_1f59:
1f59  3e 01          LD A,1                           

L_1f5b:
1f5b  6f             LD L,A                           
1f5c  dd 21 c5 43    LD IX,MENU_ENTRY_BUF             ; 43c5
1f60  fd 21 ec 18    LD IY,0x18ec                     
1f64  cd cb 18       CALL sub_18cb                    ; 18cb
1f67  21 c5 43       LD HL,MENU_ENTRY_BUF             ; 43c5
1f6a  06 03          LD B,3                           

L_1f6c:
1f6c  7e             LD A,(HL)                        
1f6d  fe 30          CP 0x30                          
1f6f  20 08          JR nz,L_1f79                     ; 1f79
1f71  78             LD A,B                           
1f72  fe 01          CP 1                             
1f74  28 03          JR z,L_1f79                      ; 1f79
1f76  23             INC HL                           
1f77  10 f3          DJNZ L_1f6c                      ; 1f6c

L_1f79:
1f79  7e             LD A,(HL)                        
1f7a  cd 29 20       CALL is_digit                    ; 2029
1f7d  da 83 1f       JP c,L_1f83                      ; 1f83
1f80  3e 30          LD A,0x30                        
1f82  77             LD (HL),A                        

L_1f83:
1f83  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1f86  e5             PUSH HL                          
1f87  c5             PUSH BC                          
1f88  cd dd 07       CALL glyph_lookup                ; 07dd
1f8b  c1             POP BC                           
1f8c  e1             POP HL                           
1f8d  23             INC HL                           
1f8e  10 e9          DJNZ L_1f79                      ; 1f79
1f90  21 c5 43       LD HL,MENU_ENTRY_BUF             ; 43c5
1f93  06 00          LD B,0                           
1f95  e5             PUSH HL                          
1f96  c5             PUSH BC                          

L_1f97:
1f97  cd 09 23       CALL menu_getchar                ; 2309
1f9a  32 0e 42       LD (CUR_CHAR),A                  ; 420e
1f9d  c1             POP BC                           
1f9e  e1             POP HL                           
1f9f  fe 08          CP 8                             
1fa1  28 35          JR z,L_1fd8                      ; 1fd8
1fa3  fe 0d          CP 13                            
1fa5  28 31          JR z,L_1fd8                      ; 1fd8
1fa7  78             LD A,B                           
1fa8  fe 03          CP 3                             
1faa  ca 35 20       JP z,menu_addr_invalid           ; 2035
1fad  04             INC B                            
1fae  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
1fb1  cd 29 20       CALL is_digit                    ; 2029
1fb4  d2 35 20       JP nc,menu_addr_invalid          ; 2035
1fb7  77             LD (HL),A                        
1fb8  23             INC HL                           
1fb9  e5             PUSH HL                          
1fba  c5             PUSH BC                          
1fbb  78             LD A,B                           
1fbc  fe 01          CP 1                             
1fbe  20 12          JR nz,L_1fd2                     ; 1fd2
1fc0  cd 99 19       CALL clear_framebuf              ; 1999
1fc3  2a 9b 41       LD HL,(FB_COL)                   ; 419b
1fc6  22 98 41       LD (FB_COLPTR),HL                ; 4198
1fc9  21 f3 2f       LD HL,MENU_STRINGS               ; 2ff3
1fcc  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
1fcf  cd f8 29       CALL menu_show_text              ; 29f8

L_1fd2:
1fd2  cd dd 07       CALL glyph_lookup                ; 07dd
1fd5  c3 97 1f       JP L_1f97                        ; 1f97

L_1fd8:
1fd8  78             LD A,B                           
1fd9  fe 00          CP 0                             
1fdb  20 02          JR nz,L_1fdf                     ; 1fdf
1fdd  06 03          LD B,3                           

L_1fdf:
1fdf  21 c5 43       LD HL,MENU_ENTRY_BUF             ; 43c5
1fe2  cd fc 1f       CALL ascii_dec_to_bin            ; 1ffc
1fe5  da 35 20       JP c,menu_addr_invalid           ; 2035
1fe8  fe 2a          CP 0x2a                          
1fea  ca 35 20       JP z,menu_addr_invalid           ; 2035
1fed  fe 00          CP 0                             
1fef  ca 35 20       JP z,menu_addr_invalid           ; 2035
1ff2  32 cb 43       LD (MY_ADDRESS),A                ; 43cb
1ff5  2f             CPL                              
1ff6  32 cc 43       LD (MY_ADDRESS_INV),A            ; 43cc
1ff9  c3 73 21       JP L_2173                        ; 2173

; ----------------------------------------------------------------
; ascii_dec_to_bin
; Convert B ASCII digits at (HL) to binary in A (C set if invalid)
ascii_dec_to_bin:
1ffc  c5             PUSH BC                          
1ffd  dd 21 26 20    LD IX,0x2026                     
2001  05             DEC B                            
2002  58             LD E,B                           
2003  16 00          LD D,0                           
2005  dd 19          ADD IX,DE                        
2007  af             XOR A                            
2008  c1             POP BC                           

L_2009:
2009  c5             PUSH BC                          
200a  5f             LD E,A                           
200b  7e             LD A,(HL)                        
200c  e6 0f          AND 15                           
200e  47             LD B,A                           
200f  fe 00          CP 0                             
2011  7b             LD A,E                           
2012  28 07          JR z,L_201b                      ; 201b

L_2014:
2014  dd 86 00       ADD A,(IX)                       
2017  38 0a          JR c,L_2023                      ; 2023
2019  10 f9          DJNZ L_2014                      ; 2014

L_201b:
201b  23             INC HL                           
201c  dd 2b          DEC IX                           
201e  c1             POP BC                           
201f  10 e8          DJNZ L_2009                      ; 2009
2021  b7             OR A                             
2022  c9             RET                              

L_2023:
2023  c1             POP BC                           
2024  37             SCF                              
2025  c9             RET                              
2026  db 0x01,0x0a,"d"

; ----------------------------------------------------------------
; is_digit
; C set if A is ASCII 0-9
is_digit:
2029  fe 3a          CP 0x3a                          
202b  30 06          JR nc,L_2033                     ; 2033
202d  fe 30          CP 0x30                          
202f  38 02          JR c,L_2033                      ; 2033
2031  37             SCF                              
2032  c9             RET                              

L_2033:
2033  b7             OR A                             
2034  c9             RET                              

; ----------------------------------------------------------------
; menu_addr_invalid
menu_addr_invalid:
2035  3e ff          LD A,0xff                        
2037  32 24 42       LD (0x4224),A                    
203a  21 46 30       LD HL,0x3046                     
203d  22 0a 42       LD (0x420a),HL                   
2040  cd 28 27       CALL editor_redraw               ; 2728
2043  c3 3a 1f       JP L_1f3a                        ; 1f3a

L_2046:
2046  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346

L_2049:
2049  7e             LD A,(HL)                        
204a  fe 03          CP 3                             
204c  28 03          JR z,L_2051                      ; 2051
204e  23             INC HL                           
204f  18 f8          JR L_2049                        ; 2049

L_2051:
2051  2b             DEC HL                           
2052  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2055  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2058  7e             LD A,(HL)                        
2059  fe d0          CP 0xd0                          
205b  da d2 1a       JP c,editor_loop                 ; 1ad2
205e  fe db          CP 0xdb                          
2060  d2 d2 1a       JP nc,editor_loop                ; 1ad2
2063  2b             DEC HL                           
2064  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2067  c3 87 20       JP L_2087                        ; 2087

L_206a:
206a  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
206d  7e             LD A,(HL)                        
206e  fe d0          CP 0xd0                          
2070  da d2 1a       JP c,editor_loop                 ; 1ad2
2073  fe db          CP 0xdb                          
2075  d2 d2 1a       JP nc,editor_loop                ; 1ad2
2078  c3 87 20       JP L_2087                        ; 2087

; ---------------- data: STR_TOP_OF_MSG (207b-2086) 
STR_TOP_OF_MSG:
        db "TOP OF MSG ",0x00                                                  ; 207b

L_2087:
2087  cd 98 06       CALL init_render                 ; 0698
208a  2a 9b 41       LD HL,(FB_COL)                   ; 419b
208d  22 98 41       LD (FB_COLPTR),HL                ; 4198
2090  21 7b 20       LD HL,STR_TOP_OF_MSG             ; 207b
2093  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
2096  cd f8 29       CALL menu_show_text              ; 29f8
2099  06 02          LD B,2                           
209b  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346

L_209e:
209e  7e             LD A,(HL)                        
209f  fe da          CP 0xda                          
20a1  20 04          JR nz,L_20a7                     ; 20a7
20a3  3e 44          LD A,0x44                        
20a5  18 0d          JR L_20b4                        ; 20b4

L_20a7:
20a7  e6 0f          AND 15                           
20a9  f6 30          OR 0x30                          
20ab  cd 29 20       CALL is_digit                    ; 2029
20ae  da b4 20       JP c,L_20b4                      ; 20b4
20b1  3e 30          LD A,0x30                        
20b3  77             LD (HL),A                        

L_20b4:
20b4  32 0e 42       LD (CUR_CHAR),A                  ; 420e
20b7  e5             PUSH HL                          
20b8  c5             PUSH BC                          
20b9  cd dd 07       CALL glyph_lookup                ; 07dd
20bc  c1             POP BC                           
20bd  e1             POP HL                           
20be  23             INC HL                           
20bf  10 dd          DJNZ L_209e                      ; 209e
20c1  c3 d5 1a       JP L_1ad5                        ; 1ad5

L_20c4:
20c4  cd 98 06       CALL init_render                 ; 0698
20c7  2a 9b 41       LD HL,(FB_COL)                   ; 419b
20ca  22 98 41       LD (FB_COLPTR),HL                ; 4198
20cd  21 0d 30       LD HL,0x300d                     
20d0  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
20d3  cd f8 29       CALL menu_show_text              ; 29f8
20d6  cd 09 23       CALL menu_getchar                ; 2309
20d9  e6 5f          AND 0x5f                         
20db  fe 59          CP 0x59                          
20dd  c2 d2 1a       JP nz,editor_loop                ; 1ad2
20e0  cd f7 13       CALL store_clear_all             ; 13f7
20e3  cd 38 1c       CALL store_finalize              ; 1c38
20e6  3e 00          LD A,0                           
20e8  c3 19 22       JP L_2219                        ; 2219

L_20eb:
20eb  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
20ee  b7             OR A                             
20ef  c2 6a 20       JP nz,L_206a                     ; 206a
20f2  cd f8 20       CALL sub_20f8                    ; 20f8
20f5  c3 87 20       JP L_2087                        ; 2087

sub_20f8:
20f8  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
20fb  11 e2 43       LD DE,MSG_STORE                  ; 43e2
20fe  b7             OR A                             
20ff  ed 52          SBC HL,DE                        
2101  e5             PUSH HL                          
2102  c1             POP BC                           
2103  fe d0          CP 0xd0                          
2105  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346

L_2108:
2108  7e             LD A,(HL)                        
2109  fe d0          CP 0xd0                          
210b  da 15 21       JP c,L_2115                      ; 2115
210e  fe db          CP 0xdb                          
2110  d2 15 21       JP nc,L_2115                     ; 2115
2113  18 0a          JR L_211f                        ; 211f

L_2115:
2115  2b             DEC HL                           
2116  0b             DEC BC                           
2117  78             LD A,B                           
2118  b1             OR C                             
2119  ca 3e 2a       JP z,pkt_process_end             ; 2a3e
211c  c3 08 21       JP L_2108                        ; 2108

L_211f:
211f  23             INC HL                           
2120  7e             LD A,(HL)                        
2121  fe d0          CP 0xd0                          
2123  da 2d 21       JP c,L_212d                      ; 212d
2126  fe db          CP 0xdb                          
2128  d2 2d 21       JP nc,L_212d                     ; 212d
212b  18 01          JR L_212e                        ; 212e

L_212d:
212d  2b             DEC HL                           

L_212e:
212e  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2131  23             INC HL                           
2132  22 40 43       LD (MOVE_DST),HL                 ; 4340
2135  eb             EX DE,HL                         
2136  2a d8 43       LD HL,(STORE_LIMIT)              ; 43d8
2139  b7             OR A                             
213a  ed 52          SBC HL,DE                        
213c  e5             PUSH HL                          
213d  c1             POP BC                           
213e  03             INC BC                           
213f  eb             EX DE,HL                         
2140  3e 03          LD A,3                           
2142  ed b1          CPIR                             
2144  78             LD A,B                           
2145  b1             OR C                             
2146  ca 3e 2a       JP z,pkt_process_end             ; 2a3e
2149  2b             DEC HL                           
214a  22 42 43       LD (MOVE_SRC),HL                 ; 4342
214d  ed 5b d8 43    LD DE,(STORE_LIMIT)              ; 43d8
2151  eb             EX DE,HL                         
2152  b7             OR A                             
2153  ed 52          SBC HL,DE                        
2155  44             LD B,H                           
2156  4d             LD C,L                           
2157  03             INC BC                           
2158  2a 42 43       LD HL,(MOVE_SRC)                 ; 4342
215b  ed 5b 40 43    LD DE,(MOVE_DST)                 ; 4340
215f  ed b0          LDIR                             
2161  cd 38 1c       CALL store_finalize              ; 1c38
2164  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2167  2b             DEC HL                           
2168  22 46 43       LD (STORE_CURSOR),HL             ; 4346
216b  c9             RET                              

L_216c:
216c  3a 58 43       LD A,(0x4358)                    
216f  2f             CPL                              
2170  32 58 43       LD (0x4358),A                    

L_2173:
2173  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2176  7e             LD A,(HL)                        
2177  fe d0          CP 0xd0                          
2179  da d2 1a       JP c,editor_loop                 ; 1ad2
217c  fe db          CP 0xdb                          
217e  d2 d2 1a       JP nc,editor_loop                ; 1ad2
2181  c3 87 20       JP L_2087                        ; 2087

L_2184:
2184  3a 64 43       LD A,(0x4364)                    
2187  2f             CPL                              
2188  32 64 43       LD (0x4364),A                    
218b  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
218e  7e             LD A,(HL)                        
218f  fe d0          CP 0xd0                          
2191  da d2 1a       JP c,editor_loop                 ; 1ad2
2194  fe db          CP 0xdb                          
2196  d2 d2 1a       JP nc,editor_loop                ; 1ad2
2199  c3 87 20       JP L_2087                        ; 2087

L_219c:
219c  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
219f  7e             LD A,(HL)                        
21a0  fe 03          CP 3                             
21a2  ca d2 1a       JP z,editor_loop                 ; 1ad2
21a5  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
21a8  b7             OR A                             
21a9  c2 4e 1c       JP nz,L_1c4e                     ; 1c4e
21ac  3e ff          LD A,0xff                        
21ae  32 cf 43       LD (0x43cf),A                    
21b1  c3 d2 1a       JP editor_loop                   ; 1ad2

L_21b4:
21b4  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
21b7  7e             LD A,(HL)                        
21b8  fe 03          CP 3                             
21ba  ca d2 1a       JP z,editor_loop                 ; 1ad2
21bd  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
21c0  b7             OR A                             
21c1  c2 4e 1c       JP nz,L_1c4e                     ; 1c4e
21c4  3e ff          LD A,0xff                        
21c6  32 21 42       LD (0x4221),A                    
21c9  c3 d2 1a       JP editor_loop                   ; 1ad2

L_21cc:
21cc  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
21cf  7e             LD A,(HL)                        
21d0  fe 03          CP 3                             
21d2  ca d2 1a       JP z,editor_loop                 ; 1ad2
21d5  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
21d8  b7             OR A                             
21d9  c2 4e 1c       JP nz,L_1c4e                     ; 1c4e
21dc  3e ff          LD A,0xff                        
21de  32 20 42       LD (0x4220),A                    
21e1  c3 d2 1a       JP editor_loop                   ; 1ad2

L_21e4:
21e4  3e ff          LD A,0xff                        
21e6  32 ca 43       LD (0x43ca),A                    
21e9  c3 d2 1a       JP editor_loop                   ; 1ad2

L_21ec:
21ec  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
21ef  7e             LD A,(HL)                        
21f0  fe 03          CP 3                             
21f2  ca d2 1a       JP z,editor_loop                 ; 1ad2
21f5  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
21f8  b7             OR A                             
21f9  c2 4e 1c       JP nz,L_1c4e                     ; 1c4e
21fc  3e ff          LD A,0xff                        
21fe  32 a1 41       LD (FB_TMP),A                    ; 41a1
2201  c3 d2 1a       JP editor_loop                   ; 1ad2
2204  fe 30          CP 0x30                          
2206  20 03          JR nz,L_220b                     ; 220b
2208  3e 39          LD A,0x39                        
220a  c9             RET                              

L_220b:
220b  3d             DEC A                            
220c  c9             RET                              

L_220d:
220d  21 2f 30       LD HL,0x302f                     
2210  cd 25 1e       CALL sub_1e25                    ; 1e25
2213  fe 65          CP 0x65                          
2215  d2 0d 22       JP nc,L_220d                     ; 220d
2218  5f             LD E,A                           

L_2219:
2219  d5             PUSH DE                          
221a  cd 26 04       CALL chan_select                 ; 0426
221d  d1             POP DE                           
221e  b7             OR A                             
221f  c2 3e 2a       JP nz,pkt_process_end            ; 2a3e
2222  22 18 42       LD (INS_PTR),HL                  ; 4218
2225  2b             DEC HL                           
2226  2b             DEC HL                           
2227  22 46 43       LD (STORE_CURSOR),HL             ; 4346
222a  d5             PUSH DE                          
222b  cd 1a 04       CALL chan_find                   ; 041a
222e  d1             POP DE                           
222f  7b             LD A,E                           
2230  fe 64          CP 0x64                          
2232  20 03          JR nz,L_2237                     ; 2237
2234  32 6a 42       LD (CHAN_LOCK),A                 ; 426a

L_2237:
2237  c3 87 20       JP L_2087                        ; 2087

L_223a:
223a  3e ff          LD A,0xff                        
223c  32 5a 43       LD (0x435a),A                    
223f  21 6b 42       LD HL,SEQ_LIST                   ; 426b
2242  06 68          LD B,0x68                        
2244  3e ff          LD A,0xff                        

L_2246:
2246  77             LD (HL),A                        
2247  23             INC HL                           
2248  10 fc          DJNZ L_2246                      ; 2246
224a  32 36 43       LD (0x4336),A                    
224d  21 6b 42       LD HL,SEQ_LIST                   ; 426b
2250  22 d3 42       LD (SEQ_PTR),HL                  ; 42d3
2253  06 67          LD B,0x67                        

L_2255:
2255  c5             PUSH BC                          
2256  21 3b 30       LD HL,0x303b                     
2259  78             LD A,B                           
225a  fe 67          CP 0x67                          
225c  28 05          JR z,L_2263                      ; 2263
225e  cd 32 1e       CALL sub_1e32                    ; 1e32
2261  18 03          JR L_2266                        ; 2266

L_2263:
2263  cd 25 1e       CALL sub_1e25                    ; 1e25

L_2266:
2266  c1             POP BC                           
2267  fe 98          CP 0x98                          
2269  28 3a          JR z,L_22a5                      ; 22a5
226b  fe 97          CP 0x97                          
226d  28 20          JR z,L_228f                      ; 228f
226f  fe 99          CP 0x99                          
2271  28 7c          JR z,L_22ef                      ; 22ef
2273  fe 9a          CP 0x9a                          
2275  ca 5c 1c       JP z,L_1c5c                      ; 1c5c
2278  2a d3 42       LD HL,(SEQ_PTR)                  ; 42d3
227b  77             LD (HL),A                        
227c  23             INC HL                           
227d  22 d3 42       LD (SEQ_PTR),HL                  ; 42d3
2280  10 d3          DJNZ L_2255                      ; 2255
2282  21 78 30       LD HL,0x3078                     
2285  23             INC HL                           
2286  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
2289  cd f8 29       CALL menu_show_text              ; 29f8
228c  cd 21 2a       CALL sub_2a21                    ; 2a21

L_228f:
228f  3e 00          LD A,0                           
2291  32 36 43       LD (0x4336),A                    
2294  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2297  7e             LD A,(HL)                        
2298  fe d0          CP 0xd0                          
229a  da d2 1a       JP c,editor_loop                 ; 1ad2
229d  fe db          CP 0xdb                          
229f  d2 d2 1a       JP nc,editor_loop                ; 1ad2
22a2  c3 87 20       JP L_2087                        ; 2087

L_22a5:
22a5  cd 09 23       CALL menu_getchar                ; 2309
22a8  fe 12          CP 0x12                          
22aa  28 f9          JR z,L_22a5                      ; 22a5
22ac  fe 43          CP 0x43                          
22ae  28 05          JR z,L_22b5                      ; 22b5
22b0  fe 63          CP 0x63                          
22b2  c2 8f 22       JP nz,L_228f                     ; 228f

L_22b5:
22b5  3e ff          LD A,0xff                        
22b7  32 0f 42       LD (0x420f),A                    
22ba  21 09 3c       LD HL,0x3c09                     
22bd  11 a5 43       LD DE,0x43a5                     

L_22c0:
22c0  7e             LD A,(HL)                        
22c1  12             LD (DE),A                        
22c2  fe 03          CP 3                             
22c4  28 04          JR z,L_22ca                      ; 22ca
22c6  23             INC HL                           
22c7  13             INC DE                           
22c8  18 f6          JR L_22c0                        ; 22c0

L_22ca:
22ca  d5             PUSH DE                          
22cb  11 00 00       LD DE,0                          
22ce  01 00 40       LD BC,0x4000                     
22d1  21 00 00       LD HL,0                          

L_22d4:
22d4  1a             LD A,(DE)                        
22d5  d5             PUSH DE                          
22d6  16 00          LD D,0                           
22d8  5f             LD E,A                           
22d9  19             ADD HL,DE                        
22da  d1             POP DE                           
22db  13             INC DE                           
22dc  0b             DEC BC                           
22dd  79             LD A,C                           
22de  b0             OR B                             
22df  20 f3          JR nz,L_22d4                     ; 22d4
22e1  d1             POP DE                           
22e2  cd 41 2a       CALL sub_2a41                    ; 2a41
22e5  13             INC DE                           
22e6  13             INC DE                           
22e7  13             INC DE                           
22e8  13             INC DE                           
22e9  3e 03          LD A,3                           
22eb  12             LD (DE),A                        
22ec  c3 5c 1c       JP L_1c5c                        ; 1c5c

L_22ef:
22ef  21 6b 42       LD HL,SEQ_LIST                   ; 426b
22f2  3e 00          LD A,0                           
22f4  06 64          LD B,0x64                        

L_22f6:
22f6  77             LD (HL),A                        
22f7  23             INC HL                           
22f8  3c             INC A                            
22f9  10 fb          DJNZ L_22f6                      ; 22f6
22fb  36 ff          LD (HL),0xff                     
22fd  23             INC HL                           
22fe  36 ff          LD (HL),0xff                     
2300  23             INC HL                           
2301  36 ff          LD (HL),0xff                     
2303  23             INC HL                           
2304  36 ff          LD (HL),0xff                     
2306  c3 5c 1c       JP L_1c5c                        ; 1c5c

; ----------------------------------------------------------------
; menu_getchar
menu_getchar:
2309  cd 13 23       CALL editor_getkey               ; 2313
230c  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
230f  a7             AND A                            
2310  28 f7          JR z,menu_getchar                ; 2309
2312  c9             RET                              

; ----------------------------------------------------------------
; editor_getkey
; Editor key source: echoes the previous key on the serial TX, then takes a key from the serial RX
; FIFO if present, else from the IR decoder (IR_CODE). So the on-sign editor can be driven from a
; serial terminal as well as the remote.
editor_getkey:
2313  3a d7 43       LD A,(0x43d7)                    
2316  a7             AND A                            
2317  28 03          JR z,L_231c                      ; 231c
2319  cd 71 15       CALL tx_send_byte                ; 1571

L_231c:
231c  cd c5 16       CALL rx_fifo_get                 ; 16c5
231f  da 3f 23       JP c,L_233f                      ; 233f
2322  a7             AND A                            
2323  28 1a          JR z,L_233f                      ; 233f
2325  af             XOR A                            
2326  32 64 43       LD (0x4364),A                    
2329  3a 26 42       LD A,(0x4226)                    
232c  32 27 42       LD (0x4227),A                    
232f  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
2332  32 26 42       LD (0x4226),A                    
2335  3a 28 42       LD A,(RX_BYTE)                   ; 4228
2338  32 25 42       LD (RX_LASTCMD),A                ; 4225
233b  32 d7 43       LD (0x43d7),A                    
233e  c9             RET                              

L_233f:
233f  3a 86 43       LD A,(IR_CODE)                   ; 4386
2342  a7             AND A                            
2343  28 38          JR z,L_237d                      ; 237d
2345  e6 3f          AND 0x3f                         
2347  32 87 43       LD (0x4387),A                    
234a  af             XOR A                            
234b  32 86 43       LD (IR_CODE),A                   ; 4386
234e  3a 87 43       LD A,(0x4387)                    
2351  fe 3e          CP 0x3e                          
2353  28 21          JR z,L_2376                      ; 2376
2355  4f             LD C,A                           
2356  3a 84 43       LD A,(IR_KEY)                    ; 4384
2359  b9             CP C                             
235a  20 28          JR nz,L_2384                     ; 2384
235c  3a 77 43       LD A,(0x4377)                    
235f  a7             AND A                            
2360  20 31          JR nz,L_2393                     ; 2393
2362  fe 24          CP 0x24                          
2364  28 17          JR z,L_237d                      ; 237d
2366  2a 80 43       LD HL,(GEN_COUNTDOWN)            ; 4380
2369  7c             LD A,H                           
236a  b5             OR L                             
236b  20 10          JR nz,L_237d                     ; 237d
236d  21 2c 01       LD HL,0x012c                     
2370  22 80 43       LD (GEN_COUNTDOWN),HL            ; 4380
2373  c3 a3 23       JP L_23a3                        ; 23a3

L_2376:
2376  af             XOR A                            
2377  32 84 43       LD (IR_KEY),A                    ; 4384
237a  32 77 43       LD (0x4377),A                    

L_237d:
237d  af             XOR A                            
237e  32 29 42       LD (0x4229),A                    
2381  c3 18 24       JP L_2418                        ; 2418

L_2384:
2384  3a 87 43       LD A,(0x4387)                    
2387  32 84 43       LD (IR_KEY),A                    ; 4384
238a  32 77 43       LD (0x4377),A                    
238d  af             XOR A                            
238e  32 86 43       LD (IR_CODE),A                   ; 4386
2391  18 ea          JR L_237d                        ; 237d

L_2393:
2393  3a 87 43       LD A,(0x4387)                    
2396  32 84 43       LD (IR_KEY),A                    ; 4384
2399  21 14 05       LD HL,0x0514                     
239c  22 80 43       LD (GEN_COUNTDOWN),HL            ; 4380
239f  af             XOR A                            
23a0  32 77 43       LD (0x4377),A                    

L_23a3:
23a3  3a 87 43       LD A,(0x4387)                    
23a6  fe 1d          CP 0x1d                          
23a8  20 17          JR nz,L_23c1                     ; 23c1
23aa  cd 48 0f       CALL sub_0f48                    ; 0f48
23ad  3a 37 43       LD A,(0x4337)                    
23b0  2f             CPL                              
23b1  32 37 43       LD (0x4337),A                    
23b4  a7             AND A                            
23b5  3e 1d          LD A,0x1d                        
23b7  20 02          JR nz,L_23bb                     ; 23bb
23b9  3e 9f          LD A,0x9f                        

L_23bb:
23bb  32 29 42       LD (0x4229),A                    
23be  c3 08 24       JP L_2408                        ; 2408

L_23c1:
23c1  21 27 24       LD HL,IR_KEY_TABLE               ; 2427
23c4  16 00          LD D,0                           
23c6  5f             LD E,A                           
23c7  19             ADD HL,DE                        
23c8  7e             LD A,(HL)                        
23c9  32 28 42       LD (RX_BYTE),A                   ; 4228
23cc  3a 64 43       LD A,(0x4364)                    
23cf  21 2d 39       LD HL,CHARSET_GRAPHICS           ; 392d
23d2  b7             OR A                             
23d3  20 20          JR nz,L_23f5                     ; 23f5
23d5  3a 37 43       LD A,(0x4337)                    
23d8  21 2d 38       LD HL,CHARSET_LOWER              ; 382d
23db  a7             AND A                            
23dc  28 0e          JR z,L_23ec                      ; 23ec
23de  21 ad 38       LD HL,CHARSET_UPPER2             ; 38ad
23e1  3a 58 43       LD A,(0x4358)                    
23e4  a7             AND A                            
23e5  28 0e          JR z,L_23f5                      ; 23f5
23e7  21 ed 38       LD HL,CHARSET_LOWER2             ; 38ed
23ea  18 09          JR L_23f5                        ; 23f5

L_23ec:
23ec  3a 58 43       LD A,(0x4358)                    
23ef  a7             AND A                            
23f0  28 03          JR z,L_23f5                      ; 23f5
23f2  21 6d 38       LD HL,CHARSET_UPPER              ; 386d

L_23f5:
23f5  3a 28 42       LD A,(RX_BYTE)                   ; 4228
23f8  5f             LD E,A                           
23f9  16 00          LD D,0                           
23fb  19             ADD HL,DE                        
23fc  7e             LD A,(HL)                        
23fd  32 29 42       LD (0x4229),A                    
2400  3e 00          LD A,0                           
2402  32 37 43       LD (0x4337),A                    
2405  cd 48 0f       CALL sub_0f48                    ; 0f48

L_2408:
2408  af             XOR A                            
2409  32 64 43       LD (0x4364),A                    
240c  3a 26 42       LD A,(0x4226)                    
240f  32 27 42       LD (0x4227),A                    
2412  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
2415  32 26 42       LD (0x4226),A                    

L_2418:
2418  3a 29 42       LD A,(0x4229)                    
241b  32 25 42       LD (RX_LASTCMD),A                ; 4225
241e  af             XOR A                            
241f  32 d7 43       LD (0x43d7),A                    
2422  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
2425  a7             AND A                            
2426  c9             RET                              

; ---------------- data: IR_KEY_TABLE (2427-2464) IR/keypad code -> character map
IR_KEY_TABLE:
        db 0x0f,0x33,0x0c,0x0b,0x0d,0x09,0x0a,0x0e,0x03,0x3f,0x3c,0x3b,0x3d,0x39,0x3a,0x3e ; 2427
        db 0x2f,0x13,0x2c,0x2b,0x2d,0x29,0x2a,0x2e,0x24,0x23,0x1c,0x1b,0x1d,0x1d,0x1a,0x22 ; 2437
        db 0x31,0x30,0x37,0x36,0x35,0x08,0x32,0x34,0x01,0x00,0x07,0x06,0x05,0x38,0x02,0x04 ; 2447
        db 0x11,0x10,0x17,0x16,0x15,0x28,0x12,0x14,0x21,0x20,0x27,0x26,0x25,0x18 ; 2457

L_2465:
2465  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2468  7e             LD A,(HL)                        
2469  fe 03          CP 3                             
246b  ca d2 1a       JP z,editor_loop                 ; 1ad2
246e  3a 37 43       LD A,(0x4337)                    
2471  b7             OR A                             
2472  28 0b          JR z,L_247f                      ; 247f
2474  3e ff          LD A,0xff                        
2476  32 41 42       LD (0x4241),A                    
2479  21 9b 2f       LD HL,0x2f9b                     
247c  22 0a 42       LD (0x420a),HL                   

L_247f:
247f  c3 d2 1a       JP editor_loop                   ; 1ad2

L_2482:
2482  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
2485  b7             OR A                             
2486  c2 6a 20       JP nz,L_206a                     ; 206a
2489  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
248c  f6 0f          OR 15                            
248e  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
2491  32 00 80       LD (CTRL_LATCH),A                ; 8000
2494  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2497  7e             LD A,(HL)                        
2498  fe 03          CP 3                             
249a  ca d2 1a       JP z,editor_loop                 ; 1ad2
249d  fe d0          CP 0xd0                          
249f  da aa 24       JP c,L_24aa                      ; 24aa
24a2  fe db          CP 0xdb                          
24a4  d2 aa 24       JP nc,L_24aa                     ; 24aa
24a7  c3 87 20       JP L_2087                        ; 2087

L_24aa:
24aa  3e 00          LD A,0                           
24ac  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
24af  2a 34 42       LD HL,(STORE_END)                ; 4234
24b2  2b             DEC HL                           
24b3  22 34 42       LD (STORE_END),HL                ; 4234
24b6  cd ea 0c       CALL sub_0cea                    ; 0cea
24b9  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
24bc  23             INC HL                           
24bd  22 40 43       LD (MOVE_DST),HL                 ; 4340
24c0  23             INC HL                           
24c1  22 42 43       LD (MOVE_SRC),HL                 ; 4342
24c4  ed 5b d8 43    LD DE,(STORE_LIMIT)              ; 43d8
24c8  eb             EX DE,HL                         
24c9  b7             OR A                             
24ca  ed 52          SBC HL,DE                        
24cc  44             LD B,H                           
24cd  4d             LD C,L                           
24ce  2a 42 43       LD HL,(MOVE_SRC)                 ; 4342
24d1  ed 5b 40 43    LD DE,(MOVE_DST)                 ; 4340
24d5  ed b0          LDIR                             
24d7  3e ff          LD A,0xff                        
24d9  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
24dc  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
24df  7e             LD A,(HL)                        
24e0  fe d0          CP 0xd0                          
24e2  da d2 1a       JP c,editor_loop                 ; 1ad2
24e5  fe db          CP 0xdb                          
24e7  d2 d2 1a       JP nc,editor_loop                ; 1ad2
24ea  2b             DEC HL                           
24eb  22 46 43       LD (STORE_CURSOR),HL             ; 4346
24ee  c3 87 20       JP L_2087                        ; 2087
24f1  db 0xc3,0xd2,0x1a

L_24f4:
24f4  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
24f7  7e             LD A,(HL)                        
24f8  fe 03          CP 3                             
24fa  28 10          JR z,L_250c                      ; 250c
24fc  23             INC HL                           
24fd  7e             LD A,(HL)                        
24fe  fe d0          CP 0xd0                          
2500  da 09 25       JP c,L_2509                      ; 2509
2503  fe db          CP 0xdb                          
2505  d2 09 25       JP nc,L_2509                     ; 2509
2508  23             INC HL                           

L_2509:
2509  22 46 43       LD (STORE_CURSOR),HL             ; 4346

L_250c:
250c  c3 d2 1a       JP editor_loop                   ; 1ad2

L_250f:
250f  06 08          LD B,8                           
2511  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346

L_2514:
2514  7e             LD A,(HL)                        
2515  fe 03          CP 3                             
2517  28 06          JR z,L_251f                      ; 251f
2519  23             INC HL                           
251a  22 46 43       LD (STORE_CURSOR),HL             ; 4346
251d  10 f5          DJNZ L_2514                      ; 2514

L_251f:
251f  c3 d2 1a       JP editor_loop                   ; 1ad2

L_2522:
2522  dd 2a 46 43    LD IX,(STORE_CURSOR)             ; 4346
2526  dd 7e 00       LD A,(IX)                        
2529  fe d0          CP 0xd0                          
252b  da 36 25       JP c,L_2536                      ; 2536
252e  fe db          CP 0xdb                          
2530  d2 36 25       JP nc,L_2536                     ; 2536
2533  c3 87 20       JP L_2087                        ; 2087

L_2536:
2536  dd 2b          DEC IX                           
2538  dd 22 46 43    LD (STORE_CURSOR),IX             ; 4346
253c  dd 7e 00       LD A,(IX)                        
253f  fe d0          CP 0xd0                          
2541  da d2 1a       JP c,editor_loop                 ; 1ad2
2544  fe db          CP 0xdb                          
2546  d2 d2 1a       JP nc,editor_loop                ; 1ad2
2549  dd 2b          DEC IX                           
254b  dd 22 46 43    LD (STORE_CURSOR),IX             ; 4346
254f  c3 87 20       JP L_2087                        ; 2087

L_2552:
2552  06 08          LD B,8                           
2554  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2557  7e             LD A,(HL)                        
2558  fe d0          CP 0xd0                          
255a  da 65 25       JP c,L_2565                      ; 2565
255d  fe db          CP 0xdb                          
255f  d2 65 25       JP nc,L_2565                     ; 2565
2562  c3 87 20       JP L_2087                        ; 2087

L_2565:
2565  2b             DEC HL                           
2566  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2569  7e             LD A,(HL)                        
256a  fe d0          CP 0xd0                          
256c  da 52 25       JP c,L_2552                      ; 2552
256f  fe db          CP 0xdb                          
2571  d2 52 25       JP nc,L_2552                     ; 2552
2574  2b             DEC HL                           
2575  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2578  c3 87 20       JP L_2087                        ; 2087
257b  10 e8          DJNZ L_2565                      ; 2565
257d  c3 d2 1a       JP editor_loop                   ; 1ad2

L_2580:
2580  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2583  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
2586  b7             OR A                             
2587  c2 6a 20       JP nz,L_206a                     ; 206a
258a  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
258d  7e             LD A,(HL)                        
258e  fe 03          CP 3                             
2590  ca 15 26       JP z,L_2615                      ; 2615
2593  fe d0          CP 0xd0                          
2595  da a1 25       JP c,L_25a1                      ; 25a1
2598  fe db          CP 0xdb                          
259a  d2 a1 25       JP nc,L_25a1                     ; 25a1
259d  23             INC HL                           
259e  22 46 43       LD (STORE_CURSOR),HL             ; 4346

L_25a1:
25a1  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
25a4  f6 0f          OR 15                            
25a6  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
25a9  32 00 80       LD (CTRL_LATCH),A                ; 8000
25ac  3e 00          LD A,0                           
25ae  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
25b1  2a 34 42       LD HL,(STORE_END)                ; 4234
25b4  23             INC HL                           
25b5  22 3e 43       LD (STORE_TMP),HL                ; 433e
25b8  ed 5b d8 43    LD DE,(STORE_LIMIT)              ; 43d8
25bc  b7             OR A                             
25bd  ed 52          SBC HL,DE                        
25bf  7c             LD A,H                           
25c0  b5             OR L                             
25c1  20 0e          JR nz,L_25d1                     ; 25d1
25c3  3e ff          LD A,0xff                        
25c5  32 24 42       LD (0x4224),A                    
25c8  21 57 30       LD HL,0x3057                     
25cb  22 0a 42       LD (0x420a),HL                   
25ce  c3 d2 1a       JP editor_loop                   ; 1ad2

L_25d1:
25d1  2a 3e 43       LD HL,(STORE_TMP)                ; 433e
25d4  22 34 42       LD (STORE_END),HL                ; 4234
25d7  cd 18 26       CALL store_make_room             ; 2618
25da  2a d8 43       LD HL,(STORE_LIMIT)              ; 43d8
25dd  22 40 43       LD (MOVE_DST),HL                 ; 4340
25e0  2b             DEC HL                           
25e1  22 42 43       LD (MOVE_SRC),HL                 ; 4342
25e4  ed 5b 46 43    LD DE,(STORE_CURSOR)             ; 4346
25e8  b7             OR A                             
25e9  ed 52          SBC HL,DE                        
25eb  44             LD B,H                           
25ec  4d             LD C,L                           
25ed  2a 42 43       LD HL,(MOVE_SRC)                 ; 4342
25f0  ed 5b 40 43    LD DE,(MOVE_DST)                 ; 4340
25f4  03             INC BC                           
25f5  ed b8          LDDR                             
25f7  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
25fa  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
25fd  77             LD (HL),A                        
25fe  2a 34 42       LD HL,(STORE_END)                ; 4234
2601  ed 5b de 43    LD DE,(0x43de)                   
2605  b7             OR A                             
2606  ed 52          SBC HL,DE                        
2608  20 0b          JR nz,L_2615                     ; 2615
260a  3e ff          LD A,0xff                        
260c  32 24 42       LD (0x4224),A                    
260f  21 67 30       LD HL,0x3067                     
2612  22 0a 42       LD (0x420a),HL                   

L_2615:
2615  c3 d2 1a       JP editor_loop                   ; 1ad2

; ----------------------------------------------------------------
; store_make_room
store_make_room:
2618  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
261b  ed 5b d8 43    LD DE,(STORE_LIMIT)              ; 43d8
261f  23             INC HL                           
2620  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2623  b7             OR A                             
2624  ed 52          SBC HL,DE                        
2626  20 13          JR nz,L_263b                     ; 263b
2628  3a 17 42       LD A,(MENU_ACTIVE)               ; 4217
262b  a7             AND A                            
262c  20 08          JR nz,L_2636                     ; 2636
262e  21 e2 43       LD HL,MSG_STORE                  ; 43e2
2631  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2634  18 05          JR L_263b                        ; 263b

L_2636:
2636  3e ff          LD A,0xff                        
2638  32 36 42       LD (0x4236),A                    

L_263b:
263b  c9             RET                              

sub_263c:
263c  cd 4c 26       CALL sub_264c                    ; 264c
263f  cd d1 26       CALL sub_26d1                    ; 26d1
2642  cd 61 26       CALL sub_2661                    ; 2661
2645  cd 75 26       CALL editor_key_to_attr          ; 2675
2648  cd bf 17       CALL rx_cmd_check                ; 17bf
264b  c9             RET                              

sub_264c:
264c  3a 21 42       LD A,(0x4221)                    
264f  b7             OR A                             
2650  c8             RET z                            
2651  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
2654  e6 0f          AND 15                           
2656  f6 a0          OR 0xa0                          
2658  32 25 42       LD (RX_LASTCMD),A                ; 4225
265b  3e 00          LD A,0                           
265d  32 21 42       LD (0x4221),A                    
2660  c9             RET                              

sub_2661:
2661  3a cf 43       LD A,(0x43cf)                    
2664  a7             AND A                            
2665  c8             RET z                            
2666  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
2669  e6 07          AND 7                            
266b  f6 f0          OR 0xf0                          
266d  32 25 42       LD (RX_LASTCMD),A                ; 4225
2670  af             XOR A                            
2671  32 cf 43       LD (0x43cf),A                    
2674  c9             RET                              

; ----------------------------------------------------------------
; editor_key_to_attr
; Translate editor function keys to message bytes: 1E->B8 graphic,11->B9 thin,19->BA wait,14->B0
; remark,12->06 pause,15->BC rainbow, 8F.. colours etc.
editor_key_to_attr:
2675  3a ca 43       LD A,(0x43ca)                    
2678  a7             AND A                            
2679  c8             RET z                            
267a  af             XOR A                            
267b  32 ca 43       LD (0x43ca),A                    
267e  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
2681  0e b8          LD C,0xb8                        
2683  fe 1e          CP 0x1e                          
2685  28 45          JR z,L_26cc                      ; 26cc
2687  0c             INC C                            
2688  fe 11          CP 0x11                          
268a  28 40          JR z,L_26cc                      ; 26cc
268c  0c             INC C                            
268d  fe 19          CP 0x19                          
268f  28 3b          JR z,L_26cc                      ; 26cc
2691  0e b0          LD C,0xb0                        
2693  fe 14          CP 0x14                          
2695  28 35          JR z,L_26cc                      ; 26cc
2697  0e 06          LD C,6                           
2699  fe 12          CP 0x12                          
269b  28 2f          JR z,L_26cc                      ; 26cc
269d  0e bc          LD C,0xbc                        
269f  fe 15          CP 0x15                          
26a1  28 29          JR z,L_26cc                      ; 26cc
26a3  fe 8f          CP 0x8f                          
26a5  28 25          JR z,L_26cc                      ; 26cc
26a7  0e 3f          LD C,0x3f                        
26a9  fe 51          CP 0x51                          
26ab  28 1f          JR z,L_26cc                      ; 26cc
26ad  fe 71          CP 0x71                          
26af  28 1b          JR z,L_26cc                      ; 26cc
26b1  0e 21          LD C,0x21                        
26b3  fe 58          CP 0x58                          
26b5  28 15          JR z,L_26cc                      ; 26cc
26b7  fe 78          CP 0x78                          
26b9  28 11          JR z,L_26cc                      ; 26cc
26bb  0e 5e          LD C,0x5e                        
26bd  fe 1f          CP 0x1f                          
26bf  28 0b          JR z,L_26cc                      ; 26cc
26c1  0e be          LD C,0xbe                        
26c3  fe 10          CP 0x10                          
26c5  28 05          JR z,L_26cc                      ; 26cc
26c7  e1             POP HL                           
26c8  e1             POP HL                           
26c9  c3 6a 20       JP L_206a                        ; 206a

L_26cc:
26cc  79             LD A,C                           
26cd  32 25 42       LD (RX_LASTCMD),A                ; 4225
26d0  c9             RET                              

sub_26d1:
26d1  3a 20 42       LD A,(0x4220)                    
26d4  a7             AND A                            
26d5  20 07          JR nz,L_26de                     ; 26de
26d7  3a a1 41       LD A,(FB_TMP)                    ; 41a1
26da  a7             AND A                            
26db  20 1e          JR nz,L_26fb                     ; 26fb
26dd  c9             RET                              

L_26de:
26de  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
26e1  e6 0f          AND 15                           
26e3  3d             DEC A                            
26e4  fe 0a          CP 10                            
26e6  38 02          JR c,L_26ea                      ; 26ea
26e8  3e 02          LD A,2                           

L_26ea:
26ea  00             NOP                              
26eb  21 18 27       LD HL,FG_IDX_TABLE               ; 2718
26ee  4f             LD C,A                           
26ef  06 00          LD B,0                           
26f1  09             ADD HL,BC                        
26f2  7e             LD A,(HL)                        
26f3  32 25 42       LD (RX_LASTCMD),A                ; 4225
26f6  af             XOR A                            
26f7  32 20 42       LD (0x4220),A                    
26fa  c9             RET                              

L_26fb:
26fb  3a 25 42       LD A,(RX_LASTCMD)                ; 4225
26fe  e6 07          AND 7                            
2700  3d             DEC A                            
2701  fe 06          CP 6                             
2703  38 02          JR c,L_2707                      ; 2707
2705  3e 05          LD A,5                           

L_2707:
2707  00             NOP                              
2708  21 22 27       LD HL,BG_IDX_TABLE               ; 2722
270b  4f             LD C,A                           
270c  06 00          LD B,0                           
270e  09             ADD HL,BC                        
270f  7e             LD A,(HL)                        
2710  32 25 42       LD (RX_LASTCMD),A                ; 4225
2713  af             XOR A                            
2714  32 a1 41       LD (FB_TMP),A                    ; 41a1
2717  c9             RET                              

; ---------------- data: FG_IDX_TABLE (2718-2721) cmd 15 n: foreground colour codes (Red,Orange,Yellow,Lime,Green,84,8E,Black,8B,81)
FG_IDX_TABLE:
        db 0x8c,0x8d,0x8f,0x87,0x83,0x84,0x8e,0x80,0x8b,0x81                   ; 2718

; ---------------- data: BG_IDX_TABLE (2722-2727) cmd 16 n: background colour codes
BG_IDX_TABLE:
        db 0x91,0x93,0x93,0x93,0x92,0x90                                       ; 2722

; ----------------------------------------------------------------
; editor_redraw
; Redraw the editor view of the current message
editor_redraw:
2728  cd ac 19       CALL clear_txbuf                 ; 19ac
272b  cd 98 06       CALL init_render                 ; 0698
272e  af             XOR A                            
272f  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
2732  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
2735  f6 0f          OR 15                            
2737  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
273a  32 00 80       LD (CTRL_LATCH),A                ; 8000
273d  3a 43 42       LD A,(0x4243)                    
2740  a7             AND A                            
2741  c2 f3 28       JP nz,L_28f3                     ; 28f3
2744  3a 36 43       LD A,(0x4336)                    
2747  cb 7f          BIT 7,A                          
2749  c2 f3 28       JP nz,L_28f3                     ; 28f3
274c  3a 99 43       LD A,(0x4399)                    
274f  a7             AND A                            
2750  c2 f3 28       JP nz,L_28f3                     ; 28f3
2753  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2756  7e             LD A,(HL)                        
2757  fe d0          CP 0xd0                          
2759  da 64 27       JP c,L_2764                      ; 2764
275c  fe db          CP 0xdb                          
275e  d2 64 27       JP nc,L_2764                     ; 2764
2761  c3 f3 28       JP L_28f3                        ; 28f3

L_2764:
2764  11 15 00       LD DE,0x15                       
2767  b7             OR A                             
2768  ed 52          SBC HL,DE                        
276a  22 44 43       LD (0x4344),HL                   
276d  ed 5b 18 42    LD DE,(INS_PTR)                  ; 4218
2771  b7             OR A                             
2772  ed 52          SBC HL,DE                        
2774  30 04          JR nc,L_277a                     ; 277a
2776  eb             EX DE,HL                         
2777  22 44 43       LD (0x4344),HL                   

L_277a:
277a  2a 18 42       LD HL,(INS_PTR)                  ; 4218
277d  22 5a 42       LD (0x425a),HL                   

L_2780:
2780  2a 5a 42       LD HL,(0x425a)                   
2783  7e             LD A,(HL)                        
2784  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2787  3e ff          LD A,0xff                        
2789  32 3a 43       LD (TINY_MODE),A                 ; 433a
278c  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
278f  fe 20          CP 0x20                          
2791  20 11          JR nz,L_27a4                     ; 27a4
2793  3a 9a 43       LD A,(0x439a)                    
2796  a7             AND A                            
2797  ca b0 28       JP z,L_28b0                      ; 28b0
279a  af             XOR A                            
279b  32 3b 43       LD (0x433b),A                    
279e  32 39 43       LD (FONT_MODE),A                 ; 4339
27a1  c3 b0 28       JP L_28b0                        ; 28b0

L_27a4:
27a4  cb 7f          BIT 7,A                          
27a6  c2 b0 27       JP nz,L_27b0                     ; 27b0
27a9  e6 60          AND 0x60                         
27ab  28 26          JR z,L_27d3                      ; 27d3
27ad  c3 b0 28       JP L_28b0                        ; 28b0

L_27b0:
27b0  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
27b3  fe 94          CP 0x94                          
27b5  da d3 27       JP c,L_27d3                      ; 27d3
27b8  fe 9f          CP 0x9f                          
27ba  da b0 28       JP c,L_28b0                      ; 28b0
27bd  e6 f0          AND 0xf0                         
27bf  fe c0          CP 0xc0                          
27c1  ca b0 28       JP z,L_28b0                      ; 28b0
27c4  fe e0          CP 0xe0                          
27c6  ca b0 28       JP z,L_28b0                      ; 28b0
27c9  fe d0          CP 0xd0                          
27cb  ca b0 28       JP z,L_28b0                      ; 28b0
27ce  fe a0          CP 0xa0                          
27d0  ca b0 28       JP z,L_28b0                      ; 28b0

L_27d3:
27d3  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
27d6  fe 15          CP 0x15                          
27d8  ca b0 28       JP z,L_28b0                      ; 28b0
27db  fe 16          CP 0x16                          
27dd  ca b0 28       JP z,L_28b0                      ; 28b0
27e0  fe bd          CP 0xbd                          
27e2  20 07          JR nz,L_27eb                     ; 27eb
27e4  af             XOR A                            
27e5  32 9a 43       LD (0x439a),A                    
27e8  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e

L_27eb:
27eb  fe 0f          CP 15                            
27ed  ca 69 28       JP z,L_2869                      ; 2869
27f0  fe 19          CP 0x19                          
27f2  ca 69 28       JP z,L_2869                      ; 2869
27f5  fe 1a          CP 0x1a                          
27f7  ca 69 28       JP z,L_2869                      ; 2869
27fa  fe 1b          CP 0x1b                          
27fc  ca 69 28       JP z,L_2869                      ; 2869
27ff  fe 18          CP 0x18                          
2801  ca 78 28       JP z,L_2878                      ; 2878
2804  fe 11          CP 0x11                          
2806  c2 12 28       JP nz,L_2812                     ; 2812
2809  af             XOR A                            
280a  32 1e 42       LD (0x421e),A                    
280d  32 39 43       LD (FONT_MODE),A                 ; 4339
2810  18 6b          JR L_287d                        ; 287d

L_2812:
2812  fe 14          CP 0x14                          
2814  c2 1e 28       JP nz,L_281e                     ; 281e
2817  3e 10          LD A,0x10                        
2819  32 a2 43       LD (0x43a2),A                    
281c  18 5f          JR L_287d                        ; 287d

L_281e:
281e  fe 13          CP 0x13                          
2820  c2 2a 28       JP nz,L_282a                     ; 282a
2823  3e 64          LD A,0x64                        
2825  32 39 43       LD (FONT_MODE),A                 ; 4339
2828  18 53          JR L_287d                        ; 287d

L_282a:
282a  fe 12          CP 0x12                          
282c  c2 37 28       JP nz,L_2837                     ; 2837
282f  af             XOR A                            
2830  cb cf          SET 1,A                          
2832  32 39 43       LD (FONT_MODE),A                 ; 4339
2835  18 46          JR L_287d                        ; 287d

L_2837:
2837  fe 10          CP 0x10                          
2839  c2 47 28       JP nz,L_2847                     ; 2847
283c  af             XOR A                            
283d  cb cf          SET 1,A                          
283f  cb df          SET 3,A                          
2841  32 39 43       LD (FONT_MODE),A                 ; 4339
2844  c3 7d 28       JP L_287d                        ; 287d

L_2847:
2847  fe b9          CP 0xb9                          
2849  c2 58 28       JP nz,L_2858                     ; 2858
284c  3e ff          LD A,0xff                        
284e  32 d6 43       LD (0x43d6),A                    
2851  af             XOR A                            
2852  32 3b 43       LD (0x433b),A                    
2855  c3 7d 28       JP L_287d                        ; 287d

L_2858:
2858  fe 1f          CP 0x1f                          
285a  c2 7d 28       JP nz,L_287d                     ; 287d
285d  af             XOR A                            
285e  32 39 43       LD (FONT_MODE),A                 ; 4339
2861  3e ff          LD A,0xff                        
2863  32 9a 43       LD (0x439a),A                    
2866  c3 7d 28       JP L_287d                        ; 287d

L_2869:
2869  3a d6 43       LD A,(0x43d6)                    
286c  a7             AND A                            
286d  c2 7d 28       JP nz,L_287d                     ; 287d
2870  3e ff          LD A,0xff                        
2872  32 3b 43       LD (0x433b),A                    
2875  c3 7d 28       JP L_287d                        ; 287d

L_2878:
2878  3e 00          LD A,0                           
287a  32 3b 43       LD (0x433b),A                    

L_287d:
287d  2a 5a 42       LD HL,(0x425a)                   
2880  ed 5b 44 43    LD DE,(0x4344)                   
2884  b7             OR A                             
2885  eb             EX DE,HL                         
2886  ed 52          SBC HL,DE                        
2888  eb             EX DE,HL                         
2889  da 92 28       JP c,L_2892                      ; 2892
288c  ca 92 28       JP z,L_2892                      ; 2892
288f  c3 e0 28       JP L_28e0                        ; 28e0

L_2892:
2892  21 62 2d       LD HL,0x2d62                     
2895  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
2898  5f             LD E,A                           
2899  16 00          LD D,0                           
289b  cb 23          SLA E                            
289d  cb 12          RL D                             
289f  19             ADD HL,DE                        
28a0  5e             LD E,(HL)                        
28a1  23             INC HL                           
28a2  56             LD D,(HL)                        
28a3  ed 53 3d 42    LD (MENU_TEXT_PTR),DE            ; 423d
28a7  cd f8 29       CALL menu_show_text              ; 29f8
28aa  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
28ad  c3 e0 28       JP L_28e0                        ; 28e0

L_28b0:
28b0  2a 5a 42       LD HL,(0x425a)                   
28b3  ed 5b 44 43    LD DE,(0x4344)                   
28b7  b7             OR A                             
28b8  eb             EX DE,HL                         
28b9  ed 52          SBC HL,DE                        
28bb  eb             EX DE,HL                         
28bc  da c5 28       JP c,L_28c5                      ; 28c5
28bf  ca c5 28       JP z,L_28c5                      ; 28c5
28c2  c3 e0 28       JP L_28e0                        ; 28e0

L_28c5:
28c5  af             XOR A                            
28c6  32 3a 43       LD (TINY_MODE),A                 ; 433a
28c9  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
28cc  e6 f0          AND 0xf0                         
28ce  fe a0          CP 0xa0                          
28d0  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
28d3  20 05          JR nz,L_28da                     ; 28da
28d5  e6 0f          AND 15                           
28d7  32 0e 42       LD (CUR_CHAR),A                  ; 420e

L_28da:
28da  cd 2a 07       CALL sub_072a                    ; 072a
28dd  cd dd 07       CALL glyph_lookup                ; 07dd

L_28e0:
28e0  2a 5a 42       LD HL,(0x425a)                   
28e3  23             INC HL                           
28e4  22 5a 42       LD (0x425a),HL                   
28e7  ed 5b 46 43    LD DE,(STORE_CURSOR)             ; 4346
28eb  eb             EX DE,HL                         
28ec  b7             OR A                             
28ed  ed 52          SBC HL,DE                        
28ef  eb             EX DE,HL                         
28f0  d2 80 27       JP nc,L_2780                     ; 2780

L_28f3:
28f3  3e ff          LD A,0xff                        
28f5  32 3a 43       LD (TINY_MODE),A                 ; 433a
28f8  3a 21 42       LD A,(0x4221)                    
28fb  a7             AND A                            
28fc  28 06          JR z,L_2904                      ; 2904
28fe  21 e3 2f       LD HL,0x2fe3                     
2901  c3 88 29       JP L_2988                        ; 2988

L_2904:
2904  3a 20 42       LD A,(0x4220)                    
2907  b7             OR A                             
2908  28 06          JR z,L_2910                      ; 2910
290a  21 52 2f       LD HL,0x2f52                     
290d  c3 88 29       JP L_2988                        ; 2988

L_2910:
2910  3a a1 41       LD A,(FB_TMP)                    ; 41a1
2913  b7             OR A                             
2914  28 06          JR z,L_291c                      ; 291c
2916  21 59 2f       LD HL,0x2f59                     
2919  c3 88 29       JP L_2988                        ; 2988

L_291c:
291c  3a ca 43       LD A,(0x43ca)                    
291f  b7             OR A                             
2920  28 06          JR z,L_2928                      ; 2928
2922  21 83 2f       LD HL,0x2f83                     
2925  c3 88 29       JP L_2988                        ; 2988

L_2928:
2928  3a 64 43       LD A,(0x4364)                    
292b  b7             OR A                             
292c  28 06          JR z,L_2934                      ; 2934
292e  21 89 2f       LD HL,0x2f89                     
2931  c3 88 29       JP L_2988                        ; 2988

L_2934:
2934  3a cf 43       LD A,(0x43cf)                    
2937  b7             OR A                             
2938  ca 41 29       JP z,L_2941                      ; 2941
293b  21 db 2f       LD HL,0x2fdb                     
293e  c3 88 29       JP L_2988                        ; 2988

L_2941:
2941  3a 99 43       LD A,(0x4399)                    
2944  b7             OR A                             
2945  ca 8e 29       JP z,L_298e                      ; 298e
2948  af             XOR A                            
2949  32 99 43       LD (0x4399),A                    
294c  cd 98 06       CALL init_render                 ; 0698
294f  2a 9b 41       LD HL,(FB_COL)                   ; 419b
2952  22 98 41       LD (FB_COLPTR),HL                ; 4198
2955  21 79 29       LD HL,STR_MAGIC_MSG              ; 2979
2958  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
295b  cd f8 29       CALL menu_show_text              ; 29f8
295e  06 02          LD B,2                           
2960  2a 18 42       LD HL,(INS_PTR)                  ; 4218
2963  2b             DEC HL                           
2964  2b             DEC HL                           

L_2965:
2965  7e             LD A,(HL)                        
2966  e6 0f          AND 15                           
2968  f6 30          OR 0x30                          
296a  32 0e 42       LD (CUR_CHAR),A                  ; 420e
296d  e5             PUSH HL                          
296e  c5             PUSH BC                          
296f  cd dd 07       CALL glyph_lookup                ; 07dd
2972  c1             POP BC                           
2973  e1             POP HL                           
2974  23             INC HL                           
2975  10 ee          DJNZ L_2965                      ; 2965
2977  18 15          JR L_298e                        ; 298e

; ---------------- data: STR_MAGIC_MSG (2979-2987) 
STR_MAGIC_MSG:
        db "    MAGIC MSG ",0x00                                               ; 2979

L_2988:
2988  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
298b  cd f8 29       CALL menu_show_text              ; 29f8

L_298e:
298e  3a 41 42       LD A,(0x4241)                    
2991  a7             AND A                            
2992  28 09          JR z,L_299d                      ; 299d
2994  2a 0a 42       LD HL,(0x420a)                   
2997  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
299a  cd f8 29       CALL menu_show_text              ; 29f8

L_299d:
299d  3a 24 42       LD A,(0x4224)                    
29a0  b7             OR A                             
29a1  28 0a          JR z,L_29ad                      ; 29ad
29a3  2a 0a 42       LD HL,(0x420a)                   
29a6  23             INC HL                           
29a7  22 3d 42       LD (MENU_TEXT_PTR),HL            ; 423d
29aa  cd f8 29       CALL menu_show_text              ; 29f8

L_29ad:
29ad  cd 21 2a       CALL sub_2a21                    ; 2a21
29b0  3a 24 42       LD A,(0x4224)                    
29b3  b7             OR A                             
29b4  28 1d          JR z,L_29d3                      ; 29d3
29b6  cd d9 29       CALL sub_29d9                    ; 29d9
29b9  3e 00          LD A,0                           
29bb  32 24 42       LD (0x4224),A                    
29be  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
29c1  7e             LD A,(HL)                        
29c2  fe d0          CP 0xd0                          
29c4  da d0 29       JP c,L_29d0                      ; 29d0
29c7  fe db          CP 0xdb                          
29c9  d2 d0 29       JP nc,L_29d0                     ; 29d0
29cc  e1             POP HL                           
29cd  c3 87 20       JP L_2087                        ; 2087

L_29d0:
29d0  c3 28 27       JP editor_redraw                 ; 2728

L_29d3:
29d3  3e ff          LD A,0xff                        
29d5  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212
29d8  c9             RET                              

sub_29d9:
29d9  3e ff          LD A,0xff                        
29db  32 12 42       LD (EFFECT_ACTIVE),A             ; 4212

L_29de:
29de  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
29e1  fe 03          CP 3                             
29e3  20 f9          JR nz,L_29de                     ; 29de

L_29e5:
29e5  3a 45 42       LD A,(ROW_INDEX)                 ; 4245
29e8  fe 02          CP 2                             
29ea  20 f9          JR nz,L_29e5                     ; 29e5
29ec  3e 50          LD A,0x50                        
29ee  32 44 42       LD (0x4244),A                    

L_29f1:
29f1  3a 44 42       LD A,(0x4244)                    
29f4  a7             AND A                            
29f5  20 fa          JR nz,L_29f1                     ; 29f1
29f7  c9             RET                              

; ----------------------------------------------------------------
; menu_show_text
; Render the NUL-terminated string at MENU_TEXT_PTR in tiny font
menu_show_text:
29f8  2a 3d 42       LD HL,(MENU_TEXT_PTR)            ; 423d
29fb  3a 3a 43       LD A,(TINY_MODE)                 ; 433a
29fe  f5             PUSH AF                          
29ff  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
2a02  f5             PUSH AF                          
2a03  3e ff          LD A,0xff                        
2a05  32 3a 43       LD (TINY_MODE),A                 ; 433a

L_2a08:
2a08  7e             LD A,(HL)                        
2a09  23             INC HL                           
2a0a  b7             OR A                             
2a0b  28 0b          JR z,L_2a18                      ; 2a18
2a0d  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2a10  e5             PUSH HL                          
2a11  cd dd 07       CALL glyph_lookup                ; 07dd
2a14  e1             POP HL                           
2a15  c3 08 2a       JP L_2a08                        ; 2a08

L_2a18:
2a18  f1             POP AF                           
2a19  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2a1c  f1             POP AF                           
2a1d  32 3a 43       LD (TINY_MODE),A                 ; 433a
2a20  c9             RET                              

sub_2a21:
2a21  2a 98 41       LD HL,(FB_COLPTR)                ; 4198
2a24  11 56 00       LD DE,0x56                       
2a27  af             XOR A                            
2a28  ed 52          SBC HL,DE                        
2a2a  22 9b 41       LD (FB_COL),HL                   ; 419b
2a2d  11 40 40       LD DE,FRAMEBUF                   ; 4040
2a30  af             XOR A                            
2a31  ed 52          SBC HL,DE                        
2a33  d2 3d 2a       JP nc,L_2a3d                     ; 2a3d
2a36  11 98 41       LD DE,FB_COLPTR                  ; 4198
2a39  19             ADD HL,DE                        
2a3a  22 9b 41       LD (FB_COL),HL                   ; 419b

L_2a3d:
2a3d  c9             RET                              

; ----------------------------------------------------------------
; pkt_process_end
pkt_process_end:
2a3e  c3 00 00       JP RESET                         ; 0000

sub_2a41:
2a41  d5             PUSH DE                          
2a42  06 02          LD B,2                           
2a44  4c             LD C,H                           

L_2a45:
2a45  79             LD A,C                           
2a46  cb 3f          SRL A                            
2a48  cb 3f          SRL A                            
2a4a  cb 3f          SRL A                            
2a4c  cb 3f          SRL A                            
2a4e  cd 60 2a       CALL nibble_to_hex               ; 2a60
2a51  12             LD (DE),A                        
2a52  13             INC DE                           
2a53  79             LD A,C                           
2a54  e6 0f          AND 15                           
2a56  cd 60 2a       CALL nibble_to_hex               ; 2a60
2a59  12             LD (DE),A                        
2a5a  13             INC DE                           
2a5b  4d             LD C,L                           
2a5c  10 e7          DJNZ L_2a45                      ; 2a45
2a5e  d1             POP DE                           
2a5f  c9             RET                              

; ----------------------------------------------------------------
; nibble_to_hex
; A = ASCII hex digit for low nibble
nibble_to_hex:
2a60  f6 30          OR 0x30                          
2a62  fe 3a          CP 0x3a                          
2a64  d8             RET c                            
2a65  c6 07          ADD A,7                          
2a67  c9             RET                              

; ----------------------------------------------------------------
; pkt_process
; Process a received packet: wait for TX idle, DI, walk PKT_BUF byte by byte. Bytes in IGNORE_TABLE
; are skipped; command bytes dispatch (02 speed,03 clear all,04 sequence,09 channel,0D end,0E delete
; channel text,15 fg idx,16 bg idx,17 time,1E A0-colour,B3 append,B4 query); anything else is inserted
; as message text
pkt_process:
2a68  3a 4d 43       LD A,(TX_STATUS)                 ; 434d
2a6b  e6 03          AND 3                            
2a6d  20 f9          JR nz,pkt_process                ; 2a68
2a6f  f3             DI                               
2a70  31 3f 40       LD SP,0x403f                     
2a73  3a 2d 42       LD A,(CTRL_LATCH_SHADOW)         ; 422d
2a76  f6 0f          OR 15                            
2a78  32 2d 42       LD (CTRL_LATCH_SHADOW),A         ; 422d
2a7b  32 00 80       LD (CTRL_LATCH),A                ; 8000
2a7e  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2a81  7e             LD A,(HL)                        
2a82  fe d0          CP 0xd0                          
2a84  da 90 2a       JP c,L_2a90                      ; 2a90
2a87  fe db          CP 0xdb                          
2a89  d2 90 2a       JP nc,L_2a90                     ; 2a90
2a8c  2b             DEC HL                           
2a8d  22 46 43       LD (STORE_CURSOR),HL             ; 4346

L_2a90:
2a90  e5             PUSH HL                          
2a91  11 e2 43       LD DE,MSG_STORE                  ; 43e2
2a94  b7             OR A                             
2a95  ed 52          SBC HL,DE                        
2a97  e5             PUSH HL                          
2a98  c1             POP BC                           
2a99  e1             POP HL                           
2a9a  2b             DEC HL                           

L_2a9b:
2a9b  7e             LD A,(HL)                        
2a9c  fe d0          CP 0xd0                          
2a9e  da a8 2a       JP c,L_2aa8                      ; 2aa8
2aa1  fe db          CP 0xdb                          
2aa3  d2 a8 2a       JP nc,L_2aa8                     ; 2aa8
2aa6  18 09          JR L_2ab1                        ; 2ab1

L_2aa8:
2aa8  2b             DEC HL                           
2aa9  0b             DEC BC                           
2aaa  79             LD A,C                           
2aab  b0             OR B                             
2aac  20 ed          JR nz,L_2a9b                     ; 2a9b
2aae  c3 3e 2a       JP pkt_process_end               ; 2a3e

L_2ab1:
2ab1  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2ab4  23             INC HL                           
2ab5  22 18 42       LD (INS_PTR),HL                  ; 4218
2ab8  cd 38 1c       CALL store_finalize              ; 1c38
2abb  3a f4 5f       LD A,(PKT_LEN)                   ; 5ff4
2abe  a7             AND A                            
2abf  ca 68 2b       JP z,pkt_process_done            ; 2b68
2ac2  47             LD B,A                           
2ac3  21 f1 5e       LD HL,PKT_BUF                    ; 5ef1

L_2ac6:
2ac6  7e             LD A,(HL)                        
2ac7  e5             PUSH HL                          
2ac8  c5             PUSH BC                          
2ac9  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2acc  cd 4a 2d       CALL is_ignored_byte             ; 2d4a
2acf  a7             AND A                            
2ad0  ca 61 2b       JP z,L_2b61                      ; 2b61
2ad3  fe 02          CP 2                             
2ad5  ca 73 2c       JP z,cmd_02_speed                ; 2c73
2ad8  fe 03          CP 3                             
2ada  ca 8e 2b       JP z,cmd_03_clear_all            ; 2b8e
2add  fe 04          CP 4                             
2adf  ca d7 2c       JP z,cmd_04_sequence             ; 2cd7
2ae2  fe 09          CP 9                             
2ae4  ca a1 2c       JP z,cmd_09_channel              ; 2ca1
2ae7  fe 0d          CP 13                            
2ae9  ca 68 2b       JP z,pkt_process_done            ; 2b68
2aec  fe 0e          CP 14                            
2aee  ca 97 2b       JP z,cmd_0E_delete_text          ; 2b97
2af1  fe 15          CP 0x15                          
2af3  ca 11 2c       JP z,cmd_15_fore_idx             ; 2c11
2af6  fe 16          CP 0x16                          
2af8  ca 22 2c       JP z,cmd_16_back_idx             ; 2c22
2afb  fe 17          CP 0x17                          
2afd  ca 33 2c       JP z,cmd_17_set_time             ; 2c33
2b00  fe 1e          CP 0x1e                          
2b02  ca 04 2c       JP z,cmd_1E_colour_A0            ; 2c04
2b05  fe b3          CP 0xb3                          
2b07  ca 80 2c       JP z,cmd_B3_append               ; 2c80
2b0a  fe b4          CP 0xb4                          
2b0c  ca db 2b       JP z,cmd_B4_query                ; 2bdb

; ----------------------------------------------------------------
; pkt_insert_text
; Insert CUR_CHAR at STORE_CURSOR (shifts the store up; refuses when CHAN_LOCK or memory full)
pkt_insert_text:
2b0f  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
2b12  b7             OR A                             
2b13  c2 61 2b       JP nz,L_2b61                     ; 2b61
2b16  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2b19  7e             LD A,(HL)                        
2b1a  fe 03          CP 3                             
2b1c  20 04          JR nz,L_2b22                     ; 2b22
2b1e  2b             DEC HL                           
2b1f  32 46 43       LD (STORE_CURSOR),A              ; 4346

L_2b22:
2b22  2a 34 42       LD HL,(STORE_END)                ; 4234
2b25  23             INC HL                           
2b26  22 3e 43       LD (STORE_TMP),HL                ; 433e
2b29  ed 5b d8 43    LD DE,(STORE_LIMIT)              ; 43d8
2b2d  b7             OR A                             
2b2e  ed 52          SBC HL,DE                        
2b30  7c             LD A,H                           
2b31  b5             OR L                             
2b32  28 2d          JR z,L_2b61                      ; 2b61
2b34  2a 3e 43       LD HL,(STORE_TMP)                ; 433e
2b37  22 34 42       LD (STORE_END),HL                ; 4234
2b3a  cd 18 26       CALL store_make_room             ; 2618
2b3d  2a d8 43       LD HL,(STORE_LIMIT)              ; 43d8
2b40  22 40 43       LD (MOVE_DST),HL                 ; 4340
2b43  2b             DEC HL                           
2b44  22 42 43       LD (MOVE_SRC),HL                 ; 4342
2b47  ed 5b 46 43    LD DE,(STORE_CURSOR)             ; 4346
2b4b  b7             OR A                             
2b4c  ed 52          SBC HL,DE                        
2b4e  44             LD B,H                           
2b4f  4d             LD C,L                           
2b50  2a 42 43       LD HL,(MOVE_SRC)                 ; 4342
2b53  ed 5b 40 43    LD DE,(MOVE_DST)                 ; 4340
2b57  03             INC BC                           
2b58  ed b8          LDDR                             
2b5a  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346
2b5d  3a 0e 42       LD A,(CUR_CHAR)                  ; 420e
2b60  77             LD (HL),A                        

L_2b61:
2b61  c1             POP BC                           
2b62  e1             POP HL                           
2b63  23             INC HL                           
2b64  05             DEC B                            
2b65  c2 c6 2a       JP nz,L_2ac6                     ; 2ac6

; ----------------------------------------------------------------
; pkt_process_done
; clear PKT_READY/PKT_STATE, re-init and return to main loop
pkt_process_done:
2b68  31 3f 40       LD SP,0x403f                     
2b6b  af             XOR A                            
2b6c  32 f0 5e       LD (PKT_READY),A                 ; 5ef0
2b6f  32 f1 5f       LD (PKT_STATE),A                 ; 5ff1
2b72  32 17 42       LD (MENU_ACTIVE),A               ; 4217
2b75  32 3b 43       LD (0x433b),A                    
2b78  21 6b 42       LD HL,SEQ_LIST                   ; 426b
2b7b  22 d3 42       LD (SEQ_PTR),HL                  ; 42d3
2b7e  cd 84 2b       CALL sub_2b84                    ; 2b84
2b81  c3 0f 00       JP L_000f                        ; 000f

sub_2b84:
2b84  06 55          LD B,0x55                        
2b86  af             XOR A                            

L_2b87:
2b87  d3 40          OUT (PORT_40_OUT),A              
2b89  10 fc          DJNZ L_2b87                      ; 2b87
2b8b  d3 80          OUT (PORT_STROBE),A              
2b8d  c9             RET                              

; ----------------------------------------------------------------
; cmd_03_clear_all
cmd_03_clear_all:
2b8e  cd f7 13       CALL store_clear_all             ; 13f7
2b91  cd 38 1c       CALL store_finalize              ; 1c38
2b94  c3 ba 2c       JP L_2cba                        ; 2cba

; ----------------------------------------------------------------
; cmd_0E_delete_text
; delete existing text of the selected channel (from INS_PTR to its 0x03 terminator)
cmd_0E_delete_text:
2b97  3a 6a 42       LD A,(CHAN_LOCK)                 ; 426a
2b9a  b7             OR A                             
2b9b  c2 61 2b       JP nz,L_2b61                     ; 2b61
2b9e  2a 18 42       LD HL,(INS_PTR)                  ; 4218
2ba1  2b             DEC HL                           
2ba2  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2ba5  23             INC HL                           
2ba6  22 40 43       LD (MOVE_DST),HL                 ; 4340
2ba9  eb             EX DE,HL                         
2baa  2a d8 43       LD HL,(STORE_LIMIT)              ; 43d8
2bad  b7             OR A                             
2bae  ed 52          SBC HL,DE                        
2bb0  e5             PUSH HL                          
2bb1  c1             POP BC                           
2bb2  03             INC BC                           
2bb3  eb             EX DE,HL                         
2bb4  3e 03          LD A,3                           
2bb6  ed b1          CPIR                             
2bb8  78             LD A,B                           
2bb9  b1             OR C                             
2bba  ca 61 2b       JP z,L_2b61                      ; 2b61
2bbd  2b             DEC HL                           
2bbe  22 42 43       LD (MOVE_SRC),HL                 ; 4342
2bc1  ed 5b d8 43    LD DE,(STORE_LIMIT)              ; 43d8
2bc5  eb             EX DE,HL                         
2bc6  b7             OR A                             
2bc7  ed 52          SBC HL,DE                        
2bc9  44             LD B,H                           
2bca  4d             LD C,L                           
2bcb  03             INC BC                           
2bcc  2a 42 43       LD HL,(MOVE_SRC)                 ; 4342
2bcf  ed 5b 40 43    LD DE,(MOVE_DST)                 ; 4340
2bd3  ed b0          LDIR                             
2bd5  cd 38 1c       CALL store_finalize              ; 1c38
2bd8  c3 61 2b       JP L_2b61                        ; 2b61

; ----------------------------------------------------------------
; cmd_B4_query
; B4 n: '0' rom id, '1' memory, '2' nop, '3' dump
cmd_B4_query:
2bdb  cd 99 19       CALL clear_framebuf              ; 1999
2bde  cd 84 2b       CALL sub_2b84                    ; 2b84
2be1  fb             EI                               
2be2  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2be5  fe 30          CP 0x30                          
2be7  cc f0 17       CALL z,query_0_romid             ; 17f0
2bea  fe 31          CP 0x31                          
2bec  cc 32 18       CALL z,query_1_memory            ; 1832
2bef  fe 32          CP 0x32                          
2bf1  cc ef 17       CALL z,sub_17ef                  ; 17ef
2bf4  fe 33          CP 0x33                          
2bf6  cc 70 18       CALL z,query_3_dump              ; 1870

L_2bf9:
2bf9  3a 4d 43       LD A,(TX_STATUS)                 ; 434d
2bfc  e6 03          AND 3                            
2bfe  20 f9          JR nz,L_2bf9                     ; 2bf9
2c00  f3             DI                               
2c01  ca 61 2b       JP z,L_2b61                      ; 2b61

; ----------------------------------------------------------------
; cmd_1E_colour_A0
; 1E n -> insert 0xA0|(n&15)
cmd_1E_colour_A0:
2c04  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2c07  e6 0f          AND 15                           
2c09  f6 a0          OR 0xa0                          
2c0b  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2c0e  c3 0f 2b       JP pkt_insert_text               ; 2b0f

; ----------------------------------------------------------------
; cmd_15_fore_idx
; 15 n -> insert FG_IDX_TABLE[n]
cmd_15_fore_idx:
2c11  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2c14  21 18 27       LD HL,FG_IDX_TABLE               ; 2718
2c17  4f             LD C,A                           
2c18  06 00          LD B,0                           
2c1a  09             ADD HL,BC                        
2c1b  7e             LD A,(HL)                        
2c1c  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2c1f  c3 0f 2b       JP pkt_insert_text               ; 2b0f

; ----------------------------------------------------------------
; cmd_16_back_idx
; 16 n -> insert BG_IDX_TABLE[n]
cmd_16_back_idx:
2c22  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2c25  21 22 27       LD HL,BG_IDX_TABLE               ; 2722
2c28  4f             LD C,A                           
2c29  06 00          LD B,0                           
2c2b  09             ADD HL,BC                        
2c2c  7e             LD A,(HL)                        
2c2d  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2c30  c3 0f 2b       JP pkt_insert_text               ; 2b0f

; ----------------------------------------------------------------
; cmd_17_set_time
; 17 h h m m a: 4 ASCII digits -> CLK_H10..CLK_M1, a=Y/y -> AM else PM. (Bug: stops clock if packet
; ends early)
cmd_17_set_time:
2c33  af             XOR A                            
2c34  32 06 42       LD (CLK_RUN),A                   ; 4206
2c37  21 00 42       LD HL,CLK_H10                    ; 4200
2c3a  06 04          LD B,4                           

L_2c3c:
2c3c  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2c3f  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2c42  e6 0f          AND 15                           
2c44  77             LD (HL),A                        
2c45  23             INC HL                           
2c46  10 f4          DJNZ L_2c3c                      ; 2c3c
2c48  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2c4b  e6 5f          AND 0x5f                         
2c4d  fe 59          CP 0x59                          
2c4f  3e ff          LD A,0xff                        
2c51  20 01          JR nz,L_2c54                     ; 2c54
2c53  af             XOR A                            

L_2c54:
2c54  32 05 42       LD (CLK_PM),A                    ; 4205
2c57  3e ff          LD A,0xff                        
2c59  32 06 42       LD (CLK_RUN),A                   ; 4206
2c5c  c3 61 2b       JP L_2b61                        ; 2b61

; ----------------------------------------------------------------
; pkt_next_byte
; Fetch next payload byte (A); if none left, jump to pkt_process_done
pkt_next_byte:
2c5f  dd e1          POP IX                           
2c61  d1             POP DE                           
2c62  fd e1          POP IY                           
2c64  fd 23          INC IY                           
2c66  15             DEC D                            
2c67  ca 68 2b       JP z,pkt_process_done            ; 2b68
2c6a  fd 7e 00       LD A,(IY)                        
2c6d  fd e5          PUSH IY                          
2c6f  d5             PUSH DE                          
2c70  dd e5          PUSH IX                          
2c72  c9             RET                              

; ----------------------------------------------------------------
; cmd_02_speed
; 02 n -> insert 0xF0|(n&7)
cmd_02_speed:
2c73  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2c76  e6 07          AND 7                            
2c78  f6 f0          OR 0xf0                          
2c7a  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2c7d  c3 0f 2b       JP pkt_insert_text               ; 2b0f

; ----------------------------------------------------------------
; cmd_B3_append
; B3: move STORE_CURSOR to end of current channel
cmd_B3_append:
2c80  2a 46 43       LD HL,(STORE_CURSOR)             ; 4346

L_2c83:
2c83  7e             LD A,(HL)                        
2c84  fe 03          CP 3                             
2c86  28 03          JR z,L_2c8b                      ; 2c8b
2c88  23             INC HL                           
2c89  18 f8          JR L_2c83                        ; 2c83

L_2c8b:
2c8b  2b             DEC HL                           
2c8c  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2c8f  7e             LD A,(HL)                        
2c90  fe d0          CP 0xd0                          
2c92  da 61 2b       JP c,L_2b61                      ; 2b61
2c95  fe db          CP 0xdb                          
2c97  d2 61 2b       JP nc,L_2b61                     ; 2b61
2c9a  2b             DEC HL                           
2c9b  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2c9e  c3 61 2b       JP L_2b61                        ; 2b61

; ----------------------------------------------------------------
; cmd_09_channel
; 09 d d: select channel (2 ASCII digits, 0-99) ; channel 100 sets CHAN_LOCK
cmd_09_channel:
2ca1  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2ca4  e6 0f          AND 15                           
2ca6  32 9c 43       LD (CHAN_D10),A                  ; 439c
2ca9  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2cac  e6 0f          AND 15                           
2cae  32 9d 43       LD (CHAN_D1),A                   ; 439d
2cb1  06 02          LD B,2                           
2cb3  21 9c 43       LD HL,CHAN_D10                   ; 439c
2cb6  cd fc 1f       CALL ascii_dec_to_bin            ; 1ffc
2cb9  5f             LD E,A                           

L_2cba:
2cba  d5             PUSH DE                          
2cbb  cd 26 04       CALL chan_select                 ; 0426
2cbe  d1             POP DE                           
2cbf  22 18 42       LD (INS_PTR),HL                  ; 4218
2cc2  2b             DEC HL                           
2cc3  2b             DEC HL                           
2cc4  22 46 43       LD (STORE_CURSOR),HL             ; 4346
2cc7  d5             PUSH DE                          
2cc8  cd 1a 04       CALL chan_find                   ; 041a
2ccb  d1             POP DE                           
2ccc  7b             LD A,E                           
2ccd  fe 64          CP 0x64                          
2ccf  20 03          JR nz,L_2cd4                     ; 2cd4
2cd1  32 6a 42       LD (CHAN_LOCK),A                 ; 426a

L_2cd4:
2cd4  c3 61 2b       JP L_2b61                        ; 2b61

; ----------------------------------------------------------------
; cmd_04_sequence
; 04 dd dd ... [D|d]: rebuild SEQ_LIST from 2-digit channel numbers
cmd_04_sequence:
2cd7  21 6b 42       LD HL,SEQ_LIST                   ; 426b
2cda  3e 00          LD A,0                           
2cdc  06 64          LD B,0x64                        

L_2cde:
2cde  77             LD (HL),A                        
2cdf  23             INC HL                           
2ce0  3c             INC A                            
2ce1  10 fb          DJNZ L_2cde                      ; 2cde
2ce3  36 ff          LD (HL),0xff                     
2ce5  23             INC HL                           
2ce6  36 ff          LD (HL),0xff                     
2ce8  23             INC HL                           
2ce9  36 ff          LD (HL),0xff                     
2ceb  23             INC HL                           
2cec  36 ff          LD (HL),0xff                     
2cee  21 6b 42       LD HL,SEQ_LIST                   ; 426b
2cf1  22 d3 42       LD (SEQ_PTR),HL                  ; 42d3
2cf4  06 67          LD B,0x67                        

L_2cf6:
2cf6  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2cf9  fe 44          CP 0x44                          
2cfb  28 41          JR z,L_2d3e                      ; 2d3e
2cfd  fe 64          CP 0x64                          
2cff  28 3d          JR z,L_2d3e                      ; 2d3e
2d01  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2d04  fe 3a          CP 0x3a                          
2d06  d2 61 2b       JP nc,L_2b61                     ; 2b61
2d09  fe 30          CP 0x30                          
2d0b  da 61 2b       JP c,L_2b61                      ; 2b61
2d0e  e6 0f          AND 15                           
2d10  32 9c 43       LD (CHAN_D10),A                  ; 439c
2d13  cd 5f 2c       CALL pkt_next_byte               ; 2c5f
2d16  fe 44          CP 0x44                          
2d18  28 24          JR z,L_2d3e                      ; 2d3e
2d1a  fe 64          CP 0x64                          
2d1c  28 20          JR z,L_2d3e                      ; 2d3e
2d1e  32 0e 42       LD (CUR_CHAR),A                  ; 420e
2d21  fe 3a          CP 0x3a                          
2d23  d2 61 2b       JP nc,L_2b61                     ; 2b61
2d26  fe 30          CP 0x30                          
2d28  da 61 2b       JP c,L_2b61                      ; 2b61
2d2b  e6 0f          AND 15                           
2d2d  32 9d 43       LD (CHAN_D1),A                   ; 439d
2d30  c5             PUSH BC                          
2d31  e5             PUSH HL                          
2d32  06 02          LD B,2                           
2d34  21 9c 43       LD HL,CHAN_D10                   ; 439c
2d37  cd fc 1f       CALL ascii_dec_to_bin            ; 1ffc
2d3a  e1             POP HL                           
2d3b  c1             POP BC                           
2d3c  18 02          JR L_2d40                        ; 2d40

L_2d3e:
2d3e  3e 64          LD A,0x64                        

L_2d40:
2d40  77             LD (HL),A                        
2d41  23             INC HL                           
2d42  3e ff          LD A,0xff                        
2d44  77             LD (HL),A                        
2d45  10 af          DJNZ L_2cf6                      ; 2cf6
2d47  c3 61 2b       JP L_2b61                        ; 2b61

; ----------------------------------------------------------------
; is_ignored_byte
; Z (A=0) if A is in IGNORE_TABLE: 00 01 05 08 0A 0B 0C 1C 1D 7F
is_ignored_byte:
2d4a  21 57 2d       LD HL,IGNORE_TABLE               ; 2d57
2d4d  01 0a 00       LD BC,10                         
2d50  ed b1          CPIR                             
2d52  2b             DEC HL                           
2d53  be             CP (HL)                          
2d54  c0             RET nz                           
2d55  af             XOR A                            
2d56  c9             RET                              

; ---------------- data: IGNORE_TABLE (2d57-2d60) payload bytes silently ignored by the parser
IGNORE_TABLE:
        db 0x00,0x01,0x05,0x08,0x0a,0x0b,0x0c,0x1c,0x1d,0x7f                   ; 2d57

; ---------------- data: GLYPH_PTR_TABLE (2d61-2ff2) 16-bit pointers/data for big glyphs & graphics (0x2E00-0x2FF0)
GLYPH_PTR_TABLE:
        db 0x00,0x00,0x00,0xdb,0x2f,0x00,0x00,0xf3,0x2e,0x3b,0x30,0x00,0x00,0xc8,0x2f,0x52 ; 2d61
        db 0x2e,0x00,0x00,0x2f,0x30,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x59 ; 2d71
        db 0x2e,0x95,0x2f,0x60,0x2f,0x67,0x2f,0xe2,0x2e,0xeb,0x2e,0x52,0x2f,0x59,0x2f,0x00 ; 2d81
        db 0x00,0xfa,0x2e,0xb9,0x2f,0xcf,0x2f,0xd4,0x2f,0x00,0x00,0x9b,0x2f,0xe3,0x2f,0xeb ; 2d91
        db 0x2f,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x31,0x00,0x00 ; 2da1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x32,0x00,0x00 ; 2db1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x33,0x00,0x00 ; 2dc1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x34,0x00,0x00 ; 2dd1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x35,0x00,0x00 ; 2de1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x36,0x00,0x00 ; 2df1
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x37,0x00,0x00 ; 2e01
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x38,0x00,0x00 ; 2e11
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x20,0x39,0x00,0x00 ; 2e21
        db 0x00,0x54,0x4f,0x50,0x20,0x4f,0x46,0x20,0x4d,0x53,0x47,0x20,0x31,0x30,0x00,0x00 ; 2e31
        db 0x00,0x54,0x4f,0x50,0x20,0x44,0x45,0x4d,0x4f,0x20,0x4d,0x53,0x47,0x20,0x00,0x00 ; 2e41
        db 0x00,0x15,0x42,0x45,0x45,0x50,0x16,0x00,0x15,0x52,0x49,0x47,0x48,0x54,0x16,0x00 ; 2e51
        db 0x00,0x88,0x30,0x90,0x30,0x98,0x30,0xa0,0x30,0xa8,0x30,0xb0,0x30,0xb8,0x30,0xc0 ; 2e61
        db 0x30,0xc7,0x30,0xcf,0x30,0xd7,0x30,0xdf,0x30,0xe7,0x30,0xed,0x30,0xf6,0x30,0xfd ; 2e71
        db 0x30,0xa2,0x2e,0xaa,0x2e,0xba,0x2e,0xb2,0x2e,0xa2,0x2e,0xaa,0x2e,0xba,0x2e,0xb2 ; 2e81
        db 0x2e,0xa2,0x2e,0xaa,0x2e,0xba,0x2e,0xb2,0x2e,0xa2,0x2e,0xaa,0x2e,0xba,0x2e,0xb2 ; 2e91
        db 0x2e,0x15,0x42,0x2d,0x42,0x4c,0x4b,0x16,0x00,0x15,0x42,0x2d,0x52,0x45,0x44,0x16 ; 2ea1
        db 0x00,0x15,0x42,0x2d,0x59,0x45,0x4c,0x16,0x00,0x15,0x42,0x2d,0x47,0x52,0x45,0x16 ; 2eb1
        db 0x00,0x8f,0x2f,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 2ec1
        db 0x00,0x6e,0x2f,0x75,0x2f,0x7c,0x2f,0xc1,0x2f,0xa3,0x2f,0xad,0x2f,0x2e,0x31,0x00 ; 2ed1
        db 0x00,0x15,0x49,0x54,0x41,0x4c,0x49,0x43,0x16,0x00,0x15,0x46,0x4c,0x41,0x53,0x48 ; 2ee1
        db 0x16,0x00,0x15,0x45,0x4e,0x44,0x16,0x00,0x00,0x15,0x4c,0x45,0x46,0x54,0x16,0x00 ; 2ef1
        db 0x00,0xa2,0x2d,0xb2,0x2d,0xc2,0x2d,0xd2,0x2d,0xe2,0x2d,0xf2,0x2d,0x02,0x2e,0x12 ; 2f01
        db 0x2e,0x22,0x2e,0x32,0x2e,0x42,0x2e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 2f11
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 2f21
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 2f31
        db 0x00,0x06,0x31,0x0b,0x31,0x10,0x31,0x15,0x31,0x1a,0x31,0x1f,0x31,0x24,0x31,0x29 ; 2f41
        db 0x31,0x15,0x43,0x4f,0x4c,0x4f,0x52,0x00,0x15,0x42,0x47,0x52,0x4e,0x44,0x00,0x15 ; 2f51
        db 0x4e,0x4f,0x52,0x4d,0x16,0x00,0x15,0x42,0x4f,0x4c,0x44,0x16,0x00,0x15,0x44,0x52 ; 2f61
        db 0x41,0x57,0x16,0x00,0x15,0x54,0x48,0x49,0x4e,0x16,0x00,0x15,0x57,0x41,0x49,0x54 ; 2f71
        db 0x16,0x00,0x15,0x46,0x55,0x4e,0x43,0x00,0x15,0x45,0x55,0x52,0x4f,0x00,0x15,0x52 ; 2f81
        db 0x45,0x4d,0x16,0x00,0x15,0x42,0x49,0x47,0x16,0x00,0x15,0x53,0x48,0x49,0x46,0x54 ; 2f91
        db 0x16,0x00,0x15,0x52,0x41,0x49,0x4e,0x42,0x4f,0x57,0x16,0x00,0x15,0x4d,0x41,0x47 ; 2fa1
        db 0x49,0x43,0x20,0x4f,0x46,0x46,0x16,0x00,0x15,0x50,0x41,0x55,0x53,0x45,0x16,0x00 ; 2fb1
        db 0x15,0x48,0x4f,0x4c,0x44,0x16,0x00,0x15,0x48,0x41,0x4c,0x54,0x16,0x00,0x15,0x55 ; 2fc1
        db 0x50,0x16,0x00,0x15,0x44,0x4f,0x57,0x4e,0x16,0x00,0x15,0x53,0x50,0x45,0x45,0x44 ; 2fd1
        db 0x20,0x00,0x15,0x47,0x52,0x41,0x50,0x48,0x20,0x00,0x15,0x4d,0x41,0x47,0x49,0x43 ; 2fe1
        db 0x16,0x00                                                           ; 2ff1

; ---------------- data: MENU_STRINGS (2ff3-3134) NUL-terminated menu prompts and the 16 foreground colour names in code order 0x80..0x8F (BLACK,D-GRE,M-GRE,GREEN,D-RED,D-YEL,D-LIM,LIME,M-RED,D-ORA,M-YEL,LEMON,RED,ORANGE,GOLD,YELLOW), speeds S0..S7, TINY
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

; ---------------- data: FONT (3135-382c) 8 bytes per glyph: 7 column bytes + width byte (see glyph_lookup)
FONT:
        db 0x1c,0x14,0x14,0x77,0x22,0x14,0x08,0x07           ; glyph   0  width 7
        db 0x08,0x14,0x22,0x77,0x14,0x14,0x1c,0x07           ; glyph   1  width 7
        db 0x30,0x70,0x38,0x34,0x3c,0x74,0x38,0x07           ; glyph   2  width 7
        db 0x20,0x70,0x70,0x3f,0x02,0x04,0x00,0x06           ; glyph   3  width 6
        db 0x08,0x1c,0x22,0x2a,0x22,0x1c,0x08,0x07           ; glyph   4  width 7
        db 0x07,0x49,0x79,0x49,0x07,0x00,0x00,0x05           ; glyph   5  width 5
        db 0x10,0x18,0x1c,0x18,0x10,0x00,0x00,0x05           ; glyph   6  width 5
        db 0x08,0x1c,0x3e,0x7f,0x3e,0x1c,0x08,0x07           ; glyph   7  width 7
        db 0x7f,0x7f,0x7f,0x7f,0x7f,0x00,0x00,0x06           ; glyph   8  width 6
        db 0x1c,0x3e,0x7f,0x7f,0x3e,0x1c,0x00,0x07           ; glyph   9  width 7
        db 0x04,0x7c,0x46,0x77,0x46,0x7c,0x04,0x07           ; glyph  10  width 7
        db 0x10,0x30,0x54,0x56,0x5f,0x50,0x30,0x07           ; glyph  11  width 7
        db 0x18,0x1e,0x7f,0x1e,0x18,0x00,0x00,0x05           ; glyph  12  width 5
        db 0x2c,0x6e,0x6d,0x6f,0x6f,0x3e,0x1c,0x07           ; glyph  13  width 7
        db 0x1c,0x22,0x41,0x4f,0x51,0x22,0x1c,0x07           ; glyph  14  width 7
        db 0x20,0x3c,0x22,0x63,0x22,0x3c,0x20,0x07           ; glyph  15  width 7
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  16  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  17  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  18  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  19  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  20  width 1
        db 0x00,0x00,0x08,0x1c,0x00,0x00,0x00,0x04           ; glyph  21  width 4
        db 0x1c,0x08,0x00,0x00,0x00,0x00,0x00,0x04           ; glyph  22  width 4
        db 0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x00,0x06           ; glyph  23  width 6
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  24  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  25  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  26  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  27  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  28  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  29  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  30  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph  31  width 1
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x05           ; glyph  32  width 5
        db 0x5f,0x00,0x00,0x00,0x00,0x00,0x00,0x04           ; glyph  33  width 4
        db 0x07,0x00,0x07,0x00,0x00,0x00,0x00,0x03           ; glyph  34  width 3
        db 0x14,0x7f,0x14,0x7f,0x14,0x00,0x00,0x05           ; glyph  35  width 5
        db 0x26,0x49,0x7f,0x49,0x32,0x00,0x00,0x05           ; glyph  36  width 5
        db 0x42,0x25,0x12,0x08,0x24,0x52,0x21,0x07           ; glyph  37  width 7
        db 0x36,0x49,0x49,0x56,0x20,0x50,0x00,0x06           ; glyph  38  width 6
        db 0x07,0x00,0x00,0x00,0x00,0x00,0x00,0x01           ; glyph  39  width 1
        db 0x1c,0x22,0x41,0x00,0x00,0x00,0x00,0x03           ; glyph  40  width 3
        db 0x41,0x22,0x1c,0x00,0x00,0x00,0x00,0x03           ; glyph  41  width 3
        db 0x2a,0x1c,0x7f,0x1c,0x2a,0x00,0x00,0x05           ; glyph  42  width 5
        db 0x08,0x08,0x3e,0x08,0x08,0x00,0x00,0x05           ; glyph  43  width 5
        db 0x40,0x30,0x30,0x00,0x00,0x00,0x00,0x03           ; glyph  44  width 3
        db 0x08,0x08,0x08,0x08,0x00,0x00,0x00,0x04           ; glyph  45  width 4
        db 0x60,0x60,0x00,0x00,0x00,0x00,0x00,0x04           ; glyph  46  width 4
        db 0x40,0x20,0x10,0x08,0x04,0x02,0x01,0x07           ; glyph  47  width 7
        db 0x3e,0x41,0x41,0x41,0x3e,0x00,0x00,0x05           ; glyph  48  width 5
        db 0x41,0x7f,0x40,0x00,0x00,0x00,0x00,0x03           ; glyph  49  width 3
        db 0x42,0x61,0x51,0x49,0x46,0x00,0x00,0x05           ; glyph  50  width 5
        db 0x22,0x41,0x49,0x49,0x36,0x00,0x00,0x05           ; glyph  51  width 5
        db 0x08,0x0c,0x0a,0x7f,0x08,0x00,0x00,0x05           ; glyph  52  width 5
        db 0x2f,0x49,0x49,0x49,0x31,0x00,0x00,0x05           ; glyph  53  width 5
        db 0x3c,0x4a,0x49,0x49,0x30,0x00,0x00,0x05           ; glyph  54  width 5
        db 0x01,0x71,0x09,0x05,0x03,0x00,0x00,0x05           ; glyph  55  width 5
        db 0x36,0x49,0x49,0x49,0x36,0x00,0x00,0x05           ; glyph  56  width 5
        db 0x06,0x49,0x49,0x49,0x3e,0x00,0x00,0x05           ; glyph  57  width 5
        db 0x6c,0x6c,0x00,0x00,0x00,0x00,0x00,0x02           ; glyph  58  width 2
        db 0x40,0x6c,0x6c,0x00,0x00,0x00,0x00,0x03           ; glyph  59  width 3
        db 0x08,0x14,0x22,0x41,0x00,0x00,0x00,0x04           ; glyph  60  width 4
        db 0x14,0x14,0x14,0x14,0x00,0x00,0x00,0x04           ; glyph  61  width 4
        db 0x41,0x22,0x14,0x08,0x00,0x00,0x00,0x04           ; glyph  62  width 4
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph  63  width 5
        db 0x3e,0x41,0x4f,0x49,0x2e,0x00,0x00,0x05           ; glyph  64  width 5
        db 0x7e,0x09,0x09,0x09,0x7e,0x00,0x00,0x05           ; glyph  65  width 5
        db 0x7f,0x49,0x49,0x49,0x36,0x00,0x00,0x05           ; glyph  66  width 5
        db 0x3e,0x41,0x41,0x41,0x22,0x00,0x00,0x05           ; glyph  67  width 5
        db 0x7f,0x41,0x41,0x41,0x3e,0x00,0x00,0x05           ; glyph  68  width 5
        db 0x7f,0x49,0x49,0x49,0x41,0x00,0x00,0x05           ; glyph  69  width 5
        db 0x7f,0x09,0x09,0x09,0x01,0x00,0x00,0x05           ; glyph  70  width 5
        db 0x3e,0x41,0x41,0x51,0x32,0x00,0x00,0x05           ; glyph  71  width 5
        db 0x7f,0x08,0x08,0x08,0x7f,0x00,0x00,0x05           ; glyph  72  width 5
        db 0x41,0x7f,0x41,0x00,0x00,0x00,0x00,0x03           ; glyph  73  width 3
        db 0x20,0x40,0x41,0x3f,0x01,0x00,0x00,0x05           ; glyph  74  width 5
        db 0x7f,0x08,0x14,0x22,0x41,0x00,0x00,0x05           ; glyph  75  width 5
        db 0x7f,0x40,0x40,0x40,0x40,0x00,0x00,0x05           ; glyph  76  width 5
        db 0x7f,0x02,0x0c,0x02,0x7f,0x00,0x00,0x05           ; glyph  77  width 5
        db 0x7f,0x02,0x04,0x08,0x7f,0x00,0x00,0x05           ; glyph  78  width 5
        db 0x3e,0x41,0x41,0x41,0x3e,0x00,0x00,0x05           ; glyph  79  width 5
        db 0x7f,0x09,0x09,0x09,0x06,0x00,0x00,0x05           ; glyph  80  width 5
        db 0x3e,0x41,0x51,0x61,0x7e,0x00,0x00,0x05           ; glyph  81  width 5
        db 0x7f,0x09,0x19,0x29,0x46,0x00,0x00,0x05           ; glyph  82  width 5
        db 0x26,0x49,0x49,0x49,0x32,0x00,0x00,0x05           ; glyph  83  width 5
        db 0x01,0x01,0x7f,0x01,0x01,0x00,0x00,0x05           ; glyph  84  width 5
        db 0x3f,0x40,0x40,0x40,0x3f,0x00,0x00,0x05           ; glyph  85  width 5
        db 0x1f,0x20,0x40,0x20,0x1f,0x00,0x00,0x05           ; glyph  86  width 5
        db 0x3f,0x40,0x38,0x40,0x3f,0x00,0x00,0x05           ; glyph  87  width 5
        db 0x63,0x14,0x08,0x14,0x63,0x00,0x00,0x05           ; glyph  88  width 5
        db 0x07,0x08,0x70,0x08,0x07,0x00,0x00,0x05           ; glyph  89  width 5
        db 0x61,0x51,0x49,0x45,0x43,0x00,0x00,0x05           ; glyph  90  width 5
        db 0x7f,0x41,0x41,0x00,0x00,0x00,0x00,0x03           ; glyph  91  width 3
        db 0x02,0x04,0x08,0x10,0x20,0x00,0x00,0x05           ; glyph  92  width 5
        db 0x41,0x41,0x7f,0x00,0x00,0x00,0x00,0x03           ; glyph  93  width 3
        db 0x04,0x02,0x7f,0x02,0x04,0x00,0x00,0x05           ; glyph  94  width 5
        db 0x1c,0x22,0x41,0x4f,0x51,0x22,0x1c,0x07           ; glyph  95  width 7
        db 0x60,0x5e,0x55,0x55,0x41,0x02,0x00,0x06           ; glyph  96  width 6
        db 0x20,0x54,0x54,0x54,0x78,0x00,0x00,0x05           ; glyph  97  width 5
        db 0x7f,0x44,0x44,0x44,0x38,0x00,0x00,0x05           ; glyph  98  width 5
        db 0x38,0x44,0x44,0x44,0x44,0x00,0x00,0x05           ; glyph  99  width 5
        db 0x38,0x44,0x44,0x44,0x7f,0x00,0x00,0x05           ; glyph 100  width 5
        db 0x38,0x54,0x54,0x54,0x58,0x00,0x00,0x05           ; glyph 101  width 5
        db 0x08,0x7e,0x09,0x02,0x00,0x00,0x00,0x04           ; glyph 102  width 4
        db 0x38,0x44,0x44,0x54,0x74,0x00,0x00,0x05           ; glyph 103  width 5
        db 0x7f,0x04,0x04,0x04,0x78,0x00,0x00,0x05           ; glyph 104  width 5
        db 0x7a,0x00,0x00,0x00,0x00,0x00,0x00,0x01           ; glyph 105  width 1
        db 0x20,0x40,0x44,0x3c,0x04,0x00,0x00,0x05           ; glyph 106  width 5
        db 0x7f,0x10,0x28,0x44,0x00,0x00,0x00,0x04           ; glyph 107  width 4
        db 0x7f,0x00,0x00,0x00,0x00,0x00,0x00,0x01           ; glyph 108  width 1
        db 0x78,0x04,0x18,0x04,0x78,0x00,0x00,0x05           ; glyph 109  width 5
        db 0x7c,0x08,0x04,0x04,0x78,0x00,0x00,0x05           ; glyph 110  width 5
        db 0x38,0x44,0x44,0x44,0x38,0x00,0x00,0x05           ; glyph 111  width 5
        db 0x7c,0x14,0x14,0x14,0x08,0x00,0x00,0x05           ; glyph 112  width 5
        db 0x38,0x44,0x54,0x64,0x78,0x00,0x00,0x05           ; glyph 113  width 5
        db 0x7c,0x08,0x04,0x04,0x08,0x00,0x00,0x05           ; glyph 114  width 5
        db 0x48,0x54,0x54,0x54,0x24,0x00,0x00,0x05           ; glyph 115  width 5
        db 0x04,0x3f,0x44,0x00,0x00,0x00,0x00,0x03           ; glyph 116  width 3
        db 0x3c,0x40,0x40,0x40,0x3c,0x00,0x00,0x05           ; glyph 117  width 5
        db 0x0c,0x30,0x40,0x30,0x0c,0x00,0x00,0x05           ; glyph 118  width 5
        db 0x3c,0x40,0x30,0x40,0x3c,0x00,0x00,0x05           ; glyph 119  width 5
        db 0x44,0x28,0x10,0x28,0x44,0x00,0x00,0x05           ; glyph 120  width 5
        db 0x04,0x08,0x70,0x08,0x04,0x00,0x00,0x05           ; glyph 121  width 5
        db 0x44,0x64,0x54,0x4c,0x44,0x00,0x00,0x05           ; glyph 122  width 5
        db 0x08,0x36,0x41,0x00,0x00,0x00,0x00,0x03           ; glyph 123  width 3
        db 0x40,0x40,0x40,0x40,0x40,0x00,0x00,0x05           ; glyph 124  width 5
        db 0x41,0x36,0x08,0x00,0x00,0x00,0x00,0x03           ; glyph 125  width 3
        db 0x08,0x04,0x08,0x04,0x00,0x00,0x00,0x04           ; glyph 126  width 4
        db 0x08,0x08,0x08,0x08,0x2a,0x1c,0x08,0x07           ; glyph 127  width 7
        db 0x78,0x15,0x16,0x14,0x78,0x00,0x00,0x05           ; glyph 128  width 5
        db 0x20,0x55,0x56,0x54,0x78,0x00,0x00,0x05           ; glyph 129  width 5
        db 0x1e,0x21,0x61,0x21,0x21,0x00,0x00,0x05           ; glyph 130  width 5
        db 0x18,0x24,0x64,0x24,0x24,0x00,0x00,0x05           ; glyph 131  width 5
        db 0x7c,0x56,0x55,0x56,0x44,0x00,0x00,0x05           ; glyph 132  width 5
        db 0x7c,0x54,0x56,0x55,0x44,0x00,0x00,0x05           ; glyph 133  width 5
        db 0x38,0x54,0x56,0x55,0x58,0x00,0x00,0x05           ; glyph 134  width 5
        db 0x7c,0x55,0x56,0x54,0x44,0x00,0x00,0x05           ; glyph 135  width 5
        db 0x38,0x55,0x56,0x54,0x58,0x00,0x00,0x05           ; glyph 136  width 5
        db 0x38,0x56,0x55,0x56,0x58,0x00,0x00,0x05           ; glyph 137  width 5
        db 0x78,0x0c,0x0a,0x7f,0x49,0x49,0x41,0x07           ; glyph 138  width 7
        db 0x20,0x54,0x54,0x78,0x54,0x54,0x08,0x07           ; glyph 139  width 7
        db 0x7c,0x09,0x11,0x21,0x7c,0x00,0x00,0x05           ; glyph 140  width 5
        db 0x7c,0x09,0x05,0x05,0x78,0x00,0x00,0x05           ; glyph 141  width 5
        db 0x3c,0x41,0x42,0x40,0x3c,0x00,0x00,0x05           ; glyph 142  width 5
        db 0x78,0x15,0x14,0x15,0x78,0x00,0x00,0x05           ; glyph 143  width 5
        db 0x20,0x55,0x54,0x55,0x78,0x00,0x00,0x05           ; glyph 144  width 5
        db 0x38,0x45,0x44,0x45,0x38,0x00,0x00,0x05           ; glyph 145  width 5
        db 0x30,0x4a,0x48,0x4a,0x30,0x00,0x00,0x05           ; glyph 146  width 5
        db 0x3c,0x41,0x40,0x41,0x3c,0x00,0x00,0x05           ; glyph 147  width 5
        db 0x78,0x14,0x15,0x14,0x78,0x00,0x00,0x05           ; glyph 148  width 5
        db 0x20,0x54,0x55,0x54,0x78,0x00,0x00,0x05           ; glyph 149  width 5
        db 0x40,0x3e,0x51,0x49,0x45,0x3e,0x01,0x07           ; glyph 150  width 7
        db 0x40,0x3c,0x52,0x4a,0x3c,0x02,0x00,0x06           ; glyph 151  width 6
        db 0x38,0x42,0x40,0x42,0x38,0x00,0x00,0x05           ; glyph 152  width 5
        db 0x1c,0x22,0x7f,0x22,0x1c,0x00,0x00,0x05           ; glyph 153  width 5
        db 0x07,0x08,0x7f,0x08,0x07,0x00,0x00,0x05           ; glyph 154  width 5
        db 0x5c,0x62,0x01,0x01,0x62,0x5c,0x00,0x06           ; glyph 155  width 6
        db 0x78,0x14,0x16,0x15,0x78,0x00,0x00,0x05           ; glyph 156  width 5
        db 0x7f,0x25,0x25,0x25,0x1a,0x00,0x00,0x05           ; glyph 157  width 5
        db 0x41,0x49,0x49,0x49,0x41,0x00,0x00,0x05           ; glyph 158  width 5
        db 0x01,0x7f,0x01,0x7f,0x01,0x00,0x00,0x05           ; glyph 159  width 5
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph 160  width 5
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph 161  width 5
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph 162  width 5
        db 0x02,0x01,0x51,0x09,0x06,0x00,0x00,0x05           ; glyph 163  width 5
        db 0x63,0x55,0x49,0x41,0x41,0x00,0x00,0x05           ; glyph 164  width 5
        db 0x20,0x54,0x56,0x55,0x78,0x00,0x00,0x05           ; glyph 165  width 5
        db 0x30,0x48,0x45,0x40,0x20,0x00,0x00,0x05           ; glyph 166  width 5
        db 0x70,0x4c,0x43,0x4c,0x70,0x00,0x00,0x05           ; glyph 167  width 5
        db 0x3e,0x49,0x49,0x49,0x3e,0x00,0x00,0x05           ; glyph 168  width 5
        db 0x70,0x0c,0x03,0x0c,0x70,0x00,0x00,0x05           ; glyph 169  width 5
        db 0x3e,0x40,0x42,0x41,0x3e,0x00,0x00,0x05           ; glyph 170  width 5
        db 0x7f,0x01,0x01,0x01,0x01,0x00,0x00,0x05           ; glyph 171  width 5
        db 0x3c,0x40,0x42,0x41,0x3c,0x00,0x00,0x05           ; glyph 172  width 5
        db 0x3e,0x41,0x42,0x40,0x3e,0x00,0x00,0x05           ; glyph 173  width 5
        db 0x00,0x7d,0x00,0x00,0x00,0x00,0x00,0x02           ; glyph 174  width 2
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 175  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 176  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 177  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 178  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 179  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 180  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 181  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 182  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 183  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 184  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 185  width 1
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01           ; glyph 186  width 1
        db 0x38,0x44,0x46,0x45,0x38,0x00,0x00,0x05           ; glyph 187  width 5
        db 0x76,0x01,0x00,0x00,0x00,0x00,0x00,0x02           ; glyph 188  width 2
        db 0x44,0x7e,0x45,0x00,0x00,0x00,0x00,0x03           ; glyph 189  width 3
        db 0x30,0x48,0x4c,0x4a,0x30,0x00,0x00,0x05           ; glyph 190  width 5
        db 0x07,0x07,0x07,0x02,0x07,0x07,0x02,0x02           ; glyph 191  width 2
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x02           ; glyph 192  width 2
        db 0x02,0x02,0x02,0x02,0x02,0x00,0x00,0x00           ; glyph 193  width 0
        db 0x02,0x02,0x02,0x02,0x07,0x07,0x07,0x02           ; glyph 194  width 2
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 195  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 196  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 197  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 198  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 199  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 200  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 201  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 202  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 203  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 204  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 205  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 206  width 0
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02           ; glyph 207  width 2
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02           ; glyph 208  width 2
        db 0x02,0x02,0x02,0x02,0x00,0x00,0x00,0x00           ; glyph 209  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07           ; glyph 210  width 7
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 211  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 212  width 0
        db 0x02,0x07,0x07,0x07,0x07,0x07,0x07,0x07           ; glyph 213  width 7
        db 0x00,0x02,0x02,0x02,0x02,0x02,0x02,0x07           ; glyph 214  width 7
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 215  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 216  width 0
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02           ; glyph 217  width 2
        db 0x02,0x02,0x02,0x07,0x00,0x00,0x00,0x00           ; glyph 218  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 219  width 0
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00           ; glyph 220  width 0
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02           ; glyph 221  width 2
        db 0x07,0x07,0x07,0x07,0x07,0x07,0x07,0x07           ; glyph 222  width 7

; ---------------- data: CHARSET_LOWER (382d-386c) glyph-order character lists used by char_to_glyph (lower-case font)
CHARSET_LOWER:
        db "kf",0x12,"pa",0x0e,0x11,0x1e," ",0x7f,")%zwytni",0x1f,"hd",0x09,0x1a,0x19,"0",0x1d,"2586k",0x00 ; 382d
        db "lgvmq",0x04,0x10,0x14,".",0x1c,"(*+9xsojbce",0x0d,0x07,0x15,0x08,0x0a,"1473ur" ; 384d

; ---------------- data: CHARSET_UPPER (386d-38ac) 
CHARSET_UPPER:
        db "KF",0x12,"PA",0x0e,0x11,0x1e," ",0x7f,")%ZWYTNI",0x1f,"HD",0x09,0x1a,0x19,"0",0x1d,"2586K",0x00 ; 386d
        db "LGVMQ",0x04,0x10,0x14,".",0x1c,"(*+9XSOJBCE",0x0d,0x07,0x15,0x08,0x0a,"1473UR" ; 388d

; ---------------- data: CHARSET_UPPER2 (38ad-38ec) 
CHARSET_UPPER2:
        db "KF",0x18,"PA",0x03,0x17,"_ ",0x7f,"&'ZWYTNI",0xbd,"HD",0x02,0x1b,0x19,"0",0x1d,"2586K",0x00 ; 38ad
        db "LGVMQ",0xbb,0x13,0x14,":",0xb6,"$#-9XSOJBCE",0xb7,0x0f,0x16,0x0b,0x0c,"1473UR" ; 38cd

; ---------------- data: CHARSET_LOWER2 (38ed-392c) 
CHARSET_LOWER2:
        db "kf",0x18,"pa",0x03,0x17,"_ ",0x7f,"&'zwytni",0xbd,"hd",0x02,0x1b,0x19,"0",0x1d,"2586k",0x00 ; 38ed
        db "lgvmq",0xbb,0x13,0x14,":",0xb6,"$#-9xsojbce",0xb7,0x0f,0x16,0x0b,0x0c,"1473ur" ; 390d

; ---------------- data: CHARSET_GRAPHICS (392d-396e) graphic / extended characters 0x94-0x9D, 0xC0-0xCF, 0xE0-0xEF
CHARSET_GRAPHICS:
        db 0xca,0xc5,0x12,0xcf,0xc0,0xde,0x11,0x1e,0x9e,0x7f,0x9d,0x96,0xed,0xe6,0xe8,0xe3 ; 392d
        db 0xcd,0xc8,0x1f,0xc7,0xc3,0xdc,0x1a,0x19,0x9b,0x1d,0x98,0xef,0xea,0x94,0xca,0x00 ; 393d
        db 0xcb,0xc6,0xe5,0xcc,0xe0,0xdd,0x10,0x14,0x9c,0x1c,0x9a,0x95,0xec,0xeb,0xe7,0xe2 ; 394d
        db 0xce,0xc9,0xc1,0xc2,0xc4,0xdf,0x07,0x15,0x08,0x0a,0x97,0xee,0xe9,0x99,0xe4,0xe1 ; 395d
        db 0xda,0xda                                                           ; 396d

; ---------------- data: DEMO_MESSAGE (396f-3c20) built-in demonstration message (contains control codes 10,11,12,13,14,BC,BE,8x colours,A2-AB graphics)
DEMO_MESSAGE:
        db "THE ",0x12,0x14,"ULTIMATE ",0x11,0x8c,"INFRARED ",0xbc,"REMOT"     ; 396f
        db "E CONTROL MULTI-COLOR DISPLAY..."                                  ; 398f
        db ".. ",0x10,"** MAGIC ** ",0x11,"AUTOMATIC COLOR"                    ; 39af
        db " CHANGING.....PLUS.....",0xbc,0x14,"RAINBOW"                       ; 39cf
        db " ",0x11,"PROGRAMMING IN ",0x10,"10 ",0x11,"VIBRANT CO"             ; 39ef
        db "LORS ",0x8c,"llllllllll ",0x83,"llllllllll ",0x8f,"ll"             ; 3a0f
        db "llllllll ",0x8d,"llllllllll ",0x87,"llllllllll"                    ; 3a2f
        db " ",0xbc,">>>>> NETWORKABLE <<<<< INCLUD"                           ; 3a4f
        db "ES PC FLOPPY DISK & CABLE .....",0x12                              ; 3a6f
        db "8K ",0x11,"MEMORY .....",0x83,0x12,"100 ",0x11,0xbc,"MEMORY B"     ; 3a8f
        db "ANKS ..... ",0x10,"14 ",0x11,"CHARACTERS OR ",0xbe,"2"             ; 3aaf
        db "8 TINY CHARACTERS ",0xbc,"..... PROGRAM"                           ; 3acf
        db "S ",0x10,"47 ",0x13,"EUROPEAN ",0x11,"CHARACTERS ...."             ; 3aef
        db ". ",0x12,"8 ",0x11,"SPEEDS ....UPPER & lower F"                    ; 3b0f
        db "ONTS ..... ",0x10,"36 SPECIAL FUNCTIONS"                           ; 3b2f
        db " ",0x11,".....INCLUDING...... CLOCK _",0x14," "                    ; 3b4f
        db " FLASH ",0x11,".....BEEP ",0x07,0x07," ",0x07,"..... ",0x12,"BOL"  ; 3b6f
        db "D ...... ",0x13,"ITALIC ",0x11,".....",0x14,"AND ...."             ; 3b8f
        db ". CUSTOM GRAPHICS ",0xa2,0xa3,0xa5,0xaa,0xab,"..... OR "           ; 3baf
        db "YOUR OWN LOGO..... ",0xbe,"TINY PRICE  "                           ; 3bcf
        db "        ",0x10,"LARGE  IMPACT!!",0x03,0xdb,"CURREN"                ; 3bef
        db "T TEST  ",0x10,0x17,0x17,0x17,0x17,0x17,0x17,0x17," ",0x03         ; 3c0f

; 3c21-7FFF: 0xFF (unused part of the 32K EPROM)
