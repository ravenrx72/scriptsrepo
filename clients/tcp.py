#!/bin/python
#Simple TCP client
import socket

target_host = "www.google.com"
target_port = 80

#create socket object
client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

#create the client
client.connect((target_host, target_port))

#send some info
client.send(b"GET / HTTP/1.1\r\n\nHost: google.com\r\n\r\n")

#receive
response = client.recv(4096)

print(response.decode())
client.close()
