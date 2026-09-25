import re

js_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/orders.js"

with open(js_file, 'r') as f:
    clean_content = f.read()

# Original card.innerHTML
pattern = r"card\.innerHTML\s*=\s*`\s*(?:\$\{errorHighlight\})?(.*?)`;"
match = re.search(pattern, clean_content, re.DOTALL)
if match:
    original_html = match.group(1).strip()
    
    # Hide desktop children
    desktop_html = original_html.replace('class="col-span-1 ', 'class="hidden md:flex col-span-1 ')

    new_html = """card.innerHTML = `
<!-- Mobile Ultra-Compact Row (Hidden on md) -->
<div class="md:hidden flex items-center gap-2 w-full p-2 box-border relative overflow-hidden">
    ${errorHighlight}
    
    <!-- Status Strip for overdue -->
    ${isOverdue ? '<div class="absolute left-0 top-0 bottom-0 w-1 bg-error"></div>' : ''}
    
    <!-- Col 1: Order Num & Status Dot -->
    <div class="w-12 shrink-0 flex flex-col items-center justify-center">
        <span class="font-label-sm text-primary text-[11px] font-bold leading-none mb-1">${o.order_number.replace('ORD-', '#')}</span>
        <div class="w-2.5 h-2.5 rounded-full ${statusBg.replace('bg-', 'bg-').replace('/10', '')} ${statusColor.replace('text-', 'bg-')} shadow-sm border border-white"></div>
    </div>
    
    <!-- Col 2: Name & Item -->
    <div class="flex-1 min-w-0 flex flex-col justify-center">
        <span class="font-headline-sm font-bold text-on-surface text-[13px] truncate w-full leading-tight mb-0.5">${o.customer_name}</span>
        <span class="font-body-sm text-on-surface-variant text-[11px] truncate w-full leading-tight">${o.items || 'Custom'}</span>
    </div>
    
    <!-- Col 3: Financials & Date -->
    <div class="w-16 shrink-0 flex flex-col items-end justify-center border-r border-outline-variant/30 pr-2 mr-1">
        <span class="font-body-md font-bold text-primary text-[12px] leading-tight">${window.API.formatCurrency(o.total_amount)}</span>
        <span class="font-label-sm text-[9px] ${o.balance_amount > 0 ? 'text-error' : 'text-green-600'} leading-tight">Rem ${window.API.formatCurrency(o.balance_amount).replace('₹', '')}</span>
    </div>
    
    <!-- Col 4: Action -->
    <div class="w-14 shrink-0 flex flex-col gap-1 items-end justify-center">
        ${(o.status !== 'STITCHING_COMPLETE' && o.status !== 'DELIVERED' && o.status !== 'CANCELLED') ? `
        <button class="mark-complete-btn w-full py-1 rounded bg-primary/10 text-primary font-bold text-[9px] hover:bg-primary border border-primary/20 flex justify-center items-center" title="Complete">
            Done
        </button>
        ` : ''}
        <button class="w-full py-1 rounded bg-primary text-on-primary font-bold text-[10px] flex justify-center items-center" onclick="event.stopPropagation(); window.API.navigate('order_details')">
            View
        </button>
    </div>
</div>

<!-- Desktop Table Row (Hidden on mobile) -->
""" + desktop_html + """
`;"""
    
    clean_content = clean_content[:match.start()] + new_html + clean_content[match.end():]
    
    # Also update card classes to have 0 padding on mobile so it looks like a tight row
    clean_content = clean_content.replace('p-4 hover:shadow-md', 'p-0 md:p-4 hover:shadow-md')
    
    with open(js_file, 'w') as f:
        f.write(clean_content)
    print("Fixed Orders JS with Ultra-Compact Mobile Row!")
else:
    print("Pattern not found!")

