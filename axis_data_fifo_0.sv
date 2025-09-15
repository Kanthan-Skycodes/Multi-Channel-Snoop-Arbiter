/**
 * @brief AXI-Stream Data FIFO
 * @details A simple, single-clock FIFO with standard AXI-Stream interfaces.
 * It uses a counter to track the number of elements, which simplifies the
 * full/empty logic and provides a direct data count output.
 */
module axis_data_fifo_0
  #(
    // The width of the TDATA bus
    parameter integer DATA_WIDTH = 8,
    // The total number of words the FIFO can store
    parameter integer DEPTH = 2048,
    // The threshold at which prog_full asserts.
    // In the snoop module, this is used to ensure there is enough space
    // for a max-sized Ethernet packet (1500 bytes) before starting a write.
    // The logic becomes: assert prog_full if (items_in_fifo > THRESHOLD)
    // or equivalently: assert prog_full if (free_space < DEPTH - THRESHOLD).
    // So, we set the threshold to DEPTH - 1500.
    parameter integer PROG_FULL_THRESH = DEPTH - 1500
  )
  (
    // Common clock and reset
    input wire                            s_axis_aclk,
    input wire                            s_axis_aresetn,

    // Slave (write) interface
    input wire                            s_axis_tvalid,
    output wire                           s_axis_tready,
    input wire [DATA_WIDTH-1 : 0]         s_axis_tdata,
    input wire                            s_axis_tlast,

    // Master (read) interface
    output wire                           m_axis_tvalid,
    input wire                            m_axis_tready,
    output wire [DATA_WIDTH-1 : 0]        m_axis_tdata,
    output wire                           m_axis_tlast,
    
    // Status signals
    output wire [31 : 0]                  axis_wr_data_count,
    output wire                           prog_full
  );

  // Calculate the width of the address pointers
  localparam ADDR_WIDTH = $clog2(DEPTH);

  // FIFO Memory: Store TDATA and TLAST together. The MSB is TLAST.
  logic [DATA_WIDTH:0] mem[0:DEPTH-1];

  // Pointers for writing and reading
  logic [ADDR_WIDTH-1:0] wr_ptr;
  logic [ADDR_WIDTH-1:0] rd_ptr;

  // Counter to track the number of elements in the FIFO.
  // It needs to be one bit wider than the address to represent the 'DEPTH' full state.
  logic [ADDR_WIDTH:0] data_count;

  // Internal full and empty signals
  logic full;
  logic empty;

  // Handshake signals
  wire wr_en = s_axis_tvalid && s_axis_tready;
  wire rd_en = m_axis_tvalid && m_axis_tready;

  // --- Combinational Logic for Status and Outputs ---

  // FIFO is full when the count reaches its maximum capacity
  assign full = (data_count == DEPTH);
  // FIFO is empty when the count is zero
  assign empty = (data_count == 0);

  // We are ready to accept data if the FIFO is not full
  assign s_axis_tready = !full;
  // We have valid data to send if the FIFO is not empty
  assign m_axis_tvalid = !empty;

  // Read data from the memory location pointed to by the read pointer
  assign m_axis_tdata = mem[rd_ptr][DATA_WIDTH-1:0];
  assign m_axis_tlast = mem[rd_ptr][DATA_WIDTH];

  // Assign status outputs
  assign axis_wr_data_count = data_count;
  assign prog_full = (data_count > PROG_FULL_THRESH);


  // --- Sequential Logic for Pointers and Counter ---

  always_ff @(posedge s_axis_aclk) begin
    if (~s_axis_aresetn) begin
      // Asynchronous reset condition
      wr_ptr     <= '0;
      rd_ptr     <= '0;
      data_count <= '0;
    end
    else begin
      // Write logic
      if (wr_en) begin
        mem[wr_ptr] <= {s_axis_tlast, s_axis_tdata};
        wr_ptr      <= wr_ptr + 1;
      end

      // Read logic
      if (rd_en) begin
        rd_ptr <= rd_ptr + 1;
      end

      // Data counter logic
      // Case 1: Write but no read
      if (wr_en && !rd_en) begin
        data_count <= data_count + 1;
      end
      // Case 2: Read but no write
      else if (!wr_en && rd_en) begin
        data_count <= data_count - 1;
      end
      // Case 3 (write and read simultaneously) and Case 4 (no activity)
      // result in no change to the data count.
    end
  end

endmodule
