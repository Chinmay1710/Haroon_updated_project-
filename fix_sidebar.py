import re

html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/orders_list.html"
with open(html_file, 'r') as f:
    content = f.read()

# Fix sidebar tag
old_sidebar = '<nav style="position:fixed; top:0; bottom:0; left:0; width:280px; display:flex; flex-direction:column; z-index:40; background:#091426; color:#ffffff; box-shadow:0 4px 6px -1px rgba(0,0,0,0.1);">'
new_sidebar = '''<!-- Mobile Sidebar Overlay -->
<div id="sidebar-overlay" class="fixed inset-0 hidden md:hidden" style="z-index:9998; background:rgba(0,0,0,0.5);" onclick="document.getElementById('sidebar').classList.remove('left-0'); document.getElementById('sidebar').classList.add('-left-[290px]'); this.classList.add('hidden'); var mb=document.getElementById('mobile-menu-btn'); if(mb){mb.style.opacity='1'; mb.style.pointerEvents='auto';}"></div>
<!-- SideNavBar -->
<nav id="sidebar" class="fixed top-0 bottom-0 -left-[290px] md:left-0 transition-all duration-300 z-[9999] md:z-40 flex flex-col shadow-md" style="width:280px; background:#091426; color:#ffffff;">'''

if old_sidebar in content:
    content = content.replace(old_sidebar, new_sidebar)
    with open(html_file, 'w') as f:
        f.write(content)
    print("Fixed sidebar!")
else:
    print("Old sidebar not found. Looking for alternative.")
    # Maybe it was partially modified
    if 'id="sidebar"' not in content:
        # replace the generic nav
        pass
