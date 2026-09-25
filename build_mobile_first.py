import os
import glob
import re

html_dir = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html"
css_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/css/input.css"

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

MOBILE_CSS = '''
/* True Mobile-First App Adjustments */
@media (max-width: 768px) {
    body {
        -webkit-tap-highlight-color: transparent;
    }
    main {
        padding-bottom: 80px !important; /* Space for bottom nav */
        padding-left: 16px !important;
        padding-right: 16px !important;
        width: 100% !important;
        margin-left: 0 !important;
    }
    header {
        height: 64px !important;
    }
    /* Typography Overrides */
    .text-headline-md, .font-headline-md { font-size: 24px !important; line-height: 1.2 !important; }
    .text-title-lg, .font-title-lg { font-size: 20px !important; }
    .text-body-md, .font-body-md { font-size: 14px !important; }
    .text-label-lg, .font-label-lg { font-size: 14px !important; }
    
    /* Touch Targets */
    button, a, input, select { min-height: 44px; }
    
    /* Grid overrides */
    .grid-cols-2, .grid-cols-3, .grid-cols-4 {
        grid-template-columns: 1fr !important;
    }
    .mobile-2-col {
        grid-template-columns: repeat(2, 1fr) !important;
    }
    
    /* Fix horizontal scrolling */
    .overflow-x-auto {
        -webkit-overflow-scrolling: touch;
        padding-bottom: 4px;
    }
    
    /* Hide top hamburger if we use bottom nav 'More' ? User said top header should have hamburger, so we keep it! */
}
'''

# 1. Inject Bottom Nav into all HTML files
files = glob.glob(os.path.join(html_dir, "*.html"))
for filepath in files:
    with open(filepath, 'r') as f:
        content = f.read()
    
    if 'id="mobile-bottom-nav"' not in content:
        content = content.replace('</body>', BOTTOM_NAV + '\n</body>')
        
    # Active state for bottom nav based on filename
    basename = os.path.basename(filepath).replace('.html', '')
    if basename in ['dashboard', 'orders_list', 'customers_list', 'payments']:
        # This is a bit hacky, but highlights the active icon
        pattern = f"window.API.navigate('{basename}')\" class=\"flex flex-col items-center gap-1 p-2 text-on-surface-variant"
        replacement = f"window.API.navigate('{basename}')\" class=\"flex flex-col items-center gap-1 p-2 text-primary"
        content = content.replace(pattern, replacement)
        
    with open(filepath, 'w') as f:
        f.write(content)

# 2. Add Mobile CSS to input.css
with open(css_file, 'r') as f:
    css_content = f.read()

if 'True Mobile-First App Adjustments' not in css_content:
    with open(css_file, 'a') as f:
        f.write('\n' + MOBILE_CSS)

# 3. Create Manifest
manifest = """{
  "name": "Haroon Tailor",
  "short_name": "Tailor",
  "start_url": "/app/dashboard.html",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#0f172a",
  "icons": [
    {
      "src": "/admin_assets/img/logo.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/admin_assets/img/logo.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}"""
with open(os.path.join(html_dir, "../manifest.json"), 'w') as f:
    f.write(manifest)

print("Applied True Mobile-First layout foundation!")
