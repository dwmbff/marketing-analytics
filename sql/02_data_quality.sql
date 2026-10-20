-- Контроль качества данных на сырой таблице. Каждая проверка -> строка в dq.report.
CREATE TABLE dq.report (
    check_id      serial PRIMARY KEY,
    check_name    text    NOT NULL,
    affected_rows integer NOT NULL,
    total_rows    integer NOT NULL,
    decision      text    NOT NULL
);

WITH total AS (SELECT count(*) AS n FROM raw.marketing_campaign),
iqr AS (
    SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY income) AS q1,
           percentile_cont(0.75) WITHIN GROUP (ORDER BY income) AS q3
    FROM raw.marketing_campaign
),
dups_wo_id AS (  -- одинаковые во всех полях, кроме ID
    SELECT id,
           row_number() OVER (
               PARTITION BY year_birth, education, marital_status, income, kidhome, teenhome,
                            dt_customer, recency, mntwines, mntfruits, mntmeatproducts,
                            mntfishproducts, mntsweetproducts, mntgoldprods, numdealspurchases,
                            numwebpurchases, numcatalogpurchases, numstorepurchases,
                            numwebvisitsmonth, acceptedcmp1, acceptedcmp2, acceptedcmp3,
                            acceptedcmp4, acceptedcmp5, complain, response
               ORDER BY id) AS rn
    FROM raw.marketing_campaign
)
INSERT INTO dq.report (check_name, affected_rows, total_rows, decision)
SELECT 'Дубликаты ID', (count(*) - count(DISTINCT id))::int, (SELECT n FROM total)::int,
       'ID уникален, дублей по ключу нет'
FROM raw.marketing_campaign
UNION ALL
SELECT 'Подозрительные дубли (все поля совпадают, кроме ID)', count(*) FILTER (WHERE rn > 1)::int, (SELECT n FROM total)::int,
       'Помечены флагом is_suspected_duplicate и остаются в данных; устойчивость выводов проверяется отдельно в Python'
FROM dups_wo_id
UNION ALL
SELECT 'Пропуски в Income', count(*) FILTER (WHERE income IS NULL)::int, (SELECT n FROM total)::int,
       'Остаются в данных; исключаются только из расчётов, где нужен доход (без подстановки среднего)'
FROM raw.marketing_campaign
UNION ALL
SELECT 'Выбросы Income (выше Q3 + 3*IQR)', count(*) FILTER (WHERE income > q3 + 3 * (q3 - q1))::int, (SELECT n FROM total)::int,
       'Исключены из анализа (analysis_ok = false)'
FROM raw.marketing_campaign, iqr
UNION ALL
SELECT 'Нереалистичный год рождения (< 1920)', count(*) FILTER (WHERE year_birth < 1920)::int, (SELECT n FROM total)::int,
       'Исключены из анализа (analysis_ok = false)'
FROM raw.marketing_campaign
UNION ALL
SELECT 'Невалидный Marital_Status (Absurd, YOLO)', count(*) FILTER (WHERE marital_status IN ('Absurd', 'YOLO'))::int, (SELECT n FROM total)::int,
       'Исключены из анализа (analysis_ok = false)'
FROM raw.marketing_campaign
UNION ALL
SELECT 'Неоднозначный Marital_Status (Alone)', count(*) FILTER (WHERE marital_status = 'Alone')::int, (SELECT n FROM total)::int,
       'Объединён со Single'
FROM raw.marketing_campaign
UNION ALL
SELECT 'Константные столбцы (Z_CostContact, Z_Revenue)',
       CASE WHEN count(DISTINCT z_costcontact) = 1 AND count(DISTINCT z_revenue) = 1 THEN 2 ELSE 0 END, 2,
       'Не несут информации, в core не переносятся'
FROM raw.marketing_campaign
UNION ALL
SELECT 'Клиенты с нулевыми тратами',
       count(*) FILTER (WHERE mntwines + mntfruits + mntmeatproducts + mntfishproducts + mntsweetproducts + mntgoldprods = 0)::int,
       (SELECT n FROM total)::int, 'Остаются в данных'
FROM raw.marketing_campaign
UNION ALL
SELECT 'Покупок нет, но траты > 0',
       count(*) FILTER (WHERE numwebpurchases + numcatalogpurchases + numstorepurchases = 0
                          AND mntwines + mntfruits + mntmeatproducts + mntfishproducts + mntsweetproducts + mntgoldprods > 0)::int,
       (SELECT n FROM total)::int, 'Логическое противоречие (траты без покупок): исключены из анализа (analysis_ok = false)'
FROM raw.marketing_campaign;
