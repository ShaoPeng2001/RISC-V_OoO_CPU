`include "sys_defs.svh"

module LQ(
    input                                       clock,
    input                                       reset,
    input                                       squash,

    input lq_store_packet [`LSQSZ-1:0]          lq_store_input,
    input                                       mem_dcache_write_enable,
    
    input [$clog2(`LSQSZ)-1:0]                  sq_head,
    input [1:0] [$clog2(`LSQSZ)-1:0]            sq_tail,

    input lq_dispatch_packet [1:0]              lq_dispatch_input,

    input [`LSQSZ-1:0]                          dcache_response,
    input [31:0]                                dcache_data,                // 在同一個cycle從Dcache得到的訊號

    input [`LSQSZ-1:0]                          memory_response,
    input [31:0]                                memory_data,       

    output logic [$clog2(`LSQSZ):0]             lq_free_space_output,

    output logic [`LSQSZ-1:0]                   data_cache_gnt,
    output logic [`LSQSZ-1:0]                   CDB_lq_forward_available,

    output lq_out_packet [`LSQSZ-1:0]           lq_out
  );

    logic [`LSQSZ-1:0] [31:0]                   store_data;
    logic [`LSQSZ-1:0]                          store_data_valid;
    logic [`LSQSZ-1:0] [15:0]                   store_addr;
    logic [`LSQSZ-1:0]                          store_address_valid;
    logic [`LSQSZ-1:0] [1:0]                    store_size;
    logic [`LSQSZ-1:0]                          store_valid;

    // dispatch load指令進到load queue
    logic [1:0] [1:0]                           dispatched_load_size;
    logic [1:0]                                 dispatched_load_enable;
    logic [1:0] [$clog2(`ROB)-1:0]              dispatched_ROB_idx;
    logic [1:0] [$clog2(`PRF)-1:0]              dispatched_PRF_idx;
    logic [1:0]                                 dispatched_load_sign;

    // 進到load queue的ALU訊號
    logic [1:0] [$clog2(`ROB)-1:0]              ALU_ROB_idx;
    logic [1:0]                                 ALU_is_valid;
    logic [1:0]                                 ALU_for_address;
    logic [1:0] [15:0]                          ALU_data;

    logic [`LSQSZ-1:0] [31:0]                   lq_data;
    logic [`LSQSZ-1:0] [15:0]                   lq_addr;
    logic [`LSQSZ-1:0] [$clog2(`PRF)-1:0]       lq_PRF_idx;
    logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0]       lq_ROB_idx;
    logic [`LSQSZ-1:0]                          lq_signed;
    logic [`LSQSZ-1:0] [1:0]                    lq_size;


  // store input packet
  generate
      for(genvar i = 0; i < `LSQSZ; i++) begin
          assign store_data[i]           = lq_store_input[i].store_data;
          assign store_data_valid[i]     = lq_store_input[i].store_data_valid;
          assign store_addr[i]           = lq_store_input[i].store_addr;
          assign store_address_valid[i]  = lq_store_input[i].store_address_valid;
          assign store_size[i]           = lq_store_input[i].store_size;
          assign store_valid[i]          = lq_store_input[i].store_valid;
      end
  endgenerate


  generate
      for(genvar i = 0; i < 2; i++) begin
          assign dispatched_load_size[i]   = lq_dispatch_input[i].dispatched_load_size;
          assign dispatched_load_enable[i] = lq_dispatch_input[i].dispatched_load_enable;
          assign dispatched_ROB_idx[i]     = lq_dispatch_input[i].dispatched_ROB_idx;
          assign dispatched_PRF_idx[i]     = lq_dispatch_input[i].dispatched_PRF_idx;
          assign dispatched_load_sign[i]   = lq_dispatch_input[i].dispatched_load_sign;

          assign ALU_ROB_idx[i]            = lq_dispatch_input[i].ALU_ROB_idx;
          assign ALU_is_valid[i]           = lq_dispatch_input[i].ALU_is_valid;
          assign ALU_for_address[i]        = lq_dispatch_input[i].ALU_for_address;
          assign ALU_data[i]               = lq_dispatch_input[i].ALU_data;
      end
  endgenerate


  generate
      for(genvar i = 0; i < `LSQSZ; i++) begin
          assign lq_out[i].lq_data     = lq_data[i];
          assign lq_out[i].lq_addr     = lq_addr[i];
          assign lq_out[i].lq_ROB_idx  = lq_ROB_idx[i];
          assign lq_out[i].lq_PRF_idx  = lq_PRF_idx[i];
          assign lq_out[i].lq_signed   = lq_signed[i];
          assign lq_out[i].lq_size     = lq_size[i];
      end
  endgenerate


  // load queue 的訊號
  logic [`LSQSZ-1:0]                        ld_free;
  logic [`LSQSZ-1:0]                        lq_addr_valid;

  logic [$clog2(`LSQSZ):0]                  lq_num_free;

  logic [`LSQSZ-1:0] [$clog2(`LSQSZ)-1:0]   sq_tail_prev;

  //  dispatch load指令進到load queue
  logic [`LSQSZ-1:0] [1:0]                  load_size_input;
  logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0]     load_ROB_index_input;
  logic [`LSQSZ-1:0] [$clog2(`PRF)-1:0]     load_PRF_index_input;
  logic [`LSQSZ-1:0]                        load_enable_input;
  logic [`LSQSZ-1:0]                        load_signed_input;
  logic [$clog2(2):0]                       dispatched_number;

  logic [`LSQSZ-1:0] [$clog2(`LSQSZ)-1:0]   sq_tail_input;

  // load queue的狀態
  logic [`LSQSZ-1:0]                        load_waiting_position;
  logic [`LSQSZ-1:0]                        load_finish_position;


  // ALU input address
  logic [1:0] [`LSQSZ-1:0]                  ALU_address_hit;
  logic [`LSQSZ-1:0] [15:0]                 lq_address_update;
  logic [`LSQSZ-1:0] [15:0]                 lq_address_forward;

  logic [`LSQSZ-1:0]                        lq_address_valid_update;
  logic [`LSQSZ-1:0]                        lq_address_valid_forward;

  // dispatch number是根據dispatch stage來決定
  always_comb begin
      case(dispatched_load_enable)
          2'b00:begin
              dispatched_number = 0;
          end
          2'b01:begin
              dispatched_number = 1;
          end
          2'b10:begin
              dispatched_number = 1;
          end
          2'b11:begin
              dispatched_number = 2;
          end
          default:begin
              dispatched_number = 0;
          end
      endcase
  end


  logic [(`LSQSZ*2)-1:0] gnt_bus;


  lq_psel_gen #(.WIDTH(`LSQSZ), .REQS(2)) input_position_selector 
  (
    .req(ld_free),
    .gnt_bus(gnt_bus)
  );


  logic [`LSQSZ-1:0] available_input_position_1;
  logic [`LSQSZ-1:0] available_input_position_2;


  generate
      for(genvar i = 0; i < `LSQSZ; i++) begin
          assign available_input_position_1[i] = (gnt_bus[i] == 1) ? 1 : 0;
          assign available_input_position_2[i] = (gnt_bus[i + `LSQSZ] == 1) ? 1 : 0;
      end
  endgenerate


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(available_input_position_1[i]) begin
              load_size_input[i] = dispatched_load_size[0];
          end else if(available_input_position_2[i]) begin
              load_size_input[i] = dispatched_load_size[1];
          end else begin
              load_size_input[i] = 0;
          end
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(available_input_position_1[i]) begin
              load_ROB_index_input[i] = dispatched_ROB_idx[0];
          end else if(available_input_position_2[i]) begin
              load_ROB_index_input[i] = dispatched_ROB_idx[1];
          end else begin
              load_ROB_index_input[i] = 0;
          end
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(available_input_position_1[i]) begin
              load_PRF_index_input[i] = dispatched_PRF_idx[0];
          end else if(available_input_position_2[i]) begin
              load_PRF_index_input[i] = dispatched_PRF_idx[1];
          end else begin
              load_PRF_index_input[i] = 0;
          end
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(available_input_position_1[i]) begin
              load_enable_input[i] = dispatched_load_enable[0];
          end else if(available_input_position_2[i]) begin
              load_enable_input[i] = dispatched_load_enable[1];
          end else begin
              load_enable_input[i] = 0;
          end
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(available_input_position_1[i]) begin
              load_signed_input[i] = dispatched_load_sign[0];
          end else if(available_input_position_2[i]) begin
              load_signed_input[i] = dispatched_load_sign[1];
          end else begin
              load_signed_input[i] = 0;
          end
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(available_input_position_1[i]) begin
              sq_tail_input[i] = sq_tail[0];
          end else if(available_input_position_2[i]) begin
              sq_tail_input[i] = sq_tail[1];
          end else begin
              sq_tail_input[i] = 0;
          end
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++)begin
          ALU_address_hit[0][i] = ((ld_free[i] == 0) && ALU_is_valid[0] && ALU_for_address[0] && (lq_addr_valid[i] == 0) && (ALU_ROB_idx[0] == lq_ROB_idx[i])) ? 1 : 0;
          ALU_address_hit[1][i] = ((ld_free[i] == 0) && ALU_is_valid[1] && ALU_for_address[1] && (lq_addr_valid[i] == 0) && (ALU_ROB_idx[1] == lq_ROB_idx[i])) ? 1 : 0;
      end
  end

  always_comb begin
    for(int i = 0; i < `LSQSZ; i++) begin
      lq_address_forward[i]        = (ALU_address_hit[0][i] || ALU_address_hit[1][i]) ? (ALU_address_hit[0][i] ? ALU_data[0] : ALU_data[1]) : 0;
      lq_address_valid_forward[i]  = (ALU_address_hit[0][i] || ALU_address_hit[1][i]) ? 1 : 0;
    end
  end

  assign lq_address_update        = lq_addr | lq_address_forward;
  assign lq_address_valid_update  = lq_addr_valid | lq_address_valid_forward;


  logic [`LSQSZ-1:0] [`LSQSZ-1:0] lsq_address_range_hit;

  logic [`LSQSZ-1:0] [`LSQSZ-1:0] lsq_address_offset_hit;
  logic [`LSQSZ-1:0] [`LSQSZ-1:0] lsq_address_size_hit;

  logic [`LSQSZ-1:0] [`LSQSZ-1:0] lsq_address_total_hit;
  logic [`LSQSZ-1:0] [`LSQSZ-1:0] lsq_address_total;



  logic [`LSQSZ-1:0] [`LSQSZ-1:0] age_logic_mask;
  logic [`LSQSZ-1:0]              after_head_region;
  logic [`LSQSZ-1:0] [`LSQSZ-1:0] before_tail_region;
  logic [`LSQSZ-1:0]              sq_head_over_tail;
  logic [`LSQSZ-1:0]              load_ready_position;

  logic [`LSQSZ-1:0] [`LSQSZ-1:0] ls_all_hit_age_logic_mask;

  logic [`LSQSZ-1:0] [`LSQSZ-1:0] available_address_hit;
  logic [`LSQSZ-1:0] [`LSQSZ-1:0] youngest_address_location;
  logic [`LSQSZ-1:0]              lsq_forward_available;
  logic [`LSQSZ-1:0] [`LSQSZ-1:0] lsq_address_forward_one_hot;

  load_queue_status [`LSQSZ-1:0] state, next_state;


