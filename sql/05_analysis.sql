-- Аналитические запросы. "-- name: <имя>" начинает новый запрос; результат сохраняется в outputs/queries/<имя>.csv

-- name: q1_rfm_segments
-- Сегменты RFM: размер, вклад в выручку (оконная SUM OVER ()), отклик на последнюю кампанию
SELECT r.rfm_segment,
       count(*)                                                        AS customers,
       round(avg(m.total_spend), 0)                                    AS avg_spend,
       round(100.0 * sum(m.total_spend) / sum(sum(m.total_spend)) OVER (), 1) AS revenue_share_pct,
       round(100.0 * avg(m.response), 1)                               AS response_rate_pct
FROM mart.rfm r
JOIN mart.customer m USING (customer_id)
GROUP BY r.rfm_segment
ORDER BY r.rfm_segment;

-- name: q2_spend_by_income_segment
-- Структура трат по категориям в разрезе квартилей дохода
SELECT income_segment,
       count(*)                                                AS customers,
       round(avg(total_spend), 0)                              AS avg_spend,
       round(100.0 * sum(spend_wine)  / sum(total_spend), 1)   AS wine_share_pct,
       round(100.0 * sum(spend_meat)  / sum(total_spend), 1)   AS meat_share_pct,
       round(100.0 * sum(spend_gold)  / sum(total_spend), 1)   AS gold_share_pct,
       round(100.0 * sum(spend_other) / sum(total_spend), 1)   AS other_share_pct
FROM mart.customer
GROUP BY income_segment
ORDER BY income_segment;

-- name: q3_response_by_children
-- Отклик на последнюю кампанию в зависимости от числа детей
SELECT children,
       count(*)                          AS customers,
       sum(response)                     AS responded,
       round(100.0 * avg(response), 1)   AS response_rate_pct
FROM mart.customer
GROUP BY children
ORDER BY children;

-- name: q4_top3_spenders_per_education
-- Топ-3 по тратам внутри каждого уровня образования (RANK по окну)
SELECT *
FROM (
    SELECT education, customer_id, total_spend,
           rank() OVER (PARTITION BY education ORDER BY total_spend DESC) AS rnk
    FROM mart.customer
) t
WHERE rnk <= 3
ORDER BY education, rnk, customer_id;

-- name: q5_signup_cohorts
-- Когорты по полугодиям регистрации: новые клиенты, средние траты, изменение к предыдущей когорте (LAG)
WITH cohorts AS (
    SELECT (date_trunc('year', dt_customer)
            + CASE WHEN extract(month FROM dt_customer) > 6 THEN interval '6 months' ELSE interval '0' END)::date AS cohort_start,
           count(*)                        AS new_customers,
           round(avg(total_spend), 0)      AS avg_spend,
           round(100.0 * avg(response), 1) AS response_rate_pct
    FROM mart.customer
    GROUP BY 1
)
SELECT cohort_start, new_customers, avg_spend, response_rate_pct,
       round(100.0 * (avg_spend - lag(avg_spend) OVER (ORDER BY cohort_start))
             / NULLIF(lag(avg_spend) OVER (ORDER BY cohort_start), 0), 1) AS avg_spend_change_pct
FROM cohorts
ORDER BY cohort_start;

-- name: q6_campaign_acceptance
-- Доля принявших каждую кампанию
SELECT campaign, customers_offered, accepted, acceptance_rate_pct
FROM mart.campaign_performance
ORDER BY campaign;

-- name: q7_income_by_partner_status
-- Доход: в паре vs без пары (после очистки данных), с медианой и размерами групп
SELECT partner_status,
       count(income)                                                          AS customers_with_income,
       round(avg(income), 0)                                                  AS mean_income,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY income)::numeric, 0) AS median_income
FROM mart.customer
GROUP BY partner_status;

-- name: q8_big_spenders_vs_segment
-- Клиенты, чьи траты более чем вдвое превышают среднее по их сегменту дохода (подзапрос + оконное среднее)
SELECT customer_id, income_segment, total_spend, round(segment_avg, 0) AS segment_avg,
       round(total_spend / segment_avg, 1) AS times_above_avg
FROM (
    SELECT customer_id, income_segment, total_spend,
           avg(total_spend) OVER (PARTITION BY income_segment) AS segment_avg
    FROM mart.customer
) t
WHERE total_spend > 2 * segment_avg
ORDER BY times_above_avg DESC, customer_id
LIMIT 20;

-- name: q9_channel_mix_by_age_group
-- Доля онлайн-покупок по возрастным группам
SELECT age_group,
       count(*)                                                    AS customers,
       round(100.0 * sum(web_purchases) / sum(total_purchases), 1) AS web_share_pct,
       round(avg(web_visits_month), 1)                             AS avg_web_visits_month
FROM mart.customer
GROUP BY age_group
ORDER BY CASE age_group WHEN '<35' THEN 1 WHEN '35-49' THEN 2 WHEN '50-64' THEN 3 ELSE 4 END;
