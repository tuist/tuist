#!/usr/bin/env python3
"""Reduces a full run's TestCoverageAttribution output and Xcode's per-process profiles to the
shape of golden.json's baseline_evidence, the way TestCoverageEvidenceService does: record
counters -> functions -> files; launches -> the app process's covered files; target rows =
whole-process files minus test and suite scopes.

usage: evidence.py <tca-dir> <derived-data> <repo>
"""
import glob, hashlib, json, os, struct, subprocess, sys, zlib
from collections import defaultdict

tca, dd, root = sys.argv[1], sys.argv[2], os.path.realpath(sys.argv[3])
golden = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "golden.json")))
test_targets = list(golden["test_targets"])
profile_dir = glob.glob(os.path.join(dd, "Build/ProfileData/*"))[0]
products = glob.glob(os.path.join(dd, "Build/Products/Debug-iphonesimulator"))[0]
profdata = os.path.join(profile_dir, "Coverage.profdata")


def rel(path):
    path = os.path.realpath(path) if os.path.exists(path) else path
    for prefix in (root + "/", "/private" + root + "/"):
        if path.startswith(prefix):
            return path[len(prefix):]
    return None


def lcov(image, profile):
    out = subprocess.run(["xcrun", "llvm-cov", "export", "-format=lcov", "-instr-profile", profile, image],
                         capture_output=True, text=True)
    files, functions, sf = {}, defaultdict(set), None
    for line in out.stdout.splitlines():
        if line.startswith("SF:"):
            sf = line[3:]
            files.setdefault(sf, False)
        elif line.startswith("DA:"):
            if int(line[3:].split(",")[1]) > 0:
                files[sf] = True
        elif line.startswith("FN:"):
            functions[line[3:].split(",")[-1]].add(sf)
    return files, functions


def covered(image, profraw):
    merged = profraw + ".profdata"
    if not os.path.exists(merged):
        subprocess.run(["xcrun", "llvm-profdata", "merge", "-o", merged, profraw], check=True)
    files, _ = lcov(image, merged)
    return {r for f, hit in files.items() if hit and (r := rel(f))}


def names(data):
    out, o = [], 0
    def uleb():
        nonlocal o
        v = s = 0
        while True:
            b = data[o]; o += 1
            v |= (b & 0x7F) << s; s += 7
            if b < 0x80:
                return v
    while o < len(data):
        u, c = uleb(), uleb()
        chunk = zlib.decompress(data[o:o + c]) if c else data[o:o + u]
        o += c or u
        out += [n.decode() for n in chunk.split(b"\x01") if n]
    return out


