`include "mycpu.h"

module id_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          es_allowin    ,
    output                         ds_allowin    ,
    //from fs
    input                          fs_to_ds_valid,
    input  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus  ,
    //from es raw
    input  [`ES_TO_DS_BUS_WD -1:0] es_to_ds_bus,
    //from ms raw
    input  [`MS_TO_DS_BUS_WD -1:0] ms_to_ds_bus,
    //to es
    output                         ds_to_es_valid,
    output [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to fs
    output [`BR_BUS_WD       -1:0] br_bus        ,
    //to rf: for write back
    input  [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus
);

reg         ds_valid   ;
wire        ds_ready_go;

wire [31                 :0] fs_pc;
reg  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus_r;
assign fs_pc = fs_to_ds_bus[31:0];

wire [31:0] ds_inst;
wire [31:0] ds_pc  ;
assign {ds_inst,
        ds_pc  } = fs_to_ds_bus_r;

wire        rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;
assign {rf_we   ,  //37:37
        rf_waddr,  //36:32
        rf_wdata   //31:0
       } = ws_to_rf_bus;

wire es_res_valid;
assign es_res_valid = es_to_ds_bus[37];

wire [ 4:0] es_dest;
wire [ 4:0] ms_dest;
wire [ 4:0] ws_dest;
wire [31:0] es_res;
wire [31:0] ms_res;
assign es_dest = es_to_ds_bus[36:32]  ;
assign ms_dest = ms_to_ds_bus[36:32]  ;
assign ws_dest = rf_waddr & {5{rf_we}};
assign es_res  = es_to_ds_bus[31:0];
assign ms_res  = ms_to_ds_bus[31:0];

wire        br_stall;
wire        br_taken;
wire [31:0] br_target;

wire [11:0] alu_op;
//!wire        load_op;
wire        src1_is_sa;
wire        src1_is_pc;
wire        src2_is_imm;
wire        src2_is_8;
wire        mem_re;
wire        gr_we;
wire        mem_we;
wire [ 4:0] dest;
wire [15:0] imm;
wire [31:0] rs_value;
wire [31:0] rt_value;

wire [ 5:0] op;
wire [ 4:0] rs;
wire [ 4:0] rt;
wire [ 4:0] rd;
wire [ 4:0] sa;
wire [ 5:0] func;
wire [25:0] jidx;
wire [63:0] op_d;
wire [31:0] rs_d;
wire [31:0] rt_d;
wire [31:0] rd_d;
wire [31:0] sa_d;
wire [63:0] func_d;

// INST DECODING
// logical
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_nor;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
// arithmetical
wire        inst_addu;
wire        inst_addiu;
wire        inst_add;
wire        inst_addi;
wire        inst_subu;
wire        inst_sub;
wire        inst_sll;
wire        inst_srl;
wire        inst_sra;
wire        inst_sllv;
wire        inst_srav;
wire        inst_srlv;
wire        inst_slt;
wire        inst_sltu;
wire        inst_slti;
wire        inst_sltiu;
// mult/div
wire        inst_mult;
wire        inst_multu;
wire        inst_div;
wire        inst_divu;
// data move with hilo
wire        inst_mfhi;
wire        inst_mflo;
wire        inst_mthi;
wire        inst_mtlo;
// general
wire        inst_lui;
// load
wire        inst_lw;
// store
wire        inst_sw;
// branch
wire        inst_beq;
wire        inst_bne;
// jump
wire        inst_jal;
wire        inst_jr;

// lab7 newly added:
wire        inst_bgez;
wire        inst_bgtz;
wire        inst_blez;
wire        inst_bltz;
wire        inst_bltzal;
wire        inst_bgezal;
wire        inst_j;
wire        inst_jalr;
wire        inst_lb;
wire        inst_lbu;
wire        inst_lh;
wire        inst_lhu;
wire        inst_lwl;
wire        inst_lwr;
wire        inst_sb;
wire        inst_sh;
wire        inst_swl;
wire        inst_swr;

wire        dst_is_r31;
wire        dst_is_rt;

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;

wire        rs_eq_rt;
// lab7 newly added:
wire        rs_be_0;
wire        rs_bt_0;
wire        rs_se_0;
wire        rs_st_0;

