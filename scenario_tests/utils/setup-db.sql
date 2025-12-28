CREATE TABLE restore_test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64),
    type VARCHAR(64),
    CONSTRAINT restore_test_name_type_uniq UNIQUE (name, type)
);



INSERT INTO restore_test (name, type) VALUES (
    'kartoza','Company'
);

CREATE TABLE COMPANY(
   ID INT PRIMARY KEY     NOT NULL,
   NAME           TEXT    NOT NULL,
   AGE            INT     NOT NULL,
   ADDRESS        CHAR(50),
   SALARY         REAL,
   JOIN_DATE      DATE
);

INSERT INTO COMPANY (ID, NAME, AGE, ADDRESS, SALARY, JOIN_DATE)
VALUES (1, 'Paul', 32, 'California', 20000.00, '2001-07-13');
