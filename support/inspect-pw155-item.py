#!/usr/bin/env python3
"""Read-only lookup of item fields in a PW155 elements.data and matching UDE schema."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct


def field_size(field_type):
    if field_type in ("int32", "float"):
        return 4
    if field_type == "int64":
        return 8
    if ":" in field_type:
        kind, length = field_type.split(":", 1)
        if kind in ("string", "wstring") and length.isdecimal():
            return int(length)
    raise ValueError(f"Unsupported schema field type: {field_type}")


def inspect(elements_path, schema_path, item_ids, material_catalog=None):
    schema_lines = [line.strip() for line in schema_path.read_text(
        encoding="utf-8-sig").splitlines() if line.strip()]
    list_count, talk_list = map(int, schema_lines[:2])
    if len(schema_lines) != 2 + 4 * list_count:
        raise ValueError("Schema list count does not match contents")
    data = elements_path.read_bytes()
    if len(data) < 8:
        raise ValueError("elements.data header truncated")
    version = struct.unpack_from("<I", data, 0)[0] & 0xFFFF
    if f"_v{version}.cfg" not in schema_path.name:
        raise ValueError(f"Schema version does not match elements.data v{version}")
    offset = 8
    found = {}

    def take(length):
        nonlocal offset
        if length < 0 or length > len(data) - offset:
            raise ValueError(f"elements.data truncated at byte {offset}")
        start = offset
        offset += length
        return start

    def integer():
        return struct.unpack_from("<i", data, take(4))[0]

    for index in range(list_count):
        name, prefix, fields, types = schema_lines[2 + 4 * index:6 + 4 * index]
        if index == 0:
            take(int(prefix) - 4)
        elif prefix.isdecimal() and int(prefix):
            take(int(prefix))
        elif prefix == "AUTO":
            integer()  # version/tag
            take(integer())
            candidate = struct.unpack_from("<i", data, offset)[0]
            if not 0 <= candidate < 100000:
                take(4)  # some PW155 v156 AUTO sections include a trailing marker
        count = integer()
        if os.environ.get("PW155_ITEM_DEBUG"):
            print(index, name, "offset", offset - 4, "count", count)
        if not 0 <= count < 1000000:
            raise ValueError(f"Implausible row count in {name} at {offset - 4}: {count}")
        if index == talk_list:
            for _ in range(count):
                take(132)
                windows = integer()
                if not 0 <= windows <= 100000:
                    raise ValueError("Implausible talk window count")
                for _ in range(windows):
                    take(8)
                    take(integer() * 2)
                    take(integer() * 136)
            continue
        field_names = fields.split(";")
        field_types = types.split(";")
        if len(field_names) != len(field_types):
            raise ValueError(f"Schema fields and types differ in {name}")
        sizes = [field_size(field_type) for field_type in field_types]
        stride = sum(sizes)
        row_start = take(count * stride)
        field_offsets = {}
        at = 0
        for field_name, size in zip(field_names, sizes):
            field_offsets[field_name.lower()] = at
            at += size
        id_offset = field_offsets.get("id")
        if id_offset is None:
            continue
        for row in range(count):
            at = row_start + row * stride
            item_id = struct.unpack_from("<i", data, at + id_offset)[0]
            if material_catalog is not None and name == "016 - MATERIAL_ESSENCE":
                max_count = struct.unpack_from(
                    "<i", data, at + field_offsets["pile_num_max"]
                )[0]
                proctype = struct.unpack_from(
                    "<i", data, at + field_offsets["proc_type"]
                )[0]
                if item_id <= 0 or item_id in material_catalog:
                    raise ValueError(f"Invalid or duplicate material ID {item_id}")
                # Initial panel scope: ordinary materials only. Bound/restricted
                # proctype flags need their own in-game claim tests.
                if 1 <= max_count <= 32767 and proctype == 0:
                    material_catalog[item_id] = {
                        "max_count": max_count, "proctype": proctype,
                    }
            if item_id not in item_ids:
                continue
            entry = {"id": item_id, "list": name, "row": row}
            for field_name in ("pile_num_max", "proc_type"):
                field_offset = field_offsets.get(field_name)
                if field_offset is not None:
                    entry[field_name] = struct.unpack_from("<i", data, at + field_offset)[0]
            found.setdefault(item_id, []).append(entry)
    if offset != len(data):
        raise ValueError(f"Schema did not consume elements.data: {offset}/{len(data)}")
    return version, found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elements", type=Path)
    parser.add_argument("schema", type=Path)
    parser.add_argument("item_id", type=int, nargs="*")
    parser.add_argument("--catalog", action="store_true",
                        help="Print verified MATERIAL_ESSENCE catalog as JSON")
    args = parser.parse_args()
    if not args.catalog and not args.item_id:
        parser.error("provide item ID(s) or --catalog")
    materials = {} if args.catalog else None
    version, found = inspect(args.elements, args.schema, set(args.item_id), materials)
    if args.catalog:
        digest = hashlib.sha256(args.elements.read_bytes()).hexdigest()
        print(json.dumps({
            "version": version, "category": "MATERIAL_ESSENCE",
            "elements_sha256": digest,
            "items": {str(key): materials[key] for key in sorted(materials)},
        }, ensure_ascii=False, separators=(",", ":")))
        return
    print(f"elements.data v{version} (read-only)")
    for item_id in args.item_id:
        print(f"{item_id}: {found.get(item_id, [])}")


if __name__ == "__main__":
    main()
