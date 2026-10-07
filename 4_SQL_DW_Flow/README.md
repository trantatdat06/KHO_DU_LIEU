# 4_SQL_DW_Flow – Luồng SQL xây dựng Kho dữ liệu (SQL Server)

Bộ script triển khai đúng thiết kế ở **Chương IV** của báo cáo: 14 bảng Staging,
12 Dimension (SCD2 + Unknown Member), 7 Fact (5 Transaction + 2 Periodic Snapshot),
ETL Log và bộ kiểm thử toàn vẹn dữ liệu ở mục 4.7.3.

```
3_Transformed_Data (13 CSV)
   │  02 EXTRACT (BULK INSERT)
   ▼
14 bảng STG_*  ──► 03 DATA QUALITY CHECK (DQ_CHECK_RESULT)
   │
   ▼  05–06 TRANSFORM + LOAD DIMENSION
DIM_DATE, DIM_TIME → DIM_DRIVER/TRUCK/TRAILER/CUSTOMER/FACILITY/ROUTE (SCD2)
→ DIM_EVENT/MAINTENANCE/INCIDENT_TYPE → DIM_LOAD
   │
   ▼  07 LOAD FACT (Business Key → Surrogate Key theo phiên bản SCD2)
FACT_TRIP → FACT_DELIVERY_EVENT, FACT_FUEL_PURCHASE, FACT_MAINTENANCE,
FACT_SAFETY_INCIDENT → FACT_TRUCK_UTILIZATION, FACT_DRIVER_MONTHLY_METRICS
   │
   ▼  09 DATA INTEGRITY TESTING  →  10 BUSINESS QUERY  →  BI / REPORTING
```

## Thứ tự chạy

| File | Nội dung | Mục báo cáo |
|---|---|---|
| `00_Create_Database.sql` | Tạo DB `Logistics_DW`, ETL_BATCH, ETL_LOG, DQ_CHECK_RESULT, hàm chuẩn hóa | 4.7.2.6 |
| `01_Create_Staging.sql` | 14 bảng STG_* (kiểu chuỗi, giữ nguyên dữ liệu nguồn) | 4.7.2.2 |
| `02_Extract_To_Staging.sql` | Thủ tục BULK INSERT CSV → Staging | 4.7.2.1 |
| `03_Data_Quality_Check.sql` | Kiểm tra thiếu, trùng, mồ côi, miền giá trị, ngoại lai IQR | 4.7.2.3 b–e |
| `04_Create_DW_Tables.sql` | 12 Dimension + 7 Fact, PK/FK, index | 4.4, 4.5 |
| `05_Load_Dim_Date_Time.sql` | Sinh DIM_DATE (có ngày lễ Mỹ) và DIM_TIME (theo phút) | 4.4.2–4.4.3 |
| `06_Load_Dimensions.sql` | Nạp Dimension SCD2 + Unknown Member (key = 0) | 4.7.2.3 f–g |
| `07_Load_Facts.sql` | Nạp Fact, tra Surrogate Key | 4.7.2.4–4.7.2.5 |
| `08_Run_ETL.sql` | Thủ tục điều phối `usp_Run_ETL` **và lệnh chạy ETL** | 4.7.1.4 |
| `09_Data_Integrity_Tests.sql` | 69 kiểm thử PASS/FAIL, đạt hết → batch VERIFIED | 4.7.3 |
| `10_Business_Queries.sql` | 7 truy vấn mẫu (4.7.3.11) + 16 câu hỏi kinh doanh (2.3) | 2.3, 4.7.3.11 |

Chạy lần lượt 00 → 10 trong SSMS (F5), hoặc bằng sqlcmd:

```bat
for %f in (0*.sql) do sqlcmd -S localhost -E -f 65001 -b -i "%f"
```

**Trước khi chạy 08:** sửa `@DataPath` cho đúng thư mục `3_Transformed_Data` trên máy.
Tài khoản dịch vụ SQL Server (vd. `NT Service\MSSQLSERVER`) phải có quyền đọc thư mục đó.

Các lần nạp sau chỉ cần chạy lại `EXEC dbo.usp_Run_ETL @DataPath = N'...'`
(không chạy lại 04 vì script đó xóa toàn bộ Dim/Fact). Mọi bước đều idempotent:
chạy lại không nhân bản dữ liệu, thuộc tính Dimension thay đổi sẽ sinh phiên bản SCD2 mới.

## Kết quả chạy thử (SQL Server 2022, dữ liệu hiện tại)

- ETL toàn bộ ~45 giây; 0 dòng bị từ chối; Staging = Fact cho cả 7 Fact.
- 68/69 kiểm thử PASS. Kiểm thử FAIL duy nhất là **dữ liệu thật**:
  436 dòng `truck_utilization_metrics` có `utilization_rate` > 1 (tối đa 1,484).

## Lưu ý về dữ liệu nguồn

1. `idle_time_hours` (trips) và `downtime_hours` (maintenance_records) trong
   `2_Cleaned_Data` / `3_Transformed_Data` bị pandas đổi nhầm sang datetime
   (`1970-01-01 00:00:00.000000003`) và **mất phần thập phân** (3.5 → 3).
   Hàm `fn_ToHours` đọc được cả dạng này lẫn dạng số, nên khi sửa script Python
   (không ép kiểu ngày cho các cột có chữ `time`/`hours`) và xuất lại CSV thì SQL vẫn chạy.
2. `Fact_Trips.csv` là trips đã merge loads → `STG_LOADS` được tách lại từ `STG_TRIPS`.
3. `Dim_Date.csv` không dùng; DIM_DATE được sinh bằng SQL theo đúng cấu trúc 4.4.2.
4. `facility_location` trong maintenance chỉ là tên thành phố → ánh xạ sang DIM_FACILITY
   theo city (ưu tiên loại Terminal); 438 dòng ở thành phố không có cơ sở → facility_key = 0.
5. Nguồn không có chi phí cầu đường/lương tài xế → "lợi nhuận" trong file 10 là
   lợi nhuận gộp ước tính = doanh thu − chi phí nhiên liệu.
