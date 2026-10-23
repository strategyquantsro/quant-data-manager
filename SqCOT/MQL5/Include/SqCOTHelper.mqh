// Generated-strategy adapter. COT service is started manually in Navigator.
#ifndef __SQ_COT_HELPER_MQH__
#define __SQ_COT_HELPER_MQH__
#include <SqCOTReader.mqh>
#include <SqCOTProtocol.mqh>
#include <SqCOTClient.mqh>
CSqCOTClient g_cotHelperClient;
// Strict readiness for new integrations. Existing no-argument helpers only report cache presence.
bool SqCOT_EnsureSeriesReady(const string series)
{
   if(g_cotHelperClient.Series()!=series && !g_cotHelperClient.OpenLive(series))return false;
   SqCOTSnapshot snapshot;return g_cotHelperClient.ReadLatest(snapshot)&&g_cotHelperClient.CanTrade(snapshot);
}
bool g_cotDataAvailable=false;
datetime g_cotHelperLastCheck=0;
bool SqCOT_EnsureDataAvailable()
{
   g_cotDataAvailable=COT_Initialize();
   if(!g_cotDataAvailable)
      Print("[SQ COT] Prepare the cache using SqCOT indicator and SqCOTService before running this strategy.");
   return g_cotDataAvailable;
}
// Call from the strategy's timer, or its existing OnTick retry path.
// At most one filesystem version check per second; none during backtests.
bool SqCOT_RetryIfNeeded()
{
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return g_cotDataAvailable;
   if(g_cotHelperLastCheck==COT_NOW()) return g_cotDataAvailable;
   g_cotHelperLastCheck=COT_NOW();
   if(!g_cotDataAvailable) g_cotDataAvailable=COT_Initialize();
   else COT_ReloadIfVersionChanged();
   return g_cotDataAvailable;
}
// Compatibility names retained for older generated strategies; no chart/EA launch.
bool SqCOT_IsDownloaderRunning() {return COT_ServiceAvailable();}
void SqCOT_LaunchDownloader()
{
   Print("[SQ COT] Start Navigator > Services > SqCOTService; update data from the SqCOT indicator.");
}
void SqCOT_Deinit()
{
   g_cotHelperClient.Close();
   COT_Deinitialize(); g_cotDataAvailable=false;
}
#endif
