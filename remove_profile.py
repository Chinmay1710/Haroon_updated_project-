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
    
    # Remove HTML comment "<!-- Profile -->"
    content = re.sub(r'<!--\s*Profile\s*-->\s*', '', content, flags=re.IGNORECASE)
    
    # Remove wrapper div containing only the profile img
    pattern1 = r'<div[^>]*>\s*<img[^>]*profile\.png[^>]*>\s*</div>'
    content = re.sub(pattern1, '', content, flags=re.IGNORECASE)
    
    # Remove the img tag alone if it wasn't caught by the div wrapper
    pattern2 = r'<img[^>]*profile\.png[^>]*>'
    content = re.sub(pattern2, '', content, flags=re.IGNORECASE)
    
    if content != original:
        count += 1
        with open(filepath, 'w') as f:
            f.write(content)

print(f"Removed profile photo from {count} HTML files!")
