`include "sys_defs.svh"
module dcache(
    input                       clock,
    input                       reset, 
    input dcache_input_packet   dcache_input,

    output logic [63:0]         dcache_read_data_out,
    output logic [`LSQSZ-1:0]   dcache_read_response,
    output logic [31:0] [63:0]  dcache_data,
    output logic [31:0] [7:0]   dcache_tags,
    output logic [31:0]         dcache_dirty_bit,
    output logic [31:0]         dcache_valid_bit,
    output logic [1:0] [12:0]   victim_tags,
    output logic [1:0] [63:0]   victim_data,
    output logic [1:0]          victim_valid,
    output logic [1:0]          victim_dirty,
    output dcache_output_packet dcache_out
);

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

    assign write_dcache_enable = dcache_input.write_dcache_enable;
    assign write_dcache_offset = dcache_input.write_dcache_offset;
    assign write_dcache_index  = dcache_input.write_dcache_index;
    assign write_dcache_tag    = dcache_input.write_dcache_tag;
    assign write_dcache_data   = dcache_input.write_dcache_data;
    assign write_dcache_size   = dcache_input.write_dcache_size;

    assign memory_dcache_write_enable   = dcache_input.memory_dcache_write_enable;
    assign memory_dcache_write_index    = dcache_input.memory_dcache_write_index;
    assign memory_dcache_write_tag      = dcache_input.memory_dcache_write_tag;
    assign memory_dcache_write_data     = dcache_input.memory_dcache_write_data;

    assign read_dcache_enable   = dcache_input.read_dcache_enable;
    assign read_dcache_offset   = dcache_input.read_dcache_offset;
    assign read_dcache_index    = dcache_input.read_dcache_index;
    assign read_dcache_tag      = dcache_input.read_dcache_tag;
    assign read_dcache_size     = dcache_input.read_dcache_size;
    assign read_dcache_pos_gnt  = dcache_input.read_dcache_pos_gnt;

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

    assign dcache_out.write_back_enable_out     = write_back_enable_out;
    assign dcache_out.write_back_address_out    = write_back_address_out;
    assign dcache_out.write_back_data_out       = write_back_data_out;
    assign dcache_out.write_back_size_out       = write_back_size_out;

    assign dcache_out.write_enable_out          = write_enable_out;
    assign dcache_out.write_address_out         = write_address_out;
    assign dcache_out.write_data_out            = write_data_out;
    assign dcache_out.write_size_out            = write_size_out;

    assign dcache_out.read_dcache_enable_out    = read_dcache_enable_out;
    assign dcache_out.read_dcache_address_out   = read_dcache_address_out;
    assign dcache_out.read_dcache_size_out      = read_dcache_size_out;
    assign dcache_out.read_dcache_pos_gnt_out   = read_dcache_pos_gnt_out;

    logic [31:0] [63:0] read_data;
    logic [31:0] [7:0]  tags; 
    logic [31:0]        valid;
    logic [31:0]        dirty;
    logic               victim_lru;

    logic [63:0] BYTE_MASK;
    logic [63:0] HALF_MASK;
    logic [63:0] WORD_MASK;
    logic [63:0] DOUBLE_MASK;

    assign BYTE_MASK    = {56'b0, {8{1'b1}}};
    assign HALF_MASK    = {48'b0, {16{1'b1}}};
    assign WORD_MASK    = {32'b0, {32{1'b1}}};
    assign DOUBLE_MASK  = {64{1'b1}};

    logic [5:0] read_shift;
    logic [5:0] write_shift;

    assign dcache_data  = read_data;
    assign dcache_tags  = tags;
    assign dcache_valid_bit = valid;
    assign dcache_dirty_bit = dirty;

    assign read_shift = {read_dcache_offset, 3'b0};
    assign write_shift = {write_dcache_offset, 3'b0};


    logic [63:0] read_data_cache;


    logic [63:0] write_size_mask;
    logic [63:0] write_size_mask_pre;
    logic [63:0] read_size_mask;


    logic [31:0] [7:0]  tags_after_write; 
    logic [31:0]        valid_bit_after_write;
    logic [31:0]        dirty_bit_after_write;

    logic [31:0] [7:0]  tags_after_read; 
    logic [31:0]        valid_bit_after_read;
    logic [31:0]        dirty_bit_after_read;


    logic [31:0] [7:0]  tags_after_req; 
    logic [31:0]        valid_bit_after_req;
    logic [31:0]        dirty_bit_after_req;

    logic [1:0] [12:0]  victim_tags_after_write;
    logic [1:0] [63:0]  victim_data_after_write;
    logic [1:0]         victim_valid_bit_after_write;
    logic [1:0]         victim_dirty_bit_after_write;
    logic               victim_LRU_after_write;

    logic [1:0] [12:0]  victim_tags_after_read;
    logic [1:0] [63:0]  victim_data_after_read;
    logic [1:0]         victim_valid_bit_after_read;
    logic [1:0]         victim_dirty_bit_after_read;
    logic               victim_LRU_after_read;

    logic [1:0] [12:0]  victim_tags_after_req;
    logic [1:0] [63:0]  victim_data_after_req;
    logic [1:0]         victim_valid_bit_after_req;
    logic [1:0]         victim_dirty_bit_after_req;
    logic               victim_LRU_after_req;


    logic               change_dirty_bit_after_write;
    logic [63:0]        change_data_after_write;
    logic [7:0]         change_tag_after_write;

    logic               change_dirty_bit_after_read;
    logic [63:0]        change_data_after_read;
    logic [7:0]         change_tag_after_read;

    logic               dcache_read_hit;
    logic [1:0]         victim_read_already_exist;
    logic               victim_read_hit;

    logic               dcache_write_hit;
    logic [1:0]         victim_write_already_exist;
    logic               victim_write_hit;

    logic               memory_cache_same;

    logic [31:0] [7:0]  tags_next;
    assign tags_next = tags_after_req;

    logic [31:0]        valid_bit_next;
    assign valid_bit_next = valid_bit_after_req;

    logic [31:0]        dirty_bit_next;
    assign dirty_bit_next = dirty_bit_after_req;

    logic [1:0] [12:0]  victim_tags_next;
    assign victim_tags_next = victim_tags_after_req;

    logic [1:0] [63:0]  victim_data_next;
    assign victim_data_next = victim_data_after_req;

    logic [1:0]         victim_valid_bit_next;
    assign victim_valid_bit_next = victim_valid_bit_after_req;

    logic [1:0]         victim_dirty_bit_next;
    assign victim_dirty_bit_next = victim_dirty_bit_after_req;

    logic               victim_LRU_next;
    assign victim_LRU_next = victim_LRU_after_req;


    always_comb begin
        case (write_dcache_size)
            BYTE:      write_size_mask_pre = BYTE_MASK;
            HALF:      write_size_mask_pre = HALF_MASK;
            WORD:      write_size_mask_pre = WORD_MASK;
            default:   write_size_mask_pre = DOUBLE_MASK;
        endcase
    end

    assign write_size_mask = write_size_mask_pre << write_shift;

    always_comb begin
        case (read_dcache_size)
            BYTE:      read_size_mask = BYTE_MASK;
            HALF:      read_size_mask = HALF_MASK;
            WORD:      read_size_mask = WORD_MASK;
            default:   read_size_mask = DOUBLE_MASK;
        endcase
    end


    always_comb begin
        if(valid_bit_after_read[memory_dcache_write_index] && (memory_dcache_write_tag == tags_after_read[memory_dcache_write_index])) begin
            memory_cache_same = 1;
        end
        else if(victim_valid_bit_after_read[0] && {memory_dcache_write_tag, memory_dcache_write_index} == victim_tags_after_read[0]) begin
            memory_cache_same = 1;
        end
        else if(victim_valid_bit_after_read[1] && {memory_dcache_write_tag, memory_dcache_write_index} == victim_tags_after_read[1]) begin
            memory_cache_same = 1;
        end
        else begin
            memory_cache_same = 0;
        end
    end

    assign read_data_cache = (read_data[read_dcache_index] >> read_shift) & read_size_mask;

    assign dcache_read_hit = tags_after_write[read_dcache_index] == read_dcache_tag && valid_bit_after_write[read_dcache_index];
    assign victim_read_hit = (victim_read_already_exist[0] || victim_read_already_exist[1]) != 0;
    assign victim_read_already_exist[0] = victim_valid_bit_after_write[0] && (victim_tags_after_write[0] == {read_dcache_tag,read_dcache_index});
    assign victim_read_already_exist[1] = victim_valid_bit_after_write[1] && (victim_tags_after_write[1] == {read_dcache_tag,read_dcache_index});
    assign victim_write_already_exist[0] = victim_valid[0] && (victim_tags[0] == {write_dcache_tag, write_dcache_index});
    assign victim_write_already_exist[1] = victim_valid[1] && (victim_tags[1] == {write_dcache_tag, write_dcache_index});


    //write hit
    assign dcache_write_hit = (tags[write_dcache_index] == write_dcache_tag) && valid[write_dcache_index];
    assign victim_write_hit = (victim_write_already_exist[0] || victim_write_already_exist[1]) != 0;

    logic [63:0] data_after_write_pre_clear;
    logic [1:0] [63:0] victim_write_pre_clear;

    assign data_after_write_pre_clear = read_data[write_dcache_index] & ~write_size_mask;
    assign victim_write_pre_clear[0] = victim_data[0] & ~write_size_mask;
    assign victim_write_pre_clear[1] = victim_data[1] & ~write_size_mask;


    logic rd_we, wr_we, req_we;

    logic [4:0] read_addr;
    logic [4:0] write_addr;
    logic [4:0] req_addr;

    logic [63:0] rd_data_in;
    logic [63:0] wr_data_in;
    logic [63:0] req_data_in;

    logic           we;
    logic [4:0]     waddr;
    logic [63:0]    wdata;

    assign we       = rd_we | wr_we | req_we;
    assign waddr    = read_addr | write_addr | req_addr;
    assign wdata    = rd_data_in | wr_data_in | req_data_in;

    logic [31:0] [4:0] raddr;

    generate
        for(genvar i = 0; i < 32; i++) begin
            assign raddr[i] = i;
        end
    endgenerate

    memDP #(
        .WIDTH     ($bits(MEM_BLOCK)),
        .DEPTH     (`ICACHE_LINES),
        .READ_PORTS(32),
        .BYPASS_EN (0))
    dcache_mem (
        .clock(clock),
        .reset(reset),
        .re   ({32{1'b1}}),
        .raddr(raddr),
        .rdata(read_data),
        .we   (we),
        .waddr(waddr),
        .wdata(wdata)
    );

    // dcache write logic
    always_comb begin
        tags_after_write                = tags; 
        valid_bit_after_write           = valid;
        dirty_bit_after_write           = dirty;

        change_data_after_write         = 0;
        change_dirty_bit_after_write    = 0;
        change_tag_after_write          = 0;

        wr_we                           = 0;
        write_addr                      = 0;
        wr_data_in                      = 0;

        if (write_dcache_enable && dcache_write_hit) begin
            dirty_bit_after_write[write_dcache_index]    = 1'b1;
            wr_we                                       = 1'b1;
            write_addr                                  = write_dcache_index;
            wr_data_in                                  = data_after_write_pre_clear | (write_size_mask & (write_dcache_data << write_shift));
        end
        else if (write_dcache_enable && victim_write_hit) begin
            case(victim_write_already_exist)
                2'b01: begin
                    change_data_after_write           = victim_write_pre_clear[0] | (write_size_mask & (write_dcache_data << write_shift));
                    change_dirty_bit_after_write      = 1'b1;
                    change_tag_after_write            = victim_tags[0][12:5];                    
                end

                2'b10: begin
                    change_data_after_write           = victim_write_pre_clear[1] | (write_size_mask & (write_dcache_data << write_shift));
                    change_dirty_bit_after_write      = 1'b1;
                    change_tag_after_write            = victim_tags[1][12:5];
                end
            endcase
            tags_after_write[write_dcache_index]             = change_tag_after_write;
            dirty_bit_after_write[write_dcache_index]        = change_dirty_bit_after_write;
            valid_bit_after_write[write_dcache_index]        = 1'b1;

            wr_we                                            = 1;
            write_addr                                       = write_dcache_index;
            wr_data_in                                       = change_data_after_write;
        end
    end

    // data cache read
    always_comb begin
        tags_after_read = tags_after_write;
        valid_bit_after_read = valid_bit_after_write;
        dirty_bit_after_read = dirty_bit_after_write;

        change_data_after_read = 0;
        change_dirty_bit_after_read = 0;
        change_tag_after_read = 0;

        dcache_read_data_out = 0;
        dcache_read_response = 0;

        rd_we                = 0;
        read_addr            = 0;
        rd_data_in           = 0;

            if (read_dcache_enable && dcache_read_hit) begin
                dcache_read_data_out     = read_data_cache;
                dcache_read_response = read_dcache_pos_gnt;
            end
            else if (read_dcache_enable && victim_read_hit) begin

                case(victim_read_already_exist)
                    2'b01: begin
                        change_data_after_read        = victim_data_after_write[0];
                        change_dirty_bit_after_read   = victim_dirty_bit_after_write[0];
                        change_tag_after_read         = victim_tags_after_write[0][12:5];

                        dcache_read_data_out                 = (victim_data_after_write[0] >> read_shift) & read_size_mask;
                        dcache_read_response             = read_dcache_pos_gnt;
                    end

                    2'b10: begin
                        change_data_after_read        = victim_data_after_write[1];
                        change_dirty_bit_after_read   = victim_dirty_bit_after_write[1];
                        change_tag_after_read         = victim_tags_after_write[1][12:5];

                        dcache_read_data_out                 = (victim_data_after_write[1] >> read_shift) & read_size_mask;
                        dcache_read_response             = read_dcache_pos_gnt;
                    end
                endcase

                valid_bit_after_read[read_dcache_index]  = 1'b1;
                dirty_bit_after_read[read_dcache_index]  = change_dirty_bit_after_read;
                tags_after_read[read_dcache_index]       = change_tag_after_read;
                rd_we                                    = 1'b1;
                read_addr                                = read_dcache_index;
                rd_data_in                               = change_data_after_read;

            end
    end

    // memory access dcache
    always_comb begin
        tags_after_req = tags_after_read;
        valid_bit_after_req = valid_bit_after_read;
        dirty_bit_after_req = dirty_bit_after_read;

        req_we              = 0;
        req_addr            = 0;
        req_data_in         = 0;

        if (memory_dcache_write_enable) begin
            if (memory_cache_same) begin
            end
            else if (~valid_bit_after_read[memory_dcache_write_index]) begin
                tags_after_req[memory_dcache_write_index]         = memory_dcache_write_tag;
                valid_bit_after_req[memory_dcache_write_index]    = 1'b1;
                dirty_bit_after_req[memory_dcache_write_index]    = 1'b0;

                req_we                                            = 1'b1;
                req_addr                                          = memory_dcache_write_index;
                req_data_in                                       = memory_dcache_write_data;
            end
            else if (victim_valid_bit_after_read != 2'b11) begin
                tags_after_req[memory_dcache_write_index]         = memory_dcache_write_tag;
                valid_bit_after_req[memory_dcache_write_index]    = 1'b1;
                dirty_bit_after_req[memory_dcache_write_index]    = 1'b0;

                req_we                                            = 1'b1;
                req_addr                                          = memory_dcache_write_index;
                req_data_in                                       = memory_dcache_write_data;
            end
            else begin
                tags_after_req[memory_dcache_write_index]         = memory_dcache_write_tag;
                valid_bit_after_req[memory_dcache_write_index]    = 1'b1;
                dirty_bit_after_req[memory_dcache_write_index]    = 1'b0;
                req_we                                            = 1'b1;
                req_addr                                          = memory_dcache_write_index;
                req_data_in                                       = memory_dcache_write_data;
            end
        end
    end

    always_comb begin
        victim_tags_after_write       = victim_tags;
        victim_data_after_write       = victim_data;
        victim_valid_bit_after_write  = victim_valid;
        victim_dirty_bit_after_write  = victim_dirty;
        victim_LRU_after_write        = victim_lru;

        if(write_dcache_enable && victim_write_hit) begin
            victim_LRU_after_write    = ~victim_write_already_exist[0];
            case(victim_write_already_exist)
                2'b01: begin
                    victim_data_after_write[0]        = read_data[write_dcache_index];
                    victim_dirty_bit_after_write[0]   = dirty[write_dcache_index];
                    victim_tags_after_write[0]        = {tags[write_dcache_index], write_dcache_index};
                    victim_valid_bit_after_write[0]   = valid[write_dcache_index];                 
                end
                2'b10: begin
                    victim_data_after_write[1]        = read_data[write_dcache_index];
                    victim_dirty_bit_after_write[1]   = dirty[write_dcache_index];
                    victim_tags_after_write[1]        = {tags[write_dcache_index], write_dcache_index};
                    victim_valid_bit_after_write[1]   = valid[write_dcache_index];
                end
            endcase
        end
    end

    always_comb begin
        victim_tags_after_read = victim_tags_after_write;
        victim_data_after_read = victim_data_after_write;
        victim_valid_bit_after_read = victim_valid_bit_after_write;
        victim_dirty_bit_after_read = victim_dirty_bit_after_write;
        victim_LRU_after_read = victim_LRU_after_write;

        if(read_dcache_enable && victim_read_hit) begin
            victim_LRU_after_read = ~victim_read_already_exist[0];
            case(victim_read_already_exist)
                2'b01: begin
                    victim_data_after_read[0]     = read_data[read_dcache_index];
                    victim_dirty_bit_after_read[0]    = dirty_bit_after_write[read_dcache_index];
                    victim_valid_bit_after_read[0]    = valid_bit_after_write[read_dcache_index];
                    victim_tags_after_read[0]     = {tags_after_write[read_dcache_index], read_dcache_index};
                end

                2'b10: begin
                    victim_data_after_read[1]     = read_data[read_dcache_index];
                    victim_dirty_bit_after_read[1]    = dirty_bit_after_write[read_dcache_index];
                    victim_valid_bit_after_read[1]    = valid_bit_after_write[read_dcache_index];
                    victim_tags_after_read[1]     = {tags_after_write[read_dcache_index], read_dcache_index};
                end

            endcase
        end
    end

    always_comb begin
        victim_tags_after_req = victim_tags_after_read;
        victim_data_after_req = victim_data_after_read;
        victim_valid_bit_after_req = victim_valid_bit_after_read;
        victim_dirty_bit_after_req = victim_dirty_bit_after_read;
        victim_LRU_after_req = victim_LRU_after_read;

        if(memory_dcache_write_enable && !memory_cache_same && valid_bit_after_read[memory_dcache_write_index] && victim_valid_bit_after_read != 2'b11) begin
            case(victim_valid_bit_after_read)
                2'b00: begin
                    victim_tags_after_req[0]         = {tags_after_read[memory_dcache_write_index], memory_dcache_write_index};
                    victim_data_after_req[0]         = read_data[memory_dcache_write_index];
                    victim_valid_bit_after_req[0]    = valid_bit_after_read[memory_dcache_write_index];
                    victim_dirty_bit_after_req[0]    = dirty_bit_after_read[memory_dcache_write_index];
                    victim_LRU_after_req             = 1;                
                end
                2'b01: begin
                    victim_tags_after_req[1]         = {tags_after_read[memory_dcache_write_index], memory_dcache_write_index};
                    victim_data_after_req[1]         = read_data[memory_dcache_write_index];
                    victim_valid_bit_after_req[1]    = valid_bit_after_read[memory_dcache_write_index];
                    victim_dirty_bit_after_req[1]    = dirty_bit_after_read[memory_dcache_write_index];
                    victim_LRU_after_req             = 0;   
                end
                2'b10: begin
                    victim_tags_after_req[0]         = {tags_after_read[memory_dcache_write_index], memory_dcache_write_index};
                    victim_data_after_req[0]         = read_data[memory_dcache_write_index];
                    victim_valid_bit_after_req[0]    = valid_bit_after_read[memory_dcache_write_index];
                    victim_dirty_bit_after_req[0]    = dirty_bit_after_read[memory_dcache_write_index];
                    victim_LRU_after_req             = 1;

                end
            endcase        
        end
        else if(memory_dcache_write_enable && !memory_cache_same && valid_bit_after_read[memory_dcache_write_index] && victim_valid_bit_after_read == 2'b11) begin
            victim_data_after_req[victim_LRU_after_read]         = read_data[memory_dcache_write_index];
            victim_tags_after_req[victim_LRU_after_read]         = {tags_after_read[memory_dcache_write_index], memory_dcache_write_index};
            victim_valid_bit_after_req[victim_LRU_after_read]    = valid_bit_after_read[memory_dcache_write_index];
            victim_dirty_bit_after_req[victim_LRU_after_read]    = dirty_bit_after_read[memory_dcache_write_index];
            victim_LRU_after_req                           = ~victim_LRU_after_read;        
        end    
    end

    always_comb begin
        write_enable_out   = (write_dcache_enable && !dcache_write_hit && !victim_write_hit) ? 1'b1 : 1'b0;
        write_address_out  = (write_dcache_enable && !dcache_write_hit && !victim_write_hit) ? {write_dcache_tag, write_dcache_index, write_dcache_offset} : 1'b0;
        write_data_out     = (write_dcache_enable && !dcache_write_hit && !victim_write_hit) ? write_dcache_data : 1'b0;
        write_size_out     = (write_dcache_enable && !dcache_write_hit && !victim_write_hit) ? write_dcache_size : 1'b0;
    end

    always_comb begin
        read_dcache_enable_out    = (read_dcache_enable && !dcache_read_hit && !victim_read_hit) ? 1'b1 : 0;
        read_dcache_address_out   = (read_dcache_enable && !dcache_read_hit && !victim_read_hit) ? {read_dcache_tag, read_dcache_index, read_dcache_offset} : 0;
        read_dcache_pos_gnt_out   = (read_dcache_enable && !dcache_read_hit && !victim_read_hit) ? read_dcache_pos_gnt : 0;
        read_dcache_size_out      = (read_dcache_enable && !dcache_read_hit && !victim_read_hit) ? read_dcache_size : 0;
    end

    always_comb begin
        write_back_enable_out   = (memory_dcache_write_enable && !memory_cache_same && valid_bit_after_read[memory_dcache_write_index] && victim_valid_bit_after_read == 2'b11) ? ((victim_dirty_bit_after_read[victim_LRU_after_read] == 1) ? 1'b1 : 0) : 0;
        write_back_address_out  = (memory_dcache_write_enable && !memory_cache_same && valid_bit_after_read[memory_dcache_write_index] && victim_valid_bit_after_read == 2'b11) ? ((victim_dirty_bit_after_read[victim_LRU_after_read] == 1) ? {victim_tags_after_read[victim_LRU_after_read], 3'b0} : 0) : 0;
        write_back_data_out     = (memory_dcache_write_enable && !memory_cache_same && valid_bit_after_read[memory_dcache_write_index] && victim_valid_bit_after_read == 2'b11) ? ((victim_dirty_bit_after_read[victim_LRU_after_read] == 1) ? victim_data_after_read[victim_LRU_after_read] : 0) : 0;
        write_back_size_out     = (memory_dcache_write_enable && !memory_cache_same && valid_bit_after_read[memory_dcache_write_index] && victim_valid_bit_after_read == 2'b11) ? ((victim_dirty_bit_after_read[victim_LRU_after_read] == 1) ? DOUBLE : 0) : 0;
    end


    always_ff @(posedge clock) begin
        if (reset) begin
            tags    <= 0; 
            valid   <= 0;
            dirty   <= 0;
        end
        else begin
            tags    <= tags_next; 
            valid   <= valid_bit_next;
            dirty   <= dirty_bit_next;
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            victim_tags     <= 0;
            victim_data     <= 0;
            victim_valid    <= 0;
            victim_dirty    <= 0;
            victim_lru      <= 0;
        end
        else begin
            victim_tags     <= victim_tags_next;
            victim_data     <= victim_data_next;
            victim_valid    <= victim_valid_bit_next;
            victim_dirty    <= victim_dirty_bit_next;
            victim_lru      <= victim_LRU_next;
        end
    end
endmodule
