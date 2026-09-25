import re

css_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/css/input.css"

with open(css_file, 'r') as f:
    content = f.read()

# Add overflow-x hidden to body and html in the mobile media query
if 'html, body {' not in content:
    replacement = """    html, body {
        overflow-x: hidden;
        width: 100%;
    }
    body {"""
    content = content.replace('    body {', replacement)
    
    with open(css_file, 'w') as f:
        f.write(content)

print("Updated CSS to fix scroll")
