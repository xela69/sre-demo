#!/usr/bin/env python3
import socket

TARGET = "10.52.0.6"  # the linux server privateIP

TCP_PORTS = [22, 25, 53, 80, 88, 123, 135, 137, 139, 161, 389, 443, 445, 464, 636, 647, 1433, 3268, 3269, 3389, 5671, 8443, 9191, 9192, 9389, 9200, 9300, 9400, 49152, 55000, 61000]
UDP_PORTS = [53, 123, 161, 5353, 5671, 9200, 9300, 9400, 53000]

print(f"=== TCP tests to {TARGET} ===")
for p in TCP_PORTS:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        s.connect((TARGET, p))
        print(f"TCP {p}  OK")
    except Exception:
        print(f"TCP {p}  FAIL")
    finally:
        s.close()

print(f"=== UDP tests to {TARGET} ===")
for p in UDP_PORTS:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(1)
    try:
        s.sendto(b"hi", (TARGET, p))
        try:
            data, _ = s.recvfrom(1024)
            if f"OK {p}".encode() in data:
                print(f"UDP {p}  OK")
            else:
                print(f"UDP {p}  FAIL")
        except socket.timeout:
            print(f"UDP {p}  FAIL")
    except Exception:
        print(f"UDP {p}  FAIL")
    finally:
        s.close()