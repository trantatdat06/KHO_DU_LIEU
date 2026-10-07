-- ==============================================================================
-- 10. TRUY VẤN PHÂN TÍCH NGHIỆP VỤ
--   Phần A: 7 truy vấn mẫu của mục 4.7.3.11 (chuyển sang cú pháp T-SQL)
--   Phần B: 16 câu hỏi kinh doanh của mục 2.3
-- Nguyên tắc chống double counting: luôn tổng hợp Fact về cùng grain (chuyến,
-- xe, tuyến...) TRƯỚC khi JOIN các Fact khác nhau với nhau.
-- ==============================================================================
USE [Logistics_DW];
GO

-- ##############################################################################
-- PHẦN A – TRUY VẤN MẪU (4.7.3.11)
-- ##############################################################################

-- Ví dụ 1 – Tổng số chuyến theo tháng
SELECT d.year, d.month_of_year, SUM(t.trip_count) AS total_trips
FROM dbo.FACT_TRIP t
JOIN dbo.DIM_DATE d ON t.dispatch_date_key = d.date_key
GROUP BY d.year, d.month_of_year
ORDER BY d.year, d.month_of_year;

-- Ví dụ 2 – Tổng doanh thu theo tháng
SELECT d.year, d.month_of_year, SUM(l.revenue) AS total_revenue
FROM dbo.DIM_LOAD l
JOIN dbo.DIM_DATE d ON l.load_date = d.full_date
WHERE l.is_current = 1 AND l.load_key <> 0
GROUP BY d.year, d.month_of_year
ORDER BY d.year, d.month_of_year;

-- Ví dụ 3 – Chi phí nhiên liệu trên mỗi mile theo xe tải
WITH FuelByTruck AS (
    SELECT tr.truck_id, SUM(f.total_cost) AS total_fuel_cost
    FROM dbo.FACT_FUEL_PURCHASE f JOIN dbo.DIM_TRUCK tr ON tr.truck_key = f.truck_key
    GROUP BY tr.truck_id
), MilesByTruck AS (
    SELECT tr.truck_id, SUM(t.actual_distance_miles) AS total_miles
    FROM dbo.FACT_TRIP t JOIN dbo.DIM_TRUCK tr ON tr.truck_key = t.truck_key
    GROUP BY tr.truck_id
)
SELECT tr.truck_id, tr.unit_number, fb.total_fuel_cost, mb.total_miles,
       fb.total_fuel_cost / NULLIF(mb.total_miles, 0) AS fuel_cost_per_mile
FROM dbo.DIM_TRUCK tr
JOIN FuelByTruck fb  ON fb.truck_id = tr.truck_id
JOIN MilesByTruck mb ON mb.truck_id = tr.truck_id
WHERE tr.is_current = 1 AND tr.truck_key <> 0
ORDER BY fuel_cost_per_mile DESC;

-- Ví dụ 4 – Chi phí bảo dưỡng theo xe tải
SELECT tr.truck_id, tr.unit_number,
       SUM(m.labor_cost)        AS total_labor_cost,
       SUM(m.parts_cost)        AS total_parts_cost,
       SUM(m.total_cost)        AS total_maintenance_cost,
       SUM(m.downtime_hours)    AS total_downtime_hours,
       SUM(m.maintenance_count) AS total_maintenance_events
FROM dbo.FACT_MAINTENANCE m
JOIN dbo.DIM_TRUCK tr ON m.truck_key = tr.truck_key
GROUP BY tr.truck_id, tr.unit_number
ORDER BY total_maintenance_cost DESC;

-- Ví dụ 5 – Tỷ lệ giao hàng đúng hạn theo tuyến
SELECT r.route_id, r.origin_city, r.origin_state, r.destination_city, r.destination_state,
       AVG(CASE WHEN e.on_time_flag = 1 THEN 1.0 ELSE 0.0 END) AS on_time_rate,
       SUM(e.event_count) AS total_events
FROM dbo.FACT_DELIVERY_EVENT e
JOIN dbo.FACT_TRIP t ON e.trip_key = t.trip_key
JOIN dbo.DIM_ROUTE r ON t.route_key = r.route_key
GROUP BY r.route_id, r.origin_city, r.origin_state, r.destination_city, r.destination_state
ORDER BY on_time_rate ASC;

