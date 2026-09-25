import re

css_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/css/input.css"

with open(css_file, 'r') as f:
    content = f.read()

# Remove overflow-x hidden
block = """    html, body {
        overflow-x: hidden;
        width: 100%;
    }"""

if block in content:
    content = content.replace(block, "")
    with open(css_file, 'w') as f:
        f.write(content)
    print("Reverted overflow-x: hidden!")
else:
    print("Block not found!")

