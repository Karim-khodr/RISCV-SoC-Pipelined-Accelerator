`timescale 1ns/1ps

module dot_product_seq_tb;

  localparam int ELEM_WIDTH       = 8;
  localparam int NUM_ELEMS        = 4;
  localparam int RESULT_WIDTH     = 32;
  localparam int CLK_PERIOD_NS    = 10;
  localparam int MAX_WAIT_CYCLES  = 20;
  localparam int NUM_RANDOM_TESTS = 100;

  logic clk;
  logic rst_n;
  logic start;
  logic [ELEM_WIDTH*NUM_ELEMS-1:0] vec_a;
  logic [ELEM_WIDTH*NUM_ELEMS-1:0] vec_b;
  logic [RESULT_WIDTH-1:0] result;
  logic busy;
  logic done;

  int unsigned tests_run;
  int unsigned failures;
  int unsigned random_seed;

  dot_product_seq #(
    .ELEM_WIDTH   (ELEM_WIDTH),
    .NUM_ELEMS    (NUM_ELEMS),
    .RESULT_WIDTH (RESULT_WIDTH)
  ) dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (start),
    .vec_a  (vec_a),
    .vec_b  (vec_b),
    .result (result),
    .busy   (busy),
    .done   (done)
  );

  initial begin
    clk = 1'b0;
  end

  always #(CLK_PERIOD_NS/2) clk <= ~clk;

  function automatic logic [RESULT_WIDTH-1:0] golden_dot(
    input logic [ELEM_WIDTH*NUM_ELEMS-1:0] a,
    input logic [ELEM_WIDTH*NUM_ELEMS-1:0] b
  );
    int i;
    logic [RESULT_WIDTH-1:0] acc;
    logic [ELEM_WIDTH-1:0] a_elem;
    logic [ELEM_WIDTH-1:0] b_elem;

    begin
      acc = '0;

      for (i = 0; i < NUM_ELEMS; i = i + 1) begin
        a_elem = a[i*ELEM_WIDTH +: ELEM_WIDTH];
        b_elem = b[i*ELEM_WIDTH +: ELEM_WIDTH];
        acc = acc + (a_elem * b_elem);
      end

      golden_dot = acc;
    end
  endfunction

  task automatic reset_dut;
    begin
      start = 1'b0;
      vec_a = '0;
      vec_b = '0;
      rst_n = 1'b0;

      repeat (3) @(posedge clk);

      rst_n = 1'b1;

      repeat (2) @(posedge clk);
    end
  endtask

  task automatic wait_for_done(output bit done_seen);
    int wait_cycles;

    begin
      done_seen   = 1'b0;
      wait_cycles = 0;

      while ((done !== 1'b1) && (wait_cycles < MAX_WAIT_CYCLES)) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
      end

      if (done === 1'b1) begin
        done_seen = 1'b1;
      end
    end
  endtask

  task automatic report_protocol(
    input string test_name,
    input bit test_failed
  );
    begin
      tests_run = tests_run + 1;

      if (test_failed) begin
        failures = failures + 1;
        $display("[FAIL] %-32s", test_name);
      end else begin
        $display("[PASS] %-32s", test_name);
      end
    end
  endtask

  task automatic report_result(
    input string test_name,
    input bit test_failed,
    input logic [ELEM_WIDTH*NUM_ELEMS-1:0] a,
    input logic [ELEM_WIDTH*NUM_ELEMS-1:0] b,
    input logic [RESULT_WIDTH-1:0] expected,
    input logic [RESULT_WIDTH-1:0] got
  );
    begin
      tests_run = tests_run + 1;

      if (test_failed) begin
        failures = failures + 1;
        $display("[FAIL] %-32s A=0x%08h B=0x%08h Expected=%0d Got=%0d",
                 test_name, a, b, expected, got);
      end else begin
        $display("[PASS] %-32s A=0x%08h B=0x%08h Result=%0d",
                 test_name, a, b, got);
      end
    end
  endtask

  task automatic check_reset_state;
    bit test_failed;

    begin
      test_failed = 1'b0;

      if (busy !== 1'b0) begin
        test_failed = 1'b1;
        $display("       Reset check failed: busy should be 0 after reset.");
      end

      if (done !== 1'b0) begin
        test_failed = 1'b1;
        $display("       Reset check failed: done should be 0 after reset.");
      end

      if (result !== '0) begin
        test_failed = 1'b1;
        $display("       Reset check failed: result should be 0 after reset.");
      end

      tests_run = tests_run + 1;

      if (test_failed) begin
        failures = failures + 1;
        $display("[FAIL] %-32s busy=%b done=%b", "reset state", busy, done);
      end else begin
        $display("[PASS] %-32s busy=%b done=%b", "reset state", busy, done);
      end
    end
  endtask

  task automatic run_dot_test(
    input string test_name,
    input logic [ELEM_WIDTH*NUM_ELEMS-1:0] a,
    input logic [ELEM_WIDTH*NUM_ELEMS-1:0] b
  );
    bit done_seen;
    bit test_failed;
    logic [RESULT_WIDTH-1:0] expected;
    logic [RESULT_WIDTH-1:0] result_at_done;

    begin
      done_seen     = 1'b0;
      test_failed   = 1'b0;
      expected      = golden_dot(a, b);
      result_at_done = '0;

      @(negedge clk);
      vec_a = a;
      vec_b = b;
      start = 1'b1;

      @(negedge clk);
      start = 1'b0;

      wait_for_done(done_seen);

      if (!done_seen) begin
        test_failed = 1'b1;
        $display("       Timeout waiting for done.");
      end else begin
        result_at_done = result;

        if (result !== expected) begin
          test_failed = 1'b1;
          $display("       Result mismatch.");
        end

        if (busy !== 1'b0) begin
          test_failed = 1'b1;
          $display("       busy should be low when done is observed.");
        end

        @(posedge clk);
        #1;

        if (done !== 1'b0) begin
          test_failed = 1'b1;
          $display("       done should be a one-cycle pulse.");
        end

        repeat (2) begin
          @(posedge clk);
          #1;

          if (result !== result_at_done) begin
            test_failed = 1'b1;
            $display("       result changed after operation completed.");
          end
        end
      end

      report_result(test_name, test_failed, a, b, expected, result);
    end
  endtask

  task automatic test_exact_latency;
    bit test_failed;
    int unsigned latency_cycles;
    logic [RESULT_WIDTH-1:0] expected;

    begin
      test_failed  = 1'b0;
      latency_cycles = 0;
      expected = golden_dot(32'h0403_0201, 32'h0807_0605);

      @(negedge clk);
      vec_a = 32'h0403_0201;
      vec_b = 32'h0807_0605;
      start = 1'b1;

      @(posedge clk);
      #1;
      if ((busy !== 1'b1) || (done !== 1'b0)) begin
        test_failed = 1'b1;
        $display("       Request was not accepted in IDLE.");
      end

      @(negedge clk);
      start = 1'b0;

      while ((done !== 1'b1) && (latency_cycles < MAX_WAIT_CYCLES)) begin
        @(posedge clk);
        #1;
        latency_cycles = latency_cycles + 1;
      end

      if (latency_cycles != NUM_ELEMS) begin
        test_failed = 1'b1;
        $display("       Expected latency=%0d cycles, observed=%0d cycles.",
                 NUM_ELEMS, latency_cycles);
      end

      if ((done !== 1'b1) || (busy !== 1'b0) || (result !== expected)) begin
        test_failed = 1'b1;
        $display("       Completion signals or result were incorrect.");
      end

      report_protocol("exact 4-cycle result latency", test_failed);
    end
  endtask

  task automatic test_earliest_restart;
    bit done_seen;
    bit test_failed;
    logic [RESULT_WIDTH-1:0] expected_second;

    begin
      done_seen = 1'b0;
      test_failed = 1'b0;
      expected_second = golden_dot(32'h0101_0101, 32'h0202_0202);

      @(negedge clk);
      vec_a = 32'h0403_0201;
      vec_b = 32'h0807_0605;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;

      wait_for_done(done_seen);
      if (!done_seen) begin
        test_failed = 1'b1;
        $display("       First operation did not complete.");
      end

      // The first edge after done is the earliest legal acceptance edge.
      @(negedge clk);
      vec_a = 32'h0101_0101;
      vec_b = 32'h0202_0202;
      start = 1'b1;
      @(posedge clk);
      #1;

      if ((busy !== 1'b1) || (done !== 1'b0)) begin
        test_failed = 1'b1;
        $display("       Earliest restart was not accepted.");
      end

      @(negedge clk);
      start = 1'b0;

      wait_for_done(done_seen);
      if (!done_seen || (result !== expected_second)) begin
        test_failed = 1'b1;
        $display("       Back-to-back second result was incorrect.");
      end

      report_protocol("earliest restart/back-to-back", test_failed);
    end
  endtask

  task automatic test_held_high_start;
    bit done_seen;
    bit test_failed;
    logic [RESULT_WIDTH-1:0] expected;

    begin
      done_seen = 1'b0;
      test_failed = 1'b0;
      expected = golden_dot(32'h0403_0201, 32'h0807_0605);

      while (done === 1'b1) begin
        @(posedge clk);
        #1;
      end

      @(negedge clk);
      vec_a = 32'h0403_0201;
      vec_b = 32'h0807_0605;
      start = 1'b1;

      wait_for_done(done_seen);
      if (!done_seen || (result !== expected)) begin
        test_failed = 1'b1;
        $display("       Held-high start first operation failed.");
      end

      // The level-sensitive command is accepted again on the next IDLE edge.
      @(posedge clk);
      #1;
      if ((busy !== 1'b1) || (done !== 1'b0)) begin
        test_failed = 1'b1;
        $display("       Held-high start did not retrigger in IDLE.");
      end

      @(negedge clk);
      start = 1'b0;

      wait_for_done(done_seen);
      if (!done_seen || (result !== expected)) begin
        test_failed = 1'b1;
        $display("       Held-high start repeated operation failed.");
      end

      report_protocol("held-high start retriggers", test_failed);
    end
  endtask

  task automatic test_reset_while_active;
    bit done_seen;
    bit test_failed;
    logic [RESULT_WIDTH-1:0] expected;

    begin
      done_seen = 1'b0;
      test_failed = 1'b0;
      expected = golden_dot(32'h0400_0201, 32'h0305_0007);

      @(negedge clk);
      vec_a = 32'hFFFF_FFFF;
      vec_b = 32'hFFFF_FFFF;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;

      @(posedge clk);
      #1;
      if (busy !== 1'b1) begin
        test_failed = 1'b1;
        $display("       Accelerator was not active before reset.");
      end

      @(negedge clk);
      rst_n = 1'b0;
      #1;
      if ((busy !== 1'b0) || (done !== 1'b0) || (result !== '0)) begin
        test_failed = 1'b1;
        $display("       Asynchronous reset did not clear active state.");
      end

      repeat (2) @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      #1;

      if ((busy !== 1'b0) || (done !== 1'b0)) begin
        test_failed = 1'b1;
        $display("       Accelerator was not idle after reset release.");
      end

      @(negedge clk);
      vec_a = 32'h0400_0201;
      vec_b = 32'h0305_0007;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;

      wait_for_done(done_seen);
      if (!done_seen || (result !== expected)) begin
        test_failed = 1'b1;
        $display("       Accelerator did not recover after active reset.");
      end

      report_protocol("reset while active and recovery", test_failed);
    end
  endtask

  task automatic test_start_while_busy_ignored;
    bit done_seen;
    bit test_failed;

    logic [ELEM_WIDTH*NUM_ELEMS-1:0] first_a;
    logic [ELEM_WIDTH*NUM_ELEMS-1:0] first_b;
    logic [ELEM_WIDTH*NUM_ELEMS-1:0] second_a;
    logic [ELEM_WIDTH*NUM_ELEMS-1:0] second_b;

    logic [RESULT_WIDTH-1:0] expected_first;

    begin
      done_seen   = 1'b0;
      test_failed = 1'b0;

      first_a  = 32'h0403_0201;
      first_b  = 32'h0807_0605;

      second_a = 32'hFFFF_FFFF;
      second_b = 32'hFFFF_FFFF;

      expected_first = golden_dot(first_a, first_b);

      @(negedge clk);
      vec_a = first_a;
      vec_b = first_b;
      start = 1'b1;

      @(negedge clk);
      start = 1'b0;

      @(negedge clk);

      if (busy !== 1'b1) begin
        test_failed = 1'b1;
        $display("       busy should be high during an active operation.");
      end

      vec_a = second_a;
      vec_b = second_b;
      start = 1'b1;

      @(negedge clk);
      start = 1'b0;

      wait_for_done(done_seen);

      if (!done_seen) begin
        test_failed = 1'b1;
        $display("       Timeout waiting for done.");
      end else begin
        if (result !== expected_first) begin
          test_failed = 1'b1;
          $display("       start while busy was not ignored.");
        end
      end

      report_result("start while busy ignored",
                    test_failed,
                    first_a,
                    first_b,
                    expected_first,
                    result);
    end
  endtask

  int i;
  logic [ELEM_WIDTH*NUM_ELEMS-1:0] rand_a;
  logic [ELEM_WIDTH*NUM_ELEMS-1:0] rand_b;

  initial begin
    $dumpfile("sim/waveforms/dot_product_seq_tb.vcd");
    $dumpvars(0, dot_product_seq_tb);

    tests_run = 0;
    failures  = 0;
    random_seed = 32'hACC0_0001;
    if ($value$plusargs("SEED=%d", random_seed)) begin
      $display("ACCEL_SEQ random seed: %0d (0x%08h)",
               random_seed, random_seed);
    end else begin
      $display("ACCEL_SEQ random seed: %0d (0x%08h)",
               random_seed, random_seed);
    end
    void'($urandom(random_seed));

    reset_dut();

    check_reset_state();

    run_dot_test("single element",     32'h0000_000C, 32'h0000_0007);
    run_dot_test("basic dot product",  32'h0403_0201, 32'h0807_0605);
    run_dot_test("all zero A",         32'h0000_0000, 32'h0607_0809);
    run_dot_test("all zero B",         32'h0102_0304, 32'h0000_0000);
    run_dot_test("all ones",           32'h0101_0101, 32'h0101_0101);
    run_dot_test("mixed small values", 32'h0400_0201, 32'h0305_0007);
    run_dot_test("max values",         32'hFFFF_FFFF, 32'hFFFF_FFFF);

    test_start_while_busy_ignored();
    test_exact_latency();
    test_earliest_restart();
    test_held_high_start();
    test_reset_while_active();

    for (i = 0; i < NUM_RANDOM_TESTS; i = i + 1) begin
      rand_a = $urandom();
      rand_b = $urandom();
      run_dot_test($sformatf("random test %0d", i), rand_a, rand_b);
    end

    $display("");
    $display("========================================");
    $display("Dot Product Accelerator Test Summary");
    $display("========================================");
    $display("Tests run : %0d", tests_run);
    $display("Failures  : %0d", failures);
    $display("========================================");

    if (failures == 0) begin
      $display("ALL TESTS PASSED");
      $finish;
    end else begin
      $display("TESTS FAILED");
      $fatal(1);
    end
  end

endmodule
