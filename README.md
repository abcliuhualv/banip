用法: ./banip.sh [选项] <IP地址/网段>

选项:

  -ban, --block    封禁指定的IP地址/网段
  
  -unban, --unblock 解封指定的IP地址/网段
  
  -h, --help       显示此帮助信息

示例:

  ./banip.sh -ban 192.168.1.100
  
  ./banip.sh -ban 2001:db8::/32
  
  ./banip.sh -ban 192.168.1.0/24
  
  ./banip.sh -unban 192.168.1.100
  

支持的IP格式:

  - IPv4: 192.168.1.1, 192.168.1.0/24
  - 
  - IPv6: 2001:db8::1, 2001:db8::/32
  - 
