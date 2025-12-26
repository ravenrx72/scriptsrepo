def print_letter_count (text,letter='a'):
    count = 0
    for char in text:
        if char == letter:
            count += 1
    print(f"The letter '{letter}' appears {count} times in the text.")

#notice 2nd paramenter is not defined
print_letter_count('How many times is a used in an apple')