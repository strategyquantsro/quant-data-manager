// Adapter for the encoded handles used by StrategyQuant COT blocks: 0..4=52W, 10..14=156W.
// Including EA defines g_currentBar before SqCOTBlocks.mqh, as in the original interface.
#ifndef __SQ_COT_STRATEGY_MQH__
#define __SQ_COT_STRATEGY_MQH__
#include <SqCOTClient.mqh>
struct CotReportCursor {long asOf;int shift;};
CSqCOTClient g_cotBlockClients[2];
CotReportCursor g_cotCursors[];
bool g_cotBlockConfigured=false,g_cotBlockInvalid=true;
string g_cotBlockProfile="";
datetime g_cotBlockBar=0;
#define COT_CURSOR_BASE 100000000
bool SqCOT_ConfigureBlocks(const string market,const string profile,const string snapshot="")
{
   g_cotBlockConfigured=false;ArrayFree(g_cotCursors);g_cotBlockProfile=profile;
   if(!COT_SafeName(market)||profile=="")return false;
   bool tester=MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION);
   for(int i=0;i<2;i++)
   {
      string series=market+(i==0?"_52W":"_156W");
      bool ok=tester?g_cotBlockClients[i].OpenSnapshot(series,snapshot,profile):g_cotBlockClients[i].OpenLive(series);
      if(!ok)return false;
   }
   g_cotBlockConfigured=true;return true;
}
bool SqCOT_BeginEvaluation()
{
   g_cotBlockInvalid=!g_cotBlockConfigured;
   datetime bar=iTime(NULL,0,g_currentBar);
   if(bar!=g_cotBlockBar){ArrayFree(g_cotCursors);g_cotBlockBar=bar;}
   if(!g_cotBlockConfigured)return false;
   SqCOTSnapshot s[];
   if(!COT_ReadBatch(g_cotBlockClients,s)||s[0].reportDate!=s[1].reportDate)g_cotBlockInvalid=true;
   return !g_cotBlockInvalid;
}
bool SqCOT_Cursor(const int bar,long &asOf,int &shift)
{
   if(bar>=COT_CURSOR_BASE)
   {
      int i=bar-COT_CURSOR_BASE;
      if(i<0||i>=ArraySize(g_cotCursors))return false;
      asOf=g_cotCursors[i].asOf;shift=g_cotCursors[i].shift;return true;
   }
   if(bar<0)return false;datetime t=iTime(NULL,0,bar);shift=0;
   return t>0&&g_cotBlockClients[0].BarUtc(t,g_cotBlockProfile,asOf);
}
int SqCOT_ReportCursor(const int startBar,const int reportShift)
{
   long asOf;int shift;
   if(reportShift<0||!SqCOT_Cursor(startBar,asOf,shift)){g_cotBlockInvalid=true;return -1;}
   if(reportShift==0)return startBar;
   shift+=reportShift;
   for(int i=0;i<ArraySize(g_cotCursors);i++)if(g_cotCursors[i].asOf==asOf&&g_cotCursors[i].shift==shift)return COT_CURSOR_BASE+i;
   int n=ArraySize(g_cotCursors);
   if(n>=4096){g_cotBlockInvalid=true;return -1;}
   ArrayResize(g_cotCursors,n+1);g_cotCursors[n].asOf=asOf;g_cotCursors[n].shift=shift;
   return COT_CURSOR_BASE+n;
}
double SqCOT_StrategyValue(const int handle,const int field,const int relativeShift)
{
   int series=handle>=10?1:0;
   if(!g_cotBlockConfigured||field<0||field>4||!((handle>=0&&handle<=4)||(handle>=10&&handle<=14)))
   {g_cotBlockInvalid=true;return EMPTY_VALUE;}
   long asOf;int reportShift;
   if(!SqCOT_Cursor(g_currentBar+relativeShift,asOf,reportShift)){g_cotBlockInvalid=true;return EMPTY_VALUE;}
   SqCOTSnapshot s;
   if(!g_cotBlockClients[series].ReadAt(asOf,s,reportShift)||!COT_ValueValid(s.values[field]))
   {g_cotBlockInvalid=true;return EMPTY_VALUE;}
   return s.values[field];
}
bool SqCOT_BlockResult(const bool value){return !g_cotBlockInvalid&&value;}
double SqCOT_NumberResult(const double value){return !g_cotBlockInvalid&&MathIsValidNumber(value)?value:EMPTY_VALUE;}
void SqCOT_CloseBlocks(){for(int i=0;i<2;i++)g_cotBlockClients[i].Close();g_cotBlockConfigured=false;g_cotBlockInvalid=true;ArrayFree(g_cotCursors);}
#endif
