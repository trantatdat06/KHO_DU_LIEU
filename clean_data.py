import os
import glob
import pandas as pd

source_dir = r"D:\0Project\Start\Kho Dữ liệu\1_Raw_Data"
output_dir = r"D:\0Project\Start\Kho Dữ liệu\2_Cleaned_Data"

os.makedirs(output_dir, exist_ok=True)

# Lấy danh sách toàn bộ các file CSV trong thư mục archive
csv_files = glob.glob(os.path.join(source_dir, "*.csv"))

for file_path in csv_files:
    file_name = os.path.basename(file_path)
    output_path = os.path.join(output_dir, file_name)
    
    print(f"Đang làm sạch dữ liệu: {file_name}...")
    
    try:
        # Tải dữ liệu vào Pandas DataFrame
        df = pd.read_csv(file_path)
            
        # --- CÁC BƯỚC LÀM SẠCH DỮ LIỆU CƠ BẢN ---
        
        # 1. Xóa các dòng trùng lặp (Duplicates)
        df.drop_duplicates(inplace=True)
        
        # 2. Xử lý giá trị trống (Missing values/NaN)
        # Cách 1: Xóa các dòng chứa giá trị trống (bỏ comment dòng dưới để dùng)
        # df.dropna(inplace=True)
        
        # Cách 2: Điền giá trị mặc định vào chỗ trống (Ví dụ: 0 hoặc 'Unknown')
        df.fillna("N/A", inplace=True)
        
        # 3. Chuẩn hóa chuỗi (Loại bỏ khoảng trắng dư thừa ở các cột chữ)
        for col in df.select_dtypes(include=['object']).columns:
            df[col] = df[col].astype(str).str.strip()
            
        # --- KẾT THÚC CÁC BƯỚC LÀM SẠCH ---
        
        # Lưu dữ liệu đã làm sạch đè lên định dạng CSV
        df.to_csv(output_path, index=False, encoding='utf-8')
            
        print(f"Thành công: Đã lưu file sạch tại {output_path}")
        
    except Exception as e:
        print(f"Lỗi khi xử lý {file_name}: {e}")

print("Hoàn tất làm sạch toàn bộ dữ liệu CSV!")
