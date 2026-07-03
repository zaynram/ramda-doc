# ramda-doc

[![build](https://github.com/zaynram/ramda-doc/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/zaynram/ramda-doc/actions/workflows/build.yml)
[![pages-build-deployment](https://github.com/zaynram/ramda-doc/actions/workflows/pages/pages-build-deployment/badge.svg?branch=gh-pages)](https://github.com/zaynram/ramda-doc/actions/workflows/pages/pages-build-deployment)

Documentation system with conventions for my projects to consume.

Published at <https://zaynram.github.io/ramda-doc/>.

## Structure

- `docs/decisions/` - Architectural Decision Records (MADR). Records merged to `main` with `status: accepted` are immutable; see the amendments in ADR-0000. Files suffixed `.draft.md` are mutable working drafts.
- `references/` - authoring conventions, including the ADR drafting protocol.
- `docs/requirements.txt` - Python toolchain manifest. The `d2` binary is a system dependency outside its scope.

## Usage

- `nu scripts/setup.nu` - arms the git hooks and synchronizes the local toolchain (requires `nu` and `pipx`). also exposes opt-in d2 installation flow with version pin.
- `bun run serve` / `bun run build` / `bun run publish` - preview, strict build, and deploy.
