-- ==============================================================================
-- 07. TRANSFORM + NẠP FACT (mục 4.7.2.4 Mapping Dimension Key, 4.7.1.4 Bước 5–6)
--  - Business Key → Surrogate Key: tra Dimension theo Business Key VÀ ngày giao dịch
--    nằm trong [effective_date, expiry_date] (đúng phiên bản SCD2 tại thời điểm phát sinh)
--  - Không tìm được Dimension → Unknown Member (key = 0)
--  - Không đọc được ngày giao dịch → từ chối dòng (rejected_row_count trong ETL_LOG)
--  - Phương pháp cập nhật: Insert (incremental) – chỉ nạp dòng chưa có trong Fact
--    theo Degenerate Dimension / grain → chạy lại không bị nhân bản
-- ==============================================================================
USE [Logistics_DW];
GO

-- ------------------------------------------------------------------------------
-- 7.1 FACT_TRIP (grain: 1 chuyến)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_FACT_TRIP @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @dup INT, @ins INT, @rej INT;

    SELECT dbo.fn_Clean(trip_id)                                       AS trip_id,
           dbo.fn_Clean(load_id)                                       AS load_id,
           dbo.fn_Clean(driver_id)                                     AS driver_id,
           dbo.fn_Clean(truck_id)                                      AS truck_id,
           dbo.fn_Clean(trailer_id)                                    AS trailer_id,
           dbo.fn_Clean(route_id)                                      AS route_id,
           TRY_CAST(dbo.fn_Clean(dispatch_date) AS DATE)               AS dispatch_date,
           dbo.fn_Clean(trip_status)                                   AS trip_status,
           TRY_CAST(dbo.fn_Clean(actual_distance_miles) AS DECIMAL(10,1)) AS actual_distance_miles,
           TRY_CAST(dbo.fn_Clean(actual_duration_hours) AS DECIMAL(10,2)) AS actual_duration_hours,
           TRY_CAST(dbo.fn_Clean(fuel_gallons_used) AS DECIMAL(10,2))  AS fuel_gallons_used,
           TRY_CAST(dbo.fn_Clean(average_mpg) AS DECIMAL(6,2))         AS average_mpg,
           dbo.fn_ToHours(idle_time_hours)                             AS idle_time_hours
    INTO #s
    FROM dbo.STG_TRIPS;
    SET @src = @@ROWCOUNT;

    SELECT @dup = COUNT(*) FROM #s s WHERE EXISTS (SELECT 1 FROM dbo.FACT_TRIP f WHERE f.trip_id = s.trip_id);

    INSERT INTO dbo.FACT_TRIP (dispatch_date_key, load_key, driver_key, truck_key, trailer_key, route_key, trip_id,
                               trip_status, actual_distance_miles, actual_duration_hours, fuel_gallons_used,
                               average_mpg, idle_time_hours, trip_count)
    SELECT dt.date_key,
           ISNULL(l.load_key, 0), ISNULL(dr.driver_key, 0), ISNULL(tk.truck_key, 0),
           ISNULL(tl.trailer_key, 0), ISNULL(r.route_key, 0),
           s.trip_id, s.trip_status, s.actual_distance_miles, s.actual_duration_hours,
           s.fuel_gallons_used, s.average_mpg, s.idle_time_hours, 1
    FROM #s s
    JOIN dbo.DIM_DATE dt        ON dt.full_date = s.dispatch_date
    LEFT JOIN dbo.DIM_LOAD l    ON l.load_id = s.load_id       AND s.dispatch_date BETWEEN l.effective_date  AND l.expiry_date
    LEFT JOIN dbo.DIM_DRIVER dr ON dr.driver_id = s.driver_id  AND s.dispatch_date BETWEEN dr.effective_date AND dr.expiry_date
    LEFT JOIN dbo.DIM_TRUCK tk  ON tk.truck_id = s.truck_id    AND s.dispatch_date BETWEEN tk.effective_date AND tk.expiry_date
    LEFT JOIN dbo.DIM_TRAILER tl ON tl.trailer_id = s.trailer_id AND s.dispatch_date BETWEEN tl.effective_date AND tl.expiry_date
    LEFT JOIN dbo.DIM_ROUTE r   ON r.route_id = s.route_id     AND s.dispatch_date BETWEEN r.effective_date  AND r.expiry_date
    WHERE s.trip_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.FACT_TRIP f WHERE f.trip_id = s.trip_id);
    SET @ins = @@ROWCOUNT;

    SET @rej = @src - @dup - @ins;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_TRIPS', N'FACT_TRIP', @src, @ins, @rej;
