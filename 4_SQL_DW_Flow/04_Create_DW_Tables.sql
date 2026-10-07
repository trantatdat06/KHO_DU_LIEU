-- ==============================================================================
-- 04. TẠO CẤU TRÚC KHO DỮ LIỆU – STAR SCHEMA / FACT CONSTELLATION (mục 4.4, 4.5, 4.6)
--   12 Dimension : DIM_DATE, DIM_TIME, DIM_DRIVER, DIM_TRUCK, DIM_TRAILER, DIM_CUSTOMER,
--                  DIM_ROUTE, DIM_LOAD, DIM_FACILITY, DIM_EVENT_TYPE,
--                  DIM_MAINTENANCE_TYPE, DIM_INCIDENT_TYPE
--   7 Fact       : FACT_TRIP, FACT_DELIVERY_EVENT, FACT_FUEL_PURCHASE, FACT_MAINTENANCE,
--                  FACT_SAFETY_INCIDENT, FACT_TRUCK_UTILIZATION, FACT_DRIVER_MONTHLY_METRICS
-- Quy ước kiểu: STRING → NVARCHAR, BOOLEAN → BIT
-- CẢNH BÁO: script này XÓA và tạo lại toàn bộ Dim/Fact (chỉ chạy khi khởi tạo).
-- ==============================================================================
USE [Logistics_DW];
GO

-- Xóa Fact trước (do khóa ngoại), sau đó Dimension
DROP TABLE IF EXISTS dbo.FACT_DELIVERY_EVENT, dbo.FACT_FUEL_PURCHASE, dbo.FACT_SAFETY_INCIDENT,
                     dbo.FACT_MAINTENANCE, dbo.FACT_TRUCK_UTILIZATION,
                     dbo.FACT_DRIVER_MONTHLY_METRICS, dbo.FACT_TRIP;
DROP TABLE IF EXISTS dbo.DIM_LOAD, dbo.DIM_DATE, dbo.DIM_TIME, dbo.DIM_DRIVER, dbo.DIM_TRUCK,
                     dbo.DIM_TRAILER, dbo.DIM_CUSTOMER, dbo.DIM_ROUTE, dbo.DIM_FACILITY,
                     dbo.DIM_EVENT_TYPE, dbo.DIM_MAINTENANCE_TYPE, dbo.DIM_INCIDENT_TYPE;
GO

-- ==============================================================================
-- PHẦN 1: DIMENSION
-- ==============================================================================

-- 4.4.2 DIM_DATE – SCD loại 0, grain: 1 ngày
CREATE TABLE dbo.DIM_DATE (
    date_key      INT          NOT NULL CONSTRAINT PK_DIM_DATE PRIMARY KEY,   -- YYYYMMDD
    full_date     DATE         NOT NULL UNIQUE,
    day_of_month  INT          NOT NULL,
    day_of_week   INT          NOT NULL,      -- 1 = Thứ Hai ... 7 = Chủ Nhật
    weekday_name  NVARCHAR(20) NOT NULL,
    day_of_year   INT          NOT NULL,
    week_of_year  INT          NOT NULL,      -- ISO week
    month_of_year INT          NOT NULL,
    month_name    NVARCHAR(20) NOT NULL,
    quarter       INT          NOT NULL,
    year          INT          NOT NULL,
    is_weekend    BIT          NOT NULL,
    is_holiday    BIT          NOT NULL       -- ngày lễ liên bang Hoa Kỳ
);

-- 4.4.3 DIM_TIME – SCD loại 0, grain: 1 phút
CREATE TABLE dbo.DIM_TIME (
    time_key         INT          NOT NULL CONSTRAINT PK_DIM_TIME PRIMARY KEY, -- HHMM
    full_time        TIME(0)      NOT NULL,
    hour             INT          NOT NULL,
    minute           INT          NOT NULL,
    second           INT          NOT NULL,
    hour_minute      CHAR(5)      NOT NULL,   -- HH:MM
    period_of_day    NVARCHAR(20) NOT NULL,
    shift            NVARCHAR(20) NOT NULL,
    is_peak_hour     BIT          NOT NULL,
    is_business_hour BIT          NOT NULL,
    minute_of_day    INT          NOT NULL
);

