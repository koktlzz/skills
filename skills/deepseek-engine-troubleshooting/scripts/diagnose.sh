#!/bin/bash
# DeepSeek 引擎故障诊断脚本
# Usage: ./diagnose.sh --env <ENV> --time "YYYY-MM-DD HH:MM" --duration <MINUTES>

set -e

ENV=""
TIME=""
DURATION=30
OUTPUT_DIR="./diagnose_output"

usage() {
    echo "Usage: $0 --env <ENV> --time \"YYYY-MM-DD HH:MM\" [--duration MINUTES]"
    echo ""
    echo "Options:"
    echo "  --env        环境标识 (prod/pre/staging)"
    echo "  --time       故障发生时间"
    echo "  --duration   查询时间窗口(分钟), 默认30"
    echo "  -h, --help   显示帮助"
    exit 1
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENV="$2"
            shift 2
            ;;
        --time)
            TIME="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# 校验参数
if [[ -z "$ENV" || -z "$TIME" ]]; then
    echo "Error: --env and --time are required"
    usage
fi

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "DeepSeek 引擎故障诊断"
echo "========================================"
echo "环境: $ENV"
echo "时间: $TIME"
echo "窗口: ${DURATION}分钟"
echo "输出: $OUTPUT_DIR"
echo "========================================"
echo ""

# 1. 查询错误码分布
echo "[1/5] 分析错误码分布..."
cat > "$OUTPUT_DIR/error_codes.txt" << 'EOF'
# 执行以下命令获取错误码分布：
# bls log query --tag deepseek_engine --env <ENV> --time "<TIME>" --duration <DURATION>m --filter "error_code!=0"
#
# 或使用 jq 分析已有日志：
# cat engine.log | jq -r 'select(.error_code!=0) | .error_code' | sort | uniq -c | sort -rn
EOF
echo "  输出: $OUTPUT_DIR/error_codes.txt"

# 2. 查询延迟指标
echo "[2/5] 提取延迟指标..."
cat > "$OUTPUT_DIR/latency.promql" << 'EOF'
# TTFT P99
histogram_quantile(0.99,
  sum(rate(deepseek_engine_ttft_bucket[5m])) by (le, pod)
)

# TPOT P99
histogram_quantile(0.99,
  sum(rate(deepseek_engine_tpot_bucket[5m])) by (le, pod)
)

# 端到端延迟
histogram_quantile(0.99,
  sum(rate(deepseek_engine_e2e_latency_bucket[5m])) by (le, pod)
)
EOF
echo "  输出: $OUTPUT_DIR/latency.promql"

# 3. 查询资源使用
echo "[3/5] 提取资源指标..."
cat > "$OUTPUT_DIR/resources.promql" << 'EOF'
# GPU利用率
nvidia_gpu_utilization_ratio

# 显存使用
(deepseek_engine_gpu_memory_used_bytes / deepseek_engine_gpu_memory_total_bytes)

# KV Cache使用率
deepseek_engine_kv_cache_usage_ratio

# Batch大小
deepseek_engine_batch_size
EOF
echo "  输出: $OUTPUT_DIR/resources.promql"

# 4. PD分离指标 (如适用)
echo "[4/5] 提取PD分离指标..."
cat > "$OUTPUT_DIR/pd_metrics.promql" << 'EOF'
# PD通信延迟
histogram_quantile(0.99,
  sum(rate(deepseek_pd_communication_latency_bucket[5m])) by (le)
)

# PVLost计数
sum(rate(deepseek_engine_pvlost_total[5m]))

# PD连接状态
deepseek_pd_connection_status
EOF
echo "  输出: $OUTPUT_DIR/pd_metrics.promql"

# 5. 生成诊断报告模板
echo "[5/5] 生成诊断报告..."
REPORT_FILE="$OUTPUT_DIR/diagnosis_report.md"

cat > "$REPORT_FILE" << EOF
# DeepSeek 引擎故障诊断报告

## 基本信息

| 项目 | 值 |
|------|---|
| 环境 | $ENV |
| 诊断时间 | $(date) |
| 故障时间 | $TIME |
| 查询窗口 | ${DURATION}分钟 |

## 检查结果

### 1. 错误码分布

\`\`\`
# 在此处粘贴错误码统计结果
\`\`\`

**分析**:
- 主要错误码: [待填写]
- 错误趋势: [递增/稳定/下降]

### 2. 延迟分析

| 指标 | P50 | P99 | 是否异常 |
|------|-----|-----|---------|
| TTFT | [ ] | [ ] | [ ] |
| TPOT | [ ] | [ ] | [ ] |
| E2E  | [ ] | [ ] | [ ] |

### 3. 资源使用

| 指标 | 峰值 | 平均值 | 是否异常 |
|------|-----|-------|---------|
| GPU利用率 | [ ] | [ ] | [ ] |
| 显存使用 | [ ] | [ ] | [ ] |
| KV Cache | [ ] | [ ] | [ ] |

### 4. PD分离指标 (如适用)

| 指标 | 值 | 是否异常 |
|------|---|---------|
| PD通信延迟P99 | [ ] | [ ] |
| PVLost | [ ] | [ ] |
| 连接状态 | [ ] | [ ] |

## 根因分析

**初步判断**: [待填写]

**支持证据**:
- [证据1]
- [证据2]

## 修复建议

1. [建议1]
2. [建议2]
3. [建议3]

## 后续行动

- [ ] [行动项1]
- [ ] [行动项2]
EOF

echo "  输出: $REPORT_FILE"

echo ""
echo "========================================"
echo "诊断准备完成"
echo "========================================"
echo ""
echo "下一步操作:"
echo "1. 使用 .promql 文件中的查询在 Prometheus/Grafana 中执行"
echo "2. 使用 bls 命令获取日志数据"
echo "3. 将结果填入 $REPORT_FILE"
echo ""
echo "常用命令参考:"
echo "  bls log query --tag deepseek_engine --env $ENV --time \"$TIME\" --duration ${DURATION}m"
echo ""
