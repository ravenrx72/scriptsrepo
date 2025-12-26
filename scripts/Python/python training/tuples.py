# list can be modified but tuple is immutable
empty_tuple = ()
element_tuple = (1,)
print(element_tuple)

data = ('john','American',1980)
if 'john' in data:
    print('This person is John')
    print('This person is American')

#using a loop to print each option in the tuple
for element in data:
    print(element)