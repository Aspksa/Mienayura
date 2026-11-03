'use strict';
function graph(memories) {
 const nodes=[],edges=[],topics=new Set();
 for(const m of memories){
  if(!m||typeof m.id!=='string')continue;
  nodes.push({id:m.id,label:String(m.title||m.content||'Запись').slice(0,100),type:'memory'});
  const tags=new Set((String(m.content||'').match(/#[a-zA-Z0-9_-]{2,40}/g)||[]).map(x=>x.slice(1).toLowerCase()));
  for(const tag of tags){topics.add(tag);edges.push({source:m.id,target:'topic:'+tag})}
 }
 for(const tag of topics)nodes.push({id:'topic:'+tag,label:tag,type:'topic'});
 return {nodes,edges};
}
function search(workspace,query){
 const q=String(query||'').trim().toLocaleLowerCase().slice(0,100);
 if(q.length<2)return [];
 const results=[];
 for(const collection of ['chats','tasks','memories','notes']){
  for(const item of workspace[collection]||[]){
   if(!item||typeof item!=='object')continue;
   const hay=[item.title,item.content,...(Array.isArray(item.messages)?item.messages.map(m=>m.content):[])].join(' ').toLocaleLowerCase();
   if(hay.includes(q))results.push({collection,id:item.id,title:String(item.title||item.content||'Запись').slice(0,120)});
   if(results.length>=100)return results;
  }
 }
 return results;
}
module.exports={graph,search};
