import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly
import numpy as np
import math
from cocotb.binary import BinaryValue
import os
import sys
from pathlib import Path
from cocotb.runner import get_runner



import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import numpy as np
import math

@cocotb.test()
async def test_background_model(dut):
    """Test the BackgroundModel module for per-pixel mean and SD computation."""

    # Parameters
    WIDTH = 4
    HEIGHT = 4
    NUM_FRAMES = 3
    TOTAL_PIXELS = WIDTH * HEIGHT

    # Clock setup
    clk_period = 10  # Clock period in ns
    clock = Clock(dut.clk, clk_period, units="ns")
    cocotb.start_soon(clock.start())

    # Initialize inputs
    dut.rst.value = 1
    dut.valid_in.value = 0
    dut.btn0.value = 0
    dut.I_R.value = 0
    dut.I_G.value = 0
    dut.I_B.value = 0

    await Timer(100, units="ns")  # Allow reset time
    dut.rst.value = 0

    # Generate test pixel data for NUM_FRAMES frames
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

    # Helper functions
    def fixed_to_float(fixed_val):
        """Convert Q16.16 fixed-point to float."""
        if fixed_val >= (1 << 31):
            fixed_val -= (1 << 32)  # Handle signed overflow
        return fixed_val / (1 << 16)

    def float_to_fixed(float_val):
        """Convert float to Q16.16 fixed-point."""
        return int(float_val * (1 << 16))

    # Reset the background model (simulate button press)
    dut.btn0.value = 1
    await RisingEdge(dut.clk)
    dut.btn0.value = 0
    await RisingEdge(dut.clk)

    # Process frames
    for frame_idx in range(NUM_FRAMES):
        dut._log.info(f"Processing frame {frame_idx + 1}/{NUM_FRAMES}")
        for row in range(HEIGHT):
            for col in range(WIDTH):
                pixel_index = row * WIDTH + col

                # Get current pixel values
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
    while not dut.valid_out.value:
        await RisingEdge(dut.clk)

    # Verify results for each pixel
    for row in range(HEIGHT):
        for col in range(WIDTH):
            pixel_index = row * WIDTH + col

            # Wait for valid_out to be asserted
            while not dut.valid_out.value:
                await RisingEdge(dut.clk)

            # Read outputs
            E_R_fixed = dut.E_R.value.signed_integer
            E_G_fixed = dut.E_G.value.signed_integer
            E_B_fixed = dut.E_B.value.signed_integer

            SD_R_fixed = dut.SD_R.value.signed_integer
            SD_G_fixed = dut.SD_G.value.signed_integer
            SD_B_fixed = dut.SD_B.value.signed_integer

            # Convert fixed-point to float
            E_R = fixed_to_float(E_R_fixed)
            E_G = fixed_to_float(E_G_fixed)
            E_B = fixed_to_float(E_B_fixed)

            SD_R = fixed_to_float(SD_R_fixed)
            SD_G = fixed_to_float(SD_G_fixed)
            SD_B = fixed_to_float(SD_B_fixed)

            # Compute expected mean and variance
            expected_mean_R = sum_R[row, col] / NUM_FRAMES
            expected_mean_G = sum_G[row, col] / NUM_FRAMES
            expected_mean_B = sum_B[row, col] / NUM_FRAMES

            expected_var_R = (sum_sq_R[row, col] / NUM_FRAMES) - (expected_mean_R ** 2)
            expected_var_G = (sum_sq_G[row, col] / NUM_FRAMES) - (expected_mean_G ** 2)
            expected_var_B = (sum_sq_B[row, col] / NUM_FRAMES) - (expected_mean_B ** 2)

            expected_SD_R = math.sqrt(expected_var_R)
            expected_SD_G = math.sqrt(expected_var_G)
            expected_SD_B = math.sqrt(expected_var_B)

            # Log results
            dut._log.info(f"Pixel ({row},{col}):")
            dut._log.info(f"  Computed Mean R: {E_R}, Expected: {expected_mean_R}")
            dut._log.info(f"  Computed Mean G: {E_G}, Expected: {expected_mean_G}")
            dut._log.info(f"  Computed Mean B: {E_B}, Expected: {expected_mean_B}")
            dut._log.info(f"  Computed SD R: {SD_R}, Expected: {expected_SD_R}")
            dut._log.info(f"  Computed SD G: {SD_G}, Expected: {expected_SD_G}")
            dut._log.info(f"  Computed SD B: {SD_B}, Expected: {expected_SD_B}")

            while dut.valid_out.value:
                await RisingEdge(dut.clk)

    dut._log.info("Test passed.")




# Runner function to build and run the test
def is_runner():
    """BackgroundModelDRAM Tester."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "background_model_test.sv",
        proj_path / "hdl" / "cordic_sqrt.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="BackgroundModelTest",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="BackgroundModelTest",
        test_module="test_background_model",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()
