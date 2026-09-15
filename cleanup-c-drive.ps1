# ============================================================
# cleanup-c-drive.ps1 —— C 盘空间清理（针对本项目 MySQL 环境）
# ============================================================
# 背景：2026-09-10 曾因 MySQL binlog 堆积 + 巨型事务把 C 盘写满，
#       导致 ETL 报 (1114, "table is full")。本脚本用于日常清理 C 盘。
#
# 功能：
#   1. 显示清理前后 C 盘剩余空间
#   2. 清空 MySQL 二进制日志（binlog）
#   3. 把 binlog 保留期设为 1 天（仅当前会话生效，重启失效）
#   4.（可选）清空当前用户临时目录
#
# 用法：
#   .\cleanup-c-drive.ps1                # 默认：只清 binlog
#   .\cleanup-c-drive.ps1 -CleanTemp     # 追加清理用户临时目录
#
# 备注（彻底治理 C 盘，见《BI看板数据修正说明》第三轮）：
#   - 永久生效需在 my.ini 里加：binlog_expire_logs_seconds=86400
#   - 本项目无主从复制，可在 my.ini 加 skip-log-bin 关闭 binlog
#   - 最彻底：把 MySQL 数据目录(datadir)迁到 D 盘
# ============================================================

param(
    [switch]$CleanTemp,                       # 是否清理用户临时目录
    [string]$MySqlUser = "root",              # MySQL 用户
    [string]$MySqlPass = "root"               # MySQL 密码（可用 $env:DB_PASSWORD 覆盖）
)

if ($env:DB_PASSWORD) { $MySqlPass = $env:DB_PASSWORD }

function Get-FreeGB([string]$Drive) {
    $p = Get-PSDrive -Name $Drive
    return [math]::Round($p.Free / 1GB, 2)
}

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " C 盘空间清理" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ("清理前 C 盘剩余: {0} GB" -f (Get-FreeGB 'C')) -ForegroundColor Yellow

# ---- 1. 清空 MySQL binlog ----
# 作用：binlog 是 MySQL 二进制操作日志，长期堆积会吃满磁盘；本项目无主从复制，不需要它
$mysql = "mysql"
try {
    & $mysql -u $MySqlUser -p$MySqlPass -e "PURGE BINARY LOGS BEFORE NOW();" 2>$null
    & $mysql -u $MySqlUser -p$MySqlPass -e "SET GLOBAL binlog_expire_logs_seconds = 86400;" 2>$null
    Write-Host "  binlog 已清空；保留期已设为 1 天（重启后失效，需写入 my.ini）" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] 未找到 mysql 客户端或连接失败，binlog 未清理" -ForegroundColor DarkYellow
}

# ---- 2.（可选）清理用户临时目录 ----
if ($CleanTemp) {
    Write-Host "清理用户临时目录 %TEMP% ..."
    Get-ChildItem -Path $env:TEMP -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  临时目录已清理" -ForegroundColor Green
}

Write-Host ("清理后 C 盘剩余: {0} GB" -f (Get-FreeGB 'C')) -ForegroundColor Yellow
Write-Host "完成。" -ForegroundColor Cyan