-- 4.4.4 DIM_DRIVER – SCD loại 2
CREATE TABLE dbo.DIM_DRIVER (
    driver_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_DRIVER PRIMARY KEY,
    driver_id         NVARCHAR(20)  NOT NULL,
    first_name        NVARCHAR(100) NULL,
    last_name         NVARCHAR(100) NULL,
    hire_date         DATE          NULL,
    termination_date  DATE          NULL,
    license_number    NVARCHAR(50)  NULL,
    license_state     NVARCHAR(10)  NULL,
    date_of_birth     DATE          NULL,
    home_terminal     NVARCHAR(100) NULL,
    employment_status NVARCHAR(50)  NULL,
    cdl_class         NVARCHAR(10)  NULL,
    years_experience  DECIMAL(5,1)  NULL,
    effective_date    DATE          NOT NULL,
    expiry_date       DATE          NOT NULL,
    is_current        BIT           NOT NULL
);
CREATE INDEX IX_DIM_DRIVER_BK ON dbo.DIM_DRIVER (driver_id, effective_date, expiry_date);

-- 4.4.5 DIM_TRUCK – SCD loại 2
CREATE TABLE dbo.DIM_TRUCK (
    truck_key             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_TRUCK PRIMARY KEY,
    truck_id              NVARCHAR(20)  NOT NULL,
    unit_number           NVARCHAR(20)  NULL,
    make                  NVARCHAR(50)  NULL,
    model_year            INT           NULL,
    vin                   NVARCHAR(30)  NULL,
    acquisition_date      DATE          NULL,
    acquisition_mileage   DECIMAL(12,1) NULL,
    fuel_type             NVARCHAR(20)  NULL,
    tank_capacity_gallons DECIMAL(8,1)  NULL,
    status                NVARCHAR(20)  NULL,
    home_terminal         NVARCHAR(100) NULL,
    effective_date        DATE          NOT NULL,
    expiry_date           DATE          NOT NULL,
    is_current            BIT           NOT NULL
);
CREATE INDEX IX_DIM_TRUCK_BK ON dbo.DIM_TRUCK (truck_id, effective_date, expiry_date);

-- 4.4.6 DIM_TRAILER – SCD loại 2
CREATE TABLE dbo.DIM_TRAILER (
    trailer_key      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_TRAILER PRIMARY KEY,
    trailer_id       NVARCHAR(20)  NOT NULL,
    trailer_number   NVARCHAR(20)  NULL,
    trailer_type     NVARCHAR(50)  NULL,
    length_feet      DECIMAL(5,1)  NULL,
    model_year       INT           NULL,
    vin              NVARCHAR(30)  NULL,
    acquisition_date DATE          NULL,
    status           NVARCHAR(20)  NULL,
    current_location NVARCHAR(100) NULL,
    effective_date   DATE          NOT NULL,
    expiry_date      DATE          NOT NULL,
    is_current       BIT           NOT NULL
);
CREATE INDEX IX_DIM_TRAILER_BK ON dbo.DIM_TRAILER (trailer_id, effective_date, expiry_date);

-- 4.4.7 DIM_CUSTOMER – SCD loại 2
CREATE TABLE dbo.DIM_CUSTOMER (
    customer_key             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_CUSTOMER PRIMARY KEY,
    customer_id              NVARCHAR(20)  NOT NULL,
    customer_name            NVARCHAR(200) NULL,
    customer_type            NVARCHAR(50)  NULL,
    credit_terms_days        INT           NULL,
    primary_freight_type     NVARCHAR(50)  NULL,
    account_status           NVARCHAR(20)  NULL,
    contract_start_date      DATE          NULL,
    annual_revenue_potential DECIMAL(18,2) NULL,
    effective_date           DATE          NOT NULL,
    expiry_date              DATE          NOT NULL,
    is_current               BIT           NOT NULL
);
CREATE INDEX IX_DIM_CUSTOMER_BK ON dbo.DIM_CUSTOMER (customer_id, effective_date, expiry_date);

