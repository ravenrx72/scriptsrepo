def get_day(user_info):
    day = int(input("Please enter your birth day (1-31): "))
    user_info.append(day)

def get_month(user_info):
    month = int(input("Please enter your birth month (1-12): "))
    user_info.append(month)
    
def get_year(user_info):
    year = int(input("Please enter your birth year: "))
    user_info.append(year)

# Main function to get user birthday calls others, using try/except for error handling
def get_user_bday(user_info):
    try:
        day = get_day(user_info)
        month = get_month(user_info)
        year = get_year(user_info)
        print(f'So your birthday is', user_info)
    except ValueError:
        print("Error")

print('Hi I will collect some info about your birthday.')
user_info = []
get_user_bday(user_info)