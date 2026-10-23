// One weekly readiness rule for the service and all live clients.
#ifndef __SQ_COT_FRESHNESS_MQH__
#define __SQ_COT_FRESHNESS_MQH__
#include <SqCOTProtocol.mqh>
#include <SqCOTSchedule.mqh>
struct CotFreshnessPolicy
{
   int releaseHour,lagMinutes,graceMinutes;
   bool legacy,allowFallback;
   int maxAgeDays;
};
bool COT_ParseFreshnessPolicy(const string text,CotFreshnessPolicy &policy)
{
   policy.releaseHour=21;policy.lagMinutes=0;policy.graceMinutes=120;
   policy.legacy=false;policy.allowFallback=false;policy.maxAgeDays=14;
   if(COT_Field(text,"POLICY_SCHEMA")=="2")
   {
      long hour,lag,grace;
      if(COT_Field(text,"RELEASE_ZONE")!="EUROPE_PRAGUE" ||
         !COT_ParseLong(COT_Field(text,"RELEASE_HOUR"),hour) || hour>23 ||
         !COT_ParseLong(COT_Field(text,"PROBE_DELAY_MINUTES"),lag) || lag>1440 ||
         !COT_ParseLong(COT_Field(text,"GRACE_MINUTES"),grace) || grace>4320)return false;
      policy.releaseHour=(int)hour;policy.lagMinutes=(int)lag;policy.graceMinutes=(int)grace;
      return true;
   }
   if(COT_Field(text,"POLICY_SCHEMA")!="")return false;
   // Read-only compatibility for previously exported snapshots.
   long lag,age;string enabled=COT_Field(text,"ALLOW_CALENDAR_FALLBACK");
   string limit=COT_Field(text,"MAX_REPORT_AGE_DAYS");
   if(!COT_ParseLong(COT_Field(text,"LAG_MINUTES"),lag) || lag>10080) return false;
   policy.lagMinutes=(int)lag;policy.legacy=true;
   // Old immutable snapshots retain their original calendar-only behavior.
   if(enabled=="" && limit=="") return true;
   if((enabled!="0" && enabled!="1") || !COT_ParseLong(limit,age) || age<7 || age>28) return false;
   policy.allowFallback=enabled=="1";policy.maxAgeDays=(int)age;return true;
}
string COT_WeeklyPolicyText(const int hour,const int lag,const int grace)
{
   return "POLICY_SCHEMA=2\nRELEASE_ZONE=EUROPE_PRAGUE\nRELEASE_HOUR="+IntegerToString(hour)+
      "\nPROBE_DELAY_MINUTES="+IntegerToString(lag)+"\nGRACE_MINUTES="+IntegerToString(grace)+"\n";
}
bool COT_ReportWithinAge(const long date,const long now,const int days)
{
   return days>=7 && days<=28 && date>0 && date<=now && now-date<=(long)days*86400;
}
bool COT_ReportReady(const long date,const long now,const bool calendarKnown,
   const long expected,const CotFreshnessPolicy &policy)
{
   if(date<=0 || date>now) return false;
   if(!policy.legacy)return expected>0 && date>=expected;
   if(calendarKnown) return expected>0 && date>=expected;
   return policy.allowFallback && COT_ReportWithinAge(date,now,policy.maxAgeDays);
}
#endif
