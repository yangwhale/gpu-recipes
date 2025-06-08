#!/bin/bash

# =============================================================================
# NeMo 分布式训练启动脚本
# 用于在 Kubernetes 集群中启动多节点 GPU 训练任务
# =============================================================================

# -----------------------------------------------------------------------------
# 1. 脚本退出处理和信号捕获
# -----------------------------------------------------------------------------

function on_script_completion {
  # 创建信号文件，通知 TCPx sidecar 容器工作负载已完成
  # 这是一个同步机制，确保所有相关容器能够正确终止
  #
  # /semaphore/workload_terminated 工作机制：
  # 1. 这是一个共享卷中的信号文件（类似于信号量 semaphore）
  # 2. 当主容器完成工作时，创建此文件作为"完成信号"
  # 3. 其他 sidecar 容器（如 TCPx 网络优化容器）监控此文件
  # 4. 一旦检测到文件存在，sidecar 容器就知道可以安全退出
  # 5. 这确保了 Pod 中所有容器的协调终止，避免僵尸进程
  touch /semaphore/workload_terminated
}

# 捕获脚本退出信号，确保清理工作总是执行
trap on_script_completion EXIT
# 忽略 SIGPROF 信号（性能分析信号）
trap "" SIGPROF

# -----------------------------------------------------------------------------
# 2. 基本信息输出和环境检查
# -----------------------------------------------------------------------------

echo "Pod on $(hostname --fqdn) is running"
echo "Pod is assigned job index of $JOB_COMPLETION_INDEX"  # Kubernetes Job 中的 Pod 索引
echo "Job ID is $JOB_IDENTIFIER"  # 唯一的作业标识符

# -----------------------------------------------------------------------------
# 3. SSH 服务配置
# 用于节点间通信，MPI 需要通过 SSH 在不同节点间启动进程
# -----------------------------------------------------------------------------

mkdir /run/sshd  # 创建 SSH 守护进程运行目录
/usr/sbin/sshd -p 2222  # 在端口 2222 启动 SSH 服务（避免与主机 SSH 冲突）
echo "Pod has started SSH daemon"

# -----------------------------------------------------------------------------
# 4. GPU 环境检查和库配置
# -----------------------------------------------------------------------------

echo "The following GPUs are visible via nvidia-smi:"
nvidia-smi --list-gpus  # 列出可用的 GPU 设备

# 配置 NVIDIA 库路径，防止库加载错误
# 注意：这些配置可能在未来版本中变为可选
ldconfig /usr/local/nvidia/lib64/
echo "Added /usr/local/nvidia/lib64/ to ldconfig. Note:"
ldconfig -p | grep libcuda | sed 's/^/  /'  # 显示 CUDA 库的加载情况

# 重新挂载 /tmp 目录为可执行，某些操作需要在 /tmp 中执行文件
mount /tmp -o remount,exec 
chmod -R a+rwx /tmp  # 给所有用户读写执行权限

# -----------------------------------------------------------------------------
# 5. 存储和网络环境检查
# -----------------------------------------------------------------------------

# 在本地 SSD 上创建测试文件，验证存储可用性
touch $SSD_MOUNT_PATH/hello-from-$HOSTNAME.txt
echo "Local SSD contents (path $SSD_MOUNT_PATH):"; ls $SSD_MOUNT_PATH | sed 's/^/  /'

# 检查 GIB (Google InfiniBand) 网络栈的安装情况
echo "Contents (mounted at /usr/local/gib/):"
ls /usr/local/gib

echo "Contents (mounted at /usr/local/gib/lib64):"
ls /usr/local/gib/lib64

echo "Contents (mounted at /usr/local/gib/configs):"
ls /usr/local/gib/configs

# -----------------------------------------------------------------------------
# 6. NCCL 网络通信配置
# NCCL 是 NVIDIA 的集合通信库，用于多 GPU 间的高效通信
# -----------------------------------------------------------------------------

echo "Setting NCCL environment variables"
# 显示并执行 GIB 提供的 NCCL 环境配置脚本
cat /usr/local/gib/scripts/set_nccl_env.sh
source /usr/local/gib/scripts/set_nccl_env.sh

