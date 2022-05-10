#!/bin/Python

#Deciding functions
def calculate (network,x,y):
    if network == "10.0.0.0":

        print(f" The sum is :{x + y}")

    else:
        print(f" Network :{network} can't be requested")

calculate("10.0.0.0",30, 10)

#Need to add input for x,y
