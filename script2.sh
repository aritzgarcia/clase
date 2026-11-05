sudo bash <<'VERIFY'
echo "----- 2) Ocultar IP -----"
grep -qE '\\4|\\6' /etc/issue && echo "[FAIL] revela IP" || echo "[OK] issue sin IP"
sed 's/^/   /' /etc/issue
echo "----- 3) Usuarios -----"
id admin
echo "----- 5) Hash de root -----"
ls -l /var/backups/password.bak
grep -i password /var/backups/password.bak
cat /var/backups/password.bak
echo "sha256(superman) = $(printf '%s' superman | sha256sum | awk '{print $1}')"
echo "----- 6) flag.txt -----"
ls -l /root/flag.txt
echo "----- 7/8) Servicios -----"
for s in ssh vsftpd apache2 mariadb; do printf "   %-10s %s\n" "$s" "$(systemctl is-active $s)"; done
echo "----- Puertos -----"
ss -tlnp | grep -E ':(21|22|80|3306)\b'
echo "----- Web portal -----"
curl -s -o /dev/null -w "   portal -> %{http_code}\n" http://localhost/portal/
echo "----- IP real (DHCP) -----"
ip -4 addr show | grep inet
VERIFY
