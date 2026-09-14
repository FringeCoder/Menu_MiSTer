# Menu core: state and open items

Written 2026-09-13, when this repository got CI for the first time. It is much
shorter than the AmigaCD core's equivalent because this repository is much
smaller: `menu.sv`, six RTL files, and the MiSTer framework in `sys/`. Only the
SNAC PSX reader and its wiring in `menu.sv` are ours; everything else is
upstream Menu_MiSTer.

Every item below cites a file and line or a commit. Nothing here is inferred
from behaviour alone.

## How we verify

- **SIM** — an Icarus bench in `rtl/sim/`, run in CI. Two benches' worth of
  surface exists today: the SNAC reader, at all three clk rates it is
  instantiated at.
- **TITLE** — observation against real hardware: a real PSX pad, a real GunCon,
  a real MT32-pi on the same user port. There is no record of any of this
  having been done on this core, which is what M3 is about.
- **FIT** — Quartus slacks. Not a live concern here: this core is tiny and has
  never been reported as tight. If it ever is, the AmigaCD core's
  `seed_sweep_both.sh` is the model, and the rule there applies here — both
  edges, always.

There is no SUITE route for this core and there does not need to be one.

---

## M1 — `snac_state`'s word order is an unchecked cross-repo contract  [SIM]

`menu.sv:251` says it outright:

    // Word 0 is status (both device IDs), then pad and axes per port. Must match the
    // word order userspace reads in snac_psx_poll().

`menu.sv:253` packs 112 bits in a specific order and userspace unpacks them in
the same order, in a different repository. Nothing checks that the two agree.
Get it wrong and every button is a different button — which is obvious the
instant anyone tries it, but only then, and the failure looks like a broken pad
rather than a field order.

This is the same class as the `hps_ext` byte_cnt alignment in the AmigaCD core,
which got a bench for exactly this reason: "the convention appears nowhere in
the source".

Doing it needs the userspace side in view to write the expected order down, so
it is blocked on having that repository to hand, not on difficulty.

## M2 — Five of the eight SNAC bench checks are not falsified  [SIM]

`rtl/sim/snac_psx/tb_snac_psx.sv` has eight checks. Three were confirmed to
fail under a matching DUT mutation on 2026-09-13 — the GunCon axes gate, the
ACK glitch filter, and ATT setup. The other five (idle-bus absence, the digital
five-byte frame, port alternation, DualShock axes, unplug clearing a held
button) went green and were never shown to go red.

A check that has never failed has not been shown to test anything. Mutate the
DUT once per check and record the result, the way the three are recorded in the
CI step's comment.

## M3 — The SNAC reader has no hardware verification on this core  [TITLE]

Three of the four commits that built `snac_psx.v` are fixes to behaviour that
only appears against a real device, which means someone was testing against
hardware while writing it. None of that is recorded, and none of it was on
*this* core — the module is shared, and the AmigaCD core is where the work
happened.

What is unverified here specifically: the 100 MHz instantiation
(`menu.sv:256` — every other use is a different rate), and the user-port
arbitration in `menu.sv:270-273`.

Needs: a MiSTer, a SNAC adapter, a digital pad, a DualShock, and ideally a
GunCon. Record what was tried and what was seen, including the negative results.

## M4 — The user-port mux between SNAC and MT32-pi is untested  [SIM]

`menu.sv:268-273`. The two tenants collide on every pin, so the mux is
"physics, not policy" as the comment says — but it is still four combinational
assignments that nothing exercises. The interesting case is not the steady
state, it is `snac_enable` changing while a poll is mid-frame: the reader is
left driving a bus it no longer owns until its state machine notices.

Cheap to bench, and the bench would be a small extension of the SNAC one.
Ranked below M1 and M2 because a wrong answer here degrades to "MIDI is silent
while SNAC is on", which is visible, rather than to a subtly wrong button map.

## M5 — `rtl/cos.sv` is outside the syntax gate  [no code]