//////////////////////////////////////////////////
//                                              //
//             address hit logic                //
//                                              //
//////////////////////////////////////////////////

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          for(int j = 0; j < `LSQSZ; j++) begin
              lsq_address_size_hit[i][j]    = (lq_size[i] == store_size[j]) ? 1 : 0;
              lsq_address_offset_hit[i][j]  = (lq_addr[i][2:0] == store_addr[j][2:0]) ? 1 : 0;
          end
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          for(int j = 0; j < `LSQSZ; j++) begin
              lsq_address_range_hit[i][j]   = (((lq_addr[i][15:3] == store_addr[j][15:3]) | (lq_addr_valid[i] == 0) | (store_address_valid[j] == 0)) && (ld_free[i] == 0) && store_valid[j]) ? 1 : 0;
              lsq_address_total[i][j]       = (lq_addr_valid[i] && store_data_valid[j] && store_address_valid[j]) ? 1 : 0;
          end
      end
  end

  assign lsq_address_total_hit = (lsq_address_range_hit & lsq_address_offset_hit & lsq_address_size_hit & lsq_address_total);

//////////////////////////////////////////////////
//                                              //
//                 age_logic                    //
//                                              //
//////////////////////////////////////////////////

  // age logic是load queue用來forward store queue或memory data的訊號
  // 用來記錄他是否比store queue head還要舊
  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          after_head_region[i] = (i >= sq_head) ? 1 : 0;
      end
  end

  // 當每個load 指令被dispatch進load queue，用來找出目前store queue tail的位置
  // 紀錄他是否比store queue 的tail還要新
  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          for(int j = 0; j < `LSQSZ; j++) begin
              before_tail_region[i][j] = (j < sq_tail_prev[i]) ? 1 : 0;
          end
      end
  end

  // 如果store queue裡的head比tail還要前面，紀錄這個訊號
  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          sq_head_over_tail[i] = (sq_head > sq_tail_prev[i]) ? 1 : 0;
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          // 如果head位置在tail後面
          if(sq_head_over_tail[i]) begin
              age_logic_mask[i] = (before_tail_region[i] | after_head_region);
          end else begin 
              // 正常的情況（head 和 tail是正常的順序）
              age_logic_mask[i] = (before_tail_region[i] & after_head_region);
          end
      end
  end

//////////////////////////////////////////////////
//                                              //
//               lq_gnt_position                //
//                                              //
//////////////////////////////////////////////////

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(sq_head_over_tail[i]) begin  
              if(lsq_address_range_hit[i] & before_tail_region[i]) begin
                  available_address_hit[i] = lsq_address_range_hit[i] & before_tail_region[i];
              end else begin
                  available_address_hit[i] = lsq_address_range_hit[i] & after_head_region;
              end
          end else begin
              available_address_hit[i] = lsq_address_range_hit[i] & age_logic_mask[i];
          end
      end
  end


  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(age_logic_mask[i] & youngest_address_location[i] & lsq_address_total_hit[i]) begin
              lsq_forward_available[i] = 1;
          end else begin
              lsq_forward_available[i] = 0;
          end 
      end
  end

  wand_sel #(.WIDTH(`LSQSZ)) youngest_age_selector [`LSQSZ-1:0] 
  (
    .req(available_address_hit),
    .gnt(youngest_address_location)
  );


  position_arbiter #(.WIDTH(`LSQSZ)) 
  CDB_selector (
               .clock(clock),
               .reset(reset),
               .req(load_finish_position),
               .gnt(CDB_lq_forward_available)
              );

  assign lsq_address_forward_one_hot = youngest_address_location & lsq_address_total_hit & age_logic_mask;

