---
description: "Use when updating the README, adding badges, updating the architecture diagram, documenting new features, or changing project documentation."
applyTo: "{README.md,ARCHITECTURE.md}"
---

# README Maintenance

`README.md` is the product entry point, not a fixed section template. Preserve its visual design, voice, useful content,
and broad ordering unless a deliberate redesign is requested. Keep claims user-focused and aligned with shipped behavior.

## Linked files

`README.md` links to `ARCHITECTURE.md` for structural detail. Keep the two consistent when a change materially affects
the architecture described to contributors.

### ARCHITECTURE.md

- Describe the current structure, target boundaries, layer responsibilities, and important cross-target data flows.
- Keep its tree representative rather than exhaustive.

**When to update `ARCHITECTURE.md`:**
- A layer, target, top-level area, feature boundary, or platform ownership rule changes.
- Extension, App Group, or other cross-target data flow changes materially.

Do not update `ARCHITECTURE.md` merely because an implementation file or test file is added inside an already documented
folder. Its tree is intentionally directory-level with selected explanatory file names, not a complete file manifest.

**Style rules for `ARCHITECTURE.md`:**
- Use the existing tree style with `├──`, `│`, `└──` box-drawing characters
- File names are listed without inline comments unless the purpose is non-obvious
- Keep the layer diagram at the top unchanged unless the architecture itself changes
- Keep names, paths, responsibilities, and data flows aligned with the project. Add detail only when it explains a real
  structural distinction.

### README.md Architecture section

The Architecture section in `README.md` is intentionally brief — it describes the pattern in one paragraph and delegates detail to `ARCHITECTURE.md` via a link. Do **not** duplicate the full tree in `README.md`.

## Rules

- Badges use shields.io `flat-square` style and remain synchronized with active product and platform versions
- Keep the opening product description concise, then maintain the existing feature groups as shipped behavior changes.
- Usage must cover clone, open in Xcode, configure a server URL, and run, plus current toolchain/platform/backend
  requirements.
- Never remove the Self-hosting guides subsection
- When a new feature is added, update the Technologies table only if a new technology or framework is introduced
- Update screenshots, download links, and extension/widget claims when shipped product behavior changes.
