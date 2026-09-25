html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/deliveries.html"
with open(html_file, 'r') as f:
    content = f.read()

bad = """<p class="font-body-lg text-body-lg text-on-surface-variant">Manage order fulfillment and delivery schedules.</p>
</div>
</div>
<div class="relative w-full md:w-80">"""
good = """<p class="font-body-lg text-body-lg text-on-surface-variant">Manage order fulfillment and delivery schedules.</p>
</div>
<div class="relative w-full md:w-80">"""

content = content.replace(bad, good)
with open(html_file, 'w') as f:
    f.write(content)
print("Fixed!")
