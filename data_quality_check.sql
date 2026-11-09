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
