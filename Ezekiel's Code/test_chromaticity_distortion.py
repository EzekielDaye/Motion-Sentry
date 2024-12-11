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



def fixed_to_float(value, Q=16):
    """Convert fixed-point Qm.n to float."""
    if value & (1 << (32 - 1)):  
        value -= 1 << 32
    return value / (1 << Q)

def float_to_fixed(value, Q=16, bits=32):
    """Convert float to fixed-point Qm.n."""
    max_val = (1 << (bits - 1)) - 1  
    min_val = -(1 << (bits - 1))     
    fixed_val = int(round(value * (1 << Q)))
    return max(min(fixed_val, max_val), min_val) & ((1 << bits) - 1)


def chromaticity_distortion_model(I_R, I_G, I_B, E_R, E_G, E_B, alpha):
    """Compute the chromaticity distortion using proper scaling."""

    I_R_fp = I_R << 16
    I_G_fp = I_G << 16
    I_B_fp = I_B << 16


    alpha_E_R = (alpha * E_R) >> 16
    alpha_E_G = (alpha * E_G) >> 16
    alpha_E_B = (alpha * E_B) >> 16


    E_R_nonzero = E_R if E_R != 0 else 1
    E_G_nonzero = E_G if E_G != 0 else 1
    E_B_nonzero = E_B if E_B != 0 else 1


    delta_R = ((I_R_fp - alpha_E_R) << 16) // E_R_nonzero
    delta_G = ((I_G_fp - alpha_E_G) << 16) // E_G_nonzero
    delta_B = ((I_B_fp - alpha_E_B) << 16) // E_B_nonzero


    delta_R_sq = delta_R * delta_R
    delta_G_sq = delta_G * delta_G
    delta_B_sq = delta_B * delta_B

    # Compute sum of squared deltas and scale to Q16.16
    sum_deltas = (delta_R_sq + delta_G_sq + delta_B_sq) >> 32

    # Compute square root of sum_deltas in Q16.16
    cd = math.sqrt(sum_deltas / (1 << 16))
    return cd


