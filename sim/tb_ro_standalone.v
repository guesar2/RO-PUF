// tb_ro_standalone: top-level smoke test with shortened times. With `SIM defined the
// ring is a 200 MHz clock, so count = 200 MHz * (window / 100 MHz) / 2 = window.

`timescale 1ps / 1ps
`default_nettype none

module tb_ro_standalone;

   localparam integer PERIOD  = 20000;
   localparam integer W_SHORT = 1000;
   localparam integer W_LONG  = 10000;

   reg        clk = 1'b0;
   reg        rstn = 1'b0;
   reg  [1:0] sw = 2'b00;
   wire [2:0] led;
   wire [7:0] an;
   wire       ca, cb, cc, cd, ce, cf, cg;

   integer errors = 0;

   always #5000 clk = ~clk;

   ro_standalone_top
     #(.PERIOD_CYCLES(PERIOD), .WINDOW_SHORT(W_SHORT), .WINDOW_LONG(W_LONG))
   dut
     (.clk(clk), .rstn(rstn), .i_sw(sw), .o_led(led), .AN(an),
      .CA(ca), .CB(cb), .CC(cc), .CD(cd), .CE(ce), .CF(cf), .CG(cg));

   task check(input [8*40-1:0] name, input integer got, input integer want, input integer tol);
      if (got < want - tol || got > want + tol) begin
         $display("FAIL: %0s: got %0d, want %0d +/- %0d", name, got, want, tol);
         errors = errors + 1;
      end else
        $display("ok:   %0s = %0d (want %0d +/- %0d)", name, got, want, tol);
   endtask

   // Segments are active low, in the order {a, b, c, d, e, f, g}.
   function [3:0] decode(input [6:0] s);
      case (s)
        7'b0000001: decode = 4'h0;
        7'b1001111: decode = 4'h1;
        7'b0010010: decode = 4'h2;
        7'b0000110: decode = 4'h3;
        7'b1001100: decode = 4'h4;
        7'b0100100: decode = 4'h5;
        7'b0100000: decode = 4'h6;
        7'b0001111: decode = 4'h7;
        7'b0000000: decode = 4'h8;
        7'b0001100: decode = 4'h9;
        7'b0001000: decode = 4'hA;
        7'b1100000: decode = 4'hB;
        7'b1110010: decode = 4'hC;
        7'b1000010: decode = 4'hD;
        7'b0110000: decode = 4'hE;
        7'b0111000: decode = 4'hF;
        default: begin
           $display("FAIL: invalid segment pattern %b at %0t", s, $time);
           errors = errors + 1;
           decode = 4'h0;
        end
      endcase
   endfunction

   // Reassembles the 32-bit value from the display, as a person reading it would.
   task read_display(output [31:0] value);
      integer d;
      integer seen;
      begin
         value = 32'd0;
         seen = 0;
         for (d = 0; d < 8; d = d + 1) begin
            wait (an == ~(8'd1 << d));
            @(negedge clk);
            value[4*d +: 4] = decode({ca, cb, cc, cd, ce, cf, cg});
            seen = seen + 1;
         end
         check("digits scanned", seen, 8, 0);
      end
   endtask

   integer runs;
   integer run_starts = 0;
   reg [31:0] disp;
   reg        hb;

   always @(posedge dut.ro_run) run_starts = run_starts + 1;

   initial begin
      repeat (10) @(negedge clk);
      rstn = 1'b1;

      // SW0 off: the ring never starts.
      repeat (3 * PERIOD) @(negedge clk);
      check("no RO starts with SW0 off", run_starts, 0, 0);
      check("display count with SW0 off", dut.shown, 0, 0);

      // Short window. Two periods make sure a full measurement has landed.
      sw = 2'b01;
      repeat (2 * PERIOD) @(negedge clk);
      check("LED0 mirrors SW0", led[0], 1, 0);
      check("short count", dut.shown, W_SHORT, 1);
      check("LED2 short", led[2], 0, 0);
      read_display(disp);
      check("display short", disp, W_SHORT, 1);
      hb = led[1];
      repeat (PERIOD) @(negedge clk);
      check("LED1 toggles per measurement", led[1], !hb, 0);

      // Long window, and the 10:1 ratio.
      sw = 2'b11;
      repeat (2 * PERIOD) @(negedge clk);
      check("long count", dut.shown, W_LONG, 1);
      check("LED2 long", led[2], 1, 0);
      read_display(disp);
      check("display long", disp, W_LONG, 1);

      // SW0 off again: the last count holds and the ring stays stopped.
      sw = 2'b00;
      repeat (2 * PERIOD) @(negedge clk);
      runs = run_starts;
      repeat (3 * PERIOD) @(negedge clk);
      check("no more RO starts after SW0 off", run_starts, runs, 0);
      check("ro_run low after SW0 off", dut.ro_run, 0, 0);
      check("count held after SW0 off", dut.shown, W_LONG, 1);

      if (errors == 0) $display("TB PASS");
      else             $display("TB FAIL (%0d errors)", errors);
      $finish;
   end

endmodule

`default_nettype wire
