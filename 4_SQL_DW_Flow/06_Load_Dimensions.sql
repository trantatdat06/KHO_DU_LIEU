-- ==============================================================================
-- 06. TRANSFORM + NẠP DIMENSION (mục 4.7.2.3 f–g, 4.7.1.4 Bước 3–4)
--  - Unknown Member: key = 0, Business Key = 'UNKNOWN' (4.7.2.3 b)
--  - SCD Type 2 cho DIM_DRIVER, DIM_TRUCK, DIM_TRAILER, DIM_CUSTOMER, DIM_ROUTE,
--    DIM_FACILITY, DIM_LOAD:
--      + Thuộc tính thay đổi  → đóng phiên bản cũ (expiry_date = @LoadDate − 1, is_current = 0)
--                              và thêm phiên bản mới (effective_date = @LoadDate)
--      + Business Key mới     → thêm phiên bản đầu tiên, effective_date = '1900-01-01'
--        (để mọi giao dịch lịch sử 2022–2024 đều tìm được phiên bản hợp lệ)
--      + Không thay đổi       → bỏ qua (chạy lại an toàn)
--  - DIM_EVENT_TYPE, DIM_MAINTENANCE_TYPE, DIM_INCIDENT_TYPE: chỉ bổ sung giá trị mới
-- ==============================================================================
USE [Logistics_DW];
GO

-- ------------------------------------------------------------------------------
-- 6.0 UNKNOWN MEMBERS
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_Unknown_Members
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @eff DATE = '1900-01-01', @exp DATE = '9999-12-31';

    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_DRIVER WHERE driver_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_DRIVER ON;
        INSERT dbo.DIM_DRIVER (driver_key, driver_id, first_name, last_name, effective_date, expiry_date, is_current)
        VALUES (0, N'UNKNOWN', N'Unknown', N'Unknown', @eff, @exp, 1);
        SET IDENTITY_INSERT dbo.DIM_DRIVER OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_TRUCK WHERE truck_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_TRUCK ON;
        INSERT dbo.DIM_TRUCK (truck_key, truck_id, make, effective_date, expiry_date, is_current)
        VALUES (0, N'UNKNOWN', N'Unknown', @eff, @exp, 1);
        SET IDENTITY_INSERT dbo.DIM_TRUCK OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_TRAILER WHERE trailer_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_TRAILER ON;
        INSERT dbo.DIM_TRAILER (trailer_key, trailer_id, trailer_type, effective_date, expiry_date, is_current)
        VALUES (0, N'UNKNOWN', N'Unknown', @eff, @exp, 1);
        SET IDENTITY_INSERT dbo.DIM_TRAILER OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_CUSTOMER WHERE customer_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_CUSTOMER ON;
        INSERT dbo.DIM_CUSTOMER (customer_key, customer_id, customer_name, effective_date, expiry_date, is_current)
        VALUES (0, N'UNKNOWN', N'Unknown', @eff, @exp, 1);
        SET IDENTITY_INSERT dbo.DIM_CUSTOMER OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_ROUTE WHERE route_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_ROUTE ON;
        INSERT dbo.DIM_ROUTE (route_key, route_id, origin_city, destination_city, effective_date, expiry_date, is_current)
        VALUES (0, N'UNKNOWN', N'Unknown', N'Unknown', @eff, @exp, 1);
        SET IDENTITY_INSERT dbo.DIM_ROUTE OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_FACILITY WHERE facility_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_FACILITY ON;
        INSERT dbo.DIM_FACILITY (facility_key, facility_id, facility_name, effective_date, expiry_date, is_current)
        VALUES (0, N'UNKNOWN', N'Unknown', @eff, @exp, 1);
        SET IDENTITY_INSERT dbo.DIM_FACILITY OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_LOAD WHERE load_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_LOAD ON;
        INSERT dbo.DIM_LOAD (load_key, load_id, effective_date, expiry_date, is_current)
        VALUES (0, N'UNKNOWN', @eff, @exp, 1);
        SET IDENTITY_INSERT dbo.DIM_LOAD OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_EVENT_TYPE WHERE event_type_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_EVENT_TYPE ON;
        INSERT dbo.DIM_EVENT_TYPE (event_type_key, event_type) VALUES (0, N'Unknown');
        SET IDENTITY_INSERT dbo.DIM_EVENT_TYPE OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_MAINTENANCE_TYPE WHERE maintenance_type_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_MAINTENANCE_TYPE ON;
        INSERT dbo.DIM_MAINTENANCE_TYPE (maintenance_type_key, maintenance_type) VALUES (0, N'Unknown');
        SET IDENTITY_INSERT dbo.DIM_MAINTENANCE_TYPE OFF;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.DIM_INCIDENT_TYPE WHERE incident_type_key = 0)
    BEGIN
        SET IDENTITY_INSERT dbo.DIM_INCIDENT_TYPE ON;
        INSERT dbo.DIM_INCIDENT_TYPE (incident_type_key, incident_type) VALUES (0, N'Unknown');
        SET IDENTITY_INSERT dbo.DIM_INCIDENT_TYPE OFF;
    END;
