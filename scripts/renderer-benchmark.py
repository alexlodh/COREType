#!/usr/bin/env python3
"""Compile the actual baseline or optimized AppKit renderer in an isolated harness.

The temporary adapter only removes NSViewRepresentable.Context from the two
unused context parameters. Baseline counters mark existing operations without
changing rendering. No window, native UI input or user-profile IO is performed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--counter-output", type=Path)
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.seconds < 1 or args.runs < 1:
        parser.error("Window duration must be at least one second and runs must be positive.")
    root = args.source.resolve()
    helpers = Path(__file__).resolve().parent
    source_hashes = {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest()
        for name in ("Sources/COREType/TypingView.swift", "Sources/COREType/InlineTextbookView.swift",
                     "Sources/TypingCore/TypingEngine.swift")
    }
    typing = (root / "Sources/COREType/TypingView.swift").read_text()
    optimized = "func render(engine:" in typing
    adapted = typing.replace("struct TypingSurface: NSViewRepresentable", "@MainActor struct TypingSurface")
    adapted = adapted.replace("func makeNSView(context: Context)", "func benchmarkMakeNSView()")
    adapted = adapted.replace("func updateNSView(_ scroll: NSScrollView, context: Context)", "func benchmarkUpdateNSView(_ scroll: NSScrollView)")
    media = (root / "Sources/COREType/InlineTextbookView.swift").read_text()
    if not optimized:
        def instrument(source, counter, before, after):
            return source if f'PerformanceCounters.record("{counter}")' in source else source.replace(before, after)
        adapted = instrument(adapted, "surface.updates", "func benchmarkUpdateNSView(_ scroll: NSScrollView) {", "func benchmarkUpdateNSView(_ scroll: NSScrollView) {\n        PerformanceCounters.record(\"surface.updates\")")
        adapted = instrument(adapted, "text.fullRebuilds", "if signature != view.lastSignature {", "if signature != view.lastSignature {\n            PerformanceCounters.record(\"text.fullRebuilds\")")
        adapted = instrument(adapted, "document.fits", "guard viewport.width > 0 else { return }", "guard viewport.width > 0 else { return }\n        PerformanceCounters.record(\"document.fits\")")
        adapted = instrument(adapted, "text.fullLayouts", "            layout.ensureLayout(for: container)", "            PerformanceCounters.record(\"text.fullLayouts\")\n            layout.ensureLayout(for: container)")
        media = instrument(media, "web.creations", "        webView = InlineTextbookWebView(", "        PerformanceCounters.record(\"web.creations\")\n        webView = InlineTextbookWebView(")
        media = instrument(media, "media.htmlLoads", "        webView.loadHTMLString(", "        PerformanceCounters.record(\"media.htmlLoads\")\n        webView.loadHTMLString(")
        media = instrument(media, "media.heightQueries", "        let version = documentVersion", "        PerformanceCounters.record(\"media.heightQueries\")\n        let version = documentVersion")
    args.output = args.output.resolve(); args.output.parent.mkdir(parents=True, exist_ok=True)
    counter_output = (args.counter_output or args.output.with_suffix(".counters.json")).resolve()
    counter_output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="COREType-Renderer-", dir="/tmp") as temporary:
        directory = Path(temporary)
        (directory / "TypingView.swift").write_text(adapted)
        (directory / "InlineTextbookView.swift").write_text(media)
        build_output = subprocess.check_output(["bash", "scripts/swift-env.sh", "build", "-c", "release", "--show-bin-path"], cwd=root, text=True)
        binary_dir = Path(build_output.strip().splitlines()[-1])
        objects = sorted((binary_dir / "TypingCore.build").glob("*.o"))
        if not objects:
            raise SystemExit("Build the source tree in release configuration first.")
        command = ["xcrun", "swiftc", "-O", "-parse-as-library", "-module-cache-path", str(helpers.parent / ".build/renderer-modules"),
                   "-I", str(binary_dir / "Modules")]
        if optimized: command += ["-D", "OPTIMIZED"]
        command += [str(root / "Sources/COREType/Appearance.swift"), str(directory / "TypingView.swift"),
                    str(directory / "InlineTextbookView.swift"), str(helpers.parent / "Sources/COREType/PerformanceCounters.swift"),
                    str(helpers / "RendererBenchmark.swift")]
        command += [str(path) for path in objects] + ["-o", str(directory / "RendererBenchmark")]
        subprocess.run(command, check=True)
        command = [str(directory / "RendererBenchmark"), "--resources", str(root / "Sources/COREType/Resources"),
                   "--output", str(args.output), "--performance-report", str(counter_output),
                   "--seconds", str(args.seconds), "--runs", str(args.runs)]
        if args.check: command += ["--check"]
        subprocess.run(command, check=True)
    report = json.loads(args.output.read_text())
    report["build_variant"] = "optimized" if optimized else "baseline"
    report["renderer_compilation"] = "xcrun swiftc -O; release TypingCore objects"
    if not args.check:
        report["warmup_seconds_per_run"] = 2
        report["counter_scope"] = "all setup and active windows; CPU and latency exclude setup/warm-up"
    report["source_sha256"] = source_hashes
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
