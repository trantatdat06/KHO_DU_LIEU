-- ==============================================================================
-- 09. KIỂM THỬ TÍNH TOÀN VẸN DỮ LIỆU SAU ETL (mục 4.7.3 – Bảng 4.7.4)
-- Mỗi kiểm thử trả về 1 dòng: actual_value so với expected_value → PASS / FAIL.
-- Nếu tất cả PASS → batch gần nhất chuyển trạng thái VERIFIED.
-- ==============================================================================
USE [Logistics_DW];
GO
SET NOCOUNT ON;

DROP TABLE IF EXISTS #T;
CREATE TABLE #T (
    test_no        INT IDENTITY(1,1),
    criterion      NVARCHAR(50),
    test_name      NVARCHAR(300),
    actual_value   DECIMAL(38,2),
    expected_value DECIMAL(38,2)
);

-- ------------------------------------------------------------------------------
-- 1. SỐ BẢN GHI: Staging = Fact (4.7.3.1)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'1. Số bản ghi', N'FACT_TRIP = STG_TRIPS',                                   (SELECT COUNT(*) FROM dbo.FACT_TRIP),                   (SELECT COUNT(*) FROM dbo.STG_TRIPS))
,(N'1. Số bản ghi', N'FACT_DELIVERY_EVENT = STG_DELIVERY_EVENTS',               (SELECT COUNT(*) FROM dbo.FACT_DELIVERY_EVENT),         (SELECT COUNT(*) FROM dbo.STG_DELIVERY_EVENTS))
,(N'1. Số bản ghi', N'FACT_FUEL_PURCHASE = STG_FUEL_PURCHASES',                 (SELECT COUNT(*) FROM dbo.FACT_FUEL_PURCHASE),          (SELECT COUNT(*) FROM dbo.STG_FUEL_PURCHASES))
,(N'1. Số bản ghi', N'FACT_MAINTENANCE = STG_MAINTENANCE_RECORDS',              (SELECT COUNT(*) FROM dbo.FACT_MAINTENANCE),            (SELECT COUNT(*) FROM dbo.STG_MAINTENANCE_RECORDS))
,(N'1. Số bản ghi', N'FACT_SAFETY_INCIDENT = STG_SAFETY_INCIDENTS',             (SELECT COUNT(*) FROM dbo.FACT_SAFETY_INCIDENT),        (SELECT COUNT(*) FROM dbo.STG_SAFETY_INCIDENTS))
,(N'1. Số bản ghi', N'FACT_DRIVER_MONTHLY_METRICS = STG_DRIVER_MONTHLY_METRICS',(SELECT COUNT(*) FROM dbo.FACT_DRIVER_MONTHLY_METRICS), (SELECT COUNT(*) FROM dbo.STG_DRIVER_MONTHLY_METRICS))
,(N'1. Số bản ghi', N'FACT_TRUCK_UTILIZATION = STG_TRUCK_UTILIZATION_METRICS', (SELECT COUNT(*) FROM dbo.FACT_TRUCK_UTILIZATION),      (SELECT COUNT(*) FROM dbo.STG_TRUCK_UTILIZATION_METRICS))
-- Dimension SCD2: số Business Key (không tính Unknown Member)
,(N'1. Số bản ghi', N'DIM_DRIVER: số driver_id = STG_DRIVERS',       (SELECT COUNT(DISTINCT driver_id)   FROM dbo.DIM_DRIVER   WHERE driver_key   <> 0), (SELECT COUNT(DISTINCT driver_id)   FROM dbo.STG_DRIVERS))
,(N'1. Số bản ghi', N'DIM_TRUCK: số truck_id = STG_TRUCKS',          (SELECT COUNT(DISTINCT truck_id)    FROM dbo.DIM_TRUCK    WHERE truck_key    <> 0), (SELECT COUNT(DISTINCT truck_id)    FROM dbo.STG_TRUCKS))
,(N'1. Số bản ghi', N'DIM_TRAILER: số trailer_id = STG_TRAILERS',    (SELECT COUNT(DISTINCT trailer_id)  FROM dbo.DIM_TRAILER  WHERE trailer_key  <> 0), (SELECT COUNT(DISTINCT trailer_id)  FROM dbo.STG_TRAILERS))
,(N'1. Số bản ghi', N'DIM_CUSTOMER: số customer_id = STG_CUSTOMERS', (SELECT COUNT(DISTINCT customer_id) FROM dbo.DIM_CUSTOMER WHERE customer_key <> 0), (SELECT COUNT(DISTINCT customer_id) FROM dbo.STG_CUSTOMERS))
,(N'1. Số bản ghi', N'DIM_ROUTE: số route_id = STG_ROUTES',          (SELECT COUNT(DISTINCT route_id)    FROM dbo.DIM_ROUTE    WHERE route_key    <> 0), (SELECT COUNT(DISTINCT route_id)    FROM dbo.STG_ROUTES))
,(N'1. Số bản ghi', N'DIM_FACILITY: số facility_id = STG_FACILITIES',(SELECT COUNT(DISTINCT facility_id) FROM dbo.DIM_FACILITY WHERE facility_key <> 0), (SELECT COUNT(DISTINCT facility_id) FROM dbo.STG_FACILITIES))
,(N'1. Số bản ghi', N'DIM_LOAD: số load_id = STG_LOADS',             (SELECT COUNT(DISTINCT load_id)     FROM dbo.DIM_LOAD     WHERE load_key     <> 0), (SELECT COUNT(DISTINCT load_id)     FROM dbo.STG_LOADS));

