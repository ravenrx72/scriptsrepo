#!/usr/bin/python
# written in 2.7

import os, binascii

target = "c:\\temp\\file.exe"
outfile = "c:\\temp\\out.txt"
bytes_per_line = 16

count = 0;
index = 0;
output = "unsigned char binary[] = {\n\t"
with open (target,"rb") as f:
    hexdata = binascii.hexlify(f.read())
hexlist = map(''.join, zip (*[iter(hexdata)]*2))
for hex in hexlist:
    if count >= bytes_per_line:
        output += "\n\t"
        count = 0;
    output += "0x" + str(hexlist[index]).upper() + ","
    count += 1;
    index +1;
output += "\n};\t"
out = open(outfile, "w")
out.write(output)
out.close()
