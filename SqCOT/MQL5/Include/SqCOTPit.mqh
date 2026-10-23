// Immutable, locally observed point-in-time revisions. Never invent pre-observation availability.
#ifndef __SQ_COT_PIT_MQH__
#define __SQ_COT_PIT_MQH__
#include <SqCOTStorage.mqh>
#define COT_PIT_MAGIC 0x32544950
#define COT_MAX_REVISIONS 400000
struct CotPitRecord {CotBinRecord value; long available; int revision;};
bool COT_SameRecord(const CotBinRecord &a,const CotBinRecord &b)
{
   return a.date==b.date && a.cpihedg==b.cpihedg && a.ctihedg==b.ctihedg &&
      a.cpispec==b.cpispec && a.ctispec==b.ctispec && a.cpismall==b.cpismall;
}
bool COT_ReadPit(const string path,CotPitRecord &rows[])
{
   int h=FileOpen(path,COT_FILE_SCOPE|FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) return false;
   uint magic=(uint)FileReadInteger(h,INT_VALUE); int count=FileReadInteger(h,INT_VALUE);
   bool ok=magic==COT_PIT_MAGIC && count>0 && count<=COT_MAX_REVISIONS &&
      FileSize(h)==8+(ulong)count*sizeof(CotPitRecord);
   if(ok) ok=ArrayResize(rows,count)==count;
   for(int i=0;ok && i<count;i++)
   {
      ok=FileReadStruct(h,rows[i])==sizeof(CotPitRecord) && COT_ValidRecord(rows[i].value) &&
         rows[i].available>0 && rows[i].revision>0;
      if(i>0) ok=ok && (rows[i].value.date>rows[i-1].value.date ||
         (rows[i].value.date==rows[i-1].value.date && rows[i].available>rows[i-1].available && rows[i].revision==rows[i-1].revision+1));
      if(i==0 || rows[i].value.date!=rows[i-1].value.date) ok=ok && rows[i].revision==1;
   }
   FileClose(h); if(!ok) ArrayFree(rows); return ok;
}
bool COT_WritePit(const string path,const CotPitRecord &rows[])
{
   int h=FileOpen(path,COT_FILE_SCOPE|FILE_WRITE|FILE_BIN); if(h==INVALID_HANDLE) return false;
   FileWriteInteger(h,COT_PIT_MAGIC,INT_VALUE); FileWriteInteger(h,ArraySize(rows),INT_VALUE);
   bool ok=true;
   for(int i=0;ok && i<ArraySize(rows);i++) ok=FileWriteStruct(h,rows[i])==sizeof(CotPitRecord);
   FileFlush(h); FileClose(h); CotPitRecord check[];
   return ok && COT_ReadPit(path,check);
}
bool COT_MergePit(const CotBinRecord &fresh[],const CotPitRecord &old[],const long observed,
                  CotPitRecord &out[],bool &changed,string &error)
{
   ArrayFree(out); changed=false; int j=0,n=0;
   int max=ArraySize(old)+ArraySize(fresh);
   if(max>COT_MAX_REVISIONS || ArrayResize(out,max)!=max) {error="Revision storage limit."; return false;}
   for(int i=0;i<ArraySize(fresh);i++)
   {
      if(j<ArraySize(old) && old[j].value.date<fresh[i].date) {error="History regression: missing prior report."; return false;}
      int first=n;
      while(j<ArraySize(old) && old[j].value.date==fresh[i].date) out[n++]=old[j++];
      if(n==first || !COT_SameRecord(out[n-1].value,fresh[i]))
      {
         if(n>first && observed<=out[n-1].available) {error="Clock regression during revision."; return false;}
         out[n].value=fresh[i]; out[n].available=observed;
         out[n].revision=(n==first?1:out[n-1].revision+1); n++; changed=true;
      }
   }
   if(j<ArraySize(old)) {error="History regression: latest report removed."; return false;}
   ArrayResize(out,n); return n>0;
}
int COT_PitAt(const CotPitRecord &rows[],const long asOf,const int reportShift=0)
{
   if(reportShift<0) return -1;
   int remaining=reportShift;
   for(int i=ArraySize(rows)-1;i>=0;)
   {
      long date=rows[i].value.date; int chosen=-1;
      do {if(chosen<0 && rows[i].available<=asOf) chosen=i; i--;} while(i>=0 && rows[i].value.date==date);
      if(chosen>=0) {if(remaining==0) return chosen; remaining--;}
   }
   return -1;
}
bool COT_ValueValid(const double x) {return x!=EMPTY_VALUE && MathIsValidNumber(x) && x>=0 && x<=1;}
// Compare every current archive row to its latest preserved revision.
bool COT_MatchesPit(const CotBinRecord &rows[],const CotPitRecord &pit[])
{
   int j=0;
   for(int i=0;i<ArraySize(rows);i++)
   {
      if(j>=ArraySize(pit) || pit[j].value.date!=rows[i].date) return false;
      while(j+1<ArraySize(pit) && pit[j+1].value.date==rows[i].date) j++;
      if(!COT_SameRecord(rows[i],pit[j].value)) return false;
      j++;
   }
   return ArraySize(rows)>0 && j==ArraySize(pit);
}
bool COT_SeriesFilesValid(const string directory,const string series)
{
   CotBinRecord rows[];CotPitRecord pit[];string error;
   return COT_ReadBin(directory+"\\"+series+".bin",rows,error) &&
      COT_ReadPit(directory+"\\"+series+".pit",pit) && COT_MatchesPit(rows,pit);
}
string COT_Hash(const uchar &bytes[])
{
   uchar key[],digest[]; if(CryptEncode(CRYPT_HASH_SHA256,bytes,key,digest)!=32) return "";
   string s=""; for(int i=0;i<32;i++) s+=StringFormat("%02x",digest[i]); return s;
}
#endif