-- ------------------------------------------------------------------------------
-- 2. KHÓA CHÍNH: không trùng, không NULL (4.7.3.2)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'2. Khóa chính', N'DIM_DRIVER.driver_key trùng/NULL',     (SELECT COUNT(*) - COUNT(DISTINCT driver_key)   FROM dbo.DIM_DRIVER),   0)
,(N'2. Khóa chính', N'DIM_TRUCK.truck_key trùng/NULL',       (SELECT COUNT(*) - COUNT(DISTINCT truck_key)    FROM dbo.DIM_TRUCK),    0)
,(N'2. Khóa chính', N'DIM_TRAILER.trailer_key trùng/NULL',   (SELECT COUNT(*) - COUNT(DISTINCT trailer_key)  FROM dbo.DIM_TRAILER),  0)
,(N'2. Khóa chính', N'DIM_CUSTOMER.customer_key trùng/NULL', (SELECT COUNT(*) - COUNT(DISTINCT customer_key) FROM dbo.DIM_CUSTOMER), 0)
,(N'2. Khóa chính', N'DIM_ROUTE.route_key trùng/NULL',       (SELECT COUNT(*) - COUNT(DISTINCT route_key)    FROM dbo.DIM_ROUTE),    0)
,(N'2. Khóa chính', N'DIM_LOAD.load_key trùng/NULL',         (SELECT COUNT(*) - COUNT(DISTINCT load_key)     FROM dbo.DIM_LOAD),     0)
,(N'2. Khóa chính', N'FACT_TRIP.trip_key trùng/NULL',        (SELECT COUNT(*) - COUNT(DISTINCT trip_key)     FROM dbo.FACT_TRIP),    0);