END;
GO

-- ------------------------------------------------------------------------------
-- 7.2 FACT_DELIVERY_EVENT (grain: 1 sự kiện giao hàng) – cần FACT_TRIP nạp trước
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_FACT_DELIVERY_EVENT @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @dup INT, @ins INT, @rej INT;

    SELECT dbo.fn_Clean(event_id)                                    AS event_id,
           dbo.fn_Clean(load_id)                                     AS load_id,
           dbo.fn_Clean(trip_id)                                     AS trip_id,
           dbo.fn_Clean(event_type)                                  AS event_type,
           dbo.fn_Clean(facility_id)                                 AS facility_id,
           TRY_CAST(dbo.fn_Clean(scheduled_datetime) AS DATETIME2(0)) AS scheduled_datetime,
           TRY_CAST(dbo.fn_Clean(actual_datetime) AS DATETIME2(0))   AS actual_datetime,
           TRY_CAST(dbo.fn_Clean(detention_minutes) AS DECIMAL(10,1)) AS detention_minutes,
           dbo.fn_ToBit(on_time_flag)                                AS on_time_flag,
           dbo.fn_Clean(location_city)                               AS location_city,
           dbo.fn_Clean(location_state)                              AS location_state
    INTO #s
    FROM dbo.STG_DELIVERY_EVENTS;
    SET @src = @@ROWCOUNT;

    SELECT @dup = COUNT(*) FROM #s s WHERE EXISTS (SELECT 1 FROM dbo.FACT_DELIVERY_EVENT f WHERE f.event_id = s.event_id);

    INSERT INTO dbo.FACT_DELIVERY_EVENT (scheduled_date_key, trip_key, event_type_key, facility_key, event_id, load_id,
                                         scheduled_datetime, actual_datetime, location_city, location_state,
                                         detention_minutes, on_time_flag, event_count)
    SELECT dt.date_key, t.trip_key, ISNULL(et.event_type_key, 0), ISNULL(fa.facility_key, 0),
           s.event_id, s.load_id, s.scheduled_datetime, s.actual_datetime, s.location_city, s.location_state,
           s.detention_minutes, s.on_time_flag, 1
    FROM #s s
    JOIN dbo.DIM_DATE dt            ON dt.full_date = CAST(s.scheduled_datetime AS DATE)
    LEFT JOIN dbo.FACT_TRIP t       ON t.trip_id = s.trip_id
    LEFT JOIN dbo.DIM_EVENT_TYPE et ON et.event_type = s.event_type
    LEFT JOIN dbo.DIM_FACILITY fa   ON fa.facility_id = s.facility_id
                                   AND CAST(s.scheduled_datetime AS DATE) BETWEEN fa.effective_date AND fa.expiry_date
    WHERE s.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.FACT_DELIVERY_EVENT f WHERE f.event_id = s.event_id);
    SET @ins = @@ROWCOUNT;

    SET @rej = @src - @dup - @ins;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_DELIVERY_EVENTS', N'FACT_DELIVERY_EVENT', @src, @ins, @rej;
END;
GO

