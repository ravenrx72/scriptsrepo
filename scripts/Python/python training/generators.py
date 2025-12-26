#generators
def get_number ():
    for i in range(1,3):   
            yield i
print(get_number())

generator = get_number()
print(next(generator))
print(next(generator))

#Makes list variable 
numbers = list(get_number())
print(numbers)