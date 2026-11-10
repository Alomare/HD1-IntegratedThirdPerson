"""Builds the sky Integrated Third Person ships, in res/: one sky per planet type and one for the night, on
the dome the game's engine keeps for the editor, and the render config with the clear pass fixed.

Adapted from Photo Mode's tools/build_sky.py (same dome, same texture format, same render config).

Usage: python -I tools/build_sky.py [path to Helldivers/contents] [path to Photo Mode]

The dome is core/editor_slave/units/skydome/skydome, in the ship's package: a hemisphere 500 m across
whose one material tiles one texture, with an `intensity`. Each sky is a copy of that unit whose only
change is the name of the material (itp/sky/<name>), and a copy of that material whose only change is
the name of the texture (itp/sky/<name>_map). The unit and the material come from the game's contents;
without them, from Photo Mode's res/sky_day.unit and .material, which are the same copies under Photo
Mode's names. The textures are drawn here: soft clouds over the colour of the planet type's fog, so the
sky meets the fog at the horizon. The mod sets the dome's intensity from the planet's fog at run time.

The render config is Photo Mode's res/render_config.bin, copied byte for byte: two mods that ship the
same bytes for one resource don't conflict in Obsidian.

Only the standard library. Writes res/sky_<name>.unit, .material and .texture and res/render_config.bin.
"""
import hashlib
import math
import random
import shutil
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "res"
CONTENTS = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Program Files (x86)\Steam\steamapps\common\Helldivers\contents")
PHOTO_MODE = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT.parent / "PhotoMode"

DOME = "core/editor_slave/units/skydome/skydome"
SHIP_BUNDLE = "ec181385e7000cf1"      # resource_packages/menu
SIZE = 256

# The fog colour of each planet type (0 to 1), as Third Person Camera measured them, and the night.
SKIES = {
    "desert": (0.62, 0.60, 0.55),
    "forest": (0.46, 0.58, 0.66),
    "snow": (0.66, 0.72, 0.80),
    "lava": (0.70, 0.34, 0.20),
    "city": (0.52, 0.55, 0.58),
    "night": (0.10, 0.13, 0.22),
}


