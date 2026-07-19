#!/usr/bin/env python3 

# this python code is just for testing purposes, it does not do anything useful
# also i dont know how to code in python, so please dont judge me

#import the socket library
import socket

# create a socket object

def start_echo_server():
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    
    #allow the socket to be reused
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    #bind the socket to a specific address and port
    server_socket.bind(('localhost', 8080))
    server_socket.listen(1)

    print("Echo server is running on port 8080...")

    try:
        while True:
            # accept a connection
            client_socket, addr = server_socket.accept()
            print(f"Connection from {addr}")

            try:
                while True:
                    # receive data from the client
                    data = client_socket.recv(1024)
                    if not data:
                        print("Client disconnected")
                        break
                    print(f"Received: {data.decode()}")
                    # send the same data back to the client
                    client_socket.sendall(data)
            except Exception as e:
                print(f"Error handling data: {e}")

            finally:
                #always close the client socket
                client_socket.close()
                print(f"Connection from {addr} closed")

    except KeyboardInterrupt:
        print("\nServer shutting down...")
    finally:
        #close the server socket
        server_socket.close()

if __name__ == "__main__":
    start_echo_server()




