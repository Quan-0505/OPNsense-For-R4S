# Inspect the OPNsense R4S arm image: decompress copy, parse partition table,
# find u-boot / bootloader areas and detect the rootfs type.
import os, struct, subprocess, sys, shutil, hashlib

xz = r"C:\Users\quan\Desktop\NetProxy-optimized-config-share\R4S-OPNsense\build\OPNsense-26.7.3-arm-aarch64-R4S.img.xz"
img = xz[:-3]

if not os.path.exists(img):
    print("decompressing with 7z/bsdtar...")
    # try tar (bsdtar) first, then 7z
    for tool in [["tar", "-xf", xz, "-C", os.path.dirname(xz)],
                 ["C:/Program Files/7-Zip/7z.exe", "x", xz, f"-o{os.path.dirname(xz)}", "-y"]]:
        try:
            r = subprocess.run(tool, capture_output=True, timeout=1800)
            if os.path.exists(img):
                break
        except Exception as e:
            print("tool fail:", e)

print("img exists:", os.path.exists(img), os.path.getsize(img) if os.path.exists(img) else "")

f = open(img, "rb")
size = os.path.getsize(img)

def read_at(off, n):
    f.seek(off); return f.read(n)

# MBR check
mbr = read_at(0, 512)
sig = struct.unpack("<H", mbr[510:512])[0]
print("MBR sig:", hex(sig), "legacy:", sig == 0xAA55)

# GPT check (LBA1)
gpt = read_at(512, 512)
print("GPT magic:", gpt[:8])

# partition table entries from GPT
if gpt[:8] == b"EFI PART":
    def parse_guid(b):
        return "-".join([b[0:4].hex(), b[4:6].hex(), b[6:8].hex(), b[8:10].hex(), b[10:16].hex()])
    entries_lba = struct.unpack("<Q", read_at(512+72, 8))[0]
    n_entries = struct.unpack("<I", read_at(512+80, 4))[0]
    esize = struct.unpack("<I", read_at(512+84, 4))[0]
    print(f"GPT entries @ lba {entries_lba}, {n_entries} entries, esize {esize}")
    for i in range(min(n_entries, 16)):
        e = read_at(entries_lba*512 + i*esize, esize)
        if e[:16] == b"\x00"*16: continue
        type_guid = parse_guid(e[0:16])
        start = struct.unpack("<Q", e[32:40])[0]
        end = struct.unpack("<Q", e[40:48])[0]
        name = e[56:128].decode("utf-16-le", errors="replace").rstrip("\x00")
        print(f"  part{i}: type={type_guid} start={start} end={end} size={(end-start+1)*512/1024/1024:.1f}MB name={name!r}")
else:
    # MBR partitions
    for i in range(4):
        pe = mbr[446+i*16:446+(i+1)*16]
        ptype = pe[4]
        if ptype == 0: continue
        start_lba = struct.unpack("<I", pe[8:12])[0]
        n_lba = struct.unpack("<I", pe[12:16])[0]
        print(f"  MBR part{i}: type=0x{ptype:02x} start={start_lba} sectors={n_lba} size={n_lba*512/1024/1024:.1f}MB")

# scan first 16MB for u-boot signatures
print("\nscanning for bootloader markers...")
for needle in [b"U-Boot 20", b"U-Boot SPL", b"u-boot", b"IDBLoader", b"RKNS", b"boot.img", b"uboot"]:
    hits = []
    start = 0
    while True:
        i = img.find(needle, start, min(size, 64*1024*1024)) if False else None
        break
# simple scan over first 64MiB for "U-Boot 20"
import io
buf = read_at(0, min(size, 64*1024*1024))
for needle in [b"U-Boot 20", b"U-Boot SPL 20", b"uboot.img", b"loader.efi"]:
    idxs = []
    pos = 0
    while True:
        j = buf.find(needle, pos)
        if j < 0: break
        idxs.append(j)
        pos = j+1
        if len(idxs) > 5: break
    print(f"  {needle.decode()}: {[(hex(i), buf[max(0,i-8):i+40].hex()[:40]) for i in idxs]}")
f.close()
print("done")
