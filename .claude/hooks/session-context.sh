#!/usr/bin/env bash
# SessionStart hook: print recent work into Claude's context.
# CLAUDE.md (incl. "Releasing") is already loaded by Claude Code; this adds what git knows.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0

echo "Recent commits (newest first; bodies capped at 4 lines):"
git log -10 --date=short --format='%x1e%h %ad %s%n%b' |
  grep -v '^Co-Authored-By:\|^Claude-Session:' |
  awk 'BEGIN { RS = "\x1e" } NF {
         n = split($0, l, "\n"); out = 0
         for (i = 1; i <= n; i++) {
           if (l[i] == "") continue
           if (out < 5) print (out ? "    " : "- ") l[i]
           else if (out == 5) print "    …"
           out++
         }
       }'

echo
echo "Uncommitted changes:"
s=$(git status --short)
if [ -n "$s" ]; then echo "$s" | head -20; else echo "(none)"; fi
