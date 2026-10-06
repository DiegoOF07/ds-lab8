-- 3.5 Muestra aleatoria reproducible de registros yellow
SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
USING SAMPLE reservoir(10 ROWS) REPEATABLE (42);
