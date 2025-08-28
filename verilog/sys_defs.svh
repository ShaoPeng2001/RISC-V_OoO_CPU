/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  sys_defs.svh                                        //
//                                                                     //
//  Description :  This file defines macros and data structures used   //
//                 throughout the processor.                           //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __SYS_DEFS_SVH__
`define __SYS_DEFS_SVH__

// all files should `include "sys_defs.svh" to at least define the timescale
`timescale 1ns/100ps

///////////////////////////////////
// ---- Starting Parameters ---- //
///////////////////////////////////

// some starting parameters that you should set
// this is *your* processor, you decide these values (try analyzing which is best!)

`define N 2
`define CDB_SZ `N

// sizes
`define ROB_SZ xx
`define RS_SZ xx
`define PHYS_REG_SZ_P6 32
`define PHYS_REG_SZ_R10K (32 + `ROB_SZ)

// worry about these later
`define BRANCH_PRED_SZ xx
`define LSQ_SZ xx

// functional units (you should decide if you want more or fewer types of FUs)
`define NUM_FU_ALU xx
`define NUM_FU_MULT xx
`define NUM_FU_LOAD xx
`define NUM_FU_STORE xx

// number of mult stages (2, 4) (you likely don't need 8)
`define MULT_STAGES 4

// own definition
`define REGS        32
`define REG_LEN     64
`define PRF         64
`define ROB         16
`define RS          8

`define OLEN        16
`define PCLEN       32
`define WAYS        2
`define LOGPRF      6
`define LSQSZ       8

///////////////////////////////
// ---- Basic Constants ---- //
///////////////////////////////

// NOTE: the global CLOCK_PERIOD is defined in the Makefile

// useful boolean single-bit definitions
`define FALSE 1'h0
`define TRUE  1'h1

// word and register sizes
typedef logic [31:0] ADDR;
typedef logic [31:0] DATA;
typedef logic [4:0] REG_IDX;

// the zero register
// In RISC-V, any read of this register returns zero and any writes are thrown away
`define ZERO_REG 5'd0

// Basic NOP instruction. Allows pipline registers to clearly be reset with
// an instruction that does nothing instead of Zero which is really an ADDI x0, x0, 0
`define NOP 32'h00000013

//////////////////////////////////
// ---- Memory Definitions ---- //
//////////////////////////////////

// Cache mode removes the byte-level interface from memory, so it always returns
// a double word. The original processor won't work with this defined. Your new
// processor will have to account for this effect on mem.
// Notably, you can no longer write data without first reading.
// TODO: uncomment this line once you've implemented your cache
//`define CACHE_MODE

// you are not allowed to change this definition for your final processor
// the project 3 processor has a massive boost in performance just from having no mem latency
// see if you can beat it's CPI in project 4 even with a 100ns latency!
//`define MEM_LATENCY_IN_CYCLES  0
`define MEM_LATENCY_IN_CYCLES (100.0/`CLOCK_PERIOD+0.49999)
// the 0.49999 is to force ceiling(100/period). The default behavior for
// float to integer conversion is rounding to nearest

// memory tags represent a unique id for outstanding mem transactions
// 0 is a sentinel value and is not a valid tag
`define NUM_MEM_TAGS 15
typedef logic [3:0] MEM_TAG;

// icache definitions
`define ICACHE_LINES 32
`define ICACHE_LINE_BITS $clog2(`ICACHE_LINES)

`define MEM_SIZE_IN_BYTES (64*1024)
`define MEM_64BIT_LINES   (`MEM_SIZE_IN_BYTES/8)

// A memory or cache block
typedef union packed {
    logic [7:0][7:0]  byte_level;
    logic [3:0][15:0] half_level;
    logic [1:0][31:0] word_level;
    logic      [63:0] dbbl_level;
} MEM_BLOCK;

typedef enum logic [1:0] {
    BYTE   = 2'h0,
    HALF   = 2'h1,
    WORD   = 2'h2,
    DOUBLE = 2'h3
} MEM_SIZE;

// Memory bus commands
typedef enum logic [1:0] {
    MEM_NONE   = 2'h0,
    MEM_LOAD   = 2'h1,
    MEM_STORE  = 2'h2
} MEM_COMMAND;

// icache tag struct
typedef struct packed {
    logic [12-`ICACHE_LINE_BITS:0] tags;
    logic                          valid;
} ICACHE_TAG;

///////////////////////////////
// ---- Exception Codes ---- //
///////////////////////////////

