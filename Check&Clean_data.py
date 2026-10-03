#!/usr/bin/env python3
"""
Data Quality Checker - Logistics Database (14 bang CSV)
=======================================================
Cach dung:
    python data_quality_check.py --data-dir ./data --out-dir ./dq_report

Nhom kiem tra:
  1. Cau truc   : thieu cot, dong trong
  2. Dinh dang  : khoang trang thua, ma khong dung mau, ngay khong parse duoc,
                  gia tri so bi loi kieu, khac biet hoa/thuong
  3. Day du     : gia tri null
  4. Duy nhat   : trung khoa chinh, trung dong, trung VIN/license/unit...
  5. Mien gia tri: so ngoai khoang hop ly (min/max)
  6. Toan ven tham chieu (FK) : orphan records
  7. Nhat quan noi bo & lien bang : cong thuc (mpg, tong tien), thu tu ngay,
                  thanh pho-bang, khop driver/truck giua trips va fuel/safety...
  8. Bang tong hop : so khop voi du lieu chi tiet
  9. Ngoai le (IQR) : chi mang tinh canh bao

Dau ra: dq_issues.csv, dq_table_summary.csv, dq_report.md  (+ in tom tat ra man hinh)
"""
import argparse
import re
from pathlib import Path

import numpy as np
import pandas as pd

# CAU HINH (sua o day neu schema/nghiep vu thay doi)
TABLES = {
    # ten bang: (khoa chinh, regex ma)
    "customers": ("customer_id", r"^CUST\d{5}$"),
    "drivers": ("driver_id", r"^DRV\d{5}$"),
    "trucks": ("truck_id", r"^TRK\d{5}$"),
    "trailers": ("trailer_id", r"^TRL\d{5}$"),
    "facilities": ("facility_id", r"^FAC\d{5}$"),
    "routes": ("route_id", r"^RTE\d{5}$"),
    "loads": ("load_id", r"^LOAD\d{8}$"),
    "trips": ("trip_id", r"^TRIP\d{8}$"),
    "fuel_purchases": ("fuel_purchase_id", r"^FUEL\d{8}$"),
    "maintenance_records": ("maintenance_id", r"^MAINT\d{8}$"),
    "delivery_events": ("event_id", r"^EVT\d{8}$"),
    "safety_incidents": ("incident_id", r"^INC\d{8}$"),
    "driver_monthly_metrics": (["driver_id", "month"], None),
    "truck_utilization_metrics": (["truck_id", "month"], None),
}

# (bang con, cot, bang cha, cot cha)
FOREIGN_KEYS = [
    ("loads", "customer_id", "customers", "customer_id"),
    ("loads", "route_id", "routes", "route_id"),
    ("trips", "load_id", "loads", "load_id"),
    ("trips", "driver_id", "drivers", "driver_id"),
    ("trips", "truck_id", "trucks", "truck_id"),
    ("trips", "trailer_id", "trailers", "trailer_id"),
    ("fuel_purchases", "trip_id", "trips", "trip_id"),
    ("fuel_purchases", "truck_id", "trucks", "truck_id"),
    ("fuel_purchases", "driver_id", "drivers", "driver_id"),
    ("maintenance_records", "truck_id", "trucks", "truck_id"),
    ("delivery_events", "load_id", "loads", "load_id"),
    ("delivery_events", "trip_id", "trips", "trip_id"),
    ("delivery_events", "facility_id", "facilities", "facility_id"),
    ("safety_incidents", "trip_id", "trips", "trip_id"),
    ("safety_incidents", "truck_id", "trucks", "truck_id"),
    ("safety_incidents", "driver_id", "drivers", "driver_id"),
    ("driver_monthly_metrics", "driver_id", "drivers", "driver_id"),
    ("truck_utilization_metrics", "truck_id", "trucks", "truck_id"),
]

DATE_COLS = {
    "customers": ["contract_start_date"],
    "drivers": ["hire_date", "termination_date", "date_of_birth"],
    "trucks": ["acquisition_date"],
    "trailers": ["acquisition_date"],
    "loads": ["load_date"],
    "trips": ["dispatch_date"],
    "fuel_purchases": ["purchase_date"],
    "maintenance_records": ["maintenance_date"],
    "delivery_events": ["scheduled_datetime", "actual_datetime"],
    "safety_incidents": ["incident_date"],
    "driver_monthly_metrics": ["month"],
    "truck_utilization_metrics": ["month"],
}

