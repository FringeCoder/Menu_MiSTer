#!/usr/bin/env bash
#
# Parse every synthesisable Verilog/SystemVerilog source standalone and fail on
# a real syntax error.
#
# Why this exists: this repository had no CI at all until 2026-09-13. Nothing
# parsed menu.sv or rtl/ before Quartus did, so a plain syntax error surfaced
# only 18 seconds into a fit. The same gate in the AmigaCD core, which this is
# ported from, was added after a missing comma in a port list cost exactly that.
#
# Parsing a file standalone necessarily reports unknown modules and unresolved
# hierarchical names, because the rest of the design is not on the command line.
# Those are expected and are ignored. Only these are treated as failures:
#
#     syntax error
#     has already been declared
#     Errors in port declarations
#
# rtl/sim/ is excluded: benches are compiled with their real dependencies by the
# bench steps in .github/workflows/rtl-sim.yml, and they legitimately reference
# DUT internals.
#
# sys/ is excluded: it is the MiSTer framework, taken wholesale from upstream
# and not ours to fix. A syntax error there is a bad sync, not a bad edit, and
# would be reported against every core at once.
#
# Individual files can be excluded too, but only with a reason, and the gate
# prints them on every run so an exclusion cannot quietly become permanent
# cover. See EXCLUDE below.

set -uo pipefail

IVERILOG=${IVERILOG:-iverilog}
NULLOUT=${TMPDIR:-/tmp}/syntax_check.$$
BUILD_ID_STUB=0
trap 'rm -f "$NULLOUT"; [ "$BUILD_ID_STUB" = 1 ] && rm -f build_id.v' EXIT

# menu.sv includes build_id.v, which Quartus generates from its pre-flow script
# (sys/build_id.tcl) and .gitignore excludes. A clean checkout does not have it,
# so menu.sv -- the file this gate most exists to cover -- fails on the missing
# include rather than on its own syntax, and Icarus reports that as a syntax
# error on the line AFTER the include, which is a misleading place to start
# looking. Stand one in when it is absent and take it away again, so a later
# real build still gets Quartus's.
if [ ! -f build_id.v ]; then
  printf '`define BUILD_DATE "000000"\n' > build_id.v
  BUILD_ID_STUB=1
fi

# Files Icarus cannot parse but Quartus accepts. Each one needs a reason here.
# This is not a place to silence a real error: if a file is on this list, the
# claim is that the construct is legal SystemVerilog that Icarus 12 does not
# implement, and that claim should be checkable from the note.
#
#   rtl/cos.sv  A 256-entry lookup table written as an unpacked-array
#               assignment pattern -- wire [7:0] qcos[0:255] = '{...}. Legal
#               SystemVerilog and accepted by Quartus (this core has shipped
#               releases built from it); Icarus 12 does not support assignment
#               patterns initialising an unpacked wire array and reports a
#               syntax error at the opening '{. Upstream Menu_MiSTer code,
#               unmodified here, so there is nothing to fix.
EXCLUDE=(
  rtl/cos.sv
)

is_excluded() {
  local f
  for f in "${EXCLUDE[@]}"; do [ "$f" = "$1" ] && return 0; done
  return 1
}

mapfile -t FILES < <(
  { find rtl -name '*.v' -o -name '*.sv'; ls *.v *.sv 2>/dev/null; } \
    | grep -v '/sim/' | sort -u
)

clean=0
unknown_only=0
bad=0

skipped=0

for f in "${FILES[@]}"; do
  if is_excluded "$f"; then
    echo "SKIP $f (see EXCLUDE in $0)"
    skipped=$((skipped + 1))
    continue
  fi
  # -I. so menu.sv's `include "sys/emu_ports.vh" resolves from the repo root.
  out=$("$IVERILOG" -g2012 -I. -t null -o "$NULLOUT" "$f" 2>&1)
  if [ -z "$out" ]; then
    clean=$((clean + 1))
    continue
  fi
  if echo "$out" | grep -qE 'syntax error|has already been declared|Errors in port declarations'; then
    bad=$((bad + 1))
    echo "FAIL $f"
    echo "$out" | grep -E 'syntax error|has already been declared|Errors in port declarations' | sed 's/^/    /'
  else
    unknown_only=$((unknown_only + 1))
  fi
done

echo
echo "files parsed        : $((${#FILES[@]} - skipped))"
echo "excluded            : $skipped"
echo "clean               : $clean"
echo "unknown-module only : $unknown_only"
echo "syntax errors       : $bad"

if [ "$bad" -ne 0 ]; then
  echo
  echo "A file above does not parse standalone. Quartus may still accept it, but"
  echo "this is the cheap place to find out -- fix it here rather than 35 minutes"
  echo "into a fit."
  exit 1
fi
