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
  openocd.cfg                    # FT4232H JTAG adapter + ZynqMP/RFSoC target
```

## 1. Start OpenOCD

```bash
openocd -f rfsoc-openocd/openocd.cfg
```

`openocd.cfg` is self-contained and intended for a custom FT4232H adapter where
channel A is JTAG and the remaining channels are UARTs.

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

The FT4232H channel A wiring assumed by `openocd.cfg` is:

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

## 2. Load FSBL and U-Boot from GDB

In another terminal:

```bash
aarch64-none-elf-gdb
```

Then from the GDB prompt:

```gdb
source rfsoc-openocd/gdb/zynqmp-load-fsbl-uboot.gdb
connect_zynqmp localhost:3333
load_fsbl /absolute/path/to/fsbl.elf
```

This is the usual OpenOCD flow: OpenOCD only provides JTAG access and a GDB
remote server; GDB performs the ELF section download and starts execution.

Wait until FSBL has initialized clocks, MIO and DDR, then press `Ctrl-C` in GDB
and load U-Boot:

```gdb
load_uboot /absolute/path/to/u-boot.elf
```

The same sequence can be typed manually without the helper file:

```gdb
set pagination off
target extended-remote localhost:3333
monitor targets zynqmp.a53.0
monitor halt

file /absolute/path/to/fsbl.elf
load
continue

# Wait for FSBL init, then press Ctrl-C in GDB.

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

## 3. Copy a firmware binary to DDR through JTAG/GDB

After U-Boot is running, the firmware image still has to be copied from the PC
into RFSoC DDR before U-Boot can write it to QSPI. Without Ethernet/TFTP, use
the same OpenOCD GDB connection and GDB's `restore ... binary ...` command.

Pick a DDR address that is free and does not overlap U-Boot, stacks, malloc
area or the image itself. `0x10000000` is a common example, but verify it
against your U-Boot memory map.

From GDB, interrupt U-Boot, copy the file to DDR, then continue U-Boot:

```gdb
load_bin_to_ddr /absolute/path/to/firmware.bin 0x10000000
```

The helper command above is equivalent to:

```gdb
monitor halt
restore /absolute/path/to/firmware.bin binary 0x10000000
continue
```

Because this transfer bypasses U-Boot file loading commands, U-Boot does not
automatically know the file size. Get the size on the host in hexadecimal:

```bash
printf '0x%x\n' "$(stat -c '%s' /absolute/path/to/firmware.bin)"
```

Then, in the U-Boot console, set the RAM address and size manually:

```bash
setenv loadaddr 0x10000000
setenv filesize 0xYOUR_FILE_SIZE_HEX
```

Probe the QSPI flash and write the RAM buffer to flash offset `0x0`:

```bash
sf probe
sf update ${loadaddr} 0x0 ${filesize}
```

If `sf update` is not available in your U-Boot build, erase and write manually.
The erase length usually must be aligned to the flash erase sector size. For a
256 KiB erase sector:

```bash
setexpr erase_size ${filesize} + 0x3ffff
setexpr erase_size ${erase_size} '&' 0xfffc0000
sf erase 0x0 ${erase_size}
sf write ${loadaddr} 0x0 ${filesize}
```

Verify by reading QSPI back to another DDR address and comparing:

```bash
setenv verifyaddr 0x20000000
sf read ${verifyaddr} 0x0 ${filesize}
cmp.b ${loadaddr} ${verifyaddr} ${filesize}
```

For the dual-parallel QSPI32 connection, U-Boot should expose the two
S25HS512T devices as one logical SPI flash. Do not split the binary manually
unless your board support package or U-Boot driver is not configured for
parallel QSPI.

## Notes for ZynqMP/RFSoC

- `fsbl.elf` must be built for the exact board configuration: PS clocks, MIO,
  DDR and QSPI32 dual-parallel settings must match the hardware.
- After `load_fsbl`, wait until FSBL has initialized the platform, interrupt
  A53 with `Ctrl-C`, then run `load_uboot`.
- A normal ZynqMP U-Boot flow often also needs PMU firmware and ARM Trusted
  Firmware (`bl31.elf`). This minimal flow assumes your `u-boot.elf` is
  suitable to run directly after FSBL, or that those stages are already handled
  by your FSBL/U-Boot build.
- For flash programming, U-Boot can be used to access the PS QSPI controller
  after it is running. Direct boundary-scan programming of dual-parallel QSPI32
  is not recommended.
