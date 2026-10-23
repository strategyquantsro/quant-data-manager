# Quant Data Manager

**Download, manage, analyze, convert, and export high-quality historical market data for algorithmic trading.**

Quant Data Manager (QDM) by [StrategyQuant](https://strategyquant.com/) prepares historical data for backtesting and strategy research. It downloads data from supported sources, imports your own files, checks data quality (gaps, price spikes, incorrect candles), works with timeframes and time zones, and exports data to trading platforms such as MetaTrader 4/5.

This repository hosts the **public modules and integrations** that extend Quant Data Manager and connect its data to trading platforms.

- Product page: <https://strategyquant.com/quantdatamanager/>
- Download: <https://strategyquant.com/quantdatamanager/download/>
- Documentation: <https://strategyquant.com/doc/category/quantdatamanager/>

## Modules

| Module | Platform | Description |
|--------|----------|-------------|
| [SqCOT](SqCOT/) | MetaTrader 5 | Commitments of Traders (COT) data in MT5: a background download service, chart indicator with market heatmap, an `iCustom` data API and an EA/SDK layer for algorithmic strategies. Data is delivered through a Quant Data Manager data licence. |

More modules will be added over time. Each module lives in its own folder with its own `README.md`, documentation and release files.

## SqCOT — StrategyQuant COT for MT5

SqCOT brings weekly CFTC Commitments of Traders reports into MetaTrader 5 so you can explore positioning on charts and use it as a strategy input.

- `Services/SqCOTService` — one background writer that downloads, schedules, retries and validates COT data.
- `Indicators/SqCOT` — visual chart indicator with automatic CFD → futures market mapping (e.g. XAUUSD → GC), legend/status panel and market heatmap.
- `Indicators/SqCOTData` — 11-buffer `iCustom` API for EAs and StrategyQuant X exports.
- `Include/SqCOTClient.mqh` — strict SDK with snapshots and portfolio reads.
- `Include/SqCOTBlocks.mqh`, `SqCOTStrategy.mqh` — StrategyQuant adapter.
- `Examples/` — non-trading example EAs and scripts.

Start with the [SqCOT README](SqCOT/README.md) and the [HTML installation and developer guide](https://strategyquantsro.github.io/quant-data-manager/SqCOT/docs/). The folder contains both MQL5 sources and compiled `.ex5` binaries; `SHA256SUMS.txt` and `BUILDINFO.json` describe the release build.

### Quick start

1. In MT5 open **File → Open Data Folder** and copy the `SqCOT/MQL5` folder into the terminal data directory.
2. Allow WebRequest for `https://cdn.strategyquantcdn.com` in MT5.
3. Start `SqCOTService`, enter your Quant Data Manager key in its **QDM Data License** input and configure `RequiredSeries`.
4. Attach the `SqCOT` indicator to a chart, or use `CSqCOTClient` / `SqCOTData` in your EA.

Verify your setup on a demo account before live use.

## Repository layout

```
quant-data-manager/
└── SqCOT/              # COT data for MetaTrader 5
    ├── MQL5/           # Drop-in MQL5 tree (Services, Indicators, Include, Experts, Scripts)
    ├── Examples/       # Example EA and script sources
    ├── config/         # Symbol-map reference files and schema
    ├── docs/           # HTML guides
    ├── README.md
    ├── BUILDINFO.json
    └── SHA256SUMS.txt
```

## Support

- Documentation: <https://strategyquant.com/doc/category/quantdatamanager/>
- FAQ: <https://strategyquant.com/faq/>
- Community and support: <https://strategyquant.com/>

Quant Data Manager and StrategyQuant are products of StrategyQuant s.r.o.
