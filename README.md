# vps-allineone
安装caddy提供的http2 naiveproxy   
安装hysteria提供的hystera2(h2)   
最好一台主机两种协议都提供，有些情况udp不是稳定  


## step1 准备文件  
git clone git@github.com:hi-wayne/vps-allineone.git  
cd vps-allineone  
mkdir -p /data  
cp -R caddy /data/caddy  
cp -R hysteria /data/hysteria  
cp /data/caddy/caddy.service /etc/systemd/system/caddy.service  
cp /data/hysteria/h2server.service /etc/systemd/system/h2server.service  


## step2 修改配置文件和添加解析      
一台机器可以用通一个域名支持caddy h2和hystera2两种协议然后分别工作在不同端口   

vim /data/caddy/Caddyfile  
按文件中中文解释部分进行修改  
如果你的vps有ipv6可以给机器分别设置a和aaaa两个域名  
注意你需要先把域名指向到vps，caddy会自动通过acme letsencrypt生产https证书  

vim  /data/hysteria/server.yaml  
按文件中中文解释部分进行修改  


## step3 启动服务开机后台运行   
systemctl daemon-reload   
systemctl enable caddy   
systemctl enable h2server    
systemctl restart caddy   
systemctl restart h2server   

## linux主机链接国外vps的hysteria2(h2)后提供socket5和http代理  
cp -R h2client /data/h2client
cp /data/h2cleint/h2h2client.service /etc/systemd/system/h2client.service  
vim /data/h2client/client.yaml
systemctl daemon-reload   
systemctl enable h2client  
systemctl restart h2client  
不方便安装h2 client的设备可以在chrome上安装创建使用socket5进行分流代理。 
插件推荐  
https://chromewebstore.google.com/detail/proxy-switchyomega-3-zero/pfnededegaaopdmhkdmcofjmoldfiped?hl=zh-CN   


## btw:     
查看运行状态   
systemctl status caddy   
systemctl status h2server    
如果发现状态不正常关闭服务后手动拉起服务看看输出日志   
systemctl stop caddy   
systemctl stop h2server    
手动拉起   
/data/caddy/caddy run --config /data/caddy/Caddyfile  
/data/hysteria/hysteria-linux-amd64 server -c /data/hysteria/server.yaml  

## vps推荐  
dmit premium网络带cn2优化，eyeball带cmin2优化  
邀请注册。
https://www.dmit.io/aff.php?aff=12025 