-- ------------------------------------------------------------------------------
-- 3–4. BUSINESS KEY & SCD2: mỗi Business Key đúng 1 phiên bản is_current = 1 (4.7.3.3)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'4. SCD Type 2', N'DIM_DRIVER: BK có >1 phiên bản hiện tại',   (SELECT COUNT(*) FROM (SELECT driver_id   FROM dbo.DIM_DRIVER   WHERE is_current = 1 GROUP BY driver_id   HAVING COUNT(*) > 1) x), 0)
,(N'4. SCD Type 2', N'DIM_TRUCK: BK có >1 phiên bản hiện tại',    (SELECT COUNT(*) FROM (SELECT truck_id    FROM dbo.DIM_TRUCK    WHERE is_current = 1 GROUP BY truck_id    HAVING COUNT(*) > 1) x), 0)
,(N'4. SCD Type 2', N'DIM_TRAILER: BK có >1 phiên bản hiện tại',  (SELECT COUNT(*) FROM (SELECT trailer_id  FROM dbo.DIM_TRAILER  WHERE is_current = 1 GROUP BY trailer_id  HAVING COUNT(*) > 1) x), 0)
,(N'4. SCD Type 2', N'DIM_CUSTOMER: BK có >1 phiên bản hiện tại', (SELECT COUNT(*) FROM (SELECT customer_id FROM dbo.DIM_CUSTOMER WHERE is_current = 1 GROUP BY customer_id HAVING COUNT(*) > 1) x), 0)
,(N'4. SCD Type 2', N'DIM_ROUTE: BK có >1 phiên bản hiện tại',    (SELECT COUNT(*) FROM (SELECT route_id    FROM dbo.DIM_ROUTE    WHERE is_current = 1 GROUP BY route_id    HAVING COUNT(*) > 1) x), 0)
,(N'4. SCD Type 2', N'DIM_LOAD: BK có >1 phiên bản hiện tại',     (SELECT COUNT(*) FROM (SELECT load_id     FROM dbo.DIM_LOAD     WHERE is_current = 1 GROUP BY load_id     HAVING COUNT(*) > 1) x), 0)
,(N'4. SCD Type 2', N'DIM_FACILITY: BK có >1 phiên bản hiện tại', (SELECT COUNT(*) FROM (SELECT facility_id FROM dbo.DIM_FACILITY WHERE is_current = 1 GROUP BY facility_id HAVING COUNT(*) > 1) x), 0)
,(N'4. SCD Type 2', N'Phiên bản có expiry_date < effective_date',
    (SELECT (SELECT COUNT(*) FROM dbo.DIM_DRIVER WHERE expiry_date < effective_date) + (SELECT COUNT(*) FROM dbo.DIM_TRUCK WHERE expiry_date < effective_date)
          + (SELECT COUNT(*) FROM dbo.DIM_TRAILER WHERE expiry_date < effective_date) + (SELECT COUNT(*) FROM dbo.DIM_CUSTOMER WHERE expiry_date < effective_date)
          + (SELECT COUNT(*) FROM dbo.DIM_ROUTE WHERE expiry_date < effective_date) + (SELECT COUNT(*) FROM dbo.DIM_LOAD WHERE expiry_date < effective_date)
          + (SELECT COUNT(*) FROM dbo.DIM_FACILITY WHERE expiry_date < effective_date)), 0);

-- ------------------------------------------------------------------------------
-- 5. KHÓA NGOẠI: không có bản ghi mồ côi (4.7.3.4)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'5. Khóa ngoại', N'FACT_TRIP → DIM_DRIVER mồ côi',  (SELECT COUNT(*) FROM dbo.FACT_TRIP f LEFT JOIN dbo.DIM_DRIVER d  ON f.driver_key  = d.driver_key  WHERE d.driver_key  IS NULL), 0)
,(N'5. Khóa ngoại', N'FACT_TRIP → DIM_TRUCK mồ côi',   (SELECT COUNT(*) FROM dbo.FACT_TRIP f LEFT JOIN dbo.DIM_TRUCK d   ON f.truck_key   = d.truck_key   WHERE d.truck_key   IS NULL), 0)
,(N'5. Khóa ngoại', N'FACT_TRIP → DIM_TRAILER mồ côi', (SELECT COUNT(*) FROM dbo.FACT_TRIP f LEFT JOIN dbo.DIM_TRAILER d ON f.trailer_key = d.trailer_key WHERE d.trailer_key IS NULL), 0)
,(N'5. Khóa ngoại', N'FACT_TRIP → DIM_LOAD mồ côi',    (SELECT COUNT(*) FROM dbo.FACT_TRIP f LEFT JOIN dbo.DIM_LOAD d    ON f.load_key    = d.load_key    WHERE d.load_key    IS NULL), 0)
,(N'5. Khóa ngoại', N'FACT_TRIP → DIM_ROUTE mồ côi',   (SELECT COUNT(*) FROM dbo.FACT_TRIP f LEFT JOIN dbo.DIM_ROUTE d   ON f.route_key   = d.route_key   WHERE d.route_key   IS NULL), 0)
,(N'5. Khóa ngoại', N'FACT_TRIP → DIM_DATE mồ côi',    (SELECT COUNT(*) FROM dbo.FACT_TRIP f LEFT JOIN dbo.DIM_DATE d    ON f.dispatch_date_key = d.date_key WHERE d.date_key IS NULL), 0)
,(N'5. Khóa ngoại', N'FACT_DELIVERY_EVENT → FACT_TRIP không liên kết được', (SELECT COUNT(*) FROM dbo.FACT_DELIVERY_EVENT WHERE trip_key IS NULL), 0)
,(N'5. Khóa ngoại', N'FACT_FUEL_PURCHASE → FACT_TRIP không liên kết được',  (SELECT COUNT(*) FROM dbo.FACT_FUEL_PURCHASE  WHERE trip_key IS NULL), 0)
,(N'5. Khóa ngoại', N'FACT_SAFETY_INCIDENT → FACT_TRIP không liên kết được',(SELECT COUNT(*) FROM dbo.FACT_SAFETY_INCIDENT WHERE trip_key IS NULL), 0);

