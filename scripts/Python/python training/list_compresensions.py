# use for loop to append
numbers = [1,2,3,4]
numbers = []
for i in range (1,20):
    numbers.append(i)
    print(numbers)

numbers2 = [x for x in range (1,20)]
print(numbers2)

#skip divided by 3 added IF in one line
numbers2 = [x for x in range (1,20) if x %3!=0]
print(numbers2)
