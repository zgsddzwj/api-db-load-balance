# DB 主从复制与读负载分担

2 台 DB 采用 **主从复制**：一台主库负责写，一台从库负责读，实现读流量的负载分担。

## MySQL 主从配置概要

### 1. 主库

- 使用 [mysql-primary.cnf](mysql-primary.cnf) 中的参数（`server-id`、`log_bin` 等），写入主库 `my.cnf` 或 `conf.d/`。
- 重启主库后创建复制用户并授权：

```sql
CREATE USER 'repl'@'%' IDENTIFIED BY 'your_password';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
-- 查看当前 binlog 位点
SHOW MASTER STATUS;
```

### 2. 从库

- 使用 [mysql-replica.cnf](mysql-replica.cnf)（注意 `server-id` 与主库不同），重启从库。
- 在从库上执行（将主库 IP、binlog 文件名和位置替换为 `SHOW MASTER STATUS` 结果）：

```sql
CHANGE MASTER TO
  MASTER_HOST='<主库IP>',
  MASTER_USER='repl',
  MASTER_PASSWORD='your_password',
  MASTER_LOG_FILE='mysql-bin.000001',
  MASTER_LOG_POS=154;
START SLAVE;
SHOW SLAVE STATUS\G
```

确认 `Slave_IO_Running` 与 `Slave_SQL_Running` 均为 Yes。

## PostgreSQL 主从配置概要

### 1. 主库

- 在 `postgresql.conf` 中加入 [postgres-primary.conf](postgres-primary.conf) 中的参数。
- 在 `pg_hba.conf` 中允许从库以复制用户连接（replication）。
- 创建复制用户并重启主库。

### 2. 从库

- 使用 `pg_basebackup` 从主库做基础备份，或从备份恢复。
- 配置 [postgres-replica.conf](postgres-replica.conf) 中的 `primary_conninfo`，并创建 `standby.signal`，重启从库。

详细步骤请参考官方文档：  
[MySQL Replication](https://dev.mysql.com/doc/refman/8.0/en/replication.html)  
[PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)

## 故障与切换

- **主库宕机**：需要将应用写流量切换到从库（从库提升为新主），并重新配置主从或新从库。
- **从库宕机**：写和读可暂时都走主库；从库恢复后重新拉齐并挂载为主从。

建议配合监控与自动化脚本做主从状态检测和切换。
