-- ==============================================================================
-- Kịch bản tạo cấu trúc Data Warehouse (Star Schema) trên Microsoft SQL Server
-- Dành cho dự án KHO DỮ LIỆU LOGISTICS
-- ==============================================================================

USE [master];
GO

-- 1. Tạo Database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'Logistics_DW')
BEGIN
    CREATE DATABASE [Logistics_DW];
END
GO

USE [Logistics_DW];
GO

-- ==========================================
-- PHẦN 1: TẠO CÁC BẢNG CHIỀU (DIMENSIONS)
-- ==========================================

-- Bảng Dim_Date (Bảng Thời Gian)
IF OBJECT_ID('dbo.Dim_Date', 'U') IS NOT NULL DROP TABLE dbo.Dim_Date;
CREATE TABLE Dim_Date (
    date_key INT PRIMARY KEY,
    full_date DATE,
    year INT,
    month INT,
    day INT,
    quarter INT,
    day_of_week INT,
    is_weekend BIT
);

-- Bảng Dim_Customer
IF OBJECT_ID('dbo.Dim_Customer', 'U') IS NOT NULL DROP TABLE dbo.Dim_Customer;
CREATE TABLE Dim_Customer (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_name NVARCHAR(255),
    contract_type NVARCHAR(100),
    payment_terms_days INT,
    industry NVARCHAR(100),
    status NVARCHAR(50),
    customer_since DATE,
    max_credit_limit FLOAT
);

-- Bảng Dim_Driver
IF OBJECT_ID('dbo.Dim_Driver', 'U') IS NOT NULL DROP TABLE dbo.Dim_Driver;
CREATE TABLE Dim_Driver (
    driver_id VARCHAR(50) PRIMARY KEY,
    first_name NVARCHAR(100),
    last_name NVARCHAR(100),
    date_of_birth DATE,
    hire_date DATE,
    license_type NVARCHAR(50),
    license_state NVARCHAR(50),
    status NVARCHAR(50)
);

-- Bảng Dim_Truck
IF OBJECT_ID('dbo.Dim_Truck', 'U') IS NOT NULL DROP TABLE dbo.Dim_Truck;
CREATE TABLE Dim_Truck (
    truck_id VARCHAR(50) PRIMARY KEY,
    unit_number VARCHAR(50),
    make NVARCHAR(100),
    model_year INT,
    vin VARCHAR(100),
    acquisition_date DATE,
    acquisition_mileage INT,
    fuel_type NVARCHAR(50),
    tank_capacity_gallons INT,
    status NVARCHAR(50),
    home_terminal NVARCHAR(100)
);

-- Bảng Dim_Trailer
IF OBJECT_ID('dbo.Dim_Trailer', 'U') IS NOT NULL DROP TABLE dbo.Dim_Trailer;
CREATE TABLE Dim_Trailer (
    trailer_id VARCHAR(50) PRIMARY KEY,
    unit_number VARCHAR(50),
    type NVARCHAR(100),
    length_feet INT,
    model_year INT,
    status NVARCHAR(50),
    home_terminal NVARCHAR(100)
);

-- Bảng Dim_Facility
IF OBJECT_ID('dbo.Dim_Facility', 'U') IS NOT NULL DROP TABLE dbo.Dim_Facility;
CREATE TABLE Dim_Facility (
    facility_id VARCHAR(50) PRIMARY KEY,
    facility_name NVARCHAR(255),
    facility_type NVARCHAR(100),
    city NVARCHAR(100),
    state NVARCHAR(50),
    latitude FLOAT,
    longitude FLOAT,
    dock_doors INT,
    operating_hours NVARCHAR(100)
);

-- Bảng Dim_Route
IF OBJECT_ID('dbo.Dim_Route', 'U') IS NOT NULL DROP TABLE dbo.Dim_Route;
CREATE TABLE Dim_Route (
    route_id VARCHAR(50) PRIMARY KEY,
    origin_city NVARCHAR(100),
    origin_state NVARCHAR(50),
    destination_city NVARCHAR(100),
    destination_state NVARCHAR(50),
    distance_miles FLOAT,
    estimated_duration_hours FLOAT,
    base_rate FLOAT
);

-- ==========================================
-- PHẦN 2: TẠO CÁC BẢNG SỰ KIỆN (FACTS)
-- ==========================================

-- Bảng Fact_Trips
IF OBJECT_ID('dbo.Fact_Trips', 'U') IS NOT NULL DROP TABLE dbo.Fact_Trips;
CREATE TABLE Fact_Trips (
    trip_id VARCHAR(50) PRIMARY KEY,
    load_id VARCHAR(50),
    driver_id VARCHAR(50),
    truck_id VARCHAR(50),
    trailer_id VARCHAR(50),
    start_time DATETIME,
    end_time DATETIME,
    distance_miles FLOAT,
    fuel_gallons FLOAT,
    toll_costs FLOAT,
    total_cost FLOAT,
    -- Thông tin Load kết hợp
    customer_id VARCHAR(50),
    route_id VARCHAR(50),
    weight_lbs FLOAT,
    commodity NVARCHAR(100),
    revenue FLOAT,
    FOREIGN KEY (driver_id) REFERENCES Dim_Driver(driver_id),
    FOREIGN KEY (truck_id) REFERENCES Dim_Truck(truck_id),
    FOREIGN KEY (trailer_id) REFERENCES Dim_Trailer(trailer_id),
    FOREIGN KEY (customer_id) REFERENCES Dim_Customer(customer_id),
    FOREIGN KEY (route_id) REFERENCES Dim_Route(route_id)
);

-- (Tương tự, bạn có thể chạy BULK INSERT hoặc xài SSIS để import dữ liệu từ folder 3_Transformed_Data vào đây)
PRINT 'Đã tạo xong cấu trúc Data Warehouse (Star Schema)!';
GO
