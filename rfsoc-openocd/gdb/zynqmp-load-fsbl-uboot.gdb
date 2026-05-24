# GDB command helpers for loading FSBL and U-Boot through an OpenOCD GDB server.
#
# Start OpenOCD separately:
#   openocd -f rfsoc-openocd/openocd.cfg
#
# Then run GDB:
#   aarch64-none-elf-gdb \
#     -ex "source rfsoc-openocd/gdb/zynqmp-load-fsbl-uboot.gdb" \
#     -ex "connect_zynqmp localhost:3333" \
#     -ex "load_fsbl_uboot /absolute/path/to/fsbl.elf /absolute/path/to/u-boot.elf"

set pagination off
set confirm off
set target-async on

define connect_zynqmp
    if $argc != 1
        echo Usage: connect_zynqmp HOST:PORT\n
        quit 1
    end

    target extended-remote $arg0
    monitor targets zynqmp.a53.0
    monitor halt
end

document connect_zynqmp
Connect to the OpenOCD GDB server and select the first A53 target.
Usage: connect_zynqmp localhost:3333
end

define load_fsbl_uboot
    if $argc != 2
        echo Usage: load_fsbl_uboot FSBL_ELF UBOOT_ELF\n
        quit 1
    end

    echo Loading FSBL: $arg0\n
    file $arg0
    load
    continue &

    echo Waiting for FSBL to initialize clocks, MIO and DDR...\n
    shell sleep 5
    interrupt

    echo Loading U-Boot: $arg1\n
    file $arg1
    load
    continue
end

document load_fsbl_uboot
Load FSBL, let it initialize the platform, then load and run U-Boot.
Usage: load_fsbl_uboot /absolute/path/to/fsbl.elf /absolute/path/to/u-boot.elf
end
