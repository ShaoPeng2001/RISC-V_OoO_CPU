/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  cpu_test.sv                                         //
//                                                                     //
//  Description :  Testbench module for the VeriSimpleV processor.     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "../verilog/sys_defs.svh"
`include "../verilog/ISA.svh"
// P4 TODO: Add your own debugging framework. Basic printing of data structures
//          is an absolute necessity for the project. You can use C functions 
//          like in test/pipeline_print.c or just do everything in verilog.
//          Be careful about running out of space on CAEN printing lots of state
//          for longer programs (alexnet, outer_product, etc.)

// These link to the pipeline_print.c file in this directory, and are used below to print
// detailed output to the pipeline_output_file, initialized by open_pipeline_output_file()
import "DPI-C" function string decode_inst(int inst);
//import "DPI-C" function void open_pipeline_output_file(string file_name);
//import "DPI-C" function void print_header();
//import "DPI-C" function void print_cycles(int clock_count);
//import "DPI-C" function void print_stage(int inst, int npc, int valid_inst);
//import "DPI-C" function void print_reg(int wb_data, int wb_idx, int wb_en);
//import "DPI-C" function void print_membus(int proc2mem_command, int proc2mem_addr,
//                                          int proc2mem_data_hi, int proc2mem_data_lo);
//import "DPI-C" function void close_pipeline_output_file();


`define TB_MAX_CYCLES 50000000


