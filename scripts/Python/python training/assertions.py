# assertions    
def calculate_area(number):
    assert (number!=0), "Number must be non-zero"
    return 1/ number

calculate_area(0)  # This will raise an AssertionError with the message "Number must be non-zero"