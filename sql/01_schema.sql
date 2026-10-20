-- Схемы проекта: raw (как загружено) -> core (очищено, нормализовано) -> mart (витрины для анализа)
-- dq хранит отчёт о качестве данных.
DROP SCHEMA IF EXISTS raw, core, mart, dq CASCADE;
CREATE SCHEMA raw;
CREATE SCHEMA core;
CREATE SCHEMA mart;
CREATE SCHEMA dq;

CREATE TABLE raw.marketing_campaign (
    id                  integer,
    year_birth          integer,
    education           text,
    marital_status      text,
    income              numeric,
    kidhome             integer,
    teenhome            integer,
    dt_customer         date,
    recency             integer,
    mntwines            integer,
    mntfruits           integer,
    mntmeatproducts     integer,
    mntfishproducts     integer,
    mntsweetproducts    integer,
    mntgoldprods        integer,
    numdealspurchases   integer,
    numwebpurchases     integer,
    numcatalogpurchases integer,
    numstorepurchases   integer,
    numwebvisitsmonth   integer,
    acceptedcmp3        integer,
    acceptedcmp4        integer,
    acceptedcmp5        integer,
    acceptedcmp1        integer,
    acceptedcmp2        integer,
    complain            integer,
    z_costcontact       integer,
    z_revenue           integer,
    response            integer
);