module testbench;
    // string inputs for loading memory and output files
    // run like: cd build && ./simv +MEMORY=../programs/mem/<my_program>.mem +OUTPUT=../output/<my_program>
    // this testbench will generate 4 output files based on the output
    // named OUTPUT.{out cpi, wb, ppln} for the memory, cpi, writeback, and pipeline outputs.
    string program_memory_file, output_name;
    string out_outfile, cpi_outfile, writeback_outfile;//, pipeline_outfile;
    int out_fileno, cpi_fileno, wb_fileno; // verilog uses integer file handles with $fopen and $fclose

    // variables used in the testbench
    logic        clock;
    logic        reset;
    logic [31:0] clock_count; // also used for terminating infinite loops
    logic [31:0] instr_count;

    MEM_COMMAND proc2mem_command;
    ADDR        proc2mem_addr;
    MEM_BLOCK   proc2mem_data;
    MEM_TAG     mem2proc_transaction_tag;
    MEM_BLOCK   mem2proc_data;
    MEM_TAG     mem2proc_data_tag;
    MEM_SIZE    proc2mem_size;

    COMMIT_PACKET [`N-1:0] committed_insts;
    EXCEPTION_CODE error_status = NO_ERROR;

    ADDR  if_NPC_dbg;
    DATA  if_inst_dbg;
    logic if_valid_dbg;
    ADDR  if_id_NPC_dbg;
    DATA  if_id_inst_dbg;
    logic if_id_valid_dbg;
    ADDR  id_ex_NPC_dbg;
    DATA  id_ex_inst_dbg;
    logic id_ex_valid_dbg;
    ADDR  ex_mem_NPC_dbg;
    DATA  ex_mem_inst_dbg;
    logic ex_mem_valid_dbg;
    ADDR  mem_wb_NPC_dbg;
    DATA  mem_wb_inst_dbg;
    logic mem_wb_valid_dbg;

    logic [31:0]            lsq_dcache_write_data;
	logic                   lsq_dcache_write_enable;
	logic [1:0]             lsq_dcache_write_size;
	logic [15:0]            lsq_dcache_write_address;

	logic [31:0] [63:0]     dcache_data;
    logic [31:0] [7:0]      dcache_tags;
    logic [31:0]            dcache_dirty;
	logic [31:0]            dcache_valid;
    
    logic [1:0] [12:0]      victim_tags;
    logic [1:0] [63:0]      victim_data;
    logic [1:0]             victim_valid;
    logic [1:0]             victim_dirty;

	logic                   bus_valid_incoming;
    logic                   bus_write_incoming;
    logic [63:0]            bus_data_incoming;
    logic [15:0]            bus_address_incoming;
    logic [15:0] [15:0]     bus_req_fifo_address;
    logic [15:0]            bus_req_fifo_write;
    logic [15:0] [1:0]      bus_req_fifo_size;
	logic [1:0]             bus_size_incoming;
	logic [15:0] [63:0]     bus_req_fifo_data;


    // Instantiate the Pipeline
    cpu VeriSimpleV(
        // Inputs
        .clock (clock),
        .reset (reset),
        .Imem2proc_transaction_tag(mem2proc_transaction_tag),
        .Imem2proc_data(mem2proc_data),
        .Imem2proc_data_tag(mem2proc_data_tag),

        // Outputs
        .Imem_command(proc2mem_command),
        .Imem_addr(proc2mem_addr),
        .proc2mem_data    (proc2mem_data),            // store
`ifndef CACHE_MODE
        .proc2mem_size    (proc2mem_size),
`endif

        .committed_insts (committed_insts),

        .lsq_dcache_write_data(lsq_dcache_write_data),
        .lsq_dcache_write_enable(lsq_dcache_write_enable),
        .lsq_dcache_write_size(lsq_dcache_write_size),
        .lsq_dcache_write_address(lsq_dcache_write_address),

        .dcache_data(dcache_data),
        .dcache_tags(dcache_tags),
        .dcache_dirty(dcache_dirty),
        .dcache_valid(dcache_valid),

        .victim_tags(victim_tags),
        .victim_data(victim_data),
        .victim_valid(victim_valid),
        .victim_dirty(victim_dirty),

        .bus_valid_incoming(bus_valid_incoming),
        .bus_write_incoming(bus_write_incoming),
        .bus_data_incoming(bus_data_incoming),
        .bus_address_incoming(bus_address_incoming),
        .bus_req_fifo_address(bus_req_fifo_address),
        .bus_req_fifo_write(bus_req_fifo_write),
        .bus_req_fifo_size(bus_req_fifo_size),
        .bus_size_incoming(bus_size_incoming),
        .bus_req_fifo_data(bus_req_fifo_data)

    );

    // Instantiate the Data Memory
    mem memory (
        // Inputs
        .clock            (clock),
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (proc2mem_size),
`endif

        // Outputs
        .mem2proc_transaction_tag (mem2proc_transaction_tag),
        .mem2proc_data            (mem2proc_data),
        .mem2proc_data_tag        (mem2proc_data_tag)
    );


    // Generate System Clock
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end


    initial begin
        $display("\n---- Starting CPU Testbench ----\n");

        // set paramterized strings, see comment at start of module
        if ($value$plusargs("MEMORY=%s", program_memory_file)) begin
            $display("Using memory file  : %s", program_memory_file);
        end else begin
            $display("Did not receive '+MEMORY=' argument. Exiting.\n");
            $finish;
        end
        if ($value$plusargs("OUTPUT=%s", output_name)) begin
            $display("Using output files : %s.{out, cpi, wb, ppln}", output_name);
            out_outfile       = {output_name,".out"}; // this is how you concatenate strings in verilog
            cpi_outfile       = {output_name,".cpi"};
            writeback_outfile = {output_name,".wb"};
            //pipeline_outfile  = {output_name,".ppln"};
        end else begin
            $display("\nDid not receive '+OUTPUT=' argument. Exiting.\n");
            $finish;
        end

        clock = 1'b0;
        reset = 1'b0;

        $display("\n  %16t : Asserting Reset", $realtime);
        reset = 1'b1;

        @(posedge clock);
        @(posedge clock);

        $display("  %16t : Loading Unified Memory", $realtime);
        // load the compiled program's hex data into the memory module
        $readmemh(program_memory_file, memory.unified_memory);

        @(posedge clock);
        @(posedge clock);
        #1; // This reset is at an odd time to avoid the pos & neg clock edges
        $display("  %16t : Deasserting Reset", $realtime);
        reset = 1'b0;

        wb_fileno = $fopen(writeback_outfile);
        $fdisplay(wb_fileno, "Register writeback output (hexadecimal)");

        // Open pipeline output file AFTER throwing the reset otherwise the reset state is displayed
        // open_pipeline_output_file(pipeline_outfile);
        // print_header();

        out_fileno = $fopen(out_outfile);

        $display("  %16t : Running Processor", $realtime);
    end


    always @(negedge clock) begin
        if (reset) begin
            // Count the number of cycles and number of instructions committed
            clock_count = 0;
            instr_count = 0;
        end else begin
            #2; // wait a short time to avoid a clock edge

            clock_count = clock_count + 1;

            if (clock_count % 10000 == 0) begin
                $display("  %16t : %d cycles", $realtime, clock_count);
            end

          
            print_custom_data();

            output_reg_writeback_and_maybe_halt();

            // stop the processor
            if (error_status != NO_ERROR || clock_count > `TB_MAX_CYCLES) begin

                $display("  %16t : Processor Finished", $realtime);

                // close the writeback and pipeline output files
                // close_pipeline_output_file();
                $fclose(wb_fileno);

                // display the final memory and status
                show_final_mem_and_status(error_status);
                // output the final CPI
                output_cpi_file();

                $display("\n---- Finished CPU Testbench ----\n");

                #100 $finish;
            end
        end // if(reset)
    end


    // Task to output register writeback data and potentially halt the processor.
    task output_reg_writeback_and_maybe_halt;
        ADDR pc;
        DATA inst;
        MEM_BLOCK block;
        for (int n = 0; n < `N; ++n) begin
            if (committed_insts[n].valid) begin
                // update the count for every committed instruction
                instr_count = instr_count + 1;

                pc = committed_insts[n].NPC - 4;
                block = memory.unified_memory[pc[31:3]];
                inst = block.word_level[pc[2]];
                // print the committed instructions to the writeback output file
                if (committed_insts[n].reg_idx == `ZERO_REG) begin
                    $fdisplay(wb_fileno, "PC %4x:%-8s| ---", pc, decode_inst(inst));
                end else begin
                    $fdisplay(wb_fileno, "PC %4x:%-8s| r%02d=%-8x",
                              pc,
                              decode_inst(inst),
                              committed_insts[n].reg_idx,
                              committed_insts[n].data);
                end

                // exit if we have an illegal instruction or a halt
                if (committed_insts[n].illegal) begin
                    error_status = ILLEGAL_INST;
                    break;
                end else if(committed_insts[n].halt) begin
                    error_status = HALTED_ON_WFI;
                    break;
                end
            end // if valid
        end
    endtask // task output_reg_writeback_and_maybe_halt


    // Task to output the final CPI and # of elapsed clock edges
    task output_cpi_file;
        real cpi;
        begin
            cpi = $itor(clock_count) / instr_count; // must convert int to real
            cpi_fileno = $fopen(cpi_outfile);
            $fdisplay(cpi_fileno, "@@@  %0d cycles / %0d instrs = %f CPI",
                      clock_count, instr_count, cpi);
            $fdisplay(cpi_fileno, "@@@  %4.2f ns total time to execute",
                      clock_count * `CLOCK_PERIOD);
            $fclose(cpi_fileno);
        end
    endtask // task output_cpi_file

    task mem_update(input [63:0] data, input MEM_SIZE mem_size, input [15:0] addr);
		MEM_BLOCK block;
		block.byte_level = memory.unified_memory[addr[15:3]];
		block.half_level = memory.unified_memory[addr[15:3]];
		block.word_level = memory.unified_memory[addr[15:3]];
		case (mem_size) 
			BYTE: begin
				block.byte_level[addr[2:0]]                 = data[7:0];
				memory.unified_memory[addr[15:3]]           = block.byte_level;
			end
			HALF: begin
				block.half_level[addr[2:1]]                 = data[15:0];
				//memory.unified_memory[proc2mem_addr[15:3]]  = block.half_level;
                memory.unified_memory[addr[15:3]]           = block.half_level;
			end
			WORD: begin
				block.word_level[addr[2]]                   = data[31:0];
				memory.unified_memory[addr[15:3]]           = block.word_level;
			end
			default: begin
				memory.unified_memory[addr[15:3]]           = data;
			end
		endcase
	endtask

    task flush_dcache_to_memory;

		for(int i = 0; i < 32; i++) begin
			if(dcache_valid[i] & dcache_dirty[i]) begin
				mem_update(dcache_data[i], DOUBLE, (32 * dcache_tags[i] + i) * 8);
			end
		end

		for (int i = 0; i < 2; ++i) begin
			if(victim_valid[i] & victim_dirty[i]) begin
				mem_update(victim_data[i], DOUBLE, victim_tags[i] * 8);
			end
		end

		if (lsq_dcache_write_enable) begin
			mem_update(lsq_dcache_write_data, lsq_dcache_write_size, lsq_dcache_write_address);
		end
        

        if(bus_valid_incoming && bus_write_incoming) begin
            mem_update(bus_data_incoming, bus_size_incoming, bus_address_incoming);
        end

		for (int i = 0; i < 2 * `LSQSZ; ++i) begin
			if (bus_req_fifo_write[i]) begin
				mem_update(bus_req_fifo_data[i], bus_req_fifo_size[i], bus_req_fifo_address[i]);
			end
		end

	endtask

    // Show contents of Unified Memory in both hex and decimal
    // Also output the final processor status
    task show_final_mem_and_status;
        input EXCEPTION_CODE final_status;
        int showing_data;
        begin
            $fdisplay(out_fileno, "\nFinal memory state and exit status:\n");
            $fdisplay(out_fileno, "@@@ Unified Memory contents hex on left, decimal on right: ");
            flush_dcache_to_memory;
            $fdisplay(out_fileno, "@@@");
            showing_data = 0;
            for (int k = 0; k <= `MEM_64BIT_LINES - 1; k = k+1) begin
                if (memory.unified_memory[k] != 0) begin
                    $fdisplay(out_fileno, "@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k],
                                                             memory.unified_memory[k]);
                    showing_data = 1;
                end else if (showing_data != 0) begin
                    $fdisplay(out_fileno, "@@@");
                    showing_data = 0;
                end
            end
            $fdisplay(out_fileno, "@@@");

            case (final_status)
                LOAD_ACCESS_FAULT: $fdisplay(out_fileno, "@@@ System halted on memory error");
                HALTED_ON_WFI:     $fdisplay(out_fileno, "@@@ System halted on WFI instruction");
                ILLEGAL_INST:      $fdisplay(out_fileno, "@@@ System halted on illegal instruction");
                default:           $fdisplay(out_fileno, "@@@ System halted on unknown error code %x", final_status);
            endcase
            $fdisplay(out_fileno, "@@@");
            $fclose(out_fileno);
        end
    endtask // task show_final_mem_and_status



    // OPTIONAL: Print our your data here
    // It will go to the $program.log file
    task print_custom_data;
        //$display("%3d: YOUR DATA HERE", 
        //    clock_count-1
        //);
    endtask


endmodule // module testbench
