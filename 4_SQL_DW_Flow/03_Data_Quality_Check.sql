-- ==============================================================================
-- 03. DATA QUALITY CHECK TẠI STAGING (mục 4.7.2.1 & 4.7.2.3 b–e)
-- Kết quả ghi vào DQ_CHECK_RESULT.
--   CRITICAL : thiếu/trùng Business Key (phá vỡ grain) → DỪNG ETL
--   WARNING  : thiếu FK, FK mồ côi, sai miền giá trị, ngoại lai, sai công thức
--              → chỉ ghi nhận; FK thiếu được gán Unknown Member (key = 0),
--                ngoại lai KHÔNG bị xóa (4.7.2.3 e)
-- ==============================================================================
USE [Logistics_DW];
GO

-- Đếm ngoại lai theo IQR [Q1 − 1,5×IQR ; Q3 + 1,5×IQR] cho một cột số
CREATE OR ALTER PROCEDURE dbo.usp_DQ_Outlier
    @BatchId INT, @Table SYSNAME, @Column SYSNAME
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX) = N'
    ;WITH v AS (
        SELECT TRY_CAST(' + QUOTENAME(@Column) + N' AS FLOAT) AS x FROM dbo.' + QUOTENAME(@Table) + N'
    ), q AS (
        SELECT x,
               PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY x) OVER () AS q1,
               PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY x) OVER () AS q3
        FROM v WHERE x IS NOT NULL
    )
    INSERT INTO dbo.DQ_CHECK_RESULT (batch_id, check_group, table_name, column_name, rule_desc, failed_rows, severity, action_taken)
    SELECT @BatchId, N''Outlier'', @Table, @Column, N''Ngoài khoảng IQR [Q1-1.5*IQR; Q3+1.5*IQR]'',
           COUNT(CASE WHEN x < q1 - 1.5 * (q3 - q1) OR x > q3 + 1.5 * (q3 - q1) THEN 1 END),
           ''WARNING'', N''Giữ lại – không xóa khi chưa có bằng chứng là lỗi''
    FROM q;';
    EXEC sp_executesql @sql, N'@BatchId INT, @Table SYSNAME, @Column SYSNAME', @BatchId, @Table, @Column;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Data_Quality_Check
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME();

    DELETE FROM dbo.DQ_CHECK_RESULT WHERE batch_id = @BatchId;

    INSERT INTO dbo.DQ_CHECK_RESULT (batch_id, check_group, table_name, column_name, rule_desc, failed_rows, severity, action_taken)
    SELECT @BatchId, g, t, c, r, n, s, a
    FROM (VALUES
    -- ---------------- 1. Business Key thiếu (CRITICAL) ----------------
     (N'Missing', N'STG_DRIVERS', N'driver_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_DRIVERS WHERE dbo.fn_Clean(driver_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_TRUCKS', N'truck_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_TRUCKS WHERE dbo.fn_Clean(truck_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_TRAILERS', N'trailer_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_TRAILERS WHERE dbo.fn_Clean(trailer_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_CUSTOMERS', N'customer_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_CUSTOMERS WHERE dbo.fn_Clean(customer_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_FACILITIES', N'facility_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_FACILITIES WHERE dbo.fn_Clean(facility_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_ROUTES', N'route_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_ROUTES WHERE dbo.fn_Clean(route_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_TRIPS', N'trip_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_TRIPS WHERE dbo.fn_Clean(trip_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_FUEL_PURCHASES', N'fuel_purchase_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_FUEL_PURCHASES WHERE dbo.fn_Clean(fuel_purchase_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_MAINTENANCE_RECORDS', N'maintenance_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_MAINTENANCE_RECORDS WHERE dbo.fn_Clean(maintenance_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_DELIVERY_EVENTS', N'event_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_DELIVERY_EVENTS WHERE dbo.fn_Clean(event_id) IS NULL), 'CRITICAL', N'Dừng ETL')
    ,(N'Missing', N'STG_SAFETY_INCIDENTS', N'incident_id', N'Business Key bị thiếu', (SELECT COUNT(*) FROM dbo.STG_SAFETY_INCIDENTS WHERE dbo.fn_Clean(incident_id) IS NULL), 'CRITICAL', N'Dừng ETL')

    -- ---------------- 2. Trùng Business Key / grain (CRITICAL) ----------------
    ,(N'Duplicate', N'STG_DRIVERS', N'driver_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT driver_id) FROM dbo.STG_DRIVERS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_TRUCKS', N'truck_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT truck_id) FROM dbo.STG_TRUCKS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_TRAILERS', N'trailer_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT trailer_id) FROM dbo.STG_TRAILERS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_CUSTOMERS', N'customer_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM dbo.STG_CUSTOMERS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_FACILITIES', N'facility_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT facility_id) FROM dbo.STG_FACILITIES), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_ROUTES', N'route_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT route_id) FROM dbo.STG_ROUTES), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_TRIPS', N'trip_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT trip_id) FROM dbo.STG_TRIPS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_FUEL_PURCHASES', N'fuel_purchase_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT fuel_purchase_id) FROM dbo.STG_FUEL_PURCHASES), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_MAINTENANCE_RECORDS', N'maintenance_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT maintenance_id) FROM dbo.STG_MAINTENANCE_RECORDS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_DELIVERY_EVENTS', N'event_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT event_id) FROM dbo.STG_DELIVERY_EVENTS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_SAFETY_INCIDENTS', N'incident_id', N'Trùng Business Key', (SELECT COUNT(*) - COUNT(DISTINCT incident_id) FROM dbo.STG_SAFETY_INCIDENTS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_DRIVER_MONTHLY_METRICS', N'driver_id, month', N'Trùng grain tài xế–tháng', (SELECT COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT driver_id, month FROM dbo.STG_DRIVER_MONTHLY_METRICS) d) FROM dbo.STG_DRIVER_MONTHLY_METRICS), 'CRITICAL', N'Dừng ETL')
    ,(N'Duplicate', N'STG_TRUCK_UTILIZATION_METRICS', N'truck_id, month', N'Trùng grain xe–tháng', (SELECT COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT truck_id, month FROM dbo.STG_TRUCK_UTILIZATION_METRICS) d) FROM dbo.STG_TRUCK_UTILIZATION_METRICS), 'CRITICAL', N'Dừng ETL')

    -- ---------------- 3. Khóa ngoại bị thiếu (WARNING) ----------------
    ,(N'Missing', N'STG_TRIPS', N'driver_id', N'Thiếu mã tài xế', (SELECT COUNT(*) FROM dbo.STG_TRIPS WHERE dbo.fn_Clean(driver_id) IS NULL), 'WARNING', N'Gán Unknown Member (driver_key = 0)')
    ,(N'Missing', N'STG_TRIPS', N'truck_id', N'Thiếu mã xe tải', (SELECT COUNT(*) FROM dbo.STG_TRIPS WHERE dbo.fn_Clean(truck_id) IS NULL), 'WARNING', N'Gán Unknown Member (truck_key = 0)')
    ,(N'Missing', N'STG_TRIPS', N'trailer_id', N'Thiếu mã xe moóc', (SELECT COUNT(*) FROM dbo.STG_TRIPS WHERE dbo.fn_Clean(trailer_id) IS NULL), 'WARNING', N'Gán Unknown Member (trailer_key = 0)')
    ,(N'Missing', N'STG_FUEL_PURCHASES', N'truck_id', N'Thiếu mã xe tải', (SELECT COUNT(*) FROM dbo.STG_FUEL_PURCHASES WHERE dbo.fn_Clean(truck_id) IS NULL), 'WARNING', N'Gán Unknown Member (truck_key = 0)')
    ,(N'Missing', N'STG_FUEL_PURCHASES', N'driver_id', N'Thiếu mã tài xế', (SELECT COUNT(*) FROM dbo.STG_FUEL_PURCHASES WHERE dbo.fn_Clean(driver_id) IS NULL), 'WARNING', N'Gán Unknown Member (driver_key = 0)')
    ,(N'Missing', N'STG_SAFETY_INCIDENTS', N'truck_id', N'Thiếu mã xe tải', (SELECT COUNT(*) FROM dbo.STG_SAFETY_INCIDENTS WHERE dbo.fn_Clean(truck_id) IS NULL), 'WARNING', N'Gán Unknown Member (truck_key = 0)')
    ,(N'Missing', N'STG_SAFETY_INCIDENTS', N'driver_id', N'Thiếu mã tài xế', (SELECT COUNT(*) FROM dbo.STG_SAFETY_INCIDENTS WHERE dbo.fn_Clean(driver_id) IS NULL), 'WARNING', N'Gán Unknown Member (driver_key = 0)')
    ,(N'Missing', N'STG_DRIVERS', N'termination_date', N'Không có ngày nghỉ việc (tài xế còn làm việc)', (SELECT COUNT(*) FROM dbo.STG_DRIVERS WHERE dbo.fn_Clean(termination_date) IS NULL), 'WARNING', N'Giữ NULL – có ý nghĩa nghiệp vụ')

    -- ---------------- 4. Khóa ngoại mồ côi (WARNING) ----------------
    ,(N'Orphan', N'STG_TRIPS', N'driver_id', N'driver_id không có trong STG_DRIVERS', (SELECT COUNT(*) FROM dbo.STG_TRIPS s WHERE dbo.fn_Clean(s.driver_id) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.STG_DRIVERS d WHERE d.driver_id = s.driver_id)), 'WARNING', N'Gán Unknown Member')
    ,(N'Orphan', N'STG_TRIPS', N'truck_id', N'truck_id không có trong STG_TRUCKS', (SELECT COUNT(*) FROM dbo.STG_TRIPS s WHERE dbo.fn_Clean(s.truck_id) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.STG_TRUCKS d WHERE d.truck_id = s.truck_id)), 'WARNING', N'Gán Unknown Member')
    ,(N'Orphan', N'STG_TRIPS', N'trailer_id', N'trailer_id không có trong STG_TRAILERS', (SELECT COUNT(*) FROM dbo.STG_TRIPS s WHERE dbo.fn_Clean(s.trailer_id) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.STG_TRAILERS d WHERE d.trailer_id = s.trailer_id)), 'WARNING', N'Gán Unknown Member')
    ,(N'Orphan', N'STG_LOADS', N'customer_id', N'customer_id không có trong STG_CUSTOMERS', (SELECT COUNT(*) FROM dbo.STG_LOADS s WHERE NOT EXISTS (SELECT 1 FROM dbo.STG_CUSTOMERS d WHERE d.customer_id = s.customer_id)), 'WARNING', N'Ghi nhận')
    ,(N'Orphan', N'STG_LOADS', N'route_id', N'route_id không có trong STG_ROUTES', (SELECT COUNT(*) FROM dbo.STG_LOADS s WHERE NOT EXISTS (SELECT 1 FROM dbo.STG_ROUTES d WHERE d.route_id = s.route_id)), 'WARNING', N'Gán Unknown Member')
    ,(N'Orphan', N'STG_DELIVERY_EVENTS', N'trip_id', N'trip_id không có trong STG_TRIPS', (SELECT COUNT(*) FROM dbo.STG_DELIVERY_EVENTS s WHERE NOT EXISTS (SELECT 1 FROM dbo.STG_TRIPS d WHERE d.trip_id = s.trip_id)), 'WARNING', N'trip_key = NULL')
    ,(N'Orphan', N'STG_DELIVERY_EVENTS', N'facility_id', N'facility_id không có trong STG_FACILITIES', (SELECT COUNT(*) FROM dbo.STG_DELIVERY_EVENTS s WHERE NOT EXISTS (SELECT 1 FROM dbo.STG_FACILITIES d WHERE d.facility_id = s.facility_id)), 'WARNING', N'Gán Unknown Member')
    ,(N'Orphan', N'STG_FUEL_PURCHASES', N'trip_id', N'trip_id không có trong STG_TRIPS', (SELECT COUNT(*) FROM dbo.STG_FUEL_PURCHASES s WHERE NOT EXISTS (SELECT 1 FROM dbo.STG_TRIPS d WHERE d.trip_id = s.trip_id)), 'WARNING', N'trip_key = NULL')
    ,(N'Orphan', N'STG_MAINTENANCE_RECORDS', N'facility_location', N'Thành phố bảo dưỡng không khớp cơ sở nào trong STG_FACILITIES', (SELECT COUNT(*) FROM dbo.STG_MAINTENANCE_RECORDS s WHERE NOT EXISTS (SELECT 1 FROM dbo.STG_FACILITIES d WHERE d.city = s.facility_location)), 'WARNING', N'Gán Unknown Member (facility_key = 0)')

    -- ---------------- 5. Định dạng ngày (WARNING – dòng sẽ bị từ chối khi nạp Fact) ----------------
    ,(N'Format', N'STG_TRIPS', N'dispatch_date', N'Không đọc được ngày', (SELECT COUNT(*) FROM dbo.STG_TRIPS WHERE TRY_CAST(dbo.fn_Clean(dispatch_date) AS DATE) IS NULL), 'WARNING', N'Từ chối dòng (rejected)')
    ,(N'Format', N'STG_DELIVERY_EVENTS', N'scheduled_datetime', N'Không đọc được ngày giờ', (SELECT COUNT(*) FROM dbo.STG_DELIVERY_EVENTS WHERE TRY_CAST(dbo.fn_Clean(scheduled_datetime) AS DATETIME2) IS NULL), 'WARNING', N'Từ chối dòng (rejected)')
    ,(N'Format', N'STG_FUEL_PURCHASES', N'purchase_date', N'Không đọc được ngày giờ', (SELECT COUNT(*) FROM dbo.STG_FUEL_PURCHASES WHERE TRY_CAST(dbo.fn_Clean(purchase_date) AS DATETIME2) IS NULL), 'WARNING', N'Từ chối dòng (rejected)')
    ,(N'Format', N'STG_MAINTENANCE_RECORDS', N'maintenance_date', N'Không đọc được ngày', (SELECT COUNT(*) FROM dbo.STG_MAINTENANCE_RECORDS WHERE TRY_CAST(dbo.fn_Clean(maintenance_date) AS DATE) IS NULL), 'WARNING', N'Từ chối dòng (rejected)')
    ,(N'Format', N'STG_SAFETY_INCIDENTS', N'incident_date', N'Không đọc được ngày giờ', (SELECT COUNT(*) FROM dbo.STG_SAFETY_INCIDENTS WHERE TRY_CAST(dbo.fn_Clean(incident_date) AS DATETIME2) IS NULL), 'WARNING', N'Từ chối dòng (rejected)')
    ,(N'Format', N'STG_TRIPS', N'idle_time_hours', N'Giá trị giờ bị lưu dạng datetime 1970-01-01 (mất phần thập phân)', (SELECT COUNT(*) FROM dbo.STG_TRIPS WHERE idle_time_hours LIKE N'1970-01-01%'), 'WARNING', N'Chuyển về số giờ nguyên bằng fn_ToHours')
    ,(N'Format', N'STG_MAINTENANCE_RECORDS', N'downtime_hours', N'Giá trị giờ bị lưu dạng datetime 1970-01-01 (mất phần thập phân)', (SELECT COUNT(*) FROM dbo.STG_MAINTENANCE_RECORDS WHERE downtime_hours LIKE N'1970-01-01%'), 'WARNING', N'Chuyển về số giờ nguyên bằng fn_ToHours')

    -- ---------------- 6. Miền giá trị (4.7.2.3 d) ----------------
    ,(N'Domain', N'STG_LOADS', N'revenue, weight_lbs, pieces', N'Giá trị âm', (SELECT COUNT(*) FROM dbo.STG_LOADS WHERE TRY_CAST(revenue AS FLOAT) < 0 OR TRY_CAST(weight_lbs AS FLOAT) < 0 OR TRY_CAST(pieces AS FLOAT) < 0), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_TRIPS', N'distance, duration, idle', N'Giá trị âm', (SELECT COUNT(*) FROM dbo.STG_TRIPS WHERE TRY_CAST(actual_distance_miles AS FLOAT) < 0 OR TRY_CAST(actual_duration_hours AS FLOAT) < 0 OR dbo.fn_ToHours(idle_time_hours) < 0), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_FUEL_PURCHASES', N'gallons, price, total_cost', N'Giá trị âm', (SELECT COUNT(*) FROM dbo.STG_FUEL_PURCHASES WHERE TRY_CAST(gallons AS FLOAT) < 0 OR TRY_CAST(price_per_gallon AS FLOAT) < 0 OR TRY_CAST(total_cost AS FLOAT) < 0), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_MAINTENANCE_RECORDS', N'labor/parts/total/downtime', N'Giá trị âm', (SELECT COUNT(*) FROM dbo.STG_MAINTENANCE_RECORDS WHERE TRY_CAST(labor_hours AS FLOAT) < 0 OR TRY_CAST(labor_cost AS FLOAT) < 0 OR TRY_CAST(parts_cost AS FLOAT) < 0 OR TRY_CAST(total_cost AS FLOAT) < 0 OR dbo.fn_ToHours(downtime_hours) < 0), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_SAFETY_INCIDENTS', N'damage, claim', N'Giá trị âm', (SELECT COUNT(*) FROM dbo.STG_SAFETY_INCIDENTS WHERE TRY_CAST(vehicle_damage_cost AS FLOAT) < 0 OR TRY_CAST(cargo_damage_cost AS FLOAT) < 0 OR TRY_CAST(claim_amount AS FLOAT) < 0), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_DRIVER_MONTHLY_METRICS', N'on_time_delivery_rate', N'Ngoài [0;1]', (SELECT COUNT(*) FROM dbo.STG_DRIVER_MONTHLY_METRICS WHERE TRY_CAST(on_time_delivery_rate AS FLOAT) NOT BETWEEN 0 AND 1), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_TRUCK_UTILIZATION_METRICS', N'utilization_rate', N'Ngoài [0;1]', (SELECT COUNT(*) FROM dbo.STG_TRUCK_UTILIZATION_METRICS WHERE TRY_CAST(utilization_rate AS FLOAT) NOT BETWEEN 0 AND 1), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_DRIVERS', N'years_experience', N'Ngoài [0;70]', (SELECT COUNT(*) FROM dbo.STG_DRIVERS WHERE TRY_CAST(years_experience AS FLOAT) NOT BETWEEN 0 AND 70), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_DRIVERS', N'termination_date', N'termination_date < hire_date', (SELECT COUNT(*) FROM dbo.STG_DRIVERS WHERE TRY_CAST(dbo.fn_Clean(termination_date) AS DATE) < TRY_CAST(hire_date AS DATE)), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_FACILITIES', N'latitude, longitude', N'Tọa độ không hợp lệ', (SELECT COUNT(*) FROM dbo.STG_FACILITIES WHERE TRY_CAST(latitude AS FLOAT) NOT BETWEEN -90 AND 90 OR TRY_CAST(longitude AS FLOAT) NOT BETWEEN -180 AND 180), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_TRUCKS', N'model_year', N'Ngoài [1900;2026]', (SELECT COUNT(*) FROM dbo.STG_TRUCKS WHERE TRY_CAST(model_year AS INT) NOT BETWEEN 1900 AND 2026), 'WARNING', N'Ghi nhận')
    ,(N'Domain', N'STG_TRAILERS', N'model_year', N'Ngoài [1900;2026]', (SELECT COUNT(*) FROM dbo.STG_TRAILERS WHERE TRY_CAST(model_year AS INT) NOT BETWEEN 1900 AND 2026), 'WARNING', N'Ghi nhận')

    -- ---------------- 7. Nhất quán công thức ----------------
    ,(N'Formula', N'STG_FUEL_PURCHASES', N'total_cost', N'|total_cost − gallons × price_per_gallon| > 0.01', (SELECT COUNT(*) FROM dbo.STG_FUEL_PURCHASES WHERE ABS(TRY_CAST(total_cost AS FLOAT) - TRY_CAST(gallons AS FLOAT) * TRY_CAST(price_per_gallon AS FLOAT)) > 0.01), 'WARNING', N'Ghi nhận')
    ,(N'Formula', N'STG_MAINTENANCE_RECORDS', N'total_cost', N'|total_cost − (labor_cost + parts_cost)| > 0.01', (SELECT COUNT(*) FROM dbo.STG_MAINTENANCE_RECORDS WHERE ABS(TRY_CAST(total_cost AS FLOAT) - TRY_CAST(labor_cost AS FLOAT) - TRY_CAST(parts_cost AS FLOAT)) > 0.01), 'WARNING', N'Ghi nhận')
    ) AS v(g, t, c, r, n, s, a);

    -- ---------------- 8. Ngoại lai IQR (4.7.2.3 e) ----------------
    EXEC dbo.usp_DQ_Outlier @BatchId, N'STG_LOADS',               N'revenue';
    EXEC dbo.usp_DQ_Outlier @BatchId, N'STG_TRIPS',               N'actual_distance_miles';
    EXEC dbo.usp_DQ_Outlier @BatchId, N'STG_TRIPS',               N'fuel_gallons_used';
    EXEC dbo.usp_DQ_Outlier @BatchId, N'STG_FUEL_PURCHASES',      N'total_cost';
    EXEC dbo.usp_DQ_Outlier @BatchId, N'STG_MAINTENANCE_RECORDS', N'total_cost';
    EXEC dbo.usp_DQ_Outlier @BatchId, N'STG_SAFETY_INCIDENTS',    N'claim_amount';
    EXEC dbo.usp_DQ_Outlier @BatchId, N'STG_DELIVERY_EVENTS',     N'detention_minutes';

    DECLARE @critical INT = (SELECT COUNT(*) FROM dbo.DQ_CHECK_RESULT
                             WHERE batch_id = @BatchId AND severity = 'CRITICAL' AND failed_rows > 0);
    DECLARE @checks INT = (SELECT COUNT(*) FROM dbo.DQ_CHECK_RESULT WHERE batch_id = @BatchId);

    IF @critical > 0
    BEGIN
        DECLARE @msg NVARCHAR(400) = CONCAT(N'Data Quality: ', @critical, N' lỗi CRITICAL – xem DQ_CHECK_RESULT, batch ', @BatchId);
        EXEC dbo.usp_Write_Log @BatchId, @t0, N'STAGING', N'DQ_CHECK_RESULT', @checks, @checks, NULL, 'FAILED', @msg;
        THROW 50001, @msg, 1;
    END;

    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STAGING', N'DQ_CHECK_RESULT', @checks, @checks;
END;
GO

PRINT N'03. Đã tạo thủ tục usp_Data_Quality_Check.';
GO
