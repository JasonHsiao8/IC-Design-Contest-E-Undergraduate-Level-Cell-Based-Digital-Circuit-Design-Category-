module LASER (
    input CLK,
    input RST,
    input [3:0] X,
    input [3:0] Y,
    output reg [3:0] C1X,
    output reg [3:0] C1Y,
    output reg [3:0] C2X,
    output reg [3:0] C2Y,
    output reg DONE
);
    // 目標點儲存記憶體 (40個目標點)
    reg [3:0] target_x [0:39]; // each target's x position(0~15)
    reg [3:0] target_y [0:39];
    reg [15:0] input_count; // from 0 to 39

    // State define
    parameter STATE_INPUT          = 4'd0, // 讀資料
              STATE_INIT           = 4'd1, // 初始化
              STATE_ITER_C2_INIT   = 4'd2, // 搜尋circle2
              STATE_ITER_C2_CALC   = 4'd3, // 計算覆蓋數
              STATE_ITER_C2_UPDATE = 4'd4,
              STATE_ITER_C2_DONE   = 4'd5,
              STATE_ITER_C1_INIT   = 4'd6,
              STATE_ITER_C1_CALC   = 4'd7,
              STATE_ITER_C1_UPDATE = 4'd8,
              STATE_ITER_C1_DONE   = 4'd9,
              STATE_CHECK          = 4'd10,
              STATE_OUTPUT         = 4'd11;

        reg [3:0] state;

        // 用來儲存迭代結果（目前最佳的圓心位置）
        reg [3:0] bestC1X, bestC1Y;
        reg [3:0] bestC2X, bestC2Y; 
        
        // 儲存上一輪結果，便於檢查是否收斂
        reg [3:0] oldC1X, oldC1Y;
        reg [3:0] oldC2X, oldC2Y;

        // 候選點搜尋相關變數（用於遍歷 16x16 的候選位置，尋找最佳候選點）
        reg [3:0] cand_x, cand_y;
        reg [5:0] targ_idx; // 0 ~ 39

        // 用來計算覆蓋數的變數
        reg [5:0] temp_count;  // 當前候選點覆蓋數
        reg [5:0] best_count;  // 當前搜尋到的最佳覆蓋數

        // 暫存當前候選點最佳結果
        reg [3:0] temp_bestX, temp_bestY;

        //---------------------------------------
        // 判斷目標物是否在以 (cx, cy) 為圓心，半徑為 4 的圓內
        function automatic in_circle; //automatic 關鍵字表示該函式的區域變數會在每次呼叫時自動分配（類似堆疊記憶體）
            input [3:0] cx, cy; // 圓心座標 circle
            input [3:0] tx, ty; // 目標物座標 target
            reg [3:0] dx, dy; // x, y軸分別距離 difference
            reg [7:0] distance;
            begin
                dx = (tx >= cx) ? (tx - cx) : (cx - tx);
                dy = (ty >= cy) ? (ty - cy) : (cy - ty);
                distance = dx * dx + dy * dy;
                in_circle = (distance <= 8'd16) ? 1'b1 : 1'b0 ; // 小於等於4平方 -> 在園內
            end
        endfunction
        /*使用 automatic，函式內的區域變數在每次函式呼叫時都是獨立的，
        這樣可以防止多個呼叫（例如並行呼叫或遞迴呼叫）之間互相干擾。*/
        //---------------------------------------
        
        always @(posedge CLK) begin
            if (RST) begin
                // RST 為high時，將所有變數初始化
                state       <= STATE_INPUT;
                input_count <= 0;
                DONE        <= 0;
                C1X         <= 0;
                C1Y         <= 0;
                C2X         <= 0;
                C2Y         <= 0;
                bestC1X     <= 0;
                bestC1Y     <= 0;
                bestC2X     <= 0;
                bestC2Y     <= 0;
                oldC1X      <= 0;
                oldC1Y      <= 0;
                oldC2X      <= 0;
                oldC2Y      <= 0;
            end else begin
                case(state)
                STATE_INPUT: begin // 40 cycle
                    DONE <= 0;
                    // 將每筆輸入存入陣列
                    target_x[input_count] <= X;
                    target_y[input_count] <= Y;
                    input_count <= input_count + 1;
                    if(input_count == 6'd39) begin
                        input_count <= 0;
                        state <= STATE_INIT;  // 讀滿 40 筆資料後進入初始化階段
                    end
                end

                STATE_INIT: begin
                    bestC1X <= 4'd0; bestC1Y <= 4'd0;
                    bestC2X <= 4'd15; bestC2Y <= 4'd15;
                    oldC1X <= 4'd0; oldC1Y <= 4'd0;
                    oldC2X <= 4'd15; oldC2Y <= 4'd15;  
                    state <= STATE_ITER_C2_INIT;
                end

                STATE_ITER_C2_INIT: begin
                    cand_x <= 2; // start from (0,0)
                    cand_y <= 2;
                    targ_idx <= 0;
                    best_count <= 0;
                    temp_count <= 0;
                    temp_bestX <= 0;
                    temp_bestY <= 0;
                    state <= STATE_ITER_C2_CALC;
                end

                STATE_ITER_C2_CALC: begin // 兩圓不動，看40個target有無被覆蓋 // 3
                    // 判斷該target是否被固定一及動圓二覆蓋
                    if(in_circle(bestC1X, bestC1Y, target_x[targ_idx], target_y[targ_idx]) ||
                       in_circle(cand_x, cand_y, target_x[targ_idx], target_y[targ_idx]))
                        temp_count <= temp_count + 1;
                    targ_idx <= targ_idx + 1;
                    if(targ_idx == 6'd39) state <= STATE_ITER_C2_UPDATE;
                end

                STATE_ITER_C2_UPDATE: begin // 微調圓二 // 4
                    if(temp_count > best_count)begin
                        best_count <= temp_count;
                        temp_bestX <= cand_x;
                        temp_bestY <= cand_y;
                    end
                    // 重設累計與target label index，準備下一個候選點
                    temp_count <= 0;
                    targ_idx <= 0;
                    // 依序更新候選點，先更動 X，再更動 Y
                    if(cand_x < 4'd13) begin 
                        cand_x <= cand_x + 1;
                        state <= STATE_ITER_C2_CALC;
                    end
                    else begin
                        cand_x <= 2;
                        if (cand_y < 4'd13) begin 
                            cand_y <= cand_y + 1;
                            state <= STATE_ITER_C2_CALC;
                        end
                        else begin // 候選區域已全部跑完
                            bestC2X <= temp_bestX;
                            bestC2Y <= temp_bestY;
                            state <= STATE_ITER_C2_DONE;
                        end
                    end
                end

                STATE_ITER_C2_DONE: begin
                    state <= STATE_ITER_C1_INIT; // 完成圓二搜尋後，開始搜尋圓一
                end

                STATE_ITER_C1_INIT: begin
                    cand_x   <= 2;
                    cand_y   <= 2;
                    targ_idx <= 0;
                    best_count <= 0;
                    temp_count <= 0;
                    temp_bestX <= 0;
                    temp_bestY <= 0;
                    state <= STATE_ITER_C1_CALC;
                end

                STATE_ITER_C1_CALC: begin
                    if (in_circle(cand_x, cand_y, target_x[targ_idx], target_y[targ_idx]) ||
                        in_circle(bestC2X, bestC2Y, target_x[targ_idx], target_y[targ_idx]) )
                        temp_count <= temp_count + 1;
                    targ_idx <= targ_idx + 1;
                    if(targ_idx == 6'd39) begin
                        state <= STATE_ITER_C1_UPDATE;
                    end
                end
                
                STATE_ITER_C1_UPDATE: begin
                    if(temp_count > best_count) begin
                        best_count <= temp_count;
                        temp_bestX <= cand_x;
                        temp_bestY <= cand_y;
                    end
                    temp_count <= 0;
                    targ_idx <= 0;
                    if(cand_x < 4'd13) begin
                        cand_x <= cand_x + 1;
                        state <= STATE_ITER_C1_CALC;
                    end
                    else begin
                        cand_x <= 2;
                        if(cand_y < 4'd13) begin
                            cand_y <= cand_y + 1;
                            state <= STATE_ITER_C1_CALC;
                        end
                        else begin
                            bestC1X <= temp_bestX;
                            bestC1Y <= temp_bestY;
                            state <= STATE_ITER_C1_DONE;
                        end
                    end
                end
        
                STATE_ITER_C1_DONE: begin
                    state <= STATE_CHECK;
                end
                
                STATE_CHECK: begin
                    if((bestC1X != oldC1X) || (bestC1Y != oldC1Y) ||
                    (bestC2X != oldC2X) || (bestC2Y != oldC2Y)) begin
                     // 有變動，更新舊值並重新進入迭代（從圓二搜尋開始）
                        oldC1X <= bestC1X;
                        oldC1Y <= bestC1Y;
                        oldC2X <= bestC2X;
                        oldC2Y <= bestC2Y;
                        state <= STATE_ITER_C2_INIT;
                    end
                    else begin
                        // 無變動，收斂，進入輸出階段
                        state <= STATE_OUTPUT;
                    end
                end

                STATE_OUTPUT: begin
                    C1X  <= bestC1X;
                    C1Y  <= bestC1Y;
                    C2X  <= bestC2X;
                    C2Y  <= bestC2Y;
                    DONE <= 1; // 拉高 DONE 表示完成計算
                    // 此處可以等待 testbench 重設 RST 以進入下一組 pattern
                    state <= STATE_INPUT;
                end        
                endcase
            end
        end
endmodule
