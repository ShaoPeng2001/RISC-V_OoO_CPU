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
	input         					clock,                  
	input         					reset,                  
	input 		  					stall,					// stall signal

	input ADDR						predicted_pc, 			// the predicted PC
	input         					take_branch,      		// taken-branch signal
	input ADDR 						target_pc,        		// target pc: use if take_branch is TRUE
	
	input [1:0] [63:0] 			    icache_data,       		// Data coming back from instruction-memory
	input [1:0]					    icache_data_valid,

	output [1:0] [31:0] 			icache_addr,    	    // address sent to icache
	output IF_ID_PACKET [1:0] 	    if_packet_out         	// if output signal packet
);

	logic    				enable;			// wheter PC can increase or not
	ADDR 					PC_reg;
	logic [1:0] [31:0] 	    PC;             // PC we are currently fetching	

	//assign enable =  ~stall && (icache_data_valid == {`N{1'b1}});	// enable logic
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
	/*
	generate
		for(genvar i = 0; i < `N; i = i + 1) begin
			if(i == 0)
				assign PC[i] = PC_reg;
			else
				assign PC[i] = PC[i-1] + 4;
		end
	endgenerate
	*/
	// fetch two instructions per cycle, so two PC
	assign PC[0] = PC_reg;
	assign PC[1] = PC[0] + 4;

	// two read port for icache
	assign icache_addr[0] = {PC[0][31:3], 3'b0};
	assign icache_addr[1] = {PC[1][31:3], 3'b0};

	// using the second bit of PC to index the memory data block
	generate
		for (genvar i = 0 ; i < 2; i = i + 1) begin
			assign if_packet_out[i].inst = PC[i][2] ? icache_data[i][63:32] : icache_data[i][31:0];	// index corresponding instruction location
			assign if_packet_out[i].NPC  = PC[i] + 4;
			assign if_packet_out[i].PC   = PC[i];
			//assign if_packet_out[i].valid = (icache_data_valid == {`N{1'b1}}) & (if_packet_out[i].inst != 0) & ~stall;
			assign if_packet_out[i].valid = (icache_data_valid == 2'b11) & (if_packet_out[i].inst != 0) & ~stall;
			//assign icache_addr[i] 	 = {PC[i][31:3], 3'b0};
		end
	endgenerate

endmodule