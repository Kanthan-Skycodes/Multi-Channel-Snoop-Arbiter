module tb_axis_snoop_arb;

  //-- Testbench Parameters
  localparam CLK_PERIOD           = 10; // 10ns = 100MHz
  localparam NUM_SNOOP_INTERFACES = 2;  // Test with 2 active interfaces
  localparam DATA_WIDTH           = 8;

  //-- Signals
  logic axis_aclk;
  logic axis_aresetn;

  //-- Snoop Slave Interfaces (driven by testbench)
  logic [3:0] s_axis_tready;
  logic [3:0][DATA_WIDTH-1:0] s_axis_tdata;
  logic [3:0] s_axis_tlast;
  logic [3:0] s_axis_tvalid;
  
  //-- Master Interface (monitor this, drive m_axis_tready)
  logic                         m_axis_tready;
  wire [DATA_WIDTH-1 : 0]       m_axis_tdata;
  wire                          m_axis_tlast;
  wire                          m_axis_tvalid;

  //-- DUT Instantiation
  axis_snoop_arb #(
    .NUM_INTERFACES(NUM_SNOOP_INTERFACES),
    .PORT_WIDTH(DATA_WIDTH)
  ) dut (
    .axis_aclk(axis_aclk),
    .axis_aresetn(axis_aresetn),

    // Connect slave interfaces
    .s00_axis_tready(s_axis_tready[0]),
    .s00_axis_tdata(s_axis_tdata[0]),
    .s00_axis_tlast(s_axis_tlast[0]),
    .s00_axis_tvalid(s_axis_tvalid[0]),

    .s01_axis_tready(s_axis_tready[1]),
    .s01_axis_tdata(s_axis_tdata[1]),
    .s01_axis_tlast(s_axis_tlast[1]),
    .s01_axis_tvalid(s_axis_tvalid[1]),

    // Tie off unused interfaces
    .s02_axis_tready(s_axis_tready[2]),
    .s02_axis_tdata(s_axis_tdata[2]),
    .s02_axis_tlast(s_axis_tlast[2]),
    .s02_axis_tvalid(s_axis_tvalid[2]),

    .s03_axis_tready(s_axis_tready[3]),
    .s03_axis_tdata(s_axis_tdata[3]),
    .s03_axis_tlast(s_axis_tlast[3]),
    .s03_axis_tvalid(s_axis_tvalid[3]),

    // Connect master interface
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid)
  );

  //-- Clock Generator
  always #((CLK_PERIOD) / 2) axis_aclk = ~axis_aclk;

  //-- Helper Task to send an AXI-Stream packet
  // This is a "blocking" task that completes before returning.
  task send_packet(input int channel, input logic [DATA_WIDTH-1:0] data[], input int delay_cycles);
    int size = data.size();
    
    // Optional delay before starting the packet
    repeat(delay_cycles) @(posedge axis_aclk);

    $display("T=%0t: Starting to send packet on channel %0d", $time, channel);
    for (int i = 0; i < size; i++) begin
      s_axis_tvalid[channel] <= 1;
      s_axis_tdata[channel]  <= data[i];
      s_axis_tlast[channel]  <= (i == size - 1);
      @(posedge axis_aclk);
    end
    s_axis_tvalid[channel] <= 0;
    s_axis_tlast[channel]  <= 0;
    $display("T=%0t: Finished sending packet into DUT on channel %0d", $time, channel);
  endtask

  //-- Main Test Sequence
  initial begin
    // 1. Initialize and Reset
    $display("T=%0t: Starting testbench...", $time);
    axis_aclk = 0;
    axis_aresetn = 0;
    s_axis_tvalid = '0;
    s_axis_tdata = '0;
    s_axis_tlast = '0;
    m_axis_tready = 1; // Initially, consumer is always ready

    // The snoop interface doesn't exert backpressure, so TREADY is an input
    // reflecting the downstream component's readiness. We tie it high.
    s_axis_tready = 4'b1111; 
                                  
    repeat (5) @(posedge axis_aclk);
    axis_aresetn <= 1;
    $display("T=%0t: Reset released.", $time);
    
    // 2. Test Case 1: Send a single packet on channel 0
    begin
      logic [DATA_WIDTH-1:0] pkt1[] = {8'hA0, 8'hA1, 8'hA2};
      $display("\n--- Test Case 1: Single packet on S00 ---");
      send_packet(0, pkt1, 2);
    end
    
    wait (m_axis_tlast && m_axis_tvalid && m_axis_tready);
    @(posedge axis_aclk);

    // 3. Test Case 2: Send two packets sequentially to test arbitration
    $display("\n--- Test Case 2: Sequential packets on S00 and S01 ---");
    // Send the first packet completely into its FIFO
    begin
        logic [DATA_WIDTH-1:0] pkt2[] = {8'hB0, 8'hB1, 8'hB2, 8'hB3};
        send_packet(0, pkt2, 2);
    end
    // Immediately send the second packet into its FIFO
    begin
        logic [DATA_WIDTH-1:0] pkt3[] = {8'hC0, 8'hC1};
        send_packet(1, pkt3, 0);
    end
    // Now both FIFOs have data. The arbiter will process S00's packet first, then S01's.
    // Wait for both packets to be transmitted by the arbiter.
    repeat(15) @(posedge axis_aclk);

    // 4. Test Case 3: Demonstrate backpressure
    $display("\n--- Test Case 3: Testing M_AXIS_TREADY backpressure ---");
    // First, send a full packet into the DUT's internal FIFO
    begin
        logic [DATA_WIDTH-1:0] pkt4[] = {8'hD0, 8'hD1, 8'hD2};
        send_packet(0, pkt4, 1);
    end

    // Now, orchestrate the readout with a stall.
    // Wait for the first byte to be transferred out of the DUT.
    wait (m_axis_tvalid && m_axis_tready);
    @(posedge axis_aclk);

    // Apply backpressure by de-asserting M_AXIS_TREADY
    $display("T=%0t: Applying backpressure with m_axis_tready=0", $time);
    m_axis_tready <= 0;
    repeat (5) @(posedge axis_aclk);

    // Release backpressure
    $display("T=%0t: Re-enabling output with m_axis_tready=1", $time);
    m_axis_tready <= 1;
    
    // 5. End Simulation
    repeat (20) @(posedge axis_aclk);
    $display("\n--- Test Finished ---");
    $finish;
  end
  
  //-- Output Monitor
  always @(posedge axis_aclk) begin
    if (m_axis_tvalid && m_axis_tready) begin
      $display("T=%0t: DUT Output -> TDATA=0x%h, TLAST=%b", $time, m_axis_tdata, m_axis_tlast);
    end
  end

endmodule
