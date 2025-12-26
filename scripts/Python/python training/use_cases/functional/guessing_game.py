correct = 1994
guess = int(input('Guess the year Python 1.0 came out '))

while guess != correct:
    if guess < 1994:
        print('It was later than that')
        guess = int(input('Try again '))

if guess == correct:
    print('BINGO!!!!')