# 覆盖网络接口配置，指定使用 eth0 和 eth1 进行 NCCL 通信
echo "Overriding NCCL_SOCKET_IFNAME definition"
export NCCL_SOCKET_IFNAME="eth0,eth1"

# 配置动态库搜索路径，确保使用正确的 NCCL 库版本
export LD_LIBRARY_PATH="/third_party/nccl-netsupport/build/lib/:/usr/local/gib/lib64:/usr/local/nccl-plugin/lib64:/usr/local/nvidia/lib64/:${LD_LIBRARY_PATH}"
echo "Setting LD_LIBRARY_PATH=$LD_LIBRARY_PATH in an attempt to override the built-in NCCL library used!"

# -----------------------------------------------------------------------------
# 7. 可选的 GCS 存储挂载
# JIT (Just-In-Time) 挂载：在运行时动态挂载 Google Cloud Storage
# -----------------------------------------------------------------------------

if ! [ -z ${JIT_GCS_FUSE_BUCKET} ]; then
  echo "Got request to JIT mount GCS bucket $JIT_GCS_FUSE_BUCKET via 'gcsfuse' to $JIT_GCS_FUSE_MOUNT_PATH:"
  mkdir -p $JIT_GCS_FUSE_MOUNT_PATH
  # 使用 gcsfuse 将 GCS 存储桶挂载为本地文件系统
  gcsfuse --client-protocol http2 $JIT_GCS_FUSE_BUCKET $JIT_GCS_FUSE_MOUNT_PATH 
fi

# -----------------------------------------------------------------------------
# 8. 模型相关文件下载
# 下载 GPT-2 分词器文件（临时解决方案，未来可能移除）
# -----------------------------------------------------------------------------

echo "Downloading GPT vocabulary files"
wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json &&\
wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt

# -----------------------------------------------------------------------------
# 9. 训练配置和参数处理
# -----------------------------------------------------------------------------

echo "NeMo configuration file:"                                         
# 显示训练配置文件内容，每行前加 "| " 前缀便于识别
cat /etc/workload-configuration/nemo-configuration.yaml | sed 's/^/| /' 
echo ""

# 收集所有以 "WORKLOAD_" 开头的环境变量，转换为 NeMo 训练参数
#
# 详细步骤解析：
# 1. env                           - 列出所有环境变量
# 2. grep -e "^WORKLOAD_"          - 筛选出以 "WORKLOAD_" 开头的变量
# 3. sed 's/^WORKLOAD_/+/'         - 将 "WORKLOAD_" 前缀替换为 "+"
# 4. tr '\n' '\0'                  - 将换行符替换为 null 字符（处理包含空格的值）
# 5. readarray -d ""               - 使用 null 字符作为分隔符读入数组
#
# 示例转换：
# 环境变量: WORKLOAD_learning_rate=0.001
# 转换后:   +learning_rate=0.001
#
# 这样转换是因为 NeMo 使用 Hydra 配置系统，支持命令行覆盖参数的语法：
# python script.py +new_param=value  (添加新参数)
# python script.py param=value       (覆盖现有参数)
readarray -d "" workload_arguments < <(env | grep -e "^WORKLOAD_" | sed 's/^WORKLOAD_/+/' | tr '\n' '\0')
echo "Detected the following additional workload arguments:"            
for workload_argument in "${workload_arguments[@]}"; do                 
  echo "  $workload_argument"                                           
done 

# 等待其他服务完全启动
sleep 10 # <- Hack to allow some time for service to boot

# -----------------------------------------------------------------------------
# 10. 调试工具检查和安装
# -----------------------------------------------------------------------------

echo "Checking for presence of nsys:"  # NVIDIA Nsight Systems 性能分析工具
which nsys  

# 创建实验结果存储目录
echo "NeMo job artifacts will go to /gcs/nemo-experiments/$JOB_IDENTIFIER/"
mkdir -p /gcs/nemo-experiments/$JOB_IDENTIFIER/

# 安装调试和性能分析工具
echo "Installing debugging tools"
python -V
apt -y update && apt -y install gdb python3.12-dbg  # GDB 调试器和 Python 调试符号
pip install austin-dist austin-tui  # Python 性能分析工具

# -----------------------------------------------------------------------------
# 11. Tensorboard 服务启动（仅在主节点）
# -----------------------------------------------------------------------------

