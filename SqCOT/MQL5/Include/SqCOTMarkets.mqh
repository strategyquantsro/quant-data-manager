// Read-only market summaries and UI preferences. No downloads or trading.
#ifndef __SQ_COT_MARKETS_MQH__
#define __SQ_COT_MARKETS_MQH__
#include <SqCOTReader.mqh>
#include <SqCOTInsights.mqh>

struct CotMarketRow
{
   string id,base,name;
   datetime date,previous;
   double values[5],prior[5];
   bool readable;
   double trail[60],peer[2]; // newest first, 12 observations per field
   datetime dates[12];
   SqCOTInsight insights[2];
};
struct CotMarketPrefs
{
   bool expanded,favoritesOnly,details;
   int weeks,metric,sort,page;
   string selected,favorites,search;
   int view;
   bool compare,eventsOnly;
   int autoMode,autoWeeks;
};
string COT_MarketBase(string id)
{
   StringToUpper(id);
   int n=StringLen(id);
   if(n>4 && StringSubstr(id,n-4)=="_52W") return StringSubstr(id,0,n-4);
   if(n>5 && StringSubstr(id,n-5)=="_156W") return StringSubstr(id,0,n-5);
   return id;
}
int COT_MarketWeeks(string id)
{
   StringToUpper(id);
   if(StringLen(id)>4 && StringSubstr(id,StringLen(id)-4)=="_52W") return 52;
   if(StringLen(id)>5 && StringSubstr(id,StringLen(id)-5)=="_156W") return 156;
   return 0;
}
string COT_MarketName(const string base)
{
   if(base=="GC") return "Gold";
   if(base=="SI") return "Silver";
   if(base=="HG") return "Copper";
   if(base=="PL") return "Platinum";
   if(base=="PA") return "Palladium";
   if(base=="6E") return "Euro";
   if(base=="6B") return "British pound";
   if(base=="6J") return "Japanese yen";
   if(base=="6A") return "Australian dollar";
   if(base=="6C") return "Canadian dollar";
   if(base=="6S") return "Swiss franc";
   if(base=="6N") return "New Zealand dollar";
   if(base=="DX") return "US Dollar Index";
   if(base=="ES") return "S&P 500";
   if(base=="NQ") return "Nasdaq 100";
   if(base=="YM") return "Dow Jones";
   if(base=="CL") return "Crude oil";
   if(base=="NG") return "Natural gas";
   if(base=="ZB") return "US Treasury bonds";
   if(base=="ZN") return "10Y Treasury notes";
   if(base=="ZF") return "5Y Treasury notes";
   if(base=="ZT") return "2Y Treasury notes";
   if(base=="ZC") return "Corn";
   if(base=="ZW") return "Wheat";
   if(base=="ZS") return "Soybeans";
   if(base=="KC") return "Coffee";
   if(base=="SB") return "Sugar";
   if(base=="CC") return "Cocoa";
   if(base=="CT") return "Cotton";
   if(base=="LE") return "Live cattle";
   if(base=="HE") return "Lean hogs";
   if(base=="BTC") return "Bitcoin";
   return base; // Unknown provider identifiers remain visible, never guessed.
}
bool COT_MarketHasFavorite(const string favorites,const string base)
{
   return StringFind(","+favorites+",",","+base+",")>=0;
}
string COT_MarketFavorites(const string list)
{
   string parts[],result="";
   int count=StringSplit(list,',',parts);
   for(int i=0;i<count && i<COT_MAX_SERIES;i++)
   {
      string base=COT_MarketBase(COT_Trim(parts[i]));
      if(!COT_SafeName(base) || COT_MarketHasFavorite(result,base)) continue;
      if(result!="") result+=",";
      result+=base;
   }
   return result;
}
void COT_MarketToggleFavorite(CotMarketPrefs &p,const string base)
{
   if(!COT_MarketHasFavorite(p.favorites,base))
   {p.favorites=COT_MarketFavorites(p.favorites+","+base); return;}
   string parts[],result="";
   int count=StringSplit(p.favorites,',',parts);
   for(int i=0;i<count;i++)
      if(parts[i]!=base) {if(result!="") result+=","; result+=parts[i];}
   p.favorites=result;
}
void COT_MarketDefaults(CotMarketPrefs &p,const string id,const string favorites)
{
   p.expanded=false; p.favoritesOnly=true; p.details=false;
   p.weeks=COT_MarketWeeks(id)==156?156:52;
   p.metric=0; p.sort=0; p.page=0;
   p.selected=id; StringToUpper(p.selected);
   p.view=0;p.compare=false;p.eventsOnly=false;p.autoMode=-1;p.autoWeeks=52;
   p.favorites=COT_MarketFavorites(favorites); p.search="";
}
double COT_MarketValue(const CotBinRecord &r,const int field)
{
   switch(field)
   {
      case 0: return r.cpihedg;
      case 1: return r.ctihedg;
      case 2: return r.cpispec;
      case 3: return r.ctispec;
      case 4: return r.cpismall;
   }
   return -1;
}
bool COT_MarketValid(const double value)
{
   return MathIsValidNumber(value) && value>=0 && value<=1;
}
void COT_MarketSummary(const string id,const CotBinRecord &records[],const datetime asOf,CotMarketRow &row)
{
   row.id=id; StringToUpper(row.id);
   row.base=COT_MarketBase(row.id); row.name=COT_MarketName(row.base);
   row.date=0; row.previous=0; row.readable=false;
   ArrayInitialize(row.trail,EMPTY_VALUE);ArrayInitialize(row.dates,0);ArrayInitialize(row.peer,EMPTY_VALUE);
   ZeroMemory(row.insights);
   for(int f=0;f<5;f++) {row.values[f]=-1; row.prior[f]=-1;}
   int last=COT_BinarySearch(records,ArraySize(records),asOf);
   if(last<0) return;
   row.readable=true; row.date=(datetime)records[last].date;
   if(last>0) row.previous=(datetime)records[last-1].date;
   for(int f=0;f<5;f++)
   {
      row.values[f]=COT_MarketValue(records[last],f);
      if(last>0) row.prior[f]=COT_MarketValue(records[last-1],f);
      for(int k=0;k<12 && last-k>=0;k++) row.trail[f*12+k]=COT_MarketValue(records[last-k],f);
   }
   for(int k=0;k<12 && last-k>=0;k++) row.dates[k]=(datetime)records[last-k].date;
   double values[],other[];ArrayResize(values,MathMin(12,last+1));
   for(int f=0;f<2;f++)
   {for(int k=0;k<ArraySize(values);k++) values[k]=row.trail[f*12+k];COT_Analyze(values,other,row.insights[f]);}
}
// Read into short-lived arrays rather than registering every market in the
// reader. A removed non-selected market must not block detail cache reloads.
bool COT_MarketBuild(const int weeks,const datetime asOf,CotMarketRow &rows[])
{
   ArrayFree(rows);
   if(!COT_Initialize()) return false;
   for(int i=0;i<g_cotAvailableCount;i++)
   {
      string id=g_cotAvailableIds[i];
      if(COT_MarketWeeks(id)!=weeks) continue;
      CotBinRecord records[];
      string error="";
      bool csv=g_cotUseCsvFallback ||
               (g_cotDataDir==COT_CACHE_DIR && !FileIsExist(g_cotDataDir+"\\"+id+".bin",COT_FILE_SCOPE));
      if(csv)
      {
         uchar bytes[];
         if(COT_ReadBytes(COT_CSV_DIR+"\\"+id+".csv",bytes,g_cotCsvInCommon?COT_FILE_SCOPE:0,8388608))
            COT_ParseCsv(CharArrayToString(bytes,0,ArraySize(bytes),CP_UTF8),records,error);
      }
      else COT_ReadBin(g_cotDataDir+"\\"+id+".bin",records,error);
      int n=ArraySize(rows); ArrayResize(rows,n+1);
      COT_MarketSummary(id,records,asOf,rows[n]);
      string peerId=rows[n].base+(weeks==52?"_156W":"_52W");
      CotBinRecord peerRecords[];string peerError;
      // A comparison is optional; never substitute another report date.
      if(COT_ReadBin(g_cotDataDir+"\\"+peerId+".bin",peerRecords,peerError))
      {
         double values[],others[];int count=0;
         while(count<12 && rows[n].dates[count]>0) count++;
         ArrayResize(values,count);ArrayResize(others,count);
         for(int f=0;f<2;f++)
         {
            ArrayInitialize(others,EMPTY_VALUE);
            for(int k=0;k<count;k++)
            {
               values[k]=rows[n].trail[f*12+k];
               int at=COT_BinarySearch(peerRecords,ArraySize(peerRecords),rows[n].dates[k]);
               if(at>=0 && peerRecords[at].date==(long)rows[n].dates[k]) others[k]=COT_MarketValue(peerRecords[at],f);
            }
            COT_Analyze(values,others,rows[n].insights[f]);
            rows[n].peer[f]=rows[n].insights[f].otherLevel;
         }
      }
   }
   return true;
}
bool COT_MarketDelta(const CotMarketRow &row,const int field,double &delta)
{
   delta=0;
   if(field<0 || field>4 || row.previous==0 ||
      !COT_MarketValid(row.values[field]) || !COT_MarketValid(row.prior[field])) return false;
   delta=100*(row.values[field]-row.prior[field]);
   return true;
}
string COT_MarketPercent(const double value)
{
   return COT_InsightIndex(value);
}
string COT_MarketDeltaText(const CotMarketRow &row,const int field)
{
   double delta;
   if(!COT_MarketDelta(row,field,delta)) return "--";
   return (delta>0?"+":"")+DoubleToString(delta,1);
}
// Descriptive labels, not trade recommendations. Only the selected hedger
// metric is compared, and missing reports are never replaced with older ones.
string COT_MarketEvent(const CotMarketRow &row,const int field)
{
   if(!row.readable) return "No data";
   double v=row.values[field],prev=row.prior[field],delta;
   if(!COT_MarketValid(v)) return "Missing";
   if(field>=0 && field<2 && row.insights[field].events!=0) return COT_InsightEvents(row.insights[field].events);
   if(COT_MarketValid(prev) && v>=0.8 && prev<0.8) return "Entered high";
   if(COT_MarketValid(prev) && v<=0.2 && prev>0.2) return "Entered low";
   if(COT_MarketDelta(row,field,delta) && MathAbs(delta)>=10) return "Large change";
   if(v>=0.8) return "High zone";
   if(v<=0.2) return "Low zone";
   return "--";
}
bool COT_MarketBefore(const CotMarketRow &a,const CotMarketRow &b,const int sort,const int field)
{
   if(sort==1)
   {
      double ad,bd;
      bool av=COT_MarketDelta(a,field,ad),bv=COT_MarketDelta(b,field,bd);
      if(av!=bv) return av;
      if(av && MathAbs(ad)!=MathAbs(bd)) return MathAbs(ad)>MathAbs(bd);
   }
   if(sort==2)
   {
      bool av=COT_MarketValid(a.values[field]),bv=COT_MarketValid(b.values[field]);
      if(av!=bv) return av;
      if(av && a.values[field]!=b.values[field]) return a.values[field]>b.values[field];
   }
   int name=StringCompare(a.name,b.name);
   return name!=0?name<0:StringCompare(a.id,b.id)<0;
}
void COT_MarketFilter(const CotMarketRow &rows[],const CotMarketPrefs &p,int &order[])
{
   ArrayFree(order);
   string search=p.search; StringToUpper(search);
   for(int i=0;i<ArraySize(rows);i++)
   {
      if(p.favoritesOnly && !COT_MarketHasFavorite(p.favorites,rows[i].base)) continue;
      if(p.eventsOnly && rows[i].insights[p.metric].events==0) continue;
      string match=rows[i].name+" "+rows[i].id; StringToUpper(match);
      if(search!="" && StringFind(match,search)<0) continue;
      int n=ArraySize(order); ArrayResize(order,n+1); order[n]=i;
      for(int j=n;j>0 && COT_MarketBefore(rows[order[j]],rows[order[j-1]],p.sort,p.metric);j--)
      {int tmp=order[j-1]; order[j-1]=order[j]; order[j]=tmp;}
   }
}
string COT_MarketSerialize(const CotMarketPrefs &p)
{
   return "COT_UI_1\n"+p.selected+"\n"+IntegerToString(p.weeks)+"\n"+
      IntegerToString(p.metric)+"\n"+IntegerToString(p.sort)+"\n"+
      IntegerToString((int)p.expanded)+"\n"+IntegerToString((int)p.favoritesOnly)+"\n"+
      IntegerToString((int)p.details)+"\n"+p.favorites+"\n"+p.search+"\n"+
      IntegerToString(p.view)+"\n"+IntegerToString((int)p.compare)+"\n"+IntegerToString((int)p.eventsOnly)+"\n"+IntegerToString(p.autoMode)+"\n"+IntegerToString(p.autoWeeks)+"\n";
}
bool COT_MarketParse(string text,CotMarketPrefs &p)
{
   StringReplace(text,"\r","");
   string lines[];
   if(StringSplit(text,'\n',lines)<10 || lines[0]!="COT_UI_1" || !COT_SafeName(lines[1]) ||
      (lines[2]!="52" && lines[2]!="156") || (lines[3]!="0" && lines[3]!="1") ||
      (lines[4]!="0" && lines[4]!="1" && lines[4]!="2")) return false;
   for(int i=5;i<=7;i++) if(lines[i]!="0" && lines[i]!="1") return false;
   if(StringLen(lines[8])>4096 || StringLen(lines[9])>64) return false;
   p.selected=lines[1]; StringToUpper(p.selected);
   p.weeks=(int)StringToInteger(lines[2]); p.metric=(int)StringToInteger(lines[3]);
   p.sort=(int)StringToInteger(lines[4]); p.expanded=lines[5]=="1";
   p.favoritesOnly=lines[6]=="1"; p.details=lines[7]=="1";
   p.favorites=COT_MarketFavorites(lines[8]); p.search=lines[9]; p.page=0;
   p.view=0;p.compare=false;p.eventsOnly=false;p.autoMode=-1;p.autoWeeks=52;
   if(ArraySize(lines)>=13)
   {
      if(lines[10]=="1" || lines[10]=="2" || lines[10]=="3") p.view=(int)StringToInteger(lines[10]);
      p.compare=lines[11]=="1";p.eventsOnly=lines[12]=="1";
   }
   if(ArraySize(lines)>=15 && (lines[13]=="0" || lines[13]=="1") && (lines[14]=="52" || lines[14]=="156"))
   {p.autoMode=(int)StringToInteger(lines[13]);p.autoWeeks=(int)StringToInteger(lines[14]);}
   if(p.view>0) p.expanded=false;
   return true;
}
bool COT_MarketSavePrefs(const string path,const CotMarketPrefs &p)
{
   // Terminal-local file; no license, account or chart trading settings.
   uchar bytes[];
   int n=StringToCharArray(COT_MarketSerialize(p),bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   int h=FileOpen(path+".tmp",FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE) return false;
   bool ok=FileWriteArray(h,bytes,0,n)==(uint)n;
   FileFlush(h); FileClose(h);
   return ok && FileMove(path+".tmp",0,path,FILE_REWRITE);
}
#endif
