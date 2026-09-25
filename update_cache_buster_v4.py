import glob
import os

html_files = glob.glob("/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/*.html")

for file in html_files:
    with open(file, 'r') as f:
        content = f.read()
    
    # Replace v=1787472001 with v=1787472005
    content = content.replace("?v=1787472001", "?v=1787472005")
    # Also catch any 1787471999 if it didn't update previously
    content = content.replace("?v=1787471999", "?v=1787472005")
    content = content.replace("?v=1787471943", "?v=1787472005")
    
    with open(file, 'w') as f:
        f.write(content)

print("Updated cache busters to v4")
