#!/bin/bash

echo "=========================================="
echo "构建自定义 opik-backend 镜像"
echo "=========================================="

set -e

# 配置变量
OPIK_VERSION="${OPIK_VERSION:-1.8.32-custom}"
IMAGE_NAME="${IMAGE_NAME:-opik-backend-custom}"
IMAGE_TAG="${IMAGE_TAG:-$OPIK_VERSION}"
REGISTRY="${REGISTRY:-}"  # 如果需要推送到私有仓库，设置这个变量

echo "OPIK版本: $OPIK_VERSION"
echo "镜像名称: $IMAGE_NAME"
echo "镜像标签: $IMAGE_TAG"
echo "仓库地址: ${REGISTRY:-本地构建}"
echo "=========================================="

# 检查Docker是否可用
if ! command -v docker &> /dev/null; then
    echo "错误: Docker 未安装或不在PATH中"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "错误: Docker daemon 未运行或无权限访问"
    exit 1
fi

# 进入opik-backend目录
cd "$(dirname "$0")/apps/opik-backend"

echo "当前目录: $(pwd)"
echo "检查Dockerfile..."
if [ ! -f "Dockerfile" ]; then
    echo "错误: 找不到 Dockerfile"
    exit 1
fi

echo "检查pom.xml..."
if [ ! -f "pom.xml" ]; then
    echo "错误: 找不到 pom.xml"
    exit 1
fi

# 显示ClickHouse迁移脚本修复状态
echo "=========================================="
echo "验证 ClickHouse 迁移脚本修复状态"
echo "=========================================="

MIGRATION_DIR="src/main/resources/liquibase/db-app-analytics/migrations"
if [ -d "$MIGRATION_DIR" ]; then
    echo "检查 ON CLUSTER 语法残留..."
    if grep -r "ON CLUSTER" "$MIGRATION_DIR" 2>/dev/null; then
        echo "⚠️  警告: 发现 ON CLUSTER 语法，正在修复..."

        # 修复所有ClickHouse迁移脚本
        echo "修复 ClickHouse 迁移脚本中的 ON CLUSTER 语法..."
        find "$MIGRATION_DIR" -name "*.sql" -exec sed -i.bak "s/ ON CLUSTER '{cluster}'//g" {} \;

        # 清理备份文件
        find "$MIGRATION_DIR" -name "*.sql.bak" -delete

        echo "✅ ClickHouse 迁移脚本修复完成"
    else
        echo "✅ 没有发现 ON CLUSTER 语法问题"
    fi
else
    echo "⚠️  警告: 迁移目录不存在: $MIGRATION_DIR"
fi

# 构建镜像
echo "=========================================="
echo "开始构建 Docker 镜像..."
echo "=========================================="

FULL_IMAGE_NAME="$IMAGE_NAME:$IMAGE_TAG"
if [ -n "$REGISTRY" ]; then
    FULL_IMAGE_NAME="$REGISTRY/$FULL_IMAGE_NAME"
fi

echo "构建镜像: $FULL_IMAGE_NAME"

# 显示构建命令
BUILD_CMD="docker build --build-arg OPIK_VERSION=$OPIK_VERSION -t $FULL_IMAGE_NAME ."
echo "执行命令: $BUILD_CMD"

# 执行构建
if $BUILD_CMD; then
    echo "✅ 镜像构建成功: $FULL_IMAGE_NAME"
else
    echo "❌ 镜像构建失败"
    exit 1
fi

# 显示镜像信息
echo "=========================================="
echo "构建完成的镜像信息:"
echo "=========================================="
docker images | grep "$IMAGE_NAME" | head -5

# 如果配置了仓库地址，询问是否推送
if [ -n "$REGISTRY" ]; then
    echo "=========================================="
    echo "推送镜像到仓库"
    echo "=========================================="

    read -p "是否推送镜像到 $REGISTRY? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "推送镜像: $FULL_IMAGE_NAME"
        if docker push "$FULL_IMAGE_NAME"; then
            echo "✅ 镜像推送成功"
        else
            echo "❌ 镜像推送失败"
            exit 1
        fi
    else
        echo "跳过推送步骤"
    fi
fi

# 生成更新Helm values的命令
echo "=========================================="
echo "更新 Helm Chart 配置"
echo "=========================================="

VALUES_FILE="../../deployment/helm_chart/opik/values-external-db-fixed.yaml"

echo "要在 Helm Chart 中使用此镜像，请更新以下文件:"
echo "文件: $VALUES_FILE"
echo ""
echo "修改 backend.image 配置:"
echo "backend:"
echo "  image:"
echo "    repository: ${REGISTRY:+$REGISTRY/}$IMAGE_NAME"
echo "    tag: \"$IMAGE_TAG\""
echo "    pullPolicy: Always"
echo ""


echo "=========================================="
echo "构建完成！"
echo "=========================================="
echo "镜像名称: $FULL_IMAGE_NAME"
echo "镜像大小: $(docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep "$IMAGE_NAME" | head -1 | awk '{print $3}')"
echo ""
echo "下一步操作:"
echo "1. 确认 Helm values 文件已更新镜像配置"
echo "2. 重新部署 opik:"
echo "   cd ../../deployment/helm_chart && ./deploy-external-db.sh"
echo ""
echo "调试命令:"
echo "  docker run --rm -it $FULL_IMAGE_NAME sh  # 进入容器调试"
echo "  docker logs \$(docker ps -q --filter ancestor=$FULL_IMAGE_NAME)  # 查看运行日志"
echo "=========================================="