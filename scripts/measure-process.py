#!/usr/bin/env python3
"""Measure only an explicitly selected COREType process on macOS.

Uses monotonic elapsed time and proc_pid_rusage cumulative CPU nanoseconds;
100 percent means one fully occupied logical core. WebKit helpers are excluded
because generic process listings cannot attribute them safely to this app.
Sampling/profiling runs should be separate from these steady-state windows.
"""

import argparse
import ctypes
import json
import os
from pathlib import Path
import statistics
import sys
import time


class RUsageInfoV0(ctypes.Structure):
    # Public macOS SDK sys/resource.h RUSAGE_INFO_V0 layout.
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [
        (name, ctypes.c_uint64)
        for name in (
            "user_time", "system_time", "pkg_idle_wakeups", "interrupt_wakeups",
            "pageins", "wired_size", "resident_size", "physical_footprint",
            "process_start", "process_exit",
        )
    ]


def measure(pid, seconds, runs, warmup, scenario):
    if sys.platform != "darwin":
        raise RuntimeError("This helper requires macOS proc_pid_rusage.")
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    libproc.proc_pidpath.restype = ctypes.c_int
    libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    libproc.proc_pid_rusage.restype = ctypes.c_int
    executable = ctypes.create_string_buffer(4096)
    if libproc.proc_pidpath(pid, executable, len(executable)) <= 0:
        raise RuntimeError("The requested process is unavailable.")
    if Path(os.fsdecode(executable.value)).name != "COREType":
        raise RuntimeError("Refusing to measure a process other than COREType.")

    def snapshot():
        usage = RUsageInfoV0()
        if libproc.proc_pid_rusage(pid, 0, ctypes.byref(usage)) != 0:
            raise RuntimeError("COREType exited or its resource usage is unavailable.")
        return time.perf_counter_ns(), usage

    _, initial = snapshot()
    time.sleep(warmup)
    windows = []
    for run in range(1, runs + 1):
        started, before = snapshot()
        time.sleep(seconds)
        stopped, after = snapshot()
        if (before.process_start != initial.process_start or
                after.process_start != initial.process_start):
            raise RuntimeError("COREType restarted; discard these noncomparable windows.")
        elapsed = (stopped - started) / 1_000_000_000
        user = (after.user_time - before.user_time) / 1_000_000_000
        system = (after.system_time - before.system_time) / 1_000_000_000
        cpu = user + system
        window = {
            "run": run,
            "elapsed_seconds": elapsed,
            "user_cpu_seconds": user,
            "system_cpu_seconds": system,
            "cpu_seconds": cpu,
            "average_cpu_percent": 100 * cpu / elapsed,
            "package_idle_wakeups": after.pkg_idle_wakeups - before.pkg_idle_wakeups,
            "interrupt_wakeups": after.interrupt_wakeups - before.interrupt_wakeups,
            "resident_bytes_start": before.resident_size,
            "resident_bytes_end": after.resident_size,
            "physical_footprint_bytes_start": before.physical_footprint,
            "physical_footprint_bytes_end": after.physical_footprint,
        }
        windows.append(window)
        print(json.dumps({"scenario": scenario, **window}, sort_keys=True), flush=True)

    cpu_percent = [window["average_cpu_percent"] for window in windows]
    report = {
        "scenario": scenario,
        "method": "monotonic wall time and proc_pid_rusage RUSAGE_INFO_V0 cumulative CPU",
        "cpu_convention": "100 percent is one logical core",
        "process_scope": "explicit COREType main process only; WebKit helpers excluded",
        "warmup_seconds": warmup,
        "windows": windows,
        "median_cpu_percent": statistics.median(cpu_percent),
        "minimum_cpu_percent": min(cpu_percent),
        "maximum_cpu_percent": max(cpu_percent),
    }
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", required=True, type=int, help="Explicit COREType PID")
    parser.add_argument("--scenario", required=True, help="Scenario recorded by the operator")
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--warmup", type=float, default=5)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.pid <= 0 or args.seconds <= 0 or args.runs <= 0 or args.warmup < 0:
        parser.error("PID, window duration and runs must be positive; warm-up cannot be negative.")
    try:
        report = measure(args.pid, args.seconds, args.runs, args.warmup, args.scenario)
    except (OSError, RuntimeError) as error:
        parser.exit(1, str(error) + "\n")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "windows"}, sort_keys=True))


if __name__ == "__main__":
    main()
