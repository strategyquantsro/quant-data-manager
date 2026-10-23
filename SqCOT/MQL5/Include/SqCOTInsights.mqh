// Shared descriptive COT analytics. Newest report first; no price/trade inference.
#ifndef __SQ_COT_INSIGHTS_MQH__
#define __SQ_COT_INSIGHTS_MQH__
#include <SqCOTClient.mqh>
enum ENUM_COT_EVENT
{
   COT_ENTER_HIGH=1, COT_ENTER_LOW=2, COT_EXIT_HIGH=4, COT_EXIT_LOW=8,
   COT_LARGE_RISE=16, COT_LARGE_FALL=32, COT_PERSIST_RISE=64, COT_PERSIST_FALL=128,
   COT_ALIGN_HIGH=256, COT_ALIGN_LOW=512, COT_HORIZON_CONFLICT=1024
};
struct SqCOTInsight
{
   bool valid,delta1Valid,delta4Valid,paired;
   double level,delta1,delta4,otherLevel;
   int events,zone,extremeReports,horizon;
   bool durationCapped;
   long reportDate,availableAtUtc,generation,evaluatedAtUtc;
   int revision;
   ENUM_COT_DATA_STATUS dataStatus;
};
int COT_InsightZone(const double v) {return v>=0.8?1:(v<=0.2?-1:0);}
int COT_HorizonState(const double a,const double b)
{
   int x=COT_InsightZone(a),y=COT_InsightZone(b);
   if(x!=0 && x==y) return x;
   if(x*y==-1) return 2;
   return 0;
}
bool COT_InsightValue(const double v) {return MathIsValidNumber(v) && v>=0 && v<=1;}
void COT_Analyze(const double &values[],const double &other[],SqCOTInsight &s)
{
   ZeroMemory(s);s.dataStatus=COT_MISSING;
   s.level=EMPTY_VALUE;s.otherLevel=EMPTY_VALUE;
   int n=ArraySize(values);
   if(n<1 || !COT_InsightValue(values[0])) return;
   s.valid=true;s.level=values[0];s.zone=COT_InsightZone(s.level);
   s.delta1Valid=n>1 && COT_InsightValue(values[1]);
   s.delta4Valid=n>4 && COT_InsightValue(values[4]);
   if(s.delta1Valid)
   {
      s.delta1=100*(values[0]-values[1]);int previous=COT_InsightZone(values[1]);
      if(s.zone==1 && previous!=1) s.events|=COT_ENTER_HIGH;
      if(s.zone==-1 && previous!=-1) s.events|=COT_ENTER_LOW;
      if(previous==1 && s.zone!=1) s.events|=COT_EXIT_HIGH;
      if(previous==-1 && s.zone!=-1) s.events|=COT_EXIT_LOW;
      if(s.delta1>=10-1e-9) s.events|=COT_LARGE_RISE;
      if(s.delta1<=-10+1e-9) s.events|=COT_LARGE_FALL;
   }
   if(s.delta4Valid) s.delta4=100*(values[0]-values[4]);
   if(s.zone!=0)
   {
      for(int i=0;i<n;i++)
      {
         if(!COT_InsightValue(values[i]) || COT_InsightZone(values[i])!=s.zone) break;
         s.extremeReports++;
      }
      s.durationCapped=s.extremeReports==n;
   }
   // Emit persistence only at the third consecutive strict move, not every report.
   if(n>=5 && COT_InsightValue(values[1]) && COT_InsightValue(values[2]) &&
      COT_InsightValue(values[3]) && COT_InsightValue(values[4]))
   {
      if(values[0]>values[1] && values[1]>values[2] && values[2]>values[3] && values[3]<=values[4]) s.events|=COT_PERSIST_RISE;
      if(values[0]<values[1] && values[1]<values[2] && values[2]<values[3] && values[3]>=values[4]) s.events|=COT_PERSIST_FALL;
   }
   s.paired=ArraySize(other)>0 && COT_InsightValue(other[0]);
   if(!s.paired) return;
   s.otherLevel=other[0];s.horizon=COT_HorizonState(values[0],other[0]);
   if(!s.delta1Valid || ArraySize(other)<2 || !COT_InsightValue(other[1])) return;
   int previous=COT_HorizonState(values[1],other[1]);
   if(s.horizon!=previous)
   {
      if(s.horizon==1) s.events|=COT_ALIGN_HIGH;
      if(s.horizon==-1) s.events|=COT_ALIGN_LOW;
      if(s.horizon==2) s.events|=COT_HORIZON_CONFLICT;
   }
}
string COT_InsightIndex(const double v) {return COT_InsightValue(v)?DoubleToString(v*100,0)+"/100":"--";}
string COT_InsightDelta(const double v) {return (v>0?"+":"")+DoubleToString(v,1);}
string COT_InsightEvents(const int events)
{
   int flags[11]={1,2,4,8,16,32,64,128,256,512,1024};
   string labels[11]={"Entered high","Entered low","Exited high","Exited low","Large rise","Large fall",
      "3 rising moves","3 falling moves","Horizons high","Horizons low","Horizon conflict"};
   string text="";
   for(int i=0;i<11;i++) if((events&flags[i])!=0) {if(text!="") text+="; ";text+=labels[i];}
   return text==""?"No new event":text;
}
string COT_InsightHorizon(const SqCOTInsight &s)
{
   if(!s.paired) return "Comparison unavailable";
   if(s.horizon==2) return "Opposite extremes";
   if(s.horizon==1) return "Both high";
   if(s.horizon==-1) return "Both low";
   return "No shared extreme";
}
// Reads every input as known at asOf. Pair only identical report dates, dataset,
// generation and matching market/opposite horizons. Missing comparison is explicit.
bool COT_ReadInsight(CSqCOTClient &client,CSqCOTClient &comparison,const long asOf,
                     SqCOTInsight &out,const int reportShift=0,const int field=0)
{
   ZeroMemory(out);out.dataStatus=COT_MISSING;
   out.level=EMPTY_VALUE;out.otherLevel=EMPTY_VALUE;
   if(reportShift<0 || field<0 || field>4) return false;
   SqCOTSnapshot latest;
   if(!client.ReadAt(asOf,latest,reportShift)) return false;
   string series=client.Series(),peer=comparison.Series();
   int suffix=StringFind(series,"_52W");
   string expectedPeer="";
   if(suffix>0 && suffix+4==StringLen(series)) expectedPeer=StringSubstr(series,0,suffix)+"_156W";
   else {suffix=StringFind(series,"_156W");if(suffix>0 && suffix+5==StringLen(series)) expectedPeer=StringSubstr(series,0,suffix)+"_52W";}
   bool paired=peer==expectedPeer && expectedPeer!="" && client.Generation()==comparison.Generation() &&
               client.DatasetKey()==comparison.DatasetKey();
   double values[],others[];ArrayResize(values,12);ArrayResize(others,12);
   ArrayInitialize(values,EMPTY_VALUE);ArrayInitialize(others,EMPTY_VALUE);
   int count=0;long observed=latest.availableAtUtc;
   for(int i=0;i<12;i++)
   {
      SqCOTSnapshot a,b;
      if(!client.ReadAt(asOf,a,reportShift+i)) break;
      values[i]=a.values[field];count++;
      observed=MathMax(observed,a.availableAtUtc);
      if(paired && comparison.ReadAt(asOf,b,reportShift+i) && a.reportDate==b.reportDate)
      {others[i]=b.values[field];observed=MathMax(observed,b.availableAtUtc);}
   }
   ArrayResize(values,count);ArrayResize(others,count);COT_Analyze(values,others,out);
   out.reportDate=latest.reportDate;out.availableAtUtc=observed;out.generation=latest.generation;
   out.evaluatedAtUtc=asOf;out.revision=latest.revision;out.dataStatus=latest.dataStatus;
   return out.valid;
}
#endif
