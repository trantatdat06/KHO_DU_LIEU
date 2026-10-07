-- ==============================================================================
-- 01. TẠO 14 BẢNG STAGING (mục 4.7.2.2)
-- Staging giữ nguyên bản sao dữ liệu nguồn ở dạng chuỗi (NVARCHAR) để:
--   - BULK INSERT không bị lỗi khi gặp giá trị bẩn ('NaT', '', ...)
--   - kiểm tra chất lượng và truy vết trước khi chuyển kiểu ở bước Transform
--
-- Ánh xạ file nguồn (thư mục 3_Transformed_Data) → bảng Staging:
--   Dim_Driver.csv            → STG_DRIVERS
--   Dim_Truck.csv             → STG_TRUCKS
--   Dim_Trailer.csv           → STG_TRAILERS
--   Dim_Customer.csv          → STG_CUSTOMERS
--   Dim_Facility.csv          → STG_FACILITIES
--   Dim_Route.csv             → STG_ROUTES
--   Fact_Trips.csv            → STG_TRIPS   (trips đã merge loads)
--   (tách từ STG_TRIPS)       → STG_LOADS
--   Fact_Fuel_Purchases.csv   → STG_FUEL_PURCHASES
--   Fact_Maintenance.csv      → STG_MAINTENANCE_RECORDS
--   Fact_Delivery_Events.csv  → STG_DELIVERY_EVENTS
--   Fact_Safety_Incidents.csv → STG_SAFETY_INCIDENTS
--   Agg_Driver_Monthly.csv    → STG_DRIVER_MONTHLY_METRICS
--   Agg_Truck_Monthly.csv     → STG_TRUCK_UTILIZATION_METRICS
--   (Dim_Date.csv không dùng: DIM_DATE được sinh bằng SQL theo cấu trúc 4.4.2)
-- Thứ tự cột phải khớp đúng thứ tự cột trong file CSV.
-- ==============================================================================
USE [Logistics_DW];
GO

DROP TABLE IF EXISTS dbo.STG_DRIVERS, dbo.STG_TRUCKS, dbo.STG_TRAILERS, dbo.STG_CUSTOMERS,
                     dbo.STG_FACILITIES, dbo.STG_ROUTES, dbo.STG_LOADS, dbo.STG_TRIPS,
                     dbo.STG_FUEL_PURCHASES, dbo.STG_MAINTENANCE_RECORDS, dbo.STG_DELIVERY_EVENTS,
                     dbo.STG_SAFETY_INCIDENTS, dbo.STG_DRIVER_MONTHLY_METRICS,
                     dbo.STG_TRUCK_UTILIZATION_METRICS;
GO

-- ---------------------------- MASTER DATA ------------------------------------
CREATE TABLE dbo.STG_DRIVERS (
    driver_id          NVARCHAR(50),
    first_name         NVARCHAR(100),
    last_name          NVARCHAR(100),
    hire_date          NVARCHAR(50),
    termination_date   NVARCHAR(50),
    license_number     NVARCHAR(50),
    license_state      NVARCHAR(50),
    date_of_birth      NVARCHAR(50),
    home_terminal      NVARCHAR(100),
    employment_status  NVARCHAR(50),
    cdl_class          NVARCHAR(10),
    years_experience   NVARCHAR(50)
);

CREATE TABLE dbo.STG_TRUCKS (
    truck_id               NVARCHAR(50),
    unit_number            NVARCHAR(50),
    make                   NVARCHAR(100),
    model_year             NVARCHAR(50),
    vin                    NVARCHAR(50),
    acquisition_date       NVARCHAR(50),
    acquisition_mileage    NVARCHAR(50),
    fuel_type              NVARCHAR(50),
    tank_capacity_gallons  NVARCHAR(50),
    status                 NVARCHAR(50),
    home_terminal          NVARCHAR(100)
);

CREATE TABLE dbo.STG_TRAILERS (
    trailer_id        NVARCHAR(50),
    trailer_number    NVARCHAR(50),
    trailer_type      NVARCHAR(50),
    length_feet       NVARCHAR(50),
    model_year        NVARCHAR(50),
    vin               NVARCHAR(50),
    acquisition_date  NVARCHAR(50),
    status            NVARCHAR(50),
    current_location  NVARCHAR(100)
);

CREATE TABLE dbo.STG_CUSTOMERS (
    customer_id               NVARCHAR(50),
    customer_name             NVARCHAR(200),
    customer_type             NVARCHAR(50),
    credit_terms_days         NVARCHAR(50),
    primary_freight_type      NVARCHAR(100),
    account_status            NVARCHAR(50),
    contract_start_date       NVARCHAR(50),
    annual_revenue_potential  NVARCHAR(50)
);

CREATE TABLE dbo.STG_FACILITIES (
    facility_id      NVARCHAR(50),
    facility_name    NVARCHAR(200),
    facility_type    NVARCHAR(50),
    city             NVARCHAR(100),
    state            NVARCHAR(50),
    latitude         NVARCHAR(50),
    longitude        NVARCHAR(50),
    dock_doors       NVARCHAR(50),
    operating_hours  NVARCHAR(50)
);

CREATE TABLE dbo.STG_ROUTES (
    route_id                NVARCHAR(50),
    origin_city             NVARCHAR(100),
    origin_state            NVARCHAR(50),
    destination_city        NVARCHAR(100),
    destination_state       NVARCHAR(50),
    typical_distance_miles  NVARCHAR(50),
    base_rate_per_mile      NVARCHAR(50),
    fuel_surcharge_rate     NVARCHAR(50),
    typical_transit_days    NVARCHAR(50)
);