-- ------------------------------------------------------------------------------
-- 6. GRAIN: không trùng theo grain của từng Fact (4.7.3.5)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'6. Grain', N'FACT_TRIP trùng trip_id',                      (SELECT COUNT(*) - COUNT(DISTINCT trip_id)          FROM dbo.FACT_TRIP), 0)
,(N'6. Grain', N'FACT_DELIVERY_EVENT trùng event_id',           (SELECT COUNT(*) - COUNT(DISTINCT event_id)         FROM dbo.FACT_DELIVERY_EVENT), 0)
,(N'6. Grain', N'FACT_FUEL_PURCHASE trùng fuel_purchase_id',    (SELECT COUNT(*) - COUNT(DISTINCT fuel_purchase_id) FROM dbo.FACT_FUEL_PURCHASE), 0)
,(N'6. Grain', N'FACT_MAINTENANCE trùng maintenance_id',        (SELECT COUNT(*) - COUNT(DISTINCT maintenance_id)   FROM dbo.FACT_MAINTENANCE), 0)
,(N'6. Grain', N'FACT_SAFETY_INCIDENT trùng incident_id',       (SELECT COUNT(*) - COUNT(DISTINCT incident_id)      FROM dbo.FACT_SAFETY_INCIDENT), 0)
,(N'6. Grain', N'FACT_TRUCK_UTILIZATION trùng xe–tháng',        (SELECT COUNT(*) FROM (SELECT truck_id,  month_date_key FROM dbo.FACT_TRUCK_UTILIZATION      GROUP BY truck_id,  month_date_key HAVING COUNT(*) > 1) x), 0)
,(N'6. Grain', N'FACT_DRIVER_MONTHLY_METRICS trùng tài xế–tháng',(SELECT COUNT(*) FROM (SELECT driver_id, month_date_key FROM dbo.FACT_DRIVER_MONTHLY_METRICS GROUP BY driver_id, month_date_key HAVING COUNT(*) > 1) x), 0);

-- ------------------------------------------------------------------------------
-- 8. MIỀN GIÁ TRỊ (4.7.3.7)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'8. Domain', N'FACT_TRIP: measure âm',
    (SELECT COUNT(*) FROM dbo.FACT_TRIP WHERE actual_distance_miles < 0 OR actual_duration_hours < 0 OR fuel_gallons_used < 0 OR average_mpg < 0 OR idle_time_hours < 0 OR trip_count < 0), 0)
,(N'8. Domain', N'FACT_FUEL_PURCHASE: measure âm',
    (SELECT COUNT(*) FROM dbo.FACT_FUEL_PURCHASE WHERE gallons < 0 OR price_per_gallon < 0 OR total_cost < 0 OR purchase_count < 0), 0)
,(N'8. Domain', N'FACT_MAINTENANCE: measure âm',
    (SELECT COUNT(*) FROM dbo.FACT_MAINTENANCE WHERE odometer_reading < 0 OR labor_hours < 0 OR labor_cost < 0 OR parts_cost < 0 OR total_cost < 0 OR downtime_hours < 0 OR maintenance_count < 0), 0)
