#!/bin/bash
# BanIP.sh - unRAID IP封禁脚本
# 功能: 封禁和解封IPv4/IPv6地址或网段，处理入站和出站流量

# 脚本配置
VERSION="1.0"
#BAN_LOG="/mnt/user/appdata/banip/banip.log"
BAN_LOG="./banip.log"
IPTABLES_V4="/usr/sbin/iptables"
IPTABLES_V6="/usr/sbin/ip6tables"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$BAN_LOG"
    echo "$1"
}

# 显示用法
usage() {
    echo "用法: $0 [选项] <IP地址/网段>"
    echo "选项:"
    echo "  -ban, --block    封禁指定的IP地址/网段"
    echo "  -unban, --unblock 解封指定的IP地址/网段"
    echo "  -h, --help       显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -ban 192.168.1.100"
    echo "  $0 -ban 2001:db8::/32"
    echo "  $0 -ban 192.168.1.0/24"
    echo "  $0 -unban 192.168.1.100"
    echo ""
    echo "支持的IP格式:"
    echo "  - IPv4: 192.168.1.1, 192.168.1.0/24"
    echo "  - IPv6: 2001:db8::1, 2001:db8::/32"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限执行${NC}"
        exit 1
    fi
}

# 检查iptables是否存在
check_iptables() {
    if [[ ! -x "$IPTABLES_V4" ]]; then
        echo -e "${RED}错误: iptables未找到${NC}"
        exit 1
    fi
    
    if [[ ! -x "$IPTABLES_V6" ]]; then
        echo -e "${RED}错误: ip6tables未找到${NC}"
        exit 1
    fi
}

# 验证IP地址格式
validate_ip() {
    local ip="$1"
    
    # 检查是否是IPv4地址或网段
    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ ]]; then
        return 0
    fi
    
    # 检查是否是IPv6地址或网段
    if [[ "$ip" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]]; then
        return 0
    fi
    
    return 1
}

# 获取IP类型 (IPv4/IPv6)
get_ip_type() {
    local ip="$1"
    
    if [[ "$ip" =~ .*:.* ]]; then
        echo "IPv6"
    else
        echo "IPv4"
    fi
}

# 检查规则是否存在
rule_exists() {
    local ip="$1"
    local iptables_cmd="$2"
    
    if $iptables_cmd -L INPUT -n | grep -q "$ip"; then
        return 0
    fi
    if $iptables_cmd -L OUTPUT -n | grep -q "$ip"; then
        return 0
    fi
    return 1
}

# 封禁IP
ban_ip() {
    local ip="$1"
    local ip_type=$(get_ip_type "$ip")
    local iptables_cmd="$IPTABLES_V4"
    
    if [[ "$ip_type" == "IPv6" ]]; then
        iptables_cmd="$IPTABLES_V6"
    fi
    
    # 检查是否已封禁
    if rule_exists "$ip" "$iptables_cmd"; then
        echo -e "${YELLOW}警告: IP地址 $ip 已被封禁${NC}"
        return 0
    fi
    
    # 封禁入站和出站流量[1,8](@ref)
    $iptables_cmd -I INPUT -s "$ip" -j DROP
    $iptables_cmd -I OUTPUT -d "$ip" -j DROP
    $iptables_cmd -I FORWARD -s "$ip" -j DROP
    $iptables_cmd -I FORWARD -d "$ip" -j DROP
    
    if [[ $? -eq 0 ]]; then
        log_action "封禁成功: $ip (类型: $ip_type)"
        echo -e "${GREEN}✓ 成功封禁IP地址: $ip${NC}"
        
        # 显示当前规则
        echo -e "${YELLOW}当前封禁规则:${NC}"
        $iptables_cmd -L INPUT -n | grep "$ip" || true
        $iptables_cmd -L OUTPUT -n | grep "$ip" || true
    else
        log_action "封禁失败: $ip (类型: $ip_type)"
        echo -e "${RED}✗ 封禁IP地址失败: $ip${NC}"
        return 1
    fi
}

# 解封IP
unban_ip() {
    local ip="$1"
    local ip_type=$(get_ip_type "$ip")
    local iptables_cmd="$IPTABLES_V4"
    
    if [[ "$ip_type" == "IPv6" ]]; then
        iptables_cmd="$IPTABLES_V6"
    fi
    
    # 检查是否已封禁
    if ! rule_exists "$ip" "$iptables_cmd"; then
        echo -e "${YELLOW}警告: IP地址 $ip 未被封禁${NC}"
        return 0
    fi
    
    # 删除封禁规则[9](@ref)
    $iptables_cmd -D INPUT -s "$ip" -j DROP 2>/dev/null || true
    $iptables_cmd -D OUTPUT -d "$ip" -j DROP 2>/dev/null || true
    $iptables_cmd -D FORWARD -s "$ip" -j DROP 2>/dev/null || true
    $iptables_cmd -D FORWARD -d "$ip" -j DROP 2>/dev/null || true
    
    log_action "解封成功: $ip (类型: $ip_type)"
    echo -e "${GREEN}✓ 成功解封IP地址: $ip${NC}"
}

# 显示封禁列表
list_banned_ips() {
    echo -e "${YELLOW}当前封禁的IPv4地址:${NC}"
    $IPTABLES_V4 -L INPUT -n | grep DROP | grep -v "0.0.0.0/0" || echo "无"
    
    echo -e "${YELLOW}当前封禁的IPv6地址:${NC}"
    $IPTABLES_V6 -L INPUT -n | grep DROP | grep -v "::/0" || echo "无"
}

# 主函数
main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    # 检查前置条件
    check_root
    check_iptables
    
    local action=""
    local ip_address=""

    # 解析参数
    case "$1" in
        -ban|--block)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}错误: 请提供要封禁的IP地址${NC}"
                exit 1
            fi
            ip_address="$2"
            ;;
        -unban|--unblock)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}错误: 请提供要解封的IP地址${NC}"
                exit 1
            fi
            ip_address="$2"
            ;;
        -list|--list)
            list_banned_ips
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}错误: 未知参数 '$1'${NC}"
            usage
            exit 1
            ;;
    esac

    # 验证IP地址格式
    if ! validate_ip "$ip_address"; then
        echo -e "${RED}错误: IP地址格式无效 '$ip_address'${NC}"
        echo "请提供有效的IPv4/IPv6地址或网段"
        exit 1
    fi

    # 执行相应操作
    case "$1" in
        -ban|--block)
            ban_ip "$ip_address"
            ;;
        -unban|--unblock)
            unban_ip "$ip_address"
            ;;
    esac
}

# 脚本初始化
if [[ ! -f "$BAN_LOG" ]]; then
    touch "$BAN_LOG"
    chmod 644 "$BAN_LOG"
fi

# 运行主函数
main "$@"