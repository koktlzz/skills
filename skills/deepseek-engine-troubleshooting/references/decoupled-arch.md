# DeepSeek 分离式架构说明

## 架构概述

DeepSeek 分离式(Decoupled)推理架构将模型的计算过程分离到不同的计算节点上执行，以优化资源利用和扩展性。

## 架构组件

### 1. Prefill 阶段

**职责**:
- 接收用户输入
- 计算输入的 KV Cache
- 产生第一个token

**资源需求**:
- 高算力（计算密集型）
- 需要较大显存存储KV Cache
- 通常在完整GPU上运行

### 2. Decode 阶段

**职责**:
- 基于已生成的KV Cache进行自回归生成
- 逐个产生后续token
- 维护生成状态

**资源需求**:
- 显存带宽密集型
- 需要快速访问KV Cache
- 可以批处理多个请求

### 3. Transfer 阶段

**职责**:
- 将Prefill产生的KV Cache传输到Decode节点
- 维护请求状态一致性
- 处理网络通信

## PD分离部署模式

### 模式1: P-D 同节点

```
┌─────────────────────────────────┐
│              GPU                │
│  ┌──────────┐  ┌────────────┐  │
│  │ Prefill  │──│  Decode    │  │
│  │ Instance │  │  Instance  │  │
│  └──────────┘  └────────────┘  │
└─────────────────────────────────┘
```

**适用场景**:
- 小规模部署
- 延迟敏感场景
- 调试测试

### 模式2: P-D 分离节点

```
        ┌─────────────┐
   ┌────│   Router    │────┐
   │    └─────────────┘    │
   │                       │
   ▼                       ▼
┌─────────────────┐   ┌─────────────────┐
│   Prefill Pool  │   │   Decode Pool   │
│  ┌───┐ ┌───┐   │   │  ┌───┐ ┌───┐   │
│  │P1 │ │P2 │...│   │  │D1 │ │D2 │...│
│  └───┘ └───┘   │   │  └───┘ └───┘   │
└─────────────────┘   └─────────────────┘
        │                       │
        │    ┌──────────┐       │
        └────│ 连接层  │───────┘
             │ (RDMA)  │
             └──────────┘
```

**适用场景**:
- 大规模生产环境
- 高并发场景
- 资源独立扩缩容需求

## 故障模式

### PVLost (Pipeline Validation Lost)

**定义**: Pipeline验证阶段的请求或上下文丢失

**发生时机**:
- Prefill完成后，KV Cache未成功传输到Decode
- Decode节点重启或异常退出
- 网络通信中断

**排查步骤**:
1. 检查PD连接状态指标
2. 查看网络延迟和丢包
3. 分析实例重启记录

**预防措施**:
- 启用PD连接健康检查
- 实现请求重试机制
- 配置合理的超时时间

### PD通信超时

**原因**:
- 网络延迟过高
- Decode节点处理慢
- KV Cache体积过大

**排查步骤**:
1. 网络延迟拨测
2. 分析KV Cache大小分布
3. 检查RDMA配置

### 负载不均

**表现**:
- 某些Prefill实例排队长
- Decode实例空闲但Prefill过载

**解决方案**:
- 调整调度策略
- 优化prefix路由
- 动态负载均衡

## 关键配置参数

### 超时配置
```yaml
pd_communication_timeout: 10000  # PD通信超时(ms)
pd_retry_attempts: 3             # 重试次数
prefill_timeout: 30000           # Prefill阶段超时
decode_timeout: 120000           # Decode阶段超时
```

### KV Cache配置
```yaml
kv_cache_page_size: 256          # 页大小
max_kv_cache_size: "32GiB"       # 最大缓存
enable_prefix_caching: true      # 启用前缀缓存
prefix_cache_ttl: 3600           # 缓存TTL(秒)
```

### 调度配置
```yaml
routing_strategy: "prefix_cache" # 路由策略
prefill_batch_size: 32           # Prefill批大小
decode_batch_size: 256           # Decode批大小
```

## 性能优化建议

1. **网络优化**:
   - 使用RDMA网络
   - 调整NCCL参数
   - 启用GPUDirect RDMA

2. **缓存优化**:
   - 合理配置prefix cache
   - 启用动态KV Cache分配
   - 定期清理过期缓存

3. **调度优化**:
   - 根据负载动态调整P/D比例
   - 实现智能请求路由
   - 启用请求合并
