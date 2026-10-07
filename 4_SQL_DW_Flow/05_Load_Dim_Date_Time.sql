-- ==============================================================================
-- 05. NẠP DIM_DATE VÀ DIM_TIME (mục 4.4.2, 4.4.3 – SCD loại 0)
-- Sinh bằng SQL, chỉ bổ sung các ngày/phút còn thiếu (chạy lại không bị trùng).
-- ==============================================================================
USE [Logistics_DW];
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_DATE
    @BatchId   INT,
    @StartDate DATE = '2015-01-01',
    @EndDate   DATE = '2030-12-31'      -- dữ liệu 2022–2024 + khoảng dự phòng
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME(),
            @days INT = DATEDIFF(DAY, @StartDate, @EndDate) + 1;

    ;WITH n AS (
        SELECT TOP (@days) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
        FROM sys.all_columns a CROSS JOIN sys.all_columns b
    ), d AS (
        SELECT DATEADD(DAY, i, @StartDate) AS dt FROM n
    ), a AS (
        SELECT dt,
               (DATEDIFF(DAY, '19000101', dt) % 7) + 1 AS dow,      -- 1 = Thứ Hai (không phụ thuộc DATEFIRST)
               (DAY(dt) - 1) / 7 + 1                  AS nth_in_month,
               DAY(EOMONTH(dt))                        AS days_in_month
        FROM d
    )
    INSERT INTO dbo.DIM_DATE (date_key, full_date, day_of_month, day_of_week, weekday_name, day_of_year,
                              week_of_year, month_of_year, month_name, quarter, year, is_weekend, is_holiday)
    SELECT dbo.fn_DateKey(dt), dt, DAY(dt), dow,
           CHOOSE(dow, N'Monday', N'Tuesday', N'Wednesday', N'Thursday', N'Friday', N'Saturday', N'Sunday'),
           DATEPART(DAYOFYEAR, dt),
           DATEPART(ISO_WEEK, dt),
           MONTH(dt),
           CHOOSE(MONTH(dt), N'January', N'February', N'March', N'April', N'May', N'June',
                  N'July', N'August', N'September', N'October', N'November', N'December'),
           DATEPART(QUARTER, dt),
           YEAR(dt),
           CASE WHEN dow IN (6, 7) THEN 1 ELSE 0 END,
           CASE -- Ngày lễ liên bang Hoa Kỳ (doanh nghiệp hoạt động tại Mỹ)
                WHEN MONTH(dt) = 1  AND DAY(dt) = 1                       THEN 1  -- New Year's Day
                WHEN MONTH(dt) = 1  AND dow = 1 AND nth_in_month = 3      THEN 1  -- Martin Luther King Jr. Day
                WHEN MONTH(dt) = 2  AND dow = 1 AND nth_in_month = 3      THEN 1  -- Presidents' Day
                WHEN MONTH(dt) = 5  AND dow = 1 AND DAY(dt) + 7 > days_in_month THEN 1  -- Memorial Day
                WHEN MONTH(dt) = 6  AND DAY(dt) = 19 AND YEAR(dt) >= 2021 THEN 1  -- Juneteenth
                WHEN MONTH(dt) = 7  AND DAY(dt) = 4                       THEN 1  -- Independence Day
                WHEN MONTH(dt) = 9  AND dow = 1 AND nth_in_month = 1      THEN 1  -- Labor Day
                WHEN MONTH(dt) = 10 AND dow = 1 AND nth_in_month = 2      THEN 1  -- Columbus Day
                WHEN MONTH(dt) = 11 AND DAY(dt) = 11                      THEN 1  -- Veterans Day
                WHEN MONTH(dt) = 11 AND dow = 4 AND nth_in_month = 4      THEN 1  -- Thanksgiving
                WHEN MONTH(dt) = 12 AND DAY(dt) = 25                      THEN 1  -- Christmas
                ELSE 0
           END
    FROM a
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_DATE x WHERE x.full_date = a.dt);

    DECLARE @ins INT = @@ROWCOUNT;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'(generated)', N'DIM_DATE', @days, @ins;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_DIM_TIME
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2(3) = SYSDATETIME();

    ;WITH n AS (
        SELECT TOP (1440) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS m
        FROM sys.all_columns
    ), t AS (
        SELECT m, m / 60 AS hh, m % 60 AS mi FROM n
    )
    INSERT INTO dbo.DIM_TIME (time_key, full_time, hour, minute, second, hour_minute, period_of_day,
                              shift, is_peak_hour, is_business_hour, minute_of_day)
    SELECT hh * 100 + mi,
           TIMEFROMPARTS(hh, mi, 0, 0, 0),
           hh, mi, 0,
           RIGHT('0' + CAST(hh AS VARCHAR(2)), 2) + ':' + RIGHT('0' + CAST(mi AS VARCHAR(2)), 2),
           CASE WHEN hh < 6  THEN N'Early Morning'
                WHEN hh < 12 THEN N'Morning'
                WHEN hh < 18 THEN N'Afternoon'
                ELSE N'Evening' END,
           CASE WHEN hh >= 6  AND hh < 14 THEN N'Shift 1 (06-14)'
                WHEN hh >= 14 AND hh < 22 THEN N'Shift 2 (14-22)'
                ELSE N'Shift 3 (22-06)' END,
           CASE WHEN hh IN (7, 8, 16, 17) THEN 1 ELSE 0 END,      -- giờ cao điểm giao thông
           CASE WHEN hh >= 8 AND hh < 17 THEN 1 ELSE 0 END,       -- giờ hành chính 08:00–17:00
           m
    FROM t
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_TIME x WHERE x.time_key = t.hh * 100 + t.mi);

    DECLARE @ins INT = @@ROWCOUNT;
    EXEC dbo.usp_Write_Log @BatchId, @t0, N'(generated)', N'DIM_TIME', 1440, @ins;
END;
GO

PRINT N'05. Đã tạo thủ tục usp_Load_DIM_DATE, usp_Load_DIM_TIME.';
GO