-- Ví dụ 6 – Hiệu suất tài xế theo tháng
SELECT d.driver_id, d.first_name, d.last_name, dt.year, dt.month_of_year,
       m.trips_completed, m.total_miles, m.total_revenue, m.average_mpg,
       m.total_fuel_gallons, m.on_time_delivery_rate, m.average_idle_hours
FROM dbo.FACT_DRIVER_MONTHLY_METRICS m
JOIN dbo.DIM_DRIVER d ON m.driver_key = d.driver_key
JOIN dbo.DIM_DATE dt  ON m.month_date_key = dt.date_key
ORDER BY dt.year, dt.month_of_year, m.total_revenue DESC;

-- Ví dụ 7 – Số sự cố theo tài xế
SELECT d.driver_id, d.first_name, d.last_name,
       COUNT(i.incident_key)                                    AS total_incidents,
       SUM(CASE WHEN i.injury_flag = 1 THEN 1 ELSE 0 END)       AS injury_incidents,
       SUM(CASE WHEN i.at_fault_flag = 1 THEN 1 ELSE 0 END)     AS at_fault_incidents,
       SUM(CASE WHEN i.preventable_flag = 1 THEN 1 ELSE 0 END)  AS preventable_incidents,
       SUM(i.vehicle_damage_cost) AS total_vehicle_damage_cost,
       SUM(i.cargo_damage_cost)   AS total_cargo_damage_cost,
       SUM(i.claim_amount)        AS total_claim_amount
FROM dbo.FACT_SAFETY_INCIDENT i
JOIN dbo.DIM_DRIVER d ON i.driver_key = d.driver_key
GROUP BY d.driver_id, d.first_name, d.last_name
ORDER BY total_incidents DESC;
GO

-- ##############################################################################
-- PHẦN B – 16 CÂU HỎI KINH DOANH (mục 2.3)
-- Lưu ý: dữ liệu nguồn không có chi phí cầu đường/lương tài xế → "lợi nhuận" ở đây
-- là lợi nhuận gộp ước tính = doanh thu (revenue + phụ phí) − chi phí nhiên liệu
-- (− chi phí bảo trì khi phân tích theo xe).
-- ##############################################################################

-- View dùng chung: mỗi chuyến 1 dòng, đã gắn doanh thu và chi phí nhiên liệu
-- (nhiên liệu được tổng hợp theo trip_key TRƯỚC khi join → không nhân bản)
CREATE OR ALTER VIEW dbo.vw_Trip_Economics AS
SELECT t.trip_key, t.trip_id, t.dispatch_date_key, t.driver_key, t.truck_key, t.trailer_key, t.route_key,
       l.customer_id, l.load_type, l.booking_type, l.weight_lbs, l.pieces,
       t.actual_distance_miles, t.actual_duration_hours, t.fuel_gallons_used, t.idle_time_hours, t.trip_count,
       ISNULL(l.revenue, 0)                                                              AS revenue,
       ISNULL(l.revenue, 0) + ISNULL(l.fuel_surcharge, 0) + ISNULL(l.accessorial_charges, 0) AS total_revenue,
       ISNULL(fp.fuel_cost, 0)                                                           AS fuel_cost
FROM dbo.FACT_TRIP t
JOIN dbo.DIM_LOAD l ON l.load_key = t.load_key
LEFT JOIN (SELECT trip_key, SUM(total_cost) AS fuel_cost
           FROM dbo.FACT_FUEL_PURCHASE WHERE trip_key IS NOT NULL
           GROUP BY trip_key) fp ON fp.trip_key = t.trip_key;
GO

-- ============================ BAN LÃNH ĐẠO ===================================

-- Q1. Sản lượng (số chuyến, khối lượng) và doanh thu theo tháng, theo mảng kinh doanh (booking_type)
SELECT d.year, d.month_of_year, e.booking_type,
       SUM(e.trip_count)    AS trips,
       SUM(e.weight_lbs)    AS total_weight_lbs,
       SUM(e.total_revenue) AS total_revenue
FROM dbo.vw_Trip_Economics e
JOIN dbo.DIM_DATE d ON d.date_key = e.dispatch_date_key
GROUP BY d.year, d.month_of_year, e.booking_type
ORDER BY d.year, d.month_of_year, e.booking_type;

