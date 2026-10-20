# Marketing analytics

Анализ клиентской базы и маркетинговых кампаний розничной компании: загрузка данных в PostgreSQL, контроль качества, витрины, проверка гипотез, визуализация и рекомендации.

Результаты и выводы: [REPORT.md](REPORT.md)

## Стек

PostgreSQL (CTE, оконные функции, подзапросы), Python (pandas, SciPy, matplotlib, seaborn, psycopg), Excel, JSON.

## Структура

```
sql/01_schema.sql         схемы raw, core, mart, dq
sql/02_data_quality.sql   проверки качества данных (таблица dq.report)
sql/03_core.sql           очистка и нормализация
sql/04_marts.sql          витрины: клиент, RFM, эффективность кампаний
sql/05_analysis.sql       аналитические запросы
analysis.py               проверка гипотез и графики
run_pipeline.py           запуск пайплайна
data/                     исходный датасет
outputs/                  графики, результаты запросов, Excel, JSON
```

## Запуск

Нужны Python 3.10+ и PostgreSQL.

```
pip install -r requirements.txt
python run_pipeline.py
```

При запуске скрипт запрашивает пароль пользователя `postgres` и сам создаёт базу `marketing`. Подключение настраивается переменными окружения `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`.

## Данные

Customer Personality Analysis (Kaggle), 2 240 клиентов: демография, доход, траты по категориям, покупки по каналам, отклик на кампании.
