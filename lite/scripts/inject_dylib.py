#!/usr/bin/env python3
"""
Adds an LC_LOAD_DYLIB command to a Mach-O executable (thin or fat), in place.

usage: inject_dylib.py <binary> <install name, e.g. @executable_path/Frameworks/LCPlus.dylib>

The existing code signature command is removed (the app is re-signed on install anyway) and the new command is
appended to the load commands, which needs free header padding, as every iOS binary links with enough of it.
"""
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC, FAT_MAGIC_64 = 0xCAFEBABE, 0xCAFEBABF
LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D
LC_LOAD_DYLIB = 0xC
DYLIB_CMDS = {0xC, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x20}  # load, weak, reexport, lazy load
HEADER_SIZE = 32


class InjectError(Exception):
    pass


def _commands(buf, base):
    magic, _cpu, _sub, _ftype, ncmds, sizeofcmds, _flags, _res = struct.unpack_from("<8I", buf, base)
    if magic != MH_MAGIC_64:
        raise InjectError("only 64-bit little-endian Mach-O slices are supported (magic %#x)" % magic)
    pos = base + HEADER_SIZE
    cmds = []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", buf, pos)
        if size < 8:
            raise InjectError("corrupt load command")
        cmds.append((pos, cmd, size))
        pos += size
    return ncmds, sizeofcmds, cmds


def inject_slice(buf, base, install_name):
    ncmds, sizeofcmds, cmds = _commands(buf, base)
    name_bytes = install_name.encode() + b"\0"
    new_size = (24 + len(name_bytes) + 7) & ~7

    first_section = None
    for pos, cmd, size in cmds:
        if cmd in DYLIB_CMDS:
            name_off = struct.unpack_from("<I", buf, pos + 8)[0]
            existing = bytes(buf[pos + name_off:pos + size]).split(b"\0")[0]
            if existing == install_name.encode():
                return "already present"
        if cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from("<I", buf, pos + 64)[0]
            for i in range(nsects):
                sec = pos + 72 + 80 * i
                size_, offset = struct.unpack_from("<QI", buf, sec + 40)
                if size_ and offset:
                    first_section = offset if first_section is None else min(first_section, offset)
    limit = base + first_section if first_section else None
    end = base + HEADER_SIZE + sizeofcmds

    # drop the old code signature command (it is invalid after the change and the app is re-signed anyway)
    for pos, cmd, size in cmds:
        if cmd == LC_CODE_SIGNATURE:
            tail = bytes(buf[pos + size:end])
            buf[pos:pos + len(tail)] = tail
            buf[pos + len(tail):end] = b"\0" * size
            ncmds -= 1
            sizeofcmds -= size
            end -= size
            break

    if limit is not None and end + new_size > limit:
        raise InjectError("not enough free space after the load commands (%d bytes needed, %d available)"
                          % (new_size, limit - end))
    struct.pack_into("<6I", buf, end, LC_LOAD_DYLIB, new_size, 24, 2, 0x10000, 0x10000)
    buf[end + 24:end + 24 + len(name_bytes)] = name_bytes
    buf[end + 24 + len(name_bytes):end + new_size] = b"\0" * (new_size - 24 - len(name_bytes))
    struct.pack_into("<II", buf, base + 16, ncmds + 1, sizeofcmds + new_size)
    return "added"


def inject(path, install_name):
    with open(path, "rb") as f:
        buf = bytearray(f.read())
    magic_be = struct.unpack_from(">I", buf, 0)[0]
    results = []
    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        narch = struct.unpack_from(">I", buf, 4)[0]
        for i in range(narch):
            if magic_be == FAT_MAGIC:
                cpu, sub, off, size, align = struct.unpack_from(">5I", buf, 8 + 20 * i)
            else:
                cpu, sub, off, size, align, _ = struct.unpack_from(">IIQQII", buf, 8 + 32 * i)
            results.append((cpu, inject_slice(buf, off, install_name)))
    else:
        results.append((struct.unpack_from("<I", buf, 4)[0], inject_slice(buf, 0, install_name)))
    with open(path, "wb") as f:
        f.write(buf)
    return results


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    try:
        for cpu, status in inject(sys.argv[1], sys.argv[2]):
            print("slice cputype %#x: %s" % (cpu, status))
    except InjectError as e:
        sys.exit("error: %s" % e)


if __name__ == "__main__":
    main()
