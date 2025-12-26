age = int(input('What is your age '))
country = input('what is your country ')

# note the OR 
if age < 25 and country == 'US' or 'MX':
    print ('**You can apply**')
else:
    print ('Go home')