/**
 * Exception codes for when something goes wrong in the processor.
 * Note that we use HALTED_ON_WFI to signify the end of computation.
 * It's original meaning is to 'Wait For an Interrupt', but we generally
 * ignore interrupts in 470
 *
 * This mostly follows the RISC-V Privileged spec
 * except a few add-ons for our infrastructure
 * The majority of them won't be used, but it's good to know what they are
 */

typedef enum logic [3:0] {
    INST_ADDR_MISALIGN  = 4'h0,
    INST_ACCESS_FAULT   = 4'h1,
    ILLEGAL_INST        = 4'h2,
    BREAKPOINT          = 4'h3,
    LOAD_ADDR_MISALIGN  = 4'h4,
    LOAD_ACCESS_FAULT   = 4'h5,
    STORE_ADDR_MISALIGN = 4'h6,
    STORE_ACCESS_FAULT  = 4'h7,
    ECALL_U_MODE        = 4'h8,
    ECALL_S_MODE        = 4'h9,
    NO_ERROR            = 4'ha, // a reserved code that we use to signal no errors
    ECALL_M_MODE        = 4'hb,
    INST_PAGE_FAULT     = 4'hc,
    LOAD_PAGE_FAULT     = 4'hd,
    HALTED_ON_WFI       = 4'he, // 'Wait For Interrupt'. In 470, signifies the end of computation
    STORE_PAGE_FAULT    = 4'hf
} EXCEPTION_CODE;

///////////////////////////////////
// ---- Instruction Typedef ---- //
///////////////////////////////////

// from the RISC-V ISA spec
typedef union packed {
    logic [31:0] inst;
    struct packed {
        logic [6:0] funct7;
        logic [4:0] rs2; // source register 2
        logic [4:0] rs1; // source register 1
        logic [2:0] funct3;
        logic [4:0] rd; // destination register
        logic [6:0] opcode;
    } r; // register-to-register instructions
    struct packed {
        logic [11:0] imm; // immediate value for calculating address
        logic [4:0]  rs1; // source register 1 (used as address base)
        logic [2:0]  funct3;
        logic [4:0]  rd;  // destination register
        logic [6:0]  opcode;
    } i; // immediate or load instructions
    struct packed {
        logic [6:0] off; // offset[11:5] for calculating address
        logic [4:0] rs2; // source register 2
        logic [4:0] rs1; // source register 1 (used as address base)
        logic [2:0] funct3;
        logic [4:0] set; // offset[4:0] for calculating address
        logic [6:0] opcode;
    } s; // store instructions
    struct packed {
        logic       of;  // offset[12]
        logic [5:0] s;   // offset[10:5]
        logic [4:0] rs2; // source register 2
        logic [4:0] rs1; // source register 1
        logic [2:0] funct3;
        logic [3:0] et;  // offset[4:1]
        logic       f;   // offset[11]
        logic [6:0] opcode;
    } b; // branch instructions
    struct packed {
        logic [19:0] imm; // immediate value
        logic [4:0]  rd; // destination register
        logic [6:0]  opcode;
    } u; // upper-immediate instructions
    struct packed {
        logic       of; // offset[20]
        logic [9:0] et; // offset[10:1]
        logic       s;  // offset[11]
        logic [7:0] f;  // offset[19:12]
        logic [4:0] rd; // destination register
        logic [6:0] opcode;
    } j;  // jump instructions

// extensions for other instruction types
`ifdef ATOMIC_EXT
    struct packed {
        logic [4:0] funct5;
        logic       aq;
        logic       rl;
        logic [4:0] rs2;
        logic [4:0] rs1;
        logic [2:0] funct3;
        logic [4:0] rd;
        logic [6:0] opcode;
    } a; // atomic instructions
`endif
`ifdef SYSTEM_EXT
    struct packed {
        logic [11:0] csr;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } sys; // system call instructions
`endif

} INST; // instruction typedef, this should cover all types of instructions

////////////////////////////////////////
// ---- Datapath Control Signals ---- //
////////////////////////////////////////

// ALU opA input mux selects
typedef enum logic [1:0] {
    OPA_IS_RS1  = 2'h0,
    OPA_IS_NPC  = 2'h1,
    OPA_IS_PC   = 2'h2,
    OPA_IS_ZERO = 2'h3
} ALU_OPA_SELECT;

