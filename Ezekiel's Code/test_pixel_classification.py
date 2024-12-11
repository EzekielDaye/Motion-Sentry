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
import random



@cocotb.test()
async def test_pixel_classification(dut):
    """Test the PixelClassification module with enhanced logging."""

    # Constants
    clk_period = 10  # Clock period in ns
    num_test_cases = 4
    pipeline_delay = 2  # Adjust to match the pipeline depth

    # Start the clock
    clock = Clock(dut.clk, clk_period, units="ns")
    cocotb.start_soon(clock.start())

    # Reset the DUT
    dut.rst.value = 1
    dut.valid_in.value = 0
    dut.I_R.value = 0
    dut.I_G.value = 0
    dut.I_B.value = 0
    dut.E_R.value = 0
    dut.E_G.value = 0
    dut.E_B.value = 0
    dut.SD_alpha.value = 0
    dut.SD_CD.value = 0
    dut.alpha.value = 0
    dut.CD.value = 0

    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0

    # Test cases
    test_cases = [
        {"I_R": 120, "I_G": 100, "I_B": 80, "E_R": 7864320, "E_G": 6553600, "E_B": 5242880,
         "SD_alpha": 6554, "SD_CD": 6554, "alpha": 65536, "CD": 5000, "expected_classification": 0},  # Background
        {"I_R": 180, "I_G": 160, "I_B": 140, "E_R": 7864320, "E_G": 6553600, "E_B": 5242880,
         "SD_alpha": 6554, "SD_CD": 6554, "alpha": 70000, "CD": 20000, "expected_classification": 1},  # Foreground
        {"I_R": 50, "I_G": 40, "I_B": 30, "E_R": 7864320, "E_G": 6553600, "E_B": 5242880,
         "SD_alpha": 6554, "SD_CD": 6554, "alpha": 50000, "CD": 1000, "expected_classification": 2},  # Shadow
        {"I_R": 60, "I_G": 70, "I_B": 90, "E_R": 7864320, "E_G": 6553600, "E_B": 5242880,
         "SD_alpha": 6554, "SD_CD": 6554, "alpha": 80000, "CD": 3000, "expected_classification": 3},  # Highlight
    ]

    # Run the test cases
    for idx, case in enumerate(test_cases):
        dut._log.info(f"Applying test case {idx + 1}/{num_test_cases}")

        # Apply inputs
        dut.I_R.value = case["I_R"]
        dut.I_G.value = case["I_G"]
        dut.I_B.value = case["I_B"]
        dut.E_R.value = case["E_R"]
        dut.E_G.value = case["E_G"]
        dut.E_B.value = case["E_B"]
        dut.SD_alpha.value = case["SD_alpha"]
        dut.SD_CD.value = case["SD_CD"]
        dut.alpha.value = case["alpha"]
        dut.CD.value = case["CD"]
        dut.valid_in.value = 1

        # Wait for one clock cycle to register the inputs
        await RisingEdge(dut.clk)
        dut.valid_in.value = 0

        # Wait for the pipeline to process
        await ClockCycles(dut.clk, pipeline_delay)

        # Check valid_out signal
        assert dut.valid_out.value == 1, f"Test case {idx + 1} failed: valid_out not asserted"

        # Log all internal signals
        dut._log.info(f"Test case {idx + 1} inputs:")
        dut._log.info(f"  I_R: {case['I_R']}, I_G: {case['I_G']}, I_B: {case['I_B']}")
        dut._log.info(f"  E_R: {case['E_R']}, E_G: {case['E_G']}, E_B: {case['E_B']}")
        dut._log.info(f"  SD_alpha: {case['SD_alpha']}, SD_CD: {case['SD_CD']}")
        dut._log.info(f"  alpha: {case['alpha']}, CD: {case['CD']}")

        # Log threshold calculations
        expected_a_lo = 65536 - (2 * case["SD_alpha"])
        expected_a_hi = 65536 + (2 * case["SD_alpha"])
        expected_b = 0 + (2 * case["SD_CD"])  # E_CD + K3 * SD_CD
        observed_a_lo = dut.a_lo.value.signed_integer
        observed_a_hi = dut.a_hi.value.signed_integer
        observed_b = dut.b.value.signed_integer

        dut._log.info(f"Thresholds:")
        dut._log.info(f"  Observed a_lo: {observed_a_lo}, Expected a_lo: {expected_a_lo}")
        dut._log.info(f"  Observed a_hi: {observed_a_hi}, Expected a_hi: {expected_a_hi}")
        dut._log.info(f"  Observed b:    {observed_b}, Expected b:    {expected_b}")

        # Log classification
        observed_classification = int(dut.classification.value)
        expected_classification = case["expected_classification"]
        dut._log.info(f"Classification:")
        dut._log.info(f"  Observed: {observed_classification}, Expected: {expected_classification}")

        # Assert correctness
        assert observed_classification == expected_classification, (
            f"Test case {idx + 1} failed: expected {expected_classification}, "
            f"got {observed_classification}"
        )

    dut._log.info("All test cases completed.")


# Runner function to build and run the test
def is_runner():
    """BackgroundModelDRAM Tester."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "pixel_classification.sv",
        proj_path / "hdl" / "cordic_sqrt.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="PixelClassification",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="PixelClassification",
        test_module="test_pixel_classification",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()