-- Q1b. Doanh thu theo xe qua các năm
SELECT d.year, tr.truck_id, tr.make, SUM(e.trip_count) AS trips, SUM(e.total_revenue) AS total_revenue
FROM dbo.vw_Trip_Economics e
JOIN dbo.DIM_DATE d   ON d.date_key = e.dispatch_date_key
JOIN dbo.DIM_TRUCK tr ON tr.truck_key = e.truck_key
GROUP BY d.year, tr.truck_id, tr.make
ORDER BY d.year, total_revenue DESC;

-- Q2. Lợi nhuận gộp của từng tuyến theo quý và theo mảng kinh doanh
SELECT d.year, d.quarter, r.route_id, r.origin_city + N' → ' + r.destination_city AS route_name, e.booking_type,
       SUM(e.total_revenue)               AS total_revenue,
       SUM(e.fuel_cost)                   AS fuel_cost,
       SUM(e.total_revenue - e.fuel_cost) AS gross_profit
FROM dbo.vw_Trip_Economics e
JOIN dbo.DIM_DATE d  ON d.date_key = e.dispatch_date_key
JOIN dbo.DIM_ROUTE r ON r.route_key = e.route_key
GROUP BY d.year, d.quarter, r.route_id, r.origin_city, r.destination_city, e.booking_type
ORDER BY d.year, d.quarter, gross_profit DESC;

-- ============================ BỘ PHẬN KINH DOANH =============================

-- Q3. Doanh thu, doanh thu/mile và lợi nhuận gộp theo tuyến – khách hàng – tháng
SELECT d.year, d.month_of_year, r.route_id, c.customer_name,
       SUM(e.total_revenue)                                          AS total_revenue,
       SUM(e.total_revenue) / NULLIF(SUM(e.actual_distance_miles), 0) AS revenue_per_mile,
       SUM(e.total_revenue - e.fuel_cost)                            AS gross_profit
FROM dbo.vw_Trip_Economics e
JOIN dbo.DIM_DATE d     ON d.date_key = e.dispatch_date_key
JOIN dbo.DIM_ROUTE r    ON r.route_key = e.route_key
JOIN dbo.DIM_CUSTOMER c ON c.customer_id = e.customer_id AND c.is_current = 1
GROUP BY d.year, d.month_of_year, r.route_id, c.customer_name
ORDER BY d.year, d.month_of_year, total_revenue DESC;

-- Q4. Khách hàng đóng góp doanh thu cao nhất và mức tập trung doanh thu (Pareto)
WITH cust AS (
    SELECT c.customer_id, c.customer_name, c.customer_type, SUM(e.total_revenue) AS revenue
    FROM dbo.vw_Trip_Economics e
    JOIN dbo.DIM_CUSTOMER c ON c.customer_id = e.customer_id AND c.is_current = 1
    GROUP BY c.customer_id, c.customer_name, c.customer_type
)
SELECT TOP (20)
       RANK() OVER (ORDER BY revenue DESC) AS rank_no,
       customer_id, customer_name, customer_type, revenue,
       revenue * 100.0 / SUM(revenue) OVER ()                                   AS pct_revenue,
       SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) * 100.0
           / SUM(revenue) OVER ()                                               AS cumulative_pct
FROM cust
ORDER BY revenue DESC;

-- Q5. Khách hàng / tuyến có lợi nhuận gộp thấp hoặc âm trong quý gần nhất của dữ liệu
DECLARE @lastQ INT, @lastY INT;
SELECT TOP 1 @lastY = d.year, @lastQ = d.quarter
FROM dbo.FACT_TRIP t JOIN dbo.DIM_DATE d ON d.date_key = t.dispatch_date_key
ORDER BY d.full_date DESC;

SELECT TOP (20) c.customer_name, r.route_id,
       SUM(e.total_revenue) AS total_revenue, SUM(e.fuel_cost) AS fuel_cost,
       SUM(e.total_revenue - e.fuel_cost) AS gross_profit,
       SUM(e.total_revenue - e.fuel_cost) / NULLIF(SUM(e.total_revenue), 0) AS gross_margin
FROM dbo.vw_Trip_Economics e
JOIN dbo.DIM_DATE d     ON d.date_key = e.dispatch_date_key
JOIN dbo.DIM_ROUTE r    ON r.route_key = e.route_key
JOIN dbo.DIM_CUSTOMER c ON c.customer_id = e.customer_id AND c.is_current = 1
WHERE d.year = @lastY AND d.quarter = @lastQ
GROUP BY c.customer_name, r.route_id
ORDER BY gross_margin ASC;
GO

-- ============================ BỘ PHẬN VẬN HÀNH ===============================

