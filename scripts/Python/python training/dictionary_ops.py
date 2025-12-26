grades = {
    'john': 85,
    'jane': 90,
    'doe': 78,
    'da': 69,
}
print("Original grades:", grades)
grades['john'] = 95  # Update John's grade

print("Updated grades:", grades)

#another way to update multiple values
grades.update((('doe', 80), ('da', 70)))
print("Grades after update:", grades)

len(grades)  # Get the number of entries in the dictionary

if 'john' in grades:
    print("John's grade:", grades['john'])

del grades['jane']  # Remove Jane's entry
print("Grades after removing Jane:", grades)

for el in grades.keys():
    print("Key:", el)

for el in grades.values():
    print("Value:", el)

for el in grades:
    print('Key:', el, 'Value:', grades[el])

# Iterate through keys and values
for person, grade in grades.items():
    print('Person:', person, 'Grade:', grade)