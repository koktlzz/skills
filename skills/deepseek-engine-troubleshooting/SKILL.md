---
name: deepseek-engine-troubleshooting
description: DeepSeek分离式推理引擎的故障定位与根因分析。用于处理以下场景：(1)引擎上游模型收到引擎返回的错误码；(2)引擎推理超时/延迟异常；(3)p/vlost等验证指标异常；(4)集群调度或资源分配问题。当用户询问关于DeepSeek推理故障、错误码诊断、超时分析或性能异常时触发。
license: Complete terms in LICENSE.txt
---

# DeepSeek 引擎故障定位

本技能提供 DeepSeek 分离式推理引擎的故障诊断方法和分析流程。

## 诊断流程

### 第一步：确认故障现象

收集关键信息：
1. **错误类型**：错误码/超时/性能降级
2. **影响范围**：单个实例/批量/全局
3. **时间窗口**：故障发生时间、持续时间
4. **请求信息**：model name、request id（如有）

### 第二步：查询关键指标

**Prometheus 监控指标**：

```promql
# 引擎推理延迟（TTFT - Time to First Token）
histogram_quantile(0.99,
  sum(rate(deepseek_engine_ttft_bucket[5m])) by (le, pod)
)

# 推理吞吐量
sum(rate(deepseek_engine_tokens_generated_total[5m])) by (pod)

# 错误码分布
sum(rate(deepseek_engine_errors_total[5m])) by (error_code, pod)

# PD分离场景下的通信延迟
histogram_quantile(0.99,
  sum(rate(deepseek_pd_communication_latency_bucket[5m])) by (le)
)
```

**关键指标阈值参考**：
| 指标 | 正常范围 | 告警阈值 |
|------|---------|---------|
| TTFT | <100ms | >500ms |
| TPOT | <10ms | >50ms |
| PVLost | 0 | >0 |

### 第三步：分析 BLS 日志

**日志查询命令**：
```bash
# 按错误码过滤
bls log query --tag deepseek_engine --filter "error_code!=0" --time "last 30m"

# 按超时过滤
bls log query --tag deepseek_engine --filter "duration>30000" --time "last 30m"

# 按 request_id 追溯
bls log query --tag deepseek_engine --filter "req_id=<REQUEST_ID>"
```

**关键日志字段**：
- `error_code`: 引擎返回的错误码
- `duration`: 请求处理耗时(ms)
- `pd_latency`: PD分离通信延迟
- `gpu_util`: GPU利用率
- `mem_usage`: 显存使用

### 第四步：根因分析矩阵

根据错误现象定位根因：

| 错误现象 | 可能原因 | 验证方法 |
|---------|---------|---------|
| error_code: -1 | 输入校验失败 | 检查输入token长度、格式 |
| error_code: -2 | 模型加载异常 | 检查模型版本、权限 |
| error_code: -3 | KV Cache不足 | 检查显存分配策略 |
| 超时 >30s | 队列堆积 | 检查batch size、并发数 |
| pvlost > 0 | Pipeline断裂 | 检查PD连接状态 |
| TTFT 突增 | 前缀缓存未命中 | 检查prefix cache命中率 |

### 第五步：修复建议

**资源配置优化**：
- KV Cache比例调整
- Batch size 动态扩缩容
- GPU显存预留策略

**超时调优**：
- 调整上游超时阈值
- 启用动态超时降级

**应急预案**：
- 实例重启
- 流量切流
- 版本回滚

## 快速诊断脚本

使用 [scripts/diagnose.sh](scripts/diagnose.sh) 执行自动化诊断：

```bash
./scripts/diagnose.sh --env <ENV> --time "2024-01-15 14:00" --duration 30m
```

输出包含：
- 错误码分布统计
- 延迟趋势图
- 资源使用瓶颈
- 推荐修复动作

## 参考资料

- 错误码完整列表：[references/error-codes.md](references/error-codes.md)
- 监控指标说明：[references/metrics.md](references/metrics.md)
- 分离式架构详解：[references/decoupled-arch.md](references/decoupled-arch.md)