-- ------------------------------------------------------------------------------
-- 7.3 FACT_FUEL_PURCHASE (grain: 1 giao dịch mua nhiên liệu)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_FACT_FUEL_PURCHASE @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @dup INT, @ins INT, @rej INT;

    SELECT dbo.fn_Clean(fuel_purchase_id)                            AS fuel_purchase_id,
           dbo.fn_Clean(trip_id)                                     AS trip_id,
           dbo.fn_Clean(truck_id)                                    AS truck_id,
           dbo.fn_Clean(driver_id)                                   AS driver_id,
           CAST(TRY_CAST(dbo.fn_Clean(purchase_date) AS DATETIME2(0)) AS DATE) AS purchase_date,
           dbo.fn_Clean(location_city)                               AS location_city,
           dbo.fn_Clean(location_state)                              AS location_state,
           TRY_CAST(dbo.fn_Clean(gallons) AS DECIMAL(10,2))          AS gallons,
           TRY_CAST(dbo.fn_Clean(price_per_gallon) AS DECIMAL(10,3)) AS price_per_gallon,
           TRY_CAST(dbo.fn_Clean(total_cost) AS DECIMAL(12,2))       AS total_cost,
           dbo.fn_Clean(fuel_card_number)                            AS fuel_card_number
    INTO #s
    FROM dbo.STG_FUEL_PURCHASES;
    SET @src = @@ROWCOUNT;

    SELECT @dup = COUNT(*) FROM #s s WHERE EXISTS (SELECT 1 FROM dbo.FACT_FUEL_PURCHASE f WHERE f.fuel_purchase_id = s.fuel_purchase_id);

    INSERT INTO dbo.FACT_FUEL_PURCHASE (purchase_date_key, trip_key, truck_key, driver_key, fuel_purchase_id,
                                        location_city, location_state, gallons, price_per_gallon, total_cost,
                                        fuel_card_number, purchase_count)
    SELECT dt.date_key, t.trip_key, ISNULL(tk.truck_key, 0), ISNULL(dr.driver_key, 0), s.fuel_purchase_id,
           s.location_city, s.location_state, s.gallons, s.price_per_gallon, s.total_cost,
           s.fuel_card_number, 1
    FROM #s s
    JOIN dbo.DIM_DATE dt        ON dt.full_date = s.purchase_date
    LEFT JOIN dbo.FACT_TRIP t   ON t.trip_id = s.trip_id
    LEFT JOIN dbo.DIM_TRUCK tk  ON tk.truck_id = s.truck_id   AND s.purchase_date BETWEEN tk.effective_date AND tk.expiry_date
    LEFT JOIN dbo.DIM_DRIVER dr ON dr.driver_id = s.driver_id AND s.purchase_date BETWEEN dr.effective_date AND dr.expiry_date
    WHERE s.fuel_purchase_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.FACT_FUEL_PURCHASE f WHERE f.fuel_purchase_id = s.fuel_purchase_id);
    SET @ins = @@ROWCOUNT;

    SET @rej = @src - @dup - @ins;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_FUEL_PURCHASES', N'FACT_FUEL_PURCHASE', @src, @ins, @rej;
END;
GO

