#first = input ('Enter 1st number')
#second = input ('Enter 2nd number')
#print ('before swapping', first, second)

#shortcut for variabale swapping
#first, second = second, first 
#print ('After swapping', first, second)

cars = ['red','blue', 'green', 'black']
print('Before =', cars)
cars [0], cars [3] = cars[3], cars [0]
print('after= ', cars)
print ('Swap blue and green')
cars [1], cars [2] = cars[2], cars [1]
print('Switch blue and green....', cars)

#reverse order in the list 
cars.sort(reverse=True)

print(cars)
print('Does Nong Da understand??')