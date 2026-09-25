import glob

html_files = glob.glob("/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/*.html")

for file in html_files:
    with open(file, 'r') as f:
        content = f.read()
    
    content = content.replace("?v=1787472020", "?v=1787472025")
    
    with open(file, 'w') as f:
        f.write(content)

print("Updated cache busters to v10")
