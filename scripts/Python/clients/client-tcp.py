#!/bin/python
#Simple TCP client
import socket

target_host = "127.0.0.1"
target_port = 9998

#create socket object
client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

#create the client
client.connect((target_host, target_port))

#send some info
client.send(b"ABCD")

#receive
response = client.recv(4096)

print(response.decode())
client.close()
