// Shared COT file format and validated, network-free storage functions.
#ifndef __SQ_COT_STORAGE_MQH__
#define __SQ_COT_STORAGE_MQH__
// Test harnesses may supply an isolated file scope and deterministic clock.
#ifndef COT_FILE_SCOPE
#define COT_FILE_SCOPE FILE_COMMON
#endif
#ifndef COT_NOW
#define COT_NOW TimeGMT
#endif

#ifndef COT_CACHE_DIR
#define COT_CACHE_DIR       "StrategyQuant\\COT\\v2"
#endif
#define COT_MANIFEST_FILE   COT_CACHE_DIR "\\manifest.dat"
#define COT_METADATA_FILE   COT_CACHE_DIR "\\metadata.dat"
#ifndef COT_CSV_DIR
#define COT_CSV_DIR         "SqCOT"
#endif
#define COT_BIN_MAGIC       0x31544F43
#define COT_MAX_SERIES      256
#define COT_MAX_RECORDS     100000

struct CotBinRecord
{
   long date;
   double cpihedg, ctihedg, cpispec, ctispec, cpismall;
};

struct CotBinHeader
{
   uint magic;
   int recordCount;
   int reserved;
};

string COT_Trim(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

bool COT_SafeName(const string value)
{
   int n=StringLen(value);
   if(n<1 || n>100) return false;
   for(int i=0;i<n;i++)
   {
      ushort c=StringGetCharacter(value,i);
      if(!((c>='a' && c<='z') || (c>='A' && c<='Z') ||
           (c>='0' && c<='9') || c=='_' || c=='-')) return false;
   }
   return true;
}

// An open handle without FILE_SHARE_* is an inter-program/inter-terminal lock.
// Do not delete lock files: closing the handle releases the OS lock, even on crash.
int COT_Lock(const string name)
{
   return FileOpen(COT_CACHE_DIR+"\\"+name+".lock",
                   COT_FILE_SCOPE|FILE_BIN|FILE_READ|FILE_WRITE);
}

bool COT_ReadBytes(const string path,uchar &bytes[],const int common=COT_FILE_SCOPE,
                   const int maxBytes=67108864)
{
   int h=FileOpen(path,FILE_READ|FILE_BIN|FILE_SHARE_READ|common);
   if(h==INVALID_HANDLE) return false;
   long size=(long)FileSize(h);
   bool ok=(size>0 && size<=maxBytes);
   if(ok)
   {
      ok=(ArrayResize(bytes,(int)size)==size);
      if(ok) ok=(FileReadArray(h,bytes,0,(int)size)==(uint)size);
   }
   FileClose(h);
   return ok;
}

bool COT_ReadText(const string path,string &value,const int common=COT_FILE_SCOPE)
{
   uchar bytes[];
   if(!COT_ReadBytes(path,bytes,common,65536)) return false;
   value=CharArrayToString(bytes,0,ArraySize(bytes),CP_UTF8);
   return true;
}

bool COT_WriteBytes(const string path,const uchar &bytes[])
{
   int h=FileOpen(path,COT_FILE_SCOPE|FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE) return false;
   int size=ArraySize(bytes);
   bool ok=(FileWriteArray(h,bytes,0,size)==(uint)size);
   FileFlush(h);
   ok=ok && (FileSize(h)==(ulong)size);
   FileClose(h);
   return ok;
}

// Callers hold the relevant lock while publishing mutable control files.
bool COT_WriteText(const string path,const string value)
{
   uchar bytes[];
   int n=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(n<=1) return false;
   ArrayResize(bytes,n-1);
   string tmp=path+".tmp";
   if(!COT_WriteBytes(tmp,bytes)) return false;
   return FileMove(tmp,COT_FILE_SCOPE,path,COT_FILE_SCOPE|FILE_REWRITE);
}

bool COT_ParseNumber(string text,double &value)
{
   text=COT_Trim(text);
   int n=StringLen(text),i=0,digits=0;
   if(n==0) return false;
   if(StringGetCharacter(text,0)=='-' || StringGetCharacter(text,0)=='+') i++;
   for(;i<n && StringGetCharacter(text,i)>='0' && StringGetCharacter(text,i)<='9';i++) digits++;
   if(i<n && StringGetCharacter(text,i)=='.')
   {
      i++;
      for(;i<n && StringGetCharacter(text,i)>='0' && StringGetCharacter(text,i)<='9';i++) digits++;
   }
   if(digits==0) return false;
   if(i<n && (StringGetCharacter(text,i)=='e' || StringGetCharacter(text,i)=='E'))
   {
      i++;
      if(i<n && (StringGetCharacter(text,i)=='-' || StringGetCharacter(text,i)=='+')) i++;
      int first=i;
      for(;i<n && StringGetCharacter(text,i)>='0' && StringGetCharacter(text,i)<='9';i++) {}
      if(i==first) return false;
   }
   if(i!=n) return false;
   value=StringToDouble(text);
   return MathIsValidNumber(value) && (value==-1.0 || (value>=0.0 && value<=1.0));
}

bool COT_ParseDate(string text,long &value)
{
   text=COT_Trim(text);
   if(StringLen(text)!=10 || StringGetCharacter(text,4)!='-' || StringGetCharacter(text,7)!='-') return false;
   for(int i=0;i<10;i++)
      if(i!=4 && i!=7 && (StringGetCharacter(text,i)<'0' || StringGetCharacter(text,i)>'9')) return false;
   MqlDateTime dt={};
   dt.year=(int)StringToInteger(StringSubstr(text,0,4));
   dt.mon=(int)StringToInteger(StringSubstr(text,5,2));
   dt.day=(int)StringToInteger(StringSubstr(text,8,2));
   if(dt.year<1970 || dt.year>2100 || dt.mon<1 || dt.mon>12 || dt.day<1 || dt.day>31) return false;
   value=(long)StructToTime(dt);
   MqlDateTime check={};
   if(!TimeToStruct((datetime)value,check)) return false;
   return check.year==dt.year && check.mon==dt.mon && check.day==dt.day;
}

bool COT_ValidRecord(const CotBinRecord &r)
{
   double v[5];
   v[0]=r.cpihedg; v[1]=r.ctihedg; v[2]=r.cpispec; v[3]=r.ctispec; v[4]=r.cpismall;
   if(r.date<0 || r.date>4133980800) return false;
   for(int i=0;i<5;i++)
      if(!MathIsValidNumber(v[i]) || !(v[i]==-1.0 || (v[i]>=0.0 && v[i]<=1.0))) return false;
   return true;
}

// Same six CSV columns as the original reader. Reject bad rows instead of
// silently turning invalid numbers into zero. Normalize descending archives.
bool COT_ParseCsv(string text,CotBinRecord &records[],string &error)
{
   ArrayFree(records);
   StringReplace(text,"\r","");
   if(StringLen(text)>0 && StringGetCharacter(text,0)==0xFEFF) text=StringSubstr(text,1);
   string lines[];
   int count=StringSplit(text,'\n',lines),used=0,direction=0;
   if(count<1 || count>COT_MAX_RECORDS+10) {error="CSV record limit exceeded or empty CSV."; return false;}
   ArrayResize(records,count);
   bool first=true;
   for(int i=0;i<count;i++)
   {
      string line=COT_Trim(lines[i]);
      if(line=="") continue;
      if(first)
      {
         first=false;
         string header=line;
         StringToLower(header);
         StringReplace(header," ","");
         if(header=="date,cpihedg,ctihedg,cpispec,ctispec,cpismall") continue;
      }
      string fields[];
      CotBinRecord r;
      if(StringSplit(line,',',fields)!=6 || !COT_ParseDate(fields[0],r.date) ||
         !COT_ParseNumber(fields[1],r.cpihedg) || !COT_ParseNumber(fields[2],r.ctihedg) ||
         !COT_ParseNumber(fields[3],r.cpispec) || !COT_ParseNumber(fields[4],r.ctispec) ||
         !COT_ParseNumber(fields[5],r.cpismall))
      { error="Invalid CSV row "+IntegerToString(i+1)+"."; ArrayFree(records); return false; }
      if(used>0)
      {
         int next=(r.date>records[used-1].date ? 1 : -1);
         if(r.date==records[used-1].date || (direction!=0 && direction!=next))
         {error="CSV dates must be ordered and unique."; ArrayFree(records); return false;}
         direction=next;
      }
      records[used++]=r;
   }
   if(used==0 || used>COT_MAX_RECORDS) {error="CSV contains no records or too many records."; ArrayFree(records); return false;}
   ArrayResize(records,used);
   if(direction<0)
      for(int i=0;i<used/2;i++) {CotBinRecord tmp=records[i]; records[i]=records[used-1-i]; records[used-1-i]=tmp;}
   return true;
}

bool COT_ReadBin(const string path,CotBinRecord &records[],string &error)
{
   int h=FileOpen(path,COT_FILE_SCOPE|FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) {error="Cannot open COT cache."; return false;}
   CotBinHeader header;
   bool ok=(FileReadStruct(h,header)==sizeof(CotBinHeader));
   ok=ok && header.magic==COT_BIN_MAGIC && header.recordCount>0 && header.recordCount<=COT_MAX_RECORDS;
   if(ok) ok=(FileSize(h)==(ulong)sizeof(CotBinHeader)+(ulong)header.recordCount*sizeof(CotBinRecord));
   if(ok)
   {
      ok=(ArrayResize(records,header.recordCount)==header.recordCount);
      for(int i=0;ok && i<header.recordCount;i++)
      {
         ok=(FileReadStruct(h,records[i])==sizeof(CotBinRecord)) && COT_ValidRecord(records[i]);
         if(i>0) ok=ok && records[i].date>records[i-1].date;
      }
   }
   FileClose(h);
   if(!ok) {ArrayFree(records); error="Invalid or incomplete COT binary cache.";}
   return ok;
}

bool COT_WriteBin(const string path,const CotBinRecord &records[],string &error)
{
   int h=FileOpen(path,COT_FILE_SCOPE|FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE) {error="Cannot create COT cache file."; return false;}
   CotBinHeader header;
   header.magic=COT_BIN_MAGIC; header.recordCount=ArraySize(records); header.reserved=0;
   bool ok=(FileWriteStruct(h,header)==sizeof(CotBinHeader));
   for(int i=0;ok && i<header.recordCount;i++) ok=(FileWriteStruct(h,records[i])==sizeof(CotBinRecord));
   FileFlush(h);
   FileClose(h);
   // Read back the temporary file before it may be published.
   CotBinRecord check[];
   if(ok) ok=COT_ReadBin(path,check,error);
   if(!ok && error=="") error="Cannot write complete COT cache file.";
   return ok;
}

bool COT_ParseMetadata(string text,string &version,datetime &updated,string &ids[])
{
   StringReplace(text,"\r","");
   string lines[];
   int n=StringSplit(text,'\n',lines);
   if(n<3) return false;
   version=COT_Trim(lines[0]);
   updated=(datetime)StringToInteger(lines[1]);
   if(!COT_SafeName(version) || updated<=0) return false;
   ArrayResize(ids,0);
   for(int i=2;i<n;i++)
   {
      string id=COT_Trim(lines[i]);
      if(id=="") continue;
      if(!COT_SafeName(id) || ArraySize(ids)>=COT_MAX_SERIES) return false;
      StringToUpper(id);
      for(int j=0;j<ArraySize(ids);j++) if(ids[j]==id) return false;
      int size=ArraySize(ids); ArrayResize(ids,size+1); ids[size]=id;
   }
   return ArraySize(ids)>0;
}

#endif