END;
GO

-- ------------------------------------------------------------------------------
-- 6.1 DIM_DRIVER (SCD2)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_DRIVER @BatchId INT, @LoadDate DATE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @ins INT;

    SELECT dbo.fn_Clean(driver_id)                               AS driver_id,
           dbo.fn_Clean(first_name)                              AS first_name,
           dbo.fn_Clean(last_name)                               AS last_name,
           TRY_CAST(dbo.fn_Clean(hire_date) AS DATE)             AS hire_date,
           TRY_CAST(dbo.fn_Clean(termination_date) AS DATE)      AS termination_date,
           dbo.fn_Clean(license_number)                          AS license_number,
           dbo.fn_Clean(license_state)                           AS license_state,
           TRY_CAST(dbo.fn_Clean(date_of_birth) AS DATE)         AS date_of_birth,
           dbo.fn_Clean(home_terminal)                           AS home_terminal,
           dbo.fn_Clean(employment_status)                       AS employment_status,
           dbo.fn_Clean(cdl_class)                               AS cdl_class,
           TRY_CAST(dbo.fn_Clean(years_experience) AS DECIMAL(5,1)) AS years_experience
    INTO #src
    FROM dbo.STG_DRIVERS
    WHERE dbo.fn_Clean(driver_id) IS NOT NULL;
    SET @src = @@ROWCOUNT;

    BEGIN TRAN;
        UPDATE d
        SET expiry_date = CASE WHEN d.effective_date < @LoadDate THEN DATEADD(DAY, -1, @LoadDate) ELSE d.effective_date END,
            is_current  = 0
        FROM dbo.DIM_DRIVER d
        JOIN #src s ON s.driver_id = d.driver_id
        WHERE d.is_current = 1
          AND EXISTS (SELECT s.first_name, s.last_name, s.hire_date, s.termination_date, s.license_number, s.license_state,
                             s.date_of_birth, s.home_terminal, s.employment_status, s.cdl_class, s.years_experience
                      EXCEPT
                      SELECT d.first_name, d.last_name, d.hire_date, d.termination_date, d.license_number, d.license_state,
                             d.date_of_birth, d.home_terminal, d.employment_status, d.cdl_class, d.years_experience);

        INSERT INTO dbo.DIM_DRIVER (driver_id, first_name, last_name, hire_date, termination_date, license_number,
                                    license_state, date_of_birth, home_terminal, employment_status, cdl_class,
                                    years_experience, effective_date, expiry_date, is_current)
        SELECT s.*,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.DIM_DRIVER x WHERE x.driver_id = s.driver_id) THEN @LoadDate ELSE '1900-01-01' END,
               '9999-12-31', 1
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_DRIVER d WHERE d.driver_id = s.driver_id AND d.is_current = 1);
        SET @ins = @@ROWCOUNT;
    COMMIT;

    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_DRIVERS', N'DIM_DRIVER', @src, @ins;