-- 4.4.8 DIM_ROUTE – SCD loại 2
CREATE TABLE dbo.DIM_ROUTE (
    route_key              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_ROUTE PRIMARY KEY,
    route_id               NVARCHAR(20)  NOT NULL,
    origin_city            NVARCHAR(100) NULL,
    origin_state           NVARCHAR(10)  NULL,
    destination_city       NVARCHAR(100) NULL,
    destination_state      NVARCHAR(10)  NULL,
    typical_distance_miles DECIMAL(10,1) NULL,
    base_rate_per_mile     DECIMAL(10,4) NULL,
    fuel_surcharge_rate    DECIMAL(10,4) NULL,
    typical_transit_days   DECIMAL(5,1)  NULL,
    effective_date         DATE          NOT NULL,
    expiry_date            DATE          NOT NULL,
    is_current             BIT           NOT NULL
);
CREATE INDEX IX_DIM_ROUTE_BK ON dbo.DIM_ROUTE (route_id, effective_date, expiry_date);

-- 4.4.9 DIM_LOAD – SCD loại 2
CREATE TABLE dbo.DIM_LOAD (
    load_key            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_LOAD PRIMARY KEY,
    load_id             NVARCHAR(20)  NOT NULL,
    customer_id         NVARCHAR(20)  NULL,
    route_id            NVARCHAR(20)  NULL,
    load_date           DATE          NULL,
    load_type           NVARCHAR(50)  NULL,
    weight_lbs          DECIMAL(12,2) NULL,
    pieces              INT           NULL,
    revenue             DECIMAL(18,2) NULL,
    fuel_surcharge      DECIMAL(18,2) NULL,
    accessorial_charges DECIMAL(18,2) NULL,
    load_status         NVARCHAR(20)  NULL,
    booking_type        NVARCHAR(20)  NULL,
    effective_date      DATE          NOT NULL,
    expiry_date         DATE          NOT NULL,
    is_current          BIT           NOT NULL
);
CREATE INDEX IX_DIM_LOAD_BK ON dbo.DIM_LOAD (load_id, effective_date, expiry_date);

-- 4.4.10 DIM_FACILITY – SCD loại 2
CREATE TABLE dbo.DIM_FACILITY (
    facility_key    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_FACILITY PRIMARY KEY,
    facility_id     NVARCHAR(20)  NOT NULL,
    facility_name   NVARCHAR(200) NULL,
    facility_type   NVARCHAR(50)  NULL,
    city            NVARCHAR(100) NULL,
    state           NVARCHAR(10)  NULL,
    latitude        DECIMAL(9,6)  NULL,
    longitude       DECIMAL(9,6)  NULL,
    dock_doors      INT           NULL,
    operating_hours NVARCHAR(50)  NULL,
    effective_date  DATE          NOT NULL,
    expiry_date     DATE          NOT NULL,
    is_current      BIT           NOT NULL
);
CREATE INDEX IX_DIM_FACILITY_BK ON dbo.DIM_FACILITY (facility_id, effective_date, expiry_date);

-- 4.4.12 DIM_EVENT_TYPE – bổ sung bản ghi mới
CREATE TABLE dbo.DIM_EVENT_TYPE (
    event_type_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_EVENT_TYPE PRIMARY KEY,
    event_type     NVARCHAR(50) NOT NULL UNIQUE
);

-- 4.4.13 DIM_MAINTENANCE_TYPE – bổ sung bản ghi mới
CREATE TABLE dbo.DIM_MAINTENANCE_TYPE (
    maintenance_type_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_MAINTENANCE_TYPE PRIMARY KEY,
    maintenance_type     NVARCHAR(50) NOT NULL UNIQUE
);

-- 4.4.14 DIM_INCIDENT_TYPE – bổ sung bản ghi mới
CREATE TABLE dbo.DIM_INCIDENT_TYPE (
    incident_type_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_INCIDENT_TYPE PRIMARY KEY,
    incident_type     NVARCHAR(100) NOT NULL UNIQUE
);
GO