,(N'8. Domain', N'FACT_DRIVER_MONTHLY_METRICS: âm hoặc tỷ lệ ngoài [0;1]',
    (SELECT COUNT(*) FROM dbo.FACT_DRIVER_MONTHLY_METRICS WHERE trips_completed < 0 OR total_miles < 0 OR total_revenue < 0 OR average_mpg < 0 OR total_fuel_gallons < 0
            OR on_time_delivery_rate < 0 OR on_time_delivery_rate > 1 OR average_idle_hours < 0 OR driver_month_record_count < 0), 0)
,(N'8. Domain', N'FACT_TRUCK_UTILIZATION: âm hoặc tỷ lệ ngoài [0;1]',
    (SELECT COUNT(*) FROM dbo.FACT_TRUCK_UTILIZATION WHERE trips_completed < 0 OR total_miles < 0 OR total_revenue < 0 OR average_mpg < 0 OR maintenance_events < 0
            OR maintenance_cost < 0 OR downtime_hours < 0 OR utilization_rate < 0 OR utilization_rate > 1), 0)
,(N'8. Domain', N'FACT_SAFETY_INCIDENT: chi phí âm',
    (SELECT COUNT(*) FROM dbo.FACT_SAFETY_INCIDENT WHERE vehicle_damage_cost < 0 OR cargo_damage_cost < 0 OR claim_amount < 0), 0)
,(N'8. Domain', N'DIM_FACILITY: tọa độ không hợp lệ',
    (SELECT COUNT(*) FROM dbo.DIM_FACILITY WHERE latitude NOT BETWEEN -90 AND 90 OR longitude NOT BETWEEN -180 AND 180), 0)
,(N'8. Domain', N'DIM_DRIVER: termination_date < hire_date',
    (SELECT COUNT(*) FROM dbo.DIM_DRIVER WHERE termination_date < hire_date), 0);

-- ------------------------------------------------------------------------------
-- 9. ĐỐI CHIẾU TỔNG MEASURE NGUỒN – KHO (4.7.3.9)  (chênh lệch tuyệt đối)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'9. Measure', N'Σ fuel total_cost: |STG − FACT|',
    ABS((SELECT SUM(TRY_CAST(total_cost AS DECIMAL(18,2))) FROM dbo.STG_FUEL_PURCHASES) - (SELECT SUM(total_cost) FROM dbo.FACT_FUEL_PURCHASE)), 0)
,(N'9. Measure', N'Σ maintenance labor_cost: |STG − FACT|',
    ABS((SELECT SUM(TRY_CAST(labor_cost AS DECIMAL(18,2))) FROM dbo.STG_MAINTENANCE_RECORDS) - (SELECT SUM(labor_cost) FROM dbo.FACT_MAINTENANCE)), 0)
,(N'9. Measure', N'Σ maintenance parts_cost: |STG − FACT|',
    ABS((SELECT SUM(TRY_CAST(parts_cost AS DECIMAL(18,2))) FROM dbo.STG_MAINTENANCE_RECORDS) - (SELECT SUM(parts_cost) FROM dbo.FACT_MAINTENANCE)), 0)
,(N'9. Measure', N'Σ maintenance total_cost: |STG − FACT|',
    ABS((SELECT SUM(TRY_CAST(total_cost AS DECIMAL(18,2))) FROM dbo.STG_MAINTENANCE_RECORDS) - (SELECT SUM(total_cost) FROM dbo.FACT_MAINTENANCE)), 0)
,(N'9. Measure', N'Σ vehicle_damage_cost: |STG − FACT|',
    ABS((SELECT SUM(TRY_CAST(vehicle_damage_cost AS DECIMAL(18,2))) FROM dbo.STG_SAFETY_INCIDENTS) - (SELECT SUM(vehicle_damage_cost) FROM dbo.FACT_SAFETY_INCIDENT)), 0)
,(N'9. Measure', N'Σ cargo_damage_cost: |STG − FACT|',
    ABS((SELECT SUM(TRY_CAST(cargo_damage_cost AS DECIMAL(18,2))) FROM dbo.STG_SAFETY_INCIDENTS) - (SELECT SUM(cargo_damage_cost) FROM dbo.FACT_SAFETY_INCIDENT)), 0)
