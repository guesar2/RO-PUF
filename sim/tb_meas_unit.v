// tb_meas_unit: checks meas_unit with two known clocks standing in for the ROs.
// The RO models run only while ro_run = 1 and rest at 1, like the real ring.

`timescale 1ps / 1ps
`default_nettype none

module tb_meas_unit;

   localparam integer CLK_HALF_PS = 5000;  // 100 MHz

   reg         clk = 1'b0;
   reg         rst = 1'b1;
   reg         start = 1'b0;
   reg  [31:0] window = 32'd0;
   reg         ro_a = 1'b1;
   reg         ro_b = 1'b1;
   wire        ro_run;
   wire        busy;
   wire        done;
   wire [31:0] count_a;
   wire [31:0] count_b;

   integer half_a = 2500;    // 200 MHz
   integer half_b = 1515;    // about 330 MHz
   reg     alive_b = 1'b1;
   integer errors = 0;

   always #(CLK_HALF_PS) clk = ~clk;

   always begin
      if (ro_run) begin
         #(half_a);
         ro_a = ro_run ? ~ro_a : 1'b1;
      end else begin
         ro_a = 1'b1;
         @(ro_run);
      end
   end

   always begin
      if (ro_run && alive_b) begin
         #(half_b);
         ro_b = ro_run ? ~ro_b : 1'b1;
      end else begin
         ro_b = 1'b1;
         @(ro_run or alive_b);
      end
   end

   meas_unit dut
     (.clk(clk), .rst(rst), .start(start), .window(window),
      .ro_clk_a(ro_a), .ro_clk_b(ro_b),
      .ro_run(ro_run), .busy(busy), .done(done),
      .count_a(count_a), .count_b(count_b));

   // Measures how long the gate stays open, in ps.
   time gate_rise = 0;
   time gate_len  = 0;
   always @(posedge dut.gate) gate_rise = $time;
   always @(negedge dut.gate) gate_len  = $time - gate_rise;

   // The clear must never overlap a running RO.
   always @(posedge clk)
     if (!rst && dut.clr && ro_run) begin
        $display("FAIL: clear asserted while ro_run = 1 at %0t", $time);
        errors = errors + 1;
     end

   task check(input [8*40-1:0] name, input integer got, input integer want, input integer tol);
      if (got < want - tol || got > want + tol) begin
         $display("FAIL: %0s: got %0d, want %0d +/- %0d", name, got, want, tol);
         errors = errors + 1;
      end else
        $display("ok:   %0s = %0d (want %0d +/- %0d)", name, got, want, tol);
   endtask

   task pulse_start;
      begin
         @(negedge clk);
         start = 1'b1;
         @(negedge clk);
         start = 1'b0;
      end
   endtask

   task wait_done;
      integer guard;
      begin
         guard = 0;
         while (!done && guard < 2000000) begin
            @(negedge clk);
            guard = guard + 1;
         end
         if (!done) begin
            $display("FAIL: timed out waiting for done");
            errors = errors + 1;
            $display("TB FAIL (%0d errors)", errors);
            $finish;
         end
      end
   endtask

   // Expected count = f * T / 2 with T = window * 10 ns. Half periods are in ps.
   function integer expected(input integer win, input integer half_ps);
      expected = (win * 10000) / (4 * half_ps);
   endfunction

   integer i;
   integer t_a, t_b;
   integer run_cycles;

   initial begin
      repeat (5) @(negedge clk);
      rst = 1'b0;
      @(negedge clk);

      check("idle busy", busy, 0, 0);
      check("idle done", done, 0, 0);
      check("idle ro_run", ro_run, 0, 0);

      // Both channels at different frequencies.
      window = 32'd1000;
      pulse_start;
      @(negedge clk);
      check("busy after start", busy, 1, 0);
      check("done cleared by start", done, 0, 0);
      wait_done;
      check("busy with done", busy, 0, 0);
      check("ro_run with done", ro_run, 0, 0);
      check("gate length (ps)", gate_len, 1000 * 2 * CLK_HALF_PS, 0);
      check("count_a 200 MHz, 1000 cycles", count_a, expected(1000, half_a), 1);
      check("count_b 330 MHz, 1000 cycles", count_b, expected(1000, half_b), 1);

      // Counts and done hold while idle.
      t_a = count_a;
      t_b = count_b;
      repeat (200) @(negedge clk);
      check("count_a holds", count_a, t_a, 0);
      check("count_b holds", count_b, t_b, 0);
      check("done holds", done, 1, 0);

      // A restart clears the old counts, with a different window.
      window = 32'd4000;
      pulse_start;
      repeat (6) @(negedge clk);
      check("count_a cleared on restart", count_a, 0, 0);
      check("count_b cleared on restart", count_b, 0, 0);
      wait_done;
      check("gate length 4000 (ps)", gate_len, 4000 * 2 * CLK_HALF_PS, 0);
      check("count_a 200 MHz, 4000 cycles", count_a, expected(4000, half_a), 1);
      check("count_b 330 MHz, 4000 cycles", count_b, expected(4000, half_b), 1);

      // Start while busy is ignored, and a change of window during busy has no effect.
      window = 32'd1000;
      pulse_start;
      run_cycles = 0;
      repeat (100) @(negedge clk);
      window = 32'd50;
      pulse_start;
      wait_done;
      window = 32'd1000;
      check("gate length with start while busy (ps)", gate_len, 1000 * 2 * CLK_HALF_PS, 0);
      check("count_a with start while busy", count_a, expected(1000, half_a), 1);

      // Slow and fast limits of the estimated range, from several clock phases.
      for (i = 0; i < 8; i = i + 1) begin
         half_a = 2941 + i * 7;   // about 170 MHz
         half_b = 1515 + i * 3;   // about 330 MHz
         window = 32'd2000 + i;
         pulse_start;
         wait_done;
         check("count_a sweep", count_a, expected(2000 + i, half_a), 1);
         check("count_b sweep", count_b, expected(2000 + i, half_b), 1);
      end

      // A dead RO reads 0, and the FSM still finishes because it runs from clk.
      half_a = 2500;
      alive_b = 1'b0;
      window = 32'd1000;
      pulse_start;
      wait_done;
      check("dead RO count_b", count_b, 0, 0);
      check("live RO count_a", count_a, expected(1000, half_a), 1);
      check("FSM finished with dead RO", done, 1, 0);

      if (errors == 0) $display("TB PASS");
      else             $display("TB FAIL (%0d errors)", errors);
      $finish;
   end

endmodule

`default_nettype wire
