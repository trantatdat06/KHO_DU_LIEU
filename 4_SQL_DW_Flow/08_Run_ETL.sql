-- ==============================================================================
-- 08. THỦ TỤC ĐIỀU PHỐI ETL (mục 4.7.1.4 Trình tự tích hợp, 4.7.2.6 xử lý lỗi)
--
--   14 CSV → EXTRACT → STAGING → DATA QUALITY CHECK → LOAD DIM_DATE/DIM_TIME
--          → LOAD DIMENSION (SCD2) → LOAD DIM_LOAD → LOAD TRANSACTION FACT
--          → LOAD SNAPSHOT FACT → (09) DATA INTEGRITY TESTING → (10) BUSINESS QUERY
--
-- Trạng thái batch: STARTED → EXTRACTED → VALIDATED → TRANSFORMED → LOADED
--                   (→ VERIFIED khi chạy 09_Data_Integrity_Tests.sql đạt) / FAILED
-- Khi lỗi: ghi ETL_LOG + ETL_BATCH = FAILED; do mọi bước đều idempotent,
--          sửa lỗi rồi chạy lại toàn bộ thủ tục là an toàn.
-- ==============================================================================
USE [Logistics_DW];
GO

CREATE OR ALTER PROCEDURE dbo.usp_Run_ETL
    @DataPath NVARCHAR(400),
    @LoadDate DATE = NULL            -- ngày hiệu lực cho phiên bản SCD2 mới (mặc định: hôm nay)
AS
BEGIN
    SET NOCOUNT ON;
    SET @LoadDate = ISNULL(@LoadDate, CAST(GETDATE() AS DATE));

    DECLARE @BatchId INT, @t0 DATETIME2(3) = SYSDATETIME(), @step NVARCHAR(100);

    INSERT INTO dbo.ETL_BATCH (load_date, data_path) VALUES (@LoadDate, @DataPath);
    SET @BatchId = SCOPE_IDENTITY();
    PRINT CONCAT(N'== ETL batch ', @BatchId, N' bắt đầu lúc ', CONVERT(NVARCHAR(30), SYSDATETIME(), 120));

    BEGIN TRY
        -- Bước 1: Extract → Staging
        SET @step = N'1. Extract to Staging';  PRINT @step;
        EXEC dbo.usp_Extract_To_Staging @BatchId, @DataPath;
        UPDATE dbo.ETL_BATCH SET status = 'EXTRACTED' WHERE batch_id = @BatchId;

        -- Data Quality Check
        SET @step = N'2. Data Quality Check';  PRINT @step;
        EXEC dbo.usp_Data_Quality_Check @BatchId;
        UPDATE dbo.ETL_BATCH SET status = 'VALIDATED' WHERE batch_id = @BatchId;

        -- Bước 2: DIM_DATE, DIM_TIME
        SET @step = N'3. Load DIM_DATE, DIM_TIME';  PRINT @step;
        EXEC dbo.usp_Load_DIM_DATE @BatchId;
        EXEC dbo.usp_Load_DIM_TIME @BatchId;

        -- Bước 3: các Dimension còn lại (SCD2 + Unknown Member)
        SET @step = N'4. Load Dimensions';  PRINT @step;
        EXEC dbo.usp_Load_Unknown_Members;
        EXEC dbo.usp_Load_DIM_DRIVER   @BatchId, @LoadDate;
        EXEC dbo.usp_Load_DIM_TRUCK    @BatchId, @LoadDate;
        EXEC dbo.usp_Load_DIM_TRAILER  @BatchId, @LoadDate;
        EXEC dbo.usp_Load_DIM_CUSTOMER @BatchId, @LoadDate;
        EXEC dbo.usp_Load_DIM_FACILITY @BatchId, @LoadDate;
        EXEC dbo.usp_Load_DIM_ROUTE    @BatchId, @LoadDate;
        EXEC dbo.usp_Load_Type_Dimensions @BatchId;

        -- Bước 4: DIM_LOAD (sau DIM_CUSTOMER, DIM_ROUTE)
        SET @step = N'5. Load DIM_LOAD';  PRINT @step;
        EXEC dbo.usp_Load_DIM_LOAD @BatchId, @LoadDate;
        UPDATE dbo.ETL_BATCH SET status = 'TRANSFORMED' WHERE batch_id = @BatchId;

        -- Bước 5: Transaction Fact (FACT_TRIP trước vì các Fact khác tham chiếu trip_key)
        SET @step = N'6. Load Transaction Facts';  PRINT @step;
        EXEC dbo.usp_Load_FACT_TRIP            @BatchId;
        EXEC dbo.usp_Load_FACT_DELIVERY_EVENT  @BatchId;
        EXEC dbo.usp_Load_FACT_FUEL_PURCHASE   @BatchId;
        EXEC dbo.usp_Load_FACT_MAINTENANCE     @BatchId;
        EXEC dbo.usp_Load_FACT_SAFETY_INCIDENT @BatchId;

        -- Bước 6: Periodic Snapshot Fact
        SET @step = N'7. Load Snapshot Facts';  PRINT @step;
        EXEC dbo.usp_Load_FACT_TRUCK_UTILIZATION      @BatchId;
        EXEC dbo.usp_Load_FACT_DRIVER_MONTHLY_METRICS @BatchId;

        UPDATE dbo.ETL_BATCH SET status = 'LOADED', batch_end_date = SYSDATETIME() WHERE batch_id = @BatchId;
        UPDATE dbo.ETL_LOG SET batch_end_date = SYSDATETIME() WHERE batch_id = @BatchId;
        PRINT CONCAT(N'== ETL batch ', @BatchId, N' hoàn tất. Chạy tiếp 09_Data_Integrity_Tests.sql để kiểm thử.');
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(4000) = CONCAT(@step, N' | ', ERROR_PROCEDURE(), N' | ', ERROR_MESSAGE());
        IF @@TRANCOUNT > 0 ROLLBACK;
        UPDATE dbo.ETL_BATCH SET status = 'FAILED', batch_end_date = SYSDATETIME(), error_message = @err
        WHERE batch_id = @BatchId;
        EXEC dbo.usp_Write_Log @BatchId, @t0, NULL, N'usp_Run_ETL', NULL, 0, NULL, 'FAILED', @err;
        UPDATE dbo.ETL_LOG SET batch_end_date = SYSDATETIME() WHERE batch_id = @BatchId;
        THROW;
    END CATCH;

    -- Tóm tắt batch
    SELECT target_table, source_row_count, loaded_row_count, rejected_row_count, status,
           DATEDIFF(MILLISECOND, start_time, end_time) AS duration_ms
    FROM dbo.ETL_LOG WHERE batch_id = @BatchId ORDER BY log_id;
END;
GO

-- ==============================================================================
-- CHẠY ETL – sửa đường dẫn cho đúng máy của bạn
-- ==============================================================================
EXEC dbo.usp_Run_ETL @DataPath = N'D:\0Project\Start\Kho Dữ liệu\3_Transformed_Data\';
GO

-- Xem kết quả Data Quality của batch gần nhất
SELECT check_group, table_name, column_name, rule_desc, failed_rows, severity, action_taken
FROM dbo.DQ_CHECK_RESULT
WHERE batch_id = (SELECT MAX(batch_id) FROM dbo.ETL_BATCH)
ORDER BY CASE severity WHEN 'CRITICAL' THEN 0 ELSE 1 END, failed_rows DESC;
GO
