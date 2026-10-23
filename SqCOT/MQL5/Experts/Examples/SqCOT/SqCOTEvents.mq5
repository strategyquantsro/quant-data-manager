#property version "4.10"
#property description "Read-only descriptive COT events. No orders or price confirmation."
#include <SqCOTInsights.mqh>
input string Market="GC";
input string SnapshotId="";
input string BrokerTimeProfile="";
CSqCOTClient ShortHorizon,LongHorizon;
string Seen="";
int OnInit()
{
   bool tester=MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION);
   bool a=tester?ShortHorizon.OpenSnapshot(Market+"_52W",SnapshotId,BrokerTimeProfile):ShortHorizon.OpenLive(Market+"_52W");
   bool b=tester?LongHorizon.OpenSnapshot(Market+"_156W",SnapshotId,BrokerTimeProfile):LongHorizon.OpenLive(Market+"_156W");
   if(!a || !b) {ShortHorizon.Close();LongHorizon.Close();return INIT_FAILED;}
   if(!EventSetTimer(5)) {ShortHorizon.Close();LongHorizon.Close();return INIT_FAILED;}
   return INIT_SUCCEEDED;
}
void Evaluate()
{
   ShortHorizon.Poll();LongHorizon.Poll();
   SqCOTSnapshot a,b;
   if(!ShortHorizon.ReadLatest(a) || !LongHorizon.ReadLatest(b) ||
      !ShortHorizon.CanTrade(a) || !LongHorizon.CanTrade(b)) return;
   long now;if(!ShortHorizon.NowUtc(now)) return;
   SqCOTInsight event;
   if(!COT_ReadInsight(ShortHorizon,LongHorizon,now,event) || !event.paired) return;
   string key=IntegerToString(event.reportDate)+":"+IntegerToString(event.availableAtUtc)+":"+IntegerToString(event.events);
   if(Seen==key) return;Seen=key;
   Print("[COT EVENTS] ",Market," ",TimeToString((datetime)event.reportDate,TIME_DATE),
      " H=",COT_InsightIndex(event.level)," ",COT_InsightEvents(event.events));
   // event.events is a bitmask. Multiple descriptive events may coexist.
   // Define and test your own price confirmation, expiry and execution rules.
}
void OnTick() {Evaluate();}
void OnTimer() {Evaluate();}
void OnDeinit(const int reason) {EventKillTimer();ShortHorizon.Close();LongHorizon.Close();}
