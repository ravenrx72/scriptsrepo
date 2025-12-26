# Function to calculate the average of a list of numbers
def get_average(input_numbers):
    sum = 0.0
    for number in input_numbers:
        sum += number
    average = sum / len(input_numbers) 
    print(average)

# function with parameters
get_average([1, 2, 3, 4, 5])

# Function with 2 parameters to print the count of a specific letter in a given text
def print_letter_count (text,letter):
    count = 0
    for char in text:
        if char == letter:
            count += 1
    print(f"The letter '{letter}' appears {count} times in the text.")

print_letter_count(text='Hello World', letter='o')
#print_letter_count('Hello World', 'o')
# named functions print_letter(text='Welcome' letter='e')