END;
GO

-- ------------------------------------------------------------------------------
-- 6.2 DIM_TRUCK (SCD2)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_TRUCK @BatchId INT, @LoadDate DATE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @ins INT;

    SELECT dbo.fn_Clean(truck_id)                                     AS truck_id,
           dbo.fn_Clean(unit_number)                                  AS unit_number,
           dbo.fn_Clean(make)                                         AS make,
           TRY_CAST(dbo.fn_Clean(model_year) AS INT)                  AS model_year,
           dbo.fn_Clean(vin)                                          AS vin,
           TRY_CAST(dbo.fn_Clean(acquisition_date) AS DATE)           AS acquisition_date,
           TRY_CAST(dbo.fn_Clean(acquisition_mileage) AS DECIMAL(12,1)) AS acquisition_mileage,
           dbo.fn_Clean(fuel_type)                                    AS fuel_type,
           TRY_CAST(dbo.fn_Clean(tank_capacity_gallons) AS DECIMAL(8,1)) AS tank_capacity_gallons,
           dbo.fn_Clean(status)                                       AS status,
           dbo.fn_Clean(home_terminal)                                AS home_terminal
    INTO #src
    FROM dbo.STG_TRUCKS
    WHERE dbo.fn_Clean(truck_id) IS NOT NULL;
    SET @src = @@ROWCOUNT;

    BEGIN TRAN;
        UPDATE d
        SET expiry_date = CASE WHEN d.effective_date < @LoadDate THEN DATEADD(DAY, -1, @LoadDate) ELSE d.effective_date END,
            is_current  = 0
        FROM dbo.DIM_TRUCK d
        JOIN #src s ON s.truck_id = d.truck_id
        WHERE d.is_current = 1
          AND EXISTS (SELECT s.unit_number, s.make, s.model_year, s.vin, s.acquisition_date, s.acquisition_mileage,
                             s.fuel_type, s.tank_capacity_gallons, s.status, s.home_terminal
                      EXCEPT
                      SELECT d.unit_number, d.make, d.model_year, d.vin, d.acquisition_date, d.acquisition_mileage,
                             d.fuel_type, d.tank_capacity_gallons, d.status, d.home_terminal);

        INSERT INTO dbo.DIM_TRUCK (truck_id, unit_number, make, model_year, vin, acquisition_date, acquisition_mileage,
                                   fuel_type, tank_capacity_gallons, status, home_terminal,
                                   effective_date, expiry_date, is_current)
        SELECT s.*,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.DIM_TRUCK x WHERE x.truck_id = s.truck_id) THEN @LoadDate ELSE '1900-01-01' END,
               '9999-12-31', 1
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_TRUCK d WHERE d.truck_id = s.truck_id AND d.is_current = 1);
        SET @ins = @@ROWCOUNT;
    COMMIT;

    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_TRUCKS', N'DIM_TRUCK', @src, @ins;
END;
GO

