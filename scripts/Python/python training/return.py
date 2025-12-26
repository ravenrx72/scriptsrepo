def get_average(input_numbers):
    sum = 0.0
    for number in input_numbers:
        sum += number
        average = sum / len(input_numbers)
        return average

print('The average is:', get_average([10, 20, 30, 40, 50]))

average = get_average([10, 20, 30, 40, 50])
if average > 25:
    print('The average is above 25.')
else:
    print('The average is 25 or below.')


#example 2/ check if first and last elements are equal
def first_and_last_equal(number_list):
    if (number_list[0] == number_list[-1]):
        return True
    else:
        return False
print((first_and_last_equal([10,65,20,10])))
