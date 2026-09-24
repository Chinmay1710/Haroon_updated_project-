import os
import glob
import re

def fix_imports():
    # Find all python files in app directory
    target_dir = os.path.join(os.path.dirname(__file__), "app")
    
    # We want to replace:
    # from app.repositories.settings_repo import SettingsRepository
    # with:
    # from app.repositories.firebase.settings_repo import SettingsRepository
    
    pattern = re.compile(r"from app\.repositories\.([a-z_]+_repo)\b")
    
    files_changed = 0
    for root, _, files in os.walk(target_dir):
        for f in files:
            if f.endswith(".py") and "firebase" not in root:
                file_path = os.path.join(root, f)
                with open(file_path, "r", encoding="utf-8") as file:
                    content = file.read()
                    
                new_content = pattern.sub(r"from app.repositories.firebase.\1", content)
                
                if new_content != content:
                    with open(file_path, "w", encoding="utf-8") as file:
                        file.write(new_content)
                    print(f"Updated imports in {file_path}")
                    files_changed += 1
                    
    print(f"Total files updated: {files_changed}")

if __name__ == "__main__":
    fix_imports()