-- ------------------------------------------------------------------------------
-- 6.3 DIM_TRAILER (SCD2)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_TRAILER @BatchId INT, @LoadDate DATE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @ins INT;

    SELECT dbo.fn_Clean(trailer_id)                            AS trailer_id,
           dbo.fn_Clean(trailer_number)                        AS trailer_number,
           dbo.fn_Clean(trailer_type)                          AS trailer_type,
           TRY_CAST(dbo.fn_Clean(length_feet) AS DECIMAL(5,1)) AS length_feet,
           TRY_CAST(dbo.fn_Clean(model_year) AS INT)           AS model_year,
           dbo.fn_Clean(vin)                                   AS vin,
           TRY_CAST(dbo.fn_Clean(acquisition_date) AS DATE)    AS acquisition_date,
           dbo.fn_Clean(status)                                AS status,
           dbo.fn_Clean(current_location)                      AS current_location
    INTO #src
    FROM dbo.STG_TRAILERS
    WHERE dbo.fn_Clean(trailer_id) IS NOT NULL;
    SET @src = @@ROWCOUNT;

    BEGIN TRAN;
        UPDATE d
        SET expiry_date = CASE WHEN d.effective_date < @LoadDate THEN DATEADD(DAY, -1, @LoadDate) ELSE d.effective_date END,
            is_current  = 0
        FROM dbo.DIM_TRAILER d
        JOIN #src s ON s.trailer_id = d.trailer_id
        WHERE d.is_current = 1
          AND EXISTS (SELECT s.trailer_number, s.trailer_type, s.length_feet, s.model_year, s.vin,
                             s.acquisition_date, s.status, s.current_location
                      EXCEPT
                      SELECT d.trailer_number, d.trailer_type, d.length_feet, d.model_year, d.vin,
                             d.acquisition_date, d.status, d.current_location);

        INSERT INTO dbo.DIM_TRAILER (trailer_id, trailer_number, trailer_type, length_feet, model_year, vin,
                                     acquisition_date, status, current_location,
                                     effective_date, expiry_date, is_current)
        SELECT s.*,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.DIM_TRAILER x WHERE x.trailer_id = s.trailer_id) THEN @LoadDate ELSE '1900-01-01' END,
               '9999-12-31', 1
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_TRAILER d WHERE d.trailer_id = s.trailer_id AND d.is_current = 1);
        SET @ins = @@ROWCOUNT;
    COMMIT;

    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_TRAILERS', N'DIM_TRAILER', @src, @ins;
END;
GO

-- ------------------------------------------------------------------------------
-- 6.4 DIM_CUSTOMER (SCD2)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_CUSTOMER @BatchId INT, @LoadDate DATE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @ins INT;

    SELECT dbo.fn_Clean(customer_id)                                       AS customer_id,
           dbo.fn_Clean(customer_name)                                     AS customer_name,
           dbo.fn_Clean(customer_type)                                     AS customer_type,
           TRY_CAST(dbo.fn_Clean(credit_terms_days) AS INT)                AS credit_terms_days,
           dbo.fn_Clean(primary_freight_type)                              AS primary_freight_type,
           dbo.fn_Clean(account_status)                                    AS account_status,
           TRY_CAST(dbo.fn_Clean(contract_start_date) AS DATE)             AS contract_start_date,
           TRY_CAST(dbo.fn_Clean(annual_revenue_potential) AS DECIMAL(18,2)) AS annual_revenue_potential
    INTO #src
    FROM dbo.STG_CUSTOMERS
    WHERE dbo.fn_Clean(customer_id) IS NOT NULL;
    SET @src = @@ROWCOUNT;

    BEGIN TRAN;
        UPDATE d
        SET expiry_date = CASE WHEN d.effective_date < @LoadDate THEN DATEADD(DAY, -1, @LoadDate) ELSE d.effective_date END,
            is_current  = 0
        FROM dbo.DIM_CUSTOMER d
        JOIN #src s ON s.customer_id = d.customer_id
        WHERE d.is_current = 1
          AND EXISTS (SELECT s.customer_name, s.customer_type, s.credit_terms_days, s.primary_freight_type,
                             s.account_status, s.contract_start_date, s.annual_revenue_potential
                      EXCEPT
                      SELECT d.customer_name, d.customer_type, d.credit_terms_days, d.primary_freight_type,
                             d.account_status, d.contract_start_date, d.annual_revenue_potential);

        INSERT INTO dbo.DIM_CUSTOMER (customer_id, customer_name, customer_type, credit_terms_days, primary_freight_type,
                                      account_status, contract_start_date, annual_revenue_potential,
                                      effective_date, expiry_date, is_current)
        SELECT s.*,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.DIM_CUSTOMER x WHERE x.customer_id = s.customer_id) THEN @LoadDate ELSE '1900-01-01' END,
               '9999-12-31', 1
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_CUSTOMER d WHERE d.customer_id = s.customer_id AND d.is_current = 1);
        SET @ins = @@ROWCOUNT;
    COMMIT;

    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_CUSTOMERS', N'DIM_CUSTOMER', @src, @ins;
