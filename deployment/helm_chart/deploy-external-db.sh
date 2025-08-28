!/bin/bash

# Opik 外部数据库部署脚本
# 这个脚本用于部署使用外部MySQL、Redis、ClickHouse服务的Opik

set -e

# 配置变量
NAMESPACE="${NAMESPACE:-opik}"
RELEASE_NAME="${RELEASE_NAME:-opik}"
VALUES_FILE="${VALUES_FILE:-opik/values-external-db-fixed.yaml}"
TIMEOUT="${TIMEOUT:-600s}"  # 增加默认超时时间

echo "=========================================="
echo "Opik 外部数据库部署脚本"
echo "=========================================="
echo "命名空间: $NAMESPACE"
echo "发布名称: $RELEASE_NAME"
echo "配置文件: $VALUES_FILE"
echo "超时时间: $TIMEOUT"
echo "=========================================="

# 检查kubectl
if ! command -v kubectl &> /dev/null; then
    echo "错误: kubectl 未安装或不在PATH中"
    exit 1
fi

# 检查helm
if ! command -v helm &> /dev/null; then
    echo "错误: helm 未安装或不在PATH中"
    exit 1
fi

# 检查配置文件
if [ ! -f "$VALUES_FILE" ]; then
    echo "错误: 配置文件 $VALUES_FILE 不存在"
    exit 1
fi

# 检查集群连接
echo "检查 Kubernetes 集群连接..."
if ! kubectl cluster-info &>/dev/null; then
    echo "错误: 无法连接到 Kubernetes 集群"
    echo "请检查 kubeconfig 配置和集群状态"
    exit 1
fi

# 创建命名空间（如果不存在）
echo "创建命名空间 $NAMESPACE（如果不存在）..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 进入 Chart 目录
cd "$(dirname "$0")/opik"

# 更新依赖
echo "更新 Helm Chart 依赖..."
helm dependency update

# 验证配置
echo "验证 Helm Chart 配置..."
helm lint . -f "../$VALUES_FILE"

# 诊断函数
diagnose_stuck_deployment() {
    echo ""
    echo "=========================================="
    echo "诊断部署卡住的原因..."
    echo "=========================================="

    echo "1. 检查现有 Pod 状态:"
    kubectl get pods -n "$NAMESPACE" -o wide

    echo ""
    echo "2. 检查 Pod 事件:"
    kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -20

    echo ""
    echo "3. 检查 Helm 发布状态:"
    helm status "$RELEASE_NAME" -n "$NAMESPACE" || echo "无法获取 Helm 状态"

    echo ""
    echo "4. 检查 PVC 状态:"
    kubectl get pvc -n "$NAMESPACE"

    echo ""
    echo "5. 检查资源使用情况:"
    kubectl top nodes || echo "Metrics server 未安装"

    echo ""
    echo "6. 检查失败的 Pod 日志:"
    for pod in $(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running --no-headers -o custom-columns=":metadata.name" 2>/dev/null); do
        if [ ! -z "$pod" ]; then
            echo "--- Pod $pod 日志 ---"
            kubectl logs "$pod" -n "$NAMESPACE" --tail=50 || echo "无法获取 $pod 日志"
            echo ""
        fi
    done

    echo ""
    echo "7. 检查 ImagePullBackOff 问题:"
    kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].state}{"\n"}{end}' | grep -i "imagepull" || echo "未发现镜像拉取问题"

    echo ""
    echo "8. 检查存储类:"
    kubectl get storageclass

    echo ""
    echo "9. 检查网络策略:"
    kubectl get networkpolicy -n "$NAMESPACE" || echo "未发现网络策略"
}

