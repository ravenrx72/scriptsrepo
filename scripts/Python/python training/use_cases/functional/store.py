#ask questions up front
day = int(input('How many days ago did you buy? '))
used = input('Have you used the items y/n? ')
broke = input('Has the item broken down? ')

#conditions met
if(broke =='y' or (day <= 10 and used == 'n')):
    print('You get a refund')

#conditions NOT met
else:
    print('Sorry no refund')