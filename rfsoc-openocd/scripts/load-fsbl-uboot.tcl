# Load and run FSBL, then load and run U-Boot on Zynq UltraScale+ RFSoC.
#
# Required command-line variables:
#   set FSBL_ELF  /abs/path/fsbl.elf
#   set UBOOT_ELF /abs/path/u-boot.elf
#
# Optional variables:
#   set A53_TARGET       zynqmp.a53.0
#   set FSBL_WAIT_MS     5000
#   set RESET_BEFORE_RUN 0
#
# Example:
#   openocd \
#     -f rfsoc-openocd/openocd.cfg \
#     -c "set FSBL_ELF /tmp/fsbl.elf" \
#     -c "set UBOOT_ELF /tmp/u-boot.elf" \
#     -f rfsoc-openocd/scripts/load-fsbl-uboot.tcl

proc fail {message} {
    echo "ERROR: $message"
    shutdown error
}

proc require_var {name} {
    upvar #0 $name value
    if {![info exists value] || $value eq ""} {
        fail "missing required variable $name"
    }
}

proc require_file {path description} {
    if {![file exists $path]} {
        fail "$description does not exist: $path"
    }
    if {![file isfile $path]} {
        fail "$description is not a regular file: $path"
    }
}

proc byte_at {bytes offset} {
    binary scan [string index $bytes $offset] c value
    return [expr {$value & 0xff}]
}

proc u32le {bytes offset} {
    set b0 [byte_at $bytes $offset]
    set b1 [byte_at $bytes [expr {$offset + 1}]]
    set b2 [byte_at $bytes [expr {$offset + 2}]]
    set b3 [byte_at $bytes [expr {$offset + 3}]]
    return [expr {$b0 | ($b1 << 8) | ($b2 << 16) | ($b3 << 24)}]
}

proc u64le {bytes offset} {
    set lo [u32le $bytes $offset]
    set hi [u32le $bytes [expr {$offset + 4}]]
    return [expr {($hi << 32) | $lo}]
}

proc hex_addr {value} {
    set lo [expr {$value & 0xffffffff}]
    set hi [expr {($value >> 32) & 0xffffffff}]

    if {$hi == 0} {
        return [format "0x%08x" $lo]
    }

    return [format "0x%08x%08x" $hi $lo]
}

proc elf_entry {path} {
    set fd [open $path rb]
    set header [read $fd 64]
    close $fd

    if {[string length $header] < 52} {
        fail "ELF header is too short: $path"
    }

    if {[string range $header 0 3] ne "\x7fELF"} {
        fail "not an ELF file: $path"
    }

    binary scan [string index $header 4] c elf_class
    binary scan [string index $header 5] c elf_data

    if {$elf_data != 1} {
        fail "only little-endian ELF files are supported by this script: $path"
    }

    if {$elf_class == 1} {
        return [u32le $header 24]
    }

    if {$elf_class == 2} {
        return [u64le $header 24]
    }

    fail "unsupported ELF class in $path"
}

proc load_and_resume_elf {path label} {
    set entry [elf_entry $path]

    echo "Loading $label: $path"
    echo "Entry point: [hex_addr $entry]"

    load_image $path
    resume $entry
}

require_var FSBL_ELF
require_var UBOOT_ELF
require_file $FSBL_ELF "FSBL ELF"
require_file $UBOOT_ELF "U-Boot ELF"

if {![info exists A53_TARGET]} {
    set A53_TARGET zynqmp.a53.0
}

if {![info exists FSBL_WAIT_MS]} {
    set FSBL_WAIT_MS 5000
}

if {![info exists RESET_BEFORE_RUN]} {
    set RESET_BEFORE_RUN 0
}

init

echo "Selecting A53 target: $A53_TARGET"
targets $A53_TARGET

if {$RESET_BEFORE_RUN} {
    echo "Resetting and halting target"
    reset halt
} else {
    echo "Halting target without reset"
    halt
}

load_and_resume_elf $FSBL_ELF "FSBL"

echo "Waiting $FSBL_WAIT_MS ms for FSBL to initialize clocks, MIO and DDR"
sleep $FSBL_WAIT_MS

echo "Halting A53 after FSBL"
halt

load_and_resume_elf $UBOOT_ELF "U-Boot"

echo "U-Boot is running. OpenOCD will stay attached; press Ctrl-C to exit."
