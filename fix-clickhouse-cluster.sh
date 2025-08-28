#!/bin/bash

echo "修复ClickHouse迁移文件中的ON CLUSTER语法..."

# 找到所有SQL文件并修复ON CLUSTER语法
for file in $(find apps/opik-backend/src/main/resources/liquibase/db-app-analytics/migrations/ -name "*.sql"); do
    echo "处理文件: $file"
    # 使用简单的sed替换，避免复杂引用
    sed -i.bak "s/ ON CLUSTER '{cluster}'//g" "$file"
    rm -f "$file.bak"
done

echo "✅ 修复完成！"

# 验证是否还有ON CLUSTER引用
echo "检查剩余的ON CLUSTER引用..."
grep -r "ON CLUSTER" apps/opik-backend/src/main/resources/liquibase/db-app-analytics/migrations/ || echo "✅ 没有找到ON CLUSTER引用"