# (cot, min, max) - None = khong gioi han
RANGES = {
    "customers": [("credit_terms_days", 0, 120), ("annual_revenue_potential", 1, None)],
    "drivers": [("years_experience", 0, 50)],
    "trucks": [("model_year", 1995, 2026), ("acquisition_mileage", 0, 1_500_000),
               ("tank_capacity_gallons", 50, 400)],
    "trailers": [("model_year", 1995, 2026), ("length_feet", 20, 57)],
    "facilities": [("latitude", 24, 50), ("longitude", -125, -66), ("dock_doors", 1, 500)],
    "routes": [("typical_distance_miles", 1, 3500), ("base_rate_per_mile", 0.5, 6),
               ("fuel_surcharge_rate", 0, 1), ("typical_transit_days", 1, 14)],
    "loads": [("weight_lbs", 1, 80_000), ("pieces", 1, None), ("revenue", 0.01, None),
              ("fuel_surcharge", 0, None), ("accessorial_charges", 0, None)],
    "trips": [("actual_distance_miles", 1, 3500), ("actual_duration_hours", 0.1, 200),
              ("fuel_gallons_used", 0.1, None), ("average_mpg", 3, 12),
              ("idle_time_hours", 0, None)],
    "fuel_purchases": [("gallons", 0.1, 400), ("price_per_gallon", 1, 8),
                       ("total_cost", 0.01, None)],
    "maintenance_records": [("odometer_reading", 0, 2_000_000), ("labor_hours", 0, None),
                            ("labor_cost", 0, None), ("parts_cost", 0, None),
                            ("total_cost", 0, None), ("downtime_hours", 0, None)],
    "delivery_events": [("detention_minutes", 0, 1440)],
    "safety_incidents": [("vehicle_damage_cost", 0, None), ("cargo_damage_cost", 0, None),
                         ("claim_amount", 0, None)],
    "driver_monthly_metrics": [("trips_completed", 0, None), ("total_miles", 0, None),
                               ("total_revenue", 0, None), ("average_mpg", 3, 12),
                               ("on_time_delivery_rate", 0, 1), ("average_idle_hours", 0, None)],
    "truck_utilization_metrics": [("trips_completed", 0, None), ("total_miles", 0, None),
                                  ("total_revenue", 0, None), ("average_mpg", 3, 12),
                                  ("maintenance_events", 0, None), ("maintenance_cost", 0, None),
                                  ("downtime_hours", 0, None), ("utilization_rate", 0, 1)],
}

# cot null la binh thuong -> bo qua o buoc kiem tra null
OPTIONAL_NULL = {("drivers", "termination_date")}

ON_TIME_GRACE_MIN = 120   # nguong tre cho phep van tinh la on-time (suy ra tu du lieu)
SEV_ORDER = {"Critical": 0, "High": 1, "Medium": 2, "Low": 3, "Info": 4}
SEV_WEIGHT_ROWS = {"Critical", "High", "Medium"}  # muc do duoc tinh vao "dong loi"
TODAY = pd.Timestamp.today().normalize()


# THU THAP KET QUA
class Report:
    def __init__(self):
        self.issues = []
        self.bad_rows = {}   # bang -> set index dong loi
        self.n_checks = 0

    def add(self, table, check, sev, col, mask, df, id_col=None, note=""):
        """Ghi nhan 1 kiem tra. mask = Series boolean (True = dong loi)."""
        self.n_checks += 1
        mask = pd.Series(mask, index=df.index).fillna(False).astype(bool)
        n = int(mask.sum())
        if n == 0:
            return
        if id_col is None:
            examples = df.index[mask][:5].tolist()
        else:
            examples = df.loc[mask, id_col].astype(str).head(5).tolist()
        self.issues.append({
            "table": table, "check": check, "severity": sev, "column": col,
            "n_affected": n, "pct_affected": round(100 * n / max(len(df), 1), 3),
            "examples": "; ".join(map(str, examples)), "note": note,
        })
        if sev in SEV_WEIGHT_ROWS:
            self.bad_rows.setdefault(table, set()).update(df.index[mask].tolist())

    def add_count(self, table, check, sev, col, n, total, examples="", note=""):
        """Dung cho kiem tra khong gan truc tiep voi 1 dong (vd: thieu cot)."""
        self.n_checks += 1
        if n == 0:
            return
        self.issues.append({
            "table": table, "check": check, "severity": sev, "column": col,
            "n_affected": int(n), "pct_affected": round(100 * n / max(total, 1), 3),
            "examples": examples, "note": note,
        })


# TIEN ICH
def is_str(s):
    return pd.api.types.is_string_dtype(s) or s.dtype == object


def load_tables(data_dir: Path, rep: Report):
    D = {}
    for name in TABLES:
        p = data_dir / f"{name}.csv"
        if not p.exists():
            rep.add_count(name, "File ton tai", "Critical", "-", 1, 1, note=f"Khong thay {p}")
            continue
        D[name] = pd.read_csv(p, low_memory=False)
    return D


def add_row_id(df, pk):
    if isinstance(pk, list):
        df["_id"] = df[pk].astype(str).agg("|".join, axis=1)
        return "_id"
    return pk


def to_dt(s):
    try:
        return pd.to_datetime(s, errors="coerce", format="mixed")
    except (TypeError, ValueError):
        return pd.to_datetime(s, errors="coerce")


