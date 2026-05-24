# GDB command helpers for loading FSBL and U-Boot through an OpenOCD GDB server.
#
# Start OpenOCD separately:
#   openocd -f rfsoc-openocd/openocd.cfg
#
# Then run GDB and type:
#   source rfsoc-openocd/gdb/zynqmp-load-fsbl-uboot.gdb
#   connect_zynqmp localhost:3333
#   load_fsbl /absolute/path/to/fsbl.elf
#   # wait for FSBL to initialize clocks/MIO/DDR, then press Ctrl-C
#   load_uboot /absolute/path/to/u-boot.elf

set pagination off
set confirm off

define connect_zynqmp
    if $argc != 1
        echo Usage: connect_zynqmp HOST:PORT\n
        quit 1
    end

    target extended-remote $arg0
    monitor targets zynqmp.a53.0
    monitor halt
end

define load_fsbl
    if $argc != 1
        echo Usage: load_fsbl FSBL_ELF\n
        quit 1
    end

    echo Loading FSBL: $arg0\n
    file $arg0
    load
    continue
end

define load_uboot
    if $argc != 1
        echo Usage: load_uboot UBOOT_ELF\n
        quit 1
    end

    echo Loading U-Boot: $arg0\n
    monitor halt
    file $arg0
    load
    continue
end
