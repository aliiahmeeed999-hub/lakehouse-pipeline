from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_unixtime, to_timestamp, year, month, dayofmonth, lpad

spark = SparkSession.builder \
    .appName("m2-register-or-append-iceberg") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.iceberg.catalog-impl", "org.apache.iceberg.nessie.NessieCatalog") \
    .config("spark.sql.catalog.iceberg.uri", "http://nessie:19120/api/v2") \
    .config("spark.sql.catalog.iceberg.ref", "main") \
    .config("spark.sql.catalog.iceberg.authentication.type", "NONE") \
    .config("spark.sql.catalog.iceberg.warehouse", "s3a://iceberg-warehouse/") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio1:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.secret.key", "minioadmin123") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .getOrCreate()

raw_path = "s3a://raw-events/"
df = spark.read.parquet(raw_path)

# Kafka Connect / Debezium source timestamp is in milliseconds.
if "__source_ts_ms" in df.columns:
    df = df.withColumn(
        "event_time",
        to_timestamp(from_unixtime((col("__source_ts_ms") / 1000).cast("long")))
    )

# Derive the same partition columns used by analytics.sql.
df = df.withColumn("year", year(col("event_time")).cast("string")) \
       .withColumn("month", lpad(month(col("event_time")).cast("string"), 2, "0")) \
       .withColumn("day", lpad(dayofmonth(col("event_time")).cast("string"), 2, "0"))

df.createOrReplaceTempView("temp_raw_events")

spark.sql("CREATE SCHEMA IF NOT EXISTS iceberg.events")

table_exists = spark.catalog.tableExists("iceberg.events.raw_events")

if not table_exists:
    spark.sql("""
    CREATE TABLE iceberg.events.raw_events
    USING iceberg
    PARTITIONED BY (year, month, day)
    AS SELECT * FROM temp_raw_events
    """)
    print("Iceberg table created with year/month/day partitioning.")
else:
    spark.sql("""
    INSERT INTO iceberg.events.raw_events
    SELECT * FROM temp_raw_events
    """)
    print("Iceberg table already existed, data appended.")

spark.sql("SELECT count(*) AS row_count FROM iceberg.events.raw_events").show()
spark.sql("""
SELECT year, month, day, count(*) AS rows
FROM iceberg.events.raw_events
GROUP BY year, month, day
ORDER BY year, month, day
""").show()


