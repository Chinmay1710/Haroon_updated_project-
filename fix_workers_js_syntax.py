html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/workers.html"
with open(html_file, 'r') as f:
    content = f.read()

bad_js = """ } catch (e) { console.error(e); }
 }
 
 async function saveWorker() {"""

good_js = """ }
 }
 
 async function loadWorkers() {
     try {
         const res = await window.API.request('get_all_workers');
         globalWorkersList = res.workers || [];
         renderWorkers();
     } catch(e) {
         console.error(e);
     }
 }
 
 async function saveWorker() {"""

content = content.replace(bad_js, good_js)

with open(html_file, 'w') as f:
    f.write(content)

print("Fixed syntax error!")
