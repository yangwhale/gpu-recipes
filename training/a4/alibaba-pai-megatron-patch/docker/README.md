# pai-megatron-patch:25.04 for A4 GPU

这是基于 pai-megatron-patch:25.04 构建的容器镜像的 Dockerfile，用于在 Google A4 GPU 上运行大型语言模型训练工作负载。

## 特性

- 基于 pai-megatron-patch:25.04 版本
- 为 A4 GPU 架构优化
- 包含 GCSfuse 组件，用于 Google Cloud Storage 集成
- 包含 Google Cloud CLI 工具，用于云资源管理
- 预配置了 222 端口的 SSH，用于多节点通信
- 包含 dllogger，用于训练指标记录
- 支持分布式训练的 SSH 密钥配置

## 文件说明

- [`pai_megatron_patch_a4.Dockerfile`](pai_megatron_patch_a4.Dockerfile): 主要的 Dockerfile，定义了容器镜像的构建过程
- [`cloudbuild.yml`](cloudbuild.yml): Google Cloud Build 配置文件，用于自动化构建流程

## 使用方法

此容器作为本仓库中 A4 训练配方的基础镜像。有关如何使用训练配方的说明，请参阅主要的 A4 [README.md](../../README.md)。

### 构建镜像

使用以下命令构建 Docker 镜像：

```bash
cd Pai-Megatron-Patch-GCP/docker
gcloud builds submit --region=${REGION} \
    --config cloudbuild.yml \
    --substitutions _ARTIFACT_REGISTRY=$ARTIFACT_REGISTRY \
    --timeout "2h" \
    --machine-type=e2-highcpu-32 \
    --quiet \
    --async
```

请确保先设置以下环境变量：
- `REGION`: Google Cloud 区域（例如：us-central1）
- `ARTIFACT_REGISTRY`: Artifact Registry 路径（例如：us-central1-docker.pkg.dev/your-project-id/your-repo）

### 镜像标签

构建完成后，镜像将被标记为：
```
${_ARTIFACT_REGISTRY}/pai_megatron_patch_a4:25.04
```

## 技术细节

### 基础镜像
```dockerfile
FROM us-central1-docker.pkg.dev/supercomputer-testing/chrisya-docker-repo-supercomputer-testing-uc1/pai-megatron-patch:25.04
```

### 安装的组件

1. **GCSfuse 和 Google Cloud CLI**
   - 用于 Google Cloud Storage 集成
   - 提供云资源管理功能

2. **dllogger**
   - NVIDIA 的深度学习日志记录工具
   - 用于训练指标的记录和监控

3. **SSH 配置**
   - 配置在端口 222 上运行
   - 自动生成 RSA 密钥对
   - 支持多节点分布式训练通信

### 工作目录
容器的工作目录设置为 `/workspace`

## 许可证

版权所有 2024 Google LLC

根据 Apache License 2.0 许可证授权。

## 故障排除

### 常见问题

1. **构建超时**
   - 如果构建时间超过 2 小时，可以增加 `--timeout` 参数的值
   - 考虑使用更高配置的构建机器类型

2. **权限问题**
   - 确保您的 Google Cloud 账户具有以下权限：
     - Cloud Build Editor
     - Artifact Registry Writer
     - Storage Object Viewer（如果需要访问基础镜像）

3. **网络连接问题**
   - 确保构建环境可以访问外部网络
   - 检查防火墙规则是否允许必要的连接

### 调试构建过程

查看构建日志：
```bash
gcloud builds list --limit=10
gcloud builds log [BUILD_ID]
```

## 更新日志

### v25.04
- 基于 pai-megatron-patch:25.04 版本
- 更新了基础镜像路径
- 优化了 SSH 配置
- 添加了 dllogger 支持

## 贡献

如需对此 Dockerfile 进行修改，请：

1. 测试您的更改
2. 更新相关文档
3. 提交 Pull Request

## 相关资源

- [pai-megatron-patch 项目](https://github.com/alibaba/Pai-Megatron-Patch)
- [Google Cloud Build 文档](https://cloud.google.com/build/docs)
- [Artifact Registry 文档](https://cloud.google.com/artifact-registry/docs)
- [GCSfuse 文档](https://cloud.google.com/storage/docs/gcs-fuse)