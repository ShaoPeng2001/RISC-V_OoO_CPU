`include "sys_defs.svh"

module LSQ(
    input                                       clock,
    input                                       reset,
    input                                       squash,

    input                                       store_retire,  
    input lsq_input_packet [1:0]                lsq_in,

    input                                       mem_dcache_write_enable,

    input [`LSQSZ-1:0]                          dcache_response,
    input [31:0]                                dcache_data,        
    input [`LSQSZ-1:0]                          mem_feedback,
    input [31:0]                                mem_data,       

    output logic [$clog2(`LSQSZ):0]             sq_free_number,
    output logic [$clog2(`LSQSZ):0]             lq_free_number,

    output lsq_dcache_packet                    lsq_dcache_out,

    output logic [31:0]                         CDB_Data_out,
  	output logic [$clog2(`PRF)-1:0]             CDB_PRF_idx_out,
  	output logic                                CDB_valid_out,
    output logic [$clog2(`ROB)-1:0]             CDB_ROB_idx_out
);


    // CDB
    logic [1:0] [31:0]                          CDB_Data;
  	logic [1:0] [$clog2(`PRF)-1:0]              CDB_PRF_idx;
  	logic [1:0]                                 CDB_valid;

    // ALU
    logic [1:0] [$clog2(`ROB)-1:0]              ALU_ROB_idx;
    logic [1:0]                                 ALU_is_valid;
    logic [1:0]                                 ALU_is_ls;      
    logic [1:0] [15:0]                          ALU_data;

    // Store queue
    logic [1:0] [1:0]                           store_size_input;
    logic [1:0] [31:0]                          store_data_input;
    logic [1:0]                                 store_data_valid_input;
    logic [1:0]                                 store_en;
    logic [1:0] [$clog2(`ROB)-1:0]              store_ROB_idx_input;

    // Load queue
    logic [1:0] [1:0]                           load_size_input;
    logic [1:0]                                 load_enable_input;
    logic [1:0] [$clog2(`ROB)-1:0]              load_ROB_idx_input;
    logic [1:0] [$clog2(`PRF)-1:0]              load_PRF_idx_input;
    logic [1:0]                                 load_sign_input;

    generate
        for(genvar i = 0; i < 2; i++) begin
            assign CDB_Data[i]                = lsq_in[i].CDB_Data;
            assign CDB_PRF_idx[i]             = lsq_in[i].CDB_PRF_idx;
            assign CDB_valid[i]               = lsq_in[i].CDB_valid;

            assign ALU_ROB_idx[i]             = lsq_in[i].ALU_ROB_idx;
            assign ALU_is_valid[i]            = lsq_in[i].ALU_is_valid;
            assign ALU_is_ls[i]               = lsq_in[i].ALU_is_ls;
            assign ALU_data[i]                = lsq_in[i].ALU_data;

            assign store_size_input[i]        = lsq_in[i].store_size_input;
            assign store_data_input[i]        = lsq_in[i].store_data_input;
            assign store_data_valid_input[i]  = lsq_in[i].store_data_valid_input;
            assign store_en[i]                = lsq_in[i].store_en;
            assign store_ROB_idx_input[i]     = lsq_in[i].store_ROB_idx_input;

            assign load_size_input[i]         = lsq_in[i].load_size_input;
            assign load_enable_input[i]       = lsq_in[i].load_enable_input;
            assign load_ROB_idx_input[i]      = lsq_in[i].load_ROB_idx_input;
            assign load_PRF_idx_input[i]      = lsq_in[i].load_PRF_idx_input;
            assign load_sign_input[i]         = lsq_in[i].load_sign_input;
        end
    endgenerate

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

    
    assign  lsq_dcache_out.dcache_write_enable = dcache_write_enable;
    assign  lsq_dcache_out.dcache_write_offset = dcache_write_offset;
    assign  lsq_dcache_out.dcache_write_idx    = dcache_write_idx;
    assign  lsq_dcache_out.dcache_write_tag    = dcache_write_tag;
    assign  lsq_dcache_out.dcache_write_data   = dcache_write_data;
    assign  lsq_dcache_out.dcache_write_size   = dcache_write_size;

    assign  lsq_dcache_out.dcache_read_offset  = dcache_read_offset;
    assign  lsq_dcache_out.dcache_read_idx     = dcache_read_idx;
    assign  lsq_dcache_out.dcache_read_tag     = dcache_read_tag;
    assign  lsq_dcache_out.dcache_read_size    = dcache_read_size;
    assign  lsq_dcache_out.dcache_read_enable  = dcache_read_enable;
    assign  lsq_dcache_out.dcache_read_gnt     = dcache_read_gnt;
    

    logic [`LSQSZ-1:0] [1:0]                        store_size;
    logic [`LSQSZ-1:0] [15:0]                       store_addr;
    logic [`LSQSZ-1:0] [31:0]                       store_data;
    logic [`LSQSZ-1:0]                              store_data_valid;
    logic [`LSQSZ-1:0]                              store_address_valid;
    logic [`LSQSZ-1:0]                              store_valid;
    logic [1:0] [$clog2(`LSQSZ)-1:0]                sq_tail_sequential;
    logic [1:0]                                     store_enable_input;

    // Store queue的訊號
    logic [$clog2(`LSQSZ)-1:0]                      sq_head;
    logic [$clog2(`LSQSZ)-1:0]                      sq_tail;
    sq_entry [`LSQSZ-1:0]                           sq_entries;

    logic                                           sq_head_output_valid;
    logic [31:0]                                    sq_head_output_data;    
    logic [15:0]                                    sq_head_output_address;
    logic [1:0]                                     sq_head_output_size;

    assign store_enable_input = store_en;


    always_comb begin
        for(int i = 0; i < `LSQSZ; i++) begin
            store_data[i]           = sq_entries[i].data;
            store_data_valid[i]     = sq_entries[i].data_valid;
        end
    end

    always_comb begin
        for(int i = 0; i <`LSQSZ; i++) begin
            store_addr[i]           = sq_entries[i].addr;
            store_address_valid[i]  = sq_entries[i].addr_valid;
        end
    end

    always_comb begin
        for(int i = 0; i < `LSQSZ; i++) begin
            store_valid[i]          = sq_entries[i].valid;
            store_size[i]           = sq_entries[i].size;
        end
    end

    always_comb begin
        sq_tail_sequential[0] = sq_tail;
        sq_tail_sequential[1] = sq_tail_sequential[0];

        if(store_en[0] && (sq_tail_sequential[0] == `LSQSZ-1)) begin
            sq_tail_sequential[1] = 0;
        end else if(store_en[0] && !(sq_tail_sequential[0] == `LSQSZ-1)) begin
            sq_tail_sequential[1] = sq_tail_sequential[0] + 1;
        end
    end

    logic [1:0] [1:0]                    load_size_in;
    logic [1:0] [$clog2(`ROB)-1:0]       load_ROB_idx_in;
    logic [1:0] [$clog2(`PRF)-1:0]       load_PRF_idx_in;


    always_comb begin
        case(load_enable_input)
            2'b00: begin
                load_size_in[0] = 0;
                load_size_in[1] = 0;
            end

            2'b01: begin
                load_size_in[0] = load_size_input[0];
                load_size_in[1] = 0;
            end

            2'b10: begin
                load_size_in[0] = 0;
                load_size_in[1] = load_size_input[1];
            end

            2'b11: begin
                load_size_in[0] = load_size_input[0];
                load_size_in[1] = load_size_input[1];
            end

            default: begin
                load_size_in[0] = 0;
                load_size_in[1] = 0;
            end
        endcase
    end

    always_comb begin
        case(load_enable_input)
            2'b00: begin
                load_ROB_idx_in[0] = 0;
                load_ROB_idx_in[1] = 0;
            end

            2'b01: begin
                load_ROB_idx_in[0] = load_ROB_idx_input[0];
                load_ROB_idx_in[1] = 0;
            end

            2'b10: begin
                load_ROB_idx_in[0] = 0;
                load_ROB_idx_in[1] = load_ROB_idx_input[1];
            end

            2'b11: begin
                load_ROB_idx_in[0] = load_ROB_idx_input[0];
                load_ROB_idx_in[1] = load_ROB_idx_input[1];
            end

            default: begin
                load_ROB_idx_in[0] = 0;
                load_ROB_idx_in[1] = 0;
            end
        endcase
    end

    always_comb begin
        case(load_enable_input)
            2'b00: begin
                load_PRF_idx_in[0] = 0;
                load_PRF_idx_in[1] = 0;
            end

            2'b01: begin
                load_PRF_idx_in[0] = load_PRF_idx_input[0];
                load_PRF_idx_in[1] = 0;
            end

            2'b10: begin
                load_PRF_idx_in[0] = 0;
                load_PRF_idx_in[1] = load_PRF_idx_input[1];
            end

            2'b11: begin
                load_PRF_idx_in[0] = load_PRF_idx_input[0];
                load_PRF_idx_in[1] = load_PRF_idx_input[1];
            end

            default: begin
                load_PRF_idx_in[0] = 0;
                load_PRF_idx_in[1] = 0;
            end
        endcase
    end

    logic [`LSQSZ-1:0]                      data_cache_gnt;
    logic [`LSQSZ-1:0] [31:0]               lq_data;
    logic [`LSQSZ-1:0] [15:0]               lq_addr;
    logic [`LSQSZ-1:0] [$clog2(`PRF)-1:0]   lq_PRF_idx;
    logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0]   lq_ROB_idx;
    logic [`LSQSZ-1:0]                      lq_signed;
    logic [`LSQSZ-1:0] [1:0]                lq_size;

    logic [`LSQSZ-1:0]                      CDB_lq_forward_available;
    
    lq_store_packet    [`LSQSZ-1:0]         lq_store_input;
    lq_dispatch_packet [1:0]                lq_dispatch_input;
    lq_out_packet      [`LSQSZ-1:0]         lq_out;

    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign lq_store_input[i].store_data          = store_data[i];
            assign lq_store_input[i].store_data_valid    = store_data_valid[i];
            assign lq_store_input[i].store_addr          = store_addr[i];
            assign lq_store_input[i].store_address_valid = store_address_valid[i];
            assign lq_store_input[i].store_size          = store_size[i];
            assign lq_store_input[i].store_valid         = store_valid[i];
        end
    endgenerate
    
    generate
        for(genvar i = 0; i < 2; i++) begin
            assign lq_dispatch_input[i].dispatched_load_size   = load_size_in[i];
            assign lq_dispatch_input[i].dispatched_load_enable = load_enable_input[i];
            assign lq_dispatch_input[i].dispatched_ROB_idx     = load_ROB_idx_in[i];
            assign lq_dispatch_input[i].dispatched_PRF_idx     = load_PRF_idx_in[i];
            assign lq_dispatch_input[i].dispatched_load_sign   = load_sign_input[i];

            assign lq_dispatch_input[i].ALU_ROB_idx            = ALU_ROB_idx[i];
            assign lq_dispatch_input[i].ALU_is_valid           = ALU_is_valid[i];
            assign lq_dispatch_input[i].ALU_for_address        = ALU_is_ls[i];
            assign lq_dispatch_input[i].ALU_data               = ALU_data[i];
        end
    endgenerate

    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign lq_data[i]     = lq_out[i].lq_data;        
            assign lq_addr[i]     = lq_out[i].lq_addr;
            assign lq_ROB_idx[i]  = lq_out[i].lq_ROB_idx;
            assign lq_PRF_idx[i]  = lq_out[i].lq_PRF_idx;
            assign lq_signed[i]   = lq_out[i].lq_signed;
            assign lq_size[i]     = lq_out[i].lq_size;
        end
    endgenerate
    
    LQ lq(
        .clock(clock),
        .reset(reset),
        .squash(squash),
        .lq_store_input(lq_store_input),
        .mem_dcache_write_enable(mem_dcache_write_enable),
        .sq_head(sq_head),
        .sq_tail(sq_tail_sequential),
        .lq_dispatch_input(lq_dispatch_input),
        .dcache_response(dcache_response),
        .dcache_data(dcache_data),        
        .memory_response(mem_feedback),
        .memory_data(mem_data), 

        // outputs
        .lq_free_space_output(lq_free_number),
        .data_cache_gnt(data_cache_gnt),
        .CDB_lq_forward_available(CDB_lq_forward_available),
        .lq_out(lq_out)
);

//////////////////////////////////////////////////
//                                              //
//            output for data cache             //
//                                              //
//////////////////////////////////////////////////

  assign dcache_read_enable  = (data_cache_gnt != 0) ? 1 : 0;
  assign dcache_read_gnt = data_cache_gnt;

  wor [$clog2(`LSQSZ)-1:0] dcache_gnt_position;
  logic [`LSQSZ-1:0]       dcache_gnt_valid;

  generate
      for(genvar i = 0; i < `LSQSZ; i++) begin
          assign dcache_gnt_position   = data_cache_gnt[i] ? i : 0;
          assign dcache_gnt_valid[i]   = data_cache_gnt[i] ? 1 : 0;
      end
  endgenerate

  always_comb begin
      dcache_read_offset = (dcache_gnt_valid[dcache_gnt_position]) ? lq_addr[dcache_gnt_position][2:0] : 0;
      dcache_read_idx    = (dcache_gnt_valid[dcache_gnt_position]) ? lq_addr[dcache_gnt_position][7:3] : 0;
      dcache_read_tag    = (dcache_gnt_valid[dcache_gnt_position]) ? lq_addr[dcache_gnt_position][15:8] : 0;
      dcache_read_size   = (dcache_gnt_valid[dcache_gnt_position]) ? lq_size[dcache_gnt_position] : 0;
  end

