`include "sys_defs.svh"

module rob(
    input                                        clock,
    input                                        reset,

    input ROB_packet [`N-1:0]                    rob_packet_in,

    input                                        lq_dcache_read_enable,
    input                                        mem_dcache_write_enable,

    output logic [$clog2(`ROB)-1:0]              tail,
    output logic [$clog2(`ROB)-1:0]              next_tail,

    output ROB_out_packet [`N-1:0]               rob_packet_out,

    output logic [$clog2(`ROB):0]                num_free,
    output logic [$clog2(`ROB):0]                next_num_free,
    output logic                                 squash,
    output logic [31:0]                          next_pc,

    output logic [`N-1:0] [31:0]                 target_out,
    output logic [$clog2(`N):0]                  committed_number,
    output logic                                 store_commit
);

    rob_entry [`ROB-1:0]                             rob_current_entry;
    rob_entry [`N-1:0]                               new_rob_entry;

    logic [$clog2(`ROB)-1:0]                         head;
    logic [$clog2(`ROB)-1:0]                         next_head;
    logic [$clog2(`N):0]                             dispatched_number;
    logic                                            store_stall;
    logic                                            tail_reset;

    logic [`N-1:0]                                   DONE;
    logic [`N-1:0]                                   STORE;
    logic [`N-1:0]                                   BRANCH;
    logic [`N-1:0]                                   MISPREDICTED;
    logic [`N-1:0]                                   DIRECTION;
    logic [`N-1:0]                                   VALID;
    logic [`N-1:0]                                   HALT;
    ADDR [`N-1:0]                                    TARGET;
    ADDR [`N-1:0]                                    NPC;
    logic [`N-1:0] [$clog2(`ROB)-1:0]                complete_position;




    assign DONE[0]              =  (STORE[0]) ? ((mem_dcache_write_enable || lq_dcache_read_enable) ? 0 : rob_current_entry[(head + 0) % `ROB].complete) : rob_current_entry[(head + 0) % `ROB].complete;
    assign STORE[0]             = rob_current_entry[(head + 0) % `ROB].is_store;
    assign BRANCH[0]            = rob_current_entry[(head + 0) % `ROB].is_branch;
    assign MISPREDICTED[0]      = rob_current_entry[(head + 0) % `ROB].mispredicted;
    assign DIRECTION[0]         = rob_current_entry[(head + 0) % `ROB].branch_direction;
    assign VALID[0]             = rob_packet_in[0].valid;
    assign TARGET[0]            = rob_current_entry[(head + 0) % `ROB].target;
    assign NPC[0]               = rob_current_entry[(head + 0) % `ROB].PC + 4;
    assign complete_position[0] = rob_packet_in[0].CDB_ROB_idx;

    assign DONE[1]              =  (STORE[1]) ? ((mem_dcache_write_enable || lq_dcache_read_enable) ? 0 : rob_current_entry[(head + 1) % `ROB].complete) : rob_current_entry[(head + 1) % `ROB].complete;
    assign STORE[1]             = rob_current_entry[(head + 1) % `ROB].is_store;
    assign BRANCH[1]            = rob_current_entry[(head + 1) % `ROB].is_branch;
    assign MISPREDICTED[1]      = rob_current_entry[(head + 1) % `ROB].mispredicted;
    assign DIRECTION[1]         = rob_current_entry[(head + 1) % `ROB].branch_direction;
    assign VALID[1]             = rob_packet_in[1].valid;
    assign TARGET[1]            = rob_current_entry[(head + 1) % `ROB].target;
    assign NPC[1]               = rob_current_entry[(head + 1) % `ROB].PC + 4;
    assign complete_position[1] = rob_packet_in[1].CDB_ROB_idx;


    assign next_num_free = (reset || squash) ? `ROB : (num_free - dispatched_number + committed_number);

// store input packet to rob entries
    always_comb begin

        dispatched_number = 0;

        for(int i = 0; i < 2; i++) begin
                new_rob_entry[i].dest_ARN           = 0;	
                new_rob_entry[i].dest_PRN           = 0;	
                new_rob_entry[i].reg_write          = 0;	
                new_rob_entry[i].is_branch          = 0;	
                new_rob_entry[i].is_store           = 0;		
                new_rob_entry[i].PC                 = 0;
                new_rob_entry[i].target             = 0;
                new_rob_entry[i].branch_direction   = 0;
                new_rob_entry[i].mispredicted       = 0;
                new_rob_entry[i].complete           = 0;
                new_rob_entry[i].illegal            = 0;
                new_rob_entry[i].halt               = 0;
            end

        case(VALID)
            2'b01: begin
                new_rob_entry[0].dest_ARN           = rob_packet_in[0].dest_ARN;
                new_rob_entry[0].dest_PRN           = rob_packet_in[0].dest_PRN;
                new_rob_entry[0].reg_write          = rob_packet_in[0].reg_write;
                new_rob_entry[0].is_branch          = rob_packet_in[0].is_branch;
                new_rob_entry[0].is_store           = rob_packet_in[0].is_store;
                new_rob_entry[0].PC                 = rob_packet_in[0].PC;
                new_rob_entry[0].target             = rob_packet_in[0].target;
                new_rob_entry[0].branch_direction   = rob_packet_in[0].branch_direction;
                new_rob_entry[0].mispredicted       = 0;
                new_rob_entry[0].complete           = 0;
                new_rob_entry[0].illegal            = rob_packet_in[0].illegal;
                new_rob_entry[0].halt               = rob_packet_in[0].halt;

                dispatched_number                   = 1;
            end

            2'b11: begin
                new_rob_entry[0].dest_ARN           = rob_packet_in[0].dest_ARN;
                new_rob_entry[0].dest_PRN           = rob_packet_in[0].dest_PRN;
                new_rob_entry[0].reg_write          = rob_packet_in[0].reg_write;
                new_rob_entry[0].is_branch          = rob_packet_in[0].is_branch;
                new_rob_entry[0].is_store           = rob_packet_in[0].is_store;
                new_rob_entry[0].PC                 = rob_packet_in[0].PC;
                new_rob_entry[0].target             = rob_packet_in[0].target;
                new_rob_entry[0].branch_direction   = rob_packet_in[0].branch_direction;
                new_rob_entry[0].mispredicted       = 0;
                new_rob_entry[0].complete           = 0;
                new_rob_entry[0].illegal            = rob_packet_in[0].illegal;
                new_rob_entry[0].halt               = rob_packet_in[0].halt;

                new_rob_entry[1].dest_ARN           = rob_packet_in[1].dest_ARN;
                new_rob_entry[1].dest_PRN           = rob_packet_in[1].dest_PRN;
                new_rob_entry[1].reg_write          = rob_packet_in[1].reg_write;
                new_rob_entry[1].is_branch          = rob_packet_in[1].is_branch;
                new_rob_entry[1].is_store           = rob_packet_in[1].is_store;
                new_rob_entry[1].PC                 = rob_packet_in[1].PC;
                new_rob_entry[1].target             = rob_packet_in[1].target;
                new_rob_entry[1].branch_direction   = rob_packet_in[1].branch_direction;
                new_rob_entry[1].mispredicted       = 0;
                new_rob_entry[1].complete           = 0;
                new_rob_entry[1].illegal            = rob_packet_in[1].illegal;
                new_rob_entry[1].halt               = rob_packet_in[1].halt;

                dispatched_number                   = 2;
    
            end
            
            default: begin
                // default values
                new_rob_entry[0].dest_ARN           = 0;	
                new_rob_entry[0].dest_PRN           = 0;	
                new_rob_entry[0].reg_write          = 0;	
                new_rob_entry[0].is_branch          = 0;	
                new_rob_entry[0].is_store           = 0;		
                new_rob_entry[0].PC                 = 0;
                new_rob_entry[0].target             = 0;
                new_rob_entry[0].branch_direction   = 0;
                new_rob_entry[0].mispredicted       = 0;
                new_rob_entry[0].complete           = 0;
                new_rob_entry[0].illegal            = 0;
                new_rob_entry[0].halt               = 0;

                new_rob_entry[1].dest_ARN           = 0;	
                new_rob_entry[1].dest_PRN           = 0;	
                new_rob_entry[1].reg_write          = 0;	
                new_rob_entry[1].is_branch          = 0;	
                new_rob_entry[1].is_store           = 0;		
                new_rob_entry[1].PC                 = 0;
                new_rob_entry[1].target             = 0;
                new_rob_entry[1].branch_direction   = 0;
                new_rob_entry[1].mispredicted       = 0;
                new_rob_entry[1].complete           = 0;
                new_rob_entry[1].illegal            = 0;
                new_rob_entry[1].halt               = 0;

                dispatched_number                   = 0;            
            end

        endcase
    end
// assign output signals
    always_comb begin
        store_commit            = 0;
        squash                  = 0;
        next_pc                 = 0;
        tail_reset              = 0;
        committed_number        = 0;

        // default outputs
        for(int i = 0; i < 2; i++) begin
            rob_packet_out[i].dest_PRN_out     = 0;
            rob_packet_out[i].dest_ARN_out     = 0;
            rob_packet_out[i].valid_out        = 0;
            rob_packet_out[i].retired          = 0;

            rob_packet_out[i].PC_out           = 0;
            rob_packet_out[i].direction_out    = 0;
            target_out[i]                      = 0;
            rob_packet_out[i].is_branch_out    = 0;
            rob_packet_out[i].illegal_out      = 0;
            rob_packet_out[i].halt_out         = 0;
        end

        case({DONE[1], DONE[0]})

            2'b01: begin
                rob_packet_out[0].dest_PRN_out     = rob_current_entry[(head) % `ROB].dest_PRN;
                rob_packet_out[0].dest_ARN_out     = rob_current_entry[(head) % `ROB].dest_ARN;
                rob_packet_out[0].valid_out        = rob_current_entry[(head) % `ROB].reg_write;

                rob_packet_out[0].PC_out           = rob_current_entry[(head) % `ROB].PC;
                rob_packet_out[0].direction_out    = rob_current_entry[(head) % `ROB].branch_direction;
                target_out[0]                      = rob_current_entry[(head) % `ROB].target;
                rob_packet_out[0].is_branch_out    = rob_current_entry[(head) % `ROB].is_branch;

                rob_packet_out[0].illegal_out      = rob_current_entry[(head) % `ROB].illegal;
                rob_packet_out[0].halt_out         = rob_current_entry[(head) % `ROB].halt;
                rob_packet_out[0].retired          = 1;

                if(BRANCH[0] && MISPREDICTED[0]) begin
                    squash          = 1;
                    tail_reset      = 1;
                    next_pc         = (DIRECTION[0]) ? TARGET[0] : NPC[0];
                end               
                
                store_commit        = (STORE[0]) ? 1 : 0;
                committed_number    = 1;

            end

            2'b11: begin
                if(STORE[0] && STORE[1]) begin
                    rob_packet_out[0].dest_PRN_out     = rob_current_entry[(head) % `ROB].dest_PRN;
                    rob_packet_out[0].dest_ARN_out     = rob_current_entry[(head) % `ROB].dest_ARN;
                    rob_packet_out[0].valid_out        = rob_current_entry[(head) % `ROB].reg_write;

                    rob_packet_out[0].PC_out           = rob_current_entry[(head) % `ROB].PC;
                    rob_packet_out[0].direction_out    = rob_current_entry[(head) % `ROB].branch_direction;
                    target_out[0]                      = rob_current_entry[(head) % `ROB].target;
                    rob_packet_out[0].is_branch_out    = rob_current_entry[(head) % `ROB].is_branch;

                    rob_packet_out[0].illegal_out      = rob_current_entry[(head) % `ROB].illegal;
                    rob_packet_out[0].halt_out         = rob_current_entry[(head) % `ROB].halt;
                    rob_packet_out[0].retired          = 1;                   

                    store_commit        = 1;
                    committed_number    = 1;
                end
                    
                else if(BRANCH[0] && MISPREDICTED[0]) begin
                    rob_packet_out[0].dest_PRN_out     = rob_current_entry[(head) % `ROB].dest_PRN;
                    rob_packet_out[0].dest_ARN_out     = rob_current_entry[(head) % `ROB].dest_ARN;
                    rob_packet_out[0].valid_out        = rob_current_entry[(head) % `ROB].reg_write;

                    rob_packet_out[0].PC_out           = rob_current_entry[(head) % `ROB].PC;
                    rob_packet_out[0].direction_out    = rob_current_entry[(head) % `ROB].branch_direction;
                    target_out[0]                      = rob_current_entry[(head) % `ROB].target;
                    rob_packet_out[0].is_branch_out    = rob_current_entry[(head) % `ROB].is_branch;

                    rob_packet_out[0].illegal_out      = rob_current_entry[(head) % `ROB].illegal;
                    rob_packet_out[0].halt_out         = rob_current_entry[(head) % `ROB].halt;
                    rob_packet_out[0].retired          = 1;

                    squash              = 1;
                    tail_reset          = 1;
                    next_pc             = ((DIRECTION[0]) ? TARGET[0] : NPC[0]);   

                    store_commit        = 0;
                    committed_number    = 1;
                end
                else begin
                    rob_packet_out[0].dest_PRN_out     = rob_current_entry[(head) % `ROB].dest_PRN;
                    rob_packet_out[0].dest_ARN_out     = rob_current_entry[(head) % `ROB].dest_ARN;
                    rob_packet_out[0].valid_out        = rob_current_entry[(head) % `ROB].reg_write;

                    rob_packet_out[0].PC_out           = rob_current_entry[(head) % `ROB].PC;
                    rob_packet_out[0].direction_out    = rob_current_entry[(head) % `ROB].branch_direction;
                    target_out[0]                      = rob_current_entry[(head) % `ROB].target;
                    rob_packet_out[0].is_branch_out    = rob_current_entry[(head) % `ROB].is_branch;

                    rob_packet_out[0].illegal_out      = rob_current_entry[(head) % `ROB].illegal;
                    rob_packet_out[0].halt_out         = rob_current_entry[(head) % `ROB].halt;
                    rob_packet_out[0].retired          = 1;

                    rob_packet_out[1].dest_PRN_out     = rob_current_entry[(head+1) % `ROB].dest_PRN;
                    rob_packet_out[1].dest_ARN_out     = rob_current_entry[(head+1) % `ROB].dest_ARN;
                    rob_packet_out[1].valid_out        = rob_current_entry[(head+1) % `ROB].reg_write;

                    rob_packet_out[1].PC_out           = rob_current_entry[(head+1) % `ROB].PC;
                    rob_packet_out[1].direction_out    = rob_current_entry[(head+1) % `ROB].branch_direction;
                    target_out[1]                      = rob_current_entry[(head+1) % `ROB].target;
                    rob_packet_out[1].is_branch_out    = rob_current_entry[(head+1) % `ROB].is_branch;

                    rob_packet_out[1].illegal_out      = rob_current_entry[(head+1) % `ROB].illegal;
                    rob_packet_out[1].halt_out         = rob_current_entry[(head+1) % `ROB].halt;
                    rob_packet_out[1].retired          = 1;

                    if(BRANCH[1] && MISPREDICTED[1]) begin
                        squash          = 1;
                        tail_reset      = 1;
                        next_pc         = (DIRECTION[1]) ? TARGET[1] : NPC[1];
                    end                                             

                    store_commit        = (STORE[0] || STORE[1]) ? 1 : 0;
                    committed_number    = 2;
                end
            end

        endcase
    end


    // retire logic, only one store instruction retired per cycle
    always_comb begin
        next_tail = (tail_reset) ? 0 : (tail + dispatched_number) % `ROB;
        next_head = (head + committed_number) % `ROB;
    end


    always_ff @(posedge clock) begin
        if(reset || squash) begin
            head                <= 0;
            tail                <= 0;
            num_free            <= `ROB;        
        end

        else begin
            // rob status update
            head                <= next_head;
            tail                <= next_tail;
            num_free            <= next_num_free;
        end

    end

    always_ff @(posedge clock) begin
        if(reset || squash) begin
            rob_current_entry   <= 0;
        end
        else begin
        // Dispatch content when instructions are valid
        if (VALID[0]) begin
            rob_current_entry[(tail + 0) % `ROB] <= new_rob_entry[0];
        end

        if (VALID[1]) begin
            rob_current_entry[(tail + 1) % `ROB] <= new_rob_entry[1];
        end

        // CDB complete
        // Deal with branch misprediction and check branch target
        if (rob_packet_in[0].CDB_valid && rob_current_entry[complete_position[0]] != 0) begin
            rob_current_entry[complete_position[0]].complete         <= 1'b1;
            rob_current_entry[complete_position[0]].mispredicted     <= rob_current_entry[complete_position[0]].is_branch && 
                                                                        (rob_packet_in[0].CDB_target != rob_current_entry[complete_position[0]].target);
            rob_current_entry[complete_position[0]].branch_direction <= rob_packet_in[0].CDB_direction;
            rob_current_entry[complete_position[0]].target           <= rob_packet_in[0].CDB_target;
        end

        if (rob_packet_in[1].CDB_valid && rob_current_entry[complete_position[1]] != 0) begin
            rob_current_entry[complete_position[1]].complete         <= 1'b1;
            rob_current_entry[complete_position[1]].mispredicted     <= rob_current_entry[complete_position[1]].is_branch && 
                                                                        (rob_packet_in[1].CDB_target != rob_current_entry[complete_position[1]].target);
            rob_current_entry[complete_position[1]].branch_direction <= rob_packet_in[1].CDB_direction;
            rob_current_entry[complete_position[1]].target           <= rob_packet_in[1].CDB_target;
        end

        // retire
        for(int i = 0; i < committed_number; i++) begin
            rob_current_entry[(head + i) % `ROB].complete           <= 0;
            end
        end
    end

endmodule