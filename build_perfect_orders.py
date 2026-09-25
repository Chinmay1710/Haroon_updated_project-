import subprocess
import re

# 1. Restore original files
subprocess.run(['git', 'restore', '/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/orders_list.html'])
subprocess.run(['git', 'restore', '/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/orders.js'])

# 2. Fix orders_list.html tabs horizontal scroll pushing issue
html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/orders_list.html"
with open(html_file, 'r') as f:
    html_content = f.read()

# Remove the -mx-4 px-4 which causes horizontal scroll on the page
html_content = html_content.replace('-mx-4 px-4 sm:mx-0 sm:px-0', '')
with open(html_file, 'w') as f:
    f.write(html_content)

# 3. Inject Mobile Card into orders.js
js_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/orders.js"
with open(js_file, 'r') as f:
    js_content = f.read()

pattern = r"card\.innerHTML\s*=\s*`\s*(?:\$\{errorHighlight\})?(.*?)`;"
match = re.search(pattern, js_content, re.DOTALL)
if match:
    original_html = match.group(1).strip()
    
    # Hide all desktop flex columns on mobile
    desktop_html = original_html.replace('class="col-span-1 ', 'class="hidden md:flex col-span-1 ')
    
    mobile_html = """card.innerHTML = `
<!-- MOBILE CARD (Hidden on Desktop) -->
<div class="flex flex-col w-full md:hidden gap-4 relative z-10 box-border" style="word-wrap: break-word;">
    ${errorHighlight}
    
    <!-- 1 & 2: Order Number & Status -->
    <div class="flex justify-between items-start gap-2">
        <div class="font-bold text-primary text-base">${o.order_number}</div>
        <div class="inline-flex items-center px-2.5 py-1 rounded-full font-label-sm text-[11px] ${statusBg} ${statusColor}">
            ${isOverdue ? 'OVERDUE' : displayStatus}
        </div>
    </div>
    
    <!-- 3 & 4: Customer Name & Mobile -->
    <div class="flex flex-col">
        <div class="text-[11px] text-on-surface-variant uppercase font-semibold mb-0.5">Customer</div>
        <div class="font-bold text-on-surface text-[15px]">${o.customer_name}</div>
        ${o.customer_mobile ? `<div class="text-[13px] text-on-surface-variant">${o.customer_mobile}</div>` : ''}
    </div>

    <!-- 5: Item/Clothing -->
    <div class="flex flex-col">
        <div class="text-[11px] text-on-surface-variant uppercase font-semibold mb-0.5">Item</div>
        <div class="text-[14px] text-on-surface">${o.items || 'Custom'}</div>
    </div>

    <!-- 6 & 7: Dates -->
    <div class="flex flex-col">
        <div class="text-[11px] text-on-surface-variant uppercase font-semibold mb-0.5">Ordered</div>
        <div class="text-[14px] text-on-surface">${window.API.formatDate(o.order_date)}</div>
    </div>
    <div class="flex flex-col">
        <div class="text-[11px] text-on-surface-variant uppercase font-semibold mb-0.5">Delivery</div>
        <div class="text-[14px] font-bold ${isOverdue || isUrgent ? 'text-error' : 'text-on-surface'}">${window.API.formatDate(o.delivery_date)}</div>
    </div>

    <!-- 8, 9, 10: Financials -->
    <div class="flex flex-col gap-1 bg-surface-container-lowest p-3 rounded-lg border border-outline-variant/30">
        <div class="flex justify-between items-center">
            <span class="text-[12px] text-on-surface-variant uppercase font-semibold">Total</span>
            <span class="font-bold text-primary text-[15px]">${window.API.formatCurrency(o.total_amount)}</span>
        </div>
        ${o.advance_payment > 0 ? `
        <div class="flex justify-between items-center">
            <span class="text-[12px] text-on-surface-variant uppercase font-semibold">Paid</span>
            <span class="font-bold text-green-600 text-[14px]">${window.API.formatCurrency(o.advance_payment)}</span>
        </div>
        ` : ''}
        ${o.balance_amount > 0 ? `
        <div class="flex justify-between items-center">
            <span class="text-[12px] text-on-surface-variant uppercase font-semibold">Remaining</span>
            <span class="font-bold text-error text-[14px]">${window.API.formatCurrency(o.balance_amount)}</span>
        </div>
        ` : ''}
    </div>

    <!-- 11: Actions -->
    <div class="flex flex-col gap-2 mt-1">
        ${(o.status !== 'STITCHING_COMPLETE' && o.status !== 'DELIVERED' && o.status !== 'CANCELLED') ? `
        <button class="mark-complete-btn w-full py-3 rounded-lg bg-primary/10 text-primary font-bold text-[14px] hover:bg-primary hover:text-on-primary transition-colors flex justify-center items-center gap-2" title="Mark Complete">
            <span class="material-symbols-outlined text-[18px]">check_circle</span>
            Mark Complete
        </button>
        ` : ''}
        <button class="w-full py-3 rounded-lg bg-primary text-on-primary font-bold text-[14px] hover:opacity-90 transition-colors flex justify-center items-center" onclick="event.stopPropagation(); window.API.navigate('order_details')">
            View Order
        </button>
    </div>
</div>

<!-- DESKTOP TABLE ROW (Hidden on Mobile) -->
""" + desktop_html + """
`;"""
    
    # We must also change card padding on mobile to be consistent with vertical layout
    js_content = js_content.replace('p-4 hover:shadow-md', 'p-4 hover:shadow-md')
    
    js_content = js_content[:match.start()] + mobile_html + js_content[match.end():]
    
    with open(js_file, 'w') as f:
        f.write(js_content)
    print("Injected perfect mobile card into orders.js!")