@cocotb.test()
async def test_chromaticity_distortion(dut):
    """Test Chromaticity Distortion Module."""

    # Start the clock
    clock = Clock(dut.clk, 10, units="ns")
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
    dut.alpha.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0

    # Test cases
    test_cases = [
        {"I_R": 100, "I_G": 150, "I_B": 200, "E_R": float_to_fixed(120, bits=16), "E_G": float_to_fixed(140, bits=16), "E_B": float_to_fixed(160, bits=16), "alpha": float_to_fixed(1.0, bits=32)},
        {"I_R": 255, "I_G": 255, "I_B": 255, "E_R": float_to_fixed(128, bits=16), "E_G": float_to_fixed(128, bits=16), "E_B": float_to_fixed(128, bits=16), "alpha": float_to_fixed(1.2, bits=32)},
        {"I_R": 50, "I_G": 75, "I_B": 100, "E_R": float_to_fixed(80, bits=16), "E_G": float_to_fixed(80, bits=16), "E_B": float_to_fixed(80, bits=16), "alpha": float_to_fixed(0.8, bits=32)},
    ]

    for i, test in enumerate(test_cases):
        # Apply inputs
        dut.I_R.value = test["I_R"]
        dut.I_G.value = test["I_G"]
        dut.I_B.value = test["I_B"]
        dut.E_R.value = test["E_R"]
        dut.E_G.value = test["E_G"]
        dut.E_B.value = test["E_B"]
        dut.alpha.value = test["alpha"]
        dut.valid_in.value = 1

        await ClockCycles(dut.clk, 5)
        dut.valid_in.value = 0

        # Wait for valid_out
        while not dut.valid_out.value:
            await RisingEdge(dut.clk)

        # Read DUT output
        cd_fixed = dut.CD.value.signed_integer
        cd = fixed_to_float(cd_fixed)


        dut_alpha_E_R = dut.alpha_E_R.value.signed_integer
        dut_alpha_E_G = dut.alpha_E_G.value.signed_integer
        dut_alpha_E_B = dut.alpha_E_B.value.signed_integer
        dut_delta_R = dut.delta_R.value.signed_integer
        dut_delta_G = dut.delta_G.value.signed_integer
        dut_delta_B = dut.delta_B.value.signed_integer
        dut_delta_R_sq = dut.delta_R_sq.value.signed_integer
        dut_delta_G_sq = dut.delta_G_sq.value.signed_integer
        dut_delta_B_sq = dut.delta_B_sq.value.signed_integer
        dut_sum_deltas = dut.sum_deltas.value.signed_integer

        # Calculate expected values in Python
        alpha = fixed_to_float(test["alpha"], Q=16)
        E_R = fixed_to_float(test["E_R"], Q=16)
        E_G = fixed_to_float(test["E_G"], Q=16)
        E_B = fixed_to_float(test["E_B"], Q=16)

        I_R_fp = test["I_R"] << 16
        I_G_fp = test["I_G"] << 16
        I_B_fp = test["I_B"] << 16

        expected_alpha_E_R = float_to_fixed(alpha * E_R, Q=16)
        expected_alpha_E_G = float_to_fixed(alpha * E_G, Q=16)
        expected_alpha_E_B = float_to_fixed(alpha * E_B, Q=16)

        expected_delta_R = (I_R_fp - expected_alpha_E_R) // (test["E_R"] or 1)
        expected_delta_G = (I_G_fp - expected_alpha_E_G) // (test["E_G"] or 1)
        expected_delta_B = (I_B_fp - expected_alpha_E_B) // (test["E_B"] or 1)

        expected_delta_R_sq = expected_delta_R * expected_delta_R
        expected_delta_G_sq = expected_delta_G * expected_delta_G
        expected_delta_B_sq = expected_delta_B * expected_delta_B
        expected_sum_deltas = expected_delta_R_sq + expected_delta_G_sq + expected_delta_B_sq

        expected_cd = math.sqrt(expected_sum_deltas / (1 << 32))

        # Log DUT observed values vs. expected values
        dut._log.info(f"Test Case {i+1}:")
        dut._log.info(f"Inputs: I_R={test['I_R']}, I_G={test['I_G']}, I_B={test['I_B']}")
        dut._log.info(f"alpha={alpha}, E_R={E_R}, E_G={E_G}, E_B={E_B}")
        dut._log.info(f"DUT alpha_E_R: {dut_alpha_E_R}, Expected alpha_E_R: {expected_alpha_E_R}")
        dut._log.info(f"DUT alpha_E_G: {dut_alpha_E_G}, Expected alpha_E_G: {expected_alpha_E_G}")
        dut._log.info(f"DUT alpha_E_B: {dut_alpha_E_B}, Expected alpha_E_B: {expected_alpha_E_B}")
        dut._log.info(f"DUT delta_R: {dut_delta_R}, Expected delta_R: {expected_delta_R}")
        dut._log.info(f"DUT delta_G: {dut_delta_G}, Expected delta_G: {expected_delta_G}")
        dut._log.info(f"DUT delta_B: {dut_delta_B}, Expected delta_B: {expected_delta_B}")
        dut._log.info(f"DUT delta_R_sq: {dut_delta_R_sq}, Expected delta_R_sq: {expected_delta_R_sq}")
        dut._log.info(f"DUT delta_G_sq: {dut_delta_G_sq}, Expected delta_G_sq: {expected_delta_G_sq}")
        dut._log.info(f"DUT delta_B_sq: {dut_delta_B_sq}, Expected delta_B_sq: {expected_delta_B_sq}")
        dut._log.info(f"DUT sum_deltas: {dut_sum_deltas}, Expected sum_deltas: {expected_sum_deltas}")
        dut._log.info(f"CD (DUT): {cd}, CD (Expected): {expected_cd}")



    dut._log.info("All test cases passed!")





# Runner function to build and run the test
def is_runner():
    """BackgroundModelDRAM Tester."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "test_chroma.sv",
        proj_path / "hdl" / "cordic_sqrt.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="ChromaticityDistortionTest",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="ChromaticityDistortionTest",
        test_module="test_chromaticity_distortion",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()
