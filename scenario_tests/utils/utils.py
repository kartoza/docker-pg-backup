import os

import psycopg2


class DBConnection:

    def __init__(self):
        self.conn = DBConnection.create_conn()

    @staticmethod
    def create_conn():
        """
        :return: psycopg2.connection
        """
        return psycopg2.connect(
            host=os.environ.get('POSTGRES_HOST'),
            database=os.environ.get('POSTGRES_DB'),
            user=os.environ.get('POSTGRES_USER'),
            password=os.environ.get('POSTGRES_PASSWORD'),
            port=os.environ.get('POSTGRES_PORT')
        )

    def cursor(self):
        """
        :return: psycopg2.cursor
        """
        return self.conn.cursor()
