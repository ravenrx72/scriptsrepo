#You are given a list with various flight connections in Europe. Each connection is represented as a tuple with the following elements:   

flightA= ('Amsterdam', 'Dublin', 100)
flightB = ('Amsterdam', 'Rome', 140)
flightC = ('Rome', 'Warsaw', 130)
flightD = ('Minsk', 'Prague', 95)
flightE = ('Stockholm', 'Rome', 190)
flightF = ('Copenhagen', 'Paris', 120)
flightG = ('Madrid', 'Rome', 135)
flightH = ('Lisbon', 'Rome', 170)
flightI = ('Dublin', 'Rome', 170)
flights = [flightA, flightB, flightC, flightD, flightE, flightF, flightG, flightH, flightI]

if 'Rome' in [flight[1] for flight in flights]:
    print('There are flights to Rome!!!')
    connections = [flight for flight in flights if flight[1] == 'Rome']
    average_flight_time = sum(flight[2] for flight in connections) / len(connections)
    print(f"{len(connections)} connections lead to Rome with an average flight time of {average_flight_time} minutes")
