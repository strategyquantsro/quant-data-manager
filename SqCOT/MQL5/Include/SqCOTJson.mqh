// Streaming schema parser for cot.json: { "6E_52w": [{date,...five fields}], ... }.
// Reads UTF-8 bytes in place and buffers one series, not a full JSON object tree.
#ifndef __SQ_COT_JSON_MQH__
#define __SQ_COT_JSON_MQH__
#include <SqCOTStorage.mqh>

void COT_JsonSpace(const uchar &data[],int &pos)
{
   int size=ArraySize(data);
   while(pos<size && (data[pos]==32 || data[pos]==9 || data[pos]==10 || data[pos]==13)) pos++;
}
bool COT_JsonTake(const uchar &data[],int &pos,const uchar expected,string &error)
{
   COT_JsonSpace(data,pos);
   if(pos>=ArraySize(data) || data[pos]!=expected)
   {error="Invalid JSON at byte "+IntegerToString(pos)+": expected "+CharToString(expected)+"."; return false;}
   pos++; return true;
}
int COT_JsonHex(const uchar c)
{
   if(c>='0' && c<='9') return c-'0';
   if(c>='a' && c<='f') return c-'a'+10;
   if(c>='A' && c<='F') return c-'A'+10;
   return -1;
}
bool COT_JsonString(const uchar &data[],int &pos,string &value,string &error)
{
   value="";
   if(!COT_JsonTake(data,pos,'"',error)) return false;
   int size=ArraySize(data);
   while(pos<size)
   {
      uchar c=data[pos++];
      if(c=='"') return true;
      if(c=='\\')
      {
         if(pos>=size) break;
         c=data[pos++];
         if(c=='u')
         {
            if(pos+4>size) break;
            int v=0;
            for(int j=0;j<4;j++)
            {
               int digit=COT_JsonHex(data[pos++]);
               if(digit<0) {error="Invalid JSON Unicode escape."; return false;}
               v=v*16+digit;
            }
            // Dataset identifiers, field names and dates are ASCII.
            if(v<32 || v>126) {error="Unsupported character in JSON key/date."; return false;}
            c=(uchar)v;
         }
         else if(c!='"' && c!='\\' && c!='/')
         {error="Unsupported JSON string escape."; return false;}
      }
      if(c<32 || c>126 || StringLen(value)>=128)
      {error="Invalid or oversized JSON key/date."; return false;}
      value+=CharToString(c);
   }
   error="Unterminated JSON string."; return false;
}
bool COT_JsonNumber(const uchar &data[],int &pos,double &value,string &error)
{
   COT_JsonSpace(data,pos);
   int start=pos,size=ArraySize(data);
   // Production cot.json uses null for unavailable historical components.
   // Preserve missingness using the reader's existing -1 sentinel.
   if(pos+4<=size && data[pos]=='n' && data[pos+1]=='u' && data[pos+2]=='l' && data[pos+3]=='l')
   {pos+=4; value=-1.0; return true;}
   if(pos<size && data[pos]=='-') pos++;
   if(pos>=size) {error="Missing JSON number."; return false;}
   if(data[pos]=='0') pos++;
   else
   {
      int digits=pos;
      while(pos<size && data[pos]>='0' && data[pos]<='9') pos++;
      if(pos==digits) {error="Expected numeric COT value at byte "+IntegerToString(start)+"."; return false;}
   }
   if(pos<size && data[pos]=='.')
   {
      int digits=++pos;
      while(pos<size && data[pos]>='0' && data[pos]<='9') pos++;
      if(pos==digits) {error="Invalid JSON fraction."; return false;}
   }
   if(pos<size && (data[pos]=='e' || data[pos]=='E'))
   {
      pos++;
      if(pos<size && (data[pos]=='+' || data[pos]=='-')) pos++;
      int digits=pos;
      while(pos<size && data[pos]>='0' && data[pos]<='9') pos++;
      if(pos==digits) {error="Invalid JSON exponent."; return false;}
   }
   if(pos-start>64 || !COT_ParseNumber(CharArrayToString(data,start,pos-start,CP_UTF8),value))
   {error="COT JSON value is outside the supported range."; return false;}
   return true;
}
bool COT_JsonRecord(const uchar &data[],int &pos,CotBinRecord &record,string &error)
{
   if(!COT_JsonTake(data,pos,'{',error)) return false;
   int mask=0;
   for(int field=0;field<6;field++)
   {
      if(field>0 && !COT_JsonTake(data,pos,',',error)) return false;
      string name;
      if(!COT_JsonString(data,pos,name,error) || !COT_JsonTake(data,pos,':',error)) return false;
      int bit=0;
      if(name=="date") bit=1;
      else if(name=="cpihedg") bit=2;
      else if(name=="ctihedg") bit=4;
      else if(name=="cpispec") bit=8;
      else if(name=="ctispec") bit=16;
      else if(name=="cpismall") bit=32;
      if(bit==0 || (mask&bit)!=0) {error="Unknown or duplicate field in COT JSON record."; return false;}
      mask|=bit;
      if(bit==1)
      {
         string date;
         if(!COT_JsonString(data,pos,date,error)) return false;
         if(!COT_ParseDate(date,record.date)) {error="Invalid date in COT JSON."; return false;}
      }
      else
      {
         double value;
         if(!COT_JsonNumber(data,pos,value,error)) return false;
         if(bit==2) record.cpihedg=value;
         else if(bit==4) record.ctihedg=value;
         else if(bit==8) record.cpispec=value;
         else if(bit==16) record.ctispec=value;
         else record.cpismall=value;
      }
   }
   return mask==63 && COT_JsonTake(data,pos,'}',error);
}
bool COT_JsonSeries(const uchar &data[],int &pos,CotBinRecord &records[],string &error)
{
   ArrayFree(records);
   if(!COT_JsonTake(data,pos,'[',error)) return false;
   COT_JsonSpace(data,pos);
   if(pos<ArraySize(data) && data[pos]==']') {pos++; return true;}
   int count=0,direction=0;
   while(pos<ArraySize(data))
   {
      if(count>=COT_MAX_RECORDS) {error="JSON series exceeds record limit."; return false;}
      CotBinRecord record;
      if(!COT_JsonRecord(data,pos,record,error)) return false;
      if(count>0)
      {
         int next=record.date>records[count-1].date?1:-1;
         if(record.date==records[count-1].date || (direction!=0 && direction!=next))
         {error="JSON dates must be ordered and unique."; return false;}
         direction=next;
      }
      if(count>=ArraySize(records) && ArrayResize(records,count+2048)<0)
      {error="Not enough memory for COT records."; return false;}
      records[count++]=record;
      COT_JsonSpace(data,pos);
      if(pos<ArraySize(data) && data[pos]==']')
      {
         pos++; ArrayResize(records,count);
         if(direction<0)
            for(int i=0;i<count/2;i++) {CotBinRecord tmp=records[i]; records[i]=records[count-1-i]; records[count-1-i]=tmp;}
         return true;
      }
      if(!COT_JsonTake(data,pos,',',error)) return false;
   }
   error="Unterminated COT JSON array."; return false;
}
#endif
