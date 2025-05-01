N=pctang_top
D=../src
SRCS=$D/pctang_top.sv \
	$D/8088/biu_max.v $D/8088/eu_rom.v $D/8088/i8088.v $D/8088/mcl86_eu_core.v \
	$D/common/MSMouseWrapper.v $D/common/simple_ram.v $D/common/tandy_pcjr_joy.sv \
	$D/KFPC-XT/HDL/Bus_Arbiter.sv $D/KFPC-XT/HDL/Chipset.sv $D/KFPC-XT/HDL/Peripherals.sv \
	$D/KFPC-XT/HDL/RAM.sv $D/KFPC-XT/HDL/Ready.sv $D/KFPC-XT/HDL/rtc.v \
	$D/KFPC-XT/HDL/XT2IDE.sv $D/common/floppy.v $D/common/simple_fifo.v \
	$D/KFPC-XT/HDL/KF8237/HDL/KF8237.sv $D/KFPC-XT/HDL/KF8237/HDL/KF8237_Address_And_Count_Registers.sv \
	$D/KFPC-XT/HDL/KF8237/HDL/KF8237_Bus_Control_Logic.sv $D/KFPC-XT/HDL/KF8237/HDL/KF8237_Priority_Encoder.sv \
	$D/KFPC-XT/HDL/KF8237/HDL/KF8237_Timing_And_Control.sv $D/KFPC-XT/HDL/KF8253/HDL/KF8253.sv \
	$D/KFPC-XT/HDL/KF8253/HDL/KF8253_Control_Logic.sv $D/KFPC-XT/HDL/KF8253/HDL/KF8253_Counter.sv \
	$D/KFPC-XT/HDL/KF8255/HDL/KF8255.sv $D/KFPC-XT/HDL/KF8255/HDL/KF8255_Control_Logic.sv \
	$D/KFPC-XT/HDL/KF8255/HDL/KF8255_Group.sv $D/KFPC-XT/HDL/KF8255/HDL/KF8255_Port.sv \
	$D/KFPC-XT/HDL/KF8255/HDL/KF8255_Port_C.sv $D/KFPC-XT/HDL/KF8259/HDL/KF8259.sv \
	$D/KFPC-XT/HDL/KF8259/HDL/KF8259_Bus_Control_Logic.sv $D/KFPC-XT/HDL/KF8259/HDL/KF8259_Control_Logic.sv \
	$D/KFPC-XT/HDL/KF8259/HDL/KF8259_In_Service.sv $D/KFPC-XT/HDL/KF8259/HDL/KF8259_Interrupt_Request.sv \
	$D/KFPC-XT/HDL/KF8259/HDL/KF8259_Priority_Resolver.sv $D/KFPC-XT/HDL/KF8288/HDL/KF8288.sv \
	$D/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB.sv $D/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB_Send_Data.sv \
	$D/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB_Shift_Register.sv $D/KFPC-XT/HDL/KFPS2KB/HDL/Tandy_Scancode_Converter.sv \
	$D/sound/saa1099.sv $D/video/UM6845R.v $D/video/cga.v \
	$D/video/cga_attrib.v $D/video/cga_composite.v $D/video/cga_pixel.sv \
	$D/video/cga_scandoubler.v $D/video/cga_sequencer.v $D/video/cga_vgaport.v \
	$D/video/cga_vram.v $D/video/vram.v $D/common/ps2_device.v \
	$D/verilator/KFSDRAM_sim.sv $D/verilator/floppy_media_sim.sv $D/verilator/bios_loader.sv

DEPS=
INCLUDES=-I$D -I$D/KFPC-XT/HDL/KF8237/HDL -I$D/KFPC-XT/HDL/KF8253/HDL -I$D/KFPC-XT/HDL/KF8255/HDL -I$D/KFPC-XT/HDL/KF8259/HDL -I$D/KFPC-XT/HDL/KF8288/HDL

CFLAGS_SDL=$(shell sdl2-config --cflags) -g -O2
LIBS_SDL=$(shell sdl2-config --libs) -g

.PHONY: build sim verilate clean gtkwave audio
	
build: ./obj_dir/V$N

verilate: ./obj_dir/V$N.cpp

./obj_dir/V$N.cpp: sim_main.cpp $(SRCS) $(DEPS)
	@echo
	@echo "### VERILATE ####"
	mkdir -p obj_dir
	verilator --top-module $N +1800-2023ext+sv --trace-fst -Wno-PINMISSING -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -cc --exe -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" $(INCLUDES) $(SRCS) sim_main.cpp
#	verilator --top-module $N --timing --trace-fst -Wno-WIDTH -Wno-PINMISSING -Wno-UNOPTFLAT -cc --exe -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" $(INCLUDES) $(SRCS) sim_main.cpp

./obj_dir/V$N: verilate
	@echo
	@echo "### BUILDING SIM ###"
	make -C obj_dir -f V$N.mk V$N
	cp -a $D/8088/microcode.mem .
	cp -a $D/pcxt_ibm5160_bios.hex .
	cp -a $D/video/splash.hex .
	cp -a $D/video/cga.hex .
	hexdump -v -e '/1 "%02x\n"' ../../software/pcdos21_disk01.img > floppy.hex
# hexdump -v -e '/1 "%02x\n"' ../../software/dos321_disk01.img > floppy.hex

sim: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (GUI) ###"
	obj_dir/V$N

trace: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (trace) ###"
	obj_dir/V$N -t

gtkwave:
	gtkwave obj_dir/waveform.fst

audio:
	ffmpeg -y -f s16le -ar 48k -ac 2 -i md.aud md.wav

clean:
	rm -rf obj_dir
