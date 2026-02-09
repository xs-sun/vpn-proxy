# vpn-proxy
vpn 隧道工具
利用`tun2socks` 工具来解决有些公司内网 vpn 不能在 mac 电脑上使用的问题。
## 解决了些什么？
在使用 mac 电脑办公时，公司内网vpn 客户端只支持 windows 电脑，于是开发了这个脚本，利用脚本创建一个 tun 网络接口，
开启代理工具后，所有内网流量统一从这个 tun 接口流向指定 ip (windows) 的端口。
> 需要在 windows 电脑上开放一个隧道端口，用来接收来自 隧道的流量。可以利用 v2rayN 等工具，开放局域网端口

## 如何使用？
直接 clone 本项目，或下载源码后，先给 proxy.sh 脚本赋予可执行权限。
用法: 
``` bash
sudo ./proxy.sh {start|stop|restart|status|install|uninstall|clean}
```

然后 执行 `install` 可以直接安装成全局命令。
``` shell
sudo ./proxy.sh install
```

全局命令为
```
sudo vproxy [start|stop|restart|status|install|uninstall|clean]
```