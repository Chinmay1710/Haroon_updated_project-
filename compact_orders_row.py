import re

js_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/orders.js"
with open(js_file, 'r') as f:
    content = f.read()

# 1. Add order-row-card class and make grid-cols-12 responsive padding/gap
content = content.replace(
    'card.className = `${cardBg} rounded-xl shadow-sm border ${cardBorder} p-4 hover:shadow-md transition-shadow group grid grid-cols-1 md:grid-cols-12 gap-4 items-center relative overflow-hidden cursor-pointer`;',
    'card.className = `order-row-card ${cardBg} rounded-xl shadow-sm border ${cardBorder} p-1 md:p-4 hover:shadow-md transition-shadow group grid grid-cols-12 gap-1 md:gap-4 items-center relative overflow-hidden cursor-pointer`;'
)

# 2. Force grid cols and layout for all screens
replacements = {
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

print("orders.js updated for compact row!")
