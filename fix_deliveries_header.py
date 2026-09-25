html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/deliveries.html"
with open(html_file, 'r') as f:
    content = f.read()

bad = """<h2 class="md:hidden font-headline-md text-headline-md text-primary font-bold">Tailor Manager</h2>

<!-- Right: Actions & Profile -->"""
good = """<h2 class="md:hidden font-headline-md text-headline-md text-primary font-bold">Tailor Manager</h2>
</div>
<!-- Right: Actions & Profile -->"""

content = content.replace(bad, good)
with open(html_file, 'w') as f:
    f.write(content)
print("Fixed header closure!")
