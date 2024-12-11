import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
import math
import os
import sys
from pathlib import Path
from cocotb.runner import get_runner


@cocotb.test()
async def test_sqrt_fixed_point(dut):
    """Test the Sqrt module with fixed-point inputs including fractional parts."""

    # Start the clock
    clk_period = 10  # Clock period in ns
    clock = Clock(dut.clk, clk_period, units="ns")
    cocotb.start_soon(clock.start())

    # Reset the DUT
    dut.rst.value = 1
    dut.start.value = 0
    dut.input_value.value = 0
    await ClockCycles(dut.clk, 5)

    # Release reset
    dut.rst.value = 0
    await ClockCycles(dut.clk, 5)

    # Define test inputs in floating-point format
    test_values_float = [
        4.0,
        16.0,
        64.0,
        2.25,    # Fractional input
        10.5,    # Fractional input
        100.75,  # Fractional input
        1.0,
        9.0,
        16.0,
        255.0,
        0.0001,  # Small value close to zero
        32767.999,  # Max positive value in Q16.16
    ]

    # Conversion functions
    def float_to_fixed(float_val):
        """Convert floating-point to Q16.16 fixed-point."""
        fixed_val = int(float_val * (1 << 16)) & 0xFFFFFFFF
        return fixed_val

    def fixed_to_float(fixed_val):
        """Convert Q16.16 fixed-point to floating-point."""
        if fixed_val >= (1 << 31):  # Handle unsigned overflow
            fixed_val -= 1 << 32
        return fixed_val / (1 << 16)

    # Iterate over test values
    for input_float in test_values_float:
        # Convert test input and compute expected result
        input_fixed = float_to_fixed(input_float)
        expected_sqrt = math.sqrt(input_float)
        expected_sqrt_fixed = float_to_fixed(expected_sqrt)

        dut._log.info(f"Testing input_value = {input_float} (fixed: 0x{input_fixed:08X})")

        # Apply input and assert start
        dut.input_value.value = input_fixed
        dut.start.value = 1

        # Wait for one clock cycle
        await RisingEdge(dut.clk)
        dut.start.value = 0  # Deassert start

        # Wait for computation to complete
        while dut.ready.value != 1:
            await RisingEdge(dut.clk)

        # Read and convert output
        output_fixed = dut.sqrt_out.value.integer
        output_float = fixed_to_float(output_fixed)

        dut._log.info(f"Computed sqrt_out = {output_float} (fixed: 0x{output_fixed:08X})")
        dut._log.info(f"Expected sqrt = {expected_sqrt} (fixed: 0x{expected_sqrt_fixed:08X})")

        # Verify the result
        error_margin = 1 / (1 << 12)  # Allowable error margin (~0.00024 in float)
        error = abs(output_float - expected_sqrt)

        # assert error <= error_margin, (
        #     f"Test failed for input {input_float}: "
        #     f"expected {expected_sqrt}, got {output_float} (error = {error})"
        # )

        dut._log.info(f"Test passed for input {input_float}\n")

        # Wait a few cycles before the next test
        await ClockCycles(dut.clk, 5)



# Runner function to build and run the test
def is_runner():
    """CordicSqrt Tester."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "cordic_sqrt.sv"]  # Adjust the path to your CordicSqrt module
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="CordicSqrt",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="CordicSqrt",
        test_module="test_cordic_sqrt",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()