-- ==============================================================================
-- PHẦN 2: FACT
-- ==============================================================================

-- 4.5.1.1 FACT_TRIP – Transaction Fact, grain: 1 chuyến
CREATE TABLE dbo.FACT_TRIP (
    trip_key              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_TRIP PRIMARY KEY,
    dispatch_date_key     INT           NOT NULL CONSTRAINT FK_TRIP_DATE    REFERENCES dbo.DIM_DATE(date_key),
    load_key              INT           NOT NULL CONSTRAINT FK_TRIP_LOAD    REFERENCES dbo.DIM_LOAD(load_key),
    driver_key            INT           NOT NULL CONSTRAINT FK_TRIP_DRIVER  REFERENCES dbo.DIM_DRIVER(driver_key),
    truck_key             INT           NOT NULL CONSTRAINT FK_TRIP_TRUCK   REFERENCES dbo.DIM_TRUCK(truck_key),
    trailer_key           INT           NOT NULL CONSTRAINT FK_TRIP_TRAILER REFERENCES dbo.DIM_TRAILER(trailer_key),
    route_key             INT           NOT NULL CONSTRAINT FK_TRIP_ROUTE   REFERENCES dbo.DIM_ROUTE(route_key),
    trip_id               NVARCHAR(20)  NOT NULL CONSTRAINT UQ_FACT_TRIP_ID UNIQUE,   -- Degenerate Dimension
    trip_status           NVARCHAR(20)  NULL,
    actual_distance_miles DECIMAL(10,1) NULL,
    actual_duration_hours DECIMAL(10,2) NULL,
    fuel_gallons_used     DECIMAL(10,2) NULL,
    average_mpg           DECIMAL(6,2)  NULL,
    idle_time_hours       DECIMAL(10,2) NULL,
    trip_count            INT           NOT NULL DEFAULT 1
);

-- 4.5.1.2 FACT_DELIVERY_EVENT – Transaction Fact, grain: 1 sự kiện giao hàng
CREATE TABLE dbo.FACT_DELIVERY_EVENT (
    delivery_event_key BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_DELIVERY_EVENT PRIMARY KEY,
    scheduled_date_key INT           NOT NULL CONSTRAINT FK_DE_DATE     REFERENCES dbo.DIM_DATE(date_key),
    trip_key           BIGINT        NULL     CONSTRAINT FK_DE_TRIP     REFERENCES dbo.FACT_TRIP(trip_key),
    event_type_key     INT           NOT NULL CONSTRAINT FK_DE_EVTYPE   REFERENCES dbo.DIM_EVENT_TYPE(event_type_key),
    facility_key       INT           NOT NULL CONSTRAINT FK_DE_FACILITY REFERENCES dbo.DIM_FACILITY(facility_key),
    event_id           NVARCHAR(20)  NOT NULL CONSTRAINT UQ_FACT_DE_ID UNIQUE,
    load_id            NVARCHAR(20)  NULL,
    scheduled_datetime DATETIME2(0)  NULL,
    actual_datetime    DATETIME2(0)  NULL,
    location_city      NVARCHAR(100) NULL,
    location_state     NVARCHAR(10)  NULL,
    detention_minutes  DECIMAL(10,1) NULL,
    on_time_flag       BIT           NULL,
    event_count        INT           NOT NULL DEFAULT 1
);

-- 4.5.2.1 FACT_FUEL_PURCHASE – Transaction Fact, grain: 1 giao dịch mua nhiên liệu
CREATE TABLE dbo.FACT_FUEL_PURCHASE (
    fuel_purchase_key BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_FUEL_PURCHASE PRIMARY KEY,
    purchase_date_key INT           NOT NULL CONSTRAINT FK_FP_DATE   REFERENCES dbo.DIM_DATE(date_key),
    trip_key          BIGINT        NULL     CONSTRAINT FK_FP_TRIP   REFERENCES dbo.FACT_TRIP(trip_key),
    truck_key         INT           NOT NULL CONSTRAINT FK_FP_TRUCK  REFERENCES dbo.DIM_TRUCK(truck_key),
    driver_key        INT           NOT NULL CONSTRAINT FK_FP_DRIVER REFERENCES dbo.DIM_DRIVER(driver_key),
    fuel_purchase_id  NVARCHAR(20)  NOT NULL CONSTRAINT UQ_FACT_FP_ID UNIQUE,
    location_city     NVARCHAR(100) NULL,
    location_state    NVARCHAR(10)  NULL,
    gallons           DECIMAL(10,2) NULL,
    price_per_gallon  DECIMAL(10,3) NULL,
    total_cost        DECIMAL(12,2) NULL,
    fuel_card_number  NVARCHAR(20)  NULL,
    purchase_count    INT           NOT NULL DEFAULT 1
);

