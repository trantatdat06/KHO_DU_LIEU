-- ==============================================================================
-- 02. EXTRACT: NẠP CSV (3_Transformed_Data) VÀO STAGING (mục 4.7.2.1)
-- - Mỗi lần chạy: TRUNCATE Staging rồi BULK INSERT lại toàn bộ (full refresh)
-- - Ghi số dòng nạp được của từng bảng vào ETL_LOG
-- Lưu ý: tài khoản dịch vụ SQL Server cần quyền đọc thư mục dữ liệu.
-- ==============================================================================
USE [Logistics_DW];
GO

CREATE OR ALTER PROCEDURE dbo.usp_Extract_To_Staging
    @BatchId  INT,
    @DataPath NVARCHAR(400)          -- ví dụ: N'D:\0Project\Start\Kho Dữ liệu\3_Transformed_Data\'
AS
BEGIN
    SET NOCOUNT ON;

    IF RIGHT(@DataPath, 1) <> N'\' SET @DataPath += N'\';

    DECLARE @Files TABLE (seq INT IDENTITY, file_name NVARCHAR(200), stg_table NVARCHAR(128));
    INSERT INTO @Files (file_name, stg_table) VALUES
        (N'Dim_Driver.csv',            N'STG_DRIVERS'),
        (N'Dim_Truck.csv',             N'STG_TRUCKS'),
        (N'Dim_Trailer.csv',           N'STG_TRAILERS'),
        (N'Dim_Customer.csv',          N'STG_CUSTOMERS'),
        (N'Dim_Facility.csv',          N'STG_FACILITIES'),
        (N'Dim_Route.csv',             N'STG_ROUTES'),
        (N'Fact_Trips.csv',            N'STG_TRIPS'),
        (N'Fact_Fuel_Purchases.csv',   N'STG_FUEL_PURCHASES'),
        (N'Fact_Maintenance.csv',      N'STG_MAINTENANCE_RECORDS'),
        (N'Fact_Delivery_Events.csv',  N'STG_DELIVERY_EVENTS'),
        (N'Fact_Safety_Incidents.csv', N'STG_SAFETY_INCIDENTS'),
        (N'Agg_Driver_Monthly.csv',    N'STG_DRIVER_MONTHLY_METRICS'),
        (N'Agg_Truck_Monthly.csv',     N'STG_TRUCK_UTILIZATION_METRICS');

    DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @Files),
            @file NVARCHAR(200), @tbl NVARCHAR(128), @sql NVARCHAR(MAX),
            @rows INT, @t0 DATETIME2(3);

    WHILE @i <= @n
    BEGIN
        SELECT @file = file_name, @tbl = stg_table FROM @Files WHERE seq = @i;
        SET @t0 = SYSDATETIME();

        SET @sql = N'TRUNCATE TABLE dbo.' + QUOTENAME(@tbl) + N';
BULK INSERT dbo.' + QUOTENAME(@tbl) + N'
FROM ''' + REPLACE(@DataPath + @file, N'''', N'''''') + N'''
WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'',
      FIELDTERMINATOR = '','', ROWTERMINATOR = ''\n'', TABLOCK);
SELECT @rows = COUNT(*) FROM dbo.' + QUOTENAME(@tbl) + N';';

        BEGIN TRY
            EXEC sp_executesql @sql, N'@rows INT OUTPUT', @rows = @rows OUTPUT;
            EXEC dbo.usp_Write_Log @BatchId, @t0, @file, @tbl, @rows, @rows;
        END TRY
        BEGIN CATCH
            DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
            EXEC dbo.usp_Write_Log @BatchId, @t0, @file, @tbl, NULL, 0, NULL, 'FAILED', @msg;
            THROW;
        END CATCH;

        SET @i += 1;
    END;

    -- Tách STG_LOADS từ STG_TRIPS (mỗi load_id lấy 1 dòng)
    SET @t0 = SYSDATETIME();
    TRUNCATE TABLE dbo.STG_LOADS;
    INSERT INTO dbo.STG_LOADS (load_id, customer_id, route_id, load_date, load_type, weight_lbs,
                               pieces, revenue, fuel_surcharge, accessorial_charges, load_status, booking_type)
    SELECT load_id, customer_id, route_id, load_date, load_type, weight_lbs,
           pieces, revenue, fuel_surcharge, accessorial_charges, load_status, booking_type
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY load_id ORDER BY trip_id) AS rn
        FROM dbo.STG_TRIPS
        WHERE dbo.fn_Clean(load_id) IS NOT NULL
    ) x
    WHERE rn = 1;
    SET @rows = @@ROWCOUNT;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'STG_TRIPS', N'STG_LOADS', @rows, @rows;
END;
GO

PRINT N'02. Đã tạo thủ tục usp_Extract_To_Staging.';
GO
