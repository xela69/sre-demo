#!/usr/bin/env python3
import socket, threading, datetime, sys, os

BIND = "0.0.0.0"

# Default test port sets (you can trim these if something already owns a port)
TCP_PORTS = [22,25,53,80,88,123,135,137,139,161,389,443,445,464,636,647,
             1433,3268,3269,3389,5671,8443,9191,9192,9389,9200,9300,9400,
             49152,55000,61000]
UDP_PORTS = [53,123,161,5353,5671,9200,9300,9400,53000]

def log(line):
    print(f"{datetime.datetime.now().isoformat(sep=' ', timespec='seconds')} {line}", flush=True)

def tcp_server(p):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((BIND, p))
        s.listen(128)
    except OSError as e:
        log(f"[TCP] FAILED to bind {BIND}:{p}: {e}")
        return
    log(f"[TCP] listening on {BIND}:{p}")
    while True:
        try:
            c, addr = s.accept()
        except OSError as e:
            log(f"[TCP] accept error on {p}: {e}")
            break
        log(f"[TCP] {p} from {addr[0]}:{addr[1]}")
        try:
            c.sendall(f"OK {p}\n".encode())
        except Exception:
            pass
        c.close()

def udp_server(p):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.bind((BIND, p))
    except OSError as e:
        log(f"[UDP] FAILED to bind {BIND}:{p}: {e}")
        return
    log(f"[UDP] listening on {BIND}:{p}")
    while True:
        try:
            data, addr = s.recvfrom(2048)
        except OSError as e:
            log(f"[UDP] recv error on {p}: {e}")
            break
        log(f"[UDP] {p} from {addr[0]}:{addr[1]} bytes={len(data)}")
        try:
            s.sendto(f"OK {p}".encode(), addr)
        except Exception:
            pass

for p in TCP_PORTS:
    threading.Thread(target=tcp_server, args=(p,), daemon=True).start()
for p in UDP_PORTS:
    threading.Thread(target=udp_server, args=(p,), daemon=True).start()

log("Echo server ready. Note: ports <1024 require root or CAP_NET_BIND_SERVICE; ports already in use will be skipped.")
threading.Event().wait()