#property version "4.00"
#property description "Read-only consistent multi-series COT example."
#include <SqCOTClient.mqh>
input string SeriesList="GC_52W,GC_156W";
input string SnapshotId="";
input string BrokerTimeProfile="";
CSqCOTClient Clients[];
int OnInit()
{
   if(!COT_ValidSeriesList(SeriesList))return INIT_PARAMETERS_INCORRECT;
   string ids[];int n=StringSplit(SeriesList,',',ids);ArrayResize(Clients,n);
   bool tester=MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION);
   for(int i=0;i<n;i++)
   {
      bool ok=tester?Clients[i].OpenSnapshot(ids[i],SnapshotId,BrokerTimeProfile):Clients[i].OpenLive(ids[i]);
      if(!ok){for(int j=0;j<=i;j++)Clients[j].Close();return INIT_FAILED;}
   }
   if(!EventSetTimer(5)){for(int i=0;i<n;i++)Clients[i].Close();return INIT_FAILED;}return INIT_SUCCEEDED;
}
void OnTimer()
{
   SqCOTSnapshot rows[];if(!COT_ReadBatch(Clients,rows))return;
   // Same-market 52W/156W scores require the SAME weekly report as well as generation.
   for(int i=1;i<ArraySize(rows);i++)if(rows[i].reportDate!=rows[0].reportDate)return;
   static long generation=0;if(generation==rows[0].generation)return;generation=rows[0].generation;
   Print("[COT PORTFOLIO] consistent generation ",generation,"; series ",ArraySize(rows));
}
void OnTick() {}
void OnDeinit(const int reason){EventKillTimer();for(int i=0;i<ArraySize(Clients);i++)Clients[i].Close();}
