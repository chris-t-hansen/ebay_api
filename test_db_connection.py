#!/usr/bin/env python3
"""Test database connection and create a test table with sample data."""

import mysql.connector
from dotenv import load_dotenv
import os

# Load environment variables
load_dotenv()

# Database configuration from .env
db_config = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 3306)),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

def test_connection():
    """Test the database connection."""
    try:
        print("Connecting to MariaDB...")
        connection = mysql.connector.connect(**db_config)
        
        if connection.is_connected():
            print("✓ Successfully connected to MariaDB")
            print(f"  Host: {db_config['host']}:{db_config['port']}")
            print(f"  Database: {db_config['database']}")
            print(f"  User: {db_config['user']}")
            return connection
    except mysql.connector.Error as e:
        print(f"✗ Error connecting to MariaDB: {e}")
        return None

def create_test_table(connection):
    """Create the test table."""
    try:
        cursor = connection.cursor()
        
        # Drop table if exists to start fresh
        cursor.execute("DROP TABLE IF EXISTS test")
        
        # Create test table
        create_query = """
        CREATE TABLE test (
            test_id INT AUTO_INCREMENT PRIMARY KEY,
            test_desc VARCHAR(255) NOT NULL
        )
        """
        cursor.execute(create_query)
        print("✓ Successfully created 'test' table")
        
    except mysql.connector.Error as e:
        print(f"✗ Error creating table: {e}")
        return None
    
    return cursor

def insert_test_data(cursor, connection):
    """Insert two rows of random test data."""
    try:
        # Insert two rows of test data
        test_data = [
            ("Random test entry 1 - Lorem ipsum dolor sit amet",),
            ("Random test entry 2 - Consectetur adipiscing elit",)
        ]
        
        insert_query = "INSERT INTO test (test_desc) VALUES (%s)"
        cursor.executemany(insert_query, test_data)
        connection.commit()
        
        print("✓ Successfully inserted 2 rows of test data")
        
        # Verify the data was inserted
        cursor.execute("SELECT * FROM test")
        rows = cursor.fetchall()
        
        print("\nTest table contents:")
        print("-" * 60)
        for row in rows:
            print(f"  test_id: {row[0]}, test_desc: {row[1]}")
        print("-" * 60)
        
    except mysql.connector.Error as e:
        print(f"✗ Error inserting data: {e}")
        connection.rollback()

def cleanup(cursor, connection):
    """Close database connections."""
    if cursor:
        cursor.close()
    if connection and connection.is_connected():
        connection.close()
        print("\n✓ Database connection closed")

if __name__ == "__main__":
    print("=" * 60)
    print("Database Connection Test")
    print("=" * 60)
    
    connection = test_connection()
    if connection:
        cursor = create_test_table(connection)
        if cursor:
            insert_test_data(cursor, connection)
        cleanup(cursor, connection)
    else:
        print("\n✗ Could not establish database connection")
        print("Please check your .env file and ensure MariaDB is running")
