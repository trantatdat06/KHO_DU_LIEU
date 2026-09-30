import os
import pandas as pd
import numpy as np

# Thiết lập đường dẫn
source_dir = r"D:\0Project\Start\Kho Dữ liệu\2_Cleaned_Data"
export_dir = r"D:\0Project\Start\Kho Dữ liệu\3_Transformed_Data"
os.makedirs(export_dir, exist_ok=True)

print("Bắt đầu quá trình Transform Data Warehouse...")

def load_csv(filename):
    path = os.path.join(source_dir, filename)
    if os.path.exists(path):
        return pd.read_csv(path)
    return pd.DataFrame()

# 1. TẠO CÁC BẢNG CHIỀU (DIMENSIONS)
print("1. Đang xử lý các Bảng Chiều (Dim Tables)...")
dim_mapping = {
    'customers.csv': 'Dim_Customer.csv',
    'drivers.csv': 'Dim_Driver.csv',
    'trucks.csv': 'Dim_Truck.csv',
    'trailers.csv': 'Dim_Trailer.csv',
    'facilities.csv': 'Dim_Facility.csv',
    'routes.csv': 'Dim_Route.csv'
}

for src, dest in dim_mapping.items():
    df = load_csv(src)
    if not df.empty:
        # Chuẩn hóa ngày tháng nếu có chứa từ 'date' trong tên cột
        for col in df.columns:
            if 'date' in col.lower() or 'time' in col.lower():
                df[col] = pd.to_datetime(df[col], errors='ignore').astype(str)
        df.to_csv(os.path.join(export_dir, dest), index=False, encoding='utf-8')

# Tạo Dim_Date (Bảng thời gian) từ 2015 đến 2025
print("-> Đang tạo bảng Dim_Date...")
date_range = pd.date_range(start='2015-01-01', end='2025-12-31')
dim_date = pd.DataFrame({
    'date_key': date_range.strftime('%Y%m%d').astype(int),
    'full_date': date_range.strftime('%Y-%m-%d'),
    'year': date_range.year,
    'month': date_range.month,
    'day': date_range.day,
    'quarter': date_range.quarter,
    'day_of_week': date_range.dayofweek,
    'is_weekend': np.where(date_range.dayofweek >= 5, 1, 0)
})
dim_date.to_csv(os.path.join(export_dir, 'Dim_Date.csv'), index=False, encoding='utf-8')


# 2. TẠO CÁC BẢNG SỰ KIỆN (FACTS)
print("2. Đang xử lý các Bảng Sự Kiện (Fact Tables)...")

# Fact_Trips (Kết hợp trips.csv và loads.csv)
trips_df = load_csv('trips.csv')
loads_df = load_csv('loads.csv')
if not trips_df.empty and not loads_df.empty:
    fact_trips = pd.merge(trips_df, loads_df, on='load_id', how='left', suffixes=('_trip', '_load'))
    # Đổi các cột thời gian sang chuẩn
    for col in fact_trips.columns:
        if 'date' in col.lower() or 'time' in col.lower():
            fact_trips[col] = pd.to_datetime(fact_trips[col], errors='ignore').astype(str)
    fact_trips.to_csv(os.path.join(export_dir, 'Fact_Trips.csv'), index=False, encoding='utf-8')
elif not trips_df.empty:
    trips_df.to_csv(os.path.join(export_dir, 'Fact_Trips.csv'), index=False, encoding='utf-8')

# Các Fact Table còn lại
fact_mapping = {
    'fuel_purchases.csv': 'Fact_Fuel_Purchases.csv',
    'maintenance_records.csv': 'Fact_Maintenance.csv',
    'safety_incidents.csv': 'Fact_Safety_Incidents.csv',
    'delivery_events.csv': 'Fact_Delivery_Events.csv'
}

for src, dest in fact_mapping.items():
    df = load_csv(src)
    if not df.empty:
        for col in df.columns:
            if 'date' in col.lower() or 'time' in col.lower():
                df[col] = pd.to_datetime(df[col], errors='ignore').astype(str)
        df.to_csv(os.path.join(export_dir, dest), index=False, encoding='utf-8')


# 3. TẠO CÁC BẢNG TỔNG HỢP (AGGREGATIONS)
print("3. Đang xử lý các Bảng Tổng hợp (Agg Tables)...")
agg_mapping = {
    'driver_monthly_metrics.csv': 'Agg_Driver_Monthly.csv',
    'truck_utilization_metrics.csv': 'Agg_Truck_Monthly.csv'
}

for src, dest in agg_mapping.items():
    df = load_csv(src)
    if not df.empty:
        df.to_csv(os.path.join(export_dir, dest), index=False, encoding='utf-8')

print("Hoàn tất! Tất cả dữ liệu DW đã được lưu tại:", export_dir)
