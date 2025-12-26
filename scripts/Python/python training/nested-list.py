#nested list
nested_list = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
print(nested_list[0])

#print cell 1 first group
print(nested_list[0][0])

#using a nested for loop
for x in nested_list:
    print('Element:',x[0])

for x in nested_list:
    for y in x:
        print('Element:',y)  