-- 4.5.3.1 FACT_MAINTENANCE – Transaction Fact, grain: 1 lần bảo dưỡng/sửa chữa
CREATE TABLE dbo.FACT_MAINTENANCE (
    maintenance_key      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_MAINTENANCE PRIMARY KEY,
    maintenance_date_key INT           NOT NULL CONSTRAINT FK_MT_DATE     REFERENCES dbo.DIM_DATE(date_key),
    truck_key            INT           NOT NULL CONSTRAINT FK_MT_TRUCK    REFERENCES dbo.DIM_TRUCK(truck_key),
    maintenance_type_key INT           NOT NULL CONSTRAINT FK_MT_TYPE     REFERENCES dbo.DIM_MAINTENANCE_TYPE(maintenance_type_key),
    facility_key         INT           NOT NULL CONSTRAINT FK_MT_FACILITY REFERENCES dbo.DIM_FACILITY(facility_key),
    maintenance_id       NVARCHAR(20)  NOT NULL CONSTRAINT UQ_FACT_MT_ID UNIQUE,
    odometer_reading     DECIMAL(12,1) NULL,
    labor_hours          DECIMAL(10,2) NULL,
    labor_cost           DECIMAL(12,2) NULL,
    parts_cost           DECIMAL(12,2) NULL,
    total_cost           DECIMAL(12,2) NULL,
    downtime_hours       DECIMAL(10,2) NULL,
    facility_location    NVARCHAR(100) NULL,
    service_description  NVARCHAR(400) NULL,
    maintenance_count    INT           NOT NULL DEFAULT 1
);

-- 4.5.3.2 FACT_TRUCK_UTILIZATION – Periodic Snapshot, grain: 1 xe / 1 tháng
CREATE TABLE dbo.FACT_TRUCK_UTILIZATION (
    utilization_key    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_TRUCK_UTILIZATION PRIMARY KEY,
    month_date_key     INT           NOT NULL CONSTRAINT FK_TU_DATE  REFERENCES dbo.DIM_DATE(date_key),
    truck_key          INT           NOT NULL CONSTRAINT FK_TU_TRUCK REFERENCES dbo.DIM_TRUCK(truck_key),
    truck_id           NVARCHAR(20)  NOT NULL,
    trips_completed    INT           NULL,
    total_miles        DECIMAL(12,1) NULL,
    total_revenue      DECIMAL(18,2) NULL,
    average_mpg        DECIMAL(6,2)  NULL,
    maintenance_events INT           NULL,
    maintenance_cost   DECIMAL(12,2) NULL,
    downtime_hours     DECIMAL(10,2) NULL,
    utilization_rate   DECIMAL(6,4)  NULL,
    CONSTRAINT UQ_FACT_TU_GRAIN UNIQUE (truck_id, month_date_key)
);

