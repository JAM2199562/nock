#!/bin/bash

set -e

# 设置 GitHub 代理
GITHUB_PROXY="https://ghproxy.nyxyy.org/"

echo -e "\n🔧 配置 needrestart 自动重启服务..."
# 安装 needrestart
apt-get update && apt-get install -y needrestart

# 配置 needrestart 自动重启
if [ -f "/etc/needrestart/needrestart.conf" ]; then
    # 备份原配置文件
    cp /etc/needrestart/needrestart.conf /etc/needrestart/needrestart.conf.bak
    # 修改配置为自动重启（使用更精确的匹配模式）
    sed -i '/^#\$nrconf{restart} = '"'"'i'"'"';/c\$nrconf{restart} = '"'"'a'"'"';' /etc/needrestart/needrestart.conf
    echo "✅ needrestart 已配置为自动重启模式"
else
    echo "⚠️ 未找到 needrestart 配置文件，跳过配置"
fi

echo -e "\n📦 正在更新系统并安装依赖..."
apt-get update && apt install sudo -y
sudo apt install -y screen curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip

echo -e "\n🔧 检查并安装 chsrc 换源工具..."
if ! command -v chsrc &> /dev/null; then
    echo "未找到 chsrc，开始安装..."
    CHSRC_PROXY="${GITHUB_PROXY}https://raw.githubusercontent.com/RubyMetric/chsrc/main/tool/installer.sh"
    curl -L "$CHSRC_PROXY" | bash -s -- -d /usr/local/bin
else
    echo "chsrc 已安装，跳过安装步骤"
fi

echo -e "\n🦀 安装 Rust..."
# 设置 RUSTUP 镜像源为中科大源
export RUSTUP_DIST_SERVER="https://mirrors.ustc.edu.cn/rust-static"
export RUSTUP_UPDATE_ROOT="https://mirrors.ustc.edu.cn/rust-static/rustup"

# 安装 Rust
curl --proto '=https' --tlsv1.2 -sSf https://mirrors.ustc.edu.cn/rust-static/rustup/rustup-init.sh | sh -s -- -y
source "$HOME/.cargo/env"

echo -e "\n📝 配置 hosts 记录..."
echo "104.18.34.128 ghproxy.nyxyy.org" >> /etc/hosts

# 使用 chsrc 配置 Cargo 镜像源
echo -e "\n📡 配置 Cargo 镜像源..."
# 删除可能存在的旧配置文件
rm -f ~/.cargo/config

mkdir -p ~/.cargo
cat > ~/.cargo/config.toml << EOF
[source.crates-io]
replace-with = 'mirror'

[source.mirror]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"

[net]
git-fetch-with-cli = true

[http]
check-revoke = false

[registries.mirror]
index = "https://mirrors.ustc.edu.cn/crates.io-index"

[source.github]
git = "https://github.com"
replace-with = 'github-mirror'

[source.github-mirror]
git = "https://ghproxy.nyxyy.org/https://github.com"
EOF

# 使用 chsrc 设置为 ustc 源（中科大源）
chsrc set cargo ustc

rustup default stable

echo -e "\n📁 检查 nockchain 仓库..."
# 设置 GitHub 代理
GITHUB_PROXY="https://ghproxy.nyxyy.org/"
REPO_URL="${GITHUB_PROXY}https://github.com/zorp-corp/nockchain"

if [ -d "nockchain" ]; then
  echo "⚠️ 已存在 nockchain 目录，是否删除重新克隆（必须选 y ）？(y/n)"
  read -r confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf nockchain
    git clone --depth 1 "$REPO_URL"
  else
    echo "➡️ 使用已有目录 nockchain"
  fi
else
  git clone --depth 1 "$REPO_URL"
fi

cd nockchain

echo -e "\n🔧 开始编译核心组件..."
make install-hoonc
make build
make install-nockchain-wallet
make install-nockchain

echo -e "\n✅ 编译完成，配置环境变量..."
echo 'export PATH="$PATH:/root/nockchain/target/release"' >> ~/.bashrc
echo 'export RUST_LOG=info' >> ~/.bashrc
echo 'export MINIMAL_LOG_FORMAT=true' >> ~/.bashrc
source ~/.bashrc

# === 生成钱包 ===
echo -e "\n🔐 自动生成钱包助记词与主私钥..."
WALLET_CMD="./target/release/nockchain-wallet"
if [ ! -f "$WALLET_CMD" ]; then
  echo "❌ 未找到钱包命令 $WALLET_CMD"
  exit 1
fi

SEED_OUTPUT=$($WALLET_CMD keygen)
echo "$SEED_OUTPUT"

SEED_PHRASE=$(echo "$SEED_OUTPUT" | grep -i "memo:" | sed 's/.*memo: //')
echo -e "\n🧠 助记词：$SEED_PHRASE"

echo -e "\n🔑 从助记词派生主私钥..."
MASTER_PRIVKEY=$(echo "$SEED_OUTPUT" | grep -A1 "New Private Key" | tail -n1 | sed 's/"//g')
echo "主私钥：$MASTER_PRIVKEY"

echo -e "\n📬 获取主公钥..."
MASTER_PUBKEY=$(echo "$SEED_OUTPUT" | grep -A1 "New Public Key" | tail -n1 | sed 's/"//g')
echo "主公钥：$MASTER_PUBKEY"

echo -e "\n📄 写入 Makefile 挖矿公钥..."
sed -i "s|^export MINING_PUBKEY :=.*$|export MINING_PUBKEY := $MASTER_PUBKEY|" Makefile

# === 可选：初始化 choo hoon 测试 ===
read -p $'\n🌀 是否执行 choo 初始化测试？这一步可能卡住界面，非必须操作。输入 y 继续：' confirm_choo
if [[ "$confirm_choo" == "y" || "$confirm_choo" == "Y" ]]; then
  mkdir -p hoon assets
  echo "%trivial" > hoon/trivial.hoon
  choo --new --arbitrary hoon/trivial.hoon
fi

# === 启动指引 ===
echo -e "\n🚀 配置完成，启动命令如下："

echo -e "\n➡️ 启动 leader 节点："
echo -e "screen -S leader\nmake run-nockchain-leader"

echo -e "\n➡️ 启动 follower 节点："
echo -e "screen -S follower\nmake run-nockchain-follower"

echo -e "\n📄 查看日志方法："
echo -e "screen -r leader   # 查看 leader 日志"
echo -e "screen -r follower # 查看 follower 日志"
echo -e "Ctrl+A 再按 D 可退出 screen 会话"

echo -e "\n🎉 部署完成，祝你挖矿愉快！"

# 修改 Cargo 配置中的 GitHub 链接也使用代理
# 删除这段重复的配置
# mkdir -p ~/.cargo
# cat > ~/.cargo/config << EOF
# [source.crates-io]
# registry = "${GITHUB_PROXY}https://github.com/rust-lang/crates.io-index"
# replace-with = 'ustc'
# 
# [source.ustc]
# registry = "git://mirrors.ustc.edu.cn/crates.io-index"
# EOF