,(N'9. Measure', N'Σ claim_amount: |STG − FACT|',
    ABS((SELECT SUM(TRY_CAST(claim_amount AS DECIMAL(18,2))) FROM dbo.STG_SAFETY_INCIDENTS) - (SELECT SUM(claim_amount) FROM dbo.FACT_SAFETY_INCIDENT)), 0)
,(N'9. Measure', N'Σ actual_distance_miles: |STG − FACT|',
    ABS((SELECT SUM(TRY_CAST(actual_distance_miles AS DECIMAL(18,1))) FROM dbo.STG_TRIPS) - (SELECT SUM(actual_distance_miles) FROM dbo.FACT_TRIP)), 0)
,(N'9. Measure', N'Σ revenue: |STG_LOADS − DIM_LOAD (current)|',
    ABS((SELECT SUM(TRY_CAST(revenue AS DECIMAL(18,2))) FROM dbo.STG_LOADS) - (SELECT SUM(revenue) FROM dbo.DIM_LOAD WHERE is_current = 1)), 0);

-- ------------------------------------------------------------------------------
-- 10. CÔNG THỨC MEASURE DẪN XUẤT (4.7.3.8)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'10. Công thức', N'FACT_FUEL_PURCHASE: |total_cost − gallons × price| > 0.01',
    (SELECT COUNT(*) FROM dbo.FACT_FUEL_PURCHASE WHERE ABS(total_cost - gallons * price_per_gallon) > 0.01), 0)
,(N'10. Công thức', N'FACT_MAINTENANCE: |total_cost − (labor + parts)| > 0.01',
    (SELECT COUNT(*) FROM dbo.FACT_MAINTENANCE WHERE ABS(total_cost - (labor_cost + parts_cost)) > 0.01), 0);

-- ------------------------------------------------------------------------------
-- 11. DATE DIMENSION: mọi khóa ngày trong Fact đều tồn tại
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'11. Date Dimension', N'Khóa ngày Fact không có trong DIM_DATE',
    (SELECT COUNT(*) FROM (
        SELECT dispatch_date_key k FROM dbo.FACT_TRIP UNION ALL
        SELECT scheduled_date_key FROM dbo.FACT_DELIVERY_EVENT UNION ALL
        SELECT purchase_date_key FROM dbo.FACT_FUEL_PURCHASE UNION ALL
        SELECT maintenance_date_key FROM dbo.FACT_MAINTENANCE UNION ALL
        SELECT incident_date_key FROM dbo.FACT_SAFETY_INCIDENT UNION ALL
        SELECT month_date_key FROM dbo.FACT_TRUCK_UTILIZATION UNION ALL
        SELECT month_date_key FROM dbo.FACT_DRIVER_MONTHLY_METRICS) f
     WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_DATE d WHERE d.date_key = f.k)), 0);

-- ------------------------------------------------------------------------------
-- 12. SNAPSHOT: đối chiếu theo Business Key + Month (4.7.3.10)
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'12. Snapshot', N'FACT_DRIVER_MONTHLY_METRICS lệch với nguồn (driver_id + month)',
    (SELECT COUNT(*) FROM dbo.STG_DRIVER_MONTHLY_METRICS s
     LEFT JOIN dbo.FACT_DRIVER_MONTHLY_METRICS f
            ON f.driver_id = s.driver_id AND f.month_date_key = dbo.fn_DateKey(TRY_CAST(s.month AS DATE))
     WHERE f.driver_monthly_key IS NULL
        OR f.trips_completed <> TRY_CAST(s.trips_completed AS INT)
        OR f.total_revenue  <> TRY_CAST(s.total_revenue AS DECIMAL(18,2))
        OR f.total_miles    <> TRY_CAST(s.total_miles AS DECIMAL(12,1))), 0)
,(N'12. Snapshot', N'FACT_TRUCK_UTILIZATION lệch với nguồn (truck_id + month)',
    (SELECT COUNT(*) FROM dbo.STG_TRUCK_UTILIZATION_METRICS s
     LEFT JOIN dbo.FACT_TRUCK_UTILIZATION f
            ON f.truck_id = s.truck_id AND f.month_date_key = dbo.fn_DateKey(TRY_CAST(s.month AS DATE))
     WHERE f.utilization_key IS NULL
        OR f.trips_completed  <> TRY_CAST(s.trips_completed AS INT)
        OR f.total_revenue    <> TRY_CAST(s.total_revenue AS DECIMAL(18,2))
        OR f.maintenance_cost <> TRY_CAST(s.maintenance_cost AS DECIMAL(12,2))), 0);

