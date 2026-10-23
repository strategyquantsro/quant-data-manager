#property version "4.00"
#property description "Read-only iCustom example; no trading operations."
#property tester_indicator "SqCOTData.ex5"
#include <SqCOTClient.mqh>
input string Series="GC_52W";
input string BrokerTimeProfile=""; // Must explicitly match broker history
input string SnapshotId="";
int Handle=INVALID_HANDLE;
CSqCOTClient Status;
int OnInit()
{
   bool tester=MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION);
   if(BrokerTimeProfile=="" || (tester && SnapshotId==""))return INIT_PARAMETERS_INCORRECT;
   bool ok=tester?Status.OpenSnapshot(Series,SnapshotId,BrokerTimeProfile):Status.OpenLive(Series);
   if(!ok)return INIT_FAILED;
   Handle=iCustom(_Symbol,_Period,"SqCOTData",Series,BrokerTimeProfile,SnapshotId,true);
   if(Handle==INVALID_HANDLE){Status.Close();return INIT_FAILED;}
   return INIT_SUCCEEDED;
}
bool ReadOne(const int field,const int shift,double &value)
{double a[1];if(CopyBuffer(Handle,field,shift,1,a)!=1)return false;value=a[0];return MathIsValidNumber(value)&&value!=EMPTY_VALUE;}
void OnTick()
{
   Status.Poll();SqCOTSnapshot latest;
   if(!Status.ReadLatest(latest)||!Status.CanTrade(latest)||BarsCalculated(Handle)<2)return;
   const int shift=1;datetime bar=iTime(_Symbol,_Period,shift);
   double first,last,api,row,cpi;
   if(!ReadOne(7,shift,first)||!ReadOne(10,shift,api)||api!=1||
      !ReadOne(8,shift,row)||row!=1||!ReadOne(0,shift,cpi)||!COT_ValueValid(cpi)||
      !ReadOne(7,shift,last)||first!=last||last!=(double)latest.generation||iTime(_Symbol,_Period,shift)!=bar)return;
   // cpi is known at this bar's OPEN, not necessarily the latest weekly report.
   static datetime shown=0;if(shown==bar)return;shown=bar;
   Print("[COT BUFFERS] bar=",bar," CPI hedgers=",cpi," generation=",(long)last);
}
void OnDeinit(const int reason){if(Handle!=INVALID_HANDLE)IndicatorRelease(Handle);Status.Close();}
