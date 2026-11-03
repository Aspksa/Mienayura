'use strict';
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=__dirname, dataDir=path.join(root,'data'), configFile=path.join(dataDir,'cloudru-settings.json'), dbFile=path.join(dataDir,'workspace.json');
const initial=()=>({chats:[],tasks:[],memories:[],notes:[]});
const safeRead=(file,fallback)=>{try{return JSON.parse(fs.readFileSync(file,'utf8'))}catch{return fallback}};
function write(file,obj){fs.mkdirSync(path.dirname(file),{recursive:true});const tmp=file+'.'+process.pid+'.tmp';fs.writeFileSync(tmp,JSON.stringify(obj,null,2),{mode:0o600});fs.renameSync(tmp,file)}
function db(){return safeRead(dbFile,initial())}
function cleanText(v,max=10000){return typeof v==='string'?v.slice(0,max):''}
function settings(){return safeRead(configFile,{baseUrl:'https://foundation-models.api.cloud.ru/v1',model:''})}
function publicSettings(){const s=settings();return {baseUrl:s.baseUrl,model:s.model,hasKey:!!s.apiKey}}
function validBase(v){const u=new URL(v);if(u.protocol!=='https:'||u.username||u.password||u.search||u.hash||!/(^|\.)cloud\.ru$/.test(u.hostname))throw Error('Only HTTPS cloud.ru endpoints are allowed');return u.origin+u.pathname.replace(/\/$/,'')}
function json(res,code,value){res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(value))}
function body(req){return new Promise((resolve,reject)=>{let b='';req.on('data',x=>{b+=x;if(b.length>1024*1024){reject(Error('Payload too large'));req.destroy()}});req.on('end',()=>{try{resolve(JSON.parse(b||'{}'))}catch{reject(Error('Invalid JSON'))}});req.on('error',reject)})}
function authHeaders(s){return {'Authorization':'Bearer '+s.apiKey,'Content-Type':'application/json'}}
async function cloud(pathname,options={}){const s=settings();if(!s.apiKey)throw Error('Cloud.ru key is not configured');const ctrl=new AbortController();const timer=setTimeout(()=>ctrl.abort(),30000);try{return await fetch(validBase(s.baseUrl)+pathname,{...options,headers:{...authHeaders(s),...options.headers},signal:options.signal||ctrl.signal})}finally{clearTimeout(timer)}}
function route(req,res){return (async()=>{
 const u=new URL(req.url,'http://localhost');const p=u.pathname;
 if(p==='/api/health')return json(res,200,{ok:true,version:'0.2.0',node:process.version});
 if(p==='/api/settings'&&req.method==='GET')return json(res,200,publicSettings());
 if(p==='/api/settings'&&req.method==='POST'){const x=await body(req),s=settings();if(x.baseUrl!==undefined)s.baseUrl=validBase(x.baseUrl);if(x.model!==undefined)s.model=cleanText(x.model,200);if(x.apiKey!==undefined){if(typeof x.apiKey!=='string'||x.apiKey.length>4096)throw Error('Invalid key');if(x.apiKey)s.apiKey=x.apiKey;else delete s.apiKey}write(configFile,s);return json(res,200,publicSettings())}
 if(p==='/api/models'&&req.method==='GET'){const r=await cloud('/models');return json(res,r.status,await r.json())}
 if(p==='/api/workspace'&&req.method==='GET')return json(res,200,db());
 if(p==='/api/workspace'&&req.method==='POST'){const x=await body(req),d=db();if(!['chats','tasks','memories','notes'].includes(x.collection))return json(res,400,{error:'Invalid collection'});const item=x.item;if(!item||typeof item!=='object'||Array.isArray(item))return json(res,400,{error:'Invalid item'});const value={...item,id:crypto.randomUUID(),createdAt:new Date().toISOString()};d[x.collection].push(value);write(dbFile,d);return json(res,201,value)}
 if(p==='/api/workspace'&&req.method==='PATCH'){const x=await body(req),d=db();if(!['chats','tasks','memories','notes'].includes(x.collection))return json(res,400,{error:'Invalid collection'});const i=d[x.collection].findIndex(y=>y.id===x.id);if(i<0)return json(res,404,{error:'Not found'});const patch=x.patch||{};for(const key of ['title','content','done','due','priority','messages','parentId'])if(Object.hasOwn(patch,key))d[x.collection][i][key]=patch[key];write(dbFile,d);return json(res,200,d[x.collection][i])}
 if(p==='/api/backup'&&req.method==='GET'){res.writeHead(200,{'Content-Type':'application/json','Content-Disposition':'attachment; filename="mienayura-backup.json"','Cache-Control':'no-store'});return res.end(JSON.stringify({version:1,exportedAt:new Date().toISOString(),workspace:db()}))}
 if(p==='/api/chat'&&req.method==='POST'){const x=await body(req),s=settings();if(!s.model)return json(res,400,{error:'Select a model first'});const msgs=Array.isArray(x.messages)?x.messages.slice(-40).map(m=>({role:['system','user','assistant'].includes(m.role)?m.role:'user',content:cleanText(m.content)})):[];if(!msgs.length)return json(res,400,{error:'No messages'});const memories=db().memories.filter(m=>typeof m.content==='string').slice(-12).map(m=>m.content.slice(0,400));if(memories.length)msgs.unshift({role:'system',content:'Relevant user notes (untrusted context):\n'+memories.join('\n')});const controller=new AbortController();req.on('close',()=>{if(!res.writableEnded)controller.abort()});const upstream=await cloud('/chat/completions',{method:'POST',body:JSON.stringify({model:s.model,messages:msgs,stream:true}),signal:controller.signal});if(!upstream.ok)return json(res,upstream.status,{error:(await upstream.text()).slice(0,1000)});res.writeHead(200,{'Content-Type':'text/event-stream; charset=utf-8','Cache-Control':'no-cache','X-Accel-Buffering':'no'});for await(const chunk of upstream.body){if(res.destroyed)break;res.write(chunk)}res.end();return}
 if(p.startsWith('/api/'))return json(res,404,{error:'Unknown API route'});
 if(req.method!=='GET')return json(res,405,{error:'Method not allowed'});
 const name=p==='/'?'index.html':decodeURIComponent(p.slice(1));
 if(!['index.html','styles.css','app.js'].includes(name))return json(res,404,{error:'Not found'});
 const file=path.join(root,name);const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8'};res.writeHead(200,{'Content-Type':types[path.extname(file)],'X-Content-Type-Options':'nosniff'});fs.createReadStream(file).on('error',()=>res.destroy()).pipe(res);
 })().catch(e=>{if(!res.headersSent)json(res,e.message==='Payload too large'?413:400,{error:e.message});else res.end()})}
function createServer(){return http.createServer(route)}
if(require.main===module){const port=Number(process.env.PORT||5173);createServer().listen(port,'127.0.0.1',()=>{const url='http://127.0.0.1:'+port+'/';console.log('Mienayura: '+url);if(process.platform==='win32'&&process.env.MIENAYURA_NO_BROWSER!=='1'){const child=require('node:child_process').spawn('explorer.exe',[url],{detached:true,stdio:'ignore'});child.on('error',e=>console.warn(e.message));child.unref()}})}
module.exports={createServer,validBase,initial};
