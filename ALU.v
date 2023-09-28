`include "menu.vh"

module ALU(

    input [`WORD-1:0] data_1, data_2,
    input [3:0] control,
    output reg [`WORD-1:0] result,
    output reg flag
    );
    
    always @(*)begin
            case(control)
            
            default: begin            
                result <= data_1 & data_2;            
            end
            
            `alu_add: begin        
                result <= data_1 + data_2;            
            end
             
            `alu_cbz: begin         
                result <= data_2;          
            end
             
            `alu_and: begin         
                 result <= data_1 & data_2;        
            end
            
            `alu_orr: begin         
                 result <= data_1 | data_2;        
            end
            
            `alu_sub: begin         
                 result <= data_1 - data_2;        
            end
            
            endcase
            
        flag <= (result == 0);
    end
    
endmodule