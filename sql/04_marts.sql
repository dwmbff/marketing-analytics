-- Витрины для анализа. Берём только корректные записи (analysis_ok).

-- Витрина клиента: одна строка = один клиент
CREATE TABLE mart.customer AS
WITH ref AS (SELECT max(dt_customer) AS ref_date FROM core.customers),
spend AS (
    SELECT customer_id,
           sum(amount)                                      AS total_spend,
           sum(amount) FILTER (WHERE category = 'wine')     AS spend_wine,
           sum(amount) FILTER (WHERE category = 'meat')     AS spend_meat,
           sum(amount) FILTER (WHERE category = 'gold')     AS spend_gold,
           sum(amount) FILTER (WHERE category IN ('fruit', 'fish', 'sweets')) AS spend_other
    FROM core.purchases_by_category GROUP BY customer_id
),
chan AS (
    SELECT customer_id,
           sum(purchases)                                     AS total_purchases,
           sum(purchases) FILTER (WHERE channel = 'web')      AS web_purchases,
           sum(purchases) FILTER (WHERE channel = 'store')    AS store_purchases
    FROM core.purchases_by_channel GROUP BY customer_id
),
camp AS (
    SELECT customer_id,
           sum(accepted) FILTER (WHERE campaign <> 'last') AS past_campaigns_accepted,
           max(accepted) FILTER (WHERE campaign = 'last')  AS response
    FROM core.campaign_responses GROUP BY customer_id
),
base AS (
    SELECT c.*, s.total_spend, s.spend_wine, s.spend_meat, s.spend_gold, s.spend_other,
           ch.total_purchases, ch.web_purchases, ch.store_purchases,
           cm.past_campaigns_accepted, cm.response,
           (extract(year FROM r.ref_date) - c.year_birth)::int AS age,
           (r.ref_date - c.dt_customer)                        AS tenure_days
    FROM core.customers c
    JOIN spend s USING (customer_id)
    JOIN chan ch USING (customer_id)
    JOIN camp cm USING (customer_id)
    CROSS JOIN ref r
    WHERE c.analysis_ok
),
quart AS (
    SELECT customer_id, ntile(4) OVER (ORDER BY income, customer_id) AS income_quartile
    FROM base WHERE income IS NOT NULL
)
SELECT b.customer_id, b.age,
       CASE WHEN b.age < 35 THEN '<35' WHEN b.age < 50 THEN '35-49'
            WHEN b.age < 65 THEN '50-64' ELSE '65+' END                  AS age_group,
       b.education, b.marital_status,
       CASE WHEN b.marital_status IN ('Married', 'Together') THEN 'В паре' ELSE 'Без пары' END AS partner_status,
       b.income,
       CASE q.income_quartile WHEN 1 THEN 'Q1 (низкий)' WHEN 2 THEN 'Q2' WHEN 3 THEN 'Q3'
            WHEN 4 THEN 'Q4 (высокий)' ELSE 'нет данных' END              AS income_segment,
       b.kidhome + b.teenhome                                             AS children,
       (b.kidhome + b.teenhome) > 0                                       AS has_children,
       b.dt_customer, b.tenure_days, b.recency,
       b.total_spend, b.spend_wine, b.spend_meat, b.spend_gold, b.spend_other,
       b.total_purchases, b.web_purchases, b.store_purchases,
       b.numwebvisitsmonth                                                AS web_visits_month,
       b.numdealspurchases                                                AS deal_purchases,
       b.past_campaigns_accepted, b.response, b.complain,
       b.is_suspected_duplicate
FROM base b
LEFT JOIN quart q USING (customer_id);
ALTER TABLE mart.customer ADD PRIMARY KEY (customer_id);

-- RFM: Recency (меньше = лучше), Frequency (число покупок), Monetary (траты). Оценки 1..5 через NTILE.
CREATE TABLE mart.rfm AS
WITH scored AS (
    SELECT customer_id, recency, total_purchases AS frequency, total_spend AS monetary,
           ntile(5) OVER (ORDER BY recency DESC, customer_id)        AS r_score,
           ntile(5) OVER (ORDER BY total_purchases, customer_id)     AS f_score,
           ntile(5) OVER (ORDER BY total_spend, customer_id)         AS m_score
    FROM mart.customer
)
SELECT *,
       CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '1. Champions'
            WHEN f_score >= 4 AND m_score >= 4                  THEN '2. Loyal'
            WHEN r_score >= 4                                   THEN '3. Recent / potential'
            WHEN r_score <= 2 AND (f_score >= 3 OR m_score >= 3) THEN '4. At risk'
            WHEN r_score <= 2                                   THEN '5. Hibernating'
            ELSE '6. Regular' END                                AS rfm_segment
FROM scored;
ALTER TABLE mart.rfm ADD PRIMARY KEY (customer_id);

-- Эффективность кампаний (по клиентам, прошедшим фильтр качества)
CREATE TABLE mart.campaign_performance AS
SELECT cr.campaign,
       count(*)                                      AS customers_offered,
       sum(cr.accepted)                              AS accepted,
       round(100.0 * sum(cr.accepted) / count(*), 2) AS acceptance_rate_pct
FROM core.campaign_responses cr
JOIN mart.customer USING (customer_id)
GROUP BY cr.campaign;
