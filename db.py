"""Подключение к PostgreSQL (параметры из переменных окружения, пароль запрашивается при запуске)."""
import os
from getpass import getpass

import psycopg

DB_NAME = os.getenv("PGDATABASE", "marketing")


def _params(dbname):
    if "PGPASSWORD" not in os.environ:
        os.environ["PGPASSWORD"] = getpass("Пароль пользователя PostgreSQL: ")
    return dict(
        host=os.getenv("PGHOST", "localhost"),
        port=int(os.getenv("PGPORT", "5432")),
        user=os.getenv("PGUSER", "postgres"),
        dbname=dbname,
    )


def ensure_database():
    """Создаёт базу, если её ещё нет."""
    with psycopg.connect(**_params("postgres"), autocommit=True) as conn:
        exists = conn.execute("SELECT 1 FROM pg_database WHERE datname = %s", (DB_NAME,)).fetchone()
        if not exists:
            conn.execute(f'CREATE DATABASE "{DB_NAME}"')


def connect():
    return psycopg.connect(**_params(DB_NAME))
