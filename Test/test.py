#!/bin/python

# Function print name, single call
def hello_program():
    name = "First Python program..."
    print(f"Hello, {name}");

hello_program()


# "Use method to multi call & reduce code"
def greet(name):
    print(f"Welcome to the Grid,{name}");

greet("Tron")
greet("Sam")
greet("user")


#Function to call
def half_twice(number):
    half = number / 2
    half_again = half / 2
    return half_again

result = half_twice(12)
print(result)

# Math Function
def get_price (price, tax):
    return price * tax

price = get_price(100,8.25)
print(price)

#New line