-- Q6. Tuyến có tỷ lệ đúng giờ thấp nhất và detention trung bình trong quý gần nhất
DECLARE @lastQ INT, @lastY INT;
SELECT TOP 1 @lastY = d.year, @lastQ = d.quarter
FROM dbo.FACT_DELIVERY_EVENT e JOIN dbo.DIM_DATE d ON d.date_key = e.scheduled_date_key
ORDER BY d.full_date DESC;

SELECT r.route_id, r.origin_city + N' → ' + r.destination_city AS route_name,
       SUM(e.event_count)                                       AS events,
       AVG(CASE WHEN e.on_time_flag = 1 THEN 1.0 ELSE 0.0 END)  AS on_time_rate,
       AVG(e.detention_minutes)                                 AS avg_detention_minutes
FROM dbo.FACT_DELIVERY_EVENT e
JOIN dbo.DIM_DATE d  ON d.date_key = e.scheduled_date_key
JOIN dbo.FACT_TRIP t ON t.trip_key = e.trip_key
JOIN dbo.DIM_ROUTE r ON r.route_key = t.route_key
WHERE d.year = @lastY AND d.quarter = @lastQ
GROUP BY r.route_id, r.origin_city, r.destination_city
ORDER BY on_time_rate ASC, avg_detention_minutes DESC;
GO

-- Q7. Thời gian thực hiện chuyến trung bình so với thời gian dự kiến theo tuyến
SELECT r.route_id, r.origin_city + N' → ' + r.destination_city AS route_name,
       COUNT(*)                              AS trips,
       AVG(t.actual_duration_hours)          AS avg_actual_hours,
       MAX(r.typical_transit_days) * 24      AS planned_hours,
       AVG(t.actual_duration_hours) - MAX(r.typical_transit_days) * 24 AS diff_hours
FROM dbo.FACT_TRIP t
JOIN dbo.DIM_ROUTE r ON r.route_key = t.route_key
WHERE r.route_key <> 0
GROUP BY r.route_id, r.origin_city, r.destination_city
ORDER BY diff_hours DESC;

-- Q8. Địa điểm nhận/giao hàng có thời gian chậm trễ (detention) trung bình cao nhất
SELECT f.facility_id, f.facility_name, f.facility_type, f.city, f.state, et.event_type,
       COUNT(*)                                                AS events,
       AVG(e.detention_minutes)                                AS avg_detention_minutes,
       AVG(DATEDIFF(MINUTE, e.scheduled_datetime, e.actual_datetime) * 1.0) AS avg_delay_minutes,
       AVG(CASE WHEN e.on_time_flag = 1 THEN 1.0 ELSE 0.0 END) AS on_time_rate
FROM dbo.FACT_DELIVERY_EVENT e
JOIN dbo.DIM_FACILITY f    ON f.facility_key = e.facility_key
JOIN dbo.DIM_EVENT_TYPE et ON et.event_type_key = e.event_type_key
GROUP BY f.facility_id, f.facility_name, f.facility_type, f.city, f.state, et.event_type
ORDER BY avg_detention_minutes DESC;

-- Q9. Tuyến đường và khu vực có số sự cố cao nhất
SELECT r.route_id, r.origin_city + N' → ' + r.destination_city AS route_name,
       COUNT(*) AS incidents, SUM(i.claim_amount) AS total_claim
FROM dbo.FACT_SAFETY_INCIDENT i
JOIN dbo.FACT_TRIP t ON t.trip_key = i.trip_key
JOIN dbo.DIM_ROUTE r ON r.route_key = t.route_key
GROUP BY r.route_id, r.origin_city, r.destination_city
ORDER BY incidents DESC;

SELECT i.location_state, it.incident_type, COUNT(*) AS incidents,
       SUM(CASE WHEN i.injury_flag = 1 THEN 1 ELSE 0 END) AS injury_incidents,
       SUM(i.claim_amount) AS total_claim
FROM dbo.FACT_SAFETY_INCIDENT i
JOIN dbo.DIM_INCIDENT_TYPE it ON it.incident_type_key = i.incident_type_key
GROUP BY i.location_state, it.incident_type
ORDER BY incidents DESC;

-- ============================ BỘ PHẬN BẢO DƯỠNG THIẾT BỊ =====================

