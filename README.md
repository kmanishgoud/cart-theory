# Cart Theory

**A SQL analytics layer on 100k real e-commerce orders.** Built in PostgreSQL on the [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce): 9 linked tables, 2016–2018. It answers the questions an e-commerce analytics team would ask: how the business is growing, whether customers come back, who the best customers are, what sells, and what delivery problems cost.

Everything is version-controlled SQL. One command rebuilds the whole database from the raw CSVs.

---

## Key findings

1. **Growth stalled in 2018 because customers don't come back.** Revenue grew fast in 2017 but plateaued at ~R$1.0–1.1M/month in 2018 (year-on-year growth fell from +745% in January to +53% in August). **97% of customers buy only once**; repeat customers generate just **5.6%** of revenue, so growth depended entirely on acquiring new customers.
2. **Late delivery ruins reviews, and the damage starts at day one.** On-time orders average 4.29★, late orders 2.27★. One-star reviews triple from 8.5% (on the promised day) to **25.1% when just 1–3 days late**, and reach 58.6% at 4–7 days late.
3. **A late first order is associated with fewer returning customers:** 1.62% came back vs 2.20% after an on-time first order (**26% lower**).
4. **Value is highly concentrated.** 18 of 74 categories make 80% of sales; the **top 10% of sellers make 67%**; São Paulo sellers account for 64%.
5. **The biggest marketing opportunity is 14,402 "new big spenders"**: recent first-time buyers spending ~R$300 (28% of revenue). The median gap before a genuine second purchase is 75 days, which suggests when to re-engage them.
6. **Black Friday 2017** (24 Nov) brought 1,147 orders in one day, about 8× a normal day, and pushed the late-delivery rate to 12.4% that month.

---

## Architecture

```
data/raw/*.csv
    │  01–02   raw schema      CSVs loaded exactly as delivered (all TEXT, never edited)
    ▼
raw  ──► 03   audit           32 checks: keys, orphans, coverage, logic, values
    │  04      core schema     typed tables, primary/foreign keys, CHECK constraints, indexes
    ▼
core
    │  05–09   analytics       views that answer business questions
    ▼
analytics
```

| Layer | Contents |
|---|---|
| `raw` | 9 tables, every column TEXT so loading can never fail on a bad value |
| `core` | 8 cleaned tables with enforced keys and constraints, built in one transaction |
| `analytics` | 12 views: order/item/delivery facts, monthly revenue, cohort retention and matrix, RFM, category and seller performance, review-by-delivery |

---

## Data quality: what the audit found and what I did

| Finding | Decision |
|---|---|
| `customer_id` is generated **per order** (0 customer_ids with >1 order); 99,441 IDs = 96,096 real people | Customers keyed on `customer_unique_id`. Analysing by `customer_id` would have shown **zero** repeat customers |
| 814 duplicate review IDs; 547 orders with several reviews | One review per order (most recent) via `ROW_NUMBER()` |
| 1M geolocation rows for ~19k zip prefixes | Collapsed to one row per prefix (average coordinates, points outside Brazil excluded) |
| 775 orders without items; 768 without a review | Flagged, kept; reviews joined with `LEFT JOIN` |
| 197 impossible or missing delivery timestamps | Flagged; excluded from delivery analysis only |
| 610 products without a category; 2 categories without a translation | Labelled `unknown`; missing translations added |
| 249 orders where payments ≠ items + freight (instalment interest, vouchers) | Revenue defined from order items; payments used only for payment analysis |
| 2016 and Sep–Oct 2018 contain only a few hundred orders | Trend analysis limited to Jan 2017 – Aug 2018 |

Full audit output: [`docs/audit_output.txt`](docs/audit_output.txt)

---

## Analyses

### Revenue trends ([`05_revenue.sql`](sql/05_revenue.sql))
Monthly revenue, average order value, month-on-month and year-on-year growth, 3-month moving average and running total, all with window functions (`LAG`, `AVG/SUM OVER`).

### Retention ([`06_cohorts.sql`](sql/06_cohorts.sql))
| Metric | Value |
|---|---|
| Customers who bought more than once | 3.00% |
| …excluding same-day "repeats" (split baskets) | **2.16%** |
| Second orders placed the same day as the first | 29.6% |
| Median days to a genuine second order | 75 |
| Average month-1 retention across cohorts | 0.48% |

The cohort grid is built with `generate_series`, so months where nobody returned count as 0% instead of disappearing and inflating the averages.

