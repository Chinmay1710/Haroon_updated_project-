import re

js_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/orders.js"
with open(js_file, 'r') as f:
    content = f.read()

# Replace all responsive classes to force desktop layout always
replacements = {
    'hidden md:grid': 'grid',
    'grid-cols-1 md:grid-cols-12': 'grid-cols-12',
    'col-span-1 md:col-span-': 'col-span-',
    'flex-row md:flex-col': 'flex-col',
    'justify-between md:justify-start': 'justify-start',
    'items-start md:items-center': 'items-center',
    'mt-2 md:mt-1': 'mt-1'
}

for old, new in replacements.items():
    content = content.replace(old, new)

with open(js_file, 'w') as f:
    f.write(content)

html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/orders_list.html"
with open(html_file, 'r') as f:
    html_content = f.read()

for old, new in replacements.items():
    html_content = html_content.replace(old, new)

with open(html_file, 'w') as f:
    f.write(html_content)

print("Forced desktop layout on mobile!")
