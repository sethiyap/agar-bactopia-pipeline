#!/usr/bin/env python3

from __future__ import annotations

import argparse
import html
import shutil
import subprocess
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

try:
    import markdown as markdown_module
except ModuleNotFoundError:
    markdown_module = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Serve a rendered Markdown preview on localhost."
    )
    parser.add_argument(
        "--file",
        default="README.md",
        help="Markdown file to preview, relative to the repo root by default.",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host interface to bind. Default: 127.0.0.1",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="Port to serve on. Default: 8000",
    )
    return parser.parse_args()


def render_markdown(markdown_path: Path) -> str:
    source = markdown_path.read_text(encoding="utf-8")
    body = render_markdown_body(source)
    title = markdown_path.name

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f7f4ec;
      --panel: #fffdf8;
      --text: #1f2328;
      --muted: #5a6270;
      --border: #ddd4bf;
      --link: #0b5fff;
      --code-bg: #f1ebdb;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: linear-gradient(180deg, #efe7d6 0%, var(--bg) 180px);
      color: var(--text);
    }}
    .wrap {{
      max-width: 980px;
      margin: 0 auto;
      padding: 32px 20px 64px;
    }}
    .header {{
      margin-bottom: 24px;
      padding: 16px 18px;
      border: 1px solid var(--border);
      border-radius: 14px;
      background: rgba(255, 253, 248, 0.9);
      backdrop-filter: blur(8px);
    }}
    .header strong {{ display: block; font-size: 15px; }}
    .header span {{ color: var(--muted); font-size: 13px; }}
    main {{
      padding: 28px 32px;
      border: 1px solid var(--border);
      border-radius: 18px;
      background: var(--panel);
      box-shadow: 0 10px 30px rgba(55, 40, 10, 0.08);
    }}
    h1, h2, h3, h4 {{ line-height: 1.2; }}
    h1 {{ margin-top: 0; }}
    a {{ color: var(--link); }}
    code {{
      padding: 0.15em 0.4em;
      border-radius: 6px;
      background: var(--code-bg);
      font-size: 0.92em;
    }}
    pre {{
      padding: 16px;
      overflow-x: auto;
      border-radius: 12px;
      background: #201a14;
      color: #f5efe6;
    }}
    pre code {{
      padding: 0;
      background: transparent;
      color: inherit;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      margin: 16px 0;
    }}
    th, td {{
      padding: 10px 12px;
      border: 1px solid var(--border);
      text-align: left;
      vertical-align: top;
    }}
    blockquote {{
      margin: 16px 0;
      padding: 4px 0 4px 16px;
      border-left: 4px solid var(--border);
      color: var(--muted);
    }}
    img {{ max-width: 100%; height: auto; }}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="header">
      <strong>{html.escape(title)}</strong>
      <span>Reload the page after editing to see the latest version.</span>
    </div>
    <main>
      {body}
    </main>
  </div>
</body>
</html>
"""


def render_markdown_body(source: str) -> str:
    if markdown_module is not None:
        return markdown_module.markdown(
            source,
            extensions=["fenced_code", "tables", "toc"],
            output_format="html5",
        )

    markdown_py = shutil.which("markdown_py")
    if markdown_py is not None:
        result = subprocess.run(
            [markdown_py],
            input=source,
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout

    escaped = html.escape(source)
    return f"<pre>{escaped}</pre>"


def make_handler(repo_root: Path, markdown_path: Path) -> type[SimpleHTTPRequestHandler]:
    class PreviewHandler(SimpleHTTPRequestHandler):
        def do_GET(self) -> None:
            path = urlparse(self.path).path
            if path in {"/", "/index.html"}:
                try:
                    payload = render_markdown(markdown_path).encode("utf-8")
                except FileNotFoundError:
                    self.send_error(404, f"Markdown file not found: {markdown_path}")
                    return

                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return

            super().do_GET()

    return partial(PreviewHandler, directory=str(repo_root))


def resolve_markdown_path(repo_root: Path, file_arg: str) -> Path:
    candidate = Path(file_arg)
    if candidate.is_absolute():
      return candidate
    return repo_root / candidate


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    markdown_path = resolve_markdown_path(repo_root, args.file)

    if not markdown_path.is_file():
        raise SystemExit(f"Markdown file not found: {markdown_path}")

    handler = make_handler(repo_root, markdown_path)
    server = ThreadingHTTPServer((args.host, args.port), handler)

    print(f"Previewing {markdown_path}")
    print(f"Open http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping preview server.")
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
