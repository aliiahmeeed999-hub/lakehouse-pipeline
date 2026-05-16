import sys
from pyspark.sql import SparkSession

try:
    spark = SparkSession.builder \
        .appName("m2-spark-validation") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.iceberg.type", "rest") \
        .config("spark.sql.catalog.iceberg.uri", "http://nessie:19120/api/v1") \
        .config("spark.sql.catalog.iceberg.warehouse", "s3a://iceberg-warehouse/") \
        .config("spark.hadoop.fs.s3a.endpoint", "http://minio1:9000") \
        .config("spark.hadoop.fs.s3a.access.key", "minioadmin") \
        .config("spark.hadoop.fs.s3a.secret.key", "minioadmin123") \
        .config("spark.hadoop.fs.s3a.path.style.access", "true") \
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
        .getOrCreate()

    spark.sql("SHOW SCHEMAS IN iceberg").show()
    spark.sql("SHOW TABLES IN iceberg.events").show()
    print("Spark -> Nessie -> MinIO connection OK")
except Exception as e:
    print(f"Validation failed: {e}", file=sys.stderr)
    sys.exit(1)
