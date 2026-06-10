#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

try:
    from openpyxl import Workbook
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(
        "openpyxl is required for workbook export.\n"
        "Install it in the Python environment used on Gadi, for example:\n"
        "  python3 -m pip install --user openpyxl\n"
    )
    raise SystemExit(1) from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-root", required=True)
    parser.add_argument("--consolidated-dir", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def read_table(path: Path) -> list[list[str]]:
    delimiter = "," if path.suffix.lower() == ".csv" else "\t"
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle, delimiter=delimiter)
        return [list(row) for row in reader]


def sanitize_sheet_name(name: str, used: set[str]) -> str:
    cleaned = name
    for char in "[]*?/\\:":
        cleaned = cleaned.replace(char, "_")
    while "__" in cleaned:
        cleaned = cleaned.replace("__", "_")
    cleaned = cleaned.strip("_") or "sheet"
    cleaned = cleaned[:31]
    candidate = cleaned
    counter = 1
    while candidate in used:
        suffix = f"_{counter}"
        candidate = f"{cleaned[: max(1, 31 - len(suffix))]}{suffix}"
        counter += 1
    used.add(candidate)
    return candidate


def collect_tables(dir_path: Path, prefix: str | None = None) -> list[tuple[str, Path]]:
    if not dir_path.exists():
        return []

    tables: list[tuple[str, Path]] = []
    for path in sorted(dir_path.rglob("*")):
        if path.suffix.lower() not in {".tsv", ".csv"} or not path.is_file():
            continue
        rel = path.relative_to(dir_path)
        sheet_name = str(rel.with_suffix("")).replace("/", "__")
        if prefix:
            sheet_name = f"{prefix}__{sheet_name}"
        tables.append((sheet_name, path))
    return tables


def choose_mapped_results(results_root: Path) -> Path:
    preferred = results_root / "AGRF_samplesheet_with_results_mlst_reviewed.tsv"
    fallback = results_root / "AGRF_samplesheet_with_results.tsv"
    if preferred.exists():
        return preferred
    if fallback.exists():
        return fallback
    raise SystemExit(
        "Neither reviewed nor mapped AGRF results were found. Expected one of:\n"
        f"  {preferred}\n"
        f"  {fallback}\n"
    )


def add_sheet(workbook: Workbook, used_names: set[str], name: str, rows: list[list[str]]) -> None:
    worksheet = workbook.create_sheet(title=sanitize_sheet_name(name, used_names))
    for row in rows:
        worksheet.append(row)


def main() -> int:
    args = parse_args()
    results_root = Path(args.results_root)
    consolidated_dir = Path(args.consolidated_dir)
    output_path = Path(args.output)

    if not results_root.is_dir():
        raise SystemExit(f"--results-root must point to an existing directory: {results_root}")
    if not consolidated_dir.is_dir():
        raise SystemExit(f"--consolidated-dir must point to an existing directory: {consolidated_dir}")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    workbook = Workbook()
    workbook.remove(workbook.active)
    used_names: set[str] = set()

    mapped_path = choose_mapped_results(results_root)
    add_sheet(workbook, used_names, "agrf_results", read_table(mapped_path))

    for top_level in ("project_summary.tsv", "tool_processing_log.tsv"):
        path = consolidated_dir / top_level
        if path.exists():
            add_sheet(workbook, used_names, path.stem, read_table(path))

    for sheet_name, path in collect_tables(consolidated_dir / "results_main" / "merged-results", "main"):
        add_sheet(workbook, used_names, sheet_name, read_table(path))

    for sheet_name, path in collect_tables(consolidated_dir / "tools", "tool"):
        add_sheet(workbook, used_names, sheet_name, read_table(path))

    workbook.save(output_path)
    print(f"Excel workbook written with openpyxl: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