-- ------------------------------------------------------------------------------
-- 7.4 FACT_MAINTENANCE (grain: 1 lần bảo dưỡng/sửa chữa)
-- facility_location chỉ là tên thành phố → ánh xạ sang DIM_FACILITY theo city:
-- ưu tiên cơ sở loại 'Terminal', sau đó facility_id nhỏ nhất; không khớp → Unknown (0)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_FACT_MAINTENANCE @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @dup INT, @ins INT, @rej INT;

    SELECT dbo.fn_Clean(maintenance_id)                              AS maintenance_id,
           dbo.fn_Clean(truck_id)                                    AS truck_id,
           TRY_CAST(dbo.fn_Clean(maintenance_date) AS DATE)          AS maintenance_date,
           dbo.fn_Clean(maintenance_type)                            AS maintenance_type,
           TRY_CAST(dbo.fn_Clean(odometer_reading) AS DECIMAL(12,1)) AS odometer_reading,
           TRY_CAST(dbo.fn_Clean(labor_hours) AS DECIMAL(10,2))      AS labor_hours,
           TRY_CAST(dbo.fn_Clean(labor_cost) AS DECIMAL(12,2))       AS labor_cost,
           TRY_CAST(dbo.fn_Clean(parts_cost) AS DECIMAL(12,2))       AS parts_cost,
           TRY_CAST(dbo.fn_Clean(total_cost) AS DECIMAL(12,2))       AS total_cost,
           dbo.fn_Clean(facility_location)                           AS facility_location,
           dbo.fn_ToHours(downtime_hours)                            AS downtime_hours,
           dbo.fn_Clean(service_description)                         AS service_description
    INTO #s
    FROM dbo.STG_MAINTENANCE_RECORDS;
    SET @src = @@ROWCOUNT;

    SELECT city, facility_key
    INTO #fac_city
    FROM (
        SELECT city, facility_key,
               ROW_NUMBER() OVER (PARTITION BY city
                                  ORDER BY CASE WHEN facility_type = N'Terminal' THEN 0 ELSE 1 END, facility_id) AS rn
        FROM dbo.DIM_FACILITY
        WHERE is_current = 1 AND facility_key <> 0
    ) x
    WHERE rn = 1;

    SELECT @dup = COUNT(*) FROM #s s WHERE EXISTS (SELECT 1 FROM dbo.FACT_MAINTENANCE f WHERE f.maintenance_id = s.maintenance_id);

    INSERT INTO dbo.FACT_MAINTENANCE (maintenance_date_key, truck_key, maintenance_type_key, facility_key, maintenance_id,
                                      odometer_reading, labor_hours, labor_cost, parts_cost, total_cost,
                                      downtime_hours, facility_location, service_description, maintenance_count)
    SELECT dt.date_key, ISNULL(tk.truck_key, 0), ISNULL(mt.maintenance_type_key, 0), ISNULL(fc.facility_key, 0),
           s.maintenance_id, s.odometer_reading, s.labor_hours, s.labor_cost, s.parts_cost, s.total_cost,
           s.downtime_hours, s.facility_location, s.service_description, 1
    FROM #s s
    JOIN dbo.DIM_DATE dt                  ON dt.full_date = s.maintenance_date
    LEFT JOIN dbo.DIM_TRUCK tk            ON tk.truck_id = s.truck_id AND s.maintenance_date BETWEEN tk.effective_date AND tk.expiry_date
    LEFT JOIN dbo.DIM_MAINTENANCE_TYPE mt ON mt.maintenance_type = s.maintenance_type
    LEFT JOIN #fac_city fc                ON fc.city = s.facility_location
    WHERE s.maintenance_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.FACT_MAINTENANCE f WHERE f.maintenance_id = s.maintenance_id);
    SET @ins = @@ROWCOUNT;

    SET @rej = @src - @dup - @ins;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_MAINTENANCE_RECORDS', N'FACT_MAINTENANCE', @src, @ins, @rej;
END;
GO

-- ------------------------------------------------------------------------------
-- 7.5 FACT_SAFETY_INCIDENT (grain: 1 sự cố)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_FACT_SAFETY_INCIDENT @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @dup INT, @ins INT, @rej INT;

    SELECT dbo.fn_Clean(incident_id)                                  AS incident_id,
           dbo.fn_Clean(trip_id)                                      AS trip_id,
           dbo.fn_Clean(truck_id)                                     AS truck_id,
           dbo.fn_Clean(driver_id)                                    AS driver_id,
           CAST(TRY_CAST(dbo.fn_Clean(incident_date) AS DATETIME2(0)) AS DATE) AS incident_date,
           dbo.fn_Clean(incident_type)                                AS incident_type,
           dbo.fn_Clean(location_city)                                AS location_city,
           dbo.fn_Clean(location_state)                               AS location_state,
           dbo.fn_ToBit(at_fault_flag)                                AS at_fault_flag,
           dbo.fn_ToBit(injury_flag)                                  AS injury_flag,
           TRY_CAST(dbo.fn_Clean(vehicle_damage_cost) AS DECIMAL(12,2)) AS vehicle_damage_cost,
           TRY_CAST(dbo.fn_Clean(cargo_damage_cost) AS DECIMAL(12,2))   AS cargo_damage_cost,
           TRY_CAST(dbo.fn_Clean(claim_amount) AS DECIMAL(12,2))        AS claim_amount,
           dbo.fn_ToBit(preventable_flag)                             AS preventable_flag,
           dbo.fn_Clean(description)                                  AS description
    INTO #s
    FROM dbo.STG_SAFETY_INCIDENTS;
    SET @src = @@ROWCOUNT;

    SELECT @dup = COUNT(*) FROM #s s WHERE EXISTS (SELECT 1 FROM dbo.FACT_SAFETY_INCIDENT f WHERE f.incident_id = s.incident_id);

    INSERT INTO dbo.FACT_SAFETY_INCIDENT (incident_date_key, trip_key, truck_key, driver_key, incident_type_key,
                                          incident_id, location_city, location_state, at_fault_flag, injury_flag,
                                          vehicle_damage_cost, cargo_damage_cost, claim_amount, preventable_flag,
                                          description, incident_count)
    SELECT dt.date_key, t.trip_key, ISNULL(tk.truck_key, 0), ISNULL(dr.driver_key, 0), ISNULL(it.incident_type_key, 0),
           s.incident_id, s.location_city, s.location_state, s.at_fault_flag, s.injury_flag,
           s.vehicle_damage_cost, s.cargo_damage_cost, s.claim_amount, s.preventable_flag, s.description, 1
    FROM #s s
    JOIN dbo.DIM_DATE dt               ON dt.full_date = s.incident_date
    LEFT JOIN dbo.FACT_TRIP t          ON t.trip_id = s.trip_id
    LEFT JOIN dbo.DIM_TRUCK tk         ON tk.truck_id = s.truck_id   AND s.incident_date BETWEEN tk.effective_date AND tk.expiry_date
    LEFT JOIN dbo.DIM_DRIVER dr        ON dr.driver_id = s.driver_id AND s.incident_date BETWEEN dr.effective_date AND dr.expiry_date
    LEFT JOIN dbo.DIM_INCIDENT_TYPE it ON it.incident_type = s.incident_type
    WHERE s.incident_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.FACT_SAFETY_INCIDENT f WHERE f.incident_id = s.incident_id);
    SET @ins = @@ROWCOUNT;

    SET @rej = @src - @dup - @ins;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_SAFETY_INCIDENTS', N'FACT_SAFETY_INCIDENT', @src, @ins, @rej;