# 1-5. KIEM TRA TUNG BANG
def check_single_table(name, df, rep, idc):
    pk, pattern = TABLES[name]
    pk_cols = pk if isinstance(pk, list) else [pk]
    fk_cols = {c for (t, c, _, _) in FOREIGN_KEYS if t == name}

    # --- cau truc
    missing_cols = [c for c in pk_cols if c not in df.columns]
    rep.add_count(name, "Thieu cot khoa chinh", "Critical", ",".join(missing_cols),
                  len(missing_cols), len(pk_cols))
    rep.add(name, "Dong rong hoan toan", "Medium", "*", df.isna().all(axis=1), df, idc)

    # --- null
    for c in df.columns:
        if c.startswith("_") or (name, c) in OPTIONAL_NULL:
            continue
        nulls = df[c].isna()
        if c in pk_cols:
            sev = "Critical"
        elif c in fk_cols:
            sev = "High"
        else:
            sev = "Medium" if nulls.mean() >= 0.05 else "Low"
        rep.add(name, "Gia tri null/thieu", sev, c, nulls, df, idc)

    # --- khoang trang thua + khac biet hoa/thuong
    for c in df.columns:
        if c.startswith("_") or not is_str(df[c]):
            continue
        s = df[c].dropna().astype(str)
        rep.add(name, "Khoang trang thua dau/cuoi", "Low", c,
                (s != s.str.strip()).reindex(df.index, fill_value=False), df, idc)
        if s.nunique() <= 60:   # cot phan loai
            norm = s.str.strip().str.lower()
            variants = s.groupby(norm).nunique()
            bad = variants[variants > 1].index
            rep.add(name, "Cung gia tri nhung viet khac (hoa/thuong/space)", "Medium", c,
                    norm.isin(bad).reindex(df.index, fill_value=False), df, idc)

    # --- dinh dang khoa chinh
    if pattern and pk in df.columns:
        s = df[pk].astype(str)
        rep.add(name, "Ma khong dung dinh dang", "High", pk,
                ~s.str.match(pattern) & df[pk].notna(), df, idc, note=f"Mong doi {pattern}")

    # --- trung khoa chinh / trung dong
    if all(c in df.columns for c in pk_cols):
        rep.add(name, "Trung khoa chinh", "Critical", ",".join(pk_cols),
                df.duplicated(pk_cols, keep=False), df, idc)
    cols_no_pk = [c for c in df.columns if c not in pk_cols and not c.startswith("_")]
    rep.add(name, "Trung toan bo noi dung (bo qua khoa chinh)", "Medium", "*",
            df.duplicated(cols_no_pk, keep=False), df, idc)

    # --- ngay thang: khong parse duoc / tuong lai / qua xa
    for c in DATE_COLS.get(name, []):
        if c not in df.columns:
            continue
        raw = df[c]
        parsed = to_dt(raw)
        rep.add(name, "Ngay khong parse duoc", "High", c, raw.notna() & parsed.isna(), df, idc)
        rep.add(name, "Ngay o tuong lai", "Medium", c, parsed > TODAY, df, idc)
        if c != "date_of_birth":   # ngay sinh truoc 2000 la binh thuong
            rep.add(name, "Ngay truoc nam 2000", "Medium", c, parsed < pd.Timestamp("2000-01-01"), df, idc)
        df[c] = parsed  # dung ban da parse cho cac buoc sau

    # --- mien gia tri so
    for c, lo, hi in RANGES.get(name, []):
        if c not in df.columns:
            continue
        num = pd.to_numeric(df[c], errors="coerce")
        rep.add(name, "Gia tri khong phai so", "High", c, df[c].notna() & num.isna(), df, idc)
        df[c] = num
        if lo is not None:
            rep.add(name, f"Gia tri < {lo}", "High", c, num < lo, df, idc)
        if hi is not None:
            rep.add(name, f"Gia tri > {hi}", "High", c, num > hi, df, idc)

    # --- ngoai le IQR (canh bao)
    for c in df.select_dtypes(include=[np.number]).columns:
        if c.startswith("_") or c in pk_cols or c in fk_cols:
            continue
        s = df[c].dropna()
        if len(s) < 50:
            continue
        q1, q3 = s.quantile([0.25, 0.75])
        iqr = q3 - q1
        if iqr == 0:
            continue
        out = (df[c] < q1 - 3 * iqr) | (df[c] > q3 + 3 * iqr)
        rep.add(name, "Ngoai le cuc doan (IQR x3)", "Info", c, out, df, idc)


# 6. TOAN VEN THAM CHIEU
def check_foreign_keys(D, rep, idcols):
    for child, col, parent, pcol in FOREIGN_KEYS:
        if child not in D or parent not in D:
            continue
        df = D[child]
        valid = set(D[parent][pcol].dropna())
        orphan = df[col].notna() & ~df[col].isin(valid)
        rep.add(child, f"Orphan FK -> {parent}.{pcol}", "Critical", col, orphan, df, idcols[child])

    # trips <-> loads phai 1-1
    if "trips" in D and "loads" in D:
        t, l = D["trips"], D["loads"]
        rep.add("trips", "Mot load co nhieu trip (phai 1-1)", "High", "load_id",
                t["load_id"].notna() & t.duplicated("load_id", keep=False), t, "trip_id")
        rep.add("loads", "Load khong co trip", "Medium", "load_id",
                ~l["load_id"].isin(t["load_id"]), l, "load_id")
    if "trips" in D and "delivery_events" in D:
        t, e = D["trips"], D["delivery_events"]
        rep.add("trips", "Trip khong co delivery_event", "Medium", "trip_id",
                ~t["trip_id"].isin(e["trip_id"]), t, "trip_id")