-- Q10. Số chuyến và tổng quãng đường theo loại xe (hãng), khu vực (terminal) và tháng
SELECT d.year, d.month_of_year, tr.make, tr.home_terminal,
       SUM(t.trip_count) AS trips, SUM(t.actual_distance_miles) AS total_miles
FROM dbo.FACT_TRIP t
JOIN dbo.DIM_DATE d   ON d.date_key = t.dispatch_date_key
JOIN dbo.DIM_TRUCK tr ON tr.truck_key = t.truck_key
GROUP BY d.year, d.month_of_year, tr.make, tr.home_terminal
ORDER BY d.year, d.month_of_year, total_miles DESC;

-- Q11. Xe có chi phí bảo trì / mile vượt mức trung bình toàn đội
WITH m AS (
    SELECT tr.truck_id, SUM(f.total_cost) AS maint_cost
    FROM dbo.FACT_MAINTENANCE f JOIN dbo.DIM_TRUCK tr ON tr.truck_key = f.truck_key
    GROUP BY tr.truck_id
), mi AS (
    SELECT tr.truck_id, SUM(t.actual_distance_miles) AS miles
    FROM dbo.FACT_TRIP t JOIN dbo.DIM_TRUCK tr ON tr.truck_key = t.truck_key
    GROUP BY tr.truck_id
), x AS (
    SELECT mi.truck_id, ISNULL(m.maint_cost, 0) AS maint_cost, mi.miles,
           ISNULL(m.maint_cost, 0) / NULLIF(mi.miles, 0) AS maint_cost_per_mile
    FROM mi LEFT JOIN m ON m.truck_id = mi.truck_id
    WHERE mi.truck_id <> N'UNKNOWN'
)
SELECT x.*, SUM(maint_cost) OVER () / SUM(miles) OVER () AS fleet_avg_cost_per_mile
FROM x
WHERE maint_cost_per_mile > (SELECT SUM(maint_cost) / SUM(miles) FROM x)
ORDER BY maint_cost_per_mile DESC;

-- Q12. Chi phí nhiên liệu / mile theo hãng xe và tháng (phát hiện tăng bất thường)
WITH fuel AS (
    SELECT f.purchase_date_key / 100 AS yyyymm, tr.make, SUM(f.total_cost) AS fuel_cost
    FROM dbo.FACT_FUEL_PURCHASE f JOIN dbo.DIM_TRUCK tr ON tr.truck_key = f.truck_key
    WHERE tr.truck_key <> 0
    GROUP BY f.purchase_date_key / 100, tr.make
), miles AS (
    SELECT t.dispatch_date_key / 100 AS yyyymm, tr.make, SUM(t.actual_distance_miles) AS miles
    FROM dbo.FACT_TRIP t JOIN dbo.DIM_TRUCK tr ON tr.truck_key = t.truck_key
    WHERE tr.truck_key <> 0
    GROUP BY t.dispatch_date_key / 100, tr.make
), k AS (
    SELECT m.yyyymm, m.make, f.fuel_cost / NULLIF(m.miles, 0) AS fuel_cost_per_mile
    FROM miles m JOIN fuel f ON f.yyyymm = m.yyyymm AND f.make = m.make
)
SELECT yyyymm, make, fuel_cost_per_mile,
       fuel_cost_per_mile - LAG(fuel_cost_per_mile) OVER (PARTITION BY make ORDER BY yyyymm) AS change_vs_prev_month
FROM k
ORDER BY make, yyyymm;

-- Q13. Tuổi xe liên quan thế nào đến tần suất bảo trì, downtime và số sự cố
WITH age AS (
    SELECT truck_id, YEAR(GETDATE()) - model_year AS truck_age
    FROM dbo.DIM_TRUCK WHERE is_current = 1 AND truck_key <> 0
), mt AS (
    SELECT tr.truck_id, SUM(f.maintenance_count) AS maint_events, SUM(f.downtime_hours) AS downtime_hours
    FROM dbo.FACT_MAINTENANCE f JOIN dbo.DIM_TRUCK tr ON tr.truck_key = f.truck_key
    GROUP BY tr.truck_id
), inc AS (
    SELECT tr.truck_id, SUM(i.incident_count) AS incidents
    FROM dbo.FACT_SAFETY_INCIDENT i JOIN dbo.DIM_TRUCK tr ON tr.truck_key = i.truck_key
    GROUP BY tr.truck_id
)
SELECT a.truck_age, COUNT(*) AS trucks,
       AVG(ISNULL(mt.maint_events, 0) * 1.0)   AS avg_maint_events_per_truck,
       AVG(ISNULL(mt.downtime_hours, 0))       AS avg_downtime_hours_per_truck,
       AVG(ISNULL(inc.incidents, 0) * 1.0)     AS avg_incidents_per_truck
