'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {graph,search}=require('../knowledge');
test('graph groups shared topics and deduplicates tags',()=>{
 const result=graph([{id:'a',title:'A',content:'#memory #memory'},{id:'b',title:'B',content:'#memory #tasks'}]);
 assert.equal(result.nodes.length,4);
 assert.equal(result.edges.length,3);
 assert.equal(result.nodes.filter(n=>n.id==='topic:memory').length,1);
});
test('search returns matches from notes and chat history',()=>{
 const d={chats:[{id:'1',title:'Dialog',messages:[{content:'hello world'}]}],tasks:[],memories:[],notes:[{id:'2',title:'World note'}]};
 assert.equal(search(d,'world').length,2);
 assert.deepEqual(search(d,'x'),[]);
});

test('automatic folders group by first tag and retain untagged entries',()=>{
 const {folders}=require('../knowledge');
 const groups=folders([{id:'1',title:'One',content:'#work task'},{id:'2',title:'Two',content:'#work note'},{id:'3',title:'Three',content:'untagged'}]);
 assert.equal(groups.find(g=>g.name==='work').count,2);
 assert.equal(groups.find(g=>g.name==='Без категории').count,1);
});
