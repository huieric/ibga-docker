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

    # 获取账户快照
    summary_list = ib.accountSummary(account)  # 现在是 list
    summary = util.df(summary_list)

    # 打印调试
    print("账户资金摘要:")
    print(summary.head())

    # 保存到CSV
    today = datetime.date.today().strftime("%Y%m%d")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    out_path = os.path.join(OUTPUT_DIR, f"account_{account}_{today}.csv")

    summary.to_csv(out_path, encoding="utf-8-sig")
    print(f"✅  已保存账户快照到 {out_path}")

    ib.disconnect()
    print("Connected to IBKR successfully")
    sys.exit(0)

if __name__ == "__main__":
    main()
