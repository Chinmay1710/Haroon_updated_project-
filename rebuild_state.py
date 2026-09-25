import os

BOTTOM_NAV = '''
<!-- Mobile Bottom Navigation -->
<nav id="mobile-bottom-nav" class="md:hidden fixed bottom-0 left-0 right-0 h-16 bg-surface shadow-[0_-4px_15px_rgba(0,0,0,0.1)] z-40 flex items-center justify-around px-2 border-t border-outline-variant/20">
    <a href="javascript:window.API.navigate('dashboard')" class="flex flex-col items-center gap-1 p-2 text-on-surface-variant hover:text-primary transition-colors">
        <span class="material-symbols-outlined text-[24px]">home</span>
        <span class="text-[10px] font-medium">Home</span>
    </a>
    <a href="javascript:window.API.navigate('orders_list')" class="flex flex-col items-center gap-1 p-2 text-primary hover:text-primary transition-colors">
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

html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/orders_list.html"
with open(html_file, 'r') as f:
    html_content = f.read()

# Add bottom nav
if 'id="mobile-bottom-nav"' not in html_content:
    html_content = html_content.replace('</body>', BOTTOM_NAV + '\n</body>')

# Add manifest
if 'rel="manifest"' not in html_content:
    html_content = html_content.replace('</head>', '  <link rel="manifest" href="../manifest.json">\n</head>')

with open(html_file, 'w') as f:
    f.write(html_content)
    
print("Added nav and manifest back!")
