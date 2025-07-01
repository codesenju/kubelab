# Webtop

links:
- https://discourse.linuxserver.io/t/webtop-kasmvnc-uncaught-typeerror/8016/1


# DB
Create a database named "tofudb" and a user named "tofu" with full permissions, using the password "mypassword":
```sql
CREATE DATABASE tofudb;

CREATE USER 'tofu'@'localhost' IDENTIFIED BY 'mypassword';
GRANT ALL PRIVILEGES ON tofudb.* TO 'tofu'@'localhost';
FLUSH PRIVILEGES;
```