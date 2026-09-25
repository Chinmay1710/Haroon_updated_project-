import re

html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/orders_list.html"
with open(html_file, 'r') as f:
    html_content = f.read()

# Make the orders container scrollable horizontally on mobile, and set a minimum width so it doesn't squish
if 'id="orders-container"' in html_content:
    html_content = html_content.replace('id="orders-container"', 'id="orders-container" style="min-width: 900px;"')
    
    # Wrap the orders container in a scrollable div
    html_content = html_content.replace('<div class="flex flex-col gap-stack_sm" id="orders-container"', '<div class="overflow-x-auto w-full"><div class="flex flex-col gap-stack_sm" id="orders-container"')
    # Find the closing tag of orders-container. 
    # It's at the end, just before </main>
    html_content = html_content.replace('</main>', '</div>\n</main>')
    
    with open(html_file, 'w') as f:
        f.write(html_content)
        print("Wrapped orders container in horizontal scroll!")
else:
    print("orders-container not found")

