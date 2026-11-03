'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),{createServer,validBase}=require('../server');
test('Cloud.ru endpoint allowlist',()=>{assert.match(validBase('https://foundation-models.api.cloud.ru/v1'),/cloud\.ru/);for(const url of ['http://foundation-models.api.cloud.ru','https://evil.example/v1','https://cloud.ru.evil.example','https://x:y@cloud.ru'])assert.throws(()=>validBase(url))});
test('health and static asset',async()=>{const server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));try{const base='http://127.0.0.1:'+server.address().port;let r=await fetch(base+'/api/health');assert.equal(r.status,200);assert.equal((await r.json()).ok,true);r=await fetch(base+'/');assert.equal(r.status,200);assert.match(await r.text(),/Mienayura/);r=await fetch(base+'/data/cloudru-settings.json');assert.equal(r.status,404)}finally{await new Promise(r=>server.close(r))}});

test('API does not expose secrets or local files',async()=>{
 const server=createServer();
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 try{
  const base='http://127.0.0.1:'+server.address().port;
  const settings=await fetch(base+'/api/settings');
  assert.equal(settings.status,200);
  const publicData=await settings.json();
  assert.equal(Object.hasOwn(publicData,'apiKey'),false);
  for(const pathname of ['/data/workspace.json','/data/cloudru-settings.json','/.gitignore','/server.js']){
   const response=await fetch(base+pathname);
   assert.equal(response.status,404,pathname+' must not be served');
  }
  const missing=await fetch(base+'/api/not-found');
  assert.equal(missing.status,404);
 }finally{await new Promise(resolve=>server.close(resolve))}
});