def murmur64(data, seed=0):
    m, r, mask = 0xc6a4a7935bd1e995, 47, (1 << 64) - 1
    h = (seed ^ (len(data) * m)) & mask
    tail = len(data) & ~7
    for (k,) in struct.iter_unpack("<Q", data[:tail]):
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    rest = data[tail:]
    if rest:
        h = ((h ^ int.from_bytes(rest, "little")) * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    return h ^ (h >> r)


def bundle_entries(path):
    """A bundle's resources: (type, name, data of the first variant)."""
    data = path.read_bytes()
    if len(data) < 12 or struct.unpack_from("<I", data, 0)[0] != 0xF0000004:
        return
    total = struct.unpack_from("<I", data, 4)[0]
    raw, pos = bytearray(), 12
    while pos < len(data) and len(raw) < total:
        (size,) = struct.unpack_from("<I", data, pos)
        pos += 4
        chunk = data[pos:pos + size]
        pos += size
        raw += chunk if size == 0x10000 else zlib.decompress(chunk)
    (count,) = struct.unpack_from("<I", raw, 0)
    pos = 260 + count * 16
    for _ in range(count):
        kind, name, variants, _ = struct.unpack_from("<QQII", raw, pos)
        pos += 24
        heads = [struct.unpack_from("<III", raw, pos + 12 * i) for i in range(variants)]
        pos += 12 * variants
        first = None
        for _, size, _ in heads:
            if first is None:
                first = bytes(raw[pos:pos + size])
            pos += size
        yield kind, name, first


def find(bundle, kind, name_hash):
    for k, n, data in bundle_entries(CONTENTS / bundle):
        if k == murmur64(kind.encode()) and n == name_hash:
            return data
    raise SystemExit(f"no {kind} {name_hash:016x} in {bundle}")


def replace_u64(data, old, new, expect=1):
    out, found, i = bytearray(data), 0, 0
    old_b, new_b = struct.pack("<Q", old), struct.pack("<Q", new)
    while True:
        i = out.find(old_b, i)
        if i < 0:
            break
        out[i:i + 8] = new_b
        found += 1
        i += 8
    if found != expect:
        raise SystemExit(f"expected {expect} of {old:016x}, found {found}")
    return bytes(out)


def dome():
    """The dome unit and material, under the dome's name, and the hash of the material's texture."""
    if (CONTENTS / SHIP_BUNDLE).exists():
        h = murmur64(DOME.encode())
        unit, material = find(SHIP_BUNDLE, "unit", h), find(SHIP_BUNDLE, "material", h)
        return unit, material, h, struct.unpack_from("<Q", material, 32)[0]
    # Photo Mode's day sky: the dome renamed photomode/sky/day, texture photomode/sky/day_map.
    unit = (PHOTO_MODE / "res" / "sky_day.unit").read_bytes()
    material = (PHOTO_MODE / "res" / "sky_day.material").read_bytes()
    return unit, material, murmur64(b"photomode/sky/day"), murmur64(b"photomode/sky/day_map")


# Drawing: value noise that tiles, summed over octaves.
def noise(rng, cells, size):
    lattice = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = [[0.0] * size for _ in range(size)]
    step = cells / size
    for y in range(size):
        fy = y * step
        y0 = int(fy) % cells
        y1 = (y0 + 1) % cells
        ty = fy - int(fy)
        ty = ty * ty * (3 - 2 * ty)
        row0, row1, line = lattice[y0], lattice[y1], out[y]
        for x in range(size):
            fx = x * step
            x0 = int(fx) % cells
            x1 = (x0 + 1) % cells
            tx = fx - int(fx)
            tx = tx * tx * (3 - 2 * tx)
            a = row0[x0] + (row0[x1] - row0[x0]) * tx
            b = row1[x0] + (row1[x1] - row1[x0]) * tx
            line[x] = a + (b - a) * ty
    return out


def fbm(seed, size, base=4, octaves=5):
    rng = random.Random(seed)
    total = [[0.0] * size for _ in range(size)]
    weight, norm = 1.0, 0.0
    for o in range(octaves):
        layer = noise(rng, base * 2 ** o, size)
        for y in range(size):
            t, l = total[y], layer[y]
            for x in range(size):
                t[x] += l[x] * weight
        norm += weight
        weight *= 0.5
    return [[v / norm for v in row] for row in total]


def draw(name, seed):
    """RGB rows: the fog colour, with lighter clouds over a share of it, and stars at night."""
    fog = [c * 255 for c in SKIES[name]]
    night = name == "night"
    cloud = [min(255, c * (1.25 if night else 1.35) + (12 if night else 30)) for c in fog]
    shade = [c * 0.82 for c in fog]
    field = fbm(seed, SIZE)
    flat = sorted(v for row in field for v in row)
    cover = 0.3 if night else 0.45
    edge = flat[int(len(flat) * (1 - cover))]
    top = flat[min(len(flat) - 1, int(len(flat) * (1 - cover + 0.25)))]
    rng = random.Random(seed + 1)
    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            v = field[y][x]
            d = min(1.0, max(0.0, (v - edge) / max(1e-6, top - edge)))
            d = d * d * (3 - 2 * d)
            lit = min(1.0, max(0.0, (v - edge) * 4))
            c = [fog[i] * (1 - d) + (shade[i] * (1 - lit) + cloud[i] * lit) * d for i in range(3)]
            if night and d < 0.3 and rng.random() < 0.012:
                star = 90 + 165 * rng.random() ** 3
                c = [max(c[i], star * (0.9, 0.95, 1.0)[i]) for i in range(3)]
            row += bytes(int(min(255, max(0, round(v2)))) for v2 in c)
        rows.append(bytes(row))
    return rows


def texture(rows):
    """Uncompressed BGRA with every mip, and the four-byte category every texture resource ends with."""
    mips = [[[tuple(r[x * 3:x * 3 + 3]) for x in range(SIZE)] for r in rows]]
    while len(mips[-1]) > 1:
        prev = mips[-1]
        half = len(prev) // 2
        mips.append([[tuple((prev[2 * y][2 * x][i] + prev[2 * y][2 * x + 1][i] + prev[2 * y + 1][2 * x][i]
                             + prev[2 * y + 1][2 * x + 1][i] + 2) // 4 for i in range(3))
                      for x in range(half)] for y in range(half)])
    header = bytearray(128)
    header[:4] = b"DDS "
    struct.pack_into("<IIIIIII", header, 4, 124, 0x0002100F, SIZE, SIZE, SIZE * 4, 0, len(mips))
    header[60:64], header[68:72] = b"UVER", b"NVTT"
    struct.pack_into("<I", header, 72, 0x00020100)
    struct.pack_into("<IIIIIIII", header, 76, 32, 0x41, 0, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    struct.pack_into("<I", header, 108, 0x00401008)
    body = bytearray()
    for mip in mips:
        for row in mip:
            for r, g, b in row:
                body += bytes((b, g, r, 255))
    return bytes(header) + bytes(body) + bytes(4)


def main():
    RES.mkdir(exist_ok=True)
    unit, material, unit_name, texture_name = dome()
    for i, name in enumerate(SKIES):
        base = f"itp/sky/{name}"
        (RES / f"sky_{name}.texture").write_bytes(texture(draw(name, 101 + i * 17)))
        (RES / f"sky_{name}.material").write_bytes(replace_u64(material, texture_name, murmur64((base + "_map").encode())))
        (RES / f"sky_{name}.unit").write_bytes(replace_u64(unit, unit_name, murmur64(base.encode())))
        print("sky", name)
    source = PHOTO_MODE / "res" / "render_config.bin"
    shutil.copyfile(source, RES / "render_config.bin")
    a, b = (hashlib.sha256(p.read_bytes()).hexdigest() for p in (source, RES / "render_config.bin"))
    if a != b:
        raise SystemExit("the render config differs from Photo Mode's")
    print("render config: Photo Mode's bytes", a[:12])


if __name__ == "__main__":
    main()
