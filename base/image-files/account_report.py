#!/usr/bin/env python3
from ib_insync import IB, util
import sys
import asyncio
import pandas as pd
import datetime
import os

OUTPUT_DIR = "/home/ibg_settings"
def main():
    ib = IB()
    ib.connect('localhost', 8888, clientId=1001)
    accounts = ib.managedAccounts()
    account = accounts[0]

    summary_list = ib.accountSummary(account)
    summary = util.df(summary_list)

    today = datetime.date.today().strftime("%Y%m%d")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    out_path = os.path.join(OUTPUT_DIR, f"account_{account}_{today}.csv")

    summary.to_csv(out_path, encoding="utf-8-sig")

    ib.disconnect()
    sys.exit(0)

if __name__ == "__main__":
    main()
