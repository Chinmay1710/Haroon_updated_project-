import re

html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/workers.html"
with open(html_file, 'r') as f:
    content = f.read()

# Add ID to search input
content = content.replace(
    'placeholder="Search workers..." type="text"/>',
    'id="worker-search" placeholder="Search workers..." type="text" oninput="renderWorkers()"/>'
)

# Extract rendering logic
original_js = """ let globalWorkersList = [];

 async function loadWorkers() {
 try {
 const res = await window.API.request('get_all_workers');
 const tbody = document.getElementById('workers-list');
 tbody.innerHTML = '';
 
 globalWorkersList = res.workers || [];
 
 if (!res.workers || res.workers.length === 0) {
 tbody.innerHTML = `<tr><td colspan="6" class="px-6 py-8 text-center text-on-surface-variant">No workers found.</td></tr>`;
 return;
 }
 
 for (const w of res.workers) {"""

new_js = """ let globalWorkersList = [];

 function renderWorkers() {
 const tbody = document.getElementById('workers-list');
 if(!tbody) return;
 tbody.innerHTML = '';
 const q = (document.getElementById('worker-search')?.value || '').toLowerCase();
 
 const filtered = globalWorkersList.filter(w => {
     if(!q) return true;
     return (w.name || '').toLowerCase().includes(q) || (w.phone || '').toLowerCase().includes(q);
 });
 
 if (filtered.length === 0) {
     tbody.innerHTML = `<tr><td colspan="6" class="px-6 py-8 text-center text-on-surface-variant">No workers found.</td></tr>`;
     return;
 }
 
 for (const w of filtered) {"""

content = content.replace(original_js, new_js)

# Find where loadWorkers ends and add it back
content = content.replace(
    """  } catch(e) {
  console.error(e);
  window.API.toast("Failed to load workers", "error");
  }
 }""",
    """  } catch(e) {
  console.error(e);
  window.API.toast("Failed to render workers", "error");
  }
 }
 
 async function loadWorkers() {
     try {
         const res = await window.API.request('get_all_workers');
         globalWorkersList = res.workers || [];
         renderWorkers();
     } catch(e) {
         console.error(e);
         window.API.toast("Failed to load workers", "error");
     }
 }"""
)

with open(html_file, 'w') as f:
    f.write(content)

print("Fixed search box on workers page!")
