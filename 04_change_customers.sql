USE DATABASE CUSTOMER_ANALYTICS_DB;
USE WAREHOUSE WH_CUSTOMER_ETL;

-- The next source snapshots contain a city change, an unchanged customer,
-- and a newly registered customer. The target history updates automatically.
INSERT INTO BRONZE.CUSTOMERS
  (CUSTOMER_ID, CUSTOMER_NAME, CITY, MEMBERSHIP_TIER)
VALUES
  (101, 'Anika Rao', 'Bengaluru', 'Silver'), --UPDATE EXPIRED AND INSERT NEW
  (102, 'Rohan Shah', 'Mumbai', 'Gold'),
  (104, 'Sara Khan', 'Delhi', 'Bronze'); --INSERT NEW

-- After the task finishes, insert a later membership upgrade separately.
-- Keeping this as a distinct load makes both historical versions visible.
INSERT INTO BRONZE.CUSTOMERS
  (CUSTOMER_ID, CUSTOMER_NAME, CITY, MEMBERSHIP_TIER)
VALUES (101, 'Anika Rao', 'Bengaluru', 'Gold'); --Membership change
