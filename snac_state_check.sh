#!/usr/bin/env bash
#
# Check this repository's half of the snac_state word order against
# docs/snac-state-contract.md.
#
# menu.sv packs 112 bits, the framework streams them 16 at a time, and
# snac_psx_poll() in FringeCoder/AmigaCD unpacks them. Nothing connects the two
# but the ordering, and getting it wrong makes every button a different button --
# which looks like a broken reader rather than a field order, so it is not
# something the next person debugs quickly.
#
# Neither repository can see the other in CI. So each side is pinned to the
# table in the contract document instead, and a change on either side that is
# not also a change to that table fails the build at the commit that made it.
# The AmigaCD repository runs the same script against its unpack side.
#
# If this fails, do NOT delete it as stale. See the contract document.
set -euo pipefail
cd "$(dirname "$0")"

CONTRACT="docs/snac-state-contract.md"
SRC="menu.sv"

# The declared order, most significant operand first -- the order the assign
# reads in. Kept here rather than parsed out of the document: this is the check,
# and a check that derives its expectation from the thing it is checking proves
# nothing. The document is for humans; these six tokens are for CI.
WANT="snac_axes1 snac_pad1 snac_axes0 snac_pad0 snac_id1 snac_id0"

[ -f "$CONTRACT" ] || { echo "error: $CONTRACT is missing" >&2; exit 1; }
[ -f "$SRC" ]      || { echo "error: $SRC is missing" >&2; exit 1; }

# Pull the operand list out of `assign snac_state = { ... };`, which may be
# wrapped across lines. Strip the braces, split on commas, drop whitespace.
GOT="$(sed -n '/assign[[:space:]]\+snac_state[[:space:]]*=/,/;/p' "$SRC" \
       | tr '\n' ' ' \
       | sed -e 's/.*{//' -e 's/}.*//' -e 's/,/ /g' \
       | tr -s '[:space:]' ' ' \
       | sed -e 's/^ //' -e 's/ $//')"

if [ -z "$GOT" ]; then
    echo "!! Could not find 'assign snac_state = { ... };' in $SRC." >&2
    echo "   If the packing moved or was rewritten, this check has to move with" >&2
    echo "   it -- and so does $CONTRACT, and so does the AmigaCD side." >&2
    exit 1
fi

if [ "$GOT" != "$WANT" ]; then
    echo "!! snac_state packing does not match the contract." >&2
    echo "   want: $WANT" >&2
    echo "   got : $GOT" >&2
    echo >&2
    echo "   Word 0 of the stream is the LAST operand pair (the ids), because" >&2
    echo "   concatenation puts the first operand in the high bits and the" >&2
    echo "   stream sends the low word first. See $CONTRACT." >&2
    echo >&2
    echo "   Changing this order means changing snac_psx_poll() in" >&2
    echo "   FringeCoder/AmigaCD and the table in $CONTRACT in the same breath." >&2
    exit 1
fi

# The width follows from the operands, but state it anyway: a field that changes
# width silently reshapes every word after it, and the packing line alone would
# still read correctly.
WIDTH_DECLS="$(grep -cE '^[[:space:]]*wire[[:space:]]+\[(15|31|7):0\][[:space:]]+snac_(pad|axes|id)[01]' "$SRC" || true)"
if [ "$WIDTH_DECLS" -lt 3 ]; then
    echo "!! The snac_pad/axes/id declarations in $SRC are not the expected widths." >&2
    echo "   Expected 16-bit pads, 32-bit axes, 8-bit ids -- see $CONTRACT." >&2
    exit 1
fi

echo "OK   snac_state packing matches $CONTRACT"
echo "     word 0 = {snac_id1, snac_id0}, then pad0, axes0 (lo,hi), pad1, axes1 (lo,hi)"
