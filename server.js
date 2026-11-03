const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const root = __dirname;
const mime = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8'};
const port = Number(process.env.PORT || 5173);
http.createServer((req,res)=>{
  const url = new URL(req.url,'http://localhost');
  const pathname = decodeURIComponent(url.pathname);
  const name = pathname === '/' ? 'index.html' : pathname.slice(1);
  const full = path.resolve(root,name);
  if (!full.startsWith(root + path.sep) || !['index.html','styles.css','app.js'].includes(name)) { res.writeHead(404); res.end('Not found'); return; }
  fs.readFile(full,(err,data)=>{if(err){res.writeHead(404);res.end('Not found');return;}res.writeHead(200,{'Content-Type':mime[path.extname(full)],'X-Content-Type-Options':'nosniff'});res.end(data);});
}).listen(port,'127.0.0.1',()=>{
  const url = 'http://127.0.0.1:'+port+'/';
  console.log('Mienayura: '+url);
  // Open only after the server is listening. Disable with MIENAYURA_NO_BROWSER=1.
  if (process.platform === 'win32' && process.env.MIENAYURA_NO_BROWSER !== '1') {
    try {
      const browser = spawn('explorer.exe',[url],{detached:true,stdio:'ignore',windowsHide:true});
      browser.on('error',err=>console.warn('Browser could not open:',err.message));
      browser.unref();
    } catch (err) { console.warn('Browser could not open:',err.message); }
  }
});