// ALU opB input mux selects
typedef enum logic [3:0] {
    OPB_IS_RS2    = 4'h0,
    OPB_IS_I_IMM  = 4'h1,
    OPB_IS_S_IMM  = 4'h2,
    OPB_IS_B_IMM  = 4'h3,
    OPB_IS_U_IMM  = 4'h4,
    OPB_IS_J_IMM  = 4'h5
} ALU_OPB_SELECT;

//
// Destination register select
//
// ALU function code
typedef enum logic [4:0] {
    ALU_ADD     = 5'h00,
    ALU_SUB     = 5'h01,
    ALU_SLT     = 5'h02,
    ALU_SLTU    = 5'h03,
    ALU_AND     = 5'h04,
    ALU_OR      = 5'h05,
    ALU_XOR     = 5'h06,
    ALU_SLL     = 5'h07,
    ALU_SRL     = 5'h08,
    ALU_SRA     = 5'h09,
    ALU_MUL     = 5'h0a,
    ALU_MULH    = 5'h0b,
    ALU_MULHSU  = 5'h0c,
    ALU_MULHU   = 5'h0d,
    ALU_DIV     = 5'h0e,
    ALU_DIVU    = 5'h0f,
    ALU_REM     = 5'h10,
    ALU_REMU    = 5'h11    
} ALU_FUNC;

// MULT funct3 code
// we don't include division or rem options
typedef enum logic [2:0] {
    M_MUL,
    M_MULH,
    M_MULHSU,
    M_MULHU
} MULT_FUNC;

typedef enum logic[1:0] {WAIT_READY, WAIT_CACHE, WAIT_MEMORY_RESPONSE, WAIT_CDB} load_queue_status;

////////////////////////////////
// ---- Datapath Packets ---- //
////////////////////////////////

/**
 * Packets are used to move many variables between modules with
 * just one datatype, but can be cumbersome in some circumstances.
 *
 * Define new ones in project 4 at your own discretion
 */

/**
 * IF_ID Packet:
 * Data exchanged from the IF to the ID stage
 */
typedef struct packed {
    logic valid;
    INST  inst;
    logic [31:0] NPC;  // PC + 4
    logic [31:0] PC;   // PC 
} IF_ID_PACKET;

/**
 * ID_EX Packet:
 * Data exchanged from the ID to the EX stage
 */
typedef struct packed {
    logic [31:0] NPC;   // PC + 4
    logic [31:0] PC;    // PC

    logic [31:0] rs1_value;    // reg A value                                  
    logic [31:0] rs2_value;    // reg B value 
                                                                                    
    ALU_OPA_SELECT opa_select;
    ALU_OPB_SELECT opb_select; 
    INST inst;

    logic [$clog2(`PRF)-1:0]    dest_PRF_idx;
    logic [$clog2(`ROB)-1:0]    rob_idx;       
    logic [1:0]       	        mem_size;
    logic 					    reg_write;

    ALU_FUNC    alu_func;
    logic       rd_mem;
    logic       wr_mem;
    logic       cond_branch;
    logic       uncond_branch;
    logic       uncond_jal;
    logic       uncond_jalr;
    logic       halt;
    logic       illegal;
    logic       csr_op;
    logic       valid;
} ID_EX_PACKET;

/**
 * EX_MEM Packet:
 * Data exchanged from the EX to the MEM stage
 */
typedef struct packed {
	logic [31:0]   alu_result;
	logic [31:0]   NPC;
	logic               take_branch;

	logic [31:0]   rs2_value;
	logic               rd_mem;
	logic			    wr_mem;
	logic				reg_write;  
	logic [1:0]       	mem_size;

	logic [$clog2(`PRF)-1:0]       	dest_PRF_idx;
	logic [$clog2(`ROB)-1:0] 		rob_idx;       

	logic               halt, illegal, csr_op, valid;

} EX_MEM_PACKET;

/**
 * MEM_WB Packet:
 * Data exchanged from the MEM to the WB stage
 *
 * Does not include data sent from the MEM stage to memory
 */
typedef struct packed {
    DATA    result;
    ADDR    NPC;
    REG_IDX dest_reg_idx;
    logic   take_branch;
    logic   halt;
    logic   illegal;
    logic   valid;
} MEM_WB_PACKET;

/**
 * Commit Packet:
 * This is an output of the processor and used in the testbench for counting
 * committed instructions
 *
 * It also acts as a "WB_PACKET", and can be reused in the final project with
 * some slight changes
 */