FROM age a
LEFT JOIN mt  ON mt.truck_id = a.truck_id
LEFT JOIN inc ON inc.truck_id = a.truck_id
GROUP BY a.truck_age
ORDER BY a.truck_age;

-- ============================ BỘ PHẬN DỊCH VỤ DOANH NGHIỆP ===================

-- Q14. Bảng xếp hạng hiệu suất tài xế theo tháng: chuyến, mile, sự cố, detention trung bình
WITH inc AS (
    SELECT dr.driver_id, i.incident_date_key / 100 AS yyyymm, SUM(i.incident_count) AS incidents
    FROM dbo.FACT_SAFETY_INCIDENT i JOIN dbo.DIM_DRIVER dr ON dr.driver_key = i.driver_key
    GROUP BY dr.driver_id, i.incident_date_key / 100
), det AS (
    SELECT dr.driver_id, e.scheduled_date_key / 100 AS yyyymm, AVG(e.detention_minutes) AS avg_detention
    FROM dbo.FACT_DELIVERY_EVENT e
    JOIN dbo.FACT_TRIP t   ON t.trip_key = e.trip_key
    JOIN dbo.DIM_DRIVER dr ON dr.driver_key = t.driver_key
    GROUP BY dr.driver_id, e.scheduled_date_key / 100
)
SELECT m.month_date_key / 100 AS yyyymm, m.driver_id, d.first_name + N' ' + d.last_name AS driver_name,
       m.trips_completed, m.total_miles, m.total_revenue, m.on_time_delivery_rate,
       ISNULL(inc.incidents, 0) AS incidents, det.avg_detention,
       RANK() OVER (PARTITION BY m.month_date_key ORDER BY m.total_revenue DESC) AS revenue_rank
FROM dbo.FACT_DRIVER_MONTHLY_METRICS m
JOIN dbo.DIM_DRIVER d ON d.driver_key = m.driver_key
LEFT JOIN inc ON inc.driver_id = m.driver_id AND inc.yyyymm = m.month_date_key / 100
LEFT JOIN det ON det.driver_id = m.driver_id AND det.yyyymm = m.month_date_key / 100
ORDER BY yyyymm, revenue_rank;

-- Q15. Cơ cấu chi phí vận hành theo tháng (nhiên liệu, bảo trì, thiệt hại sự cố)
-- (dữ liệu nguồn không có chi phí cầu đường → không đưa vào)
WITH c AS (
    SELECT purchase_date_key / 100 AS yyyymm, N'Nhiên liệu' AS cost_type, SUM(total_cost) AS cost
    FROM dbo.FACT_FUEL_PURCHASE GROUP BY purchase_date_key / 100
    UNION ALL
    SELECT maintenance_date_key / 100, N'Bảo trì', SUM(total_cost)
    FROM dbo.FACT_MAINTENANCE GROUP BY maintenance_date_key / 100
    UNION ALL
    SELECT incident_date_key / 100, N'Thiệt hại sự cố', SUM(vehicle_damage_cost + cargo_damage_cost)
    FROM dbo.FACT_SAFETY_INCIDENT GROUP BY incident_date_key / 100
)
SELECT yyyymm, cost_type, cost,
       cost * 100.0 / SUM(cost) OVER (PARTITION BY yyyymm) AS pct_of_month
FROM c
ORDER BY yyyymm, cost DESC;

-- Q16. Chi phí nhiên liệu thực tế / mile của từng tuyến theo tháng
SELECT e.dispatch_date_key / 100 AS yyyymm, r.route_id,
       r.origin_city + N' → ' + r.destination_city AS route_name,
       SUM(e.fuel_cost) / NULLIF(SUM(e.actual_distance_miles), 0) AS fuel_cost_per_mile,
       MAX(r.fuel_surcharge_rate) AS fuel_surcharge_rate
FROM dbo.vw_Trip_Economics e
JOIN dbo.DIM_ROUTE r ON r.route_key = e.route_key
WHERE r.route_key <> 0
GROUP BY e.dispatch_date_key / 100, r.route_id, r.origin_city, r.destination_city
ORDER BY r.route_id, yyyymm;
GO
