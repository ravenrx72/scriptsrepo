def show_truth():
    secret = ['new suprise']
    print(secret)

secret = ['Suprise -another secret']

# This code demonstrates the use of global and local variables in Python. Shadowing for list and dictories 
#global
print (secret)
#local
show_truth()
#global 
print(secret)