#property version "4.00"
#property description "Strict StrategyQuant encoded-handle adapter example; never trades."
int g_currentBar=0;
#include <SqCOTBlocks.mqh>
input string CotMarket="GC";
input string BrokerTimeProfile="";
input string SnapshotId="";
int OnInit(){return SqCOT_ConfigureBlocks(CotMarket,BrokerTimeProfile,SnapshotId)?INIT_SUCCEEDED:INIT_PARAMETERS_INCORRECT;}
void OnTick()
{
   if(!SqCOT_BeginEvaluation())return;
   double score=SqCOT_CalcScore(0,10,2,12,0);
   if(score==EMPTY_VALUE)return;
   // Use the value in your own decision logic; this example sends no orders.
}
void OnDeinit(const int reason){SqCOT_CloseBlocks();}
