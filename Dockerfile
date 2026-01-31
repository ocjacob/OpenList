# ================= 第一阶段：编译 =================
ARG BASE_IMAGE_TAG=base
FROM alpine:edge AS builder
LABEL stage=go-builder
WORKDIR /app/

# 安装编译所需的依赖
RUN apk add --no-cache bash curl jq gcc git go musl-dev

# 处理依赖（利用缓存）
COPY go.mod go.sum ./
RUN go mod download

# 复制源码并执行编译脚本
COPY ./ ./
RUN bash build.sh release docker

# ================= 第二阶段：运行 =================
FROM openlistteam/openlist-base-image:${BASE_IMAGE_TAG}
LABEL MAINTAINER="OpenList"

# 设置工作目录
WORKDIR /opt/openlist/

# 切换到 root 用户以处理权限和目录创建
USER root

# 1. 创建数据目录
# 2. 赋予 777 权限以兼容 Hugging Face 的持久化存储挂载
# 3. 将所有权移交给 Hugging Face 默认用户 (UID 1000)
RUN mkdir -p /opt/openlist/data && \
    chmod -R 777 /opt/openlist/data && \
    chown -R 1000:1000 /opt/openlist/data

# 从编译阶段复制二进制文件
# 注意：去掉原来的 --chown=1001:1001，改为 1000:1000
COPY --from=builder --chmod=755 /app/bin/openlist ./
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# 修正权限：确保 entrypoint 和程序可执行
RUN chmod +x /entrypoint.sh ./openlist && \
    chown 1000:1000 /entrypoint.sh ./openlist

# 环境变量设置
# 强制程序监听 Hugging Face 指定的 7860 端口
ENV PORT=7860
ENV UMASK=022
ENV RUN_ARIA2=false

# 暴露端口（虽然 HF 主要看 7860，但显式声明是个好习惯）
EXPOSE 7860

# 切换到 Hugging Face 强制要求的非 root 用户
USER 1000

# 启动命令：直接调用 server 并指定端口
# 这样可以绕过某些 entrypoint.sh 脚本中可能存在的 sudo 或 adduser 报错
CMD ["./openlist", "server", "--port", "7860"]
