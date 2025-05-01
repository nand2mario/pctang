if {$argc == 0} {
    puts "Usage: $argv0 <device>"
    puts "          device: console60k console138k"
    exit 1
}

set dev [lindex $argv 0]

if {$dev eq "console60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    add_file -type verilog "src/plla/pll.v"
    add_file -type verilog "src/plla/pll_27.v"
    add_file -type verilog "src/plla/pll_74.v"
} elseif {$dev eq "console138k"} {
    set_device GW5AST-LV138PG484AC1/I0 -device_version B
    add_file -type verilog "src/pll/pll.v"
    add_file -type verilog "src/pll/pll_27.v"
    add_file -type verilog "src/pll/pll_74.v"
}
set_option -output_base_name pctang_${dev}

add_file -type cst "src/boards/console.cst"

add_file -type verilog "src/8088/biu_max.v"
add_file -type verilog "src/8088/eu_rom.v"
add_file -type verilog "src/8088/i8088.v"
add_file -type verilog "src/8088/mcl86_eu_core.v"
add_file -type verilog "src/KFPC-XT/HDL/Bus_Arbiter.sv"
add_file -type verilog "src/KFPC-XT/HDL/Chipset.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8237/HDL/KF8237.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8237/HDL/KF8237_Address_And_Count_Registers.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8237/HDL/KF8237_Bus_Control_Logic.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8237/HDL/KF8237_Priority_Encoder.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8237/HDL/KF8237_Timing_And_Control.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8253/HDL/KF8253.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8253/HDL/KF8253_Control_Logic.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8253/HDL/KF8253_Counter.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8255/HDL/KF8255.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8255/HDL/KF8255_Control_Logic.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8255/HDL/KF8255_Group.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8255/HDL/KF8255_Port.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8255/HDL/KF8255_Port_C.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8259/HDL/KF8259.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8259/HDL/KF8259_Bus_Control_Logic.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8259/HDL/KF8259_Control_Logic.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8259/HDL/KF8259_In_Service.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8259/HDL/KF8259_Interrupt_Request.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8259/HDL/KF8259_Priority_Resolver.sv"
add_file -type verilog "src/KFPC-XT/HDL/KF8288/HDL/KF8288.sv"
add_file -type verilog "src/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB.sv"
add_file -type verilog "src/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB_Send_Data.sv"
add_file -type verilog "src/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB_Shift_Register.sv"
add_file -type verilog "src/KFPC-XT/HDL/KFPS2KB/HDL/Tandy_Scancode_Converter.sv"
add_file -type verilog "src/KFPC-XT/HDL/KFSDRAM/HDL/KFSDRAM.sv"
add_file -type verilog "src/KFPC-XT/HDL/Peripherals.sv"
add_file -type verilog "src/KFPC-XT/HDL/RAM2.sv"
add_file -type verilog "src/KFPC-XT/HDL/Ready.sv"
add_file -type verilog "src/KFPC-XT/HDL/XT2IDE.sv"
add_file -type verilog "src/KFPC-XT/HDL/rtc.v"
add_file -type verilog "src/cga2hdmi.sv"
add_file -type verilog "src/common/MSMouseWrapper.v"
add_file -type verilog "src/common/floppy.v"
add_file -type verilog "src/common/ps2_device.v"
add_file -type verilog "src/common/simple_fifo.v"
add_file -type verilog "src/common/simple_ram.v"
add_file -type verilog "src/common/tandy_pcjr_joy.sv"
add_file -type verilog "src/hdmi2/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi2/audio_info_frame.sv"
add_file -type verilog "src/hdmi2/audio_sample_packet.sv"
add_file -type verilog "src/hdmi2/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi2/hdmi.sv"
add_file -type verilog "src/hdmi2/packet_assembler.sv"
add_file -type verilog "src/hdmi2/packet_picker.sv"
add_file -type verilog "src/hdmi2/serializer.sv"
add_file -type verilog "src/hdmi2/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi2/tmds_channel.sv"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"
add_file -type verilog "src/pctang_top.sv"
add_file -type verilog "src/sdram.v"
add_file -type verilog "src/sound/saa1099.sv"
add_file -type verilog "src/video/UM6845R.v"
add_file -type verilog "src/video/cga.v"
add_file -type verilog "src/video/cga_attrib.v"
add_file -type verilog "src/video/cga_composite.v"
add_file -type verilog "src/video/cga_pixel.sv"
add_file -type verilog "src/video/cga_scandoubler.v"
add_file -type verilog "src/video/cga_sequencer.v"
add_file -type verilog "src/video/cga_vgaport.v"
add_file -type verilog "src/video/cga_vram.v"
add_file -type verilog "src/video/vram.v"
# add_file -type gao "src/floppy_read.rao"
set_option -synthesis_tool gowinsynthesis
set_option -top_module pctang_top
set_option -verilog_std sysv2017
set_option -place_option 2

run all