# 7. NHAT QUAN NOI BO & LIEN BANG
def city_state_map(D):
    """Thanh pho -> tap cac bang hop le, lay tu facilities + routes."""
    m = {}
    if "facilities" in D:
        for c, s in zip(D["facilities"]["city"], D["facilities"]["state"]):
            m.setdefault(c, set()).add(s)
    if "routes" in D:
        r = D["routes"]
        for c, s in zip(r["origin_city"], r["origin_state"]):
            m.setdefault(c, set()).add(s)
        for c, s in zip(r["destination_city"], r["destination_state"]):
            m.setdefault(c, set()).add(s)
    return m


def check_city_state(table, df, ccol, scol, cmap, rep, idc):
    known = df[ccol].isin(cmap.keys())
    ok = pd.Series([s in cmap.get(c, {s}) for c, s in zip(df[ccol], df[scol])], index=df.index)
    rep.add(table, "Thanh pho - bang khong khop (so voi facilities/routes)", "High",
            f"{ccol},{scol}", known & ~ok, df, idc,
            note="Vd: 'Columbus, MN' trong khi Columbus chi co o bang khac")


def check_cross_table(D, rep, idcols):
    cmap = city_state_map(D)

    # ---------- drivers
    if "drivers" in D:
        d = D["drivers"]
        i = idcols["drivers"]
        rep.add("drivers", "Ngay nghi viec < ngay vao lam", "High", "termination_date",
                d["termination_date"] < d["hire_date"], d, i)
        rep.add("drivers", "Status Terminated nhung khong co termination_date", "High",
                "employment_status", d["employment_status"].astype(str).str.lower().eq("terminated")
                & d["termination_date"].isna(), d, i)
        rep.add("drivers", "Co termination_date nhung status khong phai Terminated", "High",
                "employment_status", d["termination_date"].notna()
                & ~d["employment_status"].astype(str).str.lower().eq("terminated"), d, i)
        age_hire = (d["hire_date"] - d["date_of_birth"]).dt.days / 365.25
        rep.add("drivers", "Tuoi khi tuyen dung < 21 (CDL lien bang)", "High", "hire_date",
                age_hire < 21, d, i)
        age_now = (TODAY - d["date_of_birth"]).dt.days / 365.25
        rep.add("drivers", "years_experience > (tuoi - 18)", "Medium", "years_experience",
                d["years_experience"] > (age_now - 18), d, i)
        rep.add("drivers", "Trung so bang lai (license_number)", "High", "license_number",
                d["license_number"].notna() & d.duplicated("license_number", keep=False), d, i)
        check_city_state_home(d, cmap, rep, i)

    # ---------- trucks / trailers
    for tname in ("trucks", "trailers"):
        if tname not in D:
            continue
        t, i = D[tname], idcols[tname]
        rep.add(tname, "Trung VIN", "Critical", "vin",
                t["vin"].notna() & t.duplicated("vin", keep=False), t, i)
        v = t["vin"].astype(str)
        rep.add(tname, "VIN khong du 17 ky tu / chua I,O,Q", "Low", "vin",
                t["vin"].notna() & (~v.str.match(r"^[A-HJ-NPR-Z0-9]{17}$")), t, i,
                note="Neu la du lieu gia lap thi co the bo qua")
        rep.add(tname, "Mua truoc nam san xuat > 2 nam", "Medium", "acquisition_date",
                t["acquisition_date"].dt.year < t["model_year"] - 2, t, i)
    if "trucks" in D:
        t = D["trucks"]
        rep.add("trucks", "Trung unit_number", "High", "unit_number",
                t.duplicated("unit_number", keep=False), t, "truck_id")
    if "trailers" in D:
        t = D["trailers"]
        rep.add("trailers", "Trung trailer_number", "High", "trailer_number",
                t.duplicated("trailer_number", keep=False), t, "trailer_id")

    # ---------- customers: status/ngay
    if "customers" in D:
        c = D["customers"]
        rep.add("customers", "Trung ten khach hang", "Info", "customer_name",
                c.duplicated("customer_name", keep=False), c, "customer_id",
                note="Co the hop le neu la ten chung")

    # ---------- loads
    if "loads" in D and "routes" in D:
        l = D["loads"]
        # doanh thu / dam bao nhat quan voi route
        m = l.merge(D["routes"][["route_id", "typical_distance_miles", "base_rate_per_mile"]]
                    .drop_duplicates("route_id"), on="route_id", how="left")
        expected = m["typical_distance_miles"] * m["base_rate_per_mile"]
        ratio = m["revenue"] / expected
        rep.add("loads", "Revenue lech > 3x so voi (distance x base_rate)", "Medium", "revenue",
                (ratio > 3) | (ratio < 1 / 3), l, "load_id")

    # ---------- trips
    if "trips" in D:
        t = D["trips"]
        i = "trip_id"
        calc = t["actual_distance_miles"] / t["fuel_gallons_used"]
        rep.add("trips", "average_mpg khong khop distance/gallons (>5%)", "High", "average_mpg",
                (calc - t["average_mpg"]).abs() / t["average_mpg"] > 0.05, t, i)
        speed = t["actual_distance_miles"] / t["actual_duration_hours"]
        rep.add("trips", "Toc do trung binh phi ly (>80 mph hoac <10 mph)", "High",
                "actual_distance_miles,actual_duration_hours", (speed > 80) | (speed < 10), t, i)
        rep.add("trips", "idle_time > duration", "High", "idle_time_hours",
                t["idle_time_hours"] > t["actual_duration_hours"], t, i)
        if "loads" in D:
            m = t.merge(D["loads"][["load_id", "load_date", "load_status", "route_id"]]
                        .drop_duplicates("load_id"), on="load_id", how="left")
            m = m.merge(D["routes"][["route_id", "typical_distance_miles"]]
                        .drop_duplicates("route_id"), on="route_id", how="left")
            rep.add("trips", "dispatch_date truoc load_date", "High", "dispatch_date",
                    m["dispatch_date"] < m["load_date"], t, i)
            rep.add("trips", "dispatch_date > load_date + 30 ngay", "Medium", "dispatch_date",
                    (m["dispatch_date"] - m["load_date"]).dt.days > 30, t, i)
            r = m["actual_distance_miles"] / m["typical_distance_miles"]
            rep.add("trips", "Quang duong thuc te lech > 2x so voi route", "Medium",
                    "actual_distance_miles", (r > 2) | (r < 0.5), t, i)
            rep.add("trips", "trip_status khac load_status", "Medium", "trip_status",
                    m["trip_status"].astype(str).str.lower() != m["load_status"].astype(str).str.lower(),
                    t, i)

    # ---------- fuel_purchases
    if "fuel_purchases" in D:
        f = D["fuel_purchases"]
        i = "fuel_purchase_id"
        rep.add("fuel_purchases", "total_cost != gallons x price (>2%)", "High", "total_cost",
                (f["gallons"] * f["price_per_gallon"] - f["total_cost"]).abs()
                > 0.02 * f["total_cost"].abs() + 0.02, f, i)
        rep.add("fuel_purchases", "fuel_card_number sai dinh dang", "Low", "fuel_card_number",
                f["fuel_card_number"].notna() & ~f["fuel_card_number"].astype(str).str.match(r"^FC\d{6}$"),
                f, i)
        check_city_state("fuel_purchases", f, "location_city", "location_state", cmap, rep, i)
        if "trucks" in D:
            m = f.merge(D["trucks"][["truck_id", "tank_capacity_gallons"]].drop_duplicates("truck_id"),
                        on="truck_id", how="left")
            rep.add("fuel_purchases", "gallons > dung tich binh xe", "High", "gallons",
                    m["gallons"] > m["tank_capacity_gallons"], f, i)
        if "trips" in D:
            tt = D["trips"][["trip_id", "driver_id", "truck_id", "dispatch_date",
                             "actual_duration_hours"]].drop_duplicates("trip_id")
            m = f.merge(tt, on="trip_id", how="left", suffixes=("", "_trip"))
            rep.add("fuel_purchases", "driver_id khac driver cua trip", "High", "driver_id",
                    m["driver_id"].notna() & m["driver_id_trip"].notna()
                    & (m["driver_id"] != m["driver_id_trip"]), f, i)
            rep.add("fuel_purchases", "truck_id khac truck cua trip", "High", "truck_id",
                    m["truck_id"].notna() & m["truck_id_trip"].notna()
                    & (m["truck_id"] != m["truck_id_trip"]), f, i)
            end = m["dispatch_date"] + pd.to_timedelta(m["actual_duration_hours"], unit="h")
            rep.add("fuel_purchases", "Ngay mua nhien lieu truoc dispatch >1 ngay", "High",
                    "purchase_date", m["purchase_date"] < m["dispatch_date"] - pd.Timedelta(days=1), f, i)
            rep.add("fuel_purchases", "Ngay mua nhien lieu sau khi trip ket thuc >2 ngay", "Medium",
                    "purchase_date", m["purchase_date"] > end + pd.Timedelta(days=2), f, i)

    # ---------- maintenance
    if "maintenance_records" in D:
        mr = D["maintenance_records"]
        i = "maintenance_id"
        rep.add("maintenance_records", "total_cost != labor_cost + parts_cost", "High", "total_cost",
                (mr["labor_cost"] + mr["parts_cost"] - mr["total_cost"]).abs() > 0.02, mr, i)
        rep.add("maintenance_records", "labor_cost = 0 nhung labor_hours > 0", "Low", "labor_cost",
                (mr["labor_cost"] == 0) & (mr["labor_hours"] > 0), mr, i)
        if "trucks" in D:
            m = mr.merge(D["trucks"][["truck_id", "acquisition_date", "acquisition_mileage"]]
                         .drop_duplicates("truck_id"), on="truck_id", how="left")
            rep.add("maintenance_records", "Bao duong truoc ngay mua xe", "High", "maintenance_date",
                    m["maintenance_date"] < m["acquisition_date"], mr, i)
            rep.add("maintenance_records", "Odometer < so km luc mua xe", "High", "odometer_reading",
                    m["odometer_reading"] < m["acquisition_mileage"], mr, i)
        s = mr.sort_values(["truck_id", "maintenance_date"])
        dec = s.groupby("truck_id")["odometer_reading"].diff() < 0
        rep.add("maintenance_records", "Odometer giam theo thoi gian (cung xe)", "High",
                "odometer_reading", dec.reindex(mr.index, fill_value=False), mr, i)

    # ---------- delivery_events
    if "delivery_events" in D:
        e = D["delivery_events"]
        i = "event_id"
        rep.add("delivery_events", "actual_datetime thieu (event da xay ra?)", "Medium",
                "actual_datetime", e["actual_datetime"].isna(), e, i)
        rep.add("delivery_events", "detention_minutes > 0 nhung khong co actual_datetime", "Medium",
                "detention_minutes", (e["detention_minutes"] > 0) & e["actual_datetime"].isna(), e, i)
        late = (e["actual_datetime"] - e["scheduled_datetime"]).dt.total_seconds() / 60
        rep.add("delivery_events", "on_time_flag=True nhung tre > ON_TIME_GRACE_MIN", "High",
                "on_time_flag", (e["on_time_flag"].astype(str) == "True") & (late > ON_TIME_GRACE_MIN), e, i,
                note=f"Cho phep tre toi da {ON_TIME_GRACE_MIN} phut (suy ra tu du lieu)")
        rep.add("delivery_events", "on_time_flag=False nhung som hon lich", "High", "on_time_flag",
                (e["on_time_flag"].astype(str) == "False") & (late <= 0), e, i)
        check_city_state("delivery_events", e, "location_city", "location_state", cmap, rep, i)
        if "facilities" in D:
            m = e.merge(D["facilities"][["facility_id", "city", "state"]].drop_duplicates("facility_id"),
                        on="facility_id", how="left")
            rep.add("delivery_events", "location_city khac city cua facility", "High", "location_city",
                    m["city"].notna() & (m["city"] != m["location_city"]), e, i)
        # Delivery phai sau Pickup trong cung trip
        et = e["event_type"].astype(str).str.lower()
        p = e[et == "pickup"].groupby("trip_id")["actual_datetime"].min()
        dl = e[et == "delivery"].groupby("trip_id")["actual_datetime"].max()
        both = pd.concat([p.rename("p"), dl.rename("d")], axis=1).dropna()
        bad_trips = both.index[both["d"] < both["p"]]
        rep.add("delivery_events", "Delivery xay ra truoc Pickup (cung trip)", "High", "actual_datetime",
                e["trip_id"].isin(bad_trips), e, i)
        cnt = e.groupby("trip_id")["event_type"].nunique()
        rep.add("delivery_events", "Trip khong du ca Pickup va Delivery", "Medium", "event_type",
                e["trip_id"].isin(cnt.index[cnt < 2]), e, i)

    # ---------- safety_incidents
    if "safety_incidents" in D:
        s = D["safety_incidents"]
        i = "incident_id"
        rep.add("safety_incidents", "claim_amount != vehicle_damage + cargo_damage", "Medium",
                "claim_amount", (s["vehicle_damage_cost"] + s["cargo_damage_cost"] - s["claim_amount"]).abs() > 1,
                s, i)
        rep.add("safety_incidents", "preventable=True nhung at_fault=False", "Medium",
                "preventable_flag", (s["preventable_flag"].astype(str) == "True")
                & (s["at_fault_flag"].astype(str) == "False"), s, i)
        check_city_state("safety_incidents", s, "location_city", "location_state", cmap, rep, i)
        if "trips" in D:
            tt = D["trips"][["trip_id", "driver_id", "truck_id", "dispatch_date"]].drop_duplicates("trip_id")
            m = s.merge(tt, on="trip_id", how="left", suffixes=("", "_trip"))
            rep.add("safety_incidents", "driver_id khac driver cua trip", "High", "driver_id",
                    m["driver_id_trip"].notna() & (m["driver_id"] != m["driver_id_trip"]), s, i)
            rep.add("safety_incidents", "truck_id khac truck cua trip", "High", "truck_id",
                    m["truck_id_trip"].notna() & (m["truck_id"] != m["truck_id_trip"]), s, i)
            rep.add("safety_incidents", "Su co xay ra truoc dispatch >1 ngay", "Medium", "incident_date",
                    m["incident_date"] < m["dispatch_date"] - pd.Timedelta(days=1), s, i)

    # ---------- trips: driver/truck dang Terminated/Retired van chay xe?
    if "trips" in D and "drivers" in D:
        t = D["trips"].merge(D["drivers"][["driver_id", "hire_date", "termination_date"]]
                             .drop_duplicates("driver_id"), on="driver_id", how="left")
        rep.add("trips", "Trip truoc ngay driver vao lam", "High", "dispatch_date",
                t["dispatch_date"] < t["hire_date"], D["trips"], "trip_id")
        rep.add("trips", "Trip sau ngay driver nghi viec", "High", "dispatch_date",
                t["dispatch_date"] > t["termination_date"], D["trips"], "trip_id")
    if "trips" in D and "trucks" in D:
        t = D["trips"].merge(D["trucks"][["truck_id", "acquisition_date"]]
                             .drop_duplicates("truck_id"), on="truck_id", how="left")
        rep.add("trips", "Trip truoc ngay mua xe", "High", "dispatch_date",
                t["dispatch_date"] < t["acquisition_date"], D["trips"], "trip_id")
    if "trips" in D and "trailers" in D:
        t = D["trips"].merge(D["trailers"][["trailer_id", "acquisition_date"]]
                             .drop_duplicates("trailer_id"), on="trailer_id", how="left")
        rep.add("trips", "Trip truoc ngay mua trailer", "High", "dispatch_date",
                t["dispatch_date"] < t["acquisition_date"], D["trips"], "trip_id")


