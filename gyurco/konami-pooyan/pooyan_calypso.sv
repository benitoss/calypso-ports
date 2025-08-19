//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
`default_nettype none

module pooyan_calypso(
    input CLK12M,
`ifdef USE_CLOCK_50
    input CLOCK_50,
`endif

    output [7:0] LED,
    output [VGA_BITS-1:0] VGA_R,
    output [VGA_BITS-1:0] VGA_G,
    output [VGA_BITS-1:0] VGA_B,
    output VGA_HS,
    output VGA_VS,

    input SPI_SCK,
    inout SPI_DO,
    input SPI_DI,
    input SPI_SS2,
    input SPI_SS3,
    input CONF_DATA0,

`ifndef NO_DIRECT_UPLOAD
    input SPI_SS4,
`endif

`ifdef I2S_AUDIO
    output I2S_BCK,
    output I2S_LRCK,
    output I2S_DATA,
`endif

`ifdef USE_AUDIO_IN
    input AUDIO_IN,
`endif

    output [12:0] SDRAM_A,
    inout [15:0] SDRAM_DQ,
    output SDRAM_DQML,
    output SDRAM_DQMH,
    output SDRAM_nWE,
    output SDRAM_nCAS,
    output SDRAM_nRAS,
    output SDRAM_nCS,
    output [1:0] SDRAM_BA,
    output SDRAM_CLK,
    output SDRAM_CKE

);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 4;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`ifdef USE_AUDIO_IN
localparam bit USE_AUDIO_IN = 1;
wire TAPE_SOUND=AUDIO_IN;
`else
localparam bit USE_AUDIO_IN = 0;
wire TAPE_SOUND=UART_RX;
`endif

assign LED[0] = ~ioctl_downl; 

