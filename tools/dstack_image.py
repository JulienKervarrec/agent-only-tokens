#!/usr/bin/env python3
"""Recomputes the boot measurements of a dstack OS image and compares them with quotes.

    python3 tools/dstack_image.py <image directory>... <quote.hex>... [--memory 2G]

Several image directories may be given: each quote must then equal one of them on all three
registers. An image directory is the content of a dstack release archive (`metadata.json`, `ovmf.fd`,
`bzImage`, `initramfs.cpio.gz`, `sha256sum.txt`). The script checks the files against
`sha256sum.txt`, prints the OS image hash (the SHA-256 of `sha256sum.txt`, which a dstack
machine writes into its RTMR3 event log as `os-image-hash`), then for each quote whether MRTD,
RTMR1 and RTMR2 equal the values computed from the image. RTMR1 depends on the memory of the virtual
machine (the kernel is told where the initrd was loaded): without --memory, the script tries
common sizes and reports the one that matches.

RTMR0 is not computed: it covers the ACPI tables that QEMU generates for the machine, which
only QEMU itself can produce. Written from dstack's own measurement tool (`dstack-mr`, in
Dstack-TEE/dstack), without running it: the same computation, written a second time.
"""

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

PAGE = 0x1000
CHUNK = 0x100
MR_EXTEND = 0x1
PAGE_AUG = 0x2


def sha384(data):
    return hashlib.sha384(data).digest()


def replay(digests):
    register = bytes(48)
    for digest in digests:
        register = sha384(register + digest)
    return register


def guid_bytes(text):
    parts = text.split("-")
    raw = [bytes.fromhex(p) for p in parts]
    return raw[0][::-1] + raw[1][::-1] + raw[2][::-1] + raw[3] + raw[4]


def tdvf_sections(fw):
    """The TDVF metadata of the firmware: where each section lies, and how it is measured."""
    end = len(fw) - 32
    if fw[end - 16:end] != guid_bytes("96b582de-1fb2-45f7-baea-a366c55a082d"):
        sys.exit("firmware: no GUID table footer")
    tables_len = struct.unpack_from("<H", fw, end - 18)[0]
    tables = fw[end - 18 - tables_len:end - 18]
    offset, data = len(tables), None
    wanted = guid_bytes("e47a6535-984a-4798-865e-4685a7bf8ec2")
    while offset >= 18:
        entry_len = struct.unpack_from("<H", tables, offset - 18)[0]
        if tables[offset - 16:offset] == wanted:
            data = tables[offset - 18 - entry_len:offset - 18]
            break
        offset -= entry_len
    if data is None:
        sys.exit("firmware: no TDVF metadata")
    meta = len(fw) - struct.unpack_from("<I", data, len(data) - 4)[0]
    signature, _, version, count = struct.unpack_from("<4sIII", fw, meta)
    if signature != b"TDVF" or version != 1:
        sys.exit("firmware: bad TDVF descriptor")
    sections = []
    for i in range(count):
        data_offset, raw_size, address, memory_size, kind, attributes = struct.unpack_from(
            "<IIQQII", fw, meta + 16 + 32 * i)
        if address % PAGE or memory_size % PAGE or memory_size < raw_size:
            sys.exit("firmware: misaligned TDVF section")
        sections.append((data_offset, address, memory_size, attributes))
    return sections