def check_city_state_home(d, cmap, rep, idc):
    """home_terminal phai la thanh pho co trong facilities/routes."""
    rep.add("drivers", "home_terminal khong co trong danh sach thanh pho/facility", "Medium",
            "home_terminal", d["home_terminal"].notna() & ~d["home_terminal"].isin(cmap.keys()), d, idc)



# 8. BANG TONG HOP vs CHI TIET
def check_aggregates(D, rep, idcols):
    if "trips" not in D or "loads" not in D:
        return
    t = D["trips"].merge(D["loads"][["load_id", "revenue", "fuel_surcharge", "accessorial_charges"]]
                         .drop_duplicates("load_id"), on="load_id", how="left")
    t["month"] = t["dispatch_date"].dt.to_period("M").dt.to_timestamp()
    t["rev"] = t[["revenue", "fuel_surcharge", "accessorial_charges"]].sum(axis=1, min_count=1)

    def compare(table, key, df_trip_filter=None):
        if table not in D:
            return
        m = D[table]
        i = idcols[table]
        src = t if df_trip_filter is None else t[df_trip_filter(t)]
        g = src.groupby([key, "month"]).agg(n=("trip_id", "count"), miles=("actual_distance_miles", "sum"),
                                            rev=("revenue", "sum")).reset_index()
        j = m.merge(g, on=[key, "month"], how="left")
        rep.add(table, "Co (key, thang) trong tong hop nhung khong co trip nao", "High", "month",
                j["n"].isna() & (j["trips_completed"] > 0), m, i)
        rep.add(table, "trips_completed khong khop so trip chi tiet", "High", "trips_completed",
                j["n"].notna() & (j["trips_completed"] != j["n"]), m, i)
        rep.add(table, "total_miles lech >2% so voi tong trips", "High", "total_miles",
                j["miles"].notna() & ((j["total_miles"] - j["miles"]).abs() > 0.02 * j["miles"]), m, i)
        rep.add(table, "total_revenue lech >2% so voi tong loads.revenue", "Medium", "total_revenue",
                j["rev"].notna() & ((j["total_revenue"] - j["rev"]).abs() > 0.02 * j["rev"]), m, i,
                note="So sanh voi loads.revenue (chua gom surcharge)")
        # trip co trong chi tiet nhung thieu trong tong hop
        keys = set(zip(m[key], m["month"]))
        miss = ~pd.Series(list(zip(g[key], g["month"])), index=g.index).isin(keys)
        rep.add_count(table, "(key, thang) co trip nhung vang trong bang tong hop", "Medium", "month",
                      int(miss.sum()), len(g), examples="; ".join(
                          f"{a}|{b:%Y-%m}" for a, b in list(zip(g.loc[miss, key], g.loc[miss, "month"]))[:5]))
        if "month" in m.columns:
            rep.add(table, "month khong phai ngay dau thang", "Medium", "month", m["month"].dt.day != 1, m, i)

    compare("driver_monthly_metrics", "driver_id")
    compare("truck_utilization_metrics", "truck_id")

    # maintenance_events / cost trong truck_utilization vs maintenance_records
    if "truck_utilization_metrics" in D and "maintenance_records" in D:
        mr = D["maintenance_records"].copy()
        mr["month"] = mr["maintenance_date"].dt.to_period("M").dt.to_timestamp()
        g = mr.groupby(["truck_id", "month"]).agg(ev=("maintenance_id", "count"),
                                                  cost=("total_cost", "sum"),
                                                  down=("downtime_hours", "sum")).reset_index()
        u = D["truck_utilization_metrics"]
        j = u.merge(g, on=["truck_id", "month"], how="left").fillna({"ev": 0, "cost": 0, "down": 0})
        rep.add("truck_utilization_metrics", "maintenance_events khong khop maintenance_records", "High",
                "maintenance_events", j["maintenance_events"] != j["ev"], u, idcols["truck_utilization_metrics"])
        rep.add("truck_utilization_metrics", "maintenance_cost lech >2% so voi maintenance_records", "High",
                "maintenance_cost", (j["maintenance_cost"] - j["cost"]).abs() > 0.02 * j["cost"].clip(lower=1),
                u, idcols["truck_utilization_metrics"])
        rep.add("truck_utilization_metrics", "downtime_hours lech so voi maintenance_records", "Medium",
                "downtime_hours", (j["downtime_hours"] - j["down"]).abs() > 0.5,
                u, idcols["truck_utilization_metrics"])


