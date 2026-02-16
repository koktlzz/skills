# DeepSeek 监控指标说明

## 核心延迟指标

### TTFT (Time To First Token)
- **指标名**: `deepseek_engine_ttft_seconds`
- **类型**: Histogram
- **含义**: 从请求到达引擎到输出第一个token的时间
- **正常值**: P50 <50ms, P99 <200ms
- **告警阈值**: P99 >500ms
- **排查方向**:
  - 前缀缓存未命中
  - PD通信延迟
  - GPU计算队列堆积

### TPOT (Time Per Output Token)
- **指标名**: `deepseek_engine_tpot_seconds`
- **类型**: Histogram
- **含义**: 生成每个token的平均时间（不含首token）
- **正常值**: <10ms/token
- **告警阈值**: >50ms/token
- **排查方向**:
  - GPU计算能力瓶颈
  - Batch size过小
  - KV Cache访问效率

### E2ELatency (端到端延迟)
- **指标名**: `deepseek_engine_e2e_latency_seconds`
- **类型**: Histogram
- **含义**: 完整请求处理时间
- **计算公式**: TTFT + TPOT × output_tokens

## 吞吐量指标

### Tokens Generated
- **指标名**: `deepseek_engine_tokens_generated_total`
- **类型**: Counter
- **含义**: 引擎累计生成的token数
- **计算QPS**: `rate(deepseek_engine_tokens_generated_total[1m])`

### Request Rate
- **指标名**: `deepseek_engine_requests_total`
- **类型**: Counter
- **标签**: status="success|error|timeout"
- **含义**: 请求计数，按状态分类

## 资源指标

### GPU利用率
- **指标名**: `nvidia_gpu_utilization_ratio`
- **正常值**: 60-90%
- **告警**:
  - <30%: 利用率偏低，批处理不足
  - >95%: 接近瓶颈，可能排队

### 显存使用
- **指标名**: `deepseek_engine_gpu_memory_used_bytes`
- **含义**: 引擎实际使用的显存
- **建议**: 预留15-20%余量用于动态分配

### KV Cache
- **指标名**: `deepseek_engine_kv_cache_usage_ratio`
- **正常值**: <80%
- **告警阈值**: >95%
- **高使用率处理**:
  - 降低max_seq_length
  - 增加page_size
  - 启用prefix caching

### Prefix Cache
- **指标名**: `deepseek_engine_prefix_cache_hit_ratio`
- **含义**: 前缀缓存命中率
- **建议**: >70%为健康状态
- **提升方法**:
  - 增大prefix cache容量
  - 优化请求调度策略

## PD分离专用指标

### PD通信延迟
- **指标名**: `deepseek_pd_communication_latency_seconds`
- **含义**: Prefill和Decode阶段间的通信耗时
- **正常值**: P99 <10ms
- **告警阈值**: P99 >100ms

### PD连接状态
- **指标名**: `deepseek_pd_connection_status`
- **值**: 0=断开, 1=连接正常
- **必须保持**: 1

### PVLost (Pipeline Validation Lost)
- **指标名**: `deepseek_engine_pvlost_total`
- **类型**: Counter
- **含义**: Pipeline验证阶段丢失的请求数
- **告警阈值**: >0
- **原因**:
  - PD连接断开
  - 实例重启
  - 网络抖动

## 队列指标

### 等待队列长度
- **指标名**: `deepseek_engine_queue_length`
- **告警阈值**: >100

### 批处理大小
- **指标名**: `deepseek_engine_batch_size`
- **含义**: 当前正在处理的请求批大小
- **调优建议**: 根据GPU型号优化
  - A100 40GB: 64-128
  - A100 80GB: 128-256
  - H100: 256-512

## 常用 PromQL 查询

```promql
# QPS趋势
sum(rate(deepseek_engine_requests_total[5m]))

# 错误率
sum(rate(deepseek_engine_requests_total{status="error"}[5m]))
/
sum(rate(deepseek_engine_requests_total[5m]))

# 平均TTFT
histogram_quantile(0.50,
  sum(rate(deepseek_engine_ttft_bucket[5m])) by (le)
)

# 每GPU视角的延迟
topk(5,
  max by (gpu) (deepseek_engine_ttft_seconds{quantile="0.99"})
)

# 显存使用趋势
max(deepseek_engine_gpu_memory_used_bytes) /
max(deepseek_engine_gpu_memory_total_bytes)
```
