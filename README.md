# vps-allineone
serviee file

hysteria

/etc/systemd/system/h2server.service

caddy

/etc/systemd/system/caddy.service


cp caddy/caddy.service /etc/systemd/system/caddy.service

cp hysteria/h2server.service /etc/systemd/system/h2server.service

systemctl daemon-reload

systemctl enable caddy

systemctl enable h2server
