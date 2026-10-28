## Summary

<!-- What changes and why. Link the related issue, e.g. "Closes #12". -->

## Module and scope

- Module: SqCOT
- Type: bug fix / documentation / example / configuration / workflow

## Checklist

- [ ] Every changed `.mq5` / `.mqh` compiles in the current MetaEditor without warnings.
- [ ] No compiled `.ex5` files are included.
- [ ] `scripts/checksums.sh generate SqCOT` was run and `SqCOT/SHA256SUMS.txt` is committed (if anything under `SqCOT/` changed).
- [ ] Behaviour changes are documented in the module `README.md` or `docs/`.
- [ ] Public API (inputs, `iCustom` buffers, `CSqCOTClient` signatures) is unchanged, or the change is described above.

## Testing

<!-- How you verified the change: MT5 build, broker, what you ran. -->
