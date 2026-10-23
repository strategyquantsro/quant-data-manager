#property version "4.25"
#property description "StrategyQuant COT API 1. Locally observed point-in-time data. No HTTP."
#property indicator_separate_window
#property indicator_buffers 11
#property indicator_plots 11
#include <SqCOTClient.mqh>
input string SeriesId="GC_52W";
input string BrokerTimeProfile=""; // Required: UTC, UTC+120 (minutes), or verified profile filename
input string DatasetSnapshot=""; // Required in Strategy Tester; export a pinned snapshot first
input bool StrictTime=true;       // Only strict observed availability is supported
input int AutoHorizonWeeks=52;    // Used only when SeriesId=AUTO
input string AutoBrokerServer=""; // Empty = current server; snapshot must match export server
double B0[],B1[],B2[],B3[],B4[],B5[],B6[],B7[],B8[],B9[],B10[];
CSqCOTClient Client;
long Generation=0;
bool MappingWasReady=true;
int OnInit()
{
   if(BrokerTimeProfile=="" || !StrictTime) return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,B0,INDICATOR_DATA);SetIndexBuffer(1,B1,INDICATOR_DATA);SetIndexBuffer(2,B2,INDICATOR_DATA);
   SetIndexBuffer(3,B3,INDICATOR_DATA);SetIndexBuffer(4,B4,INDICATOR_DATA);SetIndexBuffer(5,B5,INDICATOR_DATA);
   SetIndexBuffer(6,B6,INDICATOR_DATA);SetIndexBuffer(7,B7,INDICATOR_DATA);SetIndexBuffer(8,B8,INDICATOR_DATA);
   SetIndexBuffer(9,B9,INDICATOR_DATA);SetIndexBuffer(10,B10,INDICATOR_DATA);
   for(int i=0;i<11;i++) {PlotIndexSetInteger(i,PLOT_DRAW_TYPE,DRAW_NONE);PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);}
   bool tester=MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
   if(tester && DatasetSnapshot=="") return INIT_PARAMETERS_INCORRECT;
   bool automatic=SeriesId=="AUTO";
   string server=AutoBrokerServer==""?AccountInfoString(ACCOUNT_SERVER):AutoBrokerServer;
   bool ok=automatic?(DatasetSnapshot==""?Client.OpenAutoLive(_Symbol,server,AutoHorizonWeeks):
      Client.OpenAutoSnapshot(_Symbol,server,AutoHorizonWeeks,DatasetSnapshot,BrokerTimeProfile)):
      (DatasetSnapshot==""?Client.OpenLive(SeriesId):Client.OpenSnapshot(SeriesId,DatasetSnapshot,BrokerTimeProfile));
   if(!ok) {Print("[SQ COT DATA] ",Client.Error());return INIT_FAILED;}
   IndicatorSetString(INDICATOR_SHORTNAME,"SqCOTData API1 "+SeriesId);return INIT_SUCCEEDED;
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   ArraySetAsSeries(time,false);Client.Poll();
   bool changed=Generation!=Client.Generation();Generation=Client.Generation();
   bool mappingReady=Client.MappingReady();
   if(mappingReady!=MappingWasReady)changed=true;
   MappingWasReady=mappingReady;
   int start=changed || prev_calculated<=0 || prev_calculated>rates_total?0:prev_calculated-1;
   for(int i=start;i<rates_total;i++)
   {
      B0[i]=B1[i]=B2[i]=B3[i]=B4[i]=B5[i]=B6[i]=B9[i]=EMPTY_VALUE;
      B7[i]=(double)Generation;B8[i]=0;B10[i]=1;
      long utc; if(!Client.BarUtc(time[i],BrokerTimeProfile,utc)) {B8[i]=3;continue;}
      SqCOTSnapshot s;if(!Client.ReadAt(utc,s)) {if(s.dataStatus==COT_INVALID) B8[i]=2;continue;}
      B0[i]=s.values[0];B1[i]=s.values[1];B2[i]=s.values[2];B3[i]=s.values[3];B4[i]=s.values[4];
      B5[i]=(double)s.reportDate;B6[i]=(double)s.availableAtUtc;B8[i]=1;B9[i]=s.revision;
   }
   return rates_total;
}
void OnDeinit(const int reason) {Client.Close();}