END;
GO

-- ------------------------------------------------------------------------------
-- 6.5 DIM_ROUTE (SCD2)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_ROUTE @BatchId INT, @LoadDate DATE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @ins INT;

    SELECT dbo.fn_Clean(route_id)                                       AS route_id,
           dbo.fn_Clean(origin_city)                                    AS origin_city,
           dbo.fn_Clean(origin_state)                                   AS origin_state,
           dbo.fn_Clean(destination_city)                               AS destination_city,
           dbo.fn_Clean(destination_state)                              AS destination_state,
           TRY_CAST(dbo.fn_Clean(typical_distance_miles) AS DECIMAL(10,1)) AS typical_distance_miles,
           TRY_CAST(dbo.fn_Clean(base_rate_per_mile) AS DECIMAL(10,4))  AS base_rate_per_mile,
           TRY_CAST(dbo.fn_Clean(fuel_surcharge_rate) AS DECIMAL(10,4)) AS fuel_surcharge_rate,
           TRY_CAST(dbo.fn_Clean(typical_transit_days) AS DECIMAL(5,1)) AS typical_transit_days
    INTO #src
    FROM dbo.STG_ROUTES
    WHERE dbo.fn_Clean(route_id) IS NOT NULL;
    SET @src = @@ROWCOUNT;

    BEGIN TRAN;
        UPDATE d
        SET expiry_date = CASE WHEN d.effective_date < @LoadDate THEN DATEADD(DAY, -1, @LoadDate) ELSE d.effective_date END,
            is_current  = 0
        FROM dbo.DIM_ROUTE d
        JOIN #src s ON s.route_id = d.route_id
        WHERE d.is_current = 1
          AND EXISTS (SELECT s.origin_city, s.origin_state, s.destination_city, s.destination_state,
                             s.typical_distance_miles, s.base_rate_per_mile, s.fuel_surcharge_rate, s.typical_transit_days
                      EXCEPT
                      SELECT d.origin_city, d.origin_state, d.destination_city, d.destination_state,
                             d.typical_distance_miles, d.base_rate_per_mile, d.fuel_surcharge_rate, d.typical_transit_days);

        INSERT INTO dbo.DIM_ROUTE (route_id, origin_city, origin_state, destination_city, destination_state,
                                   typical_distance_miles, base_rate_per_mile, fuel_surcharge_rate, typical_transit_days,
                                   effective_date, expiry_date, is_current)
        SELECT s.*,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.DIM_ROUTE x WHERE x.route_id = s.route_id) THEN @LoadDate ELSE '1900-01-01' END,
               '9999-12-31', 1
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_ROUTE d WHERE d.route_id = s.route_id AND d.is_current = 1);
        SET @ins = @@ROWCOUNT;
    COMMIT;

    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_ROUTES', N'DIM_ROUTE', @src, @ins;
END;
GO