typedef struct packed {
    logic [31:0]    NPC;
    logic [31:0]    data;
    REG_IDX reg_idx;
    logic   halt;
    logic   illegal;
    logic   valid;
} COMMIT_PACKET;

typedef struct packed {
    logic [1:0]                                 size;
    logic [31:0]                                data;
    logic                                       data_valid;
    logic [$clog2(`ROB)-1:0]                    ROB_idx;
    logic [15:0]                                addr;
    logic                                       addr_valid;
    logic                                       valid;
} sq_entry;

typedef struct packed {
    logic [$clog2(`PRF)-1:0]        rs1_index;
    logic [$clog2(`PRF)-1:0]        rs2_index;
    logic [$clog2(`PRF)-1:0]        dest_index;
    logic                           rename_request;

    logic [$clog2(`PRF)-1:0]        CDB_reg_idx;
    logic                           CDB_enable;

    logic [$clog2(`PRF)-1:0]        arch_reg_new;
    logic                           rob_retire_en;
    logic [$clog2(`PRF)-1:0]        arch_reg_old;
} valid_packet;

typedef struct packed {
    logic                           rob_retire_en;    
    logic                           rename_request;         // RAT 所需要的 freelist 個數
    logic [$clog2(`PRF)-1:0]        arch_idx_entering;      // From RRAT, these are entering RRAT      
    logic [$clog2(`PRF)-1:0]        arch_idx_leaving; 
    
} freelist_packet;

typedef struct packed {
    logic [4:0]                     rs1_idx;           // rename query 1, 查詢對應的 physical register 編號
    logic [4:0]                     rs2_idx;           // rename query 2，查詢對應的 physical register 編號
    logic [4:0]                     dest_idx;          // ARF # to be renamed	
	
    logic [4:0]                     ARF_idx;           // ARF # to be renamed, 需要在 RRAT 中更新的 ARF
    logic                           rob_retire; 	
    logic [$clog2(`PRF)-1:0]        PRF_idx;           // PRF # 

    logic [$clog2(`PRF)-1:0]        free_idx;          // from freelist, 從 freelist 當中拿 renaming 需要的 physical register
} renaming_packet;

typedef struct packed {
    logic [4:0]                        rs1_idx;            // rename query 1
    logic [4:0]                        rs2_idx;            // rename query 2
    logic [4:0]                        ARN_dest_idx;       // ARF # to be renamed

    logic [$clog2(`PRF)-1:0]           CDB_wr_reg_idx;     // From CDB, these are now valid
    logic                              CDB_wr_en;

    logic [4:0]                        ARF_reg_idx;        // ARF # to be renamed, from ROB
    logic                              rob_retire; 
    logic [$clog2(`PRF)-1:0]           PRN_idx_old;        // PRF # 
} map_arch_packet;

typedef struct packed {
    logic [$clog2(`ROB)-1:0]           CDB_ROB_idx;
    logic                              CDB_valid;
    logic                              CDB_direction;
    logic [31:0]                  CDB_target;

    logic [4:0]                        dest_ARN;
    logic [$clog2(`PRF)-1:0]           dest_PRN;
    logic                              reg_write;
    logic                              is_branch;
    logic                              is_store;
    logic                              valid;

    logic [31:0]                  PC;
    logic [31:0]                  target;
    logic                              branch_direction;

    logic                              illegal;
    logic                              halt;
} ROB_packet;

typedef struct packed{
    logic [$clog2(`REGS)-1:0]   dest_ARN;
    logic [$clog2(`PRF)-1:0]    dest_PRN;
    logic                       reg_write;
    logic                       is_branch;
    logic                       is_store;
    logic [31:0]           PC;
    logic [31:0]           target;
    logic                       branch_direction;
    logic                       mispredicted;
    logic                       complete;
    logic                       illegal;
    logic                       halt;
}rob_entry;

typedef struct packed {
    logic [4:0]                  dest_ARN_out;
    logic [$clog2(`PRF)-1:0]     dest_PRN_out;
    logic                        valid_out;

    logic [31:0]            PC_out; // cannot be output
    logic                        direction_out;
    logic                        is_branch_out; // for branch predictor

    logic                        retired;
    logic                        illegal_out;
    logic                        halt_out;
} ROB_out_packet;

