html_file = "/Users/chinmay/Documents/Haroon_tailer/app/assets/www/html/workers.html"
with open(html_file, 'r') as f:
    content = f.read()

# Tab 1: Workers Ledger
t1_bad = """<div class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest flex-1">
<div class="overflow-auto h-full">"""
t1_good = """<div class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest w-full overflow-hidden">
<div class="w-full overflow-x-auto">"""
content = content.replace(t1_bad, t1_good)

# Tab 2: Pending
t2_bad = """<div class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest">
 <table class="w-full text-left border-collapse">"""
t2_good = """<div class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest w-full overflow-hidden">
 <div class="w-full overflow-x-auto">
 <table class="w-full text-left border-collapse min-w-[700px]">"""
content = content.replace(t2_bad, t2_good)
content = content.replace(
    """ </tbody>
 </table>
 </div>
</div>""",
    """ </tbody>
 </table>
 </div>
 </div>
</div>"""
)

# Tab 3: Rates
t3_bad = """<div class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest">
 <table class="w-full text-left border-collapse">"""
t3_good = """<div class="bg-surface-container-lowest rounded-xl shadow-sm border border-surface-container-highest w-full overflow-hidden">
 <div class="w-full overflow-x-auto">
 <table class="w-full text-left border-collapse min-w-[500px]">"""
content = content.replace(t3_bad, t3_good)
# The replace above will only hit the one in tab-rates because the one in tab-pending was already modified!
content = content.replace(
    """ </tbody>
 </table>
 </div>
</div>

</main>""",
    """ </tbody>
 </table>
 </div>
 </div>
</div>

</main>"""
)

with open(html_file, 'w') as f:
    f.write(content)

print("Fixed horizontal scrolling on worker tables!")
