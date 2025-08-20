# Find max pkey
```
SELECT MAX(id) FROM statistics_short_term;
```
# Find next pkey sequence
```
SELECT nextval('statistics_short_term_id_seq');
```
# Set next pkey to +1 higher than MAX Value
```
SELECT setval('statistics_short_term_id_seq', (SELECT MAX(id) FROM statistics_short_term)+1);
```

# Migrate Database
1. Dump table
```
pg_dump --data-only -t $TABLE "postgresql://$DB_USER:$DB_PASSWORD@$DB_ADDRESS/$DATABASE" > $TABLE.sql
```
2. Edit data if required. For example pkey iteration.
3. Copy data into new database
```
psql -h $DB_ADDRESS -U postgres -d $NEW_DATABASE-f $TABLE.sql
```


# Grafana DB permissions
```
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to user;
```
