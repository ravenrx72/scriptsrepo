name = 'this is a string'
print(name)

printme = 'Print this'
print(printme[0]) #print first character
print(printme[0:5]) #print first 5 characters
for i in printme: #print each character
    print(i)


# String formatting
name2 = 'Josh'
hobby = 'motocross'
score = 95

print('I am {} and I like {}. My score is {}'.format(name2, hobby, score))
print(name2.upper()) #capitalize

x = name2.capitalize() #capitalize and store in variable
print(x)