#!/usr/bin/env python3
"""
elf2mem.py: Converts raw binary / ELF dumps to 32-bit hex words for tiny-gpu memory loading.
"""

import sys
import struct


def bin_to_hex(input_bin_path, output_hex_path, word_bytes=4):
    with open(input_bin_path, "rb") as f:
        data = f.read()

    # Pad data to multiple of word_bytes
    if len(data) % word_bytes != 0:
        data += b"\x00" * (word_bytes - (len(data) % word_bytes))

    words = []
    for i in range(0, len(data), word_bytes):
        chunk = data[i : i + word_bytes]
        if word_bytes == 4:
            val = struct.unpack("<I", chunk)[0]
            words.append(f"{val:08x}")
        elif word_bytes == 16:
            val_low = struct.unpack("<Q", chunk[:8])[0]
            val_high = struct.unpack("<Q", chunk[8:])[0]
            words.append(f"{val_high:016x}{val_low:016x}")

    with open(output_hex_path, "w") as f:
        for w in words:
            f.write(w + "\n")

    print(f"Successfully generated {output_hex_path} ({len(words)} entries).")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 elf2mem.py <input.bin> <output.hex> [word_bytes]")
        sys.exit(1)

    word_size = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    bin_to_hex(sys.argv[1], sys.argv[2], word_size)
