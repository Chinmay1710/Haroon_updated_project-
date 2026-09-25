import glob

html_files = glob.glob("/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/*.html")

for file in html_files:
    if "workers" in file:
        continue
    with open(file, 'r') as f:
        content = f.read()

    # If it has <main> without overflow-y-auto, and body has min-h-screen, let's just make main overflow-auto
    # Wait, some pages like dashboard.html might break if we force overflow-auto? No, overflow-auto is harmless on main.
    
    # We will ONLY target flex flex-col max-w-[1600px] or max-w-7xl which are our typical main containers
    modified = False
    if 'max-w-[1600px]' in content or 'max-w-7xl' in content:
        if '<main' in content and 'overflow-auto' not in content and 'overflow-y-auto' not in content:
            # Let's add overflow-auto to the main tag
            # Actually just replacing 'flex flex-col ' with 'flex flex-col overflow-auto '
            content = content.replace('flex-1 flex flex-col max-w-[1600px]', 'flex-1 flex flex-col max-w-[1600px] overflow-auto')
            content = content.replace('flex-1 mt-[72px] p-container_padding max-w-7xl', 'flex-1 mt-[72px] p-container_padding max-w-7xl overflow-auto')
            modified = True
            
    if modified:
        with open(file, 'w') as f:
            f.write(content)
            
print("Fixed other scrolling!")
