#!/usr/bin/env python3
"""Cross-check the Python CLI against TeaLogic.js.

The widget and the CLI implement the same caffeine model twice, in two
languages. That is a standing invitation for them to drift — Python's round()
is banker's rounding while JS Math.round is half-up. Every case below is
computed by BOTH implementations and compared; nothing here is a hand-written
expectation.

Run: python3 tests/test_parity.py   (needs node on PATH)
"""

import importlib.machinery
import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STRENGTHS = ["black", "green", "herbal", "decaf"]
SIZES = ["0.25", "0.5", "0.75", "1", "1.5"]
BASES = [47, 30, 60, 15, 100, 200, 10]
ROLLOVERS = [0, 4, 6, 12]

# Timestamps that straddle rollover boundaries, DST, month and year ends.
STAMPS = [
    "2026-08-26 15:30", "2026-08-27 01:30", "2026-08-27 03:59",
    "2026-08-27 04:00", "2026-08-27 00:00", "2026-01-01 02:15",
    "2025-12-31 23:59", "2026-03-08 02:30", "2026-11-01 01:30",
    "2026-02-28 23:00", "2026-03-01 03:00",
]


def load_cli():
    spec = importlib.util.spec_from_loader(
        "omarchy_tea",
        importlib.machinery.SourceFileLoader("omarchy_tea", str(ROOT / "bin" / "omarchy-tea")),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


JS_HARNESS = r"""
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "");
const Logic = {};
new Function("exports", src + "\n;Object.assign(exports, {caffeineMg, dayKey, formatCups, weekStartKey, timestampFor, addDays});")(Logic);

const input = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const out = {
  mg: input.mg.map(c => Logic.caffeineMg(c[0], c[1], c[2])),
  day: input.day.map(c => Logic.dayKey(c[0], c[1])),
  cups: input.cups.map(v => Logic.formatCups(v)),
  week: input.week.map(k => Logic.weekStartKey(k)),
};
process.stdout.write(JSON.stringify(out));
"""


def main() -> int:
    if not shutil.which("node"):
        print("SKIP: node not on PATH", file=sys.stderr)
        return 0

    cli = load_cli()
    import datetime as dt

    mg_cases = [[s, z, b] for s in STRENGTHS for z in SIZES for b in BASES]
    day_cases = []
    for stamp in STAMPS:
        ms = int(dt.datetime.strptime(stamp, "%Y-%m-%d %H:%M").timestamp() * 1000)
        for r in ROLLOVERS:
            day_cases.append([ms, r])
    # Every quarter-cup sum a real day can produce, plus the .x5 ties.
    cups_cases = [round(i * 0.25, 2) for i in range(0, 41)] + [2.25, 6.25, 0.75, 1.15, 3.35]
    week_cases = ["2026-08-26", "2026-08-24", "2026-08-30", "2026-01-01",
                  "2025-12-29", "2026-03-01", "2026-12-31"]

    payload = {"mg": mg_cases, "day": day_cases, "cups": cups_cases, "week": week_cases}
    tmp = ROOT / "tests" / ".parity-input.json"
    harness = ROOT / "tests" / ".parity-harness.js"
    tmp.write_text(json.dumps(payload))
    harness.write_text(JS_HARNESS)
    try:
        result = subprocess.run(
            ["node", str(harness), str(ROOT / "TeaLogic.js"), str(tmp)],
            capture_output=True, text=True, check=True)
        js = json.loads(result.stdout)
    finally:
        tmp.unlink(missing_ok=True)
        harness.unlink(missing_ok=True)

    failures = []

    for case, expected in zip(mg_cases, js["mg"]):
        got = cli.caffeine_mg(case[0], case[1], case[2])
        if got != expected:
            failures.append("caffeine_mg%s: python=%s js=%s" % (tuple(case), got, expected))

    for case, expected in zip(day_cases, js["day"]):
        got = cli.day_key(case[0], case[1])
        if got != expected:
            failures.append("day_key%s: python=%s js=%s" % (tuple(case), got, expected))

    for case, expected in zip(cups_cases, js["cups"]):
        got = cli.fmt_cups(case)
        if got != expected:
            failures.append("fmt_cups(%s): python=%s js=%s" % (case, got, expected))

    for case, expected in zip(week_cases, js["week"]):
        got = cli.week_start_key(case)
        if got != expected:
            failures.append("week_start_key(%s): python=%s js=%s" % (case, got, expected))

    total = len(mg_cases) + len(day_cases) + len(cups_cases) + len(week_cases)
    if failures:
        print("FAIL: %d of %d cases diverged\n" % (len(failures), total))
        for line in failures[:40]:
            print("  " + line)
        return 1

    print("OK: %d cases agree between bin/omarchy-tea and TeaLogic.js" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
