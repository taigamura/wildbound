#!/usr/bin/env python3
"""Generate HD-2D creature sprites with Codex's image tool (the /hd2d-batch skill drives this).

  python3 scripts/hd2d-codex.py check                 # is Codex's image tool offered right now? (generates nothing)
  python3 scripts/hd2d-codex.py queue                 # species without a sprite yet, in prompts.md order
  python3 scripts/hd2d-codex.py gen emberwick         # one fresh Codex session -> docs/hd2d/original/emberwick-codex-N.png
  python3 scripts/hd2d-codex.py gen emberwick --dry-run

Each `gen` is a new `codex exec` session (HD2D.md: one chat per character) with the body type's
anchor attached and the species' prompt from docs/hd2d/prompts.json (written by hd2d-prompts.py).
Codex saves images under ~/.codex/generated_images/<session>/; this copies the new one out.
Codex drops the image tool from the session entirely (no error) while the account's image quota,
shared with ChatGPT, is used up; `check` detects that so a batch stops before wasting runs.
Review and normalizing stay manual steps (scripts/hd2d-sprite.py), so a bad image never lands in game.
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROMPTS = ROOT / 'docs/hd2d/prompts.json'
ANCHORS = ROOT / 'docs/hd2d/anchors'
ORIGINAL = ROOT / 'docs/hd2d/original'
ART = ROOT / 'godot/art/hd2d'
CODEX_IMAGES = pathlib.Path.home() / '.codex/generated_images'
MODEL = 'gpt-5.6-terra'  # image_gen is only exposed to code-mode models in `codex exec` (gpt-5.5 lacks it)

INSTRUCTION = """You are generating one game sprite image. Do not read, write or edit any files and do not run any commands.
Call your image generation tool exactly once. Use the attached image as the style reference image for that call, and use the text between the PROMPT markers, verbatim, as the image prompt. The tool cannot make true transparency, so where the prompt says transparent background, render the creature on a perfectly flat, solid magenta (#FF00FF) background instead: no gradient, no shadow, no floor (the background is keyed out afterwards).
When the image has been generated, reply with only the word DONE. If the tool fails or refuses, reply with only FAILED: and the reason.

PROMPT START
{prompt}
PROMPT END"""


def load() -> dict:
    return json.loads(PROMPTS.read_text())


def queue(data: dict) -> list[str]:
    """Species without their own sprite, in prompts order (Part A anchors first)."""
    q = []
    for key, d in data.items():
        missing = not (ART / f'{key}.png').exists()
        if d['makes_anchor'] and not (ANCHORS / d['makes_anchor']).exists():
            missing = True
        if missing:
            q.append(key)
    return q


def attach_for(d: dict) -> pathlib.Path:
    # A Part A creature whose anchor already exists (a regeneration) attaches that anchor instead.
    if d['makes_anchor'] and (ANCHORS / d['makes_anchor']).exists():
        return ANCHORS / d['makes_anchor']
    return ANCHORS / d['attach']


def snapshot() -> set[pathlib.Path]:
    return set(CODEX_IMAGES.glob('*/*.png')) if CODEX_IMAGES.exists() else set()


def gen(key: str, data: dict, dry: bool, timeout: int) -> int:
    if key not in data:
        sys.exit(f'unknown species {key!r}; known: {", ".join(data)}')
    d = data[key]
    attach = attach_for(d)
    prompt = d['prompt_own_anchor'] if attach.name == d['makes_anchor'] else d['prompt']
    msg = INSTRUCTION.format(prompt=prompt)
    cmd = base_cmd() + ['--sandbox', 'read-only', '-i', str(attach), '-']
    if dry:
        print(' '.join(cmd), '<<PROMPT\n' + msg + '\nPROMPT')
        return 0
    before = snapshot()
    t0 = time.time()
    print(f'{key}: codex exec with {attach.relative_to(ROOT)} attached ...', flush=True)
    try:
        r = subprocess.run(cmd, input=msg, text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f'{key}: codex timed out after {timeout}s')
        return 2
    new = sorted((p for p in snapshot() - before), key=lambda p: p.stat().st_mtime)
    tail = (r.stdout.strip().splitlines() or [''])[-1]
    if not new:
        print(f'{key}: no image produced (exit {r.returncode}, {time.time() - t0:.0f}s). Last output: {tail}')
        print(r.stderr[-1500:])
        return 1
    ORIGINAL.mkdir(parents=True, exist_ok=True)
    n = 1
    while (ORIGINAL / f'{key}-codex-{n}.png').exists():
        n += 1
    out = ORIGINAL / f'{key}-codex-{n}.png'
    shutil.copy(new[-1], out)
    print(f'{key}: saved {out.relative_to(ROOT)} ({time.time() - t0:.0f}s)')
    return 0


def base_cmd() -> list[str]:
    return ['codex', 'exec', '--enable', 'image_generation', '-m', MODEL, '--skip-git-repo-check', '--color', 'never', '-C', str(ROOT)]


def check(timeout: int) -> int:
    """Asks a throwaway Codex session to list its code-mode tools; looks for image_gen."""
    msg = 'Use your exec tool once to print Object.keys(tools). Reply with that list verbatim and nothing else. Do not call any other tool.'
    try:
        r = subprocess.run(base_cmd() + ['--sandbox', 'read-only', '-'], input=msg, text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print('check: codex timed out'); return 2
    if 'image_gen' in r.stdout:
        print('check: image tool available'); return 0
    print('check: image tool NOT offered (image quota likely used up; try after it resets)')
    return 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('queue')
    sub.add_parser('check')
    g = sub.add_parser('gen')
    g.add_argument('species')
    g.add_argument('--dry-run', action='store_true')
    g.add_argument('--timeout', type=int, default=600)
    a = ap.parse_args()
    data = load()
    if a.cmd == 'check':
        sys.exit(check(300))
    if a.cmd == 'queue':
        for k in queue(data):
            d = data[k]
            extra = f', makes anchors/{d["makes_anchor"]}' if d['makes_anchor'] and not (ANCHORS / d['makes_anchor']).exists() else ''
            print(f'{k}\t{d["name"]}\tsize {d["size"]}\t{d["plan"]}{extra}')
    else:
        sys.exit(gen(a.species, data, a.dry_run, a.timeout))


if __name__ == '__main__':
    main()
