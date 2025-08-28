/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  if_stage.v                                          //
//                                                                     //
//  Description :  instruction fetch (IF) stage of the pipeline;       // 
//                 fetch instruction, compute next PC location, and    //
//                 send them down the pipeline.                        //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

module if_stage(
    input                           clock,                  
    input                           reset,                  
    input                           stall,					

    input ADDR	                    predicted_pc, 		
    input                           take_branch,      	
    input ADDR 	                    target_pc,              // use if take_branch is TRUE
    
    input [1:0] [63:0]              icache_data,       		
    input [1:0]                     icache_data_valid,

    output [1:0] [31:0]             icache_addr,    	    // address sent to icache
    output IF_ID_PACKET [1:0]       if_packet_out         	// if output signal packet
);

    logic                           enable;
    ADDR                            PC_reg;
    logic [1:0] [31:0]              PC;             

    assign enable =  ~stall && (icache_data_valid == 2'b11);	// enable logic

    // PC counter logic
    always_ff @(posedge clock) begin		
        if(reset)
            PC_reg <= 0; 
        else if(take_branch)
            PC_reg <= target_pc;
        else if(enable)
            PC_reg <= predicted_pc;        // predicted PC
        else
            PC_reg <= PC_reg;
    end 

    // fetch two instructions per cycle, so two PC
    assign PC[0] = PC_reg;
    assign PC[1] = PC[0] + 4;

    // two read port for icache
    assign icache_addr[0] = {PC[0][31:3], 3'b0};
    assign icache_addr[1] = {PC[1][31:3], 3'b0};


    // using the second bit of PC to index the memory data block
    assign if_packet_out[0].inst  = PC[0][2] ? icache_data[0][63:32] : icache_data[0][31:0];	// index corresponding instruction location
    assign if_packet_out[0].NPC   = PC[0] + 4;
    assign if_packet_out[0].PC    = PC[0];
    assign if_packet_out[0].valid = (icache_data_valid == 2'b11) & (if_packet_out[0].inst != 0) & ~stall;

    assign if_packet_out[1].inst  = PC[1][2] ? icache_data[1][63:32] : icache_data[1][31:0];	// index corresponding instruction location
    assign if_packet_out[1].NPC   = PC[1] + 4;
    assign if_packet_out[1].PC    = PC[1];
    assign if_packet_out[1].valid = (icache_data_valid == 2'b11) & (if_packet_out[1].inst != 0) & ~stall;

endmodule