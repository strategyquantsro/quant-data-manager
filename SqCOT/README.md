# SqCOT 4.2.5 — StrategyQuant COT for MT5

## Choose one chart indicator

Attach **SqCOT** for chart use. Its default `CotIdentifier=AUTO` maps CFDs such as XAUUSD to their COT futures market (GC). For an exact series or an SQX export, pass an explicit identifier such as `GC_52W` as the first input; the five visual buffers and first two input positions are unchanged. `SqCOTAuto` remains in this release as a compatibility alias and uses the same implementation. The service creates the shared `FILE_COMMON/StrategyQuant/COT/config/symbol-map.csv`; manual CSV copying is not required. Restart the service after installing the new binary. Expand the mapping row to inspect rules, choose a horizon, search every provider market or select a manual chart market.

[Mapping setup, CSV administration, AUTO SDK/iCustom and snapshots](docs/symbol-mapping.html). Reference files in `config/` never overwrite runtime custom rules. Quote orientation does not transform raw CPI/CTI values.


Scheduled COT updates, a market heatmap and an explicit data-readiness API for algorithmic strategies. Data provided by SpreadCharts.

Idle maintenance runs every **60 seconds** in the visual indicator and, by default, in the service. Timer and tick callbacks share one local polling gate. Manual update progress temporarily uses a one-second timer and completion refreshes immediately. The service checks metadata/file attributes each minute, validates full binary files on changes and hourly, and persists scheduler state only when it changes. Scheduled deadlines initiate retries; a successful HTTP response alone never confirms a new report. See [scheduling and maintenance](docs/index.html#schedule).

The compact **Markets / Summary / Events / Guide** accordion, optional horizon comparison, 12-report mini history, descriptive event alerts and shared analytics SDK remain available. See the [compact insights guide](docs/insights.html). The five visual buffers, 11 data buffers and first two visual input positions used by SQX exports remain unchanged. Reload the visual indicator after replacing its EX5. Exported SQX strategies that pass additional indicator inputs still require individual validation.

**Start here: [HTML installation and developer guide](docs/index.html).**

## Quick start

1. In MT5, open **File → Open Data Folder**. Copy the release package's `MQL5` folder into the terminal data directory.
2. Allow WebRequest for `https://cdn.strategyquantcdn.com` in MT5. The download URL is `https://cdn.strategyquantcdn.com/cot.php`.
3. Start `SqCOTService`. Enter your Quant Data Manager key once in its **QDM Data License** input, then configure `RequiredSeries`. Restart the service after changing its inputs.
4. Attach `SqCOT` for chart/heatmap exploration. Leave `CotIdentifier=AUTO` for a CFD chart or enter an exact series ID for an SQX-compatible explicit call. The Update button asks the running service to download using that service licence; the indicator does not accept or store a key.
5. For EAs use `CSqCOTClient` or `SqCOTData` API 1. Require `ReadLatest` plus `CanTrade` before using COT for new entries. Follow the supplied non-trading examples.

## Components and version

- `Services/SqCOTService.mq5`: one background writer, scheduling, retry, locks and alerts.
- `Indicators/SqCOT.mq5`: primary visual chart with automatic mapping, opaque legend/status panel and market heatmap.
- `Indicators/SqCOTAuto.mq5`: compatibility alias for the same visual implementation.
- `Indicators/SqCOTData.mq5`: 11-buffer iCustom API with explicit broker time and observed availability.
- `Include/SqCOTClient.mqh`: strict SDK, snapshots and portfolio reads.
- `Include/SqCOTBlocks.mqh` and `SqCOTStrategy.mqh`: StrategyQuant adapter; lifecycle integration required.
- `Examples/`: latest data, buffers, portfolio, strategy blocks and snapshot export.

The release is **4.2.5**. MT5 displays `4.25` in program properties because its MQL version field uses the compact major/minor/patch representation; the service startup log and package metadata use `4.2.5`. Distribute only the `SqCOT-4.2.5-*.zip` archive for this release.

## Scope and limitations

Verify your strategy and update workflow on a demo setup before live use.

The cache records when this installation first observed each report/revision. The first download cannot reconstruct historical availability. Strict backtests before that observation time return missing data; they require authoritative historical provider metadata to become usable. Export a snapshot and specify the broker clock for reproducible local tests. Remote/cloud snapshot distribution is not implemented.

Check download status, notification delivery and recovery after a restart on your own installation. See the HTML guide for inputs, statuses, buffers, recovery and migration.



## Continuous operation — 4.2.5

See the [24/5 operations guide](docs/index.html#reliability) for heartbeat recovery, backups, monitoring and data freshness. Local checks run every 60 seconds; network attempts follow persisted retry delays. The service begins probing every Friday at 21:00 Europe/Prague time. After the default two-hour grace period, a missing Friday report blocks new COT entries until valid data arrives. Each EA must call `CanTrade()` before new COT entries. Configure **QDM Data License** in `SqCOTService` for manual and unattended downloads. Restart the service after replacing its EX5 and reload indicators/recompile EAs with matching includes. External monitoring and host startup are not installed automatically. Verify updates and recovery on your own installation before live use.
