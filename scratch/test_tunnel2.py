from app.web.tunnel import NgrokTunnel
t = NgrokTunnel(port=8000)
print("URL:", t.start())
out, err = t.lt_process.communicate()
print("OUT:", out)
print("ERR:", err)
