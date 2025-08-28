module branch_predictor #(
    parameter SIZE    = 128,      //Size of BHT
    parameter P_SIZE  = 128,      //Size of PHT
    parameter BTB_SET = 32,       //Num of set of BTB
    parameter BTB_WAY = 4 )(      //Num of way of BTB
    // Input
    input clock, reset,
    input [31:0]                    PC,
    input [1:0]                          is_branch,        // 表示目前的 instruction 是否為 branch 類型
    input [1:0]                          is_valid,         // 表示目前的 instruction 是否有效

    input [1:0] [31:0]              PC_update,        // resolved 的 branch 的 PC
    input [1:0]                          direction_update, // resolved 的 branch 應該要 taken / not taken
    input [1:0] [31:0]              target_update,    // resolved 的 branch 應該要去的 target
    input [1:0]                          valid_update,     

    // Output
    output logic [31:0]             next_PC,          // tournament 最終選擇的 PC
    output logic [1:0]                   prediction        // tournament 最終 prediction
    );

    logic [BTB_SET-1:0] [BTB_WAY-1:0] [31:0]     BTB_PC;            // BTB 用來存對應的 PC
    logic [BTB_SET-1:0] [BTB_WAY-1:0] [31:0]     BTB_target;        // BTB 用來存要去的target
    logic [BTB_SET-1:0] [BTB_WAY-1:0]                 BTB_valid;         // BTB 存 valid bit

    // Local prediction (Per-PC)
    logic [SIZE-1:0] [$clog2(P_SIZE)-1:0]             BHT;               // 7 bits BHT
    logic [P_SIZE-1:0]  [1:0]                         PHT;               // 2-bit saturation (ST/WT/WNT/SNT)
    logic [1:0]                                       local_prediction;  // local branch prediction 的結果

    // Global prediction (Gshare)
    logic [$clog2(P_SIZE)-1:0]                        GHR;               // 7 bits Gloabal History Register
    logic [P_SIZE-1:0] [1:0]                          GSHARE;            // 2-bit saturation
    logic [1:0] [$clog2(P_SIZE)-1:0]                  index;             // 要預測的 PC 和 GHR 做 XOR
    logic [1:0] [$clog2(P_SIZE)-1:0]                  index_update;      // branch resolve 後的 PC 和 GHR 做 XOR
    logic [1:0]                                       global_prediction; // Gshare prediction的結果

    // Tournament selector (選擇要使用 Local or Global)
    logic [SIZE-1:0] [$clog2(P_SIZE)-1:0]             sel_BHT;
    logic [P_SIZE-1:0]  [1:0]                         sel_PHT;           // 2-bit saturation (00,01: choose LOCAL / 10,11: choose Gshare)
    logic                                             selection;         // 0: LOCAL / 1: GSHARE
    logic                                             local_correct;     // 用來判斷local預測是否成功(1: 代表預測和真實direction相同/0: 代表預測和真實direction不同)
    logic                                             global_correct;    // 用來判斷gshare預測是否成功(1: 代表預測和真實direction相同/0: 代表預測和真實direction不同)

    logic                                             branch;            // 已經找到要跳去的branch
    logic [$clog2(BTB_WAY):0]                         LRU;               // Least Recently Used
    logic                                             branch_h;   
    logic [1:0]                                       branch_t;

    always_comb begin
        for (int i = 0; i < 2; i++) begin
            index[i]        = (PC[$clog2(P_SIZE)+1:2] + i) ^ GHR;
            index_update[i] = PC_update[i][$clog2(P_SIZE)+1:2] ^ GHR;
        end
    end

    // 進行預測：Local 和 Global 對於進來的 PC 去查看各自是否為 taken / not taken
    always_comb begin
        local_prediction  = 0;
        branch            = 0;
        global_prediction = 0;
        selection         = 0;
        branch_h          = ((is_branch[0]  && is_valid[0]) || (is_branch[1] && is_valid[1]));
        for(int i = 0; i < 2; i++) begin
            // PHT 使用 2-bit, bit[0]表示strong/weak, bit[1]表示taken/not taken
            // 利用PC的log2(SIZE)個bit來找出對應的BHT entry，並利用該BHT內的數據指向對應的PHT entry
            // 透過該PHT中bit[1]來檢查是否為taken/not taken，若是taken且為branch指令且valid則預測
            if(PHT[BHT[(PC[$clog2(SIZE)+1:2] + i)]][1] && is_branch[i] && is_valid[i]) begin
                for(int j = 0; j < BTB_WAY; j++) begin
                    if(BTB_valid[(PC[$clog2(BTB_SET)+1:2]+i)][j] == 1 && BTB_PC[(PC[$clog2(BTB_SET)+1:2]+i)][j] == (PC+(i*4))) begin  
                        local_prediction[i] = 1;        // 預測為 taken
                        branch              = 1;        // 若 branch == 1, 結束整個迴圈
                        break;
                    end
                end
            end
            if (GSHARE[index[i]][1] && is_branch[i] && is_valid[i]) begin
                for(int j = 0; j < BTB_WAY; j++) begin
                    if(BTB_valid[(PC[$clog2(BTB_SET)+1:2]+i)][j] == 1 && BTB_PC[(PC[$clog2(BTB_SET)+1:2]+i)][j] == (PC+(i*4))) begin
                        global_prediction[i] = 1;
                        branch               = 1;
                        break;
                    end
                end
            end
            // 透過該sel_PHT中bit[1]來檢查是LOCAL/Gshare，若是Gshare且為branch指令且valid則預測
            if (sel_PHT[sel_BHT[(PC[$clog2(SIZE)+1:2] + i)]][1] && is_branch[i] && is_valid[i]) begin
                selection = 1;
            end
            if(branch)
                break;
        end
    end

    // 更新BTB：透過 resolved 的 branch 來更新以及各自predictor 的 PHT。
    always_ff @ (posedge clock) begin
        if(reset) begin
            BTB_valid  <=  0;
            BHT        <=  0;
            BTB_PC     <=  0;
            BTB_target <=  0;
            GHR        <=  0;
            for(int i = 0; i < P_SIZE; i++) begin
                PHT[i]    <= 2'b01;
                GSHARE[i] <= 2'b01;
            end
        end
        else begin
            for(int i = 0; i < 2; i++) begin
                if(valid_update[i]) begin
                    // 若 branch 真的 taken 的話，要如何更新
                    if(direction_update[i]) begin
                        // 更新 BHT
                        // 若第 i 個 instruction taken，則將 BHT shift 1 進來 (0000011 -> 0000111)
                        BHT[PC_update[i][$clog2(SIZE)+1:2]] <= {BHT[PC_update[i][$clog2(SIZE)+1:2]][$clog2(P_SIZE)-2:0],1'b1};
                        
                        // 更新 GHR
                        GHR <= {GHR[$clog2(P_SIZE)-2:0], 1'b1};
                        
                        // 更新 PHT
                        // 若目前 PHT pattern 不是 strongly taken, 則讓 PHT pattern + 1
                        if(PHT[BHT[PC_update[i][$clog2(SIZE)+1:2]]] < 2'b11) begin
                            PHT[BHT[PC_update[i][$clog2(SIZE)+1:2]]] <= PHT[BHT[PC_update[i][$clog2(SIZE)+1:2]]] + 1;
                        end
                        
                        // 更新 GSHARE
                        if (GSHARE[PC_update[i][$clog2(P_SIZE)+1:2]] < 2'b11) begin
                            GSHARE[index_update[i]] <= GSHARE[index_update[i]] + 1;
                        end

                        // 更新 BTB
                        LRU = BTB_WAY;
                        for(int j = 0; j < BTB_WAY; j++) begin
                            if(BTB_valid[PC_update[i][$clog2(BTB_SET)+1:2]][j] == 1 && BTB_PC[PC_update[i][$clog2(BTB_SET)+1:2]][j] == PC_update[i]) begin
                                LRU = j;
                                break;
                            end
                        end

                        // 在 taken 的時候，把 PC, branch target 跟 valid 更新放進 PC 對應的 BTB slot
                        // BTB[0]永遠是最新的data，透過LRU更新BTB[1~3]將重複的換掉。
                        BTB_PC      [PC_update[i][$clog2(BTB_SET)+1:2]][0]  <=  PC_update[i];
                        BTB_target  [PC_update[i][$clog2(BTB_SET)+1:2]][0]  <=  target_update[i];
                        BTB_valid   [PC_update[i][$clog2(BTB_SET)+1:2]][0]  <=  1'b1;

                        for (int j = 1; j < BTB_WAY; j++) begin
                            if(j < LRU + 1) begin
                                BTB_PC      [PC_update[i][$clog2(BTB_SET)+1:2]][j]  <=  BTB_PC       [PC_update[i][$clog2(BTB_SET)+1:2]][j-1];
                                BTB_target  [PC_update[i][$clog2(BTB_SET)+1:2]][j]  <=  BTB_target   [PC_update[i][$clog2(BTB_SET)+1:2]][j-1];
                                BTB_valid   [PC_update[i][$clog2(BTB_SET)+1:2]][j]  <=  BTB_valid    [PC_update[i][$clog2(BTB_SET)+1:2]][j-1];
                            end
                        end
                    end

                    // 若 branch 是 not taken 的話，要怎麼更新
                    else begin
                        // 更新 BHT
                        // 若第 i 個 intruction not taken，則將 BHT shift 0 進來 (0000011 -> 0000110)
                        BHT[PC_update[i][$clog2(SIZE)+1:2]] <= {BHT[PC_update[i][$clog2(SIZE)+1:2]][$clog2(P_SIZE)-2:0],1'b0};
                        
                        // 更新GHR
                        GHR <= {GHR[$clog2(P_SIZE)-2:0], 1'b0};

                        // 更新PHT
                        // 若目前 PHT pattern 不是 strongly not taken, 則讓 PHT pattern - 1
                        if(PHT[BHT[PC_update[i][$clog2(SIZE)+1:2]]] > 2'b00) begin
                            PHT[BHT[PC_update[i][$clog2(SIZE)+1:2]]] <= PHT[BHT[PC_update[i][$clog2(SIZE)+1:2]]] - 1;
                        end

                        // 更新GSHARE
                        if (GSHARE[PC_update[i][$clog2(P_SIZE)+1:2]] > 2'b00) begin
                            GSHARE[index_update[i]] <= GSHARE[index_update[i]] - 1;
                        end
                    end
                end // if valid_update
            end // loop
        end // if(!reset)
    end // always_ff

    // 判斷預測對錯logic：透過 resolved 的 direction 來更新，可以知道之前預測時兩者的正確性。
    always_comb begin
        if(reset) begin
            local_correct  = 0;
            global_correct = 0;
        end
        else begin
            for(int i = 0; i < 2; i++) begin
                if(valid_update[i]) begin
                    local_correct  = (PHT[BHT[PC_update[i][$clog2(SIZE)+1:2]]][1] == direction_update[i]);
                    global_correct = (GSHARE[index_update[i]][1] == direction_update[i]);
                end
                else begin
                    local_correct  = 0;
                    global_correct = 0;
                end
            end
        end
    end

    // 用於更新 sel_PHT, sel_BHT
    always_ff @ (posedge clock) begin
        if(reset) begin
            sel_BHT <= 0;
            for(int i = 0; i < P_SIZE; i++) begin
                sel_PHT[i] <= 2'b01;            // 初始化選擇LOCAL
            end
        end
        else begin
            for (int i = 0; i < 2; i++) begin
                if (valid_update[i]) begin
                    // 如果selector的當時選擇 GSHARE
                    if (sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]][1] == 1) begin
                        // 當時使用 GSHARE 預測時是否正確
                        // 若 GSHARE 預測成功，LOCAL預測失敗，則 sel_PHT + 1
                        if (global_correct && !local_correct) begin
                            sel_BHT[PC_update[i][$clog2(SIZE)+1:2]] <= {sel_BHT[PC_update[i][$clog2(SIZE)+1:2]][$clog2(P_SIZE)-2:0], 1'b1};
                            if (sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] < 2'b11) begin
                                sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] <= sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] + 1;
                            end
                        end
                        // 若 LOCAL 預測成功，GSHARE 預測失敗，則 sel_PHT - 1
                        else if (!global_correct && local_correct) begin
                            sel_BHT[PC_update[i][$clog2(SIZE)+1:2]] <= {sel_BHT[PC_update[i][$clog2(SIZE)+1:2]][$clog2(P_SIZE)-2:0], 1'b0};
                            if (sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] > 2'b00) begin
                                sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] <= sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] - 1;
                            end
                        end
                    end
                    // 如果selector的當時選擇 LOCAL
                    else begin
                        // 當時使用 LOCAL 預測時是否正確
                        // 若 LOCAL 預測成功，GSHARE 預測失敗，則 sel_PHT - 1
                        if (local_correct && !global_correct) begin
                            sel_BHT[PC_update[i][$clog2(SIZE)+1:2]] <= {sel_BHT[PC_update[i][$clog2(SIZE)+1:2]][$clog2(P_SIZE)-2:0], 1'b0};
                            if (sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] > 2'b00) begin
                                sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] <= sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] - 1;
                            end
                        end
                        // 若 GSHARE 預測成功，LOCAL 預測失敗，則 sel_PHT + 1
                        else if (!local_correct && global_correct) begin
                            sel_BHT[PC_update[i][$clog2(SIZE)+1:2]] <= {sel_BHT[PC_update[i][$clog2(SIZE)+1:2]][$clog2(P_SIZE)-2:0], 1'b1};
                            if (sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] < 2'b11) begin
                                sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] <= sel_PHT[sel_BHT[PC_update[i][$clog2(SIZE)+1:2]]] + 1;
                            end
                        end
                    end
                end
            end
        end
    end

    // prediction 是根據 tournament selector 的 selection 來決定要使用 global or local 的 taken / not taken。
    assign branch_t = {(is_branch[1]  && is_valid[1]) , (is_branch[0] && is_valid[0])} ;
    assign prediction = branch_h ? branch_t : (selection) ? global_prediction : local_prediction;

    always_comb begin
      next_PC = PC + 8;
        // prediction 如果 taken，就要把 BTB 的 target 給 next_PC
        if(prediction != 0) begin
            for(int i = 0; i < 2; i++) begin
                for(int j = 0; j < BTB_WAY; j++) begin
                    if(BTB_valid[(PC[$clog2(BTB_SET)+1:2]+i)][j] == 1 && BTB_PC[(PC[$clog2(BTB_SET)+1:2]+i)][j] == (PC+(i*4)))begin
                        next_PC = branch_h ? PC + 8 : BTB_target[(PC[$clog2(BTB_SET)+1:2]+i)][j]; // 從 BTB 拿 PC 對應到的 branch target
                    end
                    else begin
                      next_PC = PC + 8;
                    end
                end
            end
        end
        else begin
            next_PC = PC + 8;
        end
    end
endmodule
