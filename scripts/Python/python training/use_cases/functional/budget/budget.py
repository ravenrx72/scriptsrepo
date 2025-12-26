#John has a hard time keeping his #budget. Write a program to help him #analyse his spendings. You are given a #list with John's spendings for each #month. Go through the list, and count #the number of times...
#a. the spendings were low (< 1000.0)
#b. the spendings were normal (between #1000.0 and 2500.0 inclusive)
#c. the spendings were high (> 2500.0)
#Then, print the following to the output:
#Numbers of months with low spendings: x, normal spendings: y, high spendings: z.
#Replace x, y and z with the calculated numbers.

budget = [1346.0, 987.50, 1734.40, 2567.0, 3271.45, 2500.0, 2130.0, 2510.30, 2987.34, 3120.50, 4069.78, 1000.0]

x=0
y=0
z=0

for spent in budget:
    #use if, elif, and else for 3 operations
    if spent < 1000.0:
        x +=1
    elif spent <= 2500.0:
        z +=1
    else:
        y +=1
print ('Months low:',str(x),'high',str(y),'normal',str(z))