END;
GO

-- ------------------------------------------------------------------------------
-- 7.6 FACT_TRUCK_UTILIZATION (Periodic Snapshot: 1 xe / 1 tháng)
-- month_date_key = ngày đầu tháng (YYYYMM01)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_FACT_TRUCK_UTILIZATION @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @dup INT, @ins INT, @rej INT;

    SELECT dbo.fn_Clean(truck_id)                                         AS truck_id,
           DATEFROMPARTS(YEAR(TRY_CAST(dbo.fn_Clean(month) AS DATE)), MONTH(TRY_CAST(dbo.fn_Clean(month) AS DATE)), 1) AS month_date,
           TRY_CAST(TRY_CAST(dbo.fn_Clean(trips_completed) AS DECIMAL(12,2)) AS INT)    AS trips_completed,
           TRY_CAST(dbo.fn_Clean(total_miles) AS DECIMAL(12,1))           AS total_miles,
           TRY_CAST(dbo.fn_Clean(total_revenue) AS DECIMAL(18,2))         AS total_revenue,
           TRY_CAST(dbo.fn_Clean(average_mpg) AS DECIMAL(6,2))            AS average_mpg,
           TRY_CAST(TRY_CAST(dbo.fn_Clean(maintenance_events) AS DECIMAL(12,2)) AS INT) AS maintenance_events,
           TRY_CAST(dbo.fn_Clean(maintenance_cost) AS DECIMAL(12,2))      AS maintenance_cost,
           dbo.fn_ToHours(downtime_hours)                                 AS downtime_hours,
           TRY_CAST(dbo.fn_Clean(utilization_rate) AS DECIMAL(6,4))       AS utilization_rate
    INTO #s
    FROM dbo.STG_TRUCK_UTILIZATION_METRICS;
    SET @src = @@ROWCOUNT;

    SELECT @dup = COUNT(*) FROM #s s
    WHERE EXISTS (SELECT 1 FROM dbo.FACT_TRUCK_UTILIZATION f
                  WHERE f.truck_id = s.truck_id AND f.month_date_key = dbo.fn_DateKey(s.month_date));

    INSERT INTO dbo.FACT_TRUCK_UTILIZATION (month_date_key, truck_key, truck_id, trips_completed, total_miles, total_revenue,
                                            average_mpg, maintenance_events, maintenance_cost, downtime_hours, utilization_rate)
    SELECT dt.date_key, ISNULL(tk.truck_key, 0), s.truck_id, s.trips_completed, s.total_miles, s.total_revenue,
           s.average_mpg, s.maintenance_events, s.maintenance_cost, s.downtime_hours, s.utilization_rate
    FROM #s s
    JOIN dbo.DIM_DATE dt       ON dt.full_date = s.month_date
    LEFT JOIN dbo.DIM_TRUCK tk ON tk.truck_id = s.truck_id AND s.month_date BETWEEN tk.effective_date AND tk.expiry_date
    WHERE s.truck_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.FACT_TRUCK_UTILIZATION f
                      WHERE f.truck_id = s.truck_id AND f.month_date_key = dt.date_key);
    SET @ins = @@ROWCOUNT;

    SET @rej = @src - @dup - @ins;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_TRUCK_UTILIZATION_METRICS', N'FACT_TRUCK_UTILIZATION', @src, @ins, @rej;
