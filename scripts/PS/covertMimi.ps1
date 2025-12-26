import base64

raw = open('Invoke-Mimikatz.ps1', 'r').read()
b64 = base64.b64encode(raw.encode('utf-16-le'))
open('Invoke-Mimikatz_b64.txt', 'w').write(b64)
