#!/usr/bin/env python3
from ib_insync import IB
import sys
import asyncio

async def main():
    ib = IB()
    attempts = 0
    while not ib.isConnected():
        if attempts >= 3:
            print("Failed to connect to IBKR after 3 attempts", file=sys.stderr)
            sys.exit(1)
        try:
            await ib.connectAsync('localhost', 8888, clientId=0)
        except Exception:
            pass
        attempts += 1

    ib.disconnect()
    print("Connected to IBKR successfully")
    sys.exit(0)

if __name__ == "__main__":
    asyncio.run(main())
