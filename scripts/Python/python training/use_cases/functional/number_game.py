secret = 17

print('''
                                                            
   |  _   _ |_ / _    _  _   _  |    _   _. ._ _   _  
 \_| (_) _> | | _>   (_ (_) (_) |   (_| (_| | | | (/_ 
                                     _|                                                                                                                        

      ''')

secret_input = int(input('Guess my number:: '))
while secret_input != secret:
    print ('Wrong')
    secret_input = int(input('Guess again:: '))

print ('''  __                
 /__  _ _|_   o _|_ 
 \_| (_) |_   |  |_ 
                    ''')