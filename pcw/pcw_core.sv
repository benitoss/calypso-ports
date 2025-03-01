//
// PCW Main Core for PCW_MiSTer
//
// Copyright (c) 2020 Stephen Eddy
//
// Calypso adaptations for full SDRAM, more realistic WAIT signal implementation
// and interrupt handling (c) 2025 Manuel Teira
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without 
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

module pcw_core(
    input wire reset,           // Reset
	input wire clk_sys,         // 64 Mhz System Clock

    output logic [23:0] RGB,    // RGB Output (8-8-8)     
	output logic hsync,         // Horizontal sync
	output logic vsync,         // Vertical sync
	output logic hblank,        // Horizontal blanking
	output logic vblank,        // Vertical blanking

    output logic [7:0] LED,           // LED output
    output logic [13:0] audiomix,
    input wire [7:0] joy0,
    input wire [7:0] joy1,
    input wire [2:0] joy_type,
    input wire [10:0] ps2_key,
    input wire [24:0] ps2_mouse,
    input wire [1:0] mouse_type,
    input wire [1:0] disp_color,
    input wire ntsc,
    input wire model,
    input wire [1:0] memory_size,
    input wire dktronics,
    input wire [1:0] fake_colour_mode,

    // SDRAM signals
	output        SDRAM_CKE,
	output [11:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,
    input         locked,

    input wire [1:0]  img_mounted,
	input wire        img_readonly,
	input wire [31:0] img_size,
    input wire [1:0]  density,

	output logic [31:0] sd_lba,
	output logic [1:0] sd_rd,
	output logic [1:0] sd_wr,
	input  wire        sd_ack,
	input  wire  [8:0] sd_buff_addr,
	input  wire  [7:0] sd_buff_dout,
	output logic [7:0] sd_buff_din,
	input  wire        sd_dout_strobe,
    
    output wire [7:0] AUX
);

    
    // Joystick types
    localparam JOY_NONE         = 3'b000;
    localparam JOY_KEMPSTON     = 3'b001;
    localparam JOY_SPECTRAVIDEO = 3'b010;
    localparam JOY_CASCADE      = 3'b011;
    localparam JOY_DKTRONICS    = 3'b100;

    localparam MOUSE_NONE       = 2'b00;
    localparam MOUSE_AMX        = 2'b01;
    localparam MOUSE_KEMPSTON   = 2'b10;
    localparam MOUSE_KEYMOUSE   = 2'b11;

    localparam MODEL_8512 = 0;
    localparam MODEL_9512 = 1;

    localparam MEM_256K = 0;
    localparam MEM_512K = 1;
    localparam MEM_1M = 2;
    localparam MEM_2M = 3;

    wire cpu_ce_p /* synthesis keep */;
    wire cpu_ce_n /* synthesis keep */;
    wire sdram_clk_ref /* synthesis keep */;
    wire pix_stb /* synthesis keep */;
    wire disk_ce /* synthesis keep */;
    wire snd_ce;
    ce_generator ce_generator(
        .clk(clk_sys),
        .reset(reset),
        .cpu_ce_p(cpu_ce_p),
        .cpu_ce_n(cpu_ce_n),
        .sdram_clk_ref(sdram_clk_ref),
        .ce_16mhz(pix_stb),
        .ce_4mhz(disk_ce),
        .ce_2mhz(snd_ce)
    );
    
    wire dn_wr;
    wire dn_rd;
    wire [15:0] dn_addr;
    wire [7:0] dn_data;
    wire dn_active;
    wire [15:0] execute_addr;
    wire execute_enable;
    pcw_starter pcw_starter(
        .clk(clk_sys),
        .reset(reset),
        .sdram_clk_ref(sdram_clk_ref),
        .sdram_ready(sdram_ready),
        .model(model),
        .wr(dn_wr),
        .rd(dn_rd),
        .addr(dn_addr),
        .data(dn_data),
        .active(dn_active),
        .exec_addr(execute_addr),
        .exec_enable(execute_enable)
    );


    logic fake_colour;
    assign fake_colour = (fake_colour_mode != 2'b00);

    // Audio channels
    logic [11:0] ch_a;
    logic [11:0] ch_b;
    logic [11:0] ch_c;
    logic [13:0] audio;
    logic speaker_enable = 1'b0;

    logic [16:0] vid_ram_addr /* synthesis keep */;
    logic [20:0] cpu_ram_addr/* synthesis keep */;
    reg [7:0] vid_ram_dout /* synthesis keep */;
    reg [7:0] cpu_ram_dout;
    
    // cpu control
    logic [15:0] cpua /* synthesis keep */;
    logic [7:0] cpudo /* synthesis keep */;
    logic [7:0] cpudi /* synthesis keep */;
    logic cpuwr,cpurd,cpumreq,cpuiorq,cpum1 /* synthesis keep */;
    logic romrd,ramrd,ramwr;
    logic ior,iow,memr,memw;

    
    reg cpu_ce_g_p /* synthesis keep */;
    reg cpu_ce_g_n /* synthesis keep */;   
    reg gclk /* synthesis keep */;
    assign cpu_ce_g_p = dn_active ? 1'b0 : cpu_ce_p;
    assign cpu_ce_g_n = dn_active ? 1'b0 : cpu_ce_n;
    assign gclk = dn_active ? 1'b0 : clk_sys;
    
    reg [1:0] tstate /* synthesis keep */;
    reg WAIT_n /* synthesis keep */;
    reg [20:0] sdram_addr;
    wire rfsh;
    reg cpu_ce_g_p_last;
    always @(posedge clk_sys)
    begin
        cpu_ce_g_p_last <= cpu_ce_g_p;
        if (cpu_reset == 1'b1) begin
            tstate <= 2'b00;
        end else begin
            if (~cpu_ce_g_p_last & cpu_ce_g_p) begin
                tstate <= tstate + 1'b1;
            end
        end
    end
    assign WAIT_n = tstate == 2'b01 || ~ior || ~iow;
    reg cpu_reset /* synthesis keep */;
    assign cpu_reset = reset || dn_active;

    reg [7:0] sdram_dout /* synthesis keep */;
    logic [22:0] sdram_addr_in /* synthesis keep */;
    logic [7:0] sdram_din /* synthesis keep */;
    logic sdram_we;
    logic sdram_oe /* synthesis keep */;
    logic clkref /* synthesis keep */;
    assign sdram_addr_in = dn_active ? {7'b0, dn_addr[15:0]} : cpu_ram_addr;
    assign sdram_din = dn_active ? dn_data : cpudo;
    assign sdram_we = dn_active ? dn_wr : ~memw;
    assign sdram_oe = dn_active ? dn_rd : ~memr;
    assign cpu_ram_dout = sdram_dout;
    
    wire [15:0] vid_data_out_16;
    assign vid_ram_dout = vid_ram_addr[0] ? vid_data_out_16[15:8] : vid_data_out_16[7:0];
    
    wire sdram_ready;
    
    assign clkref = sdram_clk_ref;
    assign SDRAM_BA = 2'b00;
    sdram sdram (
        .SDRAM_CKE(SDRAM_CKE),
        .SDRAM_A(SDRAM_A),
        .SDRAM_DQ(SDRAM_DQ),
        .SDRAM_DQML(SDRAM_DQML),
        .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_nCS(SDRAM_nCS),
        .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nWE(SDRAM_nWE),
        
        .init(~locked),
        .clk(clk_sys),
        .clkref(clkref),
        
        .bank(2'b00),
        .dout(sdram_dout),
        .din (sdram_din),
        .addr(sdram_addr_in),
        .we(sdram_we),
        .oe(sdram_oe),
        
        .vram_addr(vid_ram_addr),
        .vram_dout(vid_data_out_16),

        .ready(sdram_ready)
    );

    // CPU register debugging for Signal Tap
    logic [15:0] PC /* synthesis keep */; 
    logic [15:0] SP /* synthesis keep */;
    logic [7:0]  AC /* synthesis keep */;
    logic [15:0] BC /* synthesis keep */; 
    logic [15:0] DE /* synthesis keep */;
    logic [15:0] HL /* synthesis keep */;
    logic [15:0] IX /* synthesis keep */;
    logic [15:0] IY /* synthesis keep */;
    logic Z /* synthesis keep */;
    logic N /* synthesis keep */;
    logic P  /* synthesis keep */;
    logic C /* synthesis keep */;

    // Used for CPU debugging in SignalTap
    z80_debugger debugger(
        .*,
        .ce(cpu_ce_g_p),
        .m1_n(cpum1),
        .REG_in(cpu_reg)
    ); 
    
    // Used to jump to address 0 on reset after ROM loads
    z80_regset z80_regset(
        .*,
        .dir_set(cpu_reg_set),
        .dir_out(cpu_reg_out)
    );
    
    // Generate CPU positive and negative edges (delayed 1 clk_sys)
    //logic cpu_pe, cpu_ne;
    //edge_det cpu_edge_det(.clk_sys(clk_sys), .signal(cpuclk), .pos_edge(cpu_pe), .neg_edge(cpu_ne));

    // CPU / memory access flags
    assign ior = cpurd | cpuiorq | ~cpum1;
    assign iow = cpuwr | cpuiorq | ~cpum1;
    assign memr = cpurd | cpumreq;
    assign memw = cpuwr | cpumreq;
    logic kbd_sel /* synthesis keep */;
    assign kbd_sel = cpu_ram_addr[20:4]==17'b00000111111111111 && memr==1'b0 ? 1'b1 : 1'b0;
    logic daisy_sel;
    assign daisy_sel = ((cpua[7:0]==8'hfc || cpua[7:0]==8'hfd) & model) && (~ior | ~iow)? 1'b1 : 1'b0;
	 
    // Create processor instance
    T80pa cpu(
       	.RESET_n(~cpu_reset),
        .CLK(gclk),
        .CEN_p(cpu_ce_g_p),
        .CEN_n(cpu_ce_g_n),
        .M1_n(cpum1),
        .WAIT_n(WAIT_n),
        .MREQ_n(cpumreq),
        .IORQ_n(cpuiorq),
        .NMI_n(nmi_sig),
        .INT_n(int_sig),
        .RD_n(cpurd),
        .WR_n(cpuwr),
        .RFSH_n(rfsh),
        .A(cpua),
        .DI(cpudi),
        .DO(cpudo),
		.REG(cpu_reg),
        .DIR(cpu_reg_out),
        .DIRSet(cpu_reg_set)  
    );

    // Interrupt enable flag for timer interrupt check
    logic iff1/* synthesis keep */;
    assign iff1 = cpu_reg[210]/* synthesis keep */;
    logic [3:0] timer_misses;
    logic motor = 0;          // Motor on off register
    logic disk_to_nmi = 0;  // if 1, disk generates nmi
    logic disk_to_int = 0;  // if 1, disk generates int
    logic tc = 0;           // TC signal to reset disk
    logic [7:0] portF0 /*synthesis noprune*/;     // 0x0000-0x3fff page map
    logic [7:0] portF1 /*synthesis noprune*/;     // 0x4000-0x7fff page map
    logic [7:0] portF2 /*synthesis noprune*/;     // 0x8000-0xbfff page map
    logic [7:0] portF3 /*synthesis noprune*/;     // 0xc000-0xffff page map
    logic [7:0] portF4 /*synthesis noprune*/;     // Memory read lock register (CPC only)
    logic [7:0] portF5 /*synthesis noprune*/;     // Roller RAM address
    logic [7:0] portF6 /*synthesis noprune*/;     // Y scroll
    logic [7:0] portF7 /*synthesis noprune*/;     // Inverse / Disable
    logic [7:0] portF8 /*synthesis noprune*/;     // Ntsc / Flyback (read)

    // Set CPU data in
    always_comb
    begin
        if(~ior)
        begin
            if(cpua[15:0]==16'h01fc) cpudi = model ? daisy_dout : 8'hff; 
            else begin		
                casez(cpua[7:0])
                        8'hf8: cpudi = portF8;
                        8'hf4: cpudi = portF8;      // Timer interrupt counter will also clear
                        8'hfc: cpudi = model ? daisy_dout : 8'hf8;       // Printer Controller
                        8'hfd: cpudi = model ? daisy_dout : 8'hc8;       // Printer Controller
                        8'he0: begin                // Joystick or CPS
                            case(joy_type)
                                JOY_SPECTRAVIDEO: cpudi = {3'b0,joy0[0],joy0[3],joy0[1],joy0[4],joy0[2]}; // Right,Up,Left,Fire,Down
                                JOY_CASCADE: cpudi = {~joy0[4],2'b0,~joy0[3],1'b0,~joy0[2],~joy0[0],~joy0[1]}; // Fire,Up,Down,Right,Left
                                default: cpudi = 8'h00;       // Dart and CPS
                            endcase
                        end
                        // Kempston Mouse
                        8'b110100??, 8'hd4: cpudi = kempston_dout;
                        // AMX Mouse
                        8'b10?000??: cpudi = amx_dout;
                        // DK Tronics sound and joystick controller
                        8'ha9: cpudi = dktronics ? dk_out : 8'hff;
                        // Kempston Joystick
                        8'h9f: cpudi = (joy_type==JOY_KEMPSTON) ? {3'b0,joy0[4:0]} : 8'hff; // Fire,Up,Down,Left,Right
                        // Floppy controller
                        8'b0000000?: cpudi = fdc_dout;    // Floppy read or write
                        default: cpudi = 8'hff;             
                endcase
            end
        end
        else begin
            cpudi = kbd_sel ? kbd_data : cpu_ram_dout;
        end
    end

    assign portF8 = {1'b0, vblank, fdc_int_latch, ~ntsc, timer_misses};
    logic int_mode_change = 1'b0;
    // IO writing to register ports
    always @(posedge clk_sys)
    begin
        if(reset)
        begin
            portF0 <= 8'h80;
            portF1 <= 8'h81;
            portF2 <= 8'h82;
            portF3 <= 8'h83;
            portF4 <= 8'hf1;
            portF5 <= 8'h00;
            portF6 <= 8'h00;
            portF7 <= 8'h80;
            int_mode_change <= 1'b0;
            disk_to_nmi <= 1'b0;
            disk_to_int <= 1'b0;
            tc <= 1'b0;
            motor <= 1'b0;
            speaker_enable <= 1'b0;
        end
        int_mode_change <= 1'b0;

        if(~iow && cpua[7:0]==8'hf0) portF0 <= cpudo;
        if(~iow && cpua[7:0]==8'hf1) portF1 <= cpudo;
        if(~iow && cpua[7:0]==8'hf2) portF2 <= cpudo;
        if(~iow && cpua[7:0]==8'hf3) portF3 <= cpudo;
        if(~iow && cpua[7:0]==8'hf4) portF4 <= cpudo;
        if(~iow && cpua[7:0]==8'hf5) portF5 <= cpudo;
        if(~iow && cpua[7:0]==8'hf6) portF6 <= cpudo;
        if(~iow && cpua[7:0]==8'hf7) portF7 <= cpudo;
        if(~iow && cpua[7:0]==8'hf8) 
        begin
            // decode command for System Control Register
            if(cpudo[3:0] == 4'd0) ; // Terminate bootstrap (do nothing)
           // else if(cpudo[3:0] == 4'd1) reset <= 1'b1;  // System Reset
            else if(cpudo[3:0] == 4'd2) begin           // Disk to NMI
                disk_to_nmi <= 1'b1;
                disk_to_int <= 1'b0;
            end
            else if(cpudo[3:0] == 4'd3) begin           // Disk to INT
                disk_to_int <= 1'b1;
                disk_to_nmi <= 1'b0;
                int_mode_change <= 1'b1;
            end
            else if(cpudo[3:0] == 4'd4) begin           // Disconnect Disk Int/NMI
                disk_to_int <= 1'b0;
                disk_to_nmi <= 1'b0;
                int_mode_change <= 1'b1;
            end
            else if(cpudo[3:0] == 4'd5) begin           // Set FDC TC
                tc <= 1'b1;
            end            
            else if(cpudo[3:0] == 4'd6) begin           // Clear FDC TC
                tc <= 1'b0;
            end            
            else if(cpudo[3:0] == 4'd9) motor <= 1'b1;
            else if(cpudo[3:0] == 4'd10) motor <= 1'b0;
            else if(cpudo[3:0] == 4'd11) speaker_enable <= 1'b1;
            else if(cpudo[3:0] == 4'd12) speaker_enable <= 1'b0;
            //if(img_mounted) motor <= 0; // Reset on new image mounted
        end
    end
    
    // Detect int_mode_change edge
    logic int_mode_pe, int_mode_ne;
    edge_det int_mode_edge_det(.clk_sys(clk_sys), .signal(int_mode_change), .pos_edge(int_mode_pe), .neg_edge(int_mode_ne));

    // detect fdc interrupt edge
    logic fdc_pe /* synthesis keep */, fdc_ne /* synthesis keep */;
    edge_det fdc_edge_det(.clk_sys(clk_sys), .signal(fdc_int), .pos_edge(fdc_pe), .neg_edge(fdc_ne));
    //  Drive FDC status latch (portF8) and NMI flag
    logic fdc_int_latch /* synthesis keep */ = 1'b0;
    logic clear_nmi_flag = 1'b0;
    logic nmi_flag = 1'b0;
    always @(posedge clk_sys)
    begin
        if (fdc_pe) begin
            fdc_int_latch <= 1'b1;
            if (disk_to_nmi) nmi_flag <= 1'b1;
        end
        else if (fdc_ne) fdc_int_latch <= 1'b0;
        if (clear_nmi_flag) nmi_flag <= 1'b0;
    end

    // Detect timer interrupt firing from video controller (300 hz)
    logic vid_timer /* synthesis keep */;
    logic last_vid_timer;
    logic timer_line = 1'b0;
    logic int_line = 1'b0;
    logic nmi_line = 1'b0;
    logic clear_timer = 1'b0;
    logic last_cpum1;
    
    // Timer flag and interrupt flag drivers
    always @(posedge clk_sys)
    begin
        last_cpum1 <= cpum1;
        last_vid_timer <= vid_timer;
        int_line <= disk_to_int & fdc_int_latch;
        nmi_line <= nmi_flag;
        
        if (~last_vid_timer & vid_timer)
        begin
            if (!(&timer_misses)) timer_misses <= timer_misses + 4'b1;
            timer_line <= 1'b1;
        end
        
        // Detect clear timer start
        if (~ior && cpua[7:0] == 8'hf4 && clear_timer == 1'b0) begin
            clear_timer <= 1'b1;
            timer_line <= 1'b0;
        end

        // Deferred timer cleaning
        if (clear_timer == 1'b1)
        begin
            if (~last_cpum1 & cpum1 & cpuiorq) 
            begin
                clear_timer <= 1'b0;
                timer_misses <= 'b0;
            end
        end
        
        // Clear interrupts: Check if this makes sense
        if (int_mode_pe) begin
            if (disk_to_int) clear_nmi_flag <= 1'b1;
        end 
        else clear_nmi_flag <= 1'b0;
    end
    
	logic nmi_sig/* synthesis keep */, int_sig/* synthesis keep */;
    assign nmi_sig = ~nmi_line;
    // Disk int and timer int combined
    assign int_sig = nmi_line ? 1'b1 : ~(int_line | timer_line);
    
    // Video control registers
    logic [7:0] roller_ptr;
    logic [7:0] yscroll;
    logic inverse;
    logic disable_vid;
    assign roller_ptr = portF5;
    assign yscroll = portF6;
    assign inverse = portF7[7];
    assign disable_vid = ~portF7[6] || dn_active;
    
    // Ram B address for various paging modes
    logic [20:0] pcw_ram_b_addr/* synthesis keep */;
    logic [17:0] cpc_read_ram_b_addr/* synthesis keep */;
    logic [17:0] cpc_write_ram_b_addr/* synthesis keep */;

    // Memory size adjusted ports
    logic [6:0] mportF0,mportF1,mportF2,mportF3;
    always_comb
    begin 
        case(memory_size)
            MEM_256K: begin
                mportF0 = {3'b0,portF0[3:0]};
                mportF1 = {3'b0,portF1[3:0]};
                mportF2 = {3'b0,portF2[3:0]};
                mportF3 = {3'b0,portF3[3:0]};
            end
            MEM_512K: begin
                mportF0 = {2'b0,portF0[4:0]};
                mportF1 = {2'b0,portF1[4:0]};
                mportF2 = {2'b0,portF2[4:0]};
                mportF3 = {2'b0,portF3[4:0]};
            end
            MEM_1M: begin
                mportF0 = {1'b0,portF0[5:0]};
                mportF1 = {1'b0,portF1[5:0]};
                mportF2 = {1'b0,portF2[5:0]};
                mportF3 = {1'b0,portF3[5:0]};
            end
            MEM_2M: begin
                mportF0 = portF0[6:0];
                mportF1 = portF1[6:0];
                mportF2 = portF2[6:0];
                mportF3 = portF3[6:0];
            end
       endcase
    end

    // PCW Paged memory support for read and writes
    always_comb
    begin
        case(cpua[15:14])
            2'b00: pcw_ram_b_addr = {mportF0,cpua[13:0]};
            2'b01: pcw_ram_b_addr = {mportF1,cpua[13:0]};
            2'b10: pcw_ram_b_addr = {mportF2,cpua[13:0]};
            2'b11: pcw_ram_b_addr = {mportF3,cpua[13:0]};
        endcase
    end

    // CPC Paged memory support for reads
    always_comb
    begin
        case(cpua[15:14])
            2'b00: cpc_read_ram_b_addr = portF4[4] ? {1'b0,portF0[2:0],cpua[13:0]} : {1'b0,portF0[6:4],cpua[13:0]};
            2'b01: cpc_read_ram_b_addr = portF4[5] ? {1'b0,portF1[2:0],cpua[13:0]} : {1'b0,portF1[6:4],cpua[13:0]};
            2'b10: cpc_read_ram_b_addr = portF4[6] ? {1'b0,portF2[2:0],cpua[13:0]} : {1'b0,portF2[6:4],cpua[13:0]};
            2'b11: cpc_read_ram_b_addr = portF4[7] ? {1'b0,portF3[2:0],cpua[13:0]} : {1'b0,portF3[6:4],cpua[13:0]};
        endcase
    end

    // CPC Paged memory support for writes
    always_comb
    begin
        case(cpua[15:14])
            2'b00: cpc_write_ram_b_addr = {1'b0,portF0[2:0],cpua[13:0]};
            2'b01: cpc_write_ram_b_addr = {1'b0,portF1[2:0],cpua[13:0]};
            2'b10: cpc_write_ram_b_addr = {1'b0,portF2[2:0],cpua[13:0]};
            2'b11: cpc_write_ram_b_addr = {1'b0,portF3[2:0],cpua[13:0]};
        endcase
    end

    // Finally memory address based upon above page modes
    always_comb
    begin
        case(cpua[15:14])
            2'b00: cpu_ram_addr = portF0[7] ? pcw_ram_b_addr : ~memw ? {3'b0,cpc_write_ram_b_addr} : {3'b0,cpc_read_ram_b_addr}; 
            2'b01: cpu_ram_addr = portF1[7] ? pcw_ram_b_addr : ~memw ? {3'b0,cpc_write_ram_b_addr} : {3'b0,cpc_read_ram_b_addr}; 
            2'b10: cpu_ram_addr = portF2[7] ? pcw_ram_b_addr : ~memw ? {3'b0,cpc_write_ram_b_addr} : {3'b0,cpc_read_ram_b_addr}; 
            2'b11: cpu_ram_addr = portF3[7] ? pcw_ram_b_addr : ~memw ? {3'b0,cpc_write_ram_b_addr} : {3'b0,cpc_read_ram_b_addr}; 
        endcase
    end


    // Edge detectors for moving fake pixel line using F9 and F10 keys
    logic line_up_pe, line_down_pe, toggle_pe;
    edge_det line_up_edge_det(.clk_sys(clk_sys), .signal(line_up), .pos_edge(line_up_pe));
    edge_det line_down_edge_det(.clk_sys(clk_sys), .signal(line_down), .pos_edge(line_down_pe));
    edge_det toggle_full_edge_det(.clk_sys(clk_sys), .signal(toggle_full), .pos_edge(toggle_pe));
    // Line position of fake colour line
    logic [7:0] fake_end;
    always @(posedge clk_sys)
    begin
        if(reset) fake_end <= 8'd0;
        else begin
            if(line_up_pe && fake_end > 0) fake_end <= fake_end - 8'd1;
            if(line_down_pe && fake_end < 255) fake_end <= fake_end + 8'd1;
            if(toggle_pe) begin
                if(fake_end==8'd255) fake_end <= 8'd0;
                else if(fake_end==8'd0) fake_end <= 8'd255;
                else fake_end <= 8'd0;
            end
            // Writen to via a write to port FF
            if(~iow && cpua[7:0]==8'hff) fake_end <= cpudo;
        end
    end

    logic [3:0] colour;

    logic [23:0] rgb_white;
    logic [23:0] rgb_green;
    logic [23:0] rgb_amber;

    logic cpu_reg_set = 1'b0;
    logic [211:0] cpu_reg = 'b0;
    logic [211:0] cpu_reg_out;
    logic [7:0] ypos;

    // Video output controller
    video_controller video(
        .reset(reset),
        .clk_sys(clk_sys),
        .pix_stb(pix_stb),
        .roller_ptr(roller_ptr),
        .yscroll(yscroll),
        .inverse(inverse),
        .disable_vid(disable_vid),
        .ntsc(ntsc),
        .fake_colour(fake_colour),
        .fake_end(fake_end),
        .ypos(ypos),

        .vid_addr(vid_ram_addr),
        .din(vid_ram_dout),

        .colour(colour),
        .hsync(hsync),
        .vsync(vsync),
        .hb(hblank),
        .vb(vblank),
        .timer_int(vid_timer)
    );

    // Video colour processing
    always_comb begin
        rgb_white = 24'hAAAAAA;
        if(colour==4'b0000) rgb_white = 24'h000000;
        else if(colour==4'b1111) rgb_white = 24'hAAAAAA;
    end

    always_comb begin
        rgb_green = 24'h00aa00;
        if(colour==4'b0000) rgb_green = 24'h000000;
        else if(colour==4'b1111) rgb_green = 24'h00aa00;
    end

    always_comb begin
        rgb_amber = 24'hff5500;
        if(colour==4'b0000) rgb_amber = 24'h000000;
        else if(colour==4'b1111) rgb_amber = 24'hff5500;
    end

    logic [23:0] mono_colour;
    always_comb begin
        if (disp_color==2'b00) mono_colour = model == 1'b0 ? rgb_green : rgb_white;
        else if(disp_color==2'b01) mono_colour = rgb_green;
        else if(disp_color==2'b10) mono_colour= rgb_white;
        else mono_colour = rgb_amber;
    end

    always_comb begin
        RGB = mono_colour;
        if(fake_colour && ypos < fake_end) begin
            case(fake_colour_mode)
                2'b00: RGB = mono_colour;
                2'b01: begin    // CGA Palette 0 Low
                    case(colour[3:2])
                        2'b00: RGB =  24'h000000;   // Black
                        2'b01: RGB =  24'h00aaaa;   // Cyan
                        2'b10: RGB =  24'haa00aa;   // Magenta
                        2'b11: RGB =  24'haaaaaa;   // White
                    endcase                    
                end
                2'b10: begin    // EGA PALETTE
                    case(colour)
                        4'b0000: RGB =  24'h000000;   // Black
                        4'b0001: RGB =  24'h0000aa;   // Blue
                        4'b0010: RGB =  24'h00aa00;   // Green
                        4'b0011: RGB =  24'h00aaaa;   // Cyan
                        4'b0100: RGB =  24'haa0000;   // Red
                        4'b0101: RGB =  24'haa00aa;   // Magenta
                        4'b0110: RGB =  24'haa5500;   // Yellow Brown
                        4'b0111: RGB =  24'haaaaaa;   // White / gray
                        4'b1000: RGB =  24'h555555;   // dark gray
                        4'b1001: RGB =  24'h5555ff;   // Light blue
                        4'b1010: RGB =  24'h55ff55;   // Light green
                        4'b1011: RGB =  24'h55ffff;   // light cyan
                        4'b1100: RGB =  24'hff5555;   // light red
                        4'b1101: RGB =  24'hff55ff;   // Light magenta
                        4'b1110: RGB =  24'hffff55;   // Light yellow
                        4'b1111: RGB =  24'hffffff;   // bright white
                    endcase                    
                end
			endcase
		end
    end

    logic [7:0] daisy_dout;
    // Fake daisywheel printer interface
    fake_daisy daisy(
        .reset(reset),
        .clk_sys(clk_sys),
        .ce(cpu_ce_g_p),
        .sel(daisy_sel),
        .address({cpua[8],cpua[0]}),
        .wr(~iow),
        .din(cpudo),
        .dout(daisy_dout)
    );

    // Mouse emulation
    logic mouse_left, mouse_middle, mouse_right;
    logic signed [8:0] mouse_x, mouse_y;
    mouse mouse(
        .*
    );

    // AMX mouse driver
    logic [7:0] amx_dout;
    wire amx_sel = ~ior && (cpua[7:2]==6'b101000 || cpua[7:2]==6'b100000) && mouse_type==MOUSE_AMX;
    amx_mouse amx_mouse(
        .sel(amx_sel),
        .addr(cpua[1:0]),
        .dout(amx_dout),
        .*
    );

//    // Kempston mouse driver
    logic [7:0] kempston_dout;
    wire kempston_sel = ~ior && (cpua[7:0] ==? 8'b110100?? || cpua[7:0]==8'hd4) && mouse_type==MOUSE_KEMPSTON;
    kempston_mouse kempston_mouse(
        .sel(kempston_sel),
        .addr(cpua[2:0]),
        .dout(kempston_dout),
        .input_pulse(ps2_mouse[24]),
        .*
    );

    // Keyboard / Joystick controller
    logic line_up, line_down;   // line up and down signals for moving fake colour
    logic toggle_full;          // Toggle full screen colour on / off
    logic [7:0] kbd_data;
    key_joystick keyjoy(
        .reset(reset),
        .clk_sys(clk_sys),
        .ps2_key(ps2_key),
        .joy0(joy0),
        .joy1(joy1),
        .lk1(1'b0),
        .lk2(1'b0),
        .lk3(1'b0),
        .addr(cpua[3:0]),
        .key_data(kbd_data),
        .keymouse(mouse_type==MOUSE_KEYMOUSE),
        .mouse_pulse(ps2_mouse[24]),
        .line_up(line_up),
        .line_down(line_down),
        .toggle_full(toggle_full),
        .*          // Mouse inputs
    ); 

    // DKtronics sound and joystick interface
    // {3'b0,joy0[4:0]} : 8'hff; // Fire,Up,Down,Left,Right
    logic [7:0] dkjoy_io;
    assign dkjoy_io = {1'b1,~joy0[4],~joy0[3],~joy0[2],~joy0[0],~joy0[1],2'b11};

    logic dk_busdir, dk_bc;
    always_comb
    begin
        if(~ior & cpua[7:0]==8'ha9) {dk_busdir,dk_bc} <= 2'b01;         // Port A9 - Read Register
        else if(~iow & cpua[7:0]==8'haa) {dk_busdir,dk_bc} <= 2'b11;    // Port AA - Write Address
        else if(~iow & cpua[7:0]==8'hab) {dk_busdir,dk_bc} <= 2'b10;    // Port AB - Write Register
        else {dk_busdir,dk_bc} <= 2'b00;
    end 

    logic [7:0] dk_out;
    wire [7:0] dac_out;

    psg soundchip(
        .clock(snd_ce),       
        .sel(1'b0),            
        .ce(dktronics),
        .reset(~reset),         
        .bdir(dk_busdir),      
        .bc1(dk_bc),           
        .d(cpudo),             
        .q(dk_out),            
        .a(ch_a),              
        .b(ch_b),              
        .c(ch_c),              
        .ioad(dkjoy_io),
        .iobd(8'b1),
        .iobq(dac_out)
);
    // Bleeper audio
    bleeper bleeper(
        .clk_sys(clk_sys),
        .ce(speaker_enable),
        .speaker(speaker_out)
    );

    logic [11:0] speaker = 'b0;
    logic speaker_out;
    assign speaker = {speaker_out, 11'b0};
    assign audio = {2'b00, ch_a} + {2'b00, ch_b} + {2'b00, ch_c} + {2'b00, speaker} + {1'b0, dac_out, 4'd0};
    assign audiomix = audio;


    // Floppy disk controller logic and control
    wire fdc_sel = ~cpua[7];
    
    //wire [7:0] u765_dout;
    wire [7:0] fdc_dout;// = (fdc_sel & ~ior) ? u765_dout : 8'hFF;

    reg  [1:0] u765_ready /* synthesis keep */ = {1'b0, 1'b0};
    always @(posedge clk_sys) if(img_mounted[0]) u765_ready[0] <= |img_size;
    always @(posedge clk_sys) if(img_mounted[1]) u765_ready[1] <= |img_size;
    
    assign LED[1] = u765_ready[0];
    assign LED[2] = u765_ready[1];
    assign LED[3] = fdc_int;
    assign LED[4] = nmi_line;
    assign LED[5] = int_line;
    assign LED[6] = timer_line;
    assign LED[7] = vid_timer;
    wire fdcreadreq /* synthesis keep */= ~fdc_sel | ior;
    wire fdcwritereq /* synthesis keep */= ~fdc_sel | iow;
    assign AUX[0] = fdc_int;
    assign AUX[1] = cpuiorq;
    assign AUX[2] = cpurd;
    assign AUX[3] = cpuwr;
    assign AUX[4] = WAIT_n;
    assign AUX[5] = int_sig;
    assign AUX[6] = fdc_int_latch;
    assign AUX[7] = nmi_sig;
    
    logic fdc_int /* synthesis keep */;
    
    u765 u765
    (
        .reset(reset),
        .clk_sys(clk_sys),
        .ce(disk_ce),
        .a0(cpua[0]),
        .ready(u765_ready),
        .motor({motor,motor}),
        .available(2'b11),
        .nRD(fdcreadreq), 
        .nWR(fdcwritereq),
        .din(cpudo),
        .dout(fdc_dout),
        .int_out(fdc_int),
        .tc(tc),
        .density(density),
        .activity_led(LED[0]),

        .img_mounted(img_mounted),
        .img_size(img_size[31:0]),
        .img_wp(img_readonly),
        .sd_lba(sd_lba),
        .sd_rd(sd_rd),
        .sd_wr(sd_wr),
        .sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr),
        .sd_buff_dout(sd_buff_dout),
        .sd_buff_din(sd_buff_din),
        .sd_buff_wr(sd_dout_strobe)
    );

endmodule

