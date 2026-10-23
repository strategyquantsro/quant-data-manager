#property version "4.00"
#property description "Read-only COT example. This EA never submits trades."
#include <SqCOTClient.mqh>
input string Series="GC_52W";
input string SnapshotId=""; // Required in tester
input string BrokerTimeProfile=""; // UTC or explicit offset/profile for tester
input bool PopupOnServiceFailure=true;
input bool PushOnServiceFailure=false;
CSqCOTClient Cot;
string Seen="";
int OnInit()
{
   bool tester=MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION);
   bool ok=tester?Cot.OpenSnapshot(Series,SnapshotId,BrokerTimeProfile):Cot.OpenLive(Series);
   if(!ok) {Print(Cot.Error());return INIT_FAILED;}
   Cot.SetNotifications(PopupOnServiceFailure,PushOnServiceFailure);
   if(!EventSetTimer(5)) {Cot.Close();return INIT_FAILED;}return INIT_SUCCEEDED;
}
void CheckData()
{
   Cot.Poll();SqCOTSnapshot s;
   if(!Cot.ReadLatest(s)||!Cot.CanTrade(s)) return;
   string key=s.reportId+":"+IntegerToString(s.revision);
   if(Seen==key)return;Seen=key;
   Print("[COT EXAMPLE] ",s.seriesId," report=",s.reportId," revision=",s.revision,
         " generation=",s.generation," hedgers=",s.values[0]);
}
void OnTimer() {CheckData();}
void OnTick() {CheckData();}
void OnDeinit(const int reason) {EventKillTimer();Cot.Close();}