-- 4.5.4.1 FACT_DRIVER_MONTHLY_METRICS – Periodic Snapshot, grain: 1 tài xế / 1 tháng
CREATE TABLE dbo.FACT_DRIVER_MONTHLY_METRICS (
    driver_monthly_key        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_DRIVER_MONTHLY PRIMARY KEY,
    month_date_key            INT           NOT NULL CONSTRAINT FK_DM_DATE   REFERENCES dbo.DIM_DATE(date_key),
    driver_key                INT           NOT NULL CONSTRAINT FK_DM_DRIVER REFERENCES dbo.DIM_DRIVER(driver_key),
    driver_id                 NVARCHAR(20)  NOT NULL,
    trips_completed           INT           NULL,
    total_miles               DECIMAL(12,1) NULL,
    total_revenue             DECIMAL(18,2) NULL,
    average_mpg               DECIMAL(6,2)  NULL,
    total_fuel_gallons        DECIMAL(12,2) NULL,
    on_time_delivery_rate     DECIMAL(6,4)  NULL,
    average_idle_hours        DECIMAL(10,2) NULL,
    driver_month_record_count INT           NOT NULL DEFAULT 1,
    CONSTRAINT UQ_FACT_DM_GRAIN UNIQUE (driver_id, month_date_key)
);

-- 4.5.5.1 FACT_SAFETY_INCIDENT – Transaction Fact, grain: 1 sự cố
CREATE TABLE dbo.FACT_SAFETY_INCIDENT (
    incident_key        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_SAFETY_INCIDENT PRIMARY KEY,
    incident_date_key   INT           NOT NULL CONSTRAINT FK_SI_DATE   REFERENCES dbo.DIM_DATE(date_key),
    trip_key            BIGINT        NULL     CONSTRAINT FK_SI_TRIP   REFERENCES dbo.FACT_TRIP(trip_key),
    truck_key           INT           NOT NULL CONSTRAINT FK_SI_TRUCK  REFERENCES dbo.DIM_TRUCK(truck_key),
    driver_key          INT           NOT NULL CONSTRAINT FK_SI_DRIVER REFERENCES dbo.DIM_DRIVER(driver_key),
    incident_type_key   INT           NOT NULL CONSTRAINT FK_SI_TYPE   REFERENCES dbo.DIM_INCIDENT_TYPE(incident_type_key),
    incident_id         NVARCHAR(20)  NOT NULL CONSTRAINT UQ_FACT_SI_ID UNIQUE,
    location_city       NVARCHAR(100) NULL,
    location_state      NVARCHAR(10)  NULL,
    at_fault_flag       BIT           NULL,
    injury_flag         BIT           NULL,
    vehicle_damage_cost DECIMAL(12,2) NULL,
    cargo_damage_cost   DECIMAL(12,2) NULL,
    claim_amount        DECIMAL(12,2) NULL,
    preventable_flag    BIT           NULL,
    description         NVARCHAR(400) NULL,
    incident_count      INT           NOT NULL DEFAULT 1
);
GO

-- Index cho các khóa ngoại hay dùng khi phân tích
CREATE INDEX IX_FACT_TRIP_DATE    ON dbo.FACT_TRIP (dispatch_date_key);
CREATE INDEX IX_FACT_TRIP_DRIVER  ON dbo.FACT_TRIP (driver_key);
CREATE INDEX IX_FACT_TRIP_TRUCK   ON dbo.FACT_TRIP (truck_key);
CREATE INDEX IX_FACT_TRIP_ROUTE   ON dbo.FACT_TRIP (route_key);
CREATE INDEX IX_FACT_TRIP_LOAD    ON dbo.FACT_TRIP (load_key);
CREATE INDEX IX_FACT_DE_TRIP      ON dbo.FACT_DELIVERY_EVENT (trip_key);
CREATE INDEX IX_FACT_DE_FACILITY  ON dbo.FACT_DELIVERY_EVENT (facility_key);
CREATE INDEX IX_FACT_DE_DATE      ON dbo.FACT_DELIVERY_EVENT (scheduled_date_key);
CREATE INDEX IX_FACT_FP_TRUCK     ON dbo.FACT_FUEL_PURCHASE (truck_key);
CREATE INDEX IX_FACT_FP_TRIP      ON dbo.FACT_FUEL_PURCHASE (trip_key);
CREATE INDEX IX_FACT_FP_DATE      ON dbo.FACT_FUEL_PURCHASE (purchase_date_key);
CREATE INDEX IX_FACT_MT_TRUCK     ON dbo.FACT_MAINTENANCE (truck_key);
GO

PRINT N'04. Đã tạo 12 Dimension và 7 Fact.';
GO
