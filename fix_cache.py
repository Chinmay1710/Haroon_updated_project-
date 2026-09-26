import os
import glob
import re

html_files = glob.glob('app/assets/www/html/*.html')
for filepath in html_files:
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Fix the double ?v=
    content = re.sub(r'\?v=\d+\?v=\d+', '?v=2026092602', content)
    # Fix the single ?v=
    content = re.sub(r'\?v=\d+', '?v=2026092602', content)
    
    with open(filepath, 'w') as f:
        f.write(content)

print("Fixed cache busting versions")
