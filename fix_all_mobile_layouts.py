import glob
import re

BOTTOM_NAV = '''
<!-- Mobile Bottom Navigation -->
<nav id="mobile-bottom-nav" class="md:hidden fixed bottom-0 left-0 right-0 h-16 bg-surface shadow-[0_-4px_15px_rgba(0,0,0,0.1)] z-40 flex items-center justify-around px-2 border-t border-outline-variant/20">
    <a href="javascript:window.API.navigate('dashboard')" class="flex flex-col items-center gap-1 p-2 text-on-surface-variant hover:text-primary transition-colors">
        <span class="material-symbols-outlined text-[24px]">home</span>
        <span class="text-[10px] font-medium">Home</span>
    </a>
    <a href="javascript:window.API.navigate('orders_list')" class="flex flex-col items-center gap-1 p-2 text-on-surface-variant hover:text-primary transition-colors">
        <span class="material-symbols-outlined text-[24px]">receipt_long</span>
        <span class="text-[10px] font-medium">Orders</span>
    </a>
    <a href="javascript:window.API.navigate('customers_list')" class="flex flex-col items-center gap-1 p-2 text-on-surface-variant hover:text-primary transition-colors">
        <span class="material-symbols-outlined text-[24px]">group</span>
        <span class="text-[10px] font-medium">Customers</span>
    </a>
    <a href="javascript:window.API.navigate('payments')" class="flex flex-col items-center gap-1 p-2 text-on-surface-variant hover:text-primary transition-colors">
        <span class="material-symbols-outlined text-[24px]">payments</span>
        <span class="text-[10px] font-medium">Payments</span>
    </a>
    <button onclick="var sb=document.getElementById('sidebar'); var ov=document.getElementById('sidebar-overlay'); sb.classList.remove('-left-[290px]'); sb.classList.add('left-0'); ov.classList.remove('hidden');" class="flex flex-col items-center gap-1 p-2 text-on-surface-variant hover:text-primary transition-colors">
        <span class="material-symbols-outlined text-[24px]">menu</span>
        <span class="text-[10px] font-medium">More</span>
    </button>
</nav>
'''

old_sidebar = '<nav style="position:fixed; top:0; bottom:0; left:0; width:280px; display:flex; flex-direction:column; z-index:40; background:#091426; color:#ffffff; box-shadow:0 4px 6px -1px rgba(0,0,0,0.1);">'
new_sidebar = '''<!-- Mobile Sidebar Overlay -->
<div id="sidebar-overlay" class="fixed inset-0 hidden md:hidden" style="z-index:9998; background:rgba(0,0,0,0.5);" onclick="document.getElementById('sidebar').classList.remove('left-0'); document.getElementById('sidebar').classList.add('-left-[290px]'); this.classList.add('hidden'); var mb=document.getElementById('mobile-menu-btn'); if(mb){mb.style.opacity='1'; mb.style.pointerEvents='auto';}"></div>
<!-- SideNavBar -->
<nav id="sidebar" class="fixed top-0 bottom-0 -left-[290px] md:left-0 transition-all duration-300 z-[9999] md:z-40 flex flex-col shadow-md" style="width:280px; background:#091426; color:#ffffff;">'''

hamburger_html = '''<button id="mobile-menu-btn" class="md:hidden mr-3 w-10 h-10 flex items-center justify-center text-on-surface rounded-lg relative z-[10000]" onclick="var sb=document.getElementById('sidebar'); var ov=document.getElementById('sidebar-overlay'); sb.classList.remove('-left-[290px]'); sb.classList.add('left-0'); ov.classList.remove('hidden'); this.style.opacity='0'; this.style.pointerEvents='none'; event.stopPropagation();">
    <span class="material-symbols-outlined" style="font-size:24px;">menu</span>
</button>
<h2'''

html_files = glob.glob("/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/*.html")

for file in html_files:
    if file.endswith("stitching_slip_preview.html") or file.endswith("new_order.html") or "details" in file:
        continue

    with open(file, 'r') as f:
        content = f.read()

    modified = False

    # 1. Fix sidebar
    if old_sidebar in content:
        content = content.replace(old_sidebar, new_sidebar)
        modified = True

    # 2. Add Bottom Nav
    if 'id="mobile-bottom-nav"' not in content:
        content = content.replace('</body>', BOTTOM_NAV + '\n</body>')
        modified = True

    # 3. Add Manifest
    if 'rel="manifest"' not in content:
        content = content.replace('</head>', '  <link rel="manifest" href="../manifest.json">\n</head>')
        modified = True

    # 4. Fix layout margins (be careful not to duplicate)
    if 'ml-[280px]' in content and 'md:ml-[280px]' not in content:
        content = content.replace('ml-[280px]', 'ml-0 md:ml-[280px]')
        modified = True
        
    if 'left-[280px]' in content and 'md:left-[280px]' not in content:
        content = content.replace('left-[280px]', 'left-0 md:left-[280px]')
        modified = True
        
    if '<h2 class="font-headline-md text-headline-md text-primary' in content and 'id="mobile-menu-btn"' not in content:
        content = content.replace('<h2 class="font-headline-md text-headline-md text-primary', hamburger_html + ' class="font-headline-md text-headline-md text-primary')
        modified = True

    if modified:
        with open(file, 'w') as f:
            f.write(content)
        print(f"Fixed layouts in {file}")

print("Global mobile layout fixes complete!")