The 256-entry cosine table is written as an unpacked-array assignment pattern,
`wire [7:0] qcos[0:255] = '{...}` (`rtl/cos.sv:6`). That is legal SystemVerilog
and Quartus accepts it — this core has shipped releases built from it — but
Icarus 12 does not implement assignment patterns initialising an unpacked wire
array, and reports a syntax error at the opening `'{`.

It is excluded by name in `syntax_check.sh`, which prints the exclusion on every
run so it cannot quietly become cover for something else. Nothing to fix: it is
upstream code, unmodified, and the construct is correct. Revisit only if Icarus
gains support, and delete the exclusion then rather than leaving it.

## M6 — The vendor guard is a stamp, not a live diff  [no code]

`snac_vendor_check.sh` in CI checks `rtl/snac_psx.v` against the sha256 in
`rtl/snac_psx.vendor`. That catches the copy being edited here. It does **not**
catch the canonical copy in the AmigaCD core having moved — for that the script
needs a path to a checkout, which CI cannot get without a token configured for
the other repository.

The deliberate choice is a hard local check over a cross-repo check that
degrades to "skipped" when a secret is missing. The upgrade, if the token ever
exists, is a second `actions/checkout` with `repository:` and a diff; the script
already implements that comparison. See `docs/snac-psx-vendoring.md` in the
AmigaCD core.

---

## M7 — menu.rbf reaches the MiSTer by hand, and update_all overwrites it  [no code]

Deploying this core is manual, and the manual step has a silent failure mode.

The AmigaCD userspace repository (`FringeCoder/AmigaCD`) carries the deployment
tooling. Its `scripts/stage-output.sh` copies this core's build —
`upstream/core-menu/output_files/menu.rbf` — into `output/menu.rbf`, and stops
there. **No script transfers it to the machine.** Every remote-copy site in that
repository (`scripts/deploy-from-ci.sh:65`, `scripts/deploy-from-ci.ps1:81`,
`scripts/wsl-build.sh:117`, `build.sh:26`) sends only the userspace binary, and
the CI artifact those pull from contains just `MiSTer` and `MiSTer.elf`. The
last hop for a core is a hand copy, per that repo's `docs/deployment.md:22`.

The part that bites this core specifically: `menu.rbf` cannot be protected from
`update_all`. Downloader filters are category/core level only, there is no
per-file exclusion, and the boot menu **must** be named `menu.rbf`, so renaming
is not available. The documented defence is two commands run by hand — keep
`menu_snac.rbf` as a spare and restore it after every update that touches the
Menu core.

Miss that and the SNAC pad stops answering in the boot menu with a `menu.rbf`
present and a plausible version on screen, which is a rough thing to attribute:
it looks like the pad, or the adapter, or `snac_psx=1`, or SW[1].

Also worth knowing before debugging a pad that does not answer: `snac_psx=1`
belongs in `/media/fat/MiSTer.ini` under `[MENU]`, because `main=` matches the
core's CONF_STR name and this core calls itself MENU. And SW[1] on the
DE10-Nano must be OFF — it hands three user-port pins to HDMI audio and the pad
never answers, with no error.

No action here; this is recorded so it is not rediscovered as a bug. The full
set of deployment gaps is written up in the AmigaCD repo as
`docs/deployment-gaps.md`.

## Order

1. **M2** — minutes of work, needs nothing but the repository, and it decides
   how much the rest of the bench is worth.
2. **M1** — the highest-value gap, blocked only on having the userspace source
   to hand.
3. **M3** — needs hardware. Do it the next time the hardware is in front of you
   rather than scheduling it.
4. **M4** — cheap, low consequence.
5. **M5, M6, M7** — recorded so they are not rediscovered as bugs. None is work.
   M7 is the one to reread before debugging a SNAC pad that has stopped
   answering in the boot menu, since an `update_all` is the likeliest cause.

## What is not on this list

`sys/`. It is the MiSTer framework, taken wholesale from upstream, and it is
excluded from the syntax gate for that reason: an error there is a bad sync, not
a bad edit, and it would be reported against every core at once. Do not fix it
here.