typedef struct packed {
    logic [31:0]                   CDB_Data;
    logic [$clog2(`PRF)-1:0]            CDB_PRF_idx;
    logic                               CDB_valid;

    logic                               rs1_valid_in;
    logic                               rs2_valid_in;

    ID_EX_PACKET                        id_rs_packet_in;
} RS_packet;

typedef struct packed {
	logic [$clog2(`PRF)-1:0]            CDB_write_idx;
	logic                               CDB_write_en;
	logic [31:0]                   CDB_write_data;

	logic [4:0]                         ARCH_ARF_idx;
	logic 						        rob_retire;		
	logic [$clog2(`PRF)-1:0]		    ARCH_PRF_idx;

	IF_ID_PACKET  					    if_id_packet_in;

    logic [$clog2(`PRF)-1:0]  	        dest_PRN_out;
    logic                      	        retired;
} ID_packet;

typedef struct packed {
    ADDR                proc2Icache_addr;
    logic               proc2Icache_en;

    logic [63:0]        cachemem_data;
    logic               cachemem_valid;
} Icache_packet;

typedef struct packed {
    logic                       write_en;
    logic [2:0]                 write_offset;
    logic [4:0]                 write_idx;
    logic [7:0]                 write_tag;
    logic [63:0]                write_data; 
    logic [1:0]                 write_size;

    logic                       read_en;
    logic [2:0]                 read_offset;
    logic [4:0]                 read_idx;
    logic [7:0]                 read_tag;
    logic [1:0]                 read_size;
    logic [`LSQSZ-1:0]          read_gnt;    

    logic                       memory_en;
    logic [4:0]                 memory_idx;
    logic [7:0]                 memory_tag;
    logic [63:0]                memory_data; 

} dcache_packet;

typedef struct packed {
    logic [63:0]         read_data;
    logic [`LSQSZ-1:0]   read_response;

    logic                write_back_en;
    logic [15:0]         write_back_addr;
    logic [63:0]         write_back_data;
    logic [1:0]          write_back_size;

    logic                write_out_en;
    logic [15:0]         write_out_addr;
    logic [63:0]         write_out_data;
    logic [1:0]          write_out_size;

    logic                read_out_en;
    logic [15:0]         read_out_addr;
    logic [1:0]          read_out_size;
    logic [`LSQSZ-1:0]   read_out_gnt;

    logic [31:0] [63:0]  dcache_data;
    logic [31:0] [7:0]   dcache_tags;
    logic [31:0]         dcache_dirty_bit;
    logic [31:0]         dcache_valid_bit;

    logic [1:0] [12:0]   victim_tags;
    logic [1:0] [63:0]   victim_data;
    logic [1:0]          victim_valid_bit;
    logic [1:0]          victim_dirty_bit;    
} dcache_packet_out;

typedef struct packed {
    logic [1:0]                            store_size;
    logic [31:0]                           store_data;
    logic                                  store_data_valid;
    logic [$clog2(`ROB)-1:0]               store_ROB_idx;
    logic                                  store_enable;

    logic [$clog2(`ROB)-1:0]               ALU_ROB_idx;
    logic                                  ALU_is_valid;
    logic [15:0]                           ALU_data;

    logic [31:0]                           CDB_Data;
    logic [$clog2(`PRF)-1:0]               CDB_PRF_idx;
    logic                                  CDB_valid;

} sq_input_packet;

typedef struct packed {
    logic [31:0]                   store_data;
    logic                          store_data_valid;
    logic [15:0]                   store_addr;
    logic                          store_address_valid;
    logic [1:0]                    store_size;
    logic                          store_valid;
} lq_store_packet;

typedef struct packed {
    logic [1:0]                        dispatched_load_size;
    logic                              dispatched_load_enable;
    logic [$clog2(`ROB)-1:0]           dispatched_ROB_idx;
    logic [$clog2(`PRF)-1:0]           dispatched_PRF_idx;
    logic                              dispatched_load_sign;

    logic [$clog2(`ROB)-1:0]           ALU_ROB_idx;
    logic                              ALU_is_valid;
    logic                              ALU_for_address;
    logic [15:0]                       ALU_data;
} lq_dispatch_packet;

typedef struct packed {
  logic [31:0]              lq_data;
  logic [15:0]              lq_addr;
  logic [$clog2(`PRF)-1:0]  lq_PRF_idx;
  logic [$clog2(`ROB)-1:0]  lq_ROB_idx;
  logic                     lq_signed;
  logic [1:0]               lq_size;  
} lq_out_packet;

typedef struct packed {
    // CDB
    logic [31:0]                       CDB_Data;
  	logic [$clog2(`PRF)-1:0]           CDB_PRF_idx;
  	logic                              CDB_valid;

    // ALU
    logic [$clog2(`ROB)-1:0]           ALU_ROB_idx;
    logic                              ALU_is_valid;
    logic                              ALU_is_ls;      
    logic [15:0]                       ALU_data;

    // LQ
    logic [1:0]                        load_size_input;
    logic                              load_enable_input;
    logic [$clog2(`ROB)-1:0]           load_ROB_idx_input;
    logic [$clog2(`PRF)-1:0]           load_PRF_idx_input;
    logic                              load_sign_input;  

    // SQ
    logic [1:0]                        store_size_input;
    logic [31:0]                       store_data_input;
    logic                              store_data_valid_input;
    logic                              store_en;
    logic [$clog2(`ROB)-1:0]           store_ROB_idx_input;

} lsq_input_packet;

