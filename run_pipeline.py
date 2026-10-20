"""Пайплайн: CSV -> PostgreSQL (raw, core, mart) -> SQL-запросы -> Excel, JSON -> статистика и графики."""
import io
import json
import re
import sys
from pathlib import Path

import pandas as pd

import analysis
import db

ROOT = Path(__file__).parent
SQL_DIR = ROOT / "sql"
OUT = ROOT / "outputs"


def run_sql_file(conn, name):
    print(f"-> {name}")
    conn.execute((SQL_DIR / name).read_text(encoding="utf-8"))
    conn.commit()


def load_raw(conn):
    df = pd.read_csv(ROOT / "data" / "marketing_campaign.csv")
    df = df.drop(columns=["Unnamed: 0"])
    df.columns = [c.lower() for c in df.columns]
    buf = io.StringIO()
    df.to_csv(buf, index=False, header=False)
    buf.seek(0)
    cols = ", ".join(df.columns)
    with conn.cursor() as cur, cur.copy(f"COPY raw.marketing_campaign ({cols}) FROM STDIN WITH (FORMAT csv)") as cp:
        cp.write(buf.read())
    conn.commit()
    print(f"-> загружено строк в raw: {len(df)}")


def run_analysis_queries(conn):
    text = (SQL_DIR / "05_analysis.sql").read_text(encoding="utf-8")
    blocks = re.split(r"^-- name: (\w+)\s*$", text, flags=re.M)[1:]
    results = {}
    for name, body in zip(blocks[::2], blocks[1::2]):
        cur = conn.execute(body)
        df = pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])
        df.to_csv(OUT / "queries" / f"{name}.csv", index=False, encoding="utf-8-sig")
        results[name] = df
        print(f"-> {name}: {len(df)} строк")
    return results


def export(conn, results):
    def table(sql):
        cur = conn.execute(sql)
        return pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])

    mart = table("SELECT * FROM mart.customer ORDER BY customer_id")
    rfm = table("SELECT * FROM mart.rfm ORDER BY customer_id")
    dq = table("SELECT check_id, check_name, affected_rows, total_rows, decision FROM dq.report ORDER BY check_id")
    print(dq.to_string(index=False))

    with pd.ExcelWriter(OUT / "marketing_report.xlsx") as xl:
        dq.to_excel(xl, sheet_name="Качество данных", index=False)
        for name, df in results.items():
            df.to_excel(xl, sheet_name=name[:31], index=False)
        mart.to_excel(xl, sheet_name="mart_customer", index=False)
        rfm.to_excel(xl, sheet_name="mart_rfm", index=False)

    summary = {
        "source": "marketing_campaign.csv",
        "customers_in_mart": len(mart),
        "rfm_segments": results["q1_rfm_segments"].to_dict(orient="records"),
        "campaign_acceptance": results["q6_campaign_acceptance"].to_dict(orient="records"),
    }
    (OUT / "segments_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    return mart, rfm


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    (OUT / "charts").mkdir(parents=True, exist_ok=True)
    (OUT / "queries").mkdir(parents=True, exist_ok=True)
    db.ensure_database()
    with db.connect() as conn:
        run_sql_file(conn, "01_schema.sql")
        load_raw(conn)
        run_sql_file(conn, "02_data_quality.sql")
        run_sql_file(conn, "03_core.sql")
        run_sql_file(conn, "04_marts.sql")
        results = run_analysis_queries(conn)
        mart, rfm = export(conn, results)
    analysis.run(mart, rfm, OUT)
    print("Готово. Результаты в папке outputs/")


if __name__ == "__main__":
    main()
