import os
import glob

html_dir = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html"
files = glob.glob(os.path.join(html_dir, "*.html"))

for filepath in files:
    with open(filepath, 'r') as f:
        content = f.read()
    
    if 'rel="manifest"' not in content:
        content = content.replace('</head>', '  <link rel="manifest" href="../manifest.json">\n</head>')
        
    with open(filepath, 'w') as f:
        f.write(content)
