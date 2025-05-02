#! /usr/bin/env python3

import os
import urllib.request
import zipfile
import argparse
import shutil

parser = argparse.ArgumentParser(prog="bios_make.py", description="Make a PC/XT BIOS image")
parser.add_argument("bios_type", type=str, choices=["original", "patched"], help="The original IBM 5160 BIOS or a patched version that boots faster by skipping the memory checks")
args = parser.parse_args()
bios_type = args.bios_type

SRC=["https://minuszerodegrees.net/bios/BIOS_5160_08NOV82.zip", "BIOS_5160_08NOV82_U19_5000027_27256.BIN", "BIOS_5160_08NOV82_U18_1501512.BIN"]

TMP_DIR = "bios_tmp"
os.makedirs(TMP_DIR, exist_ok=True)

req = urllib.request.Request(SRC[0], data=None, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.0.0 Safari/537.36'})
response = urllib.request.urlopen(req)

with open(os.path.join(TMP_DIR, "BIOS_5160_08NOV82.zip"), "wb") as f:
    f.write(response.read())

with zipfile.ZipFile(os.path.join(TMP_DIR, "BIOS_5160_08NOV82.zip"), "r") as zip_ref:
    zip_ref.extractall(TMP_DIR)

os.remove(os.path.join(TMP_DIR, "BIOS_5160_08NOV82.zip"))

bytes_buffer = bytearray()

with open(os.path.join(TMP_DIR, SRC[1]), "rb") as f1:
    bytes_buffer.extend(f1.read())
with open(os.path.join(TMP_DIR, SRC[2]), "rb") as f2:
    bytes_buffer.extend(f2.read())

if bios_type == "patched":
    # skip bios checksum
    bytes_buffer[0xE0D4] = 0x90
    bytes_buffer[0xE0D5] = 0x90
    bytes_buffer[0xE0D6] = 0x90
    bytes_buffer[0xE0D7] = 0x90
    bytes_buffer[0xE0D8] = 0x90
    # skip memory check
    bytes_buffer[0xE474] = 0x90
    bytes_buffer[0xE475] = 0x90

with open("bios.bin", "wb") as f:
    f.write(bytes_buffer)
    
shutil.rmtree(TMP_DIR)

print("bios.bin created")