-- ---------------------------- TRANSACTION ------------------------------------
-- Fact_Trips.csv = trips.csv LEFT JOIN loads.csv (theo transform_dw.py)
CREATE TABLE dbo.STG_TRIPS (
    trip_id                NVARCHAR(50),
    load_id                NVARCHAR(50),
    driver_id              NVARCHAR(50),
    truck_id               NVARCHAR(50),
    trailer_id             NVARCHAR(50),
    dispatch_date          NVARCHAR(50),
    actual_distance_miles  NVARCHAR(50),
    actual_duration_hours  NVARCHAR(50),
    fuel_gallons_used      NVARCHAR(50),
    average_mpg            NVARCHAR(50),
    idle_time_hours        NVARCHAR(50),
    trip_status            NVARCHAR(50),
    customer_id            NVARCHAR(50),
    route_id               NVARCHAR(50),
    load_date              NVARCHAR(50),
    load_type              NVARCHAR(50),
    weight_lbs             NVARCHAR(50),
    pieces                 NVARCHAR(50),
    revenue                NVARCHAR(50),
    fuel_surcharge         NVARCHAR(50),
    accessorial_charges    NVARCHAR(50),
    load_status            NVARCHAR(50),
    booking_type           NVARCHAR(50)
);

-- STG_LOADS được tách lại từ STG_TRIPS (mỗi load_id một dòng) trong bước Extract
CREATE TABLE dbo.STG_LOADS (
    load_id              NVARCHAR(50),
    customer_id          NVARCHAR(50),
    route_id             NVARCHAR(50),
    load_date            NVARCHAR(50),
    load_type            NVARCHAR(50),
    weight_lbs           NVARCHAR(50),
    pieces               NVARCHAR(50),
    revenue              NVARCHAR(50),
    fuel_surcharge       NVARCHAR(50),
    accessorial_charges  NVARCHAR(50),
    load_status          NVARCHAR(50),
    booking_type         NVARCHAR(50)
);

CREATE TABLE dbo.STG_FUEL_PURCHASES (
    fuel_purchase_id  NVARCHAR(50),
    trip_id           NVARCHAR(50),
    truck_id          NVARCHAR(50),
    driver_id         NVARCHAR(50),
    purchase_date     NVARCHAR(50),
    location_city     NVARCHAR(100),
    location_state    NVARCHAR(50),
    gallons           NVARCHAR(50),
    price_per_gallon  NVARCHAR(50),
    total_cost        NVARCHAR(50),
    fuel_card_number  NVARCHAR(50)
);

CREATE TABLE dbo.STG_MAINTENANCE_RECORDS (
    maintenance_id       NVARCHAR(50),
    truck_id             NVARCHAR(50),
    maintenance_date     NVARCHAR(50),
    maintenance_type     NVARCHAR(50),
    odometer_reading     NVARCHAR(50),
    labor_hours          NVARCHAR(50),
    labor_cost           NVARCHAR(50),
    parts_cost           NVARCHAR(50),
    total_cost           NVARCHAR(50),
    facility_location    NVARCHAR(100),
    downtime_hours       NVARCHAR(50),
    service_description  NVARCHAR(400)
);

CREATE TABLE dbo.STG_DELIVERY_EVENTS (
    event_id            NVARCHAR(50),
    load_id             NVARCHAR(50),
    trip_id             NVARCHAR(50),
    event_type          NVARCHAR(50),
    facility_id         NVARCHAR(50),
    scheduled_datetime  NVARCHAR(50),
    actual_datetime     NVARCHAR(50),
    detention_minutes   NVARCHAR(50),
    on_time_flag        NVARCHAR(10),
    location_city       NVARCHAR(100),
    location_state      NVARCHAR(50)
);

CREATE TABLE dbo.STG_SAFETY_INCIDENTS (
    incident_id          NVARCHAR(50),
    trip_id              NVARCHAR(50),
    truck_id             NVARCHAR(50),
    driver_id            NVARCHAR(50),
    incident_date        NVARCHAR(50),
    incident_type        NVARCHAR(100),
    location_city        NVARCHAR(100),
    location_state       NVARCHAR(50),
    at_fault_flag        NVARCHAR(10),
    injury_flag          NVARCHAR(10),
    vehicle_damage_cost  NVARCHAR(50),
    cargo_damage_cost    NVARCHAR(50),
    claim_amount         NVARCHAR(50),
    preventable_flag     NVARCHAR(10),
    description          NVARCHAR(400)
);

-- ---------------------------- AGGREGATED -------------------------------------
CREATE TABLE dbo.STG_DRIVER_MONTHLY_METRICS (
    driver_id              NVARCHAR(50),
    month                  NVARCHAR(50),
    trips_completed        NVARCHAR(50),
    total_miles            NVARCHAR(50),
    total_revenue          NVARCHAR(50),
    average_mpg            NVARCHAR(50),
    total_fuel_gallons     NVARCHAR(50),
    on_time_delivery_rate  NVARCHAR(50),
    average_idle_hours     NVARCHAR(50)
);

CREATE TABLE dbo.STG_TRUCK_UTILIZATION_METRICS (
    truck_id            NVARCHAR(50),
    month               NVARCHAR(50),
    trips_completed     NVARCHAR(50),
    total_miles         NVARCHAR(50),
    total_revenue       NVARCHAR(50),
    average_mpg         NVARCHAR(50),
    maintenance_events  NVARCHAR(50),
    maintenance_cost    NVARCHAR(50),
    downtime_hours      NVARCHAR(50),
    utilization_rate    NVARCHAR(50)
);
GO

PRINT N'01. Đã tạo 14 bảng Staging.';
GO
