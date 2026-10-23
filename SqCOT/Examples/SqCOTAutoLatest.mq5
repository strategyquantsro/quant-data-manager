#property version "4.20"
#property description "Read-only AUTO COT example. Never sends orders."
#include <SqCOTClient.mqh>
input int HorizonWeeks=52;
input string DatasetSnapshot="";
input string BrokerTimeProfile="UTC";
input string SnapshotBrokerServer=""; // Exact server captured by the snapshot exporter
CSqCOTClient Cot;
string LastStatus="";
int OnInit()
{
   bool tester=MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
   string server=SnapshotBrokerServer==""?AccountInfoString(ACCOUNT_SERVER):SnapshotBrokerServer;
   bool ok=tester?Cot.OpenAutoSnapshot(_Symbol,server,HorizonWeeks,DatasetSnapshot,BrokerTimeProfile):
      Cot.OpenAutoLive(_Symbol,server,HorizonWeeks);
   if(!ok)Print(Cot.Error());
   return ok?INIT_SUCCEEDED:INIT_FAILED;
}
void OnTick()
{
   CotMapResult mapping;Cot.Mapping(mapping);SqCOTSnapshot snapshot;
   bool ready=Cot.ReadLatest(snapshot) && Cot.CanTrade(snapshot);
   string status=mapping.status+" | "+mapping.series+" | "+mapping.orientation+" | "+(ready?"ready":"waiting");
   if(status!=LastStatus){Print(status);LastStatus=status;}
   if(!ready)return;
   // Evaluate snapshot.values[] here. INVERSE never changes those raw values.
   // CONFIG_CHANGED requires an intentional OpenAutoLive() after reviewing the change.
}
void OnDeinit(const int reason){Cot.Close();}
