orginal = 'john.smith'
new = orginal
orginal= 'john.williams'
print (orginal,new)

#use slicing to modifiy the list 
list_orginal = [1,2,3]
list_new = list_orginal[:]
list_orginal[0] = -5
print ('Orginal', list_orginal,'\nNew:',list_new)