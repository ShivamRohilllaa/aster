# Contributing to Aster

Aster is a native macOS app with a filesystem cleanup feature. Small, reviewable changes and explicit behavior are especially valuable.

## Development workflow

1. Follow [build and installation](docs/BUILD_AND_INSTALL.md) to select a compatible toolchain and build locally.
2. Create a branch for your change, for example `git switch -c fix/scan-progress`.
3. Keep UI composition in `Sources/Aster` and reusable scanning/cleanup logic in `Sources/AsterCore`.
4. Run `swift test`; run `./scripts/build-app.sh --universal` when changing distribution or architecture-specific code.
5. Describe the problem, resulting behavior, validation and remaining limitations in your pull request.

## Cleanup changes

Read [CLEANUP_RULES.md](docs/CLEANUP_RULES.md) before broadening a path rule or changing Trash behavior. Test protections and failure paths using temporary fixtures and injected movers. Never use personal files or real app data as destructive test fixtures. Never weaken preview, confirmation, symlink, changed-item or protected-path checks merely to make a test pass.

New cache rules need an exact default location, a clear reason, an ownership/running-process caveat, vendor documentation and a decision about whether Aster may offer reviewed cleanup or must show the entry as informational only. A folder name or large size is not proof that data is unused.

## Repository hygiene

Do not commit certificates, private keys, tokens, Apple account identifiers, signing logs, provisioning profiles, local paths, payment credentials or real customer data. Use generic placeholders in examples. `.build/`, `dist/` and private `previews/` are ignored.

Publish screenshots only after inspecting their pixels and metadata. Use controlled sample files and explain that they are documentation fixtures. Do not use a screenshot of a personal home directory or app inventory.

## Contact and licensing

Contact: [shivamrohillaa@gmail.com](mailto:shivamrohillaa@gmail.com).

This project uses the [MIT License](LICENSE). Submit only work you have the right to contribute. Preserve required third-party notices if introducing a dependency. Do not post security reports containing personal data or credentials in public issues; email the contact address instead.