-- ------------------------------------------------------------------------------
-- 14. ETL LOG: batch gần nhất không có bước FAILED
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'14. ETL Log', N'Số bước FAILED trong batch gần nhất',
    (SELECT COUNT(*) FROM dbo.ETL_LOG WHERE batch_id = (SELECT MAX(batch_id) FROM dbo.ETL_BATCH) AND status = 'FAILED'), 0);

-- ------------------------------------------------------------------------------
-- 15. TRUY VẾT: mọi dòng Fact giao dịch đều có Business Key nguồn
-- ------------------------------------------------------------------------------
INSERT #T (criterion, test_name, actual_value, expected_value) VALUES
 (N'15. Truy vết', N'Fact thiếu Degenerate Dimension (mã nguồn)',
    (SELECT (SELECT COUNT(*) FROM dbo.FACT_TRIP WHERE trip_id IS NULL)
          + (SELECT COUNT(*) FROM dbo.FACT_DELIVERY_EVENT WHERE event_id IS NULL)
          + (SELECT COUNT(*) FROM dbo.FACT_FUEL_PURCHASE WHERE fuel_purchase_id IS NULL)
          + (SELECT COUNT(*) FROM dbo.FACT_MAINTENANCE WHERE maintenance_id IS NULL)
          + (SELECT COUNT(*) FROM dbo.FACT_SAFETY_INCIDENT WHERE incident_id IS NULL)), 0);

-- ------------------------------------------------------------------------------
-- KẾT QUẢ
-- ------------------------------------------------------------------------------
SELECT test_no, criterion, test_name, actual_value, expected_value,
       CASE WHEN ISNULL(actual_value, -1) = expected_value THEN 'PASS' ELSE 'FAIL' END AS result
FROM #T
ORDER BY test_no;

-- Thông tin tham khảo: số dòng Fact gắn Unknown Member (key = 0) do nguồn thiếu khóa
SELECT N'FACT_TRIP' AS fact_table,
       SUM(CASE WHEN driver_key = 0 THEN 1 ELSE 0 END)  AS unknown_driver,
       SUM(CASE WHEN truck_key = 0 THEN 1 ELSE 0 END)   AS unknown_truck,
       SUM(CASE WHEN trailer_key = 0 THEN 1 ELSE 0 END) AS unknown_trailer
FROM dbo.FACT_TRIP
UNION ALL
SELECT N'FACT_FUEL_PURCHASE', SUM(CASE WHEN driver_key = 0 THEN 1 ELSE 0 END), SUM(CASE WHEN truck_key = 0 THEN 1 ELSE 0 END), NULL
FROM dbo.FACT_FUEL_PURCHASE
UNION ALL
SELECT N'FACT_SAFETY_INCIDENT', SUM(CASE WHEN driver_key = 0 THEN 1 ELSE 0 END), SUM(CASE WHEN truck_key = 0 THEN 1 ELSE 0 END), NULL
FROM dbo.FACT_SAFETY_INCIDENT;

-- Đánh dấu batch VERIFIED nếu toàn bộ kiểm thử đạt
DECLARE @fail INT = (SELECT COUNT(*) FROM #T WHERE ISNULL(actual_value, -1) <> expected_value);
DECLARE @last INT = (SELECT MAX(batch_id) FROM dbo.ETL_BATCH);
IF @fail = 0
BEGIN
    UPDATE dbo.ETL_BATCH SET status = 'VERIFIED' WHERE batch_id = @last AND status = 'LOADED';
    PRINT N'09. Tất cả kiểm thử PASS – batch ' + CAST(@last AS NVARCHAR(10)) + N' = VERIFIED.';
END
ELSE
    PRINT N'09. Có ' + CAST(@fail AS NVARCHAR(10)) + N' kiểm thử FAIL – xem cột result.';
GO