def mrtd(fw, two_pass=False):
    """What the TDX module measures while the firmware pages are added to the TD."""
    h = hashlib.sha384()

    def add(address, attributes, page):
        if not attributes & PAGE_AUG:
            h.update(b"MEM.PAGE.ADD".ljust(16, b"\0") + struct.pack("<Q", address + page * PAGE) + bytes(104))

    def extend(data_offset, address, attributes, page):
        if attributes & MR_EXTEND:
            for i in range(PAGE // CHUNK):
                gpa = address + page * PAGE + i * CHUNK
                h.update(b"MR.EXTEND".ljust(16, b"\0") + struct.pack("<Q", gpa) + bytes(104))
                start = data_offset + page * PAGE + i * CHUNK
                h.update(fw[start:start + CHUNK])

    for data_offset, address, memory_size, attributes in tdvf_sections(fw):
        pages = memory_size // PAGE
        if two_pass:
            for p in range(pages):
                add(address, attributes, p)
            for p in range(pages):
                extend(data_offset, address, attributes, p)
        else:
            for p in range(pages):
                add(address, attributes, p)
                extend(data_offset, address, attributes, p)
    return h.digest()


def patch_kernel(kernel, initrd_size, memory, acpi_size=0x28000):
    """The setup header that QEMU writes into the kernel before the firmware measures it."""
    k = bytearray(kernel)
    protocol = struct.unpack_from("<H", k, 0x206)[0]
    real, cmdline = (0x90000, 0x9A000) if protocol < 0x200 or not k[0x211] & 1 else (0x10000, 0x20000)
    if protocol >= 0x200:
        k[0x210] = 0xB0
    if protocol >= 0x201:
        k[0x211] |= 0x80
        struct.pack_into("<I", k, 0x224, max(cmdline - real - 0x200, 0))
    if protocol >= 0x202:
        struct.pack_into("<I", k, 0x228, cmdline)
    else:
        struct.pack_into("<HH", k, 0x20, 0xA33F, cmdline - real)
    if initrd_size:
        if protocol >= 0x20C:
            initrd_max = 0xFFFFFFFF if struct.unpack_from("<H", k, 0x236)[0] & 0x40 else 0x37FFFFFF
        elif protocol >= 0x203:
            initrd_max = struct.unpack_from("<I", k, 0x22C)[0] or 0x37FFFFFF
        else:
            initrd_max = 0x37FFFFFF
        lowmem = 0xB0000000 if memory < 0xB0000000 else 0x80000000
        below_4g = lowmem if memory >= lowmem else memory
        if initrd_max >= below_4g - acpi_size:
            initrd_max = below_4g - acpi_size - 1
        struct.pack_into("<II", k, 0x218, (initrd_max - initrd_size) & ~4095, initrd_size)
    return bytes(k)


def authenticode_sha384(pe):
    """The hash of a PE image as the firmware measures it before running it."""
    lfanew = struct.unpack_from("<I", pe, 0x3C)[0]
    if pe[lfanew:lfanew + 4] != b"PE\0\0":
        sys.exit("kernel: not a PE image")
    coff = lfanew + 4
    sections_count = struct.unpack_from("<H", pe, coff + 2)[0]
    optional_size = struct.unpack_from("<H", pe, coff + 16)[0]
    optional = coff + 20
    plus = struct.unpack_from("<H", pe, optional)[0] == 0x20B
    checksum = optional + 64
    cert_dir = optional + (112 if plus else 96) + 4 * 8
    headers_size = struct.unpack_from("<I", pe, optional + 60)[0]
    h = hashlib.sha384()
    h.update(pe[:checksum])
    h.update(pe[checksum + 4:cert_dir])
    h.update(pe[cert_dir + 8:headers_size])
    hashed = headers_size
    table = optional + optional_size
    sections = []
    for i in range(sections_count):
        size, pointer = struct.unpack_from("<II", pe, table + 40 * i + 16)
        if size:
            sections.append((pointer, size))
    for pointer, size in sorted(sections):
        h.update(pe[pointer:pointer + size])
        hashed += size
    cert_addr, cert_size = struct.unpack_from("<II", pe, cert_dir)
    if cert_addr and cert_size and len(pe) > hashed and len(pe) - hashed > cert_size:
        h.update(pe[hashed:hashed + len(pe) - hashed - cert_size])
    if len(pe) % 8:
        h.update(bytes(8 - len(pe) % 8))
    return h.digest()


def rtmr1(kernel, initrd_size, memory):
    return replay([
        authenticode_sha384(patch_kernel(kernel, initrd_size, memory)),
        sha384(b"Calling EFI Application from Boot Option"),
        sha384(bytes(4)),
        sha384(b"Exit Boot Services Invocation"),
        sha384(b"Exit Boot Services Returned with Success"),
    ])


def rtmr2(cmdline, initrd):
    return replay([sha384((cmdline + " initrd=initrd").encode("utf-16-le") + b"\0\0"), sha384(initrd)])


def quote_registers(quote):
    """MRTD and RTMR0 to RTMR3 of a version 4 TDX quote."""
    body = 48
    mrtd_at = body + 16 + 48 + 48 + 8 + 8 + 8
    rtmr_at = mrtd_at + 4 * 48
    return {"mrtd": quote[mrtd_at:mrtd_at + 48],
            **{f"rtmr{i}": quote[rtmr_at + 48 * i:rtmr_at + 48 * (i + 1)] for i in range(4)}}


def size(text):
    units = {"G": 1 << 30, "M": 1 << 20}
    return int(text[:-1]) * units[text[-1]] if text[-1] in units else int(text, 0)


def load(image, sizes):
    listing = (image / "sha256sum.txt").read_bytes()
    for line in listing.decode().splitlines():
        digest, name = line.split()
        if hashlib.sha256((image / name).read_bytes()).hexdigest() != digest:
            sys.exit(f"{image}: {name} does not match sha256sum.txt")
    meta = json.loads((image / "metadata.json").read_text())
    fw = (image / meta["bios"]).read_bytes()
    kernel = (image / meta["kernel"]).read_bytes()
    initrd = (image / meta["initrd"]).read_bytes()
    # QEMU adds the firmware pages to the TD in one pass or in two (all pages, then their
    # content), depending on its version: both are computed, and the quote says which was used.
    orders = {"one pass": mrtd(fw), "two passes": mrtd(fw, two_pass=True)}
    found = {"version": meta.get("version"), "orders": orders, "rtmr2": rtmr2(meta["cmdline"], initrd),
             "rtmr1": {m: rtmr1(kernel, len(initrd), m) for m in sizes}}
    print(f"image {meta.get('version')} ({meta.get('git_revision', '')[:7]}), dev: {meta.get('is_dev')}")
    print(f"  OS image hash {hashlib.sha256(listing).hexdigest()}")
    for order, value in orders.items():
        print(f"  MRTD  {value.hex()} (pages added in {order})")
    print(f"  RTMR2 {found['rtmr2'].hex()}")
    return found


def compare(image, got):
    order = next((o for o, v in image["orders"].items() if v == got["mrtd"]), None)
    memory = next((m for m, v in image["rtmr1"].items() if v == got["rtmr1"]), None)
    checks = {"MRTD": order is not None, "RTMR1": memory is not None, "RTMR2": got["rtmr2"] == image["rtmr2"]}
    notes = ([f"pages added in {order}"] if order else []) + ([f"memory {memory >> 20} MiB"] if memory else [])
    return checks, notes


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="image directories and quote files, in any order")
    parser.add_argument("--memory", type=size)
    args = parser.parse_args()
    sizes = [args.memory] if args.memory else [size(s) for s in
                                               ("1G", "2G", "3G", "4G", "6G", "8G", "12G", "16G", "32G")]
    images = [load(Path(p), sizes) for p in args.paths if Path(p).is_dir()]
    quotes = [p for p in args.paths if not Path(p).is_dir()]
    if not images or not quotes:
        sys.exit("give at least one image directory and one quote")

    failures = 0
    for path in quotes:
        quote = bytes.fromhex(Path(path).read_text().strip().removeprefix("0x"))
        got = quote_registers(quote)
        results = [(image, *compare(image, got)) for image in images]
        # A quote must equal one of the images on all three registers; otherwise the closest is shown.
        image, checks, notes = max(results, key=lambda r: sum(r[1].values()))
        failures += not all(checks.values())
        detail = ", ".join(f"{k} {'equal' if v else 'DIFFERENT'}" for k, v in checks.items())
        print(f"{path}: image {image['version']}: {detail}" + (f" ({', '.join(notes)})" if notes else ""))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
