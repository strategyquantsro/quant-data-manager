# Contributing

Thank you for your interest in the Quant Data Manager modules. This page explains how we handle issues, pull requests and releases.

## Questions and support

The issue tracker is for bugs and feature requests in the modules published here. For usage questions please use:

- Module documentation: <https://strategyquantsro.github.io/quant-data-manager/>
- Quant Data Manager documentation: <https://strategyquant.com/doc/category/quantdatamanager/>
- Forum: <https://strategyquant.com/forum/>
- Support: <https://strategyquant.com/support/>

## Reporting bugs

Open an issue with the **Bug report** template. It asks for the module version, MetaTrader 5 build, broker and the service log, which we need to reproduce the problem. Remove your Quant Data Manager licence key and account details from logs and screenshots before posting.

Security problems are handled separately. See [SECURITY.md](SECURITY.md).

## Pull requests

We welcome pull requests for bug fixes in the MQL5 sources, improvements to the examples and documentation, corrections to the symbol-map reference data and workflow fixes. For larger changes, new features or changes to the public API (indicator inputs, `iCustom` buffers, `CSqCOTClient` signatures), please open an issue first so we can agree on the approach.

1. Fork the repository and create a branch from `main`.
2. Keep commits small and focused. Describe what changed and why.
3. `main` is protected. Every change goes through a pull request, all review threads must be resolved, and maintainers merge with a merge or squash commit.
4. Make sure every `.mq5` and `.mqh` file compiles in the current MetaEditor without warnings.
5. Do not commit compiled `.ex5` files. They are published in GitHub Releases and the CI rejects them.
6. When you change any file under `SqCOT/`, regenerate the checksum manifest and commit it:

   ```sh
   scripts/checksums.sh generate SqCOT
   ```

   The **Verify checksums** workflow fails if `SqCOT/SHA256SUMS.txt` does not match the files in the repository.
7. Document behaviour changes in the module `README.md` and, where relevant, in the HTML guide under `docs/`.

Text files use LF line endings. `.gitattributes` enforces this, so you do not need to change your editor settings.

## Releases

Releases are prepared by maintainers:

1. Compile the binaries with MetaEditor and record their hashes in `BUILDINFO.json`.
2. Regenerate `SHA256SUMS.txt` with `scripts/checksums.sh generate SqCOT`.
3. Package the module as `SqCOT-X.Y.Z-mt5.zip` (the module folder including the compiled `MQL5` tree) and create `SqCOT-X.Y.Z-mt5.zip.sha256`.
4. Tag the merged commit `vX.Y.Z` and publish a GitHub Release with both files attached.

Binaries live only in GitHub Releases, never in git.

## Licence

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE) that covers this repository.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Please be respectful in issues, pull requests and discussions.
