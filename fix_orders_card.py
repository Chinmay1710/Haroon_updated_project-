import re

js_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/orders.js"

with open(js_file, 'r') as f:
    content = f.read()

# Extract the original innerHTML block
pattern = r"card\.innerHTML\s*=\s*`\s*(?:\$\{errorHighlight\})?(.*?)`;"
match = re.search(pattern, content, re.DOTALL)
if match:
    original_html = match.group(1).strip()
    # The original starts with <div class="col-span-1 md:col-span-2...
    
    new_html = """card.innerHTML = `
<!-- Mobile Card Layout (hidden on md) -->
<div class="flex flex-col gap-2 md:hidden w-full relative z-10">
    ${errorHighlight}
    <div class="flex justify-between items-start">
        <div class="flex flex-col">
            <span class="font-label-lg text-primary text-[16px]">${o.order_number}</span>
            <span class="font-headline-sm font-bold text-on-surface">${o.customer_name}</span>
        </div>
        <div class="flex flex-col items-end">
            <span class="inline-flex items-center px-2 py-1 rounded-full font-label-sm text-[10px] ${statusBg} ${statusColor}">
                ${displayStatus}
            </span>
        </div>
    </div>
    
    <div class="flex flex-col mb-1">
        <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Item</span>
        <span class="font-body-md text-on-surface font-medium">${o.items || 'Custom'}</span>
    </div>

    <div class="flex justify-between items-center bg-surface-container-lowest p-2 rounded-lg border border-outline-variant/30">
        <div class="flex flex-col items-start">
            <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Total</span>
            <span class="font-body-md font-bold text-primary">${window.API.formatCurrency(o.total_amount)}</span>
        </div>
        <div class="flex flex-col items-center">
            <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Paid</span>
            <span class="font-body-md font-bold text-green-600">${window.API.formatCurrency(o.advance_payment)}</span>
        </div>
        <div class="flex flex-col items-end">
            <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Remaining</span>
            <span class="font-body-md font-bold text-error">${window.API.formatCurrency(o.balance_amount)}</span>
        </div>
    </div>

    <div class="flex justify-between items-center mt-2">
        <div class="flex flex-col">
            <span class="font-label-sm text-on-surface-variant uppercase text-[10px]">Delivery</span>
            <div class="flex items-center gap-1">
                <span class="font-body-md font-bold ${isOverdue ? 'text-error' : 'text-on-surface'}">${window.API.formatDate(o.delivery_date)}</span>
                ${urgentBadge}
            </div>
        </div>
        <button class="h-9 px-4 rounded-lg bg-primary text-on-primary font-label-md" onclick="event.stopPropagation(); window.API.navigate('order_details')">
            View
        </button>
    </div>
</div>

<!-- Desktop Table Row (hidden on mobile) -->
<div class="hidden md:contents">
""" + original_html + """
</div>
`;"""
    
    # Replace the old card.innerHTML = `...`; with the new one
    content = content[:match.start()] + new_html + content[match.end():]
    
    # Also fix the card className to remove grid-cols-1 because we are using a block div inside!
    # Wait, if we keep grid-cols-1, the inner divs will just be placed inside the single column. That's fine!
    
    with open(js_file, 'w') as f:
        f.write(content)
    print("Successfully injected responsive Orders card!")
else:
    print("Could not find the target block")
