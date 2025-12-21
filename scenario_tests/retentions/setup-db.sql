CREATE TABLE IF NOT EXISTS restore_test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64),
    type VARCHAR(64)
);


INSERT INTO restore_test (name, type) VALUES (
    'kartoza','Company'
) ON CONFLICT (id) DO NOTHING ;

