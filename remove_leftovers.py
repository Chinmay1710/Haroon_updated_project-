import os
import glob
import re

html_dir = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html"
files = glob.glob(os.path.join(html_dir, "*.html"))

count = 0
for filepath in files:
    with open(filepath, 'r') as f:
        content = f.read()
        
    original = content
    
    # Remove the empty button wrapper in add_measurement.html
    pattern1 = r'<button class="w-10 h-10 rounded-full overflow-hidden border-2 border-surface-container focus:outline-none focus:border-primary transition-colors">\s*</button>'
    content = re.sub(pattern1, '', content, flags=re.IGNORECASE)
    
    # Remove the wrapper div and logo.png in deliveries.html
    pattern2 = r'<div class="w-10 h-10 rounded-full overflow-hidden border-2 border-surface-container cursor-pointer hover:border-primary transition-colors">\s*<img[^>]*src=\'\\"../img/logo\.png\\"/\'[^>]*>\s*</div>'
    content = re.sub(pattern2, '', content, flags=re.IGNORECASE)

    # Just in case there's an empty div
    pattern3 = r'<div class="w-10 h-10 rounded-full overflow-hidden border-2 border-surface-container cursor-pointer hover:border-primary transition-colors">\s*</div>'
    content = re.sub(pattern3, '', content, flags=re.IGNORECASE)
    
    # Also check if any empty div wrappers were left by the previous script
    pattern4 = r'<div class="ml-4 w-10 h-10 rounded-full bg-surface-container overflow-hidden border border-outline-variant cursor-pointer hidden md:block">\s*</div>'
    content = re.sub(pattern4, '', content, flags=re.IGNORECASE)

    pattern5 = r'<div class="ml-2">\s*</div>'
    content = re.sub(pattern5, '', content, flags=re.IGNORECASE)

    if content != original:
        count += 1
        with open(filepath, 'w') as f:
            f.write(content)

print(f"Removed leftovers from {count} HTML files!")
