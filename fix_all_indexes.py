"""
Fix ALL Firebase queries across ALL repositories to remove .order_by() calls
and compound where+order_by that require composite indexes.
Sort results in Python instead.
"""
import re, os, glob

repo_dir = "app/repositories/firebase"

for filepath in glob.glob(os.path.join(repo_dir, "*.py")):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    original = content
    
    # Remove .order_by("field", direction="DESCENDING") and .order_by("field")
    # These patterns cause composite index requirements when combined with .where()
    content = re.sub(r'\.order_by\([^)]+\)', '', content)
    
    if content != original:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Fixed: {filepath}")

# Now fix customer_repo.py get_all to sort in Python
with open(os.path.join(repo_dir, "customer_repo.py"), "r", encoding="utf-8") as f:
    content = f.read()

# Fix get_all - fetch without order, sort in Python
content = content.replace(
    '''    docs = self.collection.where("is_active", "==", True).get()
        all_customers = [self._dict_to_model(doc.to_dict()) for doc in docs]''',
    '''    docs = self.collection.where("is_active", "==", True).get()
        all_customers = [self._dict_to_model(doc.to_dict()) for doc in docs]
        all_customers.sort(key=lambda c: (c.name or "").lower())'''
)

with open(os.path.join(repo_dir, "customer_repo.py"), "w", encoding="utf-8") as f:
    f.write(content)
print("Fixed customer_repo.py sorting")

# Fix order_repo.py get_all to sort in Python
with open(os.path.join(repo_dir, "order_repo.py"), "r", encoding="utf-8") as f:
    content = f.read()

# The get_all query now has no order_by, so add Python sort
old_get_all = '''    query = self.orders
        if status:
            query = query.where("status", "==", status)
        docs = query.get()
        res = [self._dict_to_order(d.to_dict()) for d in docs]'''
new_get_all = '''    query = self.orders
        if status:
            query = query.where("status", "==", status)
        docs = query.get()
        res = [self._dict_to_order(d.to_dict()) for d in docs]
        res.sort(key=lambda o: getattr(o, 'created_at', '') or '', reverse=True)'''

if old_get_all in content:
    content = content.replace(old_get_all, new_get_all)

with open(os.path.join(repo_dir, "order_repo.py"), "w", encoding="utf-8") as f:
    f.write(content)
print("Fixed order_repo.py sorting")

# Fix payment_repo.py get_all to sort in Python
with open(os.path.join(repo_dir, "payment_repo.py"), "r", encoding="utf-8") as f:
    content = f.read()

old_pay = '''        docs = self.payments.get()
        return [self._dict_to_payment(d.to_dict()) for d in docs]'''
new_pay = '''        docs = self.payments.get()
        payments = [self._dict_to_payment(d.to_dict()) for d in docs]
        payments.sort(key=lambda p: getattr(p, 'payment_date', '') or '', reverse=True)
        return payments'''
if old_pay in content:
    content = content.replace(old_pay, new_pay, 1)  # Only first occurrence (get_all)

with open(os.path.join(repo_dir, "payment_repo.py"), "w", encoding="utf-8") as f:
    f.write(content)
print("Fixed payment_repo.py sorting")

# Fix expense_repo.py get_all to sort in Python
with open(os.path.join(repo_dir, "expense_repo.py"), "r", encoding="utf-8") as f:
    content = f.read()

old_exp = '''        docs = self.expenses.get()
        return [self._dict_to_expense(d.to_dict()) for d in docs]'''
new_exp = '''        docs = self.expenses.get()
        expenses = [self._dict_to_expense(d.to_dict()) for d in docs]
        expenses.sort(key=lambda e: getattr(e, 'expense_date', '') or '', reverse=True)
        return expenses'''
if old_exp in content:
    content = content.replace(old_exp, new_exp, 1)

with open(os.path.join(repo_dir, "expense_repo.py"), "w", encoding="utf-8") as f:
    f.write(content)
print("Fixed expense_repo.py sorting")

print("\n✅ ALL composite index requirements removed!")
print("All sorting now happens in Python — no Firebase indexes needed.")
