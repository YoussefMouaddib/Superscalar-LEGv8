`timescale 1ns/1ps
import core_pkg::*;

module branch_predictor #(
    parameter int BTB_ENTRIES = 256,      // 256-entry BTB
    parameter int XLEN = core_pkg::XLEN
)(
    input  logic                clk,
    input  logic                reset,
    
    // ============================================================
    // Prediction Request (from Fetch Stage)
    // ============================================================
    input  logic                predict_req,
    input  logic [XLEN-1:0]     predict_pc,
    
    output logic                predict_taken,
    output logic [XLEN-1:0]     predict_target,
    output logic                predict_valid,      // BTB hit
    
    // ============================================================
    // Update (from Branch Execution Unit)
    // ============================================================
    input  logic                update_en,
    input  logic [XLEN-1:0]     update_pc,
    input  logic                update_taken,       // Actual outcome
    input  logic [XLEN-1:0]     update_target,      // Actual target
    input  logic                update_is_branch,   // 1=conditional, 0=unconditional
    input  logic                update_is_call,
    input  logic                update_is_return,
    
    // ============================================================
    // Statistics (optional, for debugging/performance analysis)
    // ============================================================
    output logic [31:0]         stat_predictions,
    output logic [31:0]         stat_mispredictions,
    output logic [31:0]         stat_btb_hits,
    output logic [31:0]         stat_btb_misses
);

    // ============================================================
    // Local Parameters
    // ============================================================
    localparam int INDEX_BITS = $clog2(BTB_ENTRIES);
    localparam int TAG_BITS = XLEN - INDEX_BITS - 2;  // -2 for word alignment
    
    // 2-bit saturating counter states
    typedef enum logic [1:0] {
        STRONGLY_NOT_TAKEN = 2'b00,
        WEAKLY_NOT_TAKEN   = 2'b01,
        WEAKLY_TAKEN       = 2'b10,
        STRONGLY_TAKEN     = 2'b11
    } prediction_state_t;
    
    // Branch type encoding
    typedef enum logic [1:0] {
        COND_BRANCH = 2'b00,
        UNCOND_BRANCH = 2'b01,
        CALL = 2'b10,
        RETURN = 2'b11
    } branch_type_t;
    
    // ============================================================
    // BTB Entry Structure
    // ============================================================
    typedef struct packed {
        logic                     valid;
        logic [TAG_BITS-1:0]      tag;
        logic [XLEN-1:0]          target;
        prediction_state_t        counter;
        branch_type_t             br_type;
    } btb_entry_t;
    
    // ============================================================
    // BTB Storage
    // ============================================================
    btb_entry_t btb [0:BTB_ENTRIES-1];
    
    // ============================================================
    // Return Address Stack (RAS) for function calls/returns
    // ============================================================
    localparam int RAS_DEPTH = 8;
    logic [XLEN-1:0] ras [0:RAS_DEPTH-1];
    logic [2:0] ras_tos;  // Top of stack pointer
    
    // ============================================================
    // Index and Tag Extraction Functions
    // ============================================================
    function automatic logic [INDEX_BITS-1:0] get_index(input logic [XLEN-1:0] pc);
        return pc[INDEX_BITS+1:2];  // Word-aligned indexing
    endfunction
    
    function automatic logic [TAG_BITS-1:0] get_tag(input logic [XLEN-1:0] pc);
        return pc[XLEN-1:INDEX_BITS+2];
    endfunction
    
    // ============================================================
    // Prediction Logic (Combinational)
    // ============================================================
    logic [INDEX_BITS-1:0] pred_index;
    logic [TAG_BITS-1:0]   pred_tag;
    btb_entry_t            pred_entry;
    logic                  pred_btb_hit;
    
    always_comb begin
        // Extract index and tag
        pred_index = get_index(predict_pc);
        pred_tag = get_tag(predict_pc);
        
        // Read BTB entry
        pred_entry = btb[pred_index];
        
        // BTB hit check
        pred_btb_hit = pred_entry.valid && (pred_entry.tag == pred_tag);
        
        // Default outputs
        predict_valid = pred_btb_hit;
        predict_target = pred_entry.target;
        predict_taken = 1'b0;
        
        if (pred_btb_hit && predict_req) begin
            case (pred_entry.br_type)
                COND_BRANCH: begin
                    // Use 2-bit counter for conditional branches
                    predict_taken = (pred_entry.counter == WEAKLY_TAKEN) || 
                                   (pred_entry.counter == STRONGLY_TAKEN);
                end
                
                UNCOND_BRANCH: begin
                    // Always taken for unconditional branches
                    predict_taken = 1'b1;
                end
                
                CALL: begin
                    // Always taken for calls
                    predict_taken = 1'b1;
                end
                
                RETURN: begin
                    // Always taken for returns, target from RAS
                    predict_taken = 1'b1;
                    predict_target = ras[ras_tos];
                end
                
                default: begin
                    predict_taken = 1'b0;
                end
            endcase
        end
    end
    
    // ============================================================
    // Update Logic (Sequential)
    // ============================================================
    logic [INDEX_BITS-1:0] update_index;
    logic [TAG_BITS-1:0]   update_tag;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize BTB
            for (int i = 0; i < BTB_ENTRIES; i++) begin
                btb[i].valid <= 1'b0;
                btb[i].tag <= '0;
                btb[i].target <= '0;
                btb[i].counter <= WEAKLY_NOT_TAKEN;
                btb[i].br_type <= COND_BRANCH;
            end
            
            // Initialize RAS
            for (int i = 0; i < RAS_DEPTH; i++) begin
                ras[i] <= '0;
            end
            ras_tos <= '0;
            
            // Initialize statistics
            stat_predictions <= '0;
            stat_mispredictions <= '0;
            stat_btb_hits <= '0;
            stat_btb_misses <= '0;
            
        end else begin
            // ============================================================
            // BTB Update on Branch Resolution
            // ============================================================
            if (update_en) begin
                update_index = get_index(update_pc);
                update_tag = get_tag(update_pc);
                
                // Update BTB entry
                btb[update_index].valid <= 1'b1;
                btb[update_index].tag <= update_tag;
                btb[update_index].target <= update_target;
                
                // Set branch type
                if (update_is_return) begin
                    btb[update_index].br_type <= RETURN;
                end else if (update_is_call) begin
                    btb[update_index].br_type <= CALL;
                end else if (update_is_branch) begin
                    btb[update_index].br_type <= COND_BRANCH;
                end else begin
                    btb[update_index].br_type <= UNCOND_BRANCH;
                end
                
                // Update 2-bit saturating counter (only for conditional branches)
                if (update_is_branch) begin
                    case (btb[update_index].counter)
                        STRONGLY_NOT_TAKEN: begin
                            if (update_taken)
                                btb[update_index].counter <= WEAKLY_NOT_TAKEN;
                        end
                        
                        WEAKLY_NOT_TAKEN: begin
                            if (update_taken)
                                btb[update_index].counter <= WEAKLY_TAKEN;
                            else
                                btb[update_index].counter <= STRONGLY_NOT_TAKEN;
                        end
                        
                        WEAKLY_TAKEN: begin
                            if (update_taken)
                                btb[update_index].counter <= STRONGLY_TAKEN;
                            else
                                btb[update_index].counter <= WEAKLY_NOT_TAKEN;
                        end
                        
                        STRONGLY_TAKEN: begin
                            if (!update_taken)
                                btb[update_index].counter <= WEAKLY_TAKEN;
                        end
                        
                        default: begin
                            btb[update_index].counter <= WEAKLY_NOT_TAKEN;
                        end
                    endcase
                end else begin
                    // Non-conditional branches always strongly taken
                    btb[update_index].counter <= STRONGLY_TAKEN;
                end
            end
            
            // ============================================================
            // Return Address Stack (RAS) Management
            // ============================================================
            if (update_en) begin
                if (update_is_call) begin
                    // Push return address (PC + 4) onto RAS
                    ras_tos <= ras_tos + 1'b1;
                    ras[ras_tos + 1'b1] <= update_pc + 32'd4;
                end else if (update_is_return) begin
                    // Pop return address from RAS
                    if (ras_tos != 3'd0) begin
                        ras_tos <= ras_tos - 1'b1;
                    end
                end
            end
            
            // ============================================================
            // Statistics Update
            // ============================================================
            if (predict_req) begin
                stat_predictions <= stat_predictions + 1'b1;
                if (pred_btb_hit) begin
                    stat_btb_hits <= stat_btb_hits + 1'b1;
                end else begin
                    stat_btb_misses <= stat_btb_misses + 1'b1;
                end
            end
            
            //if (update_en) begin
                // Check for misprediction
               // automatic logic was_predicted_taken;
               // automatic logic btb_had_entry;
                
               // btb_had_entry = btb[update_index].valid && 
               //                (btb[update_index].tag == update_tag);
                
               // if (btb_had_entry) begin
               //     if (btb[update_index].br_type == COND_BRANCH) begin
                 //       was_predicted_taken = (btb[update_index].counter == WEAKLY_TAKEN) || 
                  //                           (btb[update_index].counter == STRONGLY_TAKEN);
                   // end else begin
                   //     was_predicted_taken = 1'b1;
                   // end
                    
                    // Misprediction if prediction doesn't match actual
                   // if (was_predicted_taken != update_taken) begin
                     /*   stat_mispredictions <= stat_mispredictions + 1'b1;
                    end
                end else begin
                    // BTB miss - if branch was taken, count as misprediction
                    if (update_taken) begin
                        stat_mispredictions <= stat_mispredictions + 1'b1;
                    end
                end 
            end*/
        end
    end
    
    // ============================================================
    // Assertions for Verification (synthesis translate_off)
    // ============================================================
    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (!reset && update_en) begin
            // Check for valid PC alignment
            if (update_pc[1:0] != 2'b00) begin
                $error("[BP] Misaligned update PC: %h", update_pc);
            end
            
            // Check for valid target alignment
            if (update_taken && update_target[1:0] != 2'b00) begin
                $error("[BP] Misaligned branch target: %h", update_target);
            end
        end
    end
    // synthesis translate_on

endmodule
