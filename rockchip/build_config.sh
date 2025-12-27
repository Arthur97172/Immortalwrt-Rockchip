#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
# yml 传入的固件大小 ROOTFS_PARTSIZE
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # 下载 run 文件仓库
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

  # 拷贝 run/arm64 下所有 run 文件和ipk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run
  # 解压并拷贝ipk到packages目录
  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
  # 添加架构优先级信息
  sed -i '1i\
  arch aarch64_generic 10\n\
  arch aarch64_cortex-a53 15' repositories.conf
fi


# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
echo "查看repositories.conf信息——————"
cat repositories.conf
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""

# --- 基础系统与核心依赖 ---
PACKAGES="base-files libc libgcc uci ubus dropbear logd mtd opkg bash htop curl wget-ssl ca-bundle ca-certificates"

# --- 磁盘与文件系统支撑 (适配 USB 3.0/SATA/M.2 接口) ---
PACKAGES="$PACKAGES block-mount fdisk lsblk blkid parted resize2fs smartmontools"
PACKAGES="$PACKAGES kmod-fs-ext4 kmod-fs-vfat kmod-fs-ntfs3 kmod-fs-exfat kmod-fs-btrfs kmod-fs-f2fs kmod-fs-nfs kmod-fs-nfsd"
PACKAGES="$PACKAGES kmod-usb-storage kmod-usb-storage-uas kmod-usb-ohci kmod-usb-uhci kmod-usb2 kmod-usb3"

# --- 瑞芯微硬件相关驱动 (板载以太网/SD卡/SATA) ---
PACKAGES="$PACKAGES kmod-dwmac-rockchip kmod-ata-ahci kmod-ata-dwc kmod-mmc kmod-r8125 kmod-r8168 kmod-r8169"

# --- 增强型 USB 有线网卡支持 (绿联/TP-LINK/2.5G 网口扩展) ---
PACKAGES="$PACKAGES kmod-usb-net kmod-usb-net-asix-ax88179 kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 r8152-firmware"
PACKAGES="$PACKAGES kmod-usb-net-cdc-ether kmod-usb-net-cdc-mbim kmod-usb-net-cdc-ncm kmod-usb-net-qmi-wwan"

# --- 增强型 USB/板载 无线网卡支持 ---
PACKAGES="$PACKAGES kmod-rtw88-8822ce kmod-rtw88-8821ce kmod-rtw88-8821cu kmod-rtw88-8822cu"
PACKAGES="$PACKAGES kmod-mt7921e kmod-mt7921u kmod-mt76x2u kmod-ath10k"

# --- 网络核心 (强制替换默认 dnsmasq 为 full 版以支持更多功能) ---
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full firewall4 nftables kmod-nft-offload"
PACKAGES="$PACKAGES ip-full ipset iw info ppp ppp-mod-pppoe ethertypes"

# --- Docker 支持 (Rockchip 性能强劲，Docker 是核心玩法) ---
# 使用 docker-ce 是目前最稳妥的选择
PACKAGES="$PACKAGES docker-ce dockerd luci-app-dockerman luci-i18n-dockerman-zh-cn"

# --- 应用层与常用插件 ---
PACKAGES="$PACKAGES luci luci-base luci-compat luci-mod-admin-full"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-app-cpufreq luci-i18n-cpufreq-zh-cn"
PACKAGES="$PACKAGES luci-app-ttyd luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-app-samba4 luci-i18n-samba4-zh-cn"
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn"
PACKAGES="$PACKAGES luci-app-wol luci-i18n-wol-zh-cn"
PACKAGES="$PACKAGES luci-app-ddns luci-i18n-ddns-zh-cn"
PACKAGES="$PACKAGES luci-app-diskman luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-app-hd-idle luci-i18n-hd-idle-zh-cn"

# --- 核心网络安全与工具 ---
# 确保使用 wpad-openssl 提供完整的 WiFi 加密支持
PACKAGES="$PACKAGES wpad-openssl"

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    # 一次性添加：引擎(docker-ce) + 守护进程(dockerd) + 界面(dockerman) + 中文包
    PACKAGES="$PACKAGES docker-ce dockerd luci-app-dockerman luci-i18n-dockerman-zh-cn"
    
    # 额外补充：Docker 通常需要 cgroup 支持和辅助库
    PACKAGES="$PACKAGES luci-lib-docker libnetwork"
    
    echo "Successfully added all Docker related packages to the list."
fi

# 文件管理器
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
# 静态文件服务器dufs(推荐)
PACKAGES="$PACKAGES luci-i18n-dufs-zh-cn"
# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi


make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
