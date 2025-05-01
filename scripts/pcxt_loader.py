#!/usr/bin/env python3

# load floppy images to PCXT core over UART

import serial
import sys
import os

def WRITE(ser, addr, data):
    d = b'\x0a' + addr.to_bytes(2, 'big') + data.to_bytes(2, 'big')
    ser.write(d)

if len(sys.argv) < 2:
    print("Usage: pcxt_loader.py <serial_port> [image1] [image2]")
    sys.exit(1)

# open serial port
ser = serial.Serial(sys.argv[1], 2000000)

if len(sys.argv) >= 3:
    image1 = sys.argv[2]

# turn overlay off
ser.write(b'\x08\x00')

# load BIOS
with open("bios.bin", "rb") as f:
    bios = f.read()
    ser.write(b'\x06\x01')
    ser.write(b'\x07' + len(bios).to_bytes(3, 'big'))
    ser.write(bios)
    ser.write(b'\x06\x00')
    print("BIOS loaded")

# only support 360k floppy for now
# test file size
if os.path.getsize(image1) != 360 * 1024:
    print("Error: 360k floppy image required")
    sys.exit(1)

# mount floppy
disk = open(image1, "rb")

# x86.cpp fdd_set()
WRITE(ser, 0xf200, 1)       # media present
WRITE(ser, 0xf201, 0)       # write protect
WRITE(ser, 0xf202, 40)      # cylinders
WRITE(ser, 0xf203, 9)       # sectors per track
WRITE(ser, 0xf204, 720)     # total sectors
WRITE(ser, 0xf205, 2)       # heads

print("Floppy mounted. Now waiting for requests...")

# read message from FPGA and process floppy ones (0x2 write and 0x3 read)
while True:
    msg = ser.read(1)
    if msg == b'\x02':
        sector = int.from_bytes(ser.read(2), 'big')
        data = ser.read(512)
        print(f"Writing sector {sector} to floppy")
        disk.seek(sector * 512)
        disk.write(data)
    elif msg == b'\x03':
        sector = int.from_bytes(ser.read(2), 'big')
        disk.seek(sector * 512)
        data = disk.read(512)
        print(f"Reading sector {sector} from floppy")
        ser.write(b'\x0b')
        ser.write(data)
    elif msg == b'\x01':           # joypad update
        ser.read(4)
    else:
        print(f"Unknown message: {msg}")