-- ------------------------------------------------------------------------------
-- 6.6 DIM_FACILITY (SCD2)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_FACILITY @BatchId INT, @LoadDate DATE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @ins INT;

    SELECT dbo.fn_Clean(facility_id)                         AS facility_id,
           dbo.fn_Clean(facility_name)                       AS facility_name,
           dbo.fn_Clean(facility_type)                       AS facility_type,
           dbo.fn_Clean(city)                                AS city,
           dbo.fn_Clean(state)                               AS state,
           TRY_CAST(dbo.fn_Clean(latitude) AS DECIMAL(9,6))  AS latitude,
           TRY_CAST(dbo.fn_Clean(longitude) AS DECIMAL(9,6)) AS longitude,
           TRY_CAST(dbo.fn_Clean(dock_doors) AS INT)         AS dock_doors,
           dbo.fn_Clean(operating_hours)                     AS operating_hours
    INTO #src
    FROM dbo.STG_FACILITIES
    WHERE dbo.fn_Clean(facility_id) IS NOT NULL;
    SET @src = @@ROWCOUNT;

    BEGIN TRAN;
        UPDATE d
        SET expiry_date = CASE WHEN d.effective_date < @LoadDate THEN DATEADD(DAY, -1, @LoadDate) ELSE d.effective_date END,
            is_current  = 0
        FROM dbo.DIM_FACILITY d
        JOIN #src s ON s.facility_id = d.facility_id
        WHERE d.is_current = 1
          AND EXISTS (SELECT s.facility_name, s.facility_type, s.city, s.state, s.latitude, s.longitude,
                             s.dock_doors, s.operating_hours
                      EXCEPT
                      SELECT d.facility_name, d.facility_type, d.city, d.state, d.latitude, d.longitude,
                             d.dock_doors, d.operating_hours);

        INSERT INTO dbo.DIM_FACILITY (facility_id, facility_name, facility_type, city, state, latitude, longitude,
                                      dock_doors, operating_hours, effective_date, expiry_date, is_current)
        SELECT s.*,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.DIM_FACILITY x WHERE x.facility_id = s.facility_id) THEN @LoadDate ELSE '1900-01-01' END,
               '9999-12-31', 1
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_FACILITY d WHERE d.facility_id = s.facility_id AND d.is_current = 1);
        SET @ins = @@ROWCOUNT;
    COMMIT;

    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_FACILITIES', N'DIM_FACILITY', @src, @ins;
END;
GO

-- ------------------------------------------------------------------------------
-- 6.7 DIM_LOAD (SCD2) – nạp SAU DIM_CUSTOMER và DIM_ROUTE (4.7.1.4 Bước 4)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_LOAD @BatchId INT, @LoadDate DATE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @ins INT;

    SELECT dbo.fn_Clean(load_id)                                     AS load_id,
           dbo.fn_Clean(customer_id)                                 AS customer_id,
           dbo.fn_Clean(route_id)                                    AS route_id,
           TRY_CAST(dbo.fn_Clean(load_date) AS DATE)                 AS load_date,
           dbo.fn_Clean(load_type)                                   AS load_type,
           TRY_CAST(dbo.fn_Clean(weight_lbs) AS DECIMAL(12,2))       AS weight_lbs,
           TRY_CAST(TRY_CAST(dbo.fn_Clean(pieces) AS DECIMAL(12,2)) AS INT) AS pieces,
           TRY_CAST(dbo.fn_Clean(revenue) AS DECIMAL(18,2))          AS revenue,
           TRY_CAST(dbo.fn_Clean(fuel_surcharge) AS DECIMAL(18,2))   AS fuel_surcharge,
           TRY_CAST(dbo.fn_Clean(accessorial_charges) AS DECIMAL(18,2)) AS accessorial_charges,
           dbo.fn_Clean(load_status)                                 AS load_status,
           dbo.fn_Clean(booking_type)                                AS booking_type
    INTO #src
    FROM dbo.STG_LOADS
    WHERE dbo.fn_Clean(load_id) IS NOT NULL;
    SET @src = @@ROWCOUNT;
    CREATE UNIQUE CLUSTERED INDEX IX_src ON #src (load_id);

    BEGIN TRAN;
        UPDATE d
        SET expiry_date = CASE WHEN d.effective_date < @LoadDate THEN DATEADD(DAY, -1, @LoadDate) ELSE d.effective_date END,
            is_current  = 0
        FROM dbo.DIM_LOAD d
        JOIN #src s ON s.load_id = d.load_id
        WHERE d.is_current = 1
          AND EXISTS (SELECT s.customer_id, s.route_id, s.load_date, s.load_type, s.weight_lbs, s.pieces, s.revenue,
                             s.fuel_surcharge, s.accessorial_charges, s.load_status, s.booking_type
                      EXCEPT
                      SELECT d.customer_id, d.route_id, d.load_date, d.load_type, d.weight_lbs, d.pieces, d.revenue,
                             d.fuel_surcharge, d.accessorial_charges, d.load_status, d.booking_type);

        INSERT INTO dbo.DIM_LOAD (load_id, customer_id, route_id, load_date, load_type, weight_lbs, pieces, revenue,
                                  fuel_surcharge, accessorial_charges, load_status, booking_type,
                                  effective_date, expiry_date, is_current)
        SELECT s.*,
               CASE WHEN EXISTS (SELECT 1 FROM dbo.DIM_LOAD x WHERE x.load_id = s.load_id) THEN @LoadDate ELSE '1900-01-01' END,
               '9999-12-31', 1
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_LOAD d WHERE d.load_id = s.load_id AND d.is_current = 1);
        SET @ins = @@ROWCOUNT;
    COMMIT;

    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_LOADS', N'DIM_LOAD', @src, @ins;
