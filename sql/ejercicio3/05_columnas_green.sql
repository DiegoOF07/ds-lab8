-- 3.3 / 3.4 Columnas y tipos (DuckDB) de los archivos green
DESCRIBE SELECT * FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true);
