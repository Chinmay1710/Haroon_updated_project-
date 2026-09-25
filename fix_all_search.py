import glob
import re

html_files = glob.glob("/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/*.html")

for file in html_files:
    if file.endswith("stitching_slip_preview.html") or file.endswith("new_order.html") or "details" in file:
        continue

    with open(file, 'r') as f:
        content = f.read()

    # If it has a hidden search in the top header
    if 'hidden md:block' in content and 'type="text"' in content:
        # Extract the entire hidden div
        match = re.search(r'<div class="[^"]*hidden md:block[^"]*">.*?<input[^>]+type="text"[^>]+>.*?</div>', content, re.DOTALL)
        if match:
            search_html = match.group(0)
            
            # Remove it from its original place
            content = content.replace(search_html, '')
            
            # Make it visible and responsive
            new_search_html = search_html.replace('hidden md:block', 'w-full md:w-80 mt-4 md:mt-0')
            if 'relative' not in new_search_html:
                new_search_html = new_search_html.replace('class="', 'class="relative ')
                
            # Find the best place to inject it in main
            # usually <h1 or <h2 in the main section followed by a description
            if '<p class="font-body-md' in content:
                # Find the first paragraph under the title
                inject_pos = content.find('</p>')
                if inject_pos != -1:
                    inject_pos += 4
                    # insert into the div
                    content = content[:inject_pos] + '\n</div>\n' + new_search_html + '\n<div>' + content[inject_pos:]
                    
            with open(file, 'w') as f:
                f.write(content)
            print(f"Moved search in {file}")

