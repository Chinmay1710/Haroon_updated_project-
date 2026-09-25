import os
import glob
import re

html_dir = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html"
files = glob.glob(os.path.join(html_dir, "*.html"))

HAMBURGER = '''
<button id="mobile-menu-btn" class="md:hidden mr-3 w-10 h-10 flex items-center justify-center text-on-surface rounded-lg relative z-[10000]" onclick="var sb=document.getElementById('sidebar'); var ov=document.getElementById('sidebar-overlay'); sb.classList.remove('-left-[290px]'); sb.classList.add('left-0'); ov.classList.remove('hidden'); this.style.opacity='0'; this.style.pointerEvents='none'; event.stopPropagation();">
    <span class="material-symbols-outlined" style="font-size:24px;">menu</span>
</button>
'''

count = 0
for filepath in files:
    with open(filepath, 'r') as f:
        content = f.read()

    original = content
    
    # Check if hamburger button is actually missing
    if 'id="mobile-menu-btn"' not in content or '<button id="mobile-menu-btn"' not in content:
        # We need to inject it!
        if '<header' in content:
            # Find the header and the first div inside it
            # Using regex with DOTALL to skip comments
            content = re.sub(r'(<header[^>]*>.*?<div[^>]*flex-1[^>]*>)', r'\1' + HAMBURGER, content, count=1, flags=re.DOTALL)
            
            # If that didn't work (maybe no flex-1), try just the first div
            if '<button id="mobile-menu-btn"' not in content:
                content = re.sub(r'(<header[^>]*>.*?<div[^>]*>)', r'\1' + HAMBURGER, content, count=1, flags=re.DOTALL)

    if content != original:
        count += 1
        with open(filepath, 'w') as f:
            f.write(content)

print(f"Fixed {count} HTML files!")
