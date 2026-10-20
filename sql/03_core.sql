-- Очищенный и нормализованный слой. Широкая таблица разворачивается в узкие (long) таблицы.
CREATE TABLE core.customers AS
WITH iqr AS (
    SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY income) AS q1,
           percentile_cont(0.75) WITHIN GROUP (ORDER BY income) AS q3
    FROM raw.marketing_campaign
),
dups AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY year_birth, education, marital_status, income, kidhome, teenhome,
                            dt_customer, recency, mntwines, mntfruits, mntmeatproducts,
                            mntfishproducts, mntsweetproducts, mntgoldprods, numdealspurchases,
                            numwebpurchases, numcatalogpurchases, numstorepurchases,
                            numwebvisitsmonth, acceptedcmp1, acceptedcmp2, acceptedcmp3,
                            acceptedcmp4, acceptedcmp5, complain, response
               ORDER BY id) > 1 AS is_dup
    FROM raw.marketing_campaign
)
SELECT r.id                                                        AS customer_id,
       r.year_birth,
       CASE r.education WHEN '2n Cycle' THEN 'Master' ELSE r.education END AS education,
       CASE r.marital_status WHEN 'Alone' THEN 'Single' ELSE r.marital_status END AS marital_status,
       r.income,
       r.kidhome,
       r.teenhome,
       r.dt_customer,
       r.recency,
       r.numdealspurchases,
       r.numwebvisitsmonth,
       r.complain,
       d.is_dup                                                    AS is_suspected_duplicate,
       NOT (r.marital_status IN ('Absurd', 'YOLO')
            OR r.year_birth < 1920
            OR COALESCE(r.income > i.q3 + 3 * (i.q3 - i.q1), false)
            OR (r.numwebpurchases + r.numcatalogpurchases + r.numstorepurchases = 0
                AND r.mntwines + r.mntfruits + r.mntmeatproducts + r.mntfishproducts
                    + r.mntsweetproducts + r.mntgoldprods > 0)) AS analysis_ok
FROM raw.marketing_campaign r
JOIN dups d USING (id)
CROSS JOIN iqr i;
ALTER TABLE core.customers ADD PRIMARY KEY (customer_id);

CREATE TABLE core.purchases_by_category AS
SELECT r.id AS customer_id, v.category, v.amount
FROM raw.marketing_campaign r
CROSS JOIN LATERAL (VALUES
    ('wine',   r.mntwines),
    ('fruit',  r.mntfruits),
    ('meat',   r.mntmeatproducts),
    ('fish',   r.mntfishproducts),
    ('sweets', r.mntsweetproducts),
    ('gold',   r.mntgoldprods)
) AS v(category, amount);

CREATE TABLE core.purchases_by_channel AS
SELECT r.id AS customer_id, v.channel, v.purchases
FROM raw.marketing_campaign r
CROSS JOIN LATERAL (VALUES
    ('web',     r.numwebpurchases),
    ('catalog', r.numcatalogpurchases),
    ('store',   r.numstorepurchases)
) AS v(channel, purchases);

-- cmp1..cmp5 - предыдущие кампании, 'last' - последняя кампания (поле Response)
CREATE TABLE core.campaign_responses AS
SELECT r.id AS customer_id, v.campaign, v.accepted
FROM raw.marketing_campaign r
CROSS JOIN LATERAL (VALUES
    ('cmp1', r.acceptedcmp1),
    ('cmp2', r.acceptedcmp2),
    ('cmp3', r.acceptedcmp3),
    ('cmp4', r.acceptedcmp4),
    ('cmp5', r.acceptedcmp5),
    ('last', r.response)
) AS v(campaign, accepted);

ALTER TABLE core.purchases_by_category ADD PRIMARY KEY (customer_id, category);
ALTER TABLE core.purchases_by_channel  ADD PRIMARY KEY (customer_id, channel);
ALTER TABLE core.campaign_responses    ADD PRIMARY KEY (customer_id, campaign);
