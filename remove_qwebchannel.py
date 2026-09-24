import os
import glob
import re

html_dir = "app/assets/www/html"
for filepath in glob.glob(os.path.join(html_dir, "*.html")):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Remove qwebchannel script
    content = re.sub(r'<script src="qrc:///qtwebchannel/qwebchannel\.js"></script>', '', content)
    
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)

print("Removed qwebchannel script from all HTML files.")
