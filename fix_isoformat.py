import re

with open("app/ui/web_bridge.py", "r", encoding="utf-8") as f:
    content = f.read()

# Add the import at the top of the file, after the existing imports
if "from app.utils.date_utils import safe_isoformat" not in content:
    content = content.replace(
        "import logging",
        "import logging\nfrom app.utils.date_utils import safe_isoformat"
    )

# Replace patterns like:  x.isoformat() if x else ""
# With: safe_isoformat(x)
# Note: we need to be careful not to break things like date.today().isoformat()

# Pattern 1: o.order_date.isoformat() if o.order_date else ""
content = re.sub(
    r'(\w+)\.order_date\.isoformat\(\)\s*if\s*\1\.order_date\s*else\s*""',
    r'safe_isoformat(\1.order_date)',
    content
)

# Pattern 2: o.delivery_date.isoformat() if o.delivery_date else ""
content = re.sub(
    r'(\w+)\.delivery_date\.isoformat\(\)\s*if\s*(?:getattr\(\1,\s*"delivery_date",\s*None\)|(?:\1\.delivery_date))\s*else\s*""',
    r'safe_isoformat(\1.delivery_date)',
    content
)

# Pattern 3: x.updated_at.isoformat() if hasattr(x, "updated_at") and x.updated_at else ""
content = re.sub(
    r'(\w+)\.updated_at\.isoformat\(\)\s*if\s*hasattr\(\1,\s*"updated_at"\)\s*and\s*\1\.updated_at\s*else\s*""',
    r'safe_isoformat(getattr(\1, "updated_at", ""))',
    content
)

# Pattern 4: p.payment_date.isoformat() if p.payment_date else ""
content = re.sub(
    r'(\w+)\.payment_date\.isoformat\(\)\s*if\s*(?:hasattr\(\1,\s*"payment_date"\)\s*and\s*)?\1\.payment_date\s*else\s*""',
    r'safe_isoformat(\1.payment_date)',
    content
)

# Pattern 5: p.updated_at.isoformat() if hasattr(p, "updated_at") and p.updated_at else ""
content = re.sub(
    r'(\w+)\.updated_at\.isoformat\(\)\s*if\s*hasattr\(\1,\s*"updated_at"\)\s*and\s*\1\.updated_at\s*else\s*""',
    r'safe_isoformat(getattr(\1, "updated_at", ""))',
    content
)

# Pattern 6: m.updated_at.isoformat()  (no condition)
content = re.sub(
    r'(\w+)\.updated_at\.isoformat\(\)',
    r'safe_isoformat(\1.updated_at)',
    content
)

# Pattern 7: last_order_date.isoformat() if last_order_date else "-"
content = re.sub(
    r'last_order_date\.isoformat\(\)\s*if\s*last_order_date\s*else\s*"-"',
    r'safe_isoformat(last_order_date) or "-"',
    content
)

# Pattern 8: e.expense_date.isoformat() if e.expense_date else ""
content = re.sub(
    r'(\w+)\.expense_date\.isoformat\(\)\s*if\s*\1\.expense_date\s*else\s*""',
    r'safe_isoformat(\1.expense_date)',
    content
)

# Remove the local _safe_iso function definition (we have a global one now)
content = re.sub(
    r'\s+def _safe_iso\(val\):.*?return val\.isoformat\(\) if hasattr\(val, \'isoformat\'\) else str\(val\)',
    '',
    content,
    flags=re.DOTALL
)
content = content.replace('_safe_iso(p.payment_date)', 'safe_isoformat(p.payment_date)')
content = content.replace("_safe_iso(getattr(p, 'updated_at', ''))", "safe_isoformat(getattr(p, 'updated_at', ''))")

with open("app/ui/web_bridge.py", "w", encoding="utf-8") as f:
    f.write(content)

print("All .isoformat() calls made safe!")
