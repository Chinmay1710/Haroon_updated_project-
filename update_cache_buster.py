import glob
import os

html_files = glob.glob("/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/*.html")

for file in html_files:
    with open(file, 'r') as f:
        content = f.read()
    
    # Replace v=1787471943 with v=1787471999
    content = content.replace("?v=1787471943", "?v=1787471999")
    
    with open(file, 'w') as f:
        f.write(content)

print("Updated cache busters in all HTML files")
