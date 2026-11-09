/*

===============================================================
Product Report
===============================================================

Purpose:
	- This report consolidates key product metrics and behaviors.

Highlights:
	1. Gathers essential fields such as product name, category, subcategory, and cost.
	2. Segments products by revenue to identify High-Performers, Mid-Range, or Low-performers.
	3. Aggregates product-level metrics:
		- total orders
		- total sales
		- total quantity sold
		- total customers (unique)
		- lifespan (in months)
	4. Calculates valuable KPIs:
		- recency (months since last sale)
		- average order revenue (AOR)
		- average monthly revenue
===============================================================
*/

SELECT *
FROM gold.dim_products;

SELECT *
FROM gold.fact_sales;

CREATE VIEW gold.report_products AS
WITH basic_query AS (
    SELECT
        f.order_number,
        f.product_key,
        f.order_date,
        f.customer_key,
        f.sales_amount,
        f.quantity,
        p.product_name,
        p.category,
        p.subcategory,
        p.cost AS p_cost
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL
),

product_aggregation AS (
    SELECT
        category,
        subcategory,
        product_name,
        product_key,
        p_cost,
        COUNT(DISTINCT order_number) AS total_orders,
        SUM(sales_amount) AS total_sales,
        SUM(quantity) AS total_quantity_sold,
        COUNT(DISTINCT customer_key) AS total_customers,
        MAX(order_date) AS last_order_date,
        ROUND(AVG(sales_amount), 1) AS avg_selling_price,
        (
            EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) * 12
            + EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date)))
        ) AS lifespan
    FROM basic_query
    GROUP BY
        category,
        subcategory,
        product_name,
        product_key,
        p_cost
)

SELECT
    category,
    subcategory,
    product_name,
    p_cost,
    avg_selling_price,
    total_orders,
    total_sales,
    CASE
        WHEN total_sales > 50000 THEN 'High_Performer'
        WHEN total_sales >= 10000 THEN 'Mid_Range'
        ELSE 'Low_Performers'
    END AS product_segment,
    total_quantity_sold,
    total_customers,
    last_order_date,
    lifespan,
    (
        EXTRACT(YEAR FROM AGE(NOW(), last_order_date)) * 12
        + EXTRACT(MONTH FROM AGE(NOW(), last_order_date))
    )AS recency,
    CASE
        WHEN total_orders = 0 THEN 0
        ELSE ROUND(total_sales / total_orders, 2)
    END AS avg_order_value,
    CASE
        WHEN lifespan = 0 THEN total_sales
        ELSE ROUND(total_sales/ lifespan, 2)
    END AS avg_monthly_revenue
FROM product_aggregation;

SELECT *
FROM gold.report_products;
