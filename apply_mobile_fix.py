import os
import glob
import re

html_dir = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html"
files = glob.glob(os.path.join(html_dir, "*.html"))

NAV_OLD = '<nav style="position:fixed; top:0; bottom:0; left:0; width:280px; display:flex; flex-direction:column; z-index:40; background:#091426; color:#ffffff; box-shadow:0 4px 6px -1px rgba(0,0,0,0.1);">'
NAV_NEW = '''<!-- Mobile Sidebar Overlay -->
<div id="sidebar-overlay" class="fixed inset-0 hidden md:hidden" style="z-index:9998; background:rgba(0,0,0,0.5);" onclick="document.getElementById('sidebar').classList.remove('left-0'); document.getElementById('sidebar').classList.add('-left-[290px]'); this.classList.add('hidden'); var mb=document.getElementById('mobile-menu-btn'); if(mb){mb.style.opacity='1'; mb.style.pointerEvents='auto';}"></div>
<!-- SideNavBar -->
<nav id="sidebar" class="fixed top-0 bottom-0 -left-[290px] md:left-0 transition-all duration-300 z-[9999] md:z-40 flex flex-col shadow-md" style="width:280px; background:#091426; color:#ffffff;">'''

HAMBURGER = '''
<button id="mobile-menu-btn" class="md:hidden mr-3 w-10 h-10 flex items-center justify-center text-on-surface rounded-lg relative z-[10000]" onclick="var sb=document.getElementById('sidebar'); var ov=document.getElementById('sidebar-overlay'); sb.classList.remove('-left-[290px]'); sb.classList.add('left-0'); ov.classList.remove('hidden'); this.style.opacity='0'; this.style.pointerEvents='none'; event.stopPropagation();">
    <span class="material-symbols-outlined" style="font-size:24px;">menu</span>
</button>
'''

SCRIPT = """
<script>
// closeSidebarOnOutsideClick
document.addEventListener('DOMContentLoaded', function() {
    document.addEventListener('click', function(event) {
        const sidebar = document.getElementById('sidebar');
        const menuBtn = document.getElementById('mobile-menu-btn');
        const overlay = document.getElementById('sidebar-overlay');
        if (sidebar && sidebar.classList.contains('left-0') && window.innerWidth < 768) {
            if (!sidebar.contains(event.target) && (!menuBtn || !menuBtn.contains(event.target))) {
                sidebar.classList.remove('left-0');
                sidebar.classList.add('-left-[290px]');
                if(overlay) overlay.classList.add('hidden');
                if(menuBtn) { menuBtn.style.opacity='1'; menuBtn.style.pointerEvents='auto'; }
            }
        }
    });
});
</script>
"""

count = 0
for filepath in files:
    with open(filepath, 'r') as f:
        content = f.read()

    original = content

    # 1. Update NAV
    content = content.replace(NAV_OLD, NAV_NEW)

    # 2. Update Header
    content = re.sub(r'left-\[280px\]', 'left-0 md:left-[280px]', content)

    # 3. Update Main
    content = re.sub(r'pl-\[280px\]', 'pl-0 md:pl-[280px]', content)
    content = re.sub(r'ml-\[280px\]', 'ml-0 md:ml-[280px]', content)

    # 4. Inject Hamburger menu in header
    if 'id="mobile-menu-btn"' not in content and '<header' in content:
        # Insert inside the first flex child of header
        # pattern: <header ...> \n <div class="flex items-center gap-gutter flex-1">
        content = re.sub(r'(<header[^>]*>\s*<div[^>]*flex-1[^>]*>)', r'\1' + HAMBURGER, content, count=1)
        
    # 5. Add overlay script
    if 'id="sidebar"' in content and 'closeSidebarOnOutsideClick' not in content:
        content = content.replace('</body>', SCRIPT + '\n</body>')

    # Mobile Header Polish
    content = content.replace(
        '<div class="relative flex items-center justify-center">',
        '<div class="relative flex items-center justify-center hidden md:flex">'
    )
    content = content.replace(
        '<div class="ml-4 w-10 h-10 rounded-full bg-surface-container overflow-hidden border border-outline-variant cursor-pointer">',
        '<div class="ml-4 w-10 h-10 rounded-full bg-surface-container overflow-hidden border border-outline-variant cursor-pointer hidden md:block">'
    )
    content = content.replace(
        'class="ml-2 h-[40px] px-4 rounded-lg bg-primary text-on-primary font-label-lg text-label-lg flex items-center gap-2',
        'class="ml-2 h-[36px] px-2 md:px-4 rounded-lg bg-primary text-on-primary font-label-lg text-label-lg flex items-center gap-1 md:gap-2 text-xs md:text-sm'
    )
    content = content.replace(
        'class="font-headline-md text-headline-md text-primary"',
        'class="font-headline-md text-sm md:text-headline-md text-primary truncate"'
    )
    
    # Fallback injection if the exact flex-1 div pattern isn't matched
    if 'id="mobile-menu-btn"' not in content and '<header' in content:
        content = re.sub(r'(<header[^>]*>\s*<div[^>]*>)', r'\1' + HAMBURGER, content, count=1)

    if content != original:
        count += 1
        with open(filepath, 'w') as f:
            f.write(content)

print(f"Applied mobile fix to {count} HTML files!")