# BAO CAO

def build_outputs(D, rep, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    issues = pd.DataFrame(rep.issues)
    if issues.empty:
        issues = pd.DataFrame(columns=["table", "check", "severity", "column", "n_affected",
                                       "pct_affected", "examples", "note"])
    issues["_o"] = issues["severity"].map(SEV_ORDER)
    issues = issues.sort_values(["_o", "n_affected"], ascending=[True, False]).drop(columns="_o")
    issues.to_csv(out_dir / "dq_issues.csv", index=False, encoding="utf-8-sig")

    rows = []
    for name, df in D.items():
        n = len(df)
        bad = len(rep.bad_rows.get(name, set()))
        sub = issues[issues["table"] == name]
        rows.append({
            "table": name, "rows": n, "columns": len([c for c in df.columns if not c.startswith("_")]),
            "rows_with_issue(>=Medium)": bad, "clean_row_pct": round(100 * (1 - bad / max(n, 1)), 2),
            "critical": int((sub["severity"] == "Critical").sum()),
            "high": int((sub["severity"] == "High").sum()),
            "medium": int((sub["severity"] == "Medium").sum()),
            "low_info": int(sub["severity"].isin(["Low", "Info"]).sum()),
        })
    summ = pd.DataFrame(rows)
    summ.to_csv(out_dir / "dq_table_summary.csv", index=False, encoding="utf-8-sig")

    total_rows = summ["rows"].sum()
    overall = 100 * (1 - summ["rows_with_issue(>=Medium)"].sum() / max(total_rows, 1))

    md = ["# BAO CAO CHAT LUONG DU LIEU", "",
          f"- So bang: **{len(D)}** | Tong dong: **{total_rows:,}** | So kiem tra da chay: **{rep.n_checks}**",
          f"- Kiem tra phat hien loi: **{len(issues)}**",
          f"- Ty le dong sach (khong loi >= Medium): **{overall:.2f}%**", "",
          "## Tom tat theo bang", "", summ.to_markdown(index=False), "",
          "## Cac van de (sap theo muc do)", ""]
    for sev in ["Critical", "High", "Medium", "Low", "Info"]:
        sub = issues[issues["severity"] == sev]
        if sub.empty:
            continue
        md += [f"### {sev} ({len(sub)})", "",
               sub[["table", "check", "column", "n_affected", "pct_affected", "examples"]]
               .to_markdown(index=False), ""]
    (out_dir / "dq_report.md").write_text("\n".join(md), encoding="utf-8")
    return issues, summ, overall


def main():
    ap = argparse.ArgumentParser(description="Kiem tra chat luong du lieu logistics")
    ap.add_argument("--data-dir", default="/mnt/user-data/uploads")
    ap.add_argument("--out-dir", default="/mnt/user-data/outputs/dq_report")
    args = ap.parse_args()

    rep = Report()
    D = load_tables(Path(args.data_dir), rep)
    idcols = {}
    for name, df in D.items():
        idcols[name] = add_row_id(df, TABLES[name][0])

    for name, df in D.items():
        print(f"[1-5] Kiem tra bang {name} ({len(df):,} dong)...")
        check_single_table(name, df, rep, idcols[name])
    print("[6] Toan ven tham chieu (FK)...")
    check_foreign_keys(D, rep, idcols)
    print("[7] Nhat quan noi bo & lien bang...")
    check_cross_table(D, rep, idcols)
    print("[8] Bang tong hop vs chi tiet...")
    check_aggregates(D, rep, idcols)

    issues, summ, overall = build_outputs(D, rep, Path(args.out_dir))

    pd.set_option("display.width", 250, "display.max_colwidth", 70, "display.max_rows", 500)
    print("\n" + "=" * 100)
    print(f"TONG KET: {rep.n_checks} kiem tra, {len(issues)} phat hien loi. "
          f"Ty le dong sach: {overall:.2f}%")
    print("=" * 100)
    print(summ.to_string(index=False))
    print("\n--- Top van de (Critical/High/Medium) ---")
    top = issues[issues["severity"].isin(["Critical", "High", "Medium"])]
    print(top[["severity", "table", "check", "column", "n_affected", "pct_affected"]]
          .head(60).to_string(index=False))
    print(f"\nBao cao chi tiet: {args.out_dir}/")


if __name__ == "__main__":
    main()