# vps-allineone
安装caddy提供的http2 naiveproxy   
安装hysteria提供的htstera2   


step1 准备文件  
git clone git@github.com:hi-wayne/vps-allineone.git  
cd vps-allineone  
mkdir -p /data  
cp -R caddy /data/caddy  
cp -R hysteria /data/hysteria  
cp /data/caddy/caddy.service /etc/systemd/system/caddy.service  
cp /data/hysteria/h2server.service /etc/systemd/system/h2server.service  


step2 修改配置文件和添加解析    
修改/data/caddy/Caddyfile文件中domain.com和basic_auth部分，其中domain.com改为自己持有的一个域名并且解析到vps，caddy会自动通过acme letsencrypt生产https证书,端口8443也可以按自己要求修改  
修改/data/hysteria/server.yaml中domain.com和password两个部分，端口443你也可以按要求修改，域名名也需要解析到这个vps  
一台机器可以用通一个域名支持caddy h2和hystera2两种协议然后分别工作在不同端口   


step3 启动服务   
systemctl daemon-reload   
systemctl enable caddy   
systemctl enable h2server    
systemctl restart caddy   
systemctl restart h2server   


btw:     
查看运行状态   
systemctl status caddy   
systemctl status h2server    
如果发现状态不正常关闭服务后手动拉起服务看看输出日志   
systemctl stop caddy   
systemctl stop h2server    
手动拉起   
/data/caddy/caddy run --config /data/caddy/Caddyfile  
/data/hysteria/hysteria-linux-amd64 server -c /data/hysteria/server.yaml  

vps推荐  
dmit premium网络带cn2优化， eyeball带cmin2 优化  
邀请注册。
https://www.dmit.io/aff.php?aff=12025 


