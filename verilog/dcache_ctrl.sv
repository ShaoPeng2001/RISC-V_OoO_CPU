`include "sys_defs.svh"

module dcache_memory_fifo(
    input                       clock,
    input                       reset,
    input                       squash,    

    input dcache_request_packet dcache_request_input,

    // response from memory
    input [3:0]                 mem2proc_transaction_tag,
	input [63:0]                mem2proc_data,    
	input [3:0]                 mem2proc_data_tag,     

    // signals go to memory
    output logic [1:0]            data_memory_command, 
    output logic [15:0]         data_memory_address,
    output logic [1:0]            data_memory_size,
    output logic [63:0]          data_memory_data,

    // signals back from memory
    output logic [`LSQSZ-1:0]     mem_response,
    output logic [31:0]           mem_data,
    
    output memory_dcache_packet memory_dcache_signals,
    output dcache_bus_packet    dcache_bus_out

);

    parameter Length = 2 * `LSQSZ;

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

    assign write_back_input         = dcache_request_input.write_back_input;
    assign write_back_address_input = dcache_request_input.write_back_address_input;
    assign write_back_data_input    = dcache_request_input.write_back_data_input;
    assign write_back_size_input    = dcache_request_input.write_back_size_input;
    
    assign write_enable_input       = dcache_request_input.write_enable_input;
    assign write_address_input      = dcache_request_input.write_address_input;
    assign write_data_input         = dcache_request_input.write_data_input;
    assign write_size_input         = dcache_request_input.write_size_input;

    assign read_enable_input        = dcache_request_input.read_enable_input;
    assign read_address_input       = dcache_request_input.read_address_input;
    assign read_gnt_input           = dcache_request_input.read_gnt_input;
    assign read_size_input          = dcache_request_input.read_size_input;

    logic                memory_write_enable;
    logic [4:0]          memory_write_idx;
    logic [7:0]          memory_write_tag;
    logic [63:0]         memory_write_data;

    assign memory_dcache_signals.memory_write_enable = memory_write_enable;
    assign memory_dcache_signals.memory_write_idx    = memory_write_idx;
    assign memory_dcache_signals.memory_write_tag    = memory_write_tag;
    assign memory_dcache_signals.memory_write_data   = memory_write_data;

    logic                bus_valid_incoming;
    logic [15:0]         bus_address_incoming;
    logic                bus_write_incoming;
    logic [63:0]         bus_data_incoming;
    logic [1:0]          bus_size_incoming;
    logic [15:0] [15:0]  bus_req_fifo_address;
    logic [15:0] [63:0]  bus_req_fifo_data;    
    logic [15:0]         bus_req_fifo_write;
    logic [15:0]         bus_req_fifo_read;
    logic [15:0] [1:0]   bus_req_fifo_size;

    assign dcache_bus_out.bus_valid_incoming    = bus_valid_incoming;
    assign dcache_bus_out.bus_address_incoming  = bus_address_incoming;
    assign dcache_bus_out.bus_write_incoming    = bus_write_incoming;
    assign dcache_bus_out.bus_data_incoming     = bus_data_incoming;
    assign dcache_bus_out.bus_size_incoming     = bus_size_incoming;
    assign dcache_bus_out.bus_req_fifo_address  = bus_req_fifo_address;
    assign dcache_bus_out.bus_req_fifo_data     = bus_req_fifo_data;
    assign dcache_bus_out.bus_req_fifo_write    = bus_req_fifo_write;
    assign dcache_bus_out.bus_req_fifo_read     = bus_req_fifo_read;
    assign dcache_bus_out.bus_req_fifo_size     = bus_req_fifo_size;

    logic                 incoming_new_write;
    logic                 incoming_new_read;
    logic [15:0]          incoming_new_address;
    logic [63:0]          incoming_new_data;
    logic [1:0]           incoming_new_size;
    logic [`LSQSZ-1:0]    incoming_new_read_response;
    logic                 incoming_new_valid;

    logic [Length-1:0] [15:0]       req_fifo_address;
    logic [Length-1:0]              req_fifo_write;
    logic [Length-1:0]              req_fifo_read;
    logic [Length-1:0] [1:0]        req_fifo_size;
    logic [Length-1:0] [`LSQSZ-1:0] req_fifo_read_response;
    logic [Length-1:0] [63:0]       req_fifo_data;

    assign bus_valid_incoming   = incoming_new_valid;
    assign bus_write_incoming   = incoming_new_write;
    assign bus_data_incoming    = incoming_new_data;
    assign bus_address_incoming = incoming_new_address;
    assign bus_req_fifo_address = req_fifo_address;
    assign bus_req_fifo_write   = req_fifo_write;
    assign bus_req_fifo_read    = req_fifo_read;
    assign bus_req_fifo_size    = req_fifo_size;
    assign bus_size_incoming    = incoming_new_size;
    assign bus_req_fifo_data    = req_fifo_data;

    logic [`LSQSZ-1:0]              mem_fifo_write;
    logic [`LSQSZ-1:0]              mem_fifo_read;
    logic [`LSQSZ-1:0] [`LSQSZ-1:0] mem_fifo_read_response;
    logic [`LSQSZ-1:0] [15:0]       mem_fifo_address;
    logic [`LSQSZ-1:0] [3:0]        mem_fifo_tag;
    logic [`LSQSZ-1:0] [1:0]        mem_fifo_size;

    logic [15:0]                    req_fifo_head_address;
    logic                           req_fifo_head_write;
    logic                           req_fifo_head_read;
    logic [1:0]                     req_fifo_head_size;
    logic [`LSQSZ-1:0]              req_fifo_head_read_response;
    logic [63:0]                    req_fifo_head_data;

    logic [15:0]        mem_fifo_head_address;
    logic               mem_fifo_head_write;
    logic               mem_fifo_head_read;
    logic [`LSQSZ-1:0]  mem_fifo_head_read_response;
    logic [3:0]         mem_fifo_head_tag;
    logic [1:0]         mem_fifo_head_size;

    logic [Length-1:0] req_fifo_head;
    logic [Length-1:0] req_fifo_tail;

    logic [`LSQSZ-1:0] mem_fifo_head;
    logic [`LSQSZ-1:0] mem_fifo_tail;

    logic [`LSQSZ-1:0]      mem_response_next;
    logic [31:0]            memory_data_next;

    logic [5:0]             mem_data_offset;
    logic [63:0]            mem_data_size_mask;
    logic [63:0]            memory_data_received;

    assign mem_data_offset = {mem_fifo_head_address[2:0], 3'b0};

    logic [Length-1:0] reset_head_position;
    logic [Length-1:0] reset_tail_position;

    assign reset_head_position = {{(Length-1){1'b0}}, 1'b1};
    assign reset_tail_position = {{(Length-1){1'b0}}, 1'b1};

    logic mem_fifo_head_mem_response;
    logic mem_fifo_retire;

    assign mem_fifo_retire = (mem_fifo_head_tag == mem2proc_data_tag) && (mem2proc_data_tag != 0);
    assign mem_fifo_head_mem_response = (mem_fifo_head_tag == mem2proc_data_tag) & mem_fifo_head_read;


    logic [`LSQSZ-1:0] [15:0] transaction_address_next;
    logic [`LSQSZ-1:0] write_transaction_next;
    logic [`LSQSZ-1:0] read_transaction_next;
    logic [`LSQSZ-1:0] [`LSQSZ-1:0] read_response_next;
    logic [`LSQSZ-1:0] [3:0] tag_transaction_next;
    logic [`LSQSZ-1:0] [1:0] size_transaction_next;


    logic               mem_fifo_write_head_next;
    logic               mem_fifo_read_head_next;
    logic [`LSQSZ-1:0]  mem_fifo_read_response_next;
    logic [15:0]        mem_fifo_head_address_next;
    logic [3:0]         mem_fifo_head_tag_next;
    logic [1:0]         mem_fifo_head_size_next;

    logic [`LSQSZ-1:0]  mem_transaction_fifo;
    logic [`LSQSZ-1:0]  mem_transaction_fifo_head_next;
    logic [`LSQSZ-1:0]  mem_transaction_tail_next;
    logic               incoming_transaction; 
    logic               mem_transaction_fifo_empty;

    logic [`LSQSZ-1:0]  mem_fifo_head_move;
    logic [`LSQSZ-1:0]  mem_fifo_tail_move;

    assign mem_fifo_head_move = {mem_fifo_head[`LSQSZ-2:0], mem_fifo_head[`LSQSZ-1]};
    assign mem_fifo_tail_move = {mem_fifo_tail[`LSQSZ-2:0], mem_fifo_tail[`LSQSZ-1]};

    wor [$clog2(`LSQSZ)-1:0]     head_location;
    logic [`LSQSZ-1:0]          head_valid;

    assign mem_transaction_fifo_empty       = (mem_fifo_head == mem_fifo_tail) ? 1 : 0;
    assign incoming_transaction             = req_fifo_head_read;

    assign mem_transaction_fifo             = mem_fifo_retire ? mem_fifo_head_move : mem_fifo_head;
    assign mem_transaction_fifo_head_next   = mem_transaction_fifo_empty ? mem_fifo_head : (mem_fifo_retire ? mem_fifo_head_move : mem_fifo_head);
    assign mem_transaction_tail_next        = incoming_transaction ? mem_fifo_tail_move : mem_fifo_tail;

    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign head_location = (mem_transaction_fifo_head_next[i] == 1) ? i : 0;
            assign head_valid[i] = (mem_transaction_fifo_head_next[i] == 1) ? 1 : 0;
        end
    endgenerate

    always_comb begin
        mem_fifo_write_head_next     = (head_valid[head_location] == 1) ? write_transaction_next[head_location]     : 0;
        mem_fifo_read_head_next      = (head_valid[head_location] == 1) ? read_transaction_next[head_location]      : 0;
        mem_fifo_read_response_next  = (head_valid[head_location] == 1) ? read_response_next[head_location]         : 0;
        mem_fifo_head_address_next   = (head_valid[head_location] == 1) ? transaction_address_next[head_location]   : 0;
        mem_fifo_head_tag_next       = (head_valid[head_location] == 1) ? tag_transaction_next[head_location]       : 0;
        mem_fifo_head_size_next      = (head_valid[head_location] == 1) ? size_transaction_next[head_location]      : 0;    
    end
        
    logic [`LSQSZ-1:0] [15:0]       retire_transaction_address;
    logic [`LSQSZ-1:0]              retire_transaction_write;
    logic [`LSQSZ-1:0]              retire_transaction_read;
    logic [`LSQSZ-1:0] [`LSQSZ-1:0] retire_transaction_response;
    logic [`LSQSZ-1:0] [3:0]        retire_transaction_tag;
    logic [`LSQSZ-1:0] [1:0]        retire_transaction_size;

    logic [`LSQSZ-1:0] [15:0]       incoming_transaction_address;
    logic [`LSQSZ-1:0]              incoming_transaction_write;
    logic [`LSQSZ-1:0]              incoming_transaction_read;
    logic [`LSQSZ-1:0] [`LSQSZ-1:0] incoming_transaction_response;
    logic [`LSQSZ-1:0] [3:0]        incoming_transaction_tag;
    logic [`LSQSZ-1:0] [1:0]        incoming_transaction_size;

    logic [`LSQSZ-1:0] [$clog2(`LSQSZ)-1:0]     head_retire_location;
    logic [`LSQSZ-1:0]                          head_retire_valid;

    logic [`LSQSZ-1:0] [$clog2(`LSQSZ)-1:0]     tail_incoming_location;
    logic [`LSQSZ-1:0]                          tail_incoming_valid;

    generate
        for(genvar i = 0; i < `LSQSZ; i = i + 1) begin
            assign head_retire_location[i]  = (mem_fifo_retire & mem_fifo_head[i]) ? i : 0;
            assign head_retire_valid[i]     = (mem_fifo_retire & mem_fifo_head[i]) ? 1 : 0;
        end
    endgenerate

    generate
        for(genvar i = 0; i < `LSQSZ; i = i + 1) begin
            assign tail_incoming_location[i]    = (incoming_transaction & mem_fifo_tail[i]) ? i : 0;
            assign tail_incoming_valid[i]       = (incoming_transaction & mem_fifo_tail[i]) ? 1 : 0;
        end
    endgenerate


    logic [`LSQSZ-1:0] [15:0] head_transaction_address_next;
    logic [`LSQSZ-1:0] head_write_transaction_next;
    logic [`LSQSZ-1:0] head_read_transaction_next;
    logic [`LSQSZ-1:0] [`LSQSZ-1:0] head_read_response_next;
    logic [`LSQSZ-1:0] [3:0] head_tag_transaction_next;
    logic [`LSQSZ-1:0] [1:0] head_size_transaction_next;

    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign head_transaction_address_next[i] = (mem_fifo_retire & mem_fifo_head[i]) ? 0 : mem_fifo_address[i];
            assign head_write_transaction_next[i]   = (mem_fifo_retire & mem_fifo_head[i]) ? 0 : mem_fifo_write[i];
            assign head_read_transaction_next[i]    = (mem_fifo_retire & mem_fifo_head[i]) ? 0 : (mem_fifo_read[i] & ~squash);
            assign head_read_response_next[i]       = (mem_fifo_retire & mem_fifo_head[i]) ? 0 : mem_fifo_read_response[i];
            assign head_tag_transaction_next[i]     = (mem_fifo_retire & mem_fifo_head[i]) ? 0 : mem_fifo_tag[i];
            assign head_size_transaction_next[i]    = (mem_fifo_retire & mem_fifo_head[i]) ? 0 : mem_fifo_size[i];
        end
    endgenerate

    logic [`LSQSZ-1:0] [15:0] tail_transaction_address_next;
    logic [`LSQSZ-1:0] tail_write_transaction_next;
    logic [`LSQSZ-1:0] tail_read_transaction_next;
    logic [`LSQSZ-1:0] [`LSQSZ-1:0] tail_read_response_next;
    logic [`LSQSZ-1:0] [3:0] tail_tag_transaction_next;
    logic [`LSQSZ-1:0] [1:0] tail_size_transaction_next;

    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign tail_transaction_address_next[i] = (incoming_transaction & mem_fifo_tail[i]) ? req_fifo_head_address : 0;
            assign tail_write_transaction_next[i]   = (incoming_transaction & mem_fifo_tail[i]) ? req_fifo_head_write : 0;
            assign tail_read_transaction_next[i]    = (incoming_transaction & mem_fifo_tail[i]) ? (req_fifo_head_read & ~squash) : 0;
            assign tail_read_response_next[i]       = (incoming_transaction & mem_fifo_tail[i]) ? req_fifo_head_read_response : 0;
            assign tail_tag_transaction_next[i]     = (incoming_transaction & mem_fifo_tail[i]) ? mem2proc_transaction_tag : 0;
            assign tail_size_transaction_next[i]    = (incoming_transaction & mem_fifo_tail[i]) ? req_fifo_head_size : 0;
        end
    endgenerate

    assign transaction_address_next = head_transaction_address_next | tail_transaction_address_next;
    assign write_transaction_next   = head_write_transaction_next | tail_write_transaction_next;
    assign read_transaction_next    = head_read_transaction_next | tail_read_transaction_next;
    assign read_response_next       = head_read_response_next | tail_read_response_next;
    assign tag_transaction_next     = head_tag_transaction_next | tail_tag_transaction_next;
    assign size_transaction_next    = head_size_transaction_next | tail_size_transaction_next;

    always_ff @(posedge clock) begin
        if(reset) begin
            mem_fifo_head <= `LSQSZ'b1;
            mem_fifo_tail <= `LSQSZ'b1;
        end
        else begin
            mem_fifo_head <= mem_transaction_fifo_head_next;
            mem_fifo_tail <= mem_transaction_tail_next;
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            mem_fifo_address        <= 0;
            mem_fifo_write          <= 0;
            mem_fifo_read           <= 0;
            mem_fifo_read_response  <= 0;
            mem_fifo_tag            <= 0;
            mem_fifo_size           <= 0;

        end
        else begin
            mem_fifo_address        <= transaction_address_next;
            mem_fifo_write          <= write_transaction_next;
            mem_fifo_read           <= read_transaction_next;
            mem_fifo_read_response  <= read_response_next;
            mem_fifo_tag            <= tag_transaction_next;
            mem_fifo_size           <= size_transaction_next;

        end
    end

    always_ff @(posedge clock) begin
        if(reset) begin
            mem_fifo_head_address       <= 0;
            mem_fifo_head_write         <= 0;
            mem_fifo_head_read          <= 0;
            mem_fifo_head_read_response <= 0;
            mem_fifo_head_tag           <= 0;
            mem_fifo_head_size          <= 0;
        end

        else begin
            mem_fifo_head_address       <= mem_fifo_head_address_next;
            mem_fifo_head_write         <= mem_fifo_write_head_next;
            mem_fifo_head_read          <= mem_fifo_read_head_next;
            mem_fifo_head_read_response <= mem_fifo_read_response_next;
            mem_fifo_head_tag           <= mem_fifo_head_tag_next;
            mem_fifo_head_size          <= mem_fifo_head_size_next;
        end

    end

    logic   write_back_request;
    logic   write_request;
    logic   read_request;

    always_comb begin
        write_back_request  = write_back_input;
        write_request       = write_enable_input;
        read_request        = read_enable_input;
    end

    logic                    incoming_new_write_next;
    logic                    incoming_new_read_next;
    logic [15:0]             incoming_new_address_next;
    logic [63:0]             incoming_new_data_next;
    logic [1:0]              incoming_new_size_next;
    logic [`LSQSZ-1:0]       incoming_new_read_response_next;
    logic                    incoming_new_valid_next;

    always_comb begin
        if(write_back_request) begin
            incoming_new_valid_next = write_back_request;
        end
        else if(write_request) begin
            incoming_new_valid_next = write_request;
        end
        else if(read_request) begin
            incoming_new_valid_next = read_request;
        end
        else begin
            incoming_new_valid_next = 0;
        end

    end

    always_comb begin
        if(write_back_request) begin
            incoming_new_write_next = write_back_input;
        end
        else if(write_request) begin
            incoming_new_write_next = write_enable_input;
        end
        else begin
            incoming_new_write_next = 0;
        end

    end

    always_comb begin
        if(write_back_request) begin
            incoming_new_address_next = write_back_address_input;
        end
        else if(write_request) begin
            incoming_new_address_next = write_address_input;
        end
        else if(read_request) begin
            incoming_new_address_next = read_address_input;
        end
        else begin
            incoming_new_address_next = 0;
        end
    end

    always_comb begin
        if(write_back_request) begin
            incoming_new_size_next = DOUBLE;
        end
        else if(write_request) begin
            incoming_new_size_next = write_size_input;
        end
        else if(read_request) begin
            incoming_new_size_next = read_size_input;
        end
        else begin
            incoming_new_size_next = 0;
        end
    end

    always_comb begin
        if(read_request) begin
            incoming_new_read_response_next = read_gnt_input;
        end
        else begin
            incoming_new_read_response_next = `LSQSZ'b0;
        end
    end
        

    always_comb begin
        if(write_back_request) begin
            incoming_new_data_next = write_back_data_input;
        end
        else if(write_request) begin
            incoming_new_data_next = write_data_input;
        end
        else begin
            incoming_new_data_next = 64'b0;
        end

    end

    always_comb begin
        if(read_request) begin
            incoming_new_read_next = (read_enable_input & ~squash);
        end
        else begin
            incoming_new_read_next = 0;
        end
    end


    always_ff @(posedge clock) begin
        if (reset) begin
            incoming_new_write          <= 0;
            incoming_new_read           <= 0;
            incoming_new_address        <= 0;
            incoming_new_data           <= 0;
            incoming_new_size           <= 0;
            incoming_new_read_response  <= 0;
            incoming_new_valid          <= 0;
        end
        else begin
            incoming_new_write          <= incoming_new_write_next;
            incoming_new_read           <= incoming_new_read_next;
            incoming_new_address        <= incoming_new_address_next;
            incoming_new_data           <= incoming_new_data_next;
            incoming_new_size           <= incoming_new_size_next;
            incoming_new_read_response  <= incoming_new_read_response_next;
            incoming_new_valid          <= incoming_new_valid_next;
        end
    end


    wor [Length-1:0]                req_fifo_write_next;
    wor [Length-1:0]                req_fifo_read_next;
    wor [Length-1:0] [63:0]         req_fifo_data_next;
    wor [Length-1:0] [`LSQSZ-1:0]   req_fifo_read_response_next;
    wor [Length-1:0] [15:0]         req_fifo_address_next;
    wor [Length-1:0] [1:0]          req_fifo_size_next;

    logic                           req_fifo_head_write_next;
    logic                           req_fifo_head_read_next;
    logic [63:0]                    req_fifo_head_data_next;
    logic [`LSQSZ-1:0]              req_fifo_head_response_next;
    logic [15:0]                    req_fifo_head_address_next;
    logic [1:0]                     req_fifo_head_size_next;


    logic [Length-1:0]              req_fifo_head_next;
    logic [Length-1:0]              req_fifo_tail_next;
    logic                           req_fifo_empty;


    assign req_fifo_empty                       = (req_fifo_head == req_fifo_tail);
    assign req_fifo_head_next                   = req_fifo_empty ? req_fifo_head : {req_fifo_head[Length-2:0], req_fifo_head[Length-1]};

    assign req_fifo_tail_next                   = incoming_new_valid ? {req_fifo_tail[Length-2:0], req_fifo_tail[Length-1]} : req_fifo_tail;

    wor [$clog2(Length)-1:0]    req_fifo_head_location;
    logic [Length-1:0]          req_fifo_head_valid;

    generate
        for(genvar i = 0; i < Length; i++) begin
            assign req_fifo_head_location   = (req_fifo_head_next[i] == 1) ? i : 0;
            assign req_fifo_head_valid[i]   = (req_fifo_head_next[i] == 1) ? 1 : 0;
        end
    endgenerate

    always_comb begin
        req_fifo_head_address_next  = (req_fifo_head_valid[req_fifo_head_location]) ? req_fifo_address_next[req_fifo_head_location] : 0;
        req_fifo_head_write_next    = (req_fifo_head_valid[req_fifo_head_location]) ? req_fifo_write_next[req_fifo_head_location] : 0;
        req_fifo_head_read_next     = (req_fifo_head_valid[req_fifo_head_location]) ? req_fifo_read_next[req_fifo_head_location] : 0;
        req_fifo_head_response_next = (req_fifo_head_valid[req_fifo_head_location]) ? req_fifo_read_response_next[req_fifo_head_location] : 0;
        req_fifo_head_size_next     = (req_fifo_head_valid[req_fifo_head_location]) ? req_fifo_size_next[req_fifo_head_location] : 0;
        req_fifo_head_data_next     = (req_fifo_head_valid[req_fifo_head_location]) ? req_fifo_data_next[req_fifo_head_location] : 0;
    end

    generate
    // req fifo head clear 
        for (genvar i = 0; i < Length; i++) begin
            assign req_fifo_data_next[i]            = req_fifo_head[i] ? 0 : req_fifo_data[i];
            assign req_fifo_write_next[i]           = req_fifo_head[i] ? 0 : req_fifo_write[i];
            assign req_fifo_read_next[i]            = req_fifo_head[i] ? 0 : (req_fifo_read[i] & ~squash);
            assign req_fifo_address_next[i]         = req_fifo_head[i] ? 0 : req_fifo_address[i];
            assign req_fifo_read_response_next[i]   = req_fifo_head[i] ? 0 : req_fifo_read_response[i];
            assign req_fifo_size_next[i]            = req_fifo_head[i] ? 0 : req_fifo_size[i];
        end
    // req fifo tail insert
        for (genvar i = 0; i < Length; i++) begin
            assign req_fifo_data_next[i]            = req_fifo_tail[i] ? incoming_new_data : 0;
            assign req_fifo_write_next[i]           = req_fifo_tail[i] ? incoming_new_write : 0;
            assign req_fifo_read_next[i]            = req_fifo_tail[i] ? (incoming_new_read & ~squash) : 0;
            assign req_fifo_address_next[i]         = req_fifo_tail[i] ? incoming_new_address : 0;
            assign req_fifo_read_response_next[i]   = req_fifo_tail[i] ? incoming_new_read_response : 0;
            assign req_fifo_size_next[i]            = req_fifo_tail[i] ? incoming_new_size : 0;
        end
    //end
    endgenerate

    always_ff @(posedge clock) begin
        if(reset) begin
            req_fifo_head   <= reset_head_position;
            req_fifo_tail   <= reset_tail_position;
        end

        else begin
            req_fifo_head <= req_fifo_head_next;
            req_fifo_tail <= req_fifo_tail_next;
        end

    end

    always_ff @(posedge clock) begin
        if(reset) begin
            req_fifo_head_address       <= 0;
            req_fifo_head_write         <= 0;
            req_fifo_head_read          <= 0;
            req_fifo_head_size          <= 0;
            req_fifo_head_read_response <= 0;
            req_fifo_head_data          <= 0;
        end

        else begin
            req_fifo_head_address       <= req_fifo_head_address_next;
            req_fifo_head_write         <= req_fifo_head_write_next;
            req_fifo_head_read          <= req_fifo_head_read_next;
            req_fifo_head_size          <= req_fifo_head_size_next;
            req_fifo_head_read_response <= req_fifo_head_response_next;
            req_fifo_head_data          <= req_fifo_head_data_next;
        end
        
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            req_fifo_address        <= 0;
            req_fifo_write          <= 0;
            req_fifo_read           <= 0;
            req_fifo_size           <= 0;
            req_fifo_read_response  <= 0;
            req_fifo_data           <= 0;

        end
        else begin
            req_fifo_address        <= req_fifo_address_next;
            req_fifo_write          <= req_fifo_write_next;
            req_fifo_read           <= req_fifo_read_next;
            req_fifo_size           <= req_fifo_size_next;
            req_fifo_read_response  <= req_fifo_read_response_next;
            req_fifo_data           <= req_fifo_data_next;
        end
    end


    always_comb begin
        case({req_fifo_head_read, req_fifo_head_write})
            2'b01: begin
                data_memory_command = MEM_STORE;
            end

            2'b10: begin
                data_memory_command = MEM_LOAD;
            end

            default: begin
                data_memory_command = MEM_NONE;
            end
        endcase
    end

    always_comb begin
        case({req_fifo_head_read, req_fifo_head_write})
            2'b01: begin
                data_memory_size = req_fifo_head_size;
            end

            2'b10: begin
                data_memory_size = DOUBLE;
            end
            default: begin
                data_memory_size = 0;
            end
        endcase
    end

    always_comb begin
        if(req_fifo_head_write) begin
            data_memory_address = req_fifo_head_address;
        end
        else begin
            data_memory_address = {req_fifo_head_address[15:3], 3'b0};
        end
    end

    always_comb begin
        if(req_fifo_head_write) begin
            data_memory_data = req_fifo_head_data;
        end
        else begin
            data_memory_data = 0;
        end
    end

    // feedback to lsq & dcache, responds only if is_rd
    assign memory_write_enable  = mem_fifo_head_mem_response;
    assign memory_write_idx     = mem_fifo_head_address[7:3];
    assign memory_write_tag     = mem_fifo_head_address[15:8];
    assign memory_write_data    = mem2proc_data;


    assign mem_response_next = mem_fifo_head_mem_response ? mem_fifo_head_read_response : 0;

    always_comb begin
        case(mem_fifo_head_size)
            BYTE:      mem_data_size_mask = {56'b0, {8{1'b1}}};
            HALF:      mem_data_size_mask = {48'b0, {16{1'b1}}};
            WORD:      mem_data_size_mask = {32'b0, {32{1'b1}}};
            default:   mem_data_size_mask = {64{1'b1}};
        endcase
    end
    assign memory_data_received = (mem2proc_data >> mem_data_offset) & mem_data_size_mask;
    assign memory_data_next     = mem_fifo_head_mem_response ? memory_data_received[31:0] : 0;

    always_ff @(posedge clock) begin
        if (reset) begin
            mem_data        <= 0;
            mem_response    <= 0;
        end
        else begin
            mem_data        <= memory_data_next;
            mem_response    <= mem_response_next;
        end
    end
endmodule