### RFM segmentation ([`07_rfm.sql`](sql/07_rfm.sql))
Textbook RFM uses quintiles for frequency, but with 97% one-time buyers, quintiles 1–4 all contain customers with exactly one order. Frequency was therefore adapted to *one-time vs repeat*, with recency and monetary value kept as quintiles.

| Segment | Customers | Revenue share | Suggested action |
|---|---|---|---|
| New big spenders | 15.4% | 28.2% | Re-engage within ~75 days |
| Lost big spenders | 14.7% | 27.5% | Win-back campaign |
| Cooling off | 19.4% | 17.8% | Reminder offers |
| New / lost, low spend | 47.5% | 21.0% | Low-cost automated emails |
| Champions + loyal | 3.0% | 5.6% | Loyalty and referral programme |

### Sellers and categories ([`08_sellers_categories.sql`](sql/08_sellers_categories.sql))
Category Pareto with cumulative `SUM() OVER`, like-for-like growth (Jan–Aug 2018 vs 2017), seller rankings nationally and within each state (`RANK() OVER (PARTITION BY state)`), and concentration by sales decile. One of the top 5 sellers by sales averages only 3.35★, a brand risk for the marketplace.

### Delivery and reviews ([`09_delivery_reviews.sql`](sql/09_delivery_reviews.sql))
| Delivery vs promised date | Avg review | 1-star share |
|---|---|---|
| 8+ days early (74% of orders) | 4.32 | 6.5% |
| On the promised day | 4.03 | 8.5% |
| 1–3 days late | 3.29 | 25.1% |
| 4–7 days late | 2.10 | 58.6% |
| 8+ days late | ~1.7 | ~70% |

Median delivery takes 7.2 days in São Paulo but 21.1 days in Pará. Rio de Janeiro is an outlier: a large market near São Paulo with a 12.1% late rate, nearly 3× São Paulo's. Late deliveries spiked to 14–19% in Feb–Mar 2018, and average reviews dropped in step.

---

## Recommendations

1. **Make retention the growth lever.** Target new big spenders before they lapse; test re-engagement around 60–75 days after the first purchase.
2. **Protect the promised date above all.** Satisfaction collapses from the first day late, so flag at-risk orders early, and investigate carriers to Rio de Janeiro and the north-east.
3. **Test tighter delivery estimates where delivery is reliable.** 74% of orders arrive 8+ days early; shorter promises in São Paulo could lift conversion without hurting reviews (A/B test).
4. **Manage seller concentration.** Give the top 10% of sellers (67% of sales) dedicated account management, and review high-volume sellers with low ratings.

---

## Limitations

- Reviews are given per **order**, so multi-seller orders share one review.
- Customer location is the address from their most recent order.
- Revenue = item prices + freight; instalment interest is excluded.
- Findings such as "late first order → fewer returns" are correlations, not proven causes.
- The data is anonymised and covers one marketplace in 2016–2018.

---

## SQL techniques used

Schemas and layered modelling · `\copy` bulk load · primary/foreign keys, `CHECK` constraints, indexes · transactions · CTEs · `NOT EXISTS` anti-joins · `DISTINCT ON` · `ROW_NUMBER`, `RANK`, `NTILE`, `LAG` · running totals and moving averages with window frames · `generate_series` grids · pivoting with `FILTER` · `PERCENTILE_CONT` medians · conditional aggregation.

---

## Reproduce it

1. Install PostgreSQL (built on 18).
2. Download the dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and extract the 9 CSVs into `data/raw/`.
3. From the project root:

```bash
psql -U postgres -c "CREATE DATABASE cart_theory;"
psql -U postgres -d cart_theory -f sql/run_all.sql -o docs/run_all_output.txt
```

---

## Project structure

```
cart-theory/
├── sql/
│   ├── 01_raw_schema.sql          # raw tables (all TEXT)
│   ├── 02_load_raw.sql            # \copy the 9 CSVs
│   ├── 03_audit.sql               # 32 data-quality checks
│   ├── 04_core.sql                # typed, keyed, cleaned core layer
│   ├── 05_revenue.sql             # revenue trends
│   ├── 06_cohorts.sql             # repeat purchases and cohort retention
│   ├── 07_rfm.sql                 # RFM segmentation
│   ├── 08_sellers_categories.sql  # Pareto, growth, seller rankings
│   ├── 09_delivery_reviews.sql    # delivery vs reviews, first-experience retention
│   └── run_all.sql                # rebuild everything
├── docs/                          # output of every script
└── data/raw/                      # Olist CSVs (not committed, download from Kaggle)
```

**Data:** Olist, *Brazilian E-Commerce Public Dataset*, licensed [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). Not redistributed in this repository.

**Tools:** PostgreSQL 18 · psql · Git