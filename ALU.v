module ALU(
    input [31:0] A,
    input [31:0] B,
    input [3:0] CONTROL,
    output reg [31:0] RESULT,
    output reg ZEROFLAG
);
    always @(*) begin
        case (CONTROL)
            4'b0000: RESULT = A & B;                    // AND
            4'b0001: RESULT = A | B;                    // OR  
            4'b0010: RESULT = A + B;                    // ADD
            4'b0011: RESULT = A - B;                    // SUB
            4'b0100: RESULT = A ^ B;                    // XOR
            4'b0101: RESULT = B;                        // MOV (uses B input)
            4'b0110: RESULT = {B[15:0], 16'b0};         // LUI (uses B input)
            4'b0111: RESULT = A << B[4:0];              // SLL
            4'b1000: RESULT = A >> B[4:0];              // SRL
            4'b1001: RESULT = $signed(A) >>> B[4:0];    // SRA
            default:  RESULT = 32'hxxxxxxxx;
        endcase
        
        ZEROFLAG = (RESULT == 0);
    end
endmodule
