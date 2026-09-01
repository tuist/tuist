-- The schema files above run as the CNPG superuser at initdb, so the
-- objects are postgres-owned; grant the application role everything it
-- needs. Role and database names must match .Values.postgresql.
GRANT ALL ON ALL TABLES IN SCHEMA public TO mdm;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO mdm;