//////////////////////////////////////////////////
//                                              //
//          CDB forward from load queue         //
//                                              //
//////////////////////////////////////////////////

  logic [31:0]  CDB_data_from_lq;
  logic [1:0]   CDB_size_from_lq;
  logic         CDB_signed;


  assign CDB_valid_out      = (CDB_lq_forward_available != 0) ? 1 : 0;


  wor   [$clog2(`LSQSZ)-1:0]  CDB_available_position;
  logic [`LSQSZ-1:0]          CDB_available;

  generate
      for(genvar i = 0; i < `LSQSZ; i++) begin
          assign CDB_available_position = CDB_lq_forward_available[i] ? i : 0;
          assign CDB_available[i]       = CDB_lq_forward_available[i] ? 1 : 0;
      end
  endgenerate

  always_comb begin
      CDB_data_from_lq  = (CDB_available[CDB_available_position]) ? lq_data[CDB_available_position] : 0;
      CDB_PRF_idx_out   = (CDB_available[CDB_available_position]) ? lq_PRF_idx[CDB_available_position] : 0;
      CDB_ROB_idx_out   = (CDB_available[CDB_available_position]) ? lq_ROB_idx[CDB_available_position] : 0;
      CDB_size_from_lq  = (CDB_available[CDB_available_position]) ? lq_size[CDB_available_position] : 0;
      CDB_signed        = (CDB_available[CDB_available_position]) ? lq_signed[CDB_available_position] : 0;
  end


  logic [31:0] CDB_data_sign_extension;

  always_comb begin
      case(CDB_size_from_lq)
          BYTE:
              CDB_data_sign_extension = {{24{CDB_data_from_lq[7]}},  CDB_data_from_lq[7:0]};
          HALF:
              CDB_data_sign_extension = {{16{CDB_data_from_lq[15]}}, CDB_data_from_lq[15:0]};
          default:
              CDB_data_sign_extension = CDB_data_from_lq;
      endcase
  end

  assign CDB_Data_out = CDB_signed ? CDB_data_sign_extension: CDB_data_from_lq;

  sq_input_packet [1:0] sq_input; 

  generate
      for(genvar i = 0; i < 2; i++) begin
          assign sq_input[i].store_size        = store_size_input[i];
          assign sq_input[i].store_data        = store_data_input[i];
          assign sq_input[i].store_data_valid  = store_data_valid_input[i];
          assign sq_input[i].store_ROB_idx     = store_ROB_idx_input[i];
          assign sq_input[i].store_enable      = store_enable_input[i];

          assign sq_input[i].CDB_Data          = CDB_Data[i];
          assign sq_input[i].CDB_PRF_idx       = CDB_PRF_idx[i];
          assign sq_input[i].CDB_valid         = CDB_valid[i];

          assign sq_input[i].ALU_ROB_idx       = ALU_ROB_idx[i];
          assign sq_input[i].ALU_is_valid      = (ALU_is_valid[i] & ALU_is_ls[i]);
          assign sq_input[i].ALU_data          = ALU_data[i];
      end
  endgenerate

    store_queue sq(
        .clock(clock),
        .reset(reset),
        .squash(squash),
        .store_retire(store_retire),
        .sq_input(sq_input),
        .sq_head,
        .sq_tail,


        .sq_head_output_valid(sq_head_output_valid),
        .sq_head_output_data(sq_head_output_data),    
        .sq_head_output_address(sq_head_output_address),
        .sq_head_output_size(sq_head_output_size),
        
        .sq_out(sq_entries),
        .num_free(sq_free_number)
    );

    assign dcache_write_enable    = (store_retire == 1) ? sq_head_output_valid : 0;
    assign dcache_write_data      = (store_retire == 1) ? sq_head_output_data  : 0;
    assign dcache_write_size      = (store_retire == 1) ? sq_head_output_size  : 0;

    assign dcache_write_offset    = (store_retire == 1) ? sq_head_output_address[2:0]  : 0;
    assign dcache_write_idx       = (store_retire == 1) ? sq_head_output_address[7:3]  : 0;
    assign dcache_write_tag       = (store_retire == 1) ? sq_head_output_address[15:8] : 0;
endmodule