typedef struct packed {

  logic                                dcache_write_enable;
  logic [2:0]                          dcache_write_offset;
  logic [4:0]                          dcache_write_idx;
  logic [7:0]                          dcache_write_tag;
  logic [31:0]                         dcache_write_data;
  logic [1:0]                          dcache_write_size;


  logic [2:0]                          dcache_read_offset;
  logic [4:0]                          dcache_read_idx;
  logic [7:0]                          dcache_read_tag;
  logic [1:0]                          dcache_read_size;
  logic                                dcache_read_enable;
  logic [`LSQSZ-1:0]                   dcache_read_gnt;

} lsq_dcache_packet;


typedef struct packed {
    
    logic                       write_back_input;
    logic [15:0]                write_back_address_input;
    logic [63:0]                write_back_data_input;
    logic [1:0]                 write_back_size_input;

    logic                       write_enable_input;
    logic [15:0]                write_address_input;
    logic [63:0]                write_data_input;
    logic [1:0]                 write_size_input;

    logic                       read_enable_input;
    logic [15:0]                read_address_input;
    logic [`LSQSZ-1:0]          read_gnt_input;
    logic [1:0]                 read_size_input; 

} dcache_request_packet;

typedef struct packed {
    logic [2:0]          bus_valid_incoming;
    logic [2:0] [15:0]   bus_address_incoming;
    logic [2:0]          bus_write_incoming;
    logic [2:0] [63:0]   bus_data_incoming;
    logic [2:0] [1:0]    bus_size_incoming;
    logic [15:0] [15:0]  bus_req_fifo_address;
    logic [15:0] [63:0]  bus_req_fifo_data;    
    logic [15:0]         bus_req_fifo_write;
    logic [15:0]         bus_req_fifo_read;
    logic [15:0] [1:0]   bus_req_fifo_size;   
} dcache_bus_packet;

typedef struct packed {
    logic                memory_write_enable;
    logic [4:0]          memory_write_idx;
    logic [7:0]          memory_write_tag;
    logic [63:0]         memory_write_data;
} memory_dcache_packet;

typedef struct packed {
    logic                       write_dcache_enable;
    logic [2:0]                 write_dcache_offset;
    logic [4:0]                 write_dcache_index;
    logic [7:0]                 write_dcache_tag;
    logic [63:0]                write_dcache_data; 
    logic [1:0]                 write_dcache_size;

    logic                       memory_dcache_write_enable;
    logic [4:0]                 memory_dcache_write_index;
    logic [7:0]                 memory_dcache_write_tag;
    logic [63:0]                memory_dcache_write_data; 

    logic                       read_dcache_enable;
    logic [2:0]                 read_dcache_offset;
    logic [4:0]                 read_dcache_index;
    logic [7:0]                 read_dcache_tag;
    logic [1:0]                 read_dcache_size;
    logic [`LSQSZ-1:0]          read_dcache_pos_gnt;
    
} dcache_input_packet;

typedef struct packed {

logic                write_back_enable_out;
logic [15:0]         write_back_address_out;
logic [63:0]         write_back_data_out;
logic [1:0]          write_back_size_out;

logic                write_enable_out;
logic [15:0]         write_address_out;
logic [63:0]         write_data_out;
logic [1:0]          write_size_out;

logic                read_dcache_enable_out;
logic [15:0]         read_dcache_address_out;
logic [1:0]          read_dcache_size_out;
logic [`LSQSZ-1:0]   read_dcache_pos_gnt_out;

} dcache_output_packet;

`endif // __SYS_DEFS_SVH__
