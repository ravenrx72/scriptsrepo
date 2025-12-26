income = 250_000
lowtaxland_rate = .05
ripoffland_rate = 0.43


# our income is {income} and you would pay {tax amount in Lowtaxland} income tax in Lowtaxland or {tax amount in Ripoffland} income tax in Ripoffland. You would save {difference between the tax amounts} by paying taxes in Lowtaxland!
print('Your income is',(income),'and you would pay', (lowtaxland_rate),'income in Lowtaxland or', (ripoffland_rate), 'income tax in Ripoffland.','You could save',(income * ripoffland_rate - income * lowtaxland_rate),'by paying taxes in Lowtaxland!')
 
 
#Sample short version
print ('text goes here', (income), '<--call a vaiable-->', (income * lowtaxland_rate))