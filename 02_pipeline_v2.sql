USE DATABASE CUSTOMER_ANALYTICS_DB;
USE WAREHOUSE WH_CUSTOMER_ETL;

-- The procedure consumes new customer snapshots and preserves changed values.
CREATE OR REPLACE PROCEDURE GOLD.LOAD_DIM_CUSTOMER()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    v_effective_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

BEGIN

    -- Store the latest customer record received from the source.
    CREATE OR REPLACE TEMPORARY TABLE CUSTOMER_INCOMING (
        CUSTOMER_ID NUMBER,
        CUSTOMER_NAME VARCHAR(100),
        CITY VARCHAR(100),
        MEMBERSHIP_TIER VARCHAR(30)
    );

    BEGIN TRANSACTION;

    -- Read new customer records captured by the Snowflake stream.
    -- If multiple snapshots arrive for a customer, use the latest one.
    INSERT INTO CUSTOMER_INCOMING (
        CUSTOMER_ID,
        CUSTOMER_NAME,
        CITY,
        MEMBERSHIP_TIER
    )
    SELECT
        CUSTOMER_ID,
        CUSTOMER_NAME,
        CITY,
        MEMBERSHIP_TIER
    FROM BRONZE.CUSTOMERS_STREAM
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY SOURCE_UPDATED_AT DESC, SOURCE_RECORD_ID DESC
    ) = 1;

    -- Maintain customer history using a single MERGE.
    MERGE INTO GOLD.DIM_CUSTOMER tgt

    USING (
        -- Rows with a matching key expire changed customer versions.
        SELECT
            src.CUSTOMER_ID AS MERGE_KEY,
            src.CUSTOMER_ID,
            src.CUSTOMER_NAME,
            src.CITY,
            src.MEMBERSHIP_TIER
        FROM CUSTOMER_INCOMING src
        JOIN GOLD.DIM_CUSTOMER tgt
          ON src.CUSTOMER_ID = tgt.CUSTOMER_ID
         AND tgt.IS_CURRENT = TRUE
        WHERE
               tgt.CUSTOMER_NAME IS DISTINCT FROM src.CUSTOMER_NAME
            OR tgt.CITY IS DISTINCT FROM src.CITY
            OR tgt.MEMBERSHIP_TIER IS DISTINCT FROM src.MEMBERSHIP_TIER

        UNION ALL

        -- Rows with a NULL merge key insert new customer versions.
        -- This includes brand-new customers and changed customers.
        SELECT
            NULL AS MERGE_KEY,
            src.CUSTOMER_ID,
            src.CUSTOMER_NAME,
            src.CITY,
            src.MEMBERSHIP_TIER
        FROM CUSTOMER_INCOMING src
        LEFT JOIN GOLD.DIM_CUSTOMER tgt
          ON src.CUSTOMER_ID = tgt.CUSTOMER_ID
         AND tgt.IS_CURRENT = TRUE
        WHERE
               tgt.CUSTOMER_ID IS NULL
            OR tgt.CUSTOMER_NAME IS DISTINCT FROM src.CUSTOMER_NAME
            OR tgt.CITY IS DISTINCT FROM src.CITY
            OR tgt.MEMBERSHIP_TIER IS DISTINCT FROM src.MEMBERSHIP_TIER

    ) src

    ON tgt.CUSTOMER_ID = src.MERGE_KEY
       AND tgt.IS_CURRENT = TRUE

    -- Expire the previous customer version.
    WHEN MATCHED THEN UPDATE SET
        tgt.VALID_TO = :v_effective_at,
        tgt.IS_CURRENT = FALSE

    -- Insert a new current customer version.
    WHEN NOT MATCHED THEN INSERT (
        CUSTOMER_ID,
        CUSTOMER_NAME,
        CITY,
        MEMBERSHIP_TIER,
        VALID_FROM,
        VALID_TO,
        IS_CURRENT
    )
    VALUES (
        src.CUSTOMER_ID,
        src.CUSTOMER_NAME,
        src.CITY,
        src.MEMBERSHIP_TIER,
        :v_effective_at,
        NULL,
        TRUE
    );

    COMMIT;

    RETURN 'Customer dimension updated successfully';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;

END;
$$;

DELETE FROM BRONZE.CUSTOMERS;
DELETE FROM GOLD.DIM_CUSTOMER;

-- A triggered task invokes the procedure whenever the source stream has data.
-- It does not need a minute-by-minute polling schedule.
CREATE OR REPLACE TASK GOLD.TASK_LOAD_DIM_CUSTOMER
  WAREHOUSE = WH_CUSTOMER_ETL
  WHEN SYSTEM$STREAM_HAS_DATA('CUSTOMER_ANALYTICS_DB.BRONZE.CUSTOMERS_STREAM')
AS
  CALL GOLD.LOAD_DIM_CUSTOMER();

-- Tasks are suspended when created; resume to enable automatic processing.
ALTER TASK GOLD.TASK_LOAD_DIM_CUSTOMER RESUME;
