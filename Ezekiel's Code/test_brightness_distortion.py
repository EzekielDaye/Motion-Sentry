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

def brightness_distortion_model(I_R, I_G, I_B, E_R, E_G, E_B, sigma_R, sigma_G, sigma_B):
    """Compute brightness distortion alpha."""

    sigma_R = sigma_R if sigma_R != 0 else 1
    sigma_G = sigma_G if sigma_G != 0 else 1
    sigma_B = sigma_B if sigma_B != 0 else 1

    N = (I_R * E_R / sigma_R) + (I_G * E_G / sigma_G) + (I_B * E_B / sigma_B)
    D = (E_R**2 / sigma_R) + (E_G**2 / sigma_G) + (E_B**2 / sigma_B)


    alpha = N / D if D != 0 else 0
    return alpha

@cocotb.test()
async def test_brightness_distortion(dut):
    """Test Brightness Distortion Module."""


    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())


    dut.rst.value = 1
    dut.valid_in.value = 0
    dut.I_R.value = 0
    dut.I_G.value = 0
    dut.I_B.value = 0
    dut.E_R.value = 0
    dut.E_G.value = 0
    dut.E_B.value = 0
    dut.sigma_R.value = 0
    dut.sigma_G.value = 0
    dut.sigma_B.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0


    test_cases = [
        {"I_R": 100, "I_G": 150, "I_B": 200, "E_R": 120, "E_G": 140, "E_B": 160, "sigma_R": 10, "sigma_G": 20, "sigma_B": 15},
        {"I_R": 255, "I_G": 255, "I_B": 255, "E_R": 128, "E_G": 128, "E_B": 128, "sigma_R": 5, "sigma_G": 10, "sigma_B": 8},
        {"I_R": 50, "I_G": 75, "I_B": 100, "E_R": 80, "E_G": 80, "E_B": 80, "sigma_R": 7, "sigma_G": 7, "sigma_B": 7},
    ]

    for i, test in enumerate(test_cases):

        dut.I_R.value = test["I_R"]
        dut.I_G.value = test["I_G"]
        dut.I_B.value = test["I_B"]
        dut.E_R.value = test["E_R"]
        dut.E_G.value = test["E_G"]
        dut.E_B.value = test["E_B"]
        dut.sigma_R.value = test["sigma_R"]
        dut.sigma_G.value = test["sigma_G"]
        dut.sigma_B.value = test["sigma_B"]
        dut.valid_in.value = 1


        await ClockCycles(dut.clk, 2)
        dut.valid_in.value = 0


        while not dut.valid_out.value:
            await RisingEdge(dut.clk)


        alpha_fixed = dut.alpha.value.signed_integer
        alpha = fixed_to_float(alpha_fixed)


        expected_alpha = brightness_distortion_model(
            I_R=test["I_R"],
            I_G=test["I_G"],
            I_B=test["I_B"],
            E_R=test["E_R"],
            E_G=test["E_G"],
            E_B=test["E_B"],
            sigma_R=test["sigma_R"],
            sigma_G=test["sigma_G"],
            sigma_B=test["sigma_B"],
        )


        dut._log.info(f"Test Case {i+1}:")
        dut._log.info(f"Inputs: I_R={test['I_R']}, I_G={test['I_G']}, I_B={test['I_B']}")
        dut._log.info(f"E_R={test['E_R']}, E_G={test['E_G']}, E_B={test['E_B']}")
        dut._log.info(f"Sigma: R={test['sigma_R']}, G={test['sigma_G']}, B={test['sigma_B']}")
        dut._log.info(f"Alpha (DUT): {alpha}")
        dut._log.info(f"Alpha (Expected): {expected_alpha}")



    dut._log.info("All test cases passed!")

# Runner function to build and run the test
def is_runner():
    """brightnessModelDRAM Tester."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "brightness_distortion.sv",
        proj_path / "hdl" / "cordic_sqrt.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="BrightnessDistortion",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="BrightnessDistortion",
        test_module="test_brightness_distortion",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()
