host_list = ['machine_A','machine_B', 'machine_C', 'Machine_D']
for host in host_list:
    print ('Machine nname is:', host)

host_list = ['machine_A','machine_B', 'machine_C', 'Machine_D']
for host_index in range(len(host_list)):
    print ('Machine name is:', host_index,' Machine Name:', host_list[host_index],)

#sum with iterating list and for loop
spent = [1.25,2.50,1.75]
sum = 0.0
for spending in spent:
    sum += spending
print ('Money spent:', sum)
