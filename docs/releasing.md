# Releasing this Menu core

A release is a GitHub release with `menu.rbf` and a changelog. It is made
**by hand, on demand**. `.github/workflows/release.yml` has
`workflow_dispatch` as its only trigger.

## How the core is fitted

`.github/workflows/fit.yml` runs Quartus 17.0.2 Lite for Cyclone V, from the
`theypsilon/quartus-lite-c5:17.0.2.docker1` image that the MiSTer nightly
builds use. That is the version `menu.qsf` was last saved with, and the tag is
pinned. `scripts/ci-fit.sh` fits one placement seed per job, all in parallel,
and reads both worst-case slacks.

- **On every push to `master`:** it fits the `.qsf`'s own seed and keeps the
  bitstream as the `core` artifact for 14 days. Timing that is not met shows
  up as a warning in the run summary, not as a failure.
- **In a release:** it fits the `seeds` input. Only a seed whose setup **and**
  hold slack are both positive is released. If no seed qualifies, nothing is
  published.

`releases/` holds upstream's own builds (Sorgelig's `menu_*.rbf`) and is left
alone. Nothing is taken from it.

## Making one

Actions -> **release** -> **Run workflow**:

| Input | Meaning |
|---|---|
| `tag` | Empty means `v<today, UTC>`. Must not exist yet |
| `seeds` | Placement seeds to fit in parallel |
| `prerelease` | Tick for a test build. FringeCoder/AmigaCD_MiSTer's package does not pick up pre-releases |
| `notes` | Optional text shown above the changelog |

The run refuses in any of these cases:
- the branch is not `master`;
- the tag already exists;
- nothing was committed since the previous release;
- no seed closes timing.

`rtl-sim.yml` also runs, with the syntax gate, the vendor stamp and the SNAC
benches, and must pass.

The release attaches `menu.rbf` (the name it needs on the card), a dated copy
and `SHA256SUMS`, and the notes record the seed and both slacks.
FringeCoder/AmigaCD_MiSTer's release bundles the latest release from here into
the AmigaCD package.

`scripts/release-notes.py` is a copy of the one in FringeCoder/AmigaCD, which
owns it. `scripts/ci-fit.sh` is shared with FringeCoder/AmigaCD_MiSTer.
