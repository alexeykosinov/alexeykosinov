# RFSoC OpenOCD + GDB FSBL/U-Boot loader

Minimal OpenOCD setup for connecting to a Xilinx Zynq UltraScale+ RFSoC such
as `xczu47dr` over JTAG. The standard flow is to run OpenOCD as a GDB server
and load `fsbl.elf` / `u-boot.elf` from `aarch64-none-elf-gdb`.

The target board described for this example uses two 1.8 V S25HS512T NOR
devices connected to the PS QSPI controller in dual-parallel QSPI32 mode. The
JTAG flow below does not program the flash directly; it only loads boot
software into the processor system so that the PS software can initialize the
board and access DDR/QSPI.

## Files

```text
rfsoc-openocd/
  gdb/zynqmp-load-fsbl-uboot.gdb
  interface/ft4232h-channel-a-jtag.cfg
  openocd.cfg                    # JTAG adapter + ZynqMP/RFSoC target
```

## 1. Start OpenOCD

```bash
openocd -f rfsoc-openocd/openocd.cfg
```

By default this uses `rfsoc-openocd/interface/ft4232h-channel-a-jtag.cfg`,
intended for a custom FT4232H adapter where channel A is JTAG and the remaining
channels are UARTs.

The default FT4232H USB ID is `0403:6011`. If your EEPROM programmed by Xilinx
`program_ftdi` uses a different VID/PID, override it:

```bash
openocd \
  -c "set FTDI_VID 0x0403" \
  -c "set FTDI_PID 0x6011" \
  -c "set FTDI_CHANNEL 0" \
  -f rfsoc-openocd/openocd.cfg
```

If several FTDI adapters are attached, select the programmed EEPROM serial:

```bash
-c "set FTDI_SERIAL your-serial-string"
```

On Linux, the currently enumerated VID/PID and serial are usually visible with:

```bash
lsusb -d 0403:
udevadm info -q property -n /dev/ttyUSB0 | grep -E 'ID_VENDOR_ID|ID_MODEL_ID|ID_SERIAL_SHORT'
```

The FT4232H channel A wiring assumed by the interface file is:

```text
ADBUS0 / TCK / SK  -> RFSoC TCK
ADBUS1 / TDI / DO  -> RFSoC TDI
ADBUS2 / TDO / DI  <- RFSoC TDO
ADBUS3 / TMS / CS  -> RFSoC TMS
GND                -> board GND
```

The JTAG voltage must match the board JTAG bank through VREF-aware buffers or
level shifting. The FT4232H USB chip itself is not a 1.8 V JTAG adapter unless
your custom hardware provides the proper I/O voltage domain/translation.

If your JTAG adapter is not this custom FT4232H, override the interface file:

```bash
openocd \
  -c "set JTAG_INTERFACE interface/jlink.cfg" \
  -c "set JTAG_SPEED_KHZ 8000" \
  -f rfsoc-openocd/openocd.cfg
```

## 2. Load FSBL and U-Boot from GDB

In another terminal:

```bash
aarch64-none-elf-gdb \
  -ex "source rfsoc-openocd/gdb/zynqmp-load-fsbl-uboot.gdb" \
  -ex "connect_zynqmp localhost:3333" \
  -ex "load_fsbl_uboot /absolute/path/to/fsbl.elf /absolute/path/to/u-boot.elf"
```

This is the usual OpenOCD flow: OpenOCD only provides JTAG access and a GDB
remote server; GDB performs the ELF section download and starts execution.

The same sequence can be typed manually:

```gdb
set pagination off
set target-async on
target extended-remote localhost:3333
monitor targets zynqmp.a53.0
monitor halt

file /absolute/path/to/fsbl.elf
load
continue &

shell sleep 5
interrupt

file /absolute/path/to/u-boot.elf
load
continue
```

If your OpenOCD build names the first A53 target differently, run once with:

```bash
openocd -f rfsoc-openocd/openocd.cfg -c init -c targets -c shutdown
```

Then replace `zynqmp.a53.0` in the GDB `monitor targets ...` command.

If GDB loads the ELF but execution does not start at the ELF entry point, check
the entry address with:

```gdb
info files
```

Then set the PC explicitly before `continue`:

```gdb
set $pc = 0xENTRY_ADDRESS
continue
```

## Notes for ZynqMP/RFSoC

- `fsbl.elf` must be built for the exact board configuration: PS clocks, MIO,
  DDR and QSPI32 dual-parallel settings must match the hardware.
- The GDB helper waits 5 seconds for FSBL to initialize the platform, interrupts
  A53, then loads `u-boot.elf`. Increase the `shell sleep 5` delay if DDR or
  board init takes longer.
- A normal ZynqMP U-Boot flow often also needs PMU firmware and ARM Trusted
  Firmware (`bl31.elf`). This minimal flow assumes your `u-boot.elf` is
  suitable to run directly after FSBL, or that those stages are already handled
  by your FSBL/U-Boot build.
- For flash programming, U-Boot can be used to access the PS QSPI controller
  after it is running. Direct boundary-scan programming of dual-parallel QSPI32
  is not recommended.
