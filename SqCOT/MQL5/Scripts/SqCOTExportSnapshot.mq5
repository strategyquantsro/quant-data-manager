#property script_show_inputs
#property version "4.00"
#property description "Export immutable local COT snapshot for testing. Never downloads or trades."
#include <SqCOTSnapshot.mqh>
input string SnapshotId=""; // New safe name; existing snapshots are never overwritten
input string BrokerProfile=""; // Optional named historical profile to freeze; fixed UTC offsets need no file
input bool IncludeMapping=true; // Pin this chart symbol and broker server for AUTO tests
void OnStart()
{
   string error;
   bool ok=COT_ExportSnapshot(SnapshotId,BrokerProfile,IncludeMapping,_Symbol,AccountInfoString(ACCOUNT_SERVER),error);
   Print(ok?"Snapshot exported to FILE_COMMON: "+COT_CACHE_DIR+"\\snapshots\\"+SnapshotId:error);
}
