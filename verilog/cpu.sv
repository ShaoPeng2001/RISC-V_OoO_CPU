`include "sys_defs.svh"
`include "ISA.svh"

module cpu(
        // Inputs
        input clock, reset,
        input MEM_TAG       Imem2proc_transaction_tag, // Should be zero unless there is a response
        input MEM_BLOCK     Imem2proc_data,
        input MEM_TAG       Imem2proc_data_tag,
        
        // Outputs
        output MEM_COMMAND  Imem_command, // Command sent to memory
        output ADDR         Imem_addr, // address sent to Instruction memory
        output [63:0]       proc2mem_data,            // store
`ifndef CACHE_MODE
        output MEM_SIZE     proc2mem_size,
`endif
        output COMMIT_PACKET [1:0]  committed_insts,

        output logic [31:0]         lsq_dcache_write_data,
        output logic                lsq_dcache_write_enable,
        output logic [1:0]          lsq_dcache_write_size,
        output logic [15:0]         lsq_dcache_write_address,

        output logic [31:0] [63:0]  dcache_data,
        output logic [31:0] [7:0]   dcache_tags,
        output logic [31:0]         dcache_dirty,
        output logic [31:0]         dcache_valid,

        output logic [1:0] [12:0]   victim_tags,
        output logic [1:0] [63:0]   victim_data,
        output logic [1:0]          victim_valid,
        output logic [1:0]          victim_dirty,

        output logic                bus_valid_incoming,
        output logic                bus_write_incoming,
        output logic [63:0]         bus_data_incoming,
        output logic [15:0]         bus_address_incoming,
        output logic [15:0] [15:0]  bus_req_fifo_address,
        output logic [15:0]         bus_req_fifo_write,
        output logic [15:0] [1:0]   bus_req_fifo_size,
        output logic [1:0]          bus_size_incoming,
        output logic [15:0] [63:0]  bus_req_fifo_data
);

    //////////////////////////////////////////////////
    //                                              //
    //            icache_dcache_arbiter             //
    //                                              //
    //////////////////////////////////////////////////
    logic [31:0]        icache_to_mem_addr;
    logic [1:0]         icache_to_mem_command;
    logic [1:0]         Data_memory_command;
    logic [15:0]        Data_memory_address;
    logic [1:0]         Data_memory_size;
    logic [63:0]        Data_memory_data;
    logic [3:0]         mem_to_icache_tag;
    logic [63:0]        mem_to_memdp_data;
    logic [3:0]         mem_to_icache_response;
    logic [3:0]         mem_to_dcache_tag;
    logic [63:0]        mem_to_dcache_data;
    logic [3:0]         mem_to_dcache_response;

    assign mem_to_icache_response   = (Data_memory_command == MEM_NONE) ? Imem2proc_transaction_tag : 0;
    assign mem_to_dcache_response   = (Data_memory_command == MEM_NONE) ? 0 : Imem2proc_transaction_tag;

    assign Imem_addr                = (Data_memory_command == MEM_NONE) ? icache_to_mem_addr : {16'b0,Data_memory_address};
    assign proc2mem_data            = (Data_memory_command == MEM_NONE) ? 0 : Data_memory_data;
    assign Imem_command             = (Data_memory_command == MEM_NONE) ? icache_to_mem_command : Data_memory_command;
    assign proc2mem_size            = (Data_memory_command == MEM_NONE) ? DOUBLE : Data_memory_size;

    assign mem_to_memdp_data        = Imem2proc_data;
    assign mem_to_icache_tag        = Imem2proc_data_tag;

    assign mem_to_dcache_data       = Imem2proc_data;
    assign mem_to_dcache_tag        = Imem2proc_data_tag;


    //////////////////////////////////////////////////
    //                                              //
    //                   LSQ                        //
    //                                              //
    //////////////////////////////////////////////////
    EX_MEM_PACKET [`N-1:0]                  ex_packet_out;

    logic [`N-1:0]                         	ALU_is_valid;
    logic [`N-1:0] [$clog2(`ROB)-1:0]       ALU_ROB_idx;
    logic [`N-1:0]                          ALU_load_or_store;
    logic [`N-1:0] [31:0]                   ALU_data;

    logic [`N-1:0] [$clog2(`ROB)-1:0]       ROB_idx;
    logic [`N-1:0] [31:0]                   store_data;
    logic [`N-1:0]                          store_en;

    logic [`N-1:0]                          load_en;
    logic [`N-1:0] [$clog2(`PRF)-1:0]       prf_idx_to_load;
    logic [`N-1:0] [1:0]                    store_size_to_load;
    logic [$clog2(`LSQSZ):0]                sq_free_number;
    logic [$clog2(`LSQSZ):0]                lq_free_number;

    generate
        for(genvar i = 0; i < 2; i++)begin
            assign ALU_is_valid[i]       = ex_packet_out[i].valid;
            assign ALU_ROB_idx[i]        = ex_packet_out[i].rob_idx;
            assign ALU_load_or_store[i]  = ex_packet_out[i].rd_mem | ex_packet_out[i].wr_mem;
            assign ALU_data[i]           = ex_packet_out[i].alu_result;

            assign ROB_idx[i]            = id_ex_packet[i].rob_idx;

            assign store_data[i]         = id_ex_packet[i].rs2_value;
            assign store_en[i]           = id_ex_packet[i].wr_mem & id_ex_packet[i].valid;
            assign load_en[i]            = id_ex_packet[i].rd_mem & id_ex_packet[i].valid;

            assign prf_idx_to_load[i]    = id_ex_packet[i].dest_PRF_idx;
            assign store_size_to_load[i] = id_ex_packet[i].mem_size;
        end
    endgenerate

    logic          sq_is_full;
    logic          lq_is_full;

    assign sq_is_full = sq_free_number < 3;
    assign lq_is_full = lq_free_number < 3;


    logic [1:0]                       dispatched_store_valid;
    logic [1:0]                       dispatched_inst_sign;

    logic                                   store_commit;
    logic [31:0]                       lq_cdb_data_broadcast;
    logic [$clog2(`PRF)-1:0]                lq_cdb_phys_broadcast;
    logic [1:0]                       lq_cdb_broadcast_valid;

    logic [$clog2(`ROB)-1:0]                lq_cdb_rob_broadcast;
    assign lq_cdb_broadcast_valid[`N-2:0] = 0;


    logic [`N-1:0] [31:0]               CDB_Data;
    logic [`N-1:0] [$clog2(`PRF)-1:0]        CDB_PRF_idx;
    logic [`N-1:0]                           CDB_valid;
    logic                                       squash;
    logic [`N-1:0]							CDB_inst_reg_write;


    logic [`N-1:0] [15:0]                       ALU_address_input;

    assign ALU_address_input[0] = ALU_data[0][15:0];
    assign ALU_address_input[1] = ALU_data[1][15:0];


    logic [2:0]                                 lsq_dcache_write_offset;
    logic [4:0]                                 lsq_dcache_write_index;
    logic [7:0]                                 lsq_dcache_write_tag;

    assign lsq_dcache_write_address = {lsq_dcache_write_tag, lsq_dcache_write_index, lsq_dcache_write_offset};

    logic [2:0]                                 lsq_dcache_read_offset;
    logic [4:0]                                 lsq_dcache_read_index;
    logic [7:0]                                 lsq_dcache_read_tag;
    logic [1:0]                                 lsq_dcache_read_size;
    logic                                       lsq_dcache_read_enable;
    logic [`LSQSZ-1:0]                          lsq_dcache_read_pos_gnt;

    logic [63:0]                                dcache_lsq_read_data;
    logic [`LSQSZ-1:0]                          dcache_response;

    logic [`LSQSZ-1:0]                          mem_feedback;
    logic [31:0]                                mem_data;       

    logic                                       mem_dcache_write_enable;
    logic [4:0]                                 mem_dcache_write_index;
    logic [7:0]                                 mem_dcache_write_tag;
    logic [63:0]                                mem_dcache_write_data;

    logic                                       dcache_mem_write_back_enable;
    logic [15:0]                                dcache_mem_write_back_address;
    logic [63:0]                                dcache_mem_write_back_data;
    logic [1:0]                                 dcache_mem_write_back_size;

    logic                                       dcache_mem_write_enable;
    logic [15:0]                                dcache_mem_write_address;
    logic [63:0]                                dcache_mem_write_data;
    logic [1:0]                                 dcache_mem_write_size;

    logic                                       dcache_mem_read_enable;
    logic [15:0]                                dcache_mem_read_address;
    logic [1:0]                                 dcache_mem_read_size;
    logic [`LSQSZ-1:0]                          dcache_mem_read_pos_gnt;

    lsq_input_packet [`N-1:0] lsq_in;
    lsq_dcache_packet lsq_dcache_out;

    generate
    for(genvar i = 0; i < 2; i++) begin
        assign lsq_in[i].CDB_Data                = CDB_Data[i];
        assign lsq_in[i].CDB_PRF_idx             = CDB_PRF_idx[i];
        assign lsq_in[i].CDB_valid               = CDB_inst_reg_write[i];

        assign lsq_in[i].ALU_ROB_idx             = ALU_ROB_idx[i];
        assign lsq_in[i].ALU_is_valid            = ALU_is_valid[i];
        assign lsq_in[i].ALU_is_ls               = ALU_load_or_store[i];
        assign lsq_in[i].ALU_data                = ALU_address_input[i];

        assign lsq_in[i].store_size_input        = store_size_to_load[i];
        assign lsq_in[i].store_data_input        = store_data[i];
        assign lsq_in[i].store_data_valid_input  = dispatched_store_valid[i];
        assign lsq_in[i].store_en                = store_en[i];
        assign lsq_in[i].store_ROB_idx_input     = ROB_idx[i];

        assign lsq_in[i].load_size_input         = store_size_to_load[i];
        assign lsq_in[i].load_enable_input       = load_en[i];
        assign lsq_in[i].load_ROB_idx_input      = ROB_idx[i];
        assign lsq_in[i].load_PRF_idx_input      = prf_idx_to_load[i];
        assign lsq_in[i].load_sign_input         = dispatched_inst_sign[i];

    end
    endgenerate

    LSQ LSQ_0(
        .clock(clock),
        .reset(reset),
        .squash(squash),

        .store_retire(store_commit),
        .lsq_in(lsq_in),
        .mem_dcache_write_enable(mem_dcache_write_enable),

        .dcache_response(dcache_response),
        .dcache_data(dcache_lsq_read_data[31:0]),

        .mem_feedback(mem_feedback),
        .mem_data(mem_data),

        .sq_free_number(sq_free_number),
        .lq_free_number(lq_free_number),

        .lsq_dcache_out(lsq_dcache_out),

        .CDB_Data_out(lq_cdb_data_broadcast),
        .CDB_PRF_idx_out(lq_cdb_phys_broadcast),
        .CDB_valid_out(lq_cdb_broadcast_valid[`N-1]),
        .CDB_ROB_idx_out(lq_cdb_rob_broadcast)
    );

    assign lsq_dcache_write_enable      = lsq_dcache_out.dcache_write_enable;
    assign lsq_dcache_write_offset      = lsq_dcache_out.dcache_write_offset;
    assign lsq_dcache_write_index       = lsq_dcache_out.dcache_write_idx;
    assign lsq_dcache_write_tag         = lsq_dcache_out.dcache_write_tag;
    assign lsq_dcache_write_data        = lsq_dcache_out.dcache_write_data;
    assign lsq_dcache_write_size        = lsq_dcache_out.dcache_write_size;

    assign lsq_dcache_read_offset       = lsq_dcache_out.dcache_read_offset;
    assign lsq_dcache_read_index        = lsq_dcache_out.dcache_read_idx;
    assign lsq_dcache_read_tag          = lsq_dcache_out.dcache_read_tag;
    assign lsq_dcache_read_size         = lsq_dcache_out.dcache_read_size;
    assign lsq_dcache_read_enable       = lsq_dcache_out.dcache_read_enable;
    assign lsq_dcache_read_pos_gnt      = lsq_dcache_out.dcache_read_gnt;

    //////////////////////////////////////////////////
    //                                              //
    //                   Dcache                     //
    //                                              //
    //////////////////////////////////////////////////
    dcache_input_packet dcache_input;
    dcache_output_packet dcache_out;

    assign dcache_input.write_dcache_enable         = lsq_dcache_write_enable;
    assign dcache_input.write_dcache_offset         = lsq_dcache_write_offset;
    assign dcache_input.write_dcache_index          = lsq_dcache_write_index;
    assign dcache_input.write_dcache_tag            = lsq_dcache_write_tag;
    assign dcache_input.write_dcache_data           = {32'b0, lsq_dcache_write_data};
    assign dcache_input.write_dcache_size           = lsq_dcache_write_size;

    assign dcache_input.memory_dcache_write_enable  = mem_dcache_write_enable;
    assign dcache_input.memory_dcache_write_index   = mem_dcache_write_index;
    assign dcache_input.memory_dcache_write_tag     = mem_dcache_write_tag;
    assign dcache_input.memory_dcache_write_data    = mem_dcache_write_data;

    assign dcache_input.read_dcache_enable          = lsq_dcache_read_enable;
    assign dcache_input.read_dcache_offset          = lsq_dcache_read_offset;
    assign dcache_input.read_dcache_index           = lsq_dcache_read_index;
    assign dcache_input.read_dcache_tag             = lsq_dcache_read_tag;
    assign dcache_input.read_dcache_size            = lsq_dcache_read_size;
    assign dcache_input.read_dcache_pos_gnt         = lsq_dcache_read_pos_gnt;

    dcache dcache_0(
        .clock(clock),
        .reset(reset),
        .dcache_input(dcache_input),

        .dcache_read_data_out(dcache_lsq_read_data),
        .dcache_read_response(dcache_response),

        .dcache_data(dcache_data),
        .dcache_tags(dcache_tags),
        .dcache_dirty_bit(dcache_dirty),
        .dcache_valid_bit(dcache_valid),

        .victim_tags(victim_tags),
        .victim_data(victim_data),
        .victim_valid(victim_valid),
        .victim_dirty(victim_dirty),

        .dcache_out(dcache_out)
    );

    assign dcache_mem_write_back_enable = dcache_out.write_back_enable_out;
    assign dcache_mem_write_back_address = dcache_out.write_back_address_out;
    assign dcache_mem_write_back_data = dcache_out.write_back_data_out;
    assign dcache_mem_write_back_size = dcache_out.write_back_size_out;

    assign dcache_mem_write_enable = dcache_out.write_enable_out;
    assign dcache_mem_write_address = dcache_out.write_address_out;
    assign dcache_mem_write_data = dcache_out.write_data_out;
    assign dcache_mem_write_size = dcache_out.write_size_out;

    assign dcache_mem_read_enable = dcache_out.read_dcache_enable_out;
    assign dcache_mem_read_address = dcache_out.read_dcache_address_out;
    assign dcache_mem_read_size = dcache_out.read_dcache_size_out;
    assign dcache_mem_read_pos_gnt  = dcache_out.read_dcache_pos_gnt_out;

    dcache_request_packet dcache_request_input;
    memory_dcache_packet  memory_dcache_signals;
    dcache_bus_packet     dcache_bus_out;

    assign dcache_request_input.write_back_input          = dcache_mem_write_back_enable;
    assign dcache_request_input.write_back_address_input  = dcache_mem_write_back_address;
    assign dcache_request_input.write_back_data_input     = dcache_mem_write_back_data;
    assign dcache_request_input.write_back_size_input     = dcache_mem_write_back_size;

    assign dcache_request_input.write_enable_input        = dcache_mem_write_enable;
    assign dcache_request_input.write_address_input       = dcache_mem_write_address;
    assign dcache_request_input.write_data_input          = dcache_mem_write_data;
    assign dcache_request_input.write_size_input          = dcache_mem_write_size;

    assign dcache_request_input.read_enable_input         = dcache_mem_read_enable;
    assign dcache_request_input.read_address_input        = dcache_mem_read_address;
    assign dcache_request_input.read_gnt_input            = dcache_mem_read_pos_gnt;
    assign dcache_request_input.read_size_input           = dcache_mem_read_size;

    dcache_memory_fifo fifo(
        .clock(clock),
        .reset(reset),
        .squash(squash),

        .dcache_request_input(dcache_request_input),
        
        .mem2proc_transaction_tag(mem_to_dcache_response),
        .mem2proc_data(mem_to_dcache_data),
        .mem2proc_data_tag(mem_to_dcache_tag),

        .data_memory_command(Data_memory_command),
        .data_memory_address(Data_memory_address),
        .data_memory_size(Data_memory_size),
        .data_memory_data(Data_memory_data),

        .mem_response(mem_feedback),
        .mem_data(mem_data),
        
        .memory_dcache_signals(memory_dcache_signals),
        .dcache_bus_out(dcache_bus_out)
    );

    assign mem_dcache_write_enable  = memory_dcache_signals.memory_write_enable;
    assign mem_dcache_write_index   = memory_dcache_signals.memory_write_idx;
    assign mem_dcache_write_tag     = memory_dcache_signals.memory_write_tag;
    assign mem_dcache_write_data    = memory_dcache_signals.memory_write_data;

    assign bus_valid_incoming       = dcache_bus_out.bus_valid_incoming;
    assign bus_address_incoming     = dcache_bus_out.bus_address_incoming;
    assign bus_write_incoming       = dcache_bus_out.bus_write_incoming;
    assign bus_data_incoming        = dcache_bus_out.bus_data_incoming;
    assign bus_size_incoming        = dcache_bus_out.bus_size_incoming;
    assign bus_req_fifo_address     = dcache_bus_out.bus_req_fifo_address;
    assign bus_req_fifo_data        = dcache_bus_out.bus_req_fifo_data;
    assign bus_req_fifo_write       = dcache_bus_out.bus_req_fifo_write;
    assign bus_req_fifo_size        = dcache_bus_out.bus_req_fifo_size;

//////////////////////////////////////////////////
//                                              //
//                  icache                      //
//                                              //
//////////////////////////////////////////////////
    logic [`N-1:0]   proc_to_icache_en;
    assign proc_to_icache_en = 2'b11;

    logic [`N-1:0] [63:0]   icache_to_proc_data;
    logic [`N-1:0]          icache_to_proc_data_valid;
    logic [`N-1:0] [31:0]   proc_to_icache_addr;


    logic [`N-1:0][63:0]    memdp_to_icache_data;
    logic [`N-1:0]          memdp_to_icache_valid;
    logic [`N-1:0] [4:0]    icache_to_memdp_read_idx;
    logic [`N-1:0] [7:0]    icache_to_memdp_read_tag;
    logic [4:0]             icache_to_memdp_idx;
    logic [7:0]             icache_to_memdp_tag;
    logic                   icache_to_memdp_enable;

    Icache_packet [`N-1:0] icache_packet_in;

    generate
        for(genvar i = 0; i < `N; i++) begin
            assign icache_packet_in[i].proc2Icache_addr = proc_to_icache_addr[i];
            assign icache_packet_in[i].proc2Icache_en   = proc_to_icache_en[i];
            assign icache_packet_in[i].cachemem_data    = memdp_to_icache_data[i];
            assign icache_packet_in[i].cachemem_valid   = memdp_to_icache_valid[i];
        end
    endgenerate

    icache prefetch(
        .clock(clock),
        .reset(reset),

        // from Imemory to icache
        .Imem2proc_transaction_tag(mem_to_icache_response),
        .Imem2proc_data_tag(mem_to_icache_tag),

        .icache_packet_in(icache_packet_in),
        // from icache to imemory
        .proc2Imem_command(icache_to_mem_command), 
        .proc2Imem_addr(icache_to_mem_addr),

        // from icache to processor
        .Icache_data_out(icache_to_proc_data),        // value is memory[proc2Icache_addr]
        .Icache_valid_out(icache_to_proc_data_valid), // when this is high

        // from icache to cache mem
        .rd_idx(icache_to_memdp_read_idx),
        .current_index(icache_to_memdp_idx),
        .data_write_enable(icache_to_memdp_enable)
    );

    memDP #(
        .WIDTH     ($bits(MEM_BLOCK)),
        .DEPTH     (`ICACHE_LINES),
        .READ_PORTS(2),
        .BYPASS_EN (0))
    icache_mem (
        .clock(clock),
        .reset(reset),
        .re   (2'b11),
        .raddr(icache_to_memdp_read_idx),
        .rdata(memdp_to_icache_data),
        .we   (icache_to_memdp_enable),
        .waddr(icache_to_memdp_idx),
        .wdata(mem_to_memdp_data)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                  Commit                      //
    //                                              //
    //////////////////////////////////////////////////

    logic [`N-1:0] [31:0]   committed_data;


    generate
        for(genvar i = 0; i < `N; i = i + 1) begin
            assign committed_insts[i].NPC       = rob_packet_out[i].PC_out + 4;
            assign committed_insts[i].data      = committed_data[i];
            assign committed_insts[i].reg_idx   = (~rob_packet_out[i].valid_out) ? `ZERO_REG : rob_packet_out[i].dest_ARN_out;
            assign committed_insts[i].halt      = rob_packet_out[i].halt_out;
            assign committed_insts[i].illegal   = rob_packet_out[i].illegal_out;
            assign committed_insts[i].valid     = rob_packet_out[i].retired;
        end
    endgenerate

    //////////////////////////////////////////////////
    //                                              //
    //                  CDB                         //
    //                                              //
    //////////////////////////////////////////////////

    logic [`N-1:0]                      valid_mem_address_to_CDB;
    logic [`N-1:0] [$clog2(`ROB)-1:0]   CDB_broadcast_ROB_index;
    logic [`N-1:0]                      CDB_braodcast_direction;
    logic [`N-1:0] [31:0]               CDB_broadcast_target;
    logic [`N-1:0]                      load_forwarding_toward_CDB;
    logic [`N-1:0]                      CDB_broadcast_branch;
    logic [`N-1:0] [31:0]               CDB_broadcast_current_PC;

    generate
        for(genvar i = 0; i < `N; i++) begin
            assign CDB_inst_reg_write[i]        = lq_cdb_broadcast_valid[i] | (ex_packet_out[i].valid & ~valid_mem_address_to_CDB[i] & ex_packet_out[i].reg_write);     // whether this CDB data will be written to a register
            assign CDB_valid[i]                 = lq_cdb_broadcast_valid[i] | ex_packet_out[i].valid;                                                             // wether it is a valid inst
            assign CDB_braodcast_direction[i]   = lq_cdb_broadcast_valid[i] ? 0 : ex_packet_out[i].take_branch;                                                   // whether this CDB's inst will be taking branch
            assign CDB_Data[i]                  = lq_cdb_broadcast_valid[i] ? lq_cdb_data_broadcast: ex_packet_out[i].take_branch ? ex_packet_out[i].NPC : ex_packet_out[i].alu_result ;
            assign CDB_PRF_idx[i]               = lq_cdb_broadcast_valid[i] ? lq_cdb_phys_broadcast : ex_packet_out[i].dest_PRF_idx;
            assign CDB_broadcast_ROB_index[i]   = lq_cdb_broadcast_valid[i] ? lq_cdb_rob_broadcast : ex_packet_out[i].rob_idx;                                          // the rob index of the CDB's inst
            assign CDB_broadcast_target[i]      = lq_cdb_broadcast_valid[i] ? 0 : ex_packet_out[i].take_branch ? ex_packet_out[i].alu_result: ex_packet_out[i].NPC ;  // if  			
            assign CDB_broadcast_current_PC[i]  = ex_packet_out[i].NPC-4;
        end
    endgenerate

    generate
        for(genvar i = 0; i < `N; i++) begin
            assign valid_mem_address_to_CDB[i]     = ~lq_cdb_broadcast_valid[i] & ex_packet_out[i].valid & (ex_packet_out[i].rd_mem) | (ex_packet_out[i].wr_mem);
            assign load_forwarding_toward_CDB[i]   = ~lq_cdb_broadcast_valid[i] & ex_packet_out[i].valid & ex_packet_out[i].rd_mem;
        end
    endgenerate


    //////////////////////////////////////////////////
    //                                              //
    //                  IF-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    IF_ID_PACKET [`N-1:0]            if_packet;
    logic                            take_branch;
    logic        [31:0]              branch_target;
    logic                            rob_is_full;
    logic                            rs_is_full;
    logic        [31:0]              squash_next_PC;
    logic [31:0]                     id_next_PC;

    if_stage IF(
        // Inputs
        .clock (clock),
        .reset (reset),
        .stall(rob_is_full | rs_is_full | lq_is_full | sq_is_full),

        .predicted_pc(id_next_PC),
        .take_branch(squash),
        .target_pc(squash_next_PC),

        .icache_data(icache_to_proc_data),
        .icache_data_valid(icache_to_proc_data_valid),
        
        // Outputs
        .icache_addr(proc_to_icache_addr),
        .if_packet_out(if_packet)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                  ID-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    ID_packet [`N-1:0]                   id_packet_in;
    ID_EX_PACKET [`N-1:0]                id_packet;
    logic [`N-1:0]                       id_predictions;                     
    logic [`N-1:0]                       id_sign_out;
    logic [`N-1:0]                       id_opa_valid;
    logic [`N-1:0]                       id_opb_valid;

    generate
        for(genvar i = 0; i < `N; i++) begin
            assign id_packet_in[i].if_id_packet_in  = if_packet[i];            
        end
    endgenerate

    generate
        for(genvar i = 0; i < `N; i++) begin
            assign id_packet_in[i].rob_retire       = rob_packet_out[i].valid_out;
            assign id_packet_in[i].ARCH_ARF_idx     = rob_packet_out[i].dest_ARN_out;
            assign id_packet_in[i].ARCH_PRF_idx     = rob_packet_out[i].dest_PRN_out;
            assign id_packet_in[i].dest_PRN_out     = rob_packet_out[i].dest_PRN_out;
            assign id_packet_in[i].retired          = rob_packet_out[i].valid_out;
        end
    endgenerate

    generate
        for(genvar i = 0; i < `N; i++) begin
            assign id_packet_in[i].CDB_write_idx    = CDB_PRF_idx[i];
            assign id_packet_in[i].CDB_write_en     = CDB_inst_reg_write[i];
            assign id_packet_in[i].CDB_write_data   = CDB_Data[i];            
        end
    endgenerate

    id_stage ID(         
        .clock(clock),                      // system clock
        .reset(reset),                      // system reset
        .squash(squash),                    // 當 head pointer 指到的 entire 有 branch misprediction 發生, ROB 會送出 squashion 信號

        .id_packet_in(id_packet_in),

        .PC_update(CDB_broadcast_current_PC),
        .direction_update(CDB_braodcast_direction),
        .target_update(CDB_broadcast_target),
        .valid_update(CDB_valid & CDB_broadcast_branch),

        // Output
        .next_PC(id_next_PC),               // predicted PC
        .predictions(id_predictions),       // predicted direction


        .id_packet_out(id_packet),          // ID stage output
        .sign_out(id_sign_out),             
        .opa_valid(id_opa_valid),           // source register 是否為 valid
        .opb_valid(id_opb_valid),           // source register 是否為 valid
        .committed_data(committed_data)
    );

    //////////////////////////////////////////////////
    //                                              //
    //       ID/ROB & RS Pipeline Register          //
    //                                              //
    //////////////////////////////////////////////////
    ID_EX_PACKET [`N-1:0]       id_ex_packet;
    logic id_ex_enable;

    logic [31:0]                id_ex_next_PC;
    logic [`N-1:0]              id_ex_predictions;
    logic [`N-1:0]              id_ex_opa_valid;
    logic [$clog2(`ROB):0]      next_num_free;
    logic [$clog2(`RS):0]       num_is_free_next;
    logic [$clog2(`ROB)-1:0]    next_tail;

    assign rob_is_full  = next_num_free < 2 * `N;
    assign rs_is_full   = num_is_free_next < `N;

    assign id_ex_enable = ~rob_is_full & ~rs_is_full & ~lq_is_full & ~sq_is_full & ~squash;

    always_ff @(posedge clock) begin
        if(reset || rob_is_full || rs_is_full || lq_is_full || sq_is_full || squash) begin            
            id_ex_packet                <= 0;
            id_ex_predictions           <= 2'b00;
            id_ex_opa_valid             <= 0;
            dispatched_store_valid		<= 0;
            dispatched_inst_sign        <= 0;            
        end
        else if(id_ex_enable) begin
            id_ex_packet            <= id_packet;
            id_ex_next_PC           <= id_next_PC;
            id_ex_predictions       <= id_predictions;
            id_ex_opa_valid         <= id_opa_valid;
            dispatched_store_valid  <= id_opb_valid;
            dispatched_inst_sign    <= id_sign_out;
            for(int i = 0; i < `N; i++) begin
                id_ex_packet[i].rob_idx <= (next_tail + i) % `ROB;
            end
        end
    end

    //////////////////////////////////////////////////
    //                                              //
    //                   ROB-Stage                  //
    //                                              //
    //////////////////////////////////////////////////


    ROB_packet [`N-1:0]                 rob_packet_in;
    ROB_out_packet [`N-1:0]             rob_packet_out;
    // input to ROB
    logic [`N-1:0] [4:0]                dest_ARN;
    logic [`N-1:0] [$clog2(`PRF)-1:0]   dest_PRN;
    logic [`N-1:0]                      is_branch;
    logic [`N-1:0]                      valid;
    logic [`N-1:0]                      illegal;
    logic [`N-1:0]                      halt;
    logic [`N-1:0] [31:0]               PC_in_rob;
    logic [`N-1:0] [31:0]               target;
    logic [`N-1:0]                      id_ex_reg_write;
    logic [`N-1:0]                      id_ex_is_store;

    // output from ROB
    logic [$clog2(`ROB)-1:0]        tail;
    logic [$clog2(`ROB):0]          num_free;
    logic [`N-1:0] [31:0]           target_out;
    logic [$clog2(`N):0]            num_committed;

    generate
        for(genvar i = 0; i < `N; i++) begin
            assign rob_packet_in[i].CDB_ROB_idx      = CDB_broadcast_ROB_index[i];
            assign rob_packet_in[i].CDB_valid        = CDB_valid[i] & ~load_forwarding_toward_CDB[i];
            assign rob_packet_in[i].CDB_direction    = CDB_braodcast_direction[i];
            assign rob_packet_in[i].CDB_target       = CDB_broadcast_target[i];
            assign rob_packet_in[i].dest_ARN         = id_ex_packet[i].inst.r.rd;
            assign rob_packet_in[i].dest_PRN         = id_ex_packet[i].dest_PRF_idx;
            assign rob_packet_in[i].is_branch        = id_ex_packet[i].cond_branch | id_ex_packet[i].uncond_branch;
            assign rob_packet_in[i].valid            = id_ex_packet[i].valid & ~squash;
            assign rob_packet_in[i].illegal          = id_ex_packet[i].illegal;
            assign rob_packet_in[i].halt             = id_ex_packet[i].halt;
            assign rob_packet_in[i].PC               = id_ex_packet[i].PC;
            assign rob_packet_in[i].target           = id_ex_predictions[i] ? id_ex_next_PC : id_ex_packet[i].PC + 4;  // no branch prediction for milestone 2
            assign rob_packet_in[i].branch_direction = id_ex_predictions[i];
            assign rob_packet_in[i].reg_write        = id_ex_packet[i].reg_write;
            assign rob_packet_in[i].is_store         = id_ex_packet[i].wr_mem;
        end
    endgenerate

    rob ROB(
        .clock(clock),
        .reset(reset),

        .rob_packet_in(rob_packet_in),
        .lq_dcache_read_enable(lsq_dcache_read_enable),
        .mem_dcache_write_enable(mem_dcache_write_enable),

        // output
        .tail(tail),                            // 當前 ROB 的 tail 位置
        .next_tail(next_tail),                  // 當前 ROB tail 的下一個位置

        .rob_packet_out(rob_packet_out),

        .num_free(num_free),                    // 當前 ROB 當中的空位
        .next_num_free(next_num_free),          // ROB 下一個可用的空位
        .squash(squash),                        // branch misprediction 是否發生
        .next_pc(squash_next_PC),               // 根據是否有 misprediction 發生來決定 IF_stage 下一次要 fetch 的 PC
     
        .target_out(target_out),

        .committed_number(num_committed),
        .store_commit(store_commit)             // avoid two store retire at one time
    );

    //////////////////////////////////////////////////
    //                                              //
    //                   RS-Stage                   //
    //                                              //
    //////////////////////////////////////////////////
    RS_packet [`N-1:0]              rs_packet_in;
    ID_EX_PACKET [`N-1:0]           rs_packet_out;
    logic [$clog2(`RS):0]           num_is_free;
    logic [`N-1:0]               ALU_in_use;

    generate
        for(genvar i = 0; i < `N; i++) begin
            assign rs_packet_in[i].CDB_Data        = CDB_Data[i];
            assign rs_packet_in[i].CDB_PRF_idx     = CDB_PRF_idx[i];
            assign rs_packet_in[i].CDB_valid       = CDB_inst_reg_write[i];
            assign rs_packet_in[i].rs1_valid_in    = id_ex_opa_valid[i];
            assign rs_packet_in[i].rs2_valid_in    = dispatched_store_valid[i];
            assign rs_packet_in[i].id_rs_packet_in = id_ex_packet[i];
        end
    endgenerate

    RS Rs(
        .clock(clock),
        .reset(reset | squash),                 // when branch misprediction happened, flush RS

        .load(~(num_free < `N) & ~(num_is_free < `N) & ~squash),   // high when dispatch
        .ALU_in_usage(ALU_in_use | lq_cdb_broadcast_valid),		   // ALU function unit 是否被占用

        .rs_packet_in(rs_packet_in),
        .rs_packet_out(rs_packet_out),          // 從 RS issue 出去的 signal packet

        .free_rs_space(num_is_free),            // 目前 RS 當中空閒的數量
        .free_rs_space_next(num_is_free_next)
    );


    //////////////////////////////////////////////////
    //                                              //
    //          RS/EX Pipeline Register             //
    //                                              //
    //////////////////////////////////////////////////
    ID_EX_PACKET [`N-1:0] ex_packet_in_stall;

    always_ff @(posedge clock) begin
        for(int i = 0; i < `N; i++) begin
            if(~ALU_in_use[i] & ~lq_cdb_broadcast_valid[i]) begin                      // if no FU structural hazard
                ex_packet_in_stall[i] <= rs_packet_out[i];    // issue out packet
            end
        end
    end

    //////////////////////////////////////////////////
    //                                              //
    //                   EX-Stage                   //
    //                                              //
    //////////////////////////////////////////////////
    ID_EX_PACKET [`N-1:0]        ex_packet_in;

    generate 
        for(genvar i = 0; i < `N; i++) begin
            assign ex_packet_in[i]      = (ALU_in_use[i] | lq_cdb_broadcast_valid[i]) ? ex_packet_in_stall[i] : rs_packet_out[i];
        end
    endgenerate

    ex_stage EX (
        // Inputs
        .clock(clock),
        .reset(reset || squash),               // if branch misprediction happened, flush current procedure in FU
        .CDB_hazard (lq_cdb_broadcast_valid),  // modifed, since currently no LSQ
        .id_ex_packet_in(ex_packet_in),
        // Outputs
        .ex_packet_out(ex_packet_out),      
        .FU_in_usage(ALU_in_use),              // status showing which FU are stuck
        .ex_branch_out(CDB_broadcast_branch)   // FU result is for branch result
    );
endmodule
