// Weekly release window, computed without an annual calendar.
#ifndef __SQ_COT_SCHEDULE_MQH__
#define __SQ_COT_SCHEDULE_MQH__
#include <SqCOTStorage.mqh>
struct CotRelease {long due; long dataDate;};
bool COT_ParseLong(const string value,long &out)
{
   int n=StringLen(value); if(n<1 || n>16) return false;
   for(int i=0;i<n;i++) if(StringGetCharacter(value,i)<'0' || StringGetCharacter(value,i)>'9') return false;
   out=StringToInteger(value); return out>=0;
}
datetime COT_Date(const int year,const int month,const int day)
{
   MqlDateTime d={}; d.year=year; d.mon=month; d.day=day; return StructToTime(d);
}
datetime COT_LastSunday(const int year,const int month)
{
   datetime first=month==12?COT_Date(year+1,1,1):COT_Date(year,month+1,1);
   MqlDateTime d;TimeToStruct(first-86400,d);
   return first-86400-d.day_of_week*86400;
}
// EU DST transitions are 01:00 UTC on the last Sunday of March and October.
int COT_PragueOffsetUtc(const long utc)
{
   MqlDateTime d;TimeToStruct((datetime)utc,d);
   long start=(long)COT_LastSunday(d.year,3)+3600,end=(long)COT_LastSunday(d.year,10)+3600;
   return utc>=start && utc<end?120:60;
}
long COT_PragueFridayUtc(const long localFriday,const int hour)
{
   MqlDateTime d;TimeToStruct((datetime)localFriday,d);
   long local=localFriday+hour*3600;
   long start=(long)COT_LastSunday(d.year,3),end=(long)COT_LastSunday(d.year,10);
   return local-(local>=start && local<end?120:60)*60;
}
// target drives acquisition; tradeExpected advances after the grace period.
bool COT_WeeklyExpectation(const long now,const int hour,const int lagMinutes,const int graceMinutes,
   long &target,long &tradeExpected,long &due,long &next)
{
   target=0;tradeExpected=0;due=0;next=0;
   if(now<=0 || hour<0 || hour>23 || lagMinutes<0 || lagMinutes>1440 ||
      graceMinutes<0 || graceMinutes>4320)return false;
   long localNow=now+(long)COT_PragueOffsetUtc(now)*60;
   MqlDateTime d;TimeToStruct((datetime)localNow,d);
   long localFriday=(long)COT_Date(d.year,d.mon,d.day)-((d.day_of_week+2)%7)*86400;
   long at=COT_PragueFridayUtc(localFriday,hour)+(long)lagMinutes*60;
   if(now<at)localFriday-=7*86400;
   due=COT_PragueFridayUtc(localFriday,hour)+(long)lagMinutes*60;
   next=COT_PragueFridayUtc(localFriday+7*86400,hour)+(long)lagMinutes*60;
   target=localFriday;
   tradeExpected=now<due+(long)graceMinutes*60?localFriday-7*86400:localFriday;
   return true;
}
// A parser solely for previously exported immutable snapshots. No built-in dates.
bool COT_LoadLegacyCalendar(CotRelease &rows[],long &validUntil,const string path)
{
   ArrayFree(rows);validUntil=0;
   string text,lines[];if(!COT_ReadText(path,text))return false;
   StringReplace(text,"\r","");int n=StringSplit(text,'\n',lines);
   if(n<3 || lines[0]!="SQCOT_CALENDAR_1" || !COT_ParseLong(lines[1],validUntil))return false;
   for(int i=2;i<n;i++)
   {
      if(lines[i]=="")continue;
      string f[];CotRelease r;
      if(StringSplit(lines[i],',',f)!=2 || !COT_ParseLong(f[0],r.due) ||
         !COT_ParseLong(f[1],r.dataDate) || r.due<=0 || r.dataDate<=0 || r.dataDate>r.due ||
         (ArraySize(rows)>0 && rows[ArraySize(rows)-1].due>=r.due))return false;
      int k=ArraySize(rows);if(k>=1000)return false;ArrayResize(rows,k+1);rows[k]=r;
   }
   return ArraySize(rows)>0 && validUntil>rows[ArraySize(rows)-1].due;
}
bool COT_LegacyExpected(const long now,const int lagMinutes,long &expected,long &due,long &next,
   const CotRelease &rows[],const long until)
{
   expected=0;due=0;next=0;
   if(lagMinutes<0 || lagMinutes>10080 || now>=until)return false;
   for(int i=0;i<ArraySize(rows);i++)
   {
      long at=rows[i].due+(long)lagMinutes*60;
      if(at<=now){expected=rows[i].dataDate;due=at;}else{next=at;break;}
   }
   return expected>0;
}
// Supported fixed offsets and explicit historical offset transition files. No inferred broker DST.
bool COT_BarUtc(const datetime bar,const string profile,long &utc)
{
   if(profile=="UTC") {utc=(long)bar; return true;}
   if(StringFind(profile,"UTC+")==0 || StringFind(profile,"UTC-")==0)
   {
      long minutes; if(!COT_ParseLong(StringSubstr(profile,4),minutes) || minutes>840) return false;
      utc=(long)bar-(StringGetCharacter(profile,3)=='+'?1:-1)*minutes*60; return true;
   }
   // profile is a safe filename in the shared v2 profiles directory.
   if(!COT_SafeName(profile)) return false;
   string text,lines[]; if(!COT_ReadText(COT_CACHE_DIR+"\\profiles\\"+profile+".csv",text)) return false;
   return COT_ProfileUtc(bar,text,utc);
}
bool COT_ProfileUtc(const datetime bar,string text,long &utc)
{
   string lines[];
   StringReplace(text,"\r",""); int count=StringSplit(text,'\n',lines),matches=0;
   // Each row: UTC start inclusive, UTC end exclusive, signed offset minutes.
   for(int i=0;i<count;i++)
   {
      if(lines[i]=="") continue; string f[]; long start,end,offset;
      if(StringSplit(lines[i],',',f)!=3 || !COT_ParseLong(f[0],start) || !COT_ParseLong(f[1],end)) return false;
      string number=f[2]; bool neg=StringFind(number,"-")==0;
      if(neg) number=StringSubstr(number,1);
      if(!COT_ParseLong(number,offset) || offset>840 || end<=start) return false;
      if(neg) offset=-offset;
      long candidate=(long)bar-offset*60;
      if(candidate>=start && candidate<end) {utc=candidate; matches++;}
   }
   return matches==1; // ambiguous autumn broker timestamps fail closed.
}
#endif
