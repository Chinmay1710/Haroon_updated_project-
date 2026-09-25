html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/payments.html"
with open(html_file, 'r') as f:
    content = f.read()

# Remove the duplicated button remnant
remnant = """<span class="material-symbols-outlined">add</span>
 Add Payment
 </button>"""

if content.count(remnant) > 1:
    # Find the last occurrence and remove it
    last_idx = content.rfind(remnant)
    content = content[:last_idx] + content[last_idx + len(remnant):]
    
    with open(html_file, 'w') as f:
        f.write(content)
    print("Cleaned up button remnant!")
else:
    print("No duplicates found.")

