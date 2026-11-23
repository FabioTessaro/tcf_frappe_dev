#!/usr/bin/env python3
"""Assemble the architecture guide into one Markdown book for pandoc.

Usage: assemble.py <guide-dir> <output.md>

- Each top-level folder becomes a part (level-1 heading).
- Each file becomes a chapter (its "# " heading becomes level 2; deeper headings shift by one).
- Links between guide files become internal anchors; links leaving the guide become plain text.
"""

import re
import sys
from pathlib import Path

PARTS = {
    "00-foundations": "Part 0 · Foundations",
    "01-system": "Part 1 · System",
    "02-domain-foundations": "Part 2 · Domain foundations",
    "03-contracts": "Part 3 · Contracts",
    "10-frontend": "Part 10 · Frontend",
    "20-backend": "Part 20 · Backend",
    "30-security-and-compliance": "Part 30 · Security and compliance",
    "40-testing": "Part 40 · Testing",
    "50-delivery": "Part 50 · Delivery",
    "60-operations": "Part 60 · Operations",
    "70-compliance-framework": "Part 70 · Compliance framework",
    "80-playbooks": "Part 80 · Playbooks",
    "90-appendices": "Part 90 · Appendices",
}

# Reading order inside folders whose file names do not sort meaningfully.
ORDER = {
    "80-playbooks": [
        "new-feature-app.md",
        "new-feature.md",
        "new-capability.md",
        "new-party-type.md",
        "new-error-code.md",
        "new-integration-endpoint.md",
        "new-storage-class-or-file-policy.md",
        "new-language-or-script.md",
        "covering-a-new-norm.md",
    ],
    "90-appendices": ["open-decisions.md", "adr-template.md", "reference-deployment.md"],
}

LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")


def anchor_for(rel: Path) -> str:
    """Stable anchor for a guide file or folder, relative to the guide root."""
    stem = rel.as_posix().removesuffix(".md").removesuffix("/")
    return "g-" + re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")


def chapter_files(root: Path):
    for folder in PARTS:
        files = sorted(p.name for p in (root / folder).glob("*.md"))
        order = ORDER.get(folder, [])
        files = [f for f in order if f in files] + [f for f in files if f not in order]
        yield folder, [root / folder / f for f in files]


def rewrite_links(text: str, src: Path, root: Path) -> str:
    def repl(m: re.Match) -> str:
        label, target = m.group(1), m.group(2)
        if target.startswith(("http://", "https://", "mailto:")):
            return m.group(0)
        path_part, _, _frag = target.partition("#")
        if not path_part:  # same-file fragment: point at the chapter itself
            return f"[{label}](#{anchor_for(src.relative_to(root))})"
        dest = (src.parent / path_part).resolve()
        try:
            rel = dest.relative_to(root.resolve())
        except ValueError:
            return label  # outside the guide: keep the text only
        if rel.as_posix() == "README.md":
            return f"[{label}](#g-about)"
        return f"[{label}](#{anchor_for(rel)})"

    return LINK.sub(repl, text)


def shift_headings(text: str, chapter_anchor: str) -> str:
    out, in_fence, first = [], False, True
    for line in text.splitlines():
        if line.startswith("```"):
            # Tag untagged blocks as text so the PDF typesets them in the (smaller)
            # code-block font of the highlighting environment, keeping diagrams aligned.
            if not in_fence and line.strip() == "```":
                line = "```text"
            in_fence = not in_fence
        m = None if in_fence else HEADING.match(line)
        if m:
            level = min(len(m.group(1)) + 1, 6)
            title = m.group(2)
            if first:
                line = f"{'#' * level} {title} {{#{chapter_anchor}}}"
                first = False
            else:
                line = f"{'#' * level} {title} {{-}}"
        out.append(line)
    return "\n".join(out)


def main() -> None:
    root, output = Path(sys.argv[1]), Path(sys.argv[2])
    chunks = []

    readme = (root / "README.md").read_text()
    readme = readme.split("\n", 1)[1]  # drop the title: it is the book title
    readme = rewrite_links(readme, root / "README.md", root)
    readme = shift_headings("# About this guide\n" + readme, "g-about")
    chunks.append(readme.replace("{#g-about}", "{#g-about .unnumbered}"))

    for folder, files in chapter_files(root):
        chunks.append(f"# {PARTS[folder]} {{#{anchor_for(Path(folder))}}}")
        for f in files:
            body = rewrite_links(f.read_text(), f, root)
            chunks.append(shift_headings(body, anchor_for(f.relative_to(root))))

    book = "\n\n".join(chunks) + "\n"
    # Glyphs missing from the PDF body font (Source Serif Pro): use close equivalents.
    book = book.replace("⇒", "→")
    output.write_text(book)


if __name__ == "__main__":
    main()
