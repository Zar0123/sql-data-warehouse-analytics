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
