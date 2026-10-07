-- ==============================================================================
-- 00. TẠO DATABASE + HẠ TẦNG ETL (ETL LOG, DATA QUALITY, HÀM CHUẨN HÓA)
-- Dự án: Kho dữ liệu vận tải J.B. Hunt (Logistics Operations 2022–2024)
-- Theo báo cáo: mục 4.7.2.6 (ETL Log – Bảng 4.7.3) và 4.7.2.3 (Transform)
-- ==============================================================================
USE [master];
GO

IF DB_ID(N'Logistics_DW') IS NULL
    CREATE DATABASE [Logistics_DW];
GO

USE [Logistics_DW];
GO

-- ------------------------------------------------------------------------------
-- 1. ETL_BATCH: mỗi lần chạy ETL là một batch.
--    Trạng thái theo 4.7.2.6: STARTED → EXTRACTED → VALIDATED → TRANSFORMED
--                              → LOADED → VERIFIED  (hoặc FAILED)
-- ------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.ETL_BATCH', N'U') IS NULL
CREATE TABLE dbo.ETL_BATCH (
    batch_id          INT IDENTITY(1,1) PRIMARY KEY,
    batch_start_date  DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    batch_end_date    DATETIME2(0)  NULL,
    load_date         DATE          NOT NULL,
    data_path         NVARCHAR(400) NULL,
    status            VARCHAR(20)   NOT NULL DEFAULT 'STARTED',
    run_user          NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    error_message     NVARCHAR(4000) NULL
);
GO

-- ------------------------------------------------------------------------------
-- 2. ETL_LOG: đúng 14 trường của Bảng 4.7.3
-- ------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.ETL_LOG', N'U') IS NULL
CREATE TABLE dbo.ETL_LOG (
    log_id             INT IDENTITY(1,1) PRIMARY KEY,
    batch_id           INT           NOT NULL REFERENCES dbo.ETL_BATCH(batch_id),
    start_time         DATETIME2(3)  NOT NULL,
    end_time           DATETIME2(3)  NULL,
    source_table       NVARCHAR(128) NULL,
    target_table       NVARCHAR(128) NULL,
    source_row_count   INT           NULL,
    loaded_row_count   INT           NULL,
    rejected_row_count INT           NULL,
    error_count        INT           NOT NULL DEFAULT 0,
    status             VARCHAR(10)   NOT NULL,          -- SUCCESS / FAILED
    error_message      NVARCHAR(4000) NULL,
    run_user           NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    batch_start_date   DATETIME2(0)  NULL,
    batch_end_date     DATETIME2(0)  NULL
);
GO

-- ------------------------------------------------------------------------------
-- 3. DQ_CHECK_RESULT: kết quả kiểm tra chất lượng dữ liệu tại Staging
-- ------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DQ_CHECK_RESULT', N'U') IS NULL
CREATE TABLE dbo.DQ_CHECK_RESULT (
    dq_id         INT IDENTITY(1,1) PRIMARY KEY,
    batch_id      INT           NOT NULL REFERENCES dbo.ETL_BATCH(batch_id),
    check_time    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    check_group   NVARCHAR(50)  NOT NULL,   -- Missing / Duplicate / Domain / Outlier / Orphan / Format
    table_name    NVARCHAR(128) NOT NULL,
    column_name   NVARCHAR(128) NULL,
    rule_desc     NVARCHAR(400) NOT NULL,
    failed_rows   INT           NOT NULL,
    severity      VARCHAR(10)   NOT NULL,   -- CRITICAL (dừng ETL) / WARNING (chỉ ghi nhận)
    action_taken  NVARCHAR(400) NULL
);
GO

-- ------------------------------------------------------------------------------
-- 4. HÀM CHUẨN HÓA KIỂU DỮ LIỆU (4.7.2.3 a)
-- ------------------------------------------------------------------------------

-- Chuỗi rỗng / 'NaT' / 'nan' / 'None' (sinh ra bởi pandas) → NULL
CREATE OR ALTER FUNCTION dbo.fn_Clean (@v NVARCHAR(400))
RETURNS NVARCHAR(400)
WITH SCHEMABINDING
AS
BEGIN
    SET @v = LTRIM(RTRIM(@v));
    RETURN CASE WHEN @v IS NULL OR @v IN (N'', N'NaT', N'nan', N'NaN', N'None', N'NULL') THEN NULL ELSE @v END;
END;
GO

-- 'True'/'False'/'1'/'0' → BIT
CREATE OR ALTER FUNCTION dbo.fn_ToBit (@v NVARCHAR(10))
RETURNS BIT
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE UPPER(LTRIM(RTRIM(@v)))
               WHEN N'TRUE' THEN 1 WHEN N'1' THEN 1 WHEN N'YES' THEN 1
               WHEN N'FALSE' THEN 0 WHEN N'0' THEN 0 WHEN N'NO' THEN 0
           END;
END;
GO

-- Các cột *_hours (idle_time_hours, downtime_hours) bị pandas đổi nhầm sang datetime
-- dạng '1970-01-01 00:00:00.000000003' (số giờ nằm ở phần nano giây, đã mất phần thập phân).
-- Hàm đọc được cả 2 dạng: số thường (3.5) và dạng lỗi trên (→ 3).
CREATE OR ALTER FUNCTION dbo.fn_ToHours (@v NVARCHAR(50))
RETURNS DECIMAL(10,2)
WITH SCHEMABINDING
AS
BEGIN
    SET @v = LTRIM(RTRIM(@v));
    IF @v LIKE N'1970-01-01 00:00:00.%'
        RETURN TRY_CAST(SUBSTRING(@v, CHARINDEX(N'.', @v) + 1, 20) AS DECIMAL(20,0));
    RETURN TRY_CAST(@v AS DECIMAL(10,2));
END;
GO

-- DATE → date_key dạng YYYYMMDD
CREATE OR ALTER FUNCTION dbo.fn_DateKey (@d DATE)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    RETURN YEAR(@d) * 10000 + MONTH(@d) * 100 + DAY(@d);
END;
GO

-- ------------------------------------------------------------------------------
-- 5. THỦ TỤC GHI LOG
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_Write_Log
    @BatchId       INT,
    @StartTime     DATETIME2(3),
    @SourceTable   NVARCHAR(128),
    @TargetTable   NVARCHAR(128),
    @SourceRows    INT,
    @LoadedRows    INT,
    @RejectedRows  INT = NULL,
    @Status        VARCHAR(10) = 'SUCCESS',
    @ErrorMessage  NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.ETL_LOG (batch_id, start_time, end_time, source_table, target_table,
                             source_row_count, loaded_row_count, rejected_row_count,
                             error_count, status, error_message, batch_start_date)
    SELECT @BatchId, @StartTime, SYSDATETIME(), @SourceTable, @TargetTable,
           @SourceRows, @LoadedRows, ISNULL(@RejectedRows, 0),
           CASE WHEN @Status = 'FAILED' THEN 1 ELSE 0 END, @Status, @ErrorMessage,
           b.batch_start_date
    FROM dbo.ETL_BATCH b
    WHERE b.batch_id = @BatchId;
END;
GO

PRINT N'00. Đã tạo database Logistics_DW và hạ tầng ETL.';
GO
