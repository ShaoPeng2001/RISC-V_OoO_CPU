`include "../verilog/rob.svh"
`define DEBUG

module RAT_RRAT_test; 

    logic clock;
    logic reset;
    logic except;
    logic [`WAYS-1:0] [4:0]              rda_idx;
    logic [`WAYS-1:0] [4:0]              rdb_idx;
    logic [`WAYS-1:0] [4:0]              RAT_dest_idx;
    logic [`WAYS-1:0]                    RAT_idx_valid;
    logic [`WAYS-1:0] [$clog2(`PRF)-1:0] reg_idx_wr_CDB;
    logic [`WAYS-1:0]                    wr_en_CDB;

    logic [`WAYS-1:0] [4:0]              RRAT_ARF_idx;       
    logic [`WAYS-1:0]                    RRAT_idx_valid; 
    logic [`WAYS-1:0] [$clog2(`PRF)-1:0] RRAT_PRF_idx;      

    logic [`WAYS-1:0] [$clog2(`PRF)-1:0] rename_result;      
    logic [`WAYS-1:0]                    rename_result_valid;

    logic [`WAYS-1:0] [$clog2(`PRF)-1:0] rda_idx_out;         
    logic [`WAYS-1:0] [$clog2(`PRF)-1:0] rdb_idx_out;        
    logic [`WAYS-1:0]                    rda_valid;
    logic [`WAYS-1:0]                    rdb_valid;

    `ifdef DEBUG
    logic [31:0] [$clog2(`PRF)-1:0]      RRAT_reg_out_out;
    `endif


    RAT_RRAT 
    uut(
        .clock(clock),
        .reset(reset),
        .except(except),
        .rda_idx(rda_idx),
        .rdb_idx(rdb_idx),
        .RAT_dest_idx(RAT_dest_idx),
        .RAT_idx_valid(RAT_idx_valid),
        .reg_idx_wr_CDB(reg_idx_wr_CDB),
        .wr_en_CDB(wr_en_CDB),
        .RRAT_ARF_idx(RRAT_ARF_idx),
        .RRAT_idx_valid(RRAT_idx_valid),
        .RRAT_PRF_idx(RRAT_PRF_idx),
        .rename_result(rename_result),
        .rename_result_valid(rename_result_valid),
        .rda_idx_out(rda_idx_out),
        .rdb_idx_out(rdb_idx_out),
        .rda_valid(rda_valid),
        .rdb_valid(rdb_valid)
        `ifdef DEBUG
        ,
        .RRAT_reg_out_out(RRAT_reg_out_out)
        `endif
    );

    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end

    initial begin

        reset = 1;
        except = 0;
        for(int i = 0; i < `WAYS; i++) begin
            rda_idx[i]      	= 0;
            rdb_idx[i]      	= 0;
            RAT_dest_idx[i]   	= 0;
            RAT_idx_valid[i]    = 1;
            reg_idx_wr_CDB[i]   = 0;
            wr_en_CDB[i]        = 0;
            RRAT_ARF_idx[i]     = 0;
            RRAT_idx_valid[i]   = 0;
            RRAT_PRF_idx[i]     = 0;
        end
        @(negedge clock);
        reset = 0;
        RAT_idx_valid[0]    = 0;
        RAT_idx_valid[1]    = 0;
        rda_idx[0] = 0;
        rdb_idx[0] = 1;
        rda_idx[1] = 2;
        rdb_idx[1] = 3;
        @(negedge clock);
        $display("\nrename result 1 = %0d rename result 2 = %0d rename result valid = %0d %0d", rename_result[0], rename_result[1], rename_result_valid[0], rename_result_valid[1]);
        $display("\nopa(r0) opb(r1) index after reset");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d valid = %0d %0d", rda_idx_out[0], rdb_idx_out[0], rda_valid[0], rdb_valid[0]);

        $display("\nopa(r2) opb(r3) index after reset");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d valid = %0d %0d", rda_idx_out[1], rdb_idx_out[1], rda_valid[1], rdb_valid[1]);

        #10;
        @(negedge clock);
        $display("\nrename result 1 = %0d rename result 2 = %0d rename result valid = %0d %0d", rename_result[0], rename_result[1], rename_result_valid[0], rename_result_valid[1]);
        $display("\nRename 1 register (r1)");
        RAT_dest_idx[0] = 1;
        RAT_idx_valid[0] = 1;
        @(negedge clock);
        RAT_idx_valid[0] = 0;
        $display("\nopa(r0) opb(r1) index after rename r1");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d valid = %0d %0d", rda_idx_out[0], rdb_idx_out[0], rda_valid[0], rdb_valid[0]);

        #10;
        @(negedge clock);
        $display("\nrename result 1 = %0d rename result 2 = %0d rename result valid = %0d %0d", rename_result[0], rename_result[1], rename_result_valid[0], rename_result_valid[1]);
        $display("\nRename 2 register (r1 r2)");
        RAT_dest_idx[0] = 1;
        RAT_idx_valid[0] = 1;
        RAT_dest_idx[1] = 2;
        RAT_idx_valid[1] = 1;
        @(negedge clock);
        RAT_idx_valid[0] = 0;
        RAT_idx_valid[1] = 0; 
        $display("\nopa(r0) opb(r1) index after rename r1");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d valid = %0d %0d", rda_idx_out[0], rdb_idx_out[0], rda_valid[0], rdb_valid[0]);
        $display("\nopa(r2) opb(r3) index after rename r2");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d valid = %0d %0d", rda_idx_out[1], rdb_idx_out[1], rda_valid[1], rdb_valid[1]);

        #10;
        @(negedge clock);
        $display("\nrename result 1 = %0d rename result 2 = %0d rename result valid = %0d %0d", rename_result[0], rename_result[1], rename_result_valid[0], rename_result_valid[1]);
        $display("\nRename same register (r1)");
        RAT_dest_idx[0] = 1;
        RAT_idx_valid[0] = 1;
        RAT_dest_idx[1] = 1;
        RAT_idx_valid[1] = 1;
        @(negedge clock);
        RAT_idx_valid[0] = 0;
        RAT_idx_valid[1] = 0;
        $display("\nopa(r0) opb(r1) index after rename r1");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d valid = %0d %0d", rda_idx_out[0], rdb_idx_out[0], rda_valid[0], rdb_valid[0]);
        $display("\nopa(r2) opb(r3) index after rename r1");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d valid = %0d %0d", rda_idx_out[1], rdb_idx_out[1], rda_valid[1], rdb_valid[1]);

        #10;
        @(negedge clock);
        $display("\nComplete r1 PRF");
        reg_idx_wr_CDB[0] = 33;
        wr_en_CDB [0] = 1;
        @(negedge clock);
        wr_en_CDB [0] = 0;
        $display("\nopa(r0) opb(r1) index after complete r1");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d valid = %0d %0d", rda_idx_out[0], rdb_idx_out[0], rda_valid[0], rdb_valid[0]);


        #10;
        @(negedge clock);
        $display("\nRetire 1 register (r1)");
        RRAT_ARF_idx[0] = 1;
        RRAT_idx_valid[0] = 1;
        RRAT_PRF_idx[0] = 40;
        @(negedge clock);
        RRAT_idx_valid[0] = 0;
        $display("\nopa(r0) opb(r1) index after retire r1 (40)");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d", RRAT_reg_out_out[0], RRAT_reg_out_out[1]);

        #10;
        @(negedge clock);
        $display("\nRetire 2 register (r1 r2)");
        RRAT_ARF_idx[0] = 1;
        RRAT_idx_valid[0] = 1;
        RRAT_PRF_idx[0] = 45;
        RRAT_ARF_idx[1] = 2;
        RRAT_idx_valid[1] = 1;
        RRAT_PRF_idx[1] = 41;
        @(negedge clock);
        RRAT_idx_valid[0] = 0;
        RRAT_idx_valid[1] = 0;
        $display("\nopa(r0) opb(r1) index after retire r1 (45)");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d", RRAT_reg_out_out[0], RRAT_reg_out_out[1]);
        $display("\nopa(r2) opb(r3) index after retire r2 (41)");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d", RRAT_reg_out_out[2], RRAT_reg_out_out[3]);

        #10;
        @(negedge clock);
        $display("\nRetire same register (r1) (42 43)");
        RRAT_ARF_idx[0] = 1;
        RRAT_idx_valid[0] = 1;
        RRAT_PRF_idx[0] = 42;
        RRAT_ARF_idx[1] = 1;
        RRAT_idx_valid[1] = 1;
        RRAT_PRF_idx[1] = 43;
        @(negedge clock);
        RRAT_idx_valid[0] = 0;
        RRAT_idx_valid[1] = 0;
        $display("\nopa(r0) opb(r1) index after retire r1");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d", RRAT_reg_out_out[0], RRAT_reg_out_out[1]);
        $display("\nopa(r2) opb(r3) index after retire r1");
        $display("opa_PRF_idx = %0d opb_PRF_idx = %0d", RRAT_reg_out_out[2], RRAT_reg_out_out[3]);

        #100;
		$display("@@@ Passed");
        $finish;
    end

endmodule