END;
GO

-- ------------------------------------------------------------------------------
-- 6.8 DIM_EVENT_TYPE, DIM_MAINTENANCE_TYPE, DIM_INCIDENT_TYPE (bổ sung giá trị mới)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_Type_Dimensions @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3), @src INT, @ins INT;

    SET @t0 = SYSDATETIME();
    INSERT INTO dbo.DIM_EVENT_TYPE (event_type)
    SELECT DISTINCT dbo.fn_Clean(event_type) FROM dbo.STG_DELIVERY_EVENTS s
    WHERE dbo.fn_Clean(event_type) IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.DIM_EVENT_TYPE d WHERE d.event_type = dbo.fn_Clean(s.event_type));
    SET @ins = @@ROWCOUNT;
    SELECT @src = COUNT(DISTINCT event_type) FROM dbo.STG_DELIVERY_EVENTS;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_DELIVERY_EVENTS', N'DIM_EVENT_TYPE', @src, @ins;

    SET @t0 = SYSDATETIME();
    INSERT INTO dbo.DIM_MAINTENANCE_TYPE (maintenance_type)
    SELECT DISTINCT dbo.fn_Clean(maintenance_type) FROM dbo.STG_MAINTENANCE_RECORDS s
    WHERE dbo.fn_Clean(maintenance_type) IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.DIM_MAINTENANCE_TYPE d WHERE d.maintenance_type = dbo.fn_Clean(s.maintenance_type));
    SET @ins = @@ROWCOUNT;
    SELECT @src = COUNT(DISTINCT maintenance_type) FROM dbo.STG_MAINTENANCE_RECORDS;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_MAINTENANCE_RECORDS', N'DIM_MAINTENANCE_TYPE', @src, @ins;

    SET @t0 = SYSDATETIME();
    INSERT INTO dbo.DIM_INCIDENT_TYPE (incident_type)
    SELECT DISTINCT dbo.fn_Clean(incident_type) FROM dbo.STG_SAFETY_INCIDENTS s
    WHERE dbo.fn_Clean(incident_type) IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.DIM_INCIDENT_TYPE d WHERE d.incident_type = dbo.fn_Clean(s.incident_type));
    SET @ins = @@ROWCOUNT;
    SELECT @src = COUNT(DISTINCT incident_type) FROM dbo.STG_SAFETY_INCIDENTS;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_SAFETY_INCIDENTS', N'DIM_INCIDENT_TYPE', @src, @ins;
END;
GO

PRINT N'06. Đã tạo các thủ tục nạp Dimension (SCD2 + Unknown Member).';
GO
