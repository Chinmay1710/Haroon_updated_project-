import sys, os
exe_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath("app/web/tunnel.py")))), "cloudflared.exe")
if not os.path.exists(exe_path):
    exe_path = "cloudflared.exe" if os.path.exists("cloudflared.exe") else "cloudflared"
print("EXE PATH IS:", exe_path)
import subprocess
try:
    p = subprocess.Popen([exe_path, "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = p.communicate()
    print("OUTPUT:", out, err)
except Exception as e:
    print("ERROR:", e)
