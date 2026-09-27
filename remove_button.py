import glob
import re

html_files = glob.glob("app/assets/www/html/*.html")
total_removed = 0

for f in html_files:
    with open(f, "r") as file:
        content = file.read()
    
    # Find the header block
    header_pattern = re.compile(r'(<header.*?</header>)', re.IGNORECASE | re.DOTALL)
    
    def replace_in_header(match):
        header_html = match.group(1)
        # Find the New Order button inside the header
        btn_pattern = re.compile(r'<button[^>]*onclick="window\.API\.navigate\(\'new_order\'\)"[^>]*>.*?New Order\s*</button>', re.IGNORECASE | re.DOTALL)
        new_header, count = btn_pattern.subn("", header_html)
        if count > 0:
            global total_removed
            total_removed += count
        return new_header

    new_content = header_pattern.sub(replace_in_header, content)
    
    if new_content != content:
        with open(f, "w") as file:
            file.write(new_content)
        print(f"Removed from {f}")

print(f"Total buttons removed: {total_removed}")