//////////////////////////////////////////////////
//                                              //
//            output for data cache             //
//                                              //
//////////////////////////////////////////////////

  logic dcache_miss;

  position_arbiter #(.WIDTH(`LSQSZ)) data_cache_selector (
               .clock(clock),
               .reset(reset),
               .req(load_ready_position),
               .gnt(data_cache_gnt)
             );

  assign dcache_miss = (dcache_response == 0) ? 1 : 0;

//////////////////////////////////////////////////
//                                              //
//               FSM for load queue             //
//                                              //
//////////////////////////////////////////////////

  always_ff @(posedge clock) begin
      if(reset || squash) begin
          state <= 0;
      end else begin
          state <= next_state;
      end
  end


  always_comb begin
      for (int i = 0; i < `LSQSZ; i++) begin
          case(state[i])
              // 維持在同一個stage直到forwarding或address是valid
              WAIT_READY: begin   
                  if ((youngest_address_location[i] == 0) & (~ld_free[i]) & lq_addr_valid[i] & (mem_dcache_write_enable == 0)) begin
                      next_state[i] = WAIT_CACHE;
                  end else if (lsq_forward_available[i]) begin
                      next_state[i] = WAIT_CDB;
                  end else begin
                      next_state[i] = WAIT_READY;
                  end
              end
              // 到Dcache load 資料
              WAIT_CACHE: begin  
              // 如果Dcache miss就去memory拿
                  if (data_cache_gnt[i] && dcache_miss && (mem_dcache_write_enable == 0))begin
                      //if (dcache_miss)
                      next_state[i] = WAIT_MEMORY_RESPONSE;
                  end else if(data_cache_gnt[i]) begin
                      // get required data from memory
                      next_state[i] = WAIT_CDB;
                  end else begin
                      next_state[i] = WAIT_CACHE;
                  end
              end
              WAIT_MEMORY_RESPONSE: begin
              // 如果memory 有回應 就準備到CDB broadcast   
                  if (memory_response[i]) begin
                      next_state[i] = WAIT_CDB;
                  end else begin
                      next_state[i] = WAIT_MEMORY_RESPONSE;
                  end
              end
              // 等待CDB 有空間來broadcast loaded data
              WAIT_CDB: begin    
                  if (CDB_lq_forward_available[i]) begin
                      next_state[i] = WAIT_READY;
                  end else begin
                      next_state[i] = WAIT_CDB;
                  end
              end
              // default value
              default: begin
                  next_state[i] = WAIT_READY;
              end
          endcase
        end
      end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          load_waiting_position[i]    = (state[i] == WAIT_MEMORY_RESPONSE) ? 1 : 0;
          load_ready_position[i]      = (state[i] == WAIT_CACHE && (mem_dcache_write_enable == 0)) ? 1 : 0;
          load_finish_position[i]     = (state[i] == WAIT_CDB) ? 1 : 0;
      end
  end


//////////////////////////////////////////////////
//                                              //
//        space management in load queue        //
//                                              //
//////////////////////////////////////////////////

  logic CDB_free_space; 

  assign CDB_free_space = (CDB_lq_forward_available != 0) ? 1 : 0;

  assign lq_free_space_output  = lq_num_free - dispatched_number + CDB_free_space;

  // always_ff
  logic [`LSQSZ-1:0] load_free_clear;
  logic [`LSQSZ-1:0] ld_free_next;

  assign load_free_clear  = ld_free | CDB_lq_forward_available;
  assign ld_free_next     = (ld_free | CDB_lq_forward_available) & (~load_enable_input);

  logic [`LSQSZ-1:0] [1:0]                load_size_next;
  logic [`LSQSZ-1:0] [31:0]               load_data_next;
  logic [`LSQSZ-1:0] [15:0]               load_address_next;
  logic [`LSQSZ-1:0]                      load_ready_address_next;

  logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0]   load_ROB_idx_next;
  logic [`LSQSZ-1:0] [$clog2(`PRF)-1:0]   load_PRF_idx_next;
  logic [`LSQSZ-1:0]                      load_signed_next;
  logic [`LSQSZ-1:0] [$clog2(`LSQSZ)-1:0] sq_tail_prev_next;

  logic [`LSQSZ-1:0] [31:0]               data_from_processor;
  logic [`LSQSZ-1:0] [31:0]               data_from_dcache;
  logic [`LSQSZ-1:0] [31:0]               data_from_memory;
  wor   [`LSQSZ-1:0] [31:0]               data_from_store_queue;

  always_ff @ (posedge clock) begin
      if (reset | squash) begin
          ld_free         <= {`LSQSZ{1'b1}};
          lq_num_free     <= `LSQSZ;
      end else begin
          ld_free         <= ld_free_next;
          lq_num_free     <= lq_free_space_output;
      end
  end

  always_ff @ (posedge clock) begin
      if (reset | squash) begin
          lq_addr_valid   <= 0;
          lq_addr         <= 0;
          lq_data         <= 0;
      end else begin
          lq_addr_valid   <= load_ready_address_next;
          lq_addr         <= load_address_next;
          lq_data         <= load_data_next;
      end
  end

  assign load_ready_address_next = lq_address_valid_update & (~ld_free_next);
  
  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(load_free_clear[i] && load_enable_input[i]) begin
              load_size_next[i] = load_size_input[i];
          end else if(load_free_clear[i] && !load_enable_input[i]) begin
              load_size_next[i] = 0;
          end else begin
              load_size_next[i] = lq_size[i];
          end
      end
  end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(load_free_clear[i] && load_enable_input[i]) begin
              load_ROB_idx_next[i] = load_ROB_index_input[i];
          end else if(load_free_clear[i] && !load_enable_input[i]) begin
              load_ROB_idx_next[i] = 0;
          end else begin
              load_ROB_idx_next[i] = lq_ROB_idx[i];
          end
      end
  end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(load_free_clear[i] && load_enable_input[i]) begin
              load_PRF_idx_next[i] = load_PRF_index_input[i];
          end else if(load_free_clear[i] && !load_enable_input[i]) begin
              load_PRF_idx_next[i] = 0;
          end else begin
              load_PRF_idx_next[i] = lq_PRF_idx[i];
          end
      end
  end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
        if(load_free_clear[i] && load_enable_input[i]) begin
            load_signed_next[i] = load_signed_input[i];
        end else if(load_free_clear[i] && !load_enable_input[i]) begin
            load_signed_next[i] = 0;
        end else begin
            load_signed_next[i] = lq_signed[i];
        end
      end
  end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(ld_free_next[i]) begin
              load_address_next[i] = 0;
          end else begin
              load_address_next[i] = lq_address_update[i];
          end
      end
  end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(load_free_clear[i] && load_enable_input[i]) begin
              sq_tail_prev_next[i] = sq_tail_input[i];      
          end else if (load_free_clear[i] && !load_enable_input[i]) begin
              sq_tail_prev_next[i] = 0;
          end else begin
              sq_tail_prev_next[i] = sq_tail_prev[i];
          end
      end
  end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(CDB_lq_forward_available[i] | lsq_forward_available[i] | dcache_response[i] | memory_response[i]) begin
              data_from_processor[i] = 0;
          end else begin
              data_from_processor[i] = lq_data[i];
          end
      end
  end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(dcache_response[i]) begin
              data_from_dcache[i] = dcache_data;
          end else begin
              data_from_dcache[i] = 0;
          end
      end
  end

  always_comb begin
      for(int i = 0; i < `LSQSZ; i++) begin
          if(memory_response[i] && load_waiting_position[i]) begin
              data_from_memory[i] = memory_data;
          end else begin
              data_from_memory[i] = 0;
          end
      end
  end

  generate
      for(genvar i = 0; i < `LSQSZ; i++) begin
          for(genvar j = 0; j < `LSQSZ; j++) begin
              assign data_from_store_queue[i] = lsq_address_forward_one_hot[i][j] ? store_data[j] : 0;
          end
      end
  endgenerate

  assign load_data_next = data_from_processor | data_from_dcache | data_from_memory | data_from_store_queue;


  always_ff @ (posedge clock) begin
      if (reset | squash) begin
          lq_size         <= 0;
          lq_ROB_idx      <= 0;
          lq_PRF_idx      <= 0;
          lq_signed       <= 0;
          sq_tail_prev    <= 0;
      end else begin
          lq_size         <= load_size_next;
          lq_ROB_idx      <= load_ROB_idx_next;
          lq_PRF_idx      <= load_PRF_idx_next;
          lq_signed       <= load_signed_next;
          sq_tail_prev     <= sq_tail_prev_next;
      end
  end
endmodule

module lq_psel_gen #(parameter WIDTH, REQS) (
    input wire [WIDTH-1:0]       req,

    output wand [WIDTH*REQS-1:0] gnt_bus
);

    // Internal stuff
    wire  [WIDTH*REQS-1:0]  tmp_reqs;
    wire  [WIDTH*REQS-1:0]  tmp_reqs_rev;
    wire  [WIDTH*REQS-1:0]  tmp_gnts;
    wire  [WIDTH*REQS-1:0]  tmp_gnts_rev;

    wor [WIDTH-1:0]         gnt;
    wire                    empty;

    assign empty = ~(|req);

    genvar j, k;

    for (j = 0; j < REQS; j++)begin
        if (j == 0) begin
            assign tmp_reqs[WIDTH-1:0]  = req[WIDTH-1:0];
            assign gnt_bus[WIDTH-1:0]   = tmp_gnts[WIDTH-1:0];
        end else if (j == 1) begin
            for (k = 0; k < WIDTH; k++)begin
                assign tmp_reqs[2*WIDTH-1-k] = req[k];
            end
            assign gnt_bus[2*WIDTH-1 -: WIDTH] = tmp_gnts_rev[2*WIDTH-1 -: WIDTH] & ~tmp_gnts[WIDTH-1:0];
        end else begin    
            assign tmp_reqs[(j+1)*WIDTH-1 -: WIDTH] = tmp_reqs[(j-1)*WIDTH-1 -: WIDTH] &
                                                        ~tmp_gnts[(j-1)*WIDTH-1 -: WIDTH];

            if (j % 2 == 0)
                assign gnt_bus[(j+1)*WIDTH-1 -: WIDTH] = tmp_gnts[(j+1)*WIDTH-1 -: WIDTH];
            else
                assign gnt_bus[(j+1)*WIDTH-1 -: WIDTH] = tmp_gnts_rev[(j+1)*WIDTH-1 -: WIDTH];
        end

        wand_sel #(WIDTH) psel (.req(tmp_reqs[(j+1)*WIDTH-1 -: WIDTH]), .gnt(tmp_gnts[(j+1)*WIDTH-1 -: WIDTH]));

        for (k = 0; k < WIDTH; k++)begin
            assign tmp_gnts_rev[(j+1)*WIDTH-1-k] = tmp_gnts[(j)*WIDTH+k];
        end

        for (k = j + 1; k < REQS; k = k + 2)begin
            assign gnt_bus[(k+1)*WIDTH-1 -: WIDTH] = ~gnt_bus[(j+1)*WIDTH-1 -: WIDTH];
        end
    end


    for(k = 0; k < REQS; k++)begin
        assign gnt = gnt_bus[(k+1)*WIDTH-1 -: WIDTH];
    end

endmodule // psel_gen


module position_arbiter #(parameter WIDTH = 16) (
    input clock,
    input reset,
    input [WIDTH-1:0] req,
    output wire [WIDTH-1:0] gnt
);
reg [WIDTH-1:0] reg_update;
wand [WIDTH-1:0] new_mask;

wire  [WIDTH-1:0] req_front;
wand  [WIDTH-1:0] gnt_front;

wire  [WIDTH-1:0] req_back;
wand  [WIDTH-1:0] gnt_back;

wire [WIDTH-1:0] final_req;
wire [WIDTH-1:0] gnt_front_result;
wire [WIDTH-1:0] gnt_back_result;

assign final_req = reg_update & req;

//priority selector
genvar i;

for (i = 0; i < WIDTH; i++) begin
    assign req_front[WIDTH-1-i]         = final_req[i];
    assign gnt_front_result[WIDTH-1-i]  = gnt_front[i];
end

for (i = 0; i < WIDTH-1 ; i++) begin
    assign gnt_front [WIDTH-1:i] = {{(WIDTH-1-i){~req_front[i]}},req_front[i]};
end
  
assign gnt_front[WIDTH-1] = req_front[WIDTH-1];


for (i = 0; i < WIDTH; i++) begin
    assign req_back[WIDTH-1-i]          = req[i];
    assign gnt_back_result[WIDTH-1-i]   = gnt_back[i];
end

for (i = 0; i < WIDTH-1 ; i++) begin
    assign gnt_back [WIDTH-1:i] = {{(WIDTH-1-i){~req_back[i]}},req_back[i]};
end

assign gnt_back[WIDTH-1] = req_back[WIDTH-1];

generate;
    assign new_mask = {WIDTH{1'b1}};
    for (i = 0; i < WIDTH; i++) begin
        assign new_mask[i:0] = {(i+1){gnt[i]}};
    end
endgenerate

assign gnt = gnt_front_result ? gnt_front_result : gnt_back_result;


always_ff @ (posedge clock) begin
    if (reset) begin
        reg_update <= {WIDTH{1'b1}};
    end
    else begin
        reg_update <= new_mask;
    end
end
endmodule