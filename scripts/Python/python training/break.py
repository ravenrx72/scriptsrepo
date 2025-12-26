while True:
    name = input ('Enter your name or EXIT to close ')
    if (name == 'EXIT'):
        break

print('print this is outside the loop')


#continue

while True:
    name = input ('Enter your name or EXIT to close ')
    if (name == 'EXIT'):
        break
    print('Hello ', name)

print('print this is outside the loop')


#continue break

while True:
    name = input ('Enter your name or CONTINUE to skip ')
    if (name == 'CONTINUE'):
        continue
    print('Hello ', name)