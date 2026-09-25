import re

html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/orders_list.html"
with open(html_file, 'r') as f:
    content = f.read()

# Fix layout margins
content = content.replace('ml-[280px]', 'ml-0 md:ml-[280px]')
content = content.replace('left-[280px]', 'left-0 md:left-[280px]')

# Inject hamburger menu button in top header if missing
hamburger_html = '''<button id="mobile-menu-btn" class="md:hidden mr-3 w-10 h-10 flex items-center justify-center text-on-surface rounded-lg relative z-[10000]" onclick="var sb=document.getElementById('sidebar'); var ov=document.getElementById('sidebar-overlay'); sb.classList.remove('-left-[290px]'); sb.classList.add('left-0'); ov.classList.remove('hidden'); this.style.opacity='0'; this.style.pointerEvents='none'; event.stopPropagation();">
    <span class="material-symbols-outlined" style="font-size:24px;">menu</span>
</button>
<h2'''

if '<h2 class="font-headline-md text-headline-md text-primary' in content and 'id="mobile-menu-btn"' not in content:
    content = content.replace('<h2 class="font-headline-md text-headline-md text-primary', hamburger_html + ' class="font-headline-md text-headline-md text-primary')

with open(html_file, 'w') as f:
    f.write(content)
print("Fixed header layout and injected hamburger!")