// lab7 newly added:
//!wire [ 2:0] load_type;
//!wire [ 2:0] store_type;
wire [ 5:0] ls_type;
wire [ 1:0] ls_laddr; // lowest 2 bits in address

assign br_bus       = {br_stall, br_taken, br_target};
assign ds_to_es_bus = {ls_type    ,  //151:146  lab7 modified
                       ls_laddr   ,  //145:144
                       inst_mtlo  ,  //143     | op
                       inst_mthi  ,  //142
                       inst_mflo  ,  //141
                       inst_mfhi  ,  //140
                       inst_divu  ,  //139
                       inst_div   ,  //138
                       inst_multu ,  //137
                       inst_mult  ,  //136
                       alu_op     ,  //135:124
                       mem_re     ,  //123:123
                       src1_is_sa ,  //122:122  | src
                       src1_is_pc ,  //121:121
                       src2_is_imm,  //120:120
                       src2_is_8  ,  //119:119
                       gr_we      ,  //118:118  | we
                       mem_we     ,  //117:117
                       dest       ,  //116:112  | val
                       imm        ,  //111:96
                       rs_value   ,  //95 :64
                       rt_value   ,  //63 :32
                       ds_pc         //31 :0
                      };

// lab7 newly added: load/store type
assign ls_type = {inst_lhu | inst_lbu ,          // [5] unsigned extension
                  inst_lwr | inst_swr ,          // [4] l/s word right
                  inst_lwl | inst_swl ,          // [3] l/s word left
                  inst_lh  | inst_lhu | inst_sh, // [2] l/s halfword
                  inst_lb  | inst_lbu | inst_sb, // [1] l/s byte
                  inst_lw  | inst_sw             // [0] l/s word
                  };

/*---Need block? begin---*/
// if reg/dest == 0 ?
wire rs_neq_0;
wire rt_neq_0;
wire es_dest_neq_0;
wire ms_dest_neq_0;
wire ws_dest_neq_0;
// if(|a=0) neq=0
assign rs_neq_0 = |rs;
assign rt_neq_0 = |rt;
assign es_dest_neq_0 = |es_dest;
assign ms_dest_neq_0 = |ms_dest;
assign ws_dest_neq_0 = |ws_dest;

// if a_rx == b_dest ?
wire rs_eq_es_dest;
wire rt_eq_es_dest;
wire rs_eq_ms_dest;
wire rt_eq_ms_dest;
wire rs_eq_ws_dest;
wire rt_eq_ws_dest;
wire st_eq_es_dest; //st(@es)
// if(ab!=0 && a==b) eq=1
assign rs_eq_es_dest = (rs_neq_0 & es_dest_neq_0) && (rs == es_dest); // rs
assign rs_eq_ms_dest = (rs_neq_0 & ms_dest_neq_0) && (rs == ms_dest);
assign rs_eq_ws_dest = (rs_neq_0 & ws_dest_neq_0) && (rs == ws_dest);
assign rt_eq_es_dest = (rt_neq_0 & es_dest_neq_0) && (rt == es_dest); // rt
assign rt_eq_ms_dest = (rt_neq_0 & ms_dest_neq_0) && (rt == ms_dest);
assign rt_eq_ws_dest = (rt_neq_0 & ws_dest_neq_0) && (rt == ws_dest);
assign st_eq_es_dest = rs_eq_es_dest | rt_eq_es_dest;                 // st(@es)

// Type define for block situation
// if current type (i.e. at decode stage) has any src from reg
wire type_st;
wire type_rs;
wire type_rt;
wire type_nr;
                            // src from rs & rt
assign type_st = inst_addu  // (op)[rs, rt] -> rd
               | inst_add   // ...
               | inst_subu  // ...
               | inst_sub   // ...
               | inst_and   // ...
               | inst_nor   // ...
               | inst_or    // ...
               | inst_xor   // ...
               | inst_slt   // ...
               | inst_sltu  // ...
               | inst_sllv  // ...
               | inst_srav  // ...
               | inst_srlv  // ...
               | inst_beq   // (op)[rs, rt] -> br_taken
               | inst_bne   // ...
               | inst_mult  // (op)[rs, rt] -> HI, LO
               | inst_multu // ...
               | inst_div   // ...
               | inst_divu;
                            // src from rs
