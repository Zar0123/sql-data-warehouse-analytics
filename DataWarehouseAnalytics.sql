
CREATE SCHEMA gold;

CREATE TABLE gold.dim_customers(
    customer_key int,
    customer_id int,
    customer_number varchar(50),
    first_name varchar(50),
    last_name varchar(50),
    country varchar(50),
    marital_status varchar(50),
    gender varchar(50),
    birthdate date,
    create_date date
);

CREATE TABLE gold.dim_products(
	product_key int ,
    product_id int ,
    product_number varchar(50) ,
    product_name varchar(50) ,
    category_id varchar(50) ,
    category varchar(50) ,
    subcategory varchar(50) ,
    maintenance varchar(50) ,
    cost int,
    product_line varchar(50),
    start_date date
);

CREATE TABLE gold.fact_sales(
	order_number varchar(50),
	product_key int,
	customer_key int,
	order_date date,
	shipping_date date,
	due_date date,
	sales_amount int,
	quantity smallint,
	price int
);

SELECT *
FROM gold.dim_customers;

SELECT *
FROM gold.dim_products;

SELECT *
FROM gold.fact_sales;

--- Checking the Duplicated rows for all tables ----

SELECT customer_id, COUNT(customer_id)
FROM gold.dim_customers
GROUP BY customer_id
HAVING COUNT(customer_id) > 1
;

SELECT product_id, COUNT(product_id)
FROM gold.dim_products
GROUP BY product_id
HAVING COUNT(product_id) > 1;

SELECT 
	order_number,
	product_key, 
	customer_key,
	order_date,
	shipping_date,
	due_date,
	sales_amount, quantity,
	price,
COUNT(*) AS duplicate_count
FROM gold.fact_sales
GROUP BY order_number,
	product_key, 
	customer_key,
	order_date,
	shipping_date,
	due_date,
	sales_amount, 
	quantity,
	price
HAVING COUNT(*) > 1
;

---- Analyze Sales Performance Over Time ------

SELECT 
	EXTRACT(YEAR FROM order_date) as order_year, 
	EXTRACT(MONTH FROM order_date) as order_month,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY order_year, order_month
ORDER BY order_year, order_month ASC;

SELECT 
	DATE_TRUNC('year', order_date) AS order_date,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATE_TRUNC('year', order_date)
ORDER BY DATE_TRUNC('year', order_date);

SELECT 
	TO_CHAR(order_date, 'YYYY-Mon') AS order_date,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
	GROUP BY TO_CHAR(order_date, 'YYYY-Mon')
	ORDER BY TO_CHAR(order_date, 'YYYY-Mon');

---- Cumulative Analysis ----

-- Calculate the total sales per month and the running total of sales over time 

SELECT 
	order_date,
	total_sales,
	SUM(total_sales) OVER(ORDER BY order_date) AS running_total_sales,
	ROUND(avg_price, 0) AS round_avg_price,
	ROUND(AVG(avg_price) OVER(ORDER BY order_date), 0) AS running_avg_price
	FROM
(
SELECT 
	DATE_TRUNC('year', order_date) AS order_date, 
	SUM(sales_amount) AS total_sales,
	AVG(price) AS avg_price
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATE_TRUNC('year', order_date)
ORDER BY DATE_TRUNC('year', order_date))
;

-- Performance Analysis ---
-- Comparing the current value to a target value. 

-- Current[Mesure] - Target[Measure]
-- Current Sales - Average Sales
-- Current Year Sales - Previous Year Sales 
-- Current Sales - Lowest Sales

/* Analyze the yearly performance of products
by comparing each product's sales to both its average sales performance and
the previous year's sales.*/
WITH yearly_product_sales AS(
SELECT 
	EXTRACT(YEAR FROM order_date) AS order_year,
	p.product_name,
	SUM(f.sales_amount) AS current_sales
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_products p
	ON f.product_key = p.product_key
WHERE order_date IS NOT NULL
GROUP BY EXTRACT(YEAR FROM order_date), p.product_name
)
SELECT 
order_year,
product_name,
current_sales,
ROUND(AVG(current_sales) OVER(PARTITION BY product_name ), 0) avg_sales,
current_sales - ROUND(AVG(current_sales) OVER(PARTITION BY product_name ), 0) AS diff_avg,
CASE WHEN current_sales - ROUND(AVG(current_sales) OVER(PARTITION BY product_name ), 0) > 0 THEN 'Increase'
	WHEN current_sales - ROUND(AVG(current_sales) OVER(PARTITION BY product_name ), 0) < 0 THEN 'Decrease'
	ELSE 'No Change'
END AS avg_change,
LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS pre_year_sales,
current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS diff_py
FROM yearly_product_sales
ORDER BY product_name, order_year
;


-- Part-To-Whole Analysis ---
-- ([Measure] / Total [Measure]) + 100 By [Dimension]
-- (Sales/TotalSales) + 100 By Category
-- (Quantity/ Total Quantity) + 100 By Country

-- Which categories contribute the most to overall sales?
WITH category_sales AS (
	SELECT 
		category, 
		SUM(sales_amount) AS total_sales
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_products p
		ON p.product_key = f.product_key
	GROUP BY category
	)
SELECT
category,
total_sales,
SUM(total_sales) OVER() overall_sales,
CONCAT(ROUND((total_sales / SUM(total_sales) OVER())*100, 2), '%') AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC

;

