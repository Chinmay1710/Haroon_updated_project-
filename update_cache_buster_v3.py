import glob
import os

html_files = glob.glob("/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/*.html")

for file in html_files:
    with open(file, 'r') as f:
        content = f.read()
    
    # Replace v=1787471999 with v=1787472001
    content = content.replace("?v=1787471999", "?v=1787472001")
    
    with open(file, 'w') as f:
        f.write(content)

print("Updated cache busters to v3")
