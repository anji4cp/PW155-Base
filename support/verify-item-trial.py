#!/usr/bin/env python3
"""Read-only inspection of a role's pocket after a material mail trial."""

import argparse
import struct

from sync_characters import Reader, request


GET_ROLE_POCKET = 3053


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--role-id", type=int, default=1024)
    parser.add_argument("--item-id", type=int, default=21652)
    args = parser.parse_args()
    if not 0 < args.role_id <= 0x7FFFFFFF or not 0 < args.item_id <= 0x7FFFFFFF:
        parser.error("role and item IDs must be positive")
    opcode, payload = request(
        GET_ROLE_POCKET, struct.pack(">II", 0xFFFFFFFF, args.role_id)
    )
    if opcode != GET_ROLE_POCKET:
        raise RuntimeError(f"Unexpected opcode {opcode}")
    reader = Reader(payload)
    reader.u32()  # RPC handle
    retcode = reader.u32()
    if retcode:
        raise RuntimeError(f"GetRolePocket retcode={retcode}")
    capacity, timestamp, money = reader.u32(), reader.u32(), reader.u32()
    slots = reader.cuint()
    if capacity > 1000 or slots > 1000:
        raise RuntimeError("Implausible pocket size")
    matches = []
    for _ in range(slots):
        item_id, pos, count, max_count = (
            reader.u32(), reader.u32(), reader.u32(), reader.u32()
        )
        data = reader.octets()
        proctype, expire_date, guid1, guid2, mask = (reader.u32() for _ in range(5))
        if item_id == args.item_id:
            matches.append({
                "id": item_id, "pos": pos, "count": count,
                "max_count": max_count, "data_bytes": len(data),
                "proctype": proctype, "expire_date": expire_date,
                "guid1": guid1, "guid2": guid2, "mask": mask,
            })
    reader.u32()  # reserved1
    reader.u32()  # reserved2
    if reader.offset != len(payload):
        raise RuntimeError("Pocket response has trailing data")
    print(f"role={args.role_id} capacity={capacity} slots={slots} "
          f"item={args.item_id} matches={matches}")


if __name__ == "__main__":
    main()
