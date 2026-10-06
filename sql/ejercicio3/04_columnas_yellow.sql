-- 3.3 / 3.4 Columnas y tipos (DuckDB) de los archivos yellow
DESCRIBE SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true);
