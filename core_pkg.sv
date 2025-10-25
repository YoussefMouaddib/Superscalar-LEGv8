// core_pkg.sv
// Central parameters for the minimal-OOO core (locked scope)
package core_pkg;

  // --- Datapath widths
  parameter int XLEN        = 32;   // data/register width
  parameter int ARCH_REGS   = 32;   // architectural registers (x0..x31)
  parameter int PREGS       = 48;   // physical register count (PRF)
  parameter int ROB_ENTRIES = 16;   // reorder buffer entries
  parameter int IQ_ENTRIES  = 16;   // issue queue / window entries
  parameter int LSQ_ENTRIES = 16;   // load/store queue total
  parameter int FETCH_WIDTH = 2;    // fetch bundle width
  parameter int ISSUE_WIDTH = 2;    // issue width

  // tagging sizes
  localparam int LOG2_PREGS = (PREGS <= 1) ? 1 : $clog2(PREGS);
  localparam int LOG2_ARCH  = (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS);

  typedef logic [XLEN-1:0]  reg_t;
  typedef logic [LOG2_PREGS-1:0] preg_tag_t;
  typedef logic [LOG2_ARCH-1:0]  areg_tag_t;

endpackage : core_pkg
