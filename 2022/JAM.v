module JAM (
    input CLK,
    input RST,
    output reg [2:0] W,
    output reg [2:0] J,
    input [6:0] Cost, // 0 ~ 100
    output reg [3:0] MatchCount, // 輸出符合最小成本可能組合的數量
    output reg [9:0] MinCost, // 輸出最小總工作成本的數值。
    output reg Valid 
);

    // term[i] 表示第 i 位工人分配到的工作編號 (0~7)
    reg [2:0] term [0:7];
    
    reg [9:0] current_sum;  // 當前排列的總成本
    reg [2:0] worker_index;   // 查詢工人編號（從 0 到 7）    

    //-----STATE-----
    reg [2:0] state;
    parameter  STATE_INIT = 3'd0,
               STATE_SEARCH = 3'd1,
               STATE_ADD = 3'd2,
               STATE_COMPARE = 3'd3, 
               STATE_FIND_K_LOOP = 3'd4, // 尋找替換點
               STATE_FIND_L_LOOP = 3'd5,
               STATE_REVERSE_LOOP = 3'd6,
               STATE_DONE = 3'd7;
    
    //---------------
    reg [2:0] k, l;          // 替換點 k 與 l
    reg [2:0] rev_i, rev_j;  // 反轉區間的索引

    
    always @(posedge CLK) begin
        if(RST)begin
            state <= STATE_INIT;
            //初始化排列 0 1 2 3 4 5 6 7 
            term[0] <= 3'd0;
            term[1] <= 3'd1;
            term[2] <= 3'd2;
            term[3] <= 3'd3;
            term[4] <= 3'd4;
            term[5] <= 3'd5;
            term[6] <= 3'd6;
            term[7] <= 3'd7;
            current_sum <= 10'd0;
            MinCost <= 10'd1023;
            MatchCount <= 4'd0;
            Valid <= 1'b0;
            worker_index <= 3'd0;
            W <= 3'd0;
            J <= 3'd0;
        end
        else begin
            case (state)
                STATE_INIT: begin
                    worker_index <= 3'd0;
                    current_sum <= 10'd0;
                    W <= worker_index;
                    J <= term[worker_index];
                    state <= STATE_SEARCH;                    
                end 

                STATE_SEARCH: begin // 查詢當前工人的當前工作
                    W <= worker_index+1;
                    J <= term[worker_index+1];
                    state <= STATE_ADD;
                end

                STATE_ADD: begin //讀取cost並累加
                   current_sum <= current_sum + Cost;
                   if (worker_index == 3'd7) begin
                        state <= STATE_COMPARE;
                   end
                   else begin
                        W <= worker_index+2;
                        J <= term[worker_index+2];
                        worker_index <= worker_index + 3'd1;
                        state <= STATE_ADD;
                   end 
                end

                STATE_COMPARE: begin //當前成本與目前MinCost比較
                    if (current_sum < MinCost) begin
                        MinCost <= current_sum;
                        MatchCount <= 4'd1;
                    end
                    else if (current_sum == MinCost) begin
                        MatchCount <= MatchCount + 4'd1;
                    end
                        k <= 3'd6;
                        state <= STATE_FIND_K_LOOP;
                end

                STATE_FIND_K_LOOP: begin // 找到最大的替換點 k
                    if (term[k] < term[k+1]) begin 
                        l <= 3'd7;
                        state <= STATE_FIND_L_LOOP;
                    end
                    else if (k == 3'd0) // 全排列結束
                        state <= STATE_DONE; 
                    else begin
                        if(term[k-1] < term[k])begin
                            k <= k - 1;
                            state <= STATE_FIND_L_LOOP;
                        end
                        else begin
                            k <= k - 1;
                            state <= STATE_FIND_K_LOOP;  
                        end
                    end
                end

                STATE_FIND_L_LOOP: begin // 找出比替換數大的最小數字
                  /* pivot 右側的子序列一定是降冪排序
                     只要從右往左掃描，遇到的第一個大於 pivot 的元素
                    ，即為該子序列中"最小的比 pivot 大"的元素。*/
                    if (term[l] > term[k]) begin
                        {term[k], term[l]} <= {term[l], term[k]};
                        rev_i <= k + 1;
                        rev_j <= 3'd7;
                        state <= STATE_REVERSE_LOOP;
                    end
                    else begin
                        l <= l - 1;
                       state <= STATE_FIND_L_LOOP; 
                    end
                end

                STATE_REVERSE_LOOP: begin
                    if (rev_i < rev_j) begin
                        {term[rev_i], term[rev_j]} <= {term[rev_j], term[rev_i]};
                        rev_i <= rev_i + 1;
                        rev_j <= rev_j - 1;
                        if(rev_i + 1 >= rev_j - 1)begin
                            current_sum <= 10'd0;
                            worker_index <= 3'd0;
                            state <= STATE_INIT; 
                        end
                        else;
                    end
                    else begin 
                        state <= STATE_INIT;
                        current_sum <= 10'd0;
                        worker_index <= 3'd0;
                    end
                end

                STATE_DONE: begin // 全排列結束
                    Valid <= 1'b1;
                    state <= STATE_DONE;
                end

                default: state <= STATE_INIT;
            endcase
        end
    end
endmodule