assign type_rs = inst_addiu // (op)[rs] -> rt
               | inst_addi  // ...
               | inst_slti  // ...
               | inst_sltiu // ...
               | inst_andi  // ...
               | inst_ori   // ...
               | inst_xori  // ...
               | inst_lw    // ...
               | inst_jr    // j [rs]
               | inst_mthi  // mov [rs] -> HI, LO
               | inst_mtlo; // ...
                            // src from rt
assign type_rt = inst_sw    // (op)[rt] -> mem
               | inst_sll   // (op)[rt] -> rd
               | inst_sra   // ...
               | inst_srl;  // ...
                            // No src from reg
assign type_nr = inst_lui   // (op)imm -> rt
               | inst_jal   // (op)PC+8 -> GPR[31]
               | inst_mfhi  // (op)()->rd
               | inst_mflo; // (op)()->rd

// if rx == dests?
wire rs_eq_dests;
wire rt_eq_dests;
wire st_eq_dests;
// rs+rt=st
assign rs_eq_dests = rs_eq_es_dest | rs_eq_ms_dest | rs_eq_ws_dest;
assign rt_eq_dests = rt_eq_es_dest | rt_eq_ms_dest | rt_eq_ws_dest;
assign st_eq_dests = rs_eq_dests   | rt_eq_dests   ;

// signal generate in ds_ready_go
// With Bypass Tech: only block when src_reg crash with a load inst(@es)
assign ds_ready_go = es_res_valid
                   | ~( rs_eq_es_dest & type_rs
                      | rt_eq_es_dest & type_rt
                      | st_eq_es_dest & type_st
                      );
// Without Bypass Tech
/*
assign ds_ready_go    =  type_st & ~st_eq_dests
                      || type_rs & ~rs_eq_dests
                      || type_rt & ~rt_eq_dests
                      || type_nr ;
*/
/*---Need block? end---*/

assign ds_allowin     = !ds_valid || ds_ready_go && es_allowin;
assign ds_to_es_valid =  ds_valid && ds_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ds_valid <= 1'b0;
    end
    else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid;
    end
    if (fs_to_ds_valid && ds_allowin) begin
        fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end

assign op   = ds_inst[31:26];
assign rs   = ds_inst[25:21];
assign rt   = ds_inst[20:16];
assign rd   = ds_inst[15:11];
assign sa   = ds_inst[10: 6];
assign func = ds_inst[ 5: 0];
assign imm  = ds_inst[15: 0];
assign jidx = ds_inst[25: 0];

decoder_6_64 u_dec0(.in(op  ), .out(op_d  ));
decoder_6_64 u_dec1(.in(func), .out(func_d));
decoder_5_32 u_dec2(.in(rs  ), .out(rs_d  ));
decoder_5_32 u_dec3(.in(rt  ), .out(rt_d  ));
decoder_5_32 u_dec4(.in(rd  ), .out(rd_d  ));
decoder_5_32 u_dec5(.in(sa  ), .out(sa_d  ));

