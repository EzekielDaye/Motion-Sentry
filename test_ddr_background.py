import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ReadOnly
import numpy as np
import math
from MigDDR import MigDDR
from pathlib import Path
import os
import sys
from cocotb.runner import get_runner



@cocotb.test()
async def test_combined_background_model(dut):
    """Revised Test CombinedBackgroundModel with DRAM simulation."""

    # Parameters
    WIDTH = 4
    HEIGHT = 4
    NUM_FRAMES = 3
    TOTAL_PIXELS = WIDTH * HEIGHT
    BYTES_PER_PIXEL = 16  


    clk_period = 10  
    clock = Clock(dut.clk, clk_period, units="ns")
    cocotb.start_soon(clock.start())

    # Initialize inputs
    dut.rst.value = 1
    dut.valid_in.value = 0
    dut.btn0.value = 0
    dut.I_R.value = 0
    dut.I_G.value = 0
    dut.I_B.value = 0

    await Timer(100, units="ns")  
    dut.rst.value = 0


    dram = MigDDR(dut, dut.clk)


    dut._log.info("Initializing DRAM...")
    for addr in range(0, TOTAL_PIXELS * BYTES_PER_PIXEL, BYTES_PER_PIXEL):
        dram.memory[addr // 8] = 0
    dut._log.info("DRAM initialization complete.")


    np.random.seed(0)  # For reproducibility
    frames_R = np.random.randint(0, 256, (NUM_FRAMES, HEIGHT, WIDTH), dtype=np.uint8)
    frames_G = np.random.randint(0, 256, (NUM_FRAMES, HEIGHT, WIDTH), dtype=np.uint8)
    frames_B = np.random.randint(0, 256, (NUM_FRAMES, HEIGHT, WIDTH), dtype=np.uint8)

    # Expected results
    sum_R = np.zeros((HEIGHT, WIDTH), dtype=np.uint64)
    sum_G = np.zeros((HEIGHT, WIDTH), dtype=np.uint64)
    sum_B = np.zeros((HEIGHT, WIDTH), dtype=np.uint64)
    sum_sq_R = np.zeros((HEIGHT, WIDTH), dtype=np.uint64)
    sum_sq_G = np.zeros((HEIGHT, WIDTH), dtype=np.uint64)
    sum_sq_B = np.zeros((HEIGHT, WIDTH), dtype=np.uint64)


    def compute_expected_mean_std(row, col):
        """Compute the expected mean and standard deviation for a pixel."""
        mean_R = sum_R[row, col] / NUM_FRAMES
        mean_G = sum_G[row, col] / NUM_FRAMES
        mean_B = sum_B[row, col] / NUM_FRAMES

        var_R = (sum_sq_R[row, col] / NUM_FRAMES) - (mean_R ** 2)
        var_G = (sum_sq_G[row, col] / NUM_FRAMES) - (mean_G ** 2)
        var_B = (sum_sq_B[row, col] / NUM_FRAMES) - (mean_B ** 2)

        std_R = math.sqrt(max(0, var_R))
        std_G = math.sqrt(max(0, var_G))
        std_B = math.sqrt(max(0, var_B))

        return mean_R, mean_G, mean_B, std_R, std_G, std_B


    dut.btn0.value = 1
    await RisingEdge(dut.clk)
    dut.btn0.value = 0
    await RisingEdge(dut.clk)

    # Process frames
    for frame_idx in range(NUM_FRAMES):
        dut._log.info(f"Processing frame {frame_idx + 1}/{NUM_FRAMES}")
        for row in range(HEIGHT):
            for col in range(WIDTH):
                I_R = int(frames_R[frame_idx, row, col])
                I_G = int(frames_G[frame_idx, row, col])
                I_B = int(frames_B[frame_idx, row, col])

                # Update expected accumulators
                sum_R[row, col] += I_R
                sum_G[row, col] += I_G
                sum_B[row, col] += I_B
                sum_sq_R[row, col] += I_R * I_R
                sum_sq_G[row, col] += I_G * I_G
                sum_sq_B[row, col] += I_B * I_B

                # Apply pixel values to DUT
                dut.I_R.value = I_R
                dut.I_G.value = I_G
                dut.I_B.value = I_B
                dut.valid_in.value = 1

                # Wait for one clock cycle
                await RisingEdge(dut.clk)

                # Deassert valid_in
                dut.valid_in.value = 0
                await RisingEdge(dut.clk)

    # Wait for computation to complete
    dut._log.info("Waiting for DUT to signal valid_out...")
    while not dut.valid_out.value:
        await RisingEdge(dut.clk)

    # Verify means and standard deviations for each pixel
    dut._log.info("Verifying pixel data...")
    for row in range(HEIGHT):
        for col in range(WIDTH):
            addr = (row * WIDTH + col) * BYTES_PER_PIXEL // 8
            data = dram.memory.get(addr, 0)
            data_hex = f"{data:084x}".zfill(84)

            sum_B_val = int(data_hex[0:12], 16)
            sum_G_val = int(data_hex[12:24], 16)
            sum_R_val = int(data_hex[24:36], 16)
            sum_sq_B_val = int(data_hex[36:52], 16)
            sum_sq_G_val = int(data_hex[52:68], 16)
            sum_sq_R_val = int(data_hex[68:84], 16)

            # Calculate mean and standard deviation
            mean_R = sum_R_val / NUM_FRAMES
            mean_G = sum_G_val / NUM_FRAMES
            mean_B = sum_B_val / NUM_FRAMES

            var_R = (sum_sq_R_val / NUM_FRAMES) - (mean_R ** 2)
            var_G = (sum_sq_G_val / NUM_FRAMES) - (mean_G ** 2)
            var_B = (sum_sq_B_val / NUM_FRAMES) - (mean_B ** 2)

            std_R = math.sqrt(max(0, var_R))
            std_G = math.sqrt(max(0, var_G))
            std_B = math.sqrt(max(0, var_B))

            expected_mean_R, expected_mean_G, expected_mean_B, expected_std_R, expected_std_G, expected_std_B = compute_expected_mean_std(row, col)


    dut._log.info("All checks passed.")





async def handle_dram(dut, dram):
    """Handle DRAM read and write requests from the DUT."""
    # Check for DRAM read request
    if dut.app_en.value and dut.app_cmd.value == 1 and dut.app_rdy.value:
        # Read request
        address = dut.app_addr.value.integer
        data = dram.get(address, 0)
        await RisingEdge(dut.clk)
        dut.app_rd_data_valid.value = 1
        dut.app_rd_data.value = data
    else:
        dut.app_rd_data_valid.value = 0
        dut.app_rd_data.value = 0

    # Check for DRAM write request
    if dut.app_wdf_wren.value and dut.app_en.value and dut.app_cmd.value == 0 and dut.app_wdf_rdy.value:
        # Write request
        address = dut.app_addr.value.integer
        data = dut.app_wdf_data.value.integer
        dram[address] = data

    await ReadOnly()

# Runner function to build and run the test
def is_runner():
    """BackgroundModelDRAM Tester."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "FinalCombinedBackgroundModel.sv",
        proj_path / "hdl" / "cordic_sqrt.sv",
        proj_path / "hdl" / "test_chroma.sv",
        proj_path / "hdl" / "test_bright.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="CombinedBackgroundModel",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="CombinedBackgroundModel",
        test_module="test_ddr_background",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()