# 超时处理函数
timeout_handler() {
    echo ""
    echo "=========================================="
    echo "警告: Helm 操作超时 ($TIMEOUT)"
    echo "=========================================="
    diagnose_stuck_deployment

    echo ""
    echo "=========================================="
    echo "建议的解决方案:"
    echo "=========================================="
    echo "1. 检查集群资源是否充足"
    echo "2. 验证外部数据库连接:"
    echo "   kubectl run test-mysql --image=mysql:8.0 --rm -it --restart=Never -- mysql -h rm-j6cnx7ou6hi9zv199.mysql.cnhk.rds.aliyuncs.com -u aitrack -p"
    echo ""
    echo "3. 手动清理卡住的资源:"
    echo "   kubectl delete pods --field-selector=status.phase!=Running -n $NAMESPACE"
    echo ""
    echo "4. 如果需要重置部署:"
    echo "   helm uninstall $RELEASE_NAME -n $NAMESPACE"
    echo "   kubectl delete pvc --all -n $NAMESPACE"
    echo ""
    echo "5. 检查 Helm 发布历史:"
    echo "   helm history $RELEASE_NAME -n $NAMESPACE"
    echo ""
    echo "6. 回滚到上一个版本:"
    echo "   helm rollback $RELEASE_NAME -n $NAMESPACE"

    exit 1
}

# 设置信号处理，当脚本被中断时也进行诊断
trap 'echo "脚本被中断"; diagnose_stuck_deployment; exit 1' INT TERM

# 检查是否已经安装
echo "检查现有部署..."
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    echo "发现现有安装，执行升级..."
    echo "开始升级，超时时间: $TIMEOUT"
    echo "如果升级卡住，请按 Ctrl+C 查看诊断信息..."

    # 使用 timeout 命令来控制超时
    if timeout "$TIMEOUT" helm upgrade "$RELEASE_NAME" . -f "../$VALUES_FILE" -n "$NAMESPACE" --wait --timeout="$TIMEOUT"; then
        echo "升级成功完成！"
    else
        echo "升级操作失败或超时"
        timeout_handler
    fi
else
    echo "执行新安装..."
    echo "开始安装，超时时间: $TIMEOUT"
    echo "如果安装卡住，请按 Ctrl+C 查看诊断信息..."

    # 使用 timeout 命令来控制超时
    if timeout "$TIMEOUT" helm install "$RELEASE_NAME" . -f "../$VALUES_FILE" -n "$NAMESPACE" --wait --timeout="$TIMEOUT"; then
        echo "安装成功完成！"
    else
        echo "安装操作失败或超时"
        timeout_handler
    fi
fi

echo "=========================================="
echo "部署完成！"
echo "=========================================="

# 显示部署状态
echo "检查 Pod 状态:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "检查服务状态:"
kubectl get svc -n "$NAMESPACE"

echo ""
echo "检查 Helm 发布状态:"
helm status "$RELEASE_NAME" -n "$NAMESPACE"

echo ""
echo "=========================================="
echo "数据库连接测试:"
echo "=========================================="
echo "测试外部数据库连接 (这可能需要几分钟)..."

# 等待后端 Pod 就绪
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=opik,app.kubernetes.io/component=backend -n "$NAMESPACE" --timeout=300s

# 检查后端健康状态
echo "检查后端健康状态:"
if kubectl exec deployment/opik-backend -n "$NAMESPACE" -- curl -s http://localhost:8080/health-check?name=all&type=ready; then
    echo "✓ 后端健康检查通过"
else
    echo "✗ 后端健康检查失败，查看日志："
    kubectl logs deployment/opik-backend -n "$NAMESPACE" --tail=50
fi

echo ""
echo "=========================================="
echo "有用的命令:"
echo "=========================================="
echo "查看所有资源:"
echo "  kubectl get all -n $NAMESPACE"
echo ""
echo "查看后端日志:"
echo "  kubectl logs -f deployment/opik-backend -n $NAMESPACE"
echo ""
echo "查看前端日志:"
echo "  kubectl logs -f deployment/opik-frontend -n $NAMESPACE"
echo ""
echo "端口转发到前端:"
echo "  kubectl port-forward svc/opik-frontend 5173:5173 -n $NAMESPACE"
echo ""
echo "查看 Helm 状态:"
echo "  helm status -n $NAMESPACE $RELEASE_NAME"
echo ""
echo "查看详细 Pod 信息:"
echo "  kubectl describe pods -n $NAMESPACE"
echo ""
echo "测试数据库连接:"
echo "  kubectl exec -it deployment/opik-backend -n $NAMESPACE -- curl http://localhost:8080/health-check"
echo ""
echo "如果遇到问题，运行诊断:"
echo "  kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp"
echo ""
echo "卸载:"
echo "  helm uninstall -n $NAMESPACE $RELEASE_NAME"
echo "=========================================="