export NODE_RANK=$JOB_COMPLETION_INDEX  # 设置节点排名                               
# 如果是主节点（rank 0）且配置了 Tensorboard，则启动 Tensorboard 服务
if [ "$NODE_RANK" -eq "0" ] && { ! [ -z ${EMBEDDED_TENSORBOARD_TARGET} ]; }; then
  echo "Launching an embedded Tensorboard against log directory $EMBEDDED_TENSORBOARD_TARGET"
  tensorboard --logdir $EMBEDDED_TENSORBOARD_TARGET &  # 后台运行
fi

# =============================================================================
# 12. 分布式训练协调逻辑
# =============================================================================

# 只有主节点（索引为 0）负责协调整个分布式训练
if [ "$JOB_COMPLETION_INDEX" -eq "0" ]; then
  echo "Delaying 10 sec to allow SSH service to start"
  sleep 10

  # ---------------------------------------------------------------------------
  # 12.1 节点发现和连通性测试
  # ---------------------------------------------------------------------------
  
  echo "List of worker services:"
  # 遍历所有工作节点，建立 SSH 连接
  for JOB_INDEX in $(seq 0 $((NNODES-1))); do
    # 构造 Kubernetes 服务的 FQDN
    WORKER="$JOB_NAME-$JOB_INDEX.$JOB_NAME.default.svc.cluster.local"

    echo "  Ping $WORKER"
    # 测试 SSH 连接，获取远程主机名
    echo -n "  Pong "; ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -p 2222 $WORKER hostname
    ssh_exit_code=$?  # $? 是 bash 的特殊变量，保存上一个命令的退出状态码
                      # 0 表示成功，非 0 表示失败
    
    # 重试机制：如果连接失败（退出码非 0），每 2 秒重试一次
    while [ $ssh_exit_code -ne 0 ]; do
      echo "  (pong failed, retrying in 2 seconds)"
      sleep 2
      echo -n "  Pong "; ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -p 2222 $WORKER hostname 
      ssh_exit_code=$?
    done

    # ---------------------------------------------------------------------------
    # 12.2 物理拓扑发现
    # 查询每个节点的物理位置，用于优化通信拓扑
    # ---------------------------------------------------------------------------
    
    echo "  Querying $WORKER for VM physical location"
    # 通过 Google Cloud 元数据 API 获取物理主机信息
    LOCATION=$(ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -p 2222 $WORKER curl "-s" "-H" "\"Metadata-Flavor: Google\"" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/physical_host" )

    ssh_exit_code=$?  # 再次获取上一个 SSH 命令的退出状态码
    # 重试机制：确保能够获取到位置信息（如果 SSH 或 curl 命令失败）
    while [ $ssh_exit_code -ne 0 ]; do
      echo "  (query failed, retrying in 2 seconds)"
      sleep 2
      LOCATION=$(ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -p 2222 $WORKER curl "-s" "-H" "\"Metadata-Flavor: Google\"" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/physical_host" )
      ssh_exit_code=$?
    done

    echo "  Got $LOCATION"
    # 记录物理位置和主机名的映射关系
    echo "$LOCATION $WORKER" >> "/tmp/${JOB_NAME}-job-worker-locations.txt"

    # 配置 SSH 客户端，简化后续连接
    echo "Host $WORKER" >> /root/.ssh/config
    echo "  Port 2222" >> /root/.ssh/config
    echo "  StrictHostKeyChecking no" >> /root/.ssh/config
  done

  # ---------------------------------------------------------------------------
  # 12.3 拓扑优化排序
  # 根据物理位置对节点进行排序，优化网络通信效率
  # ---------------------------------------------------------------------------
  
  echo "Sorting VM list by physical location:"
  # 对节点按物理位置进行排序，优化网络通信拓扑
  #
  # 输入文件格式: "物理位置 主机名"，例如：
  # rack-1-host-3 worker-0.job.default.svc.cluster.local
  # rack-1-host-5 worker-1.job.default.svc.cluster.local
  # rack-2-host-1 worker-2.job.default.svc.cluster.local
  #
  # sort 命令会按第一列（物理位置）进行字典序排序
  # 这样相同机架或相近位置的节点会被排在一起，减少跨机架通信
  sort "/tmp/${JOB_NAME}-job-worker-locations.txt" > /tmp/job-worker-rank-order.txt

  cat /tmp/job-worker-rank-order.txt | sed 's/^/  /'
  # 生成 MPI hostfile，每个节点分配 8 个 slots（对应 8 个 GPU）
  # awk '{print $2}' 提取排序后的主机名（第二列）
  for WORKER in $(cat /tmp/job-worker-rank-order.txt | awk '{print $2}'); do
    echo "$WORKER slots=8" >> /etc/job-worker-services.txt
  done

  # ---------------------------------------------------------------------------
  # 12.4 环境变量收集
  # 收集所有 NCCL 相关的环境变量，传递给 MPI 进程
  # ---------------------------------------------------------------------------
  
  # 收集所有 NCCL 环境变量并转换为 MPI 参数格式
  #
  # 语法解析：
  # < <(...)           - 进程替换 (Process Substitution)
  #                      将命令的输出作为文件描述符传递给左边的命令
  #                      等价于创建一个临时的命名管道
  #
  # 步骤分解：
  # 1. env                    - 列出所有环境变量
  # 2. grep -e "^NCCL_"       - 筛选 NCCL 开头的变量
  # 3. sed 's/^/-x /'         - 在每行前加 "-x " (MPI 环境变量传递语法)
  # 4. tr '\n' '\0'           - 换行符转为 null 字符
  # 5. readarray -d ""        - 用 null 分隔符读入数组
  readarray -d "" nccl_environment < <(env | grep -e "^NCCL_" | sed 's/^/-x /' | tr '\n' '\0')
  
  echo "Detected NCCL environment:"
  # 数组遍历语法：
  # "${nccl_environment[@]}" - 展开数组的所有元素
  # [@] 表示数组的所有索引，等价于 [*] 但在引号内行为不同
  # [@] 会将每个元素作为独立的词，[*] 会将所有元素连接成一个词
  for nccl_variable in "${nccl_environment[@]}"; do
    echo "  $nccl_variable"
  done

  # ---------------------------------------------------------------------------
  # 12.5 构建工作进程命令
  # 每个 MPI 进程将执行的 Python 训练命令
  # ---------------------------------------------------------------------------
  
  worker_command="export RANK=\$OMPI_COMM_WORLD_RANK ;"  # MPI 全局排名
  worker_command+="export LOCAL_RANK=\$OMPI_COMM_WORLD_LOCAL_RANK ;"  # 节点内本地排名
  worker_command+="export HYDRA_FULL_ERROR=1 ;"  # 启用详细错误报告
  worker_command+="echo \"Worker has started with rank \$RANK and local rank \$LOCAL_RANK\" ;"
  # 启动 NeMo 训练脚本，传入配置文件和参数
  worker_command+="python $TORCH_DISTRIBUTED_TARGET \\"
  worker_command+="  --config-path=\"/etc/workload-configuration\" \\"
  worker_command+="  --config-name=\"nemo-configuration.yaml\" \\"
  worker_command+="  +trainer.num_nodes=\"$NNODES\" \\"
  worker_command+="  +exp_manager.version=\"$JOB_IDENTIFIER\" \\"
  worker_command+="  ${workload_arguments[@]}"

  # ---------------------------------------------------------------------------
  # 12.6 启动分布式训练
  # 使用 MPI 在所有节点上启动训练进程
  # ---------------------------------------------------------------------------
  
  echo "Launching MPI job across all hosts"
  # NVTE_UB_SOCKET_IFNAME: NVIDIA Transformer Engine 的 Userbuffers 网络接口配置
  #
  # 作用说明：
  # - NVTE (NVIDIA Transformer Engine) 是用于加速 Transformer 模型训练的库
  # - UB (Userbuffers) 是一种高性能的 GPU 间通信机制
  # - 该参数指定 Transformer Engine 使用哪个网络接口进行 GPU 间的直接通信
  #
  # 为什么设置为 "eth1"：
  # - eth0: 通常用于一般的网络通信和 NCCL 集合操作
  # - eth1: 专门用于 Transformer Engine 的 Userbuffers 通信
  # - 分离不同类型的网络流量，避免带宽竞争，提高训练性能
  #
  # 性能影响：
  # - 正确配置可以显著提升大模型训练的通信效率
  # - 特别是在多节点、多 GPU 的分布式训练场景中效果明显
  export NVTE_UB_SOCKET_IFNAME="eth1"
  
  # MCA (Modular Component Architecture) 参数说明：
  # --mca 是 OpenMPI 的模块化组件架构配置选项
  # 用于精细控制 MPI 运行时的各个组件行为
  
  mpirun \
    --allow-run-as-root \  # 允许以 root 用户运行
    -n "$((8*$NNODES))" \  # 总进程数 = 节点数 × 每节点 GPU 数
    --mca orte_keep_fqdn_hostnames t \  # ORTE 模块：保持完整域名（避免主机名解析问题）
    --mca plm_rsh_agent "ssh -q -o LogLevel=ERROR -o StrictHostKeyChecking=no -p 2222" \  # PLM 模块：指定 SSH 启动代理
    --hostfile /etc/job-worker-services.txt \  # 主机列表文件
    --mca btl_tcp_if_include $NCCL_SOCKET_IFNAME \  # BTL 模块：指定 TCP 通信接口
    --mca btl tcp,self \  # BTL 模块：启用 TCP 和本地回环通信
    -x LD_LIBRARY_PATH \  # 传递库路径
    -x MASTER_ADDR \      # 传递主节点地址
    -x MASTER_PORT \      # 传递主节点端口
    -x NNODES \           # 传递节点数
    -x GPUS_PER_NODE \    # 传递每节点 GPU 数
    -x GLOO_SOCKET_IFNAME \  # Gloo 后端网络接口
    -x PYTORCH_CUDA_ALLOC_CONF \  # CUDA 内存分配配置
    -x NVTE_FWD_LAYERNORM_SM_MARGIN \  # Transformer Engine 前向传播配置
    -x NVTE_BWD_LAYERNORM_SM_MARGIN \  # Transformer Engine 反向传播配置
    -x NVIDIA_PYTORCH_VERSION \  # PyTorch 版本信息
    -x NVTE_UB_SOCKET_IFNAME \   # Transformer Engine 网络接口
    ${nccl_environment[@]} \     # 所有 NCCL 环境变量
    bash -c "$worker_command"    # 执行工作进程命令
 
  # ---------------------------------------------------------------------------
  # 12.7 训练完成后的清理工作
  # 通知所有工作节点训练已完成，可以安全退出
  # ---------------------------------------------------------------------------
  
  echo "Informing all worker pods that the workload has terminated:"
  for JOB_INDEX in $(seq 0 $((NNODES-1))); do
    WORKER="$JOB_NAME-$JOB_INDEX.$JOB_NAME.default.svc.cluster.local"
    echo -n "  Write to $WORKER:/semaphore/workload_terminated to terminate worker: "
    # 在每个工作节点创建终止信号文件
    #
    # 信号文件机制详解：
    # 1. 主节点通过 SSH 在每个工作节点创建 /semaphore/workload_terminated 文件
    # 2. 这个文件作为"训练完成"的信号，通知工作节点可以安全退出
    # 3. 工作节点的等待循环会检测到这个文件并结束等待
    # 4. 确保分布式训练的所有节点能够协调一致地终止
    ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -p 2222 $WORKER touch /semaphore/workload_terminated
    if [ "$?" -eq 0 ]; then
      echo "success"
    else
      echo "failed"
    fi
  done

else
  # ---------------------------------------------------------------------------
  # 13. 工作节点等待逻辑
  # 非主节点等待主节点的终止信号
  # ---------------------------------------------------------------------------
  
  echo "Worker node waiting for termination signal from master..."
  # 持续检查终止信号文件，直到主节点创建该文件
  #
  # 等待机制详解：
  # 1. [ ! -e "/semaphore/workload_terminated" ] 检查文件是否不存在
  # 2. 如果文件不存在，继续等待（sleep 10 秒后再检查）
  # 3. 一旦主节点创建了这个文件，条件变为 false，退出循环
  # 4. 这确保工作节点不会在训练完成前提前退出
  # 5. 避免了分布式训练中的"僵尸节点"问题
  while [ ! -e "/semaphore/workload_terminated" ]; do
    sleep 10
  done
  echo "Received termination signal, worker node exiting..."
fi

echo "Pod on $(hostname --fqdn) is exiting"