# FROM nvcr.io/nvidia/nemo:24.12
FROM nvcr.io/nvidia/nemo:25.02.rc4
WORKDIR /workspace

# GCSfuse components (used to provide shared storage, not intended for high performance)
RUN apt-get update && apt-get install --yes --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
  && echo "deb https://packages.cloud.google.com/apt gcsfuse-buster main" \
    | tee /etc/apt/sources.list.d/gcsfuse.list \
  && echo "deb https://packages.cloud.google.com/apt cloud-sdk main" \
    | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
  && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
  && apt-get update \
  && apt-get install --yes gcsfuse \
  && apt-get install --yes google-cloud-cli \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && mkdir /gcs
RUN pip install git+https://github.com/NVIDIA/dllogger#egg=dllogger

# RUN TORCH_CUDA_ARCH_LIST="9.0,10.0,12.0" pip install git+https://github.com/fanshiqing/grouped_gemm@v1.0

# Have an override for NCCL version 2.25.1 v1 for RAS feature
# ARG CUDA12_GENCODE='-gencode=arch=compute_90,code=sm_90'
# ARG CUDA12_PTX='-gencode=arch=compute_90,code=compute_90'

ARG CUDA13_GENCODE='-gencode=arch=compute_100,code=sm_100 -gencode=arch=compute_120,code=sm_120'
ARG CUDA13_PTX='-gencode=arch=compute_120,code=compute_120'

WORKDIR /third_party
RUN git clone https://github.com/NVIDIA/nccl.git nccl-netsupport && \
  cd nccl-netsupport && \
  git fetch --all --tags && \
  git checkout v2.25.1-1
WORKDIR nccl-netsupport
RUN make NVCC_GENCODE="$CUDA13_GENCODE $CUDA13_PTX" -j 16

# Make the pods capable of speaking to each other via SSH on port 222
RUN cd /etc/ssh/ && sed --in-place='.bak' 's/#Port 22/Port 222/' sshd_config && \
    sed --in-place='.bak' 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' sshd_config
RUN ssh-keygen -t rsa -b 4096 -q -f /root/.ssh/id_rsa -N ""
RUN touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
RUN cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

WORKDIR /workspace