END;
GO

-- ------------------------------------------------------------------------------
-- 7.7 FACT_DRIVER_MONTHLY_METRICS (Periodic Snapshot: 1 tài xế / 1 tháng)
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Load_FACT_DRIVER_MONTHLY_METRICS @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(), @src INT, @dup INT, @ins INT, @rej INT;

    SELECT dbo.fn_Clean(driver_id)                                         AS driver_id,
           DATEFROMPARTS(YEAR(TRY_CAST(dbo.fn_Clean(month) AS DATE)), MONTH(TRY_CAST(dbo.fn_Clean(month) AS DATE)), 1) AS month_date,
           TRY_CAST(TRY_CAST(dbo.fn_Clean(trips_completed) AS DECIMAL(12,2)) AS INT) AS trips_completed,
           TRY_CAST(dbo.fn_Clean(total_miles) AS DECIMAL(12,1))            AS total_miles,
           TRY_CAST(dbo.fn_Clean(total_revenue) AS DECIMAL(18,2))          AS total_revenue,
           TRY_CAST(dbo.fn_Clean(average_mpg) AS DECIMAL(6,2))             AS average_mpg,
           TRY_CAST(dbo.fn_Clean(total_fuel_gallons) AS DECIMAL(12,2))     AS total_fuel_gallons,
           TRY_CAST(dbo.fn_Clean(on_time_delivery_rate) AS DECIMAL(6,4))   AS on_time_delivery_rate,
           dbo.fn_ToHours(average_idle_hours)                              AS average_idle_hours
    INTO #s
    FROM dbo.STG_DRIVER_MONTHLY_METRICS;
    SET @src = @@ROWCOUNT;

    SELECT @dup = COUNT(*) FROM #s s
    WHERE EXISTS (SELECT 1 FROM dbo.FACT_DRIVER_MONTHLY_METRICS f
                  WHERE f.driver_id = s.driver_id AND f.month_date_key = dbo.fn_DateKey(s.month_date));

    INSERT INTO dbo.FACT_DRIVER_MONTHLY_METRICS (month_date_key, driver_key, driver_id, trips_completed, total_miles,
                                                 total_revenue, average_mpg, total_fuel_gallons, on_time_delivery_rate,
                                                 average_idle_hours, driver_month_record_count)
    SELECT dt.date_key, ISNULL(dr.driver_key, 0), s.driver_id, s.trips_completed, s.total_miles,
           s.total_revenue, s.average_mpg, s.total_fuel_gallons, s.on_time_delivery_rate,
           s.average_idle_hours, 1
    FROM #s s
    JOIN dbo.DIM_DATE dt        ON dt.full_date = s.month_date
    LEFT JOIN dbo.DIM_DRIVER dr ON dr.driver_id = s.driver_id AND s.month_date BETWEEN dr.effective_date AND dr.expiry_date
    WHERE s.driver_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.FACT_DRIVER_MONTHLY_METRICS f
                      WHERE f.driver_id = s.driver_id AND f.month_date_key = dt.date_key);
    SET @ins = @@ROWCOUNT;

    SET @rej = @src - @dup - @ins;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_DRIVER_MONTHLY_METRICS', N'FACT_DRIVER_MONTHLY_METRICS', @src, @ins, @rej;
END;
GO

PRINT N'07. Đã tạo các thủ tục nạp Fact.';
GO
