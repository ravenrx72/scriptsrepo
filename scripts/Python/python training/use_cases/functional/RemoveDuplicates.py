#example 1
def unique_elements(input_list):
    unique_list = []
    for item in input_list:
        if item not in unique_list:
            unique_list.append(item)
    return unique_list

print(unique_elements([1, 1, 4, 5, 1]))
print(unique_elements(['Marc','Josh', 'Jim', 'Ralf', 'Mohommand', 'Alex', 'Robert', 'Abdul Azim', 'Abdul-Jalil', 'Josh']))