assign inst_addu   = op_d[6'h00] & func_d[6'h21] & sa_d[5'h00];
assign inst_subu   = op_d[6'h00] & func_d[6'h23] & sa_d[5'h00];
assign inst_slt    = op_d[6'h00] & func_d[6'h2a] & sa_d[5'h00];
assign inst_sltu   = op_d[6'h00] & func_d[6'h2b] & sa_d[5'h00];
assign inst_and    = op_d[6'h00] & func_d[6'h24] & sa_d[5'h00];
assign inst_or     = op_d[6'h00] & func_d[6'h25] & sa_d[5'h00];
assign inst_xor    = op_d[6'h00] & func_d[6'h26] & sa_d[5'h00];
assign inst_nor    = op_d[6'h00] & func_d[6'h27] & sa_d[5'h00];
assign inst_sll    = op_d[6'h00] & func_d[6'h00] & rs_d[5'h00];
assign inst_srl    = op_d[6'h00] & func_d[6'h02] & rs_d[5'h00];
assign inst_sra    = op_d[6'h00] & func_d[6'h03] & rs_d[5'h00];
assign inst_addiu  = op_d[6'h09];
assign inst_lui    = op_d[6'h0f] & rs_d[5'h00];
assign inst_lw     = op_d[6'h23];
assign inst_sw     = op_d[6'h2b];
assign inst_beq    = op_d[6'h04];
assign inst_bne    = op_d[6'h05];
assign inst_jal    = op_d[6'h03];
assign inst_jr     = op_d[6'h00] & func_d[6'h08] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00];
assign inst_add    = op_d[6'h00] & func_d[6'h20] & sa_d[5'h00];
assign inst_addi   = op_d[6'h08];
assign inst_sub    = op_d[6'h00] & func_d[6'h22] & sa_d[5'h00];
assign inst_slti   = op_d[6'h0a];
assign inst_sltiu  = op_d[6'h0b];
assign inst_andi   = op_d[6'h0c];
assign inst_ori    = op_d[6'h0d];
assign inst_xori   = op_d[6'h0e];
assign inst_sllv   = op_d[6'h00] & func_d[6'h04] & sa_d[5'h00];
assign inst_srav   = op_d[6'h00] & func_d[6'h07] & sa_d[5'h00];
assign inst_srlv   = op_d[6'h00] & func_d[6'h06] & sa_d[5'h00];
assign inst_mult   = op_d[6'h00] & func_d[6'h18] & sa_d[5'h00];
assign inst_multu  = op_d[6'h00] & func_d[6'h19] & sa_d[5'h00];
assign inst_div    = op_d[6'h00] & func_d[6'h1a] & sa_d[5'h00];
assign inst_divu   = op_d[6'h00] & func_d[6'h1b] & sa_d[5'h00];
assign inst_mfhi   = op_d[6'h00] & func_d[6'h10] & sa_d[5'h00];
assign inst_mflo   = op_d[6'h00] & func_d[6'h12] & sa_d[5'h00];
assign inst_mthi   = op_d[6'h00] & func_d[6'h11] & sa_d[5'h00];
assign inst_mtlo   = op_d[6'h00] & func_d[6'h13] & sa_d[5'h00];
// lab7 newly added:
assign inst_bgez   = op_d[6'h01] & rt_d[5'h01];
assign inst_bgtz   = op_d[6'h07] & rt_d[5'h00];
assign inst_blez   = op_d[6'h06] & rt_d[5'h00];
assign inst_bltz   = op_d[6'h01] & rt_d[5'h00];
assign inst_bltzal = op_d[6'h01] & rt_d[5'h10];
assign inst_bgezal = op_d[6'h01] & rt_d[5'h11];
assign inst_j      = op_d[6'h02];
assign inst_jalr   = op_d[6'h00] & func_d[6'h09] & rt_d[5'h00] & sa_d[5'h00];
assign inst_lb     = op_d[6'h20];
assign inst_lbu    = op_d[6'h24];
assign inst_lh     = op_d[6'h21];
assign inst_lhu    = op_d[6'h25];
assign inst_lwl    = op_d[6'h22];
assign inst_lwr    = op_d[6'h26];
assign inst_sb     = op_d[6'h28];
assign inst_sh     = op_d[6'h29];
assign inst_swl    = op_d[6'h2a];
assign inst_swr    = op_d[6'h2e];

assign alu_op[ 0] = |{inst_addu, inst_addiu, inst_add, inst_addi,
                      inst_lw, inst_lwl, inst_lwr,                // lab7 newly added:
                      inst_lb, inst_lbu, inst_lh, inst_lhu,
                      inst_sw, inst_sb, inst_sh, inst_swl, inst_swr,
                      inst_bgezal, inst_bltzal,
                      inst_jal, inst_jalr}; // ADD
assign alu_op[ 1] = inst_subu | inst_sub  ; // SUB
assign alu_op[ 2] = inst_slt  | inst_slti ; // SLT : Set on Less Than
assign alu_op[ 3] = inst_sltu | inst_sltiu; // SLTU: Set on Less Than Unsigned
assign alu_op[ 4] = inst_and  | inst_andi ; // AND
assign alu_op[ 5] = inst_nor  ;             // NOR
assign alu_op[ 6] = inst_or   | inst_ori  ; // OR
assign alu_op[ 7] = inst_xor  | inst_xori ; // XOR
assign alu_op[ 8] = inst_sll  | inst_sllv ; // SLL : Shift Word Left  Logical
assign alu_op[ 9] = inst_srl  | inst_srlv ; // SRL : Shift Word Right Logical
assign alu_op[10] = inst_sra  | inst_srav ; // SRA : Shift Word Right Arithmetical
assign alu_op[11] = inst_lui  ;             // LUI : Load Upper Immediate

assign ls_laddr = {2{mem_re | mem_we}} & func[1:0];

assign src1_is_sa  = inst_sll
                   | inst_srl
                   | inst_sra;
assign src1_is_pc  = inst_jal
                   | inst_bltzal
                   | inst_bgezal
                   | inst_jalr;
assign src2_is_imm = |{inst_addiu, inst_lui, inst_lw, inst_sw,
                       inst_addi, inst_slti, inst_sltiu,
                       inst_andi, inst_xori, inst_ori,  // note: uimm as imm
                       inst_lb  , inst_lbu , inst_lh , inst_lhu,
                       inst_sb  , inst_sh  ,
                       inst_swl , inst_swr , inst_lwl, inst_lwr// lab7 newly added
                      };
assign src2_is_8   = inst_jal
                   | inst_bltzal // lab7 newly added
                   | inst_bgezal
                   | inst_jalr;
assign dst_is_r31  = inst_jal    // lab7 newly added
                   | inst_bltzal
                   | inst_bgezal ;
assign dst_is_rt   = |{inst_addiu, inst_addi, inst_slti, inst_sltiu,
                       inst_andi, inst_ori, inst_xori,
                       inst_lui,
                       inst_lw,
                       inst_lb, inst_lbu, inst_lh, inst_lhu,// lab7 newly added
                       inst_lwl, inst_lwr // lab7 newly added
                      };
assign gr_we       = ~|{inst_sw, inst_sb, inst_sh, inst_swl, inst_swr,
                        inst_beq, inst_bne, inst_bgez, inst_bgtz, inst_blez, inst_bltz,
                        inst_jr, inst_j,// newly added
                        inst_mult, inst_multu,
                        inst_div, inst_divu,
                        inst_mthi, inst_mtlo
                       };

assign mem_re = inst_lw
              | inst_lb     // lab7 newly added
              | inst_lbu
              | inst_lh
              | inst_lhu
              | inst_lwl
              | inst_lwr;
assign mem_we = inst_sw
              | inst_sb     // lab7 newly added
              | inst_sh
              | inst_swl
              | inst_swr;
assign dest   = dst_is_r31 ? 5'd31 :
                dst_is_rt  ? rt    :
                             rd    ;

assign rf_raddr1 = rs;
assign rf_raddr2 = rt;
regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );

// Fowarding(Bypass)
assign rs_value = rs_eq_es_dest ? es_res   :
                  rs_eq_ms_dest ? ms_res   :
                  rs_eq_ws_dest ? rf_wdata :
                                  rf_rdata1;
assign rt_value = rt_eq_es_dest ? es_res   :
                  rt_eq_ms_dest ? ms_res   :
                  rt_eq_ws_dest ? rf_wdata :
                                  rf_rdata2;

assign rs_eq_rt = (rs_value == rt_value);
// lab7 newly added: >=0, >0, <=0, <0
assign rs_be_0 = ~rs_value[31] ;
assign rs_bt_0 = ~rs_value[31] & ( |rs_value);
assign rs_se_0 =  rs_value[31] | (~|rs_value);
assign rs_st_0 =  rs_value[31] ;

// br info
assign br_stall = 1'b0; //(inst_beq || inst_bne ) & st_eq_dests;
// lab7 modified
assign br_taken = ( inst_beq    &  rs_eq_rt  // lab7 modified
                  | inst_bne    & ~rs_eq_rt
                  | inst_bgez   &  rs_be_0
                  | inst_bgtz   &  rs_bt_0
                  | inst_blez   &  rs_se_0
                  | inst_bltz   &  rs_st_0
                  | inst_bltzal &  rs_st_0
                  | inst_bgezal &  rs_be_0
                  | inst_jal
                  | inst_jalr
                  | inst_j
                  | inst_jr
                  ) && ds_valid;
assign br_target = ( inst_beq
                   | inst_bne
                   | inst_bgez
                   | inst_bgtz
                   | inst_blez
                   | inst_bltz
                   | inst_bltzal
                   | inst_bgezal) ? (fs_pc + {{14{imm[15]}}, imm[15:0], 2'b0}) :
                    (inst_jr
                   | inst_jalr)   ?  rs_value :
                     /*jal/j*/      {fs_pc[31:28], jidx[25:0], 2'b0};

endmodule
