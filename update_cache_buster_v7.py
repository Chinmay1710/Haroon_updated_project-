import glob

html_files = glob.glob("/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/*.html")

for file in html_files:
    with open(file, 'r') as f:
        content = f.read()
    
    content = content.replace("?v=1787472010", "?v=1787472013")
    content = content.replace("?v=1787471943", "?v=1787472013")
    
    with open(file, 'w') as f:
        f.write(content)

print("Updated cache busters to v7")
