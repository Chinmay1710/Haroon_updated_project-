html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/workers.html"
with open(html_file, 'r') as f:
    content = f.read()

# Change overflow-hidden to overflow-auto on these card wrappers
content = content.replace(
    'class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest overflow-hidden flex-1"',
    'class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest flex-1"'
)
content = content.replace(
    'class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest overflow-hidden"',
    'class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest"'
)
content = content.replace(
    'class="overflow-x-auto h-full"',
    'class="overflow-auto h-full"'
)

# And ensure main has no flex-1 restriction if body is min-h-screen
# Actually let's just make sure the body can scroll vertically by removing overflow-x-hidden?
# No, overflow-x-hidden on body is to prevent horizontal scrollbar.
# Let's add overflow-y-auto to main if it's trapped in a flex layout.
# Wait, replacing <main class="..."> with <main class="... overflow-y-auto"> is safer!
if 'overflow-y-auto' not in content.split('<main')[1].split('>')[0]:
    content = content.replace(
        '<main class="mt-[72px] p-container_padding flex-1 flex flex-col max-w-[1600px] mx-auto w-full">',
        '<main class="mt-[72px] p-container_padding flex-1 flex flex-col max-w-[1600px] mx-auto w-full overflow-auto">'
    )

with open(html_file, 'w') as f:
    f.write(content)

print("Fixed workers scrolling!")
