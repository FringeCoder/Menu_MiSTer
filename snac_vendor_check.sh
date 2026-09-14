#!/usr/bin/env bash
#
# Check rtl/snac_psx.v against the canonical copy, or refresh the stamp.
#
# rtl/snac_psx.v is copied from the AmigaCD core, which owns it. MiSTer core
# repositories are self-contained Quartus projects with no submodule or package
# step anywhere in the toolchain, so copying is the platform's convention; the
# cost of that convention is drift, and this is the control for it.
#
# Two modes:
#
#   ./snac_vendor_check.sh                      Verify the local copy still
#                                               hashes to what rtl/snac_psx.vendor
#                                               records. This is what CI runs:
#                                               it needs no second checkout and
#                                               catches the copy being edited
#                                               here, which is the common case.
#
#   ./snac_vendor_check.sh /path/to/amigacd     Also diff against a real
#                                               checkout of the canonical repo,
#                                               which is the only way to catch
#                                               the canonical side having moved.
#
#   ./snac_vendor_check.sh --stamp /path/...    Re-vendor: copy the module and
#                                               bench across and rewrite the
#                                               stamp. Run the bench afterwards.
#
# CI deliberately runs only the first mode. A job here cannot read the other
# repository without a token configured for it, and a check that silently
# degrades to "skipped" when the token is absent is worse than no check at all.

set -euo pipefail
cd "$(dirname "$0")"

VENDOR="rtl/snac_psx.vendor"
MODULE="rtl/snac_psx.v"
BENCH="rtl/sim/snac_psx/tb_snac_psx.sv"

[ -f "$VENDOR" ] || { echo "error: $VENDOR is missing" >&2; exit 1; }

stamp_field() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$VENDOR" | head -1; }

WANT_SHA=$(stamp_field sha256)
WANT_REPO=$(stamp_field repo)
CANON_PATH=$(stamp_field path)

STAMP=0
if [ "${1:-}" = "--stamp" ]; then STAMP=1; shift; fi
CANON="${1:-}"

if [ "$STAMP" = 1 ]; then
	[ -n "$CANON" ] || { echo "error: --stamp needs a path to a $WANT_REPO checkout" >&2; exit 1; }
	[ -f "$CANON/$CANON_PATH" ] || { echo "error: $CANON/$CANON_PATH not found" >&2; exit 1; }
	cp "$CANON/$CANON_PATH" "$MODULE"
	if [ -f "$CANON/rtl/sim/snac_psx/tb_snac_psx.sv" ]; then
		mkdir -p "$(dirname "$BENCH")"
		cp "$CANON/rtl/sim/snac_psx/tb_snac_psx.sv" "$BENCH"
	fi
	NEW_SHA=$(sha256sum "$MODULE" | cut -d' ' -f1)
	NEW_COMMIT=$(git -C "$CANON" rev-parse HEAD 2>/dev/null || echo "unknown")
	sed -i "s/^sha256 .*/sha256 = $NEW_SHA/; s/^commit .*/commit = $NEW_COMMIT/; s/^vendored .*/vendored = $(date -u +%Y-%m-%d)/" "$VENDOR"
	echo "re-vendored from $CANON"
	echo "  commit $NEW_COMMIT"
	echo "  sha256 $NEW_SHA"
	echo
	echo "Now run the bench before committing:"
	echo "  cd rtl/sim/snac_psx && iverilog -g2012 -o tb_snac ../../snac_psx.v tb_snac_psx.sv && vvp tb_snac"
	exit 0
fi

GOT_SHA=$(sha256sum "$MODULE" | cut -d' ' -f1)
if [ "$GOT_SHA" != "$WANT_SHA" ]; then
	echo "FAIL $MODULE does not match the vendor stamp."
	echo "  recorded $WANT_SHA"
	echo "  actual   $GOT_SHA"
	echo
	echo "Either this copy was edited in place -- don't; it is not canonical, fix"
	echo "it in $WANT_REPO and re-vendor -- or a re-vendor updated the file and"
	echo "left $VENDOR behind. Refresh with:"
	echo "  ./snac_vendor_check.sh --stamp /path/to/amigacd-checkout"
	exit 1
fi
echo "OK   $MODULE matches the vendor stamp ($GOT_SHA)"

if [ -n "$CANON" ]; then
	[ -f "$CANON/$CANON_PATH" ] || { echo "error: $CANON/$CANON_PATH not found" >&2; exit 1; }
	if diff -u "$CANON/$CANON_PATH" "$MODULE"; then
		echo "OK   identical to the canonical copy in $CANON"
	else
		echo
		echo "FAIL the canonical copy has moved. Re-vendor:"
		echo "  ./snac_vendor_check.sh --stamp $CANON"
		exit 1
	fi
fi