def counter_functions(data, data_addr, cnts_addr, cnts_size):
    total = cnts_size // 8
    for size, count_off in [(64, 48), (56, 40), (48, 40)]:
        if not data or len(data) % size:
            continue
        for relative in (True, False):
            res, claimed, ok = [], 0, True
            for i in range(len(data) // size):
                off = i * size
                ref, = struct.unpack_from("<Q", data, off)
                ptr, = struct.unpack_from("<q", data, off + 16)
                n, = struct.unpack_from("<I", data, off + count_off)
                if n == 0 and ptr == 0:
                    continue
                addr = data_addr + off + ptr if relative else ptr
                d = addr - cnts_addr
                if d < 0 or d % 8 or d // 8 + n > total:
                    ok = False; break
                res.append((ref, d // 8, n)); claimed += n
            if ok and claimed and claimed * 2 >= total:
                return res
    return []


def md5ref(name):
    return struct.unpack("<Q", hashlib.md5(name.encode()).digest()[:8])[0]


def records(path):
    b, o, out = open(path, "rb").read(), 0, []
    def s():
        nonlocal o
        n, = struct.unpack_from("<I", b, o); o += 4
        v = b[o:o + n].decode(); o += n
        return v
    while o < len(b):
        kind, flags, _, _ = struct.unpack_from("<4B", b, o); o += 4
        module, suite, name = s(), s(), s()
        count, = struct.unpack_from("<I", b, o); o += 4
        moved = {}
        for _ in range(count):
            img, n = struct.unpack_from("<II", b, o); o += 8
            moved[img] = struct.unpack_from(f"<{n}I", b, o); o += 12 * n
        out.append((kind, flags, module, suite, name, moved))
    return out


def test_name(selector):
    # "-[Suite testName]" -> "testName"
    return selector.strip("-[]").split(" ")[-1]


tests, suites, targets, process_files = defaultdict(set), defaultdict(set), defaultdict(set), defaultdict(set)
overlapped = set()
app_images = [os.path.join(products, "App.app/App.debug.dylib"), os.path.join(products, "App.app/Frameworks/Catalog.framework/Catalog")]
pid_profiles = {os.path.basename(p).rsplit("-", 1)[-1][:-len(".profraw")]: p for p in glob.glob(os.path.join(profile_dir, "*.profraw"))}

for pid_dir in sorted(glob.glob(os.path.join(tca, "*"))):
    pid = os.path.basename(pid_dir)
    images, tables = {}, {}
    for line in open(os.path.join(pid_dir, "images.tsv")):
        idx, size, data_addr, cnts_addr, path = line.rstrip("\n").split("\t")
        idx = int(idx)
        if not os.path.exists(path) and "/Containers/Bundle/Application/" in path:
            # Parallel clones are deleted after the run; the installed app is a copy of the product.
            path = os.path.join(products, path.split("/Containers/Bundle/Application/", 1)[1].split("/", 1)[1])
        images[idx] = path
        data = open(os.path.join(pid_dir, f"{idx}.data"), "rb").read()
        nm = names(open(os.path.join(pid_dir, f"{idx}.names"), "rb").read())
        by_ref = {md5ref(n): n for n in nm}
        _, fn_files = lcov(path, profdata)
        table = [None] * (int(size) // 8)
        for ref, first, n in counter_functions(data, int(data_addr, 0), int(cnts_addr, 0), int(size)):
            files = {r for f in fn_files.get(by_ref.get(ref), ()) if (r := rel(f))}
            for c in range(first, first + n):
                table[c] = files
        tables[idx] = table
    modules = set()
    for kind, flags, module, suite, name, moved in records(os.path.join(pid_dir, "records.bin")):
        files = set()
        for img, idxs in moved.items():
            for c in idxs:
                files |= tables[img][c] or set()
        modules.add(module)
        if kind == 0:
            if suite:
                suites[f"{module}/{suite}"] |= files
        else:
            key = f"{module}/{suite}/{test_name(name) if kind == 1 else name}"
            if flags & 1:
                overlapped.add(key)
            else:
                tests[key] |= files
    # Whole-process files of the test process itself.
    if pid in pid_profiles:
        for img in images.values():
            for m in modules:
                process_files[m] |= covered(img, pid_profiles[pid])
    launches = os.path.join(pid_dir, "launches.tsv")
    if os.path.exists(launches):
        for line in open(launches):
            f = line.rstrip("\n").split("\t")
            if len(f) != 4 or f[0] not in pid_profiles:
                continue
            app_pid, module, suite, name = f
            files = set()
            for img in app_images:
                files |= covered(img, pid_profiles[app_pid])
            process_files[module] |= files
            if name:
                tests[f"{module}/{suite}/{test_name(name)}"] |= files
            elif suite:
                suites[f"{module}/{suite}"] |= files

for module, files in process_files.items():
    scoped = set()
    for k, v in list(tests.items()) + list(suites.items()):
        if k.split("/")[0] == module:
            scoped |= v
    targets[module] = files - scoped

if overlapped:
    sys.exit(f"Tests ran concurrently in one process, so their evidence can't be told apart: {sorted(overlapped)}")

json.dump({
    "tests": {k: sorted(v) for k, v in sorted(tests.items()) if v},
    "suites": {k: sorted(v) for k, v in sorted(suites.items()) if v},
    "targets": {t: sorted(targets.get(t, ())) for t in test_targets},
    "test_files": sorted({p for files in [*tests.values(), *suites.values(), *targets.values()]
                          for p in files if p.split("/")[0] in test_targets}),
}, sys.stdout, indent=1)
print()
