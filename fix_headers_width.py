import re

js_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/js/orders.js"
with open(js_file, 'r') as f:
    content = f.read()

# Make headers visible and compact
content = content.replace(
    '<div class="hidden md:grid grid-cols-12 gap-4 px-4 py-2 font-label-sm text-label-sm',
    '<div class="order-row-header grid grid-cols-12 gap-1 md:gap-4 px-1 md:px-4 py-2 font-label-sm text-label-sm'
)

with open(js_file, 'w') as f:
    f.write(content)

css_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/css/input.css"
with open(css_file, 'r') as f:
    css_content = f.read()

# Add smaller margins and apply the text scaling to the header too
css_content = css_content.replace(
    '.order-row-card * {',
    '.order-row-card *, .order-row-header * {'
)
css_content = css_content.replace(
    '.order-row-card .font-label-sm,',
    '.order-row-header, .order-row-card .font-label-sm,'
)
css_content = css_content.replace(
    '#orders-container {\n        padding-left: 2px !important;\n        padding-right: 2px !important;\n    }',
    '#orders-container {\n        padding-left: 6px !important;\n        padding-right: 6px !important;\n    }\n    .order-row-card {\n        padding-left: 4px !important;\n        padding-right: 4px !important;\n    }'
)

with open(css_file, 'w') as f:
    f.write(css_content)

print("Updated JS and CSS!")
