import re

js_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/orders.js"

with open(js_file, 'r') as f:
    content = f.read()

# I will find the block I injected earlier, which starts with `<!-- Mobile Card Layout (hidden on md) -->`
# and ends with `<!-- Desktop Table Row (hidden on mobile) -->\n<div class="hidden md:contents">\n`
# and then a `\n</div>\n`;` at the end.

# Let's just restore the file from git to be clean!
import subprocess
subprocess.run(['git', 'restore', js_file])

with open(js_file, 'r') as f:
    clean_content = f.read()

# Now find the original card.innerHTML
pattern = r"card\.innerHTML\s*=\s*`\s*(?:\$\{errorHighlight\})?(.*?)`;"
match = re.search(pattern, clean_content, re.DOTALL)
if match:
    original_html = match.group(1).strip()
    
    # In the original HTML, we need to add `hidden md:flex` to all the direct child divs!
    # The direct child divs look like `<div class="col-span-1 ... flex ...`
    # We can just replace `class="col-span-1` with `class="hidden md:flex col-span-1`
    desktop_html = original_html.replace('class="col-span-1 ', 'class="hidden md:flex col-span-1 ')
    # Wait, the 4th item is `<div class="col-span-1 md:col-span-1 flex...`. Replacing `class="col-span-1 ` covers it.
    # What about the last item: `<div class="col-span-1 md:col-span-2 flex justify-end`? It replaces it perfectly!

    new_html = """card.innerHTML = `
<!-- Mobile Card Layout (Hidden on md) -->
<div class="md:hidden flex flex-col gap-3 w-full p-1 box-border">
    ${errorHighlight}
    <div class="flex justify-between items-start w-full">
        <div class="flex flex-col min-w-0 flex-1 pr-2">
            <span class="font-label-lg text-primary text-[14px]">${o.order_number}</span>
            <span class="font-headline-sm font-bold text-on-surface truncate w-full">${o.customer_name}</span>
        </div>
        <div class="flex flex-col items-end shrink-0">
            <span class="inline-flex items-center px-2 py-1 rounded-full font-label-sm text-[10px] ${statusBg} ${statusColor}">
                ${displayStatus}
            </span>
        </div>
    </div>
    
    <div class="flex flex-col w-full">
        <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Item</span>
        <span class="font-body-md text-on-surface font-medium truncate w-full">${o.items || 'Custom'}</span>
    </div>

    <div class="flex justify-between items-center bg-surface-container-lowest p-2 rounded-lg border border-outline-variant/30 w-full overflow-hidden">
        <div class="flex flex-col items-start min-w-0 flex-1">
            <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Total</span>
            <span class="font-body-md font-bold text-primary truncate w-full">${window.API.formatCurrency(o.total_amount)}</span>
        </div>
        <div class="flex flex-col items-center min-w-0 flex-1">
            <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Paid</span>
            <span class="font-body-md font-bold text-green-600 truncate w-full">${window.API.formatCurrency(o.advance_payment)}</span>
        </div>
        <div class="flex flex-col items-end min-w-0 flex-1">
            <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Remain</span>
            <span class="font-body-md font-bold text-error truncate w-full">${window.API.formatCurrency(o.balance_amount)}</span>
        </div>
    </div>

    <div class="flex justify-between items-center mt-1 w-full gap-2">
        <div class="flex flex-col min-w-0 shrink-0">
            <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Delivery</span>
            <div class="flex items-center gap-1">
                <span class="font-body-md font-bold text-[13px] ${isOverdue ? 'text-error' : 'text-on-surface'}">${window.API.formatDate(o.delivery_date)}</span>
            </div>
        </div>
        <div class="flex items-center gap-2 shrink-0">
            ${(o.status !== 'STITCHING_COMPLETE' && o.status !== 'DELIVERED' && o.status !== 'CANCELLED') ? `
            <button class="mark-complete-btn px-2 py-1.5 rounded-md bg-primary/10 text-primary font-label-sm hover:bg-primary whitespace-nowrap border border-primary/20 flex items-center gap-1" title="Mark Complete">
                <span class="material-symbols-outlined text-[14px]">check_circle</span>
                Complete
            </button>
            ` : ''}
            <button class="px-3 py-1.5 rounded-md bg-primary text-on-primary font-label-sm flex items-center gap-1 whitespace-nowrap" onclick="event.stopPropagation(); window.API.navigate('order_details')">
                View
            </button>
        </div>
    </div>
</div>

<!-- Desktop Table Row (Hidden on mobile) -->
""" + desktop_html + """
`;"""
    
    clean_content = clean_content[:match.start()] + new_html + clean_content[match.end():]
    
    with open(js_file, 'w') as f:
        f.write(clean_content)
    print("Fixed Orders JS!")
else:
    print("Pattern not found!")

# Also fix orders_list.html tabs container to remove -mx-4
html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/orders_list.html"
with open(html_file, 'r') as f:
    html_content = f.read()

html_content = html_content.replace('-mx-4 px-4 sm:mx-0 sm:px-0', '')
html_content = html_content.replace('overflow-x-auto gap-2', 'overflow-x-auto gap-2 w-full')

with open(html_file, 'w') as f:
    f.write(html_content)
    print("Fixed Orders HTML!")

