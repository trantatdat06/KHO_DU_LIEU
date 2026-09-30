import csv
import json
import os
import glob

source_dir = r"D:\0Project\Start\Kho Dữ liệu\archive"
target_dir = r"D:\0Project\Start\Kho Dữ liệu\Data"

os.makedirs(target_dir, exist_ok=True)

csv_files = glob.glob(os.path.join(source_dir, "*.csv"))

for csv_file in csv_files:
    file_name = os.path.basename(csv_file)
    json_file_name = os.path.splitext(file_name)[0] + ".json"
    json_file = os.path.join(target_dir, json_file_name)
    
    print(f"Converting {file_name} to {json_file_name}...")
    
    data = []
    try:
        with open(csv_file, 'r', encoding='utf-8') as csvf:
            csvReader = csv.DictReader(csvf)
            for row in csvReader:
                data.append(row)
                
        with open(json_file, 'w', encoding='utf-8') as jsonf:
            json.dump(data, jsonf, indent=4)
        print(f"Success: {json_file_name}")
    except Exception as e:
        print(f"Error converting {file_name}: {e}")

print("Done!")
