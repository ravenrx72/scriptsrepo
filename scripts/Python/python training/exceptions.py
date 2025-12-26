while True:
    try:
        value = int(input("Please enter a number: "))
        print("You entered:", value)
        raise SyntaxError("This is a syntax error for demonstration purposes.")
    except ValueError:
        print("Invalid input. Please enter a valid number.")
    except ZeroDivisionError:
        print("Division by zero is not allowed.")