`include "build_id.v" 

localparam CONF_STR = {
    "POOYAN;;",
    "O2,Rotate Controls,Off,On;",
    "OGH,Orientation,Vertical,Clockwise,Anticlockwise;",
    "OI,Rotation filter,Off,On;",
    "O34,Scanlines,Off,25%,50%,75%;",
    "O5,Blend,Off,On;",
    "O67,Lives,3,4,5,Unl.;",
    "O8,Bonus Life,50K 80K+,30K 70K+;",
    "O9B,Difficulty,1,2,3,4,5,6,7,8;",
    "OC,Demo Sounds,Off,On;",
    "T0,Reset;",
    "V,",`BUILD_VERSION,"-",`BUILD_DATE
};

wire       rotate = status[2];
wire [1:0] rotate_screen = status[17:16];
wire       rotate_filter = status[18];
wire [1:0] scanlines = status[4:3];
wire       blend = status[5];
wire [1:0] lives = status[7:6];
wire       bonus = status[8];
wire [2:0] difficulty = status[11:9];
wire       demosnd = status[12];

assign SDRAM_CLK = clock_96;
assign SDRAM_CKE = 1;

/////////////////  CLOCKS  ////////////////////////

wire clock_96, clock_48, clock_12, clock_6, clock_14, clock_70, pll_locked;
pll pll(
    .inclk0(CLK12M),
    .c0(clock_96),
    .c1(clock_12),
    .c2(clock_6),
    .c3(clock_48),
    .locked(pll_locked)
);
    
pll_aud pll_aud(
    .inclk0(CLK12M),
    .c0(clock_14),
    .c1(clock_70)
);


wire [31:0] status;
wire  [1:0] buttons;
wire  [1:0] switches;
wire  [31:0] joystick_0;
wire  [31:0] joystick_1;
wire        scandoublerD;
wire        ypbpr;
wire        no_csync;
wire        key_strobe;
wire        key_pressed;
wire  [7:0] key_code;


user_io #(
    .STRLEN($size(CONF_STR)>>3),
    .FEATURES(32'h0 | (BIG_OSD << 13) | (HDMI << 14)))
user_io(
    .clk_sys        (clock_12       ),
    .conf_str       (CONF_STR       ),
    .SPI_CLK        (SPI_SCK        ),
    .SPI_SS_IO      (CONF_DATA0     ),
    .SPI_MISO       (SPI_DO         ),
    .SPI_MOSI       (SPI_DI         ),
    .buttons        (buttons        ),
    .switches       (switches       ),
    .scandoubler_disable (scandoublerD    ),
    .ypbpr          (ypbpr          ),
    .no_csync       (no_csync       ),
    
    .key_strobe     (key_strobe     ),
    .key_pressed    (key_pressed    ),
    .key_code       (key_code       ),
    .joystick_0     (joystick_0     ),
    .joystick_1     (joystick_1     ),
    .status         (status         )
    );

wire [14:0] rom_addr;
wire [15:0] rom_do;
wire        rom_rd;
wire        ioctl_downl;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

data_io data_io(
    .clk_sys       ( clock_48     ),
    .SPI_SCK       ( SPI_SCK      ),
    .SPI_SS2       ( SPI_SS2      ),
    .SPI_DI        ( SPI_DI       ),
    .ioctl_download( ioctl_downl  ),
    .ioctl_index   ( ioctl_index  ),
    .ioctl_wr      ( ioctl_wr     ),
    .ioctl_addr    ( ioctl_addr   ),
    .ioctl_dout    ( ioctl_dout   )
);

reg port1_req = 1'b0;

always @(posedge clock_48) begin
    reg        ioctl_wr_last = 0;

    ioctl_wr_last <= ioctl_wr;
    if (ioctl_downl) begin
        if (~ioctl_wr_last && ioctl_wr) begin
            port1_req <= ~port1_req;
        end
    end
end

reg reset = 1;
reg rom_loaded = 0;
always @(posedge clock_12) begin
    reg ioctl_downlD;
    ioctl_downlD <= ioctl_downl;

    if (ioctl_downlD & ~ioctl_downl) rom_loaded <= 1;
    reset <= status[0] | buttons[1] | ~rom_loaded;
end

wire [10:0] audio;
wire        hs, vs;
wire        hb, vb;
wire [2:0]  r,g;
wire [1:0]  b;

pooyan pooyan(
    .clock_6(clock_6),
    .clock_12(clock_12),
    .clock_14(clock_14),
    .reset(reset),
    .video_r(r),
    .video_g(g),
    .video_b(b),
    .video_hblank(hb),
    .video_vblank(vb),
    .video_hs(hs),
    .video_vs(vs),
    .audio_out(audio),
    .roms_addr          ( rom_addr          ),
    .roms_do            ( rom_addr[0] ? rom_do[15:8] : rom_do[7:0] ),
    .roms_rd                ( rom_rd                ),
    .dip_switch_1(8'b11111111),// Coinage_B / Coinage_A
    .dip_switch_2(~{demosnd, difficulty, bonus, 1'b1, lives}),// Sound(8)/Difficulty(7-5)/Bonus(4)/Cocktail(3)/lives(2-1)
    .start2(m_two_players),
    .start1(m_one_player),
    .coin1(m_coin1),
    .fire1(m_fireA),
    .right1(m_right),
    .left1(m_left),
    .down1(m_down),
    .up1(m_up),
    .fire2(m_fire2A),
    .right2(m_right2),
    .left2(m_left2),
    .down2(m_down2),
    .up2(m_up2)
    );

mist_dual_video #(.COLOR_DEPTH(3), .SD_HCNT_WIDTH(10), .OUT_COLOR_DEPTH(VGA_BITS), .USE_BLANKS(1'b1), .BIG_OSD(BIG_OSD)) mist_video(
    .clk_sys        ( clock_96 | reset        ),
    .SPI_SCK        ( SPI_SCK          ),
    .SPI_SS3        ( SPI_SS3          ),
    .SPI_DI         ( SPI_DI           ),
    .R              ( r                ),
    .G              ( g                ),
    .B              ( {b, b[1]}        ),
    .HBlank         ( hb               ),
    .VBlank         ( vb               ),
    .HSync          ( hs               ),
    .VSync          ( vs               ),
    .VGA_R          ( VGA_R            ),
    .VGA_G          ( VGA_G            ),
    .VGA_B          ( VGA_B            ),
    .VGA_VS         ( VGA_VS           ),
    .VGA_HS         ( VGA_HS           ),

    .clk_sdram      ( clock_96         ),
    .sdram_init     ( ~pll_locked      ),
    .SDRAM_A        ( SDRAM_A          ),
    .SDRAM_DQ       ( SDRAM_DQ         ),
    .SDRAM_DQML     ( SDRAM_DQML       ),
    .SDRAM_DQMH     ( SDRAM_DQMH       ),
    .SDRAM_nWE      ( SDRAM_nWE        ),
    .SDRAM_nCAS     ( SDRAM_nCAS       ),
    .SDRAM_nRAS     ( SDRAM_nRAS       ),
    .SDRAM_nCS      ( SDRAM_nCS        ),
    .SDRAM_BA       ( SDRAM_BA         ),

    .ram_din        ( {ioctl_dout, ioctl_dout} ),
    .ram_dout       ( ),
    .ram_addr       ( ioctl_addr[22:1] ),
    .ram_ds         ( { ioctl_addr[0], ~ioctl_addr[0] } ),
    .ram_req        ( port1_req        ),
    .ram_we         ( ioctl_downl      ),
    .ram_ack        ( ),
    .rom_oe         ( rom_rd           ),
    .rom_addr       ( rom_addr[14:1]   ),
    .rom_dout       ( rom_do           ),

    .ce_divider     ( 4'd15            ),
    .rotate         ( { 1'b1, rotate } ),
    .rotate_screen  ( rotate_screen    ),
    .rotate_hfilter ( rotate_filter    ),
    .rotate_vfilter ( rotate_filter    ),
    
    .scandoubler_disable( scandoublerD ),
    .blend          ( blend            ),
    .scanlines      ( scanlines        ),
    .ypbpr          ( ypbpr            ),
    .no_csync       ( no_csync         )
    );


`ifdef I2S_AUDIO
i2s i2s (
    .reset(1'b0),
    .clk(clock_70),
    .clk_rate(32'd71_589_996),
    .sclk(I2S_BCK),
    .lrclk(I2S_LRCK),
    .sdata(I2S_DATA),
    .left_chan({2'd0, audio, 3'd0}),
    .right_chan({2'd0, audio, 3'd0})
);
`endif


// Arcade inputs
wire m_up, m_down, m_left, m_right, m_fireA, m_fireB, m_fireC, m_fireD, m_fireE, m_fireF;
wire m_up2, m_down2, m_left2, m_right2, m_fire2A, m_fire2B, m_fire2C, m_fire2D, m_fire2E, m_fire2F;
wire m_tilt, m_coin1, m_coin2, m_coin3, m_coin4, m_one_player, m_two_players, m_three_players, m_four_players;

arcade_inputs #(.START1(10), .START2(12), .COIN1(11)) inputs (
    .clk         ( clock_12    ),
    .key_strobe  ( key_strobe  ),
    .key_pressed ( key_pressed ),
    .key_code    ( key_code    ),
    .joystick_0  ( joystick_0  ),
    .joystick_1  ( joystick_1  ),
    .rotate      ( rotate      ),
    .orientation ( {1'b1, ~|rotate_screen} ),
    .joyswap     ( 1'b0        ),
    .oneplayer   ( 1'b1        ),
    .controls    ( {m_tilt, m_coin4, m_coin3, m_coin2, m_coin1, m_four_players, m_three_players, m_two_players, m_one_player} ),
    .player1     ( {m_fireF, m_fireE, m_fireD, m_fireC, m_fireB, m_fireA, m_up, m_down, m_left, m_right} ),
    .player2     ( {m_fire2F, m_fire2E, m_fire2D, m_fire2C, m_fire2B, m_fire2A, m_up2, m_down2, m_left2, m_right2} )
);

endmodule
