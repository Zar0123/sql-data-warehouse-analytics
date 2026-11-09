# Data Warehouse Analytics Project

This project analyzes sales, customer, and product performance using a PostgreSQL data warehouse.

The analysis covers:
- Data-quality checks
- Sales performance over time
- Cumulative sales analysis
- Product performance analysis
- Part-to-whole analysis
- Customer and product segmentation
- Customer report
- Product report

## Database Schema

The project uses a start-schema-style data warehouse with the following tables:

| Table | Description |
|-------|-------------|
| `gold.dim_customers` | Contains customer information such as name, country, gender, birthdate, and customer number |
| `gold.dim_products` | Contains product information such as product name, category, subcategory, and cost |
| `gold.fact_sales` | Contains sales transactions, including order number, product, customer, order date, sales amount, quantity, and price |


## Technologies Used
- PostgreSQL
- SQL
- Data warehouse modeling
- Aggregate functions
- Window functions
- Common Table Expression (CTEs)
- Views

## 1. Data Quality Checks

Data-quality checks help identify duplicate records and missing values before performing analysis.

### 1.1 Check Duplicate Customers

This query finds customers that appear more than once in the customer dimension table.

```sql
SELECT
  customer_id,
  COUNT(customer_id) AS duplicate_count
FROM gold.dim_customers
GROUP BY customer_id
HAVING COUNT(customer_id) > 1
;
```

### 1.2 Check Duplicate Products

This query finds products that appear more than once in the product dimension table.

```sql
SELECT product_id, COUNT(product_id) AS duplicate_count
FROM gold.dim_products
GROUP BY product_id
HAVING COUNT(product_id) > 1;
```

### 1.3 Check Duplicate Sales Records

This query checks whether the same sales transaction appears more than once.

```sql
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
```

## 2. Sales Performance Analysis

This section analyzes sales performance by time period.

### 2.1 Yearly & Monthly Sales Performance

This query calculates total sales, unique customers, total quantity sold, and total orders for each year.

```sql
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
```


```sql
SELECT 
	DATE_TRUNC('year', order_date) AS order_year,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATE_TRUNC('year', order_date)
ORDER BY DATE_TRUNC('year', order_date);
```

```sql
SELECT 
	DATE_TRUNC('month', order_date) AS order_month,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATE_TRUNC('month', order_date)
ORDER BY DATE_TRUNC('month', order_date);
```


### 2.2 Monthly Sales Using Text Format
```sql
SELECT 
	TO_CHAR(order_date, 'YYYY-Mon') AS order_date,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
	GROUP BY TO_CHAR(order_date, 'YYYY-Mon')
	ORDER BY TO_CHAR(order_date, 'YYYY-Mon');
```

## 3. This query calculate the total sales per month and the running total of sales over time 

```sql
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
```

```sql
SELECT 
	TO_CHAR(order_date, 'YYYY-Mon') AS order_date,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
	GROUP BY TO_CHAR(order_date, 'YYYY-Mon')
	ORDER BY TO_CHAR(order_date, 'YYYY-Mon');
```
## 4. Analyze the yearly performance of products by comparing each product's sales to both its average sales performance and the previous year's sales.

```sql
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

```

## 5. Which categories contribute the most to overall sales?

```sql
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

```

## 6. Which country generate the higest product sales valume, and what is each country's percentage share of total quantity sold?

```sql
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
```

## 7. Segment products into cost ranges and count how many products fall into each segment

```sql
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

```

## 8. Group customers into three segements based on their spending behavior:
- VIP: at least 12 months of history and spending more than €5,000.
- Regular: at least 12 months of history but spending €5,000 or less.
- New: lifespan less than 12 months.
And find the total number of customers by each group.

```sql
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

```
## 9. Customer Report View

This view creates a customer-level report with demographic information, purchase behavior, and key performance indicators.

```sql
CREATE VIEW gold.report_customers AS
WITH base_query AS(
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
	CASE
		WHEN total_orders = 0 THEN 0
		ELSE total_sales/total_orders
	END AS avg_order_value,
	CASE
		WHEN lifespan = 0 THEN total_sales
		ELSE ROUND(total_sales/lifespan, 2)
	END AS avg_monthly_spend
FROM customer_aggregation
;
```

```sql
SELECT *
FROM gold.report_customers
GROUP BY age_group;
```

## 10. Product Report View

This view creates a product-level report with sales performance, customer reach, lifespan, and revenue metrics.

```sql
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
```

```sql
SELECT *
FROM gold.report_products;

```

## How to Run the Project

1. Create the `gold` schema and tables.
2. Load data into `gold.dim_customers`, `gold.dim_products`, and `gold.fact_sales`.
3. Run the data-quality checks.
4. Run the sales, product, and customer analysis queries.
5. Create the reporting views.
6. Query the final reports:

## Author - Zar Chi Lin Htet

This project is part of my portfolio, showcasing the SQL skills essential for data analyst roles. If you have any questions, feedback, or would like to collaborate, feel free to get in touch!


- **LinkedIn**: [Connect with me professionally](https://www.linkedin.com/in/zar-chi-lin-htet-863b18286)


Thank you for your support, and I look forward to connecting with you!



