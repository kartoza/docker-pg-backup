import unittest
from utils.utils import DBConnection


class TestRestore(unittest.TestCase):

    def setUp(self):
        self.db = DBConnection()
        self.db_query = """
                SELECT EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_name = 'restore_test'
                );
            """

    def test_read_data(self):
        self.db.conn.autocommit = True

        with self.db.cursor() as c:
            # Check that the table exists before querying it
            c.execute(self.db_query)
            exists = c.fetchone()[0]
            self.assertTrue(exists, "Expected table 'restore_test' does not exist")

            c.execute("""
                        SELECT name, type
                        FROM restore_test
                        WHERE name = 'kartoza' AND type = 'Company';
                    """)
            rows = c.fetchall()

            # Expect exactly one matching row
            self.assertEqual(
                len(rows),
                1,
                "Expected row ('kartoza', 'Company') not found in restore_test"
            )

    def test_add_data(self):
        self.db.conn.autocommit = True

        with self.db.cursor() as c:
            # Ensure the table exists before inserting
            c.execute(self.db_query)
            exists = c.fetchone()[0]
            self.assertTrue(exists, "Expected table 'restore_test' does not exist")

            # Insert a test row
            c.execute("""
                INSERT INTO restore_test (name, type)
                VALUES ('unit test', 'python')
                ON CONFLICT (name, type)
                DO NOTHING;
            """)

            # Query the inserted row
            c.execute("""
                SELECT name, type
                FROM restore_test
                WHERE name = 'unit test' AND type = 'python';
            """)
            rows = c.fetchall()

            # Validate the inserted data
            self.assertEqual(len(rows), 1, "Inserted row not found in restore_test")
            self.assertEqual(rows[0][0], "unit test")
            self.assertEqual(rows[0][1], "python")


