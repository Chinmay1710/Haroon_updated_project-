import re

# Fix HTML id
html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/deliveries.html"
with open(html_file, 'r') as f:
    content = f.read()

content = content.replace(
    '<input class="w-full h-10 pl-10 pr-4 rounded-lg border border-outline-variant bg-surface-container-lowest focus:border-primary focus:ring-1 focus:ring-primary text-body-md placeholder:text-on-surface-variant"',
    '<input id="delivery-search" class="w-full h-10 pl-10 pr-4 rounded-lg border border-outline-variant bg-surface-container-lowest focus:border-primary focus:ring-1 focus:ring-primary text-body-md placeholder:text-on-surface-variant"'
)

with open(html_file, 'w') as f:
    f.write(content)

# Fix JS logic
js_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/deliveries.js"
with open(js_file, 'r') as f:
    js_content = f.read()

# Add event listener
init_search = """ setupFilters();
 loadDeliveries();
 }"""
new_init = """ setupFilters();
 const searchInput = document.getElementById('delivery-search');
 if (searchInput) {
     searchInput.addEventListener('input', renderDeliveries);
 }
 loadDeliveries();
 }"""
js_content = js_content.replace(init_search, new_init)

# Update renderDeliveries to filter by search query
render_search = """function renderDeliveries() {
 const container = document.getElementById('deliveries-container');"""

new_render = """function renderDeliveries() {
 const container = document.getElementById('deliveries-container');
 const q = (document.getElementById('delivery-search')?.value || '').toLowerCase();"""

js_content = js_content.replace(render_search, new_render)

# Find where it filters activeFilter
filter_logic = """ let filtered = allDeliveries.filter(d => {
 if (activeFilter === 'All') return true;
 if (activeFilter === 'Pending') return !d.is_delivered;
 if (activeFilter === 'Delivered') return d.is_delivered;
 return true;
 });"""

new_filter = """ let filtered = allDeliveries.filter(d => {
 let matchesStatus = true;
 if (activeFilter === 'Pending') matchesStatus = !d.is_delivered;
 if (activeFilter === 'Delivered') matchesStatus = d.is_delivered;
 
 if (!matchesStatus) return false;
 
 if (q) {
    const custName = (d.customer_name || '').toLowerCase();
    const orderNum = (d.order_number || '').toLowerCase();
    const orderId = (d.order_id || '').toLowerCase();
    if (!custName.includes(q) && !orderNum.includes(q) && !orderId.includes(q)) {
        return false;
    }
 }
 return true;
 });"""

js_content = js_content.replace(filter_logic, new_filter)

with open(js_file, 'w') as f:
    f.write(js_content)

print("Fixed deliveries search!")