/* Which country generate the higest product sales valume, 
and what is each country's percentage share of total quantity sold? */
WITH country_sales AS(
SELECT 
	country,
	SUM(quantity) total_quantity
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
	ON f.customer_key = c.customer_key
GROUP BY country
)
SELECT country,
total_quantity,
SUM(total_quantity) OVER() overall_quantity,
CONCAT(ROUND((total_quantity/SUM(total_quantity) OVER())*100, 2), '%') AS quantity_percentage,
ROW_NUMBER() OVER(ORDER BY total_quantity DESC) AS rank_no
FROM country_sales
ORDER BY total_quantity DESC
;

-- 42:21 stopped
-- Data Segmentation ---
-- [Measure] By [Measure] --

-- Total Products By Sales Range
-- Total Customers By Age

/* Segment products into cost ranges and
count how many products fall into each segment */

WITH product_segments AS
(
SELECT 
	product_key,
	product_name,
	cost,
	CASE 
		WHEN cost < 100 THEN 'Below 100'
		WHEN cost BETWEEN 100 AND 500 THEN '100-500'
		WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
		ELSE 'Above 1000'
	END cost_range
FROM gold.dim_products
)
SELECT 
	cost_range,
	COUNT(product_key) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC
;

/*
Group customers into three segements based on their spending behavior:
- VIP: at least 12 months of history and spending more than €5,000.
- Regular: at least 12 months of history but spending €5,000 or less.
- New: lifespan less than 12 months.
And find the total number of customers by each group. 
*/
WITH customer_spending AS
(
	SELECT 
		c.customer_key, 
		sum(f.sales_amount) AS total_spending,
		MIN(order_date) AS first_order,
		MAX(order_date) AS last_order,
		(EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date)))*12 -- converting year into months -> *12
		+ EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date))) ) AS lifespan
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_customers c
		ON f.customer_key = c.customer_key
	GROUP BY c.customer_key
)
SELECT customer_segment,
COUNT(customer_key) AS total_customers
FROM(
SELECT
	customer_key,
	CASE WHEN lifespan >=12 AND total_spending > 5000 THEN 'VIP'
		WHEN lifespan >=12 AND total_spending <= 5000 THEN 'Regular'
		ELSE 'New'
	END customer_segment
FROM customer_spending
) t
GROUP BY customer_segment
ORDER BY total_customers DESC
;

/*

===============================================================
Customer Report
===============================================================

Purpose:
	- This report consolidates key customer metrics and behaviors

Highlights:
	1. Gathers essentials fields such as names, ages, and transaction details.
	2. Segments customer into categories (VIP, Regular, New) and age groups.
	3. Aggregates customer_level metrics:
		- total orders
		- total sales
		- total quantity purchased
		- total products
		- lifespan (in months)
	4. Calculates valuable KPIs
		- recency (month since last order)
		- average order value (Average Order Value = Total Sales/Total Number of Orders)
		- average monthly spend (Average monthly spend = Total Sales/Number of months)
===============================================================

*/
CREATE VIEW gold.report_customers AS
WITH base_query AS(
/*
(1) Basic Query: Retrieves core columns from tables
*/
	SELECT
		f.order_number,
		f.product_key,
		f.order_date,
		f.sales_amount,
		f.quantity,
		c.customer_key,
		c.customer_number,
		CONCAT(c.first_name, ' ',c.last_name) AS customer_name,
		EXTRACT(YEAR FROM AGE(NOW(), c.birthdate)) AS age
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_customers c
	ON c.customer_key = f.customer_key
	WHERE order_date IS NOT NULL
	)

, customer_aggregation AS
(
SELECT 
	customer_key,
	customer_number,
	customer_name,
	age,
	COUNT(DISTINCT order_number) AS total_orders,
	SUM(sales_amount) AS total_sales,
	SUM(quantity) AS total_quantity,
	COUNT(DISTINCT product_key) AS total_products,
	MAX(order_date) AS last_order_date,
	(EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date)))*12 -- converting year into months -> *12
	+ EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date))) ) AS lifespan
FROM base_query
GROUP BY 
	customer_key,
	customer_number,
	customer_name,
	age
)
SELECT 
	customer_key,
	customer_number,
	customer_name,
	age,
	CASE 
		WHEN age < 20 THEN 'Under 20'
		WHEN age between 20 and 29 THEN '20-29'
		WHEN age between 30 and 39 THEN '30-39'
		WHEN age between 40 and 49 THEN '40-49'
		ELSE '50 and above'
	END AS age_group,
	CASE
		WHEN lifespan >=12 AND total_sales > 5000 THEN 'VIP'
		WHEN lifespan >=12 AND total_sales <= 5000 THEN 'Regular'
		ELSE 'New'
	END AS customer_segment,
	last_order_date,
	(EXTRACT(YEAR FROM AGE(NOW(), last_order_date))*12 
	+EXTRACT(MONTH FROM AGE(NOW(), last_order_date))) AS recency,
	total_orders,
	total_sales,
	total_quantity,
	total_products,
	lifespan,
	-- Compuate average order value (AVO)
	CASE
		WHEN total_orders = 0 THEN 0
		ELSE total_sales/total_orders
	END AS avg_order_value,
	-- Compuate average monthly spend
	CASE
		WHEN lifespan = 0 THEN total_sales
		ELSE ROUND(total_sales/lifespan, 2)
	END AS avg_monthly_spend
FROM customer_aggregation
;

SELECT 
*
FROM gold.report_customers
GROUP BY age_group;

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
