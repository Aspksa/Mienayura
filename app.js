(() => {
 const $ = id => document.getElementById(id);
 const read = (key, fallback) => { try { return JSON.parse(localStorage.getItem('mienayura.'+key)) ?? fallback; } catch { return fallback; } };
 const save = (key,value) => { try { localStorage.setItem('mienayura.'+key,JSON.stringify(value)); } catch {} };
 const clamp = (n,min,max) => Math.max(min,Math.min(max,n));
 const avatar=$('avatar'), chat=$('chat'), header=$('chatHeader');
 const mobile=()=>matchMedia('(max-width:700px)').matches;
 const pages={'Дела':['Ваши дела','Здесь появятся задачи, планы и напоминания. Пока данных нет.'],'Мозг':['Мозг и память','Раздел памяти и графа знаний подготовлен для дальнейшего подключения.'],'Обновление':['Обновление проекта','Здесь появятся проверка версий, история и безопасная установка обновлений.'],'Настройки':['Настройки','Параметры интерфейса и подключения будут доступны здесь.']};
 document.querySelectorAll('[data-page]').forEach(btn=>btn.addEventListener('click',()=>{document.querySelectorAll('[data-page]').forEach(b=>b.classList.toggle('active',b===btn));$('pageTitle').textContent=btn.dataset.page;$('sectionTitle').textContent=pages[btn.dataset.page][0];$('sectionDescription').textContent=pages[btn.dataset.page][1];$('sidebar').classList.remove('open');$('shade').hidden=true;$('menuToggle').setAttribute('aria-expanded','false');}));
 $('menuToggle').onclick=()=>{const open=$('sidebar').classList.toggle('open');$('shade').hidden=!open;$('menuToggle').setAttribute('aria-expanded',String(open));};
 $('shade').onclick=()=>$('menuToggle').click();
 function placeAvatar(x,y){avatar.style.left=clamp(x,0,innerWidth-avatar.offsetWidth)+'px';avatar.style.top=clamp(y,0,innerHeight-avatar.offsetHeight)+'px';save('avatar',{x:parseFloat(avatar.style.left),y:parseFloat(avatar.style.top)});}
 const pos=read('avatar',null);if(pos)requestAnimationFrame(()=>placeAvatar(pos.x,pos.y));
 function openChat(open){chat.hidden=!open;if(open){restoreChat();$('messageInput').focus();}else $('viewMenu').hidden=true;}
 $('closeChat').onclick=()=>openChat(false);
 document.addEventListener('keydown',e=>{if(e.ctrlKey&&e.key.toLowerCase()==='k'){e.preventDefault();openChat(chat.hidden);}if(e.key==='Escape'&&!chat.hidden)openChat(false);});
 let avatarDrag=null;
 avatar.addEventListener('pointerdown',e=>{avatarDrag={x:e.clientX,y:e.clientY,left:avatar.offsetLeft,top:avatar.offsetTop,moved:false};avatar.setPointerCapture(e.pointerId);});
 avatar.addEventListener('pointermove',e=>{if(!avatarDrag)return;const dx=e.clientX-avatarDrag.x,dy=e.clientY-avatarDrag.y;if(Math.hypot(dx,dy)>5)avatarDrag.moved=true;if(avatarDrag.moved)placeAvatar(avatarDrag.left+dx,avatarDrag.top+dy);});
 avatar.addEventListener('pointerup',()=>{if(avatarDrag&&!avatarDrag.moved)openChat(chat.hidden);avatarDrag=null;});
 avatar.addEventListener('keydown',e=>{const delta={ArrowLeft:[-10,0],ArrowRight:[10,0],ArrowUp:[0,-10],ArrowDown:[0,10]}[e.key];if(delta){e.preventDefault();placeAvatar(avatar.offsetLeft+delta[0],avatar.offsetTop+delta[1]);}});
 function saveChat(){if(mobile()||chat.classList.contains('maximized'))return;save('chatBounds',{x:chat.offsetLeft,y:chat.offsetTop,w:chat.offsetWidth,h:chat.offsetHeight});}
 function restoreChat(){if(mobile())return;const p=read('chatBounds',null);if(p){chat.style.width=clamp(p.w,350,innerWidth)+'px';chat.style.height=clamp(p.h,340,innerHeight)+'px';chat.style.left=clamp(p.x,0,Math.max(0,innerWidth-chat.offsetWidth))+'px';chat.style.top=clamp(p.y,0,Math.max(0,innerHeight-chat.offsetHeight))+'px';}}
 function maximize(){chat.classList.toggle('maximized');if(!chat.classList.contains('maximized'))restoreChat();}
 $('maximize').onclick=maximize;header.addEventListener('dblclick',e=>{if(!e.target.closest('button'))maximize();});
 let drag=null;
 header.addEventListener('pointerdown',e=>{if(mobile()||chat.classList.contains('maximized')||e.target.closest('button'))return;drag={x:e.clientX,y:e.clientY,left:chat.offsetLeft,top:chat.offsetTop};header.setPointerCapture(e.pointerId);});
 header.addEventListener('pointermove',e=>{if(!drag)return;chat.style.left=clamp(drag.left+e.clientX-drag.x,0,Math.max(0,innerWidth-chat.offsetWidth))+'px';chat.style.top=clamp(drag.top+e.clientY-drag.y,0,Math.max(0,innerHeight-chat.offsetHeight))+'px';});
 header.addEventListener('pointerup',()=>{if(drag)saveChat();drag=null;});
 new ResizeObserver(()=>{if(!chat.hidden)saveChat();}).observe(chat);
 $('viewToggle').onclick=()=>{const open=$('viewMenu').hidden;$('viewMenu').hidden=!open;$('viewToggle').setAttribute('aria-expanded',String(open));};
 for(const [id,key,values] of [['density','density',['comfortable','compact']],['fontSize','fontSize',['small','normal','large']]]){$(id).value=values.includes(read(key,''))?read(key,''):values[0];$(id).onchange=()=>{save(key,$(id).value);applyView();};}
 function applyView(){chat.classList.toggle('compact',$('density').value==='compact');chat.classList.remove('font-small','font-large');if($('fontSize').value!=='normal')chat.classList.add('font-'+$('fontSize').value);}
 applyView();
 $('composer').onsubmit=e=>{e.preventDefault();const input=$('messageInput');const value=input.value.trim();if(!value)return;const intro=$('messages').querySelector('.intro');if(intro)intro.remove();const bubble=document.createElement('div');bubble.className='bubble';bubble.textContent=value;$('messages').append(bubble);const note=document.createElement('p');note.className='notice';note.textContent='ИИ-модель пока не подключена — сообщение не отправлено.';$('messages').append(note);$('messages').scrollTop=$('messages').scrollHeight;input.value='';};
 addEventListener('resize',()=>{placeAvatar(avatar.offsetLeft,avatar.offsetTop);if(!mobile()&&!chat.hidden)restoreChat();});
})();
