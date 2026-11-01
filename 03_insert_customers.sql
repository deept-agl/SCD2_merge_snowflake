USE DATABASE CUSTOMER_ANALYTICS_DB;
USE WAREHOUSE WH_CUSTOMER_ETL;

-- Initial arrival: three customer snapshots from the source system.
INSERT INTO BRONZE.CUSTOMERS
  (CUSTOMER_ID, CUSTOMER_NAME, CITY, MEMBERSHIP_TIER)
VALUES
  (101, 'Anika Rao', 'Pune', 'Silver'),
  (102, 'Rohan Shah', 'Mumbai', 'Gold'),
  (103, 'Meera Iyer', 'Chennai', 'Silver');

-- The task picks up these inserts automatically after the statement commits.
-- Run 05_validation.sql after the task has succeeded.


