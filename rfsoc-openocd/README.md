# RFSoC OpenOCD FSBL + U-Boot loader

Minimal OpenOCD setup for loading an FSBL ELF and then a U-Boot ELF over JTAG
on a Xilinx Zynq UltraScale+ RFSoC such as `xczu47dr`.

The target board described for this example uses two 1.8 V S25HS512T NOR
devices connected to the PS QSPI controller in dual-parallel QSPI32 mode. The
JTAG flow below does not program the flash directly; it only loads boot
software into the processor system so that the PS software can initialize the
board and access DDR/QSPI.

## Files

```text
rfsoc-openocd/
  openocd.cfg                    # JTAG adapter + ZynqMP/RFSoC target
  scripts/load-fsbl-uboot.tcl    # load FSBL ELF, wait, load U-Boot ELF
```

## Run

```bash
openocd \
  -f rfsoc-openocd/openocd.cfg \
  -c "set FSBL_ELF /absolute/path/to/fsbl.elf" \
  -c "set UBOOT_ELF /absolute/path/to/u-boot.elf" \
  -f rfsoc-openocd/scripts/load-fsbl-uboot.tcl
```

If your JTAG adapter is not Digilent HS2, override the interface file:

```bash
openocd \
  -c "set JTAG_INTERFACE interface/jlink.cfg" \
  -c "set JTAG_SPEED_KHZ 8000" \
  -f rfsoc-openocd/openocd.cfg \
  -c "set FSBL_ELF /absolute/path/to/fsbl.elf" \
  -c "set UBOOT_ELF /absolute/path/to/u-boot.elf" \
  -f rfsoc-openocd/scripts/load-fsbl-uboot.tcl
```

If your board has reliable JTAG-controlled reset and you want OpenOCD to reset
the target before loading FSBL, add:

```bash
-c "set RESET_BEFORE_RUN 1"
```

If your OpenOCD build names the first A53 target differently, run once with:

```bash
openocd -f rfsoc-openocd/openocd.cfg -c init -c targets -c shutdown
```

Then pass the observed A53 target name:

```bash
-c "set A53_TARGET zynqmp.a53.0"
```

## Notes for ZynqMP/RFSoC

- `fsbl.elf` must be built for the exact board configuration: PS clocks, MIO,
  DDR and QSPI32 dual-parallel settings must match the hardware.
- The script waits for FSBL to initialize the platform, halts A53, then loads
  `u-boot.elf`. Increase `FSBL_WAIT_MS` if DDR or board init takes longer.
- A normal ZynqMP U-Boot flow often also needs PMU firmware and ARM Trusted
  Firmware (`bl31.elf`). This minimal script assumes your `u-boot.elf` is
  suitable to run directly after FSBL, or that those stages are already handled
  by your FSBL/U-Boot build.
- For flash programming, U-Boot can be used to access the PS QSPI controller
  after it is running. Direct boundary-scan programming of dual-parallel QSPI32
  is not recommended.
