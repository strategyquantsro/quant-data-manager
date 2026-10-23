#ifndef __SQ_COT_SCHEDULER_MQH__
#define __SQ_COT_SCHEDULER_MQH__
#include <SqCOTProtocol.mqh>
#include <SqCOTSchedule.mqh>
struct CotJobState
{
   long lastAttempt,lastChecked,nextAttempt,expected;
   int failures;
   string state,error,job,alertKey;
};
bool COT_ParseJob(const string text,CotJobState &s)
{
   long schema; if(!COT_ParseLong(COT_Field(text,"SCHEMA"),schema) || schema!=1) return false;
   long failures;
   if(!COT_ParseLong(COT_Field(text,"LAST_ATTEMPT"),s.lastAttempt)||!COT_ParseLong(COT_Field(text,"LAST_CHECKED"),s.lastChecked)||
      !COT_ParseLong(COT_Field(text,"NEXT_ATTEMPT"),s.nextAttempt)||!COT_ParseLong(COT_Field(text,"EXPECTED"),s.expected)||
      !COT_ParseLong(COT_Field(text,"FAILURES"),failures)||failures>100000)return false;
   s.failures=(int)failures; s.state=COT_Field(text,"STATE");
   s.error=COT_Field(text,"ERROR"); s.job=COT_Field(text,"JOB"); s.alertKey=COT_Field(text,"ALERT");
   string states="|IDLE|DOWNLOADING|BACKOFF|CONFIG_BLOCKED|WAITING_NEW_REPORT|REPORT_LATE|WAITING_CLIENTS|WAITING_CREDENTIALS|AUTO_DISABLED|POLICY_ERROR|";
   if(s.failures<0 || s.state=="" || StringFind(states,"|"+s.state+"|")<0 ||
      s.lastAttempt>4133980800 || s.lastChecked>4133980800 || s.nextAttempt>4133980800 || s.expected>4133980800) return false;
   // Retry state cannot legitimately defer a worker for months after one failure.
   if(s.state=="BACKOFF" && (s.nextAttempt<s.lastAttempt || s.nextAttempt-s.lastAttempt>86430)) return false;
   return true;
}
bool COT_LoadJob(CotJobState &s)
{
   ZeroMemory(s);s.state="IDLE";
   int lock=COT_Lock("scheduler");if(lock==INVALID_HANDLE)return false;
   string text;CotJobState parsed;
   bool ok=COT_ReadText(COT_CACHE_DIR+"\\scheduler.dat",text)&&COT_ParseJob(text,parsed);
   if(!ok)ok=COT_ReadText(COT_CACHE_DIR+"\\scheduler.dat.previous",text)&&COT_ParseJob(text,parsed);
   FileClose(lock);if(ok)s=parsed;return ok;
}
string COT_JobText(const CotJobState &s)
{
   return "SCHEMA=1\nSTATE="+s.state+"\nERROR="+s.error+"\nJOB="+s.job+
      "\nLAST_ATTEMPT="+IntegerToString(s.lastAttempt)+"\nLAST_CHECKED="+IntegerToString(s.lastChecked)+
      "\nNEXT_ATTEMPT="+IntegerToString(s.nextAttempt)+"\nEXPECTED="+IntegerToString(s.expected)+
      "\nFAILURES="+IntegerToString(s.failures)+"\nALERT="+s.alertKey+"\n";
}
bool COT_SaveJob(const CotJobState &s)
{
   int lock=COT_Lock("scheduler"); if(lock==INVALID_HANDLE) return false;
   string path=COT_CACHE_DIR+"\\scheduler.dat",old,text=COT_JobText(s);
   bool ok=true;CotJobState validOld;
   if(COT_ReadText(path,old)&&COT_ParseJob(old,validOld))ok=COT_WriteText(path+".previous",old);
   if(ok) ok=COT_WriteText(path,text); FileClose(lock); return ok;
}
// Owned by the single service writer. Failed saves must remain retryable.
class CCOTJobWriter
{
private:
   string m_saved;
public:
   CCOTJobWriter() {m_saved="";}
   bool Save(const CotJobState &s)
   {
      string text=COT_JobText(s);
      if(text==m_saved) return true;
      if(!COT_SaveJob(s)) return false;
      m_saved=text;return true;
   }
};
int COT_RetrySeconds(const int failures)
{
   if(failures<=1) return 300; if(failures==2) return 900; if(failures==3) return 1800; return 3600;
}
int COT_MissingRetrySeconds(const long sinceDue)
{
   if(sinceDue<7200)return 900;
   if(sinceDue<86400)return 3600;
   return 14400;
}
bool COT_ConfigError(const string code)
{
   return code=="HTTP_400" || code=="HTTP_401" || code=="HTTP_403" ||
      code=="ERROR_ENDPOINT" || code=="ERROR_WEBREQUEST_NOT_ALLOWED";
}
void COT_JobFailure(CotJobState &s,const string code,const long now)
{
   s.failures=MathMin(100000,s.failures+1); s.error=code;
   s.state=COT_ConfigError(code)?"CONFIG_BLOCKED":"BACKOFF";
   s.nextAttempt=now+COT_RetrySeconds(s.failures);
}
#endif
