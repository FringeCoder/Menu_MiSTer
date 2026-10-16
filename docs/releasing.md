# Releasing this Menu core

A release is a GitHub release with `menu.rbf` and a changelog. It is made
**by hand, on demand**. `.github/workflows/release.yml` has
`workflow_dispatch` as its only trigger.

The core is not built in CI: Quartus is not installed there. Commit the fit as
**`releases/menu_snac_YYYYMMDD.rbf`**. Do not use `menu_YYYYMMDD.rbf`: that is
upstream's own naming, and `releases/` already holds upstream's builds, which
do not have the SNAC reader. Only `menu_snac_*.rbf` is ever released.

Then go to Actions -> **release** -> **Run workflow**:

| Input | Meaning |
|---|---|
| `tag` | Empty means `v<date of the newest releases/menu_snac_*.rbf>`. Must not exist yet |
| `prerelease` | Tick for a test build. FringeCoder/AmigaCD_MiSTer's package does not pick up pre-releases |
| `notes` | Optional text shown above the changelog |

The run refuses in any of these cases:
- the branch is not `master`;
- no `menu_snac_*.rbf` is committed, or it is under 500 KB;
- the tag already exists;
- the `.rbf` was already in the previous release.

`rtl-sim.yml` runs first, with the syntax gate, the vendor stamp and the SNAC
benches, and must pass.

The release attaches `menu.rbf` (the name it needs on the card), the dated copy
and `SHA256SUMS`. FringeCoder/AmigaCD_MiSTer's release bundles the latest
release from here into the AmigaCD package.

`scripts/release-notes.py` is a copy of the one in FringeCoder/AmigaCD, which
owns it.
