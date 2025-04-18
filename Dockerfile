FROM debian:bookworm-slim

ARG NGROK_TOKEN
ARG REGION=ap
ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装必要组件并清理缓存
RUN apt update \
 && apt upgrade -y \
 && apt install -y \
    openssh-server \
    wget \
    unzip \
    vim \
    curl \
    python3 \
 && rm -rf /var/lib/apt/lists/*

# 2. 下载并解压 ngrok v3
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip \
    -O /ngrok.zip \
 && unzip /ngrok.zip -d / \
 && rm /ngrok.zip \
 && chmod +x /ngrok

# 3. 准备 SSHD 运行目录
RUN mkdir -p /run/sshd

# 4. 创建 entrypoint 脚本：启动 ngrok、打印 SSH 信息、再启动 sshd
RUN tee /entrypoint.sh << 'EOF'
#!/usr/bin/env bash

# 启动 ngrok TCP 隧道
/ngrok tcp --authtoken ${NGROK_TOKEN} --region ${REGION} 22 &

# 等待隧道就绪
sleep 5

# 查询 ngrok API 并打印 SSH 连接命令
curl -s http://localhost:4040/api/tunnels | python3 - << 'PYCODE'
import sys, json

data = json.load(sys.stdin)
tunnels = data.get('tunnels', [])
if not tunnels:
    print("Error：未能获取 ngrok 隧道信息，请检查 NGROK_TOKEN 或区域是否正确。", file=sys.stderr)
    sys.exit(1)

# public_url 格式 tcp://host:port
public_url = tunnels[0]['public_url']
host_port = public_url.split("://")[1]
host, port = host_port.split(":")

print("ssh info:")
print(f"  ssh root@{host} -p {port}")
print("ROOT Password: craxid")
PYCODE

# 启动 sshd
exec /usr/sbin/sshd -D
EOF

# 5. 配置 SSHD：允许 root 登录、设置 root 密码
RUN chmod +x /entrypoint.sh \
 && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
 && echo 'root:craxid' | chpasswd

# 6. 只暴露 ngrok 仪表盘和 SSH 端口
EXPOSE 4040 22

# 7. 使用 entrypoint 脚本启动容器
ENTRYPOINT ["/entrypoint.sh"]
