#!/usr/bin/env bash
# ============================================================================
#  setup_maquina_vulnerable.sh
#  Practica Hacking Etico (Egibide) — Aritz Garcia (AG)
#
#  Aprovisiona la MAQUINA VULNERABLE (Debian 12 "bookworm").
#  SOLO para laboratorio en red aislada (NAT). NO exponer a Internet.
#
#  Uso:
#     sudo bash setup_maquina_vulnerable.sh 2>&1 | tee salida.txt
#  Luego pega el contenido de salida.txt para la verificacion.
#
#  Partes que NO cubre (se hacen en pasos guiados aparte):
#     - Red NAT (se configura en el virtualizador)
#     - Backdoor vsftpd 2.3.4 (CVE-2011-2523)
#     - SUID de escalada de privilegios
#     - Escaneo con OpenVAS/Greenbone
# ============================================================================

# -------------------- CONFIGURACION (edita si quieres) ----------------------
USER_ADMIN="admin"          # usuario "tipico" de entrada por SSH
PASS_ADMIN="admin"          # contrasena tipica (en cualquier diccionario)
ROOT_PASS="superman"        # pass de root (esta en password.lst y rockyou)
BACKUP_FILE="/var/backups/password.bak"   # fichero con la palabra 'password'
FLAG_FILE="/root/flag.txt"
WEB_DIR="/var/www/html/portal"
# ----------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

# -------------------- Helpers de log ----------------------------------------
c_ok()   { echo -e "[\e[32m OK \e[0m] $*"; }
c_warn() { echo -e "[\e[33mWARN\e[0m] $*"; }
c_err()  { echo -e "[\e[31mFAIL\e[0m] $*"; }
c_step() { echo -e "\n\e[36m===== $* =====\e[0m"; }

# -------------------- 0. Comprobaciones previas -----------------------------
if [ "$(id -u)" -ne 0 ]; then
  c_err "Hay que ejecutarlo como root:  sudo bash $0"
  exit 1
fi
c_step "0. Comprobaciones previas"
. /etc/os-release 2>/dev/null
echo "Distro: ${PRETTY_NAME:-desconocida}"
c_ok "Ejecutando como root"

# -------------------- 1. Instalacion de paquetes ----------------------------
c_step "1. Instalando paquetes necesarios"
apt-get update -y
if apt-get install -y openssh-server vsftpd apache2 libapache2-mod-php \
        php php-mysql mariadb-server curl; then
  c_ok "Paquetes instalados"
else
  c_err "Fallo al instalar paquetes (revisa la conexion a Internet de la VM)"
fi

# -------------------- 2. Ocultar la IP en el arranque -----------------------
c_step "2. Ocultando la IP en el login (/etc/issue)"
cp -n /etc/issue /etc/issue.bak 2>/dev/null
cat > /etc/issue <<'EOF'
***  ACCESO RESTRINGIDO - Laboratorio Hacking Etico  ***
Debian GNU/Linux \n \l

EOF
cp -n /etc/issue.net /etc/issue.net.bak 2>/dev/null
printf '***  ACCESO RESTRINGIDO  ***\n' > /etc/issue.net

if grep -qE '\\4|\\6' /etc/issue /etc/issue.net; then
  c_err "El issue todavia contiene codigos de IP (\\4/\\6)"
else
  c_ok "El issue NO revela la IP"
fi

# MOTD dinamico: avisar si algun script muestra la IP
if ls /etc/update-motd.d/* >/dev/null 2>&1; then
  if grep -rliE 'hostname -I|ip (a|addr)|\$\(ip' /etc/update-motd.d/ >/dev/null 2>&1; then
    c_warn "Hay scripts en /etc/update-motd.d que podrian mostrar la IP (revisar)"
  else
    c_ok "MOTD dinamico sin referencias a la IP"
  fi
else
  c_ok "Sin MOTD dinamico"
fi

# -------------------- 3. Usuarios y contrasenas -----------------------------
c_step "3. Usuarios y contrasenas"
if id "$USER_ADMIN" &>/dev/null; then
  c_ok "El usuario $USER_ADMIN ya existe"
else
  useradd -m -s /bin/bash "$USER_ADMIN" && c_ok "Creado usuario $USER_ADMIN"
fi
echo "${USER_ADMIN}:${PASS_ADMIN}" | chpasswd && c_ok "Pass de $USER_ADMIN = $PASS_ADMIN"
echo "root:${ROOT_PASS}" | chpasswd && c_ok "Pass de root = $ROOT_PASS"

# Nos aseguramos de que admin NO tenga sudo (si no, se salta el crackeo de root)
if id -nG "$USER_ADMIN" | grep -qw sudo; then
  deluser "$USER_ADMIN" sudo && c_warn "Quitado $USER_ADMIN del grupo sudo"
fi

# -------------------- 4. SSH con autenticacion por contrasena ---------------
c_step "4. Configurando SSH"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
if [ -d /etc/ssh/sshd_config.d ]; then
  echo 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/99-lab.conf
fi
systemctl enable --now ssh >/dev/null 2>&1
systemctl restart ssh && c_ok "SSH activo con PasswordAuthentication yes"

# -------------------- 5. Fichero oculto con el hash de root -----------------
c_step "5. Fichero con el hash de root (palabra clave 'password')"
HASH_ROOT=$(printf '%s' "$ROOT_PASS" | sha256sum | awk '{print $1}')
mkdir -p "$(dirname "$BACKUP_FILE")"
cat > "$BACKUP_FILE" <<EOF
# Backup de credenciales del sistema - NO DISTRIBUIR
#
# root password (cifrada con SHA-256):
${HASH_ROOT}
EOF
chmod 644 "$BACKUP_FILE"
chown root:root "$BACKUP_FILE"
c_ok "Creado $BACKUP_FILE  (SHA-256 de '$ROOT_PASS')"
echo "       hash = $HASH_ROOT"

# -------------------- 6. flag.txt en /root ----------------------------------
c_step "6. flag.txt en /root"
cat > "$FLAG_FILE" <<'EOF'
FLAG{R00T_C0NSEGU1D0_AG}

Enhorabuena: has conseguido privilegios de root en la maquina.
Practica de Hacking Etico - Aritz Garcia (AG)
EOF
chmod 600 "$FLAG_FILE"
chown root:root "$FLAG_FILE"
c_ok "Creado $FLAG_FILE (solo lo lee root)"

# -------------------- 7. FTP anonimo (vsftpd del repo) ----------------------
c_step "7. FTP con login anonimo (vsftpd)"
cp -n /etc/vsftpd.conf /etc/vsftpd.conf.bak 2>/dev/null
cat > /etc/vsftpd.conf <<'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=YES
local_enable=YES
write_enable=NO
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
anon_root=/srv/ftp
no_anon_password=YES
EOF
mkdir -p /srv/ftp/pub
cat > /srv/ftp/pub/leeme.txt <<'EOF'
El portal web guarda credenciales en su base de datos...
y los backups del sistema (/var/backups) tambien son interesantes ;)
EOF
chown -R ftp:ftp /srv/ftp 2>/dev/null || true
chmod -R 555 /srv/ftp
systemctl enable --now vsftpd >/dev/null 2>&1
systemctl restart vsftpd && c_ok "vsftpd activo con anonymous_enable=YES"

# -------------------- 8. Servidor web + portal SQLi -------------------------
c_step "8. Servidor web + portal vulnerable (SQLi)"
systemctl enable --now mariadb >/dev/null 2>&1
systemctl enable --now apache2 >/dev/null 2>&1
mkdir -p "$WEB_DIR"

# --- index.php (login vulnerable a SQLi) ---
cat > "$WEB_DIR/index.php" <<'PHP'
<?php
// Portal de Acceso - DELIBERADAMENTE VULNERABLE (SQLi). Solo laboratorio.
ini_set('display_errors', 1);
error_reporting(E_ALL);
$con = mysqli_connect('localhost', 'webapp', 'webapp123', 'portal');
if (!$con) { die('Error de conexion a la BBDD: ' . mysqli_connect_error()); }
$ok=false; $mensaje=''; $user_log=''; $pass_log='';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $user = $_POST['usuario']  ?? '';
    $pass = $_POST['password'] ?? '';
    // CONSULTA VULNERABLE: concatenacion directa, sin sanitizar
    $sql = "SELECT usuario, password FROM usuarios WHERE usuario='$user' AND password='$pass'";
    $res = mysqli_query($con, $sql);
    if ($res === false) { $mensaje = 'Error SQL: ' . mysqli_error($con); }
    elseif (mysqli_num_rows($res) > 0) {
        $f = mysqli_fetch_assoc($res); $ok=true; $user_log=$f['usuario']; $pass_log=$f['password'];
    } else { $mensaje = 'Usuario o contrasena incorrectos.'; }
}
?>
<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Portal de Acceso</title>
<style>
body{font-family:system-ui,Arial,sans-serif;background:#0f172a;color:#e2e8f0;display:flex;
min-height:100vh;align-items:center;justify-content:center;margin:0}
.card{background:#1e293b;padding:2rem 2.5rem;border-radius:14px;width:340px;box-shadow:0 10px 30px rgba(0,0,0,.4)}
h1{margin:0 0 1.2rem;font-size:1.3rem;text-align:center}
label{display:block;margin:.6rem 0 .2rem;font-size:.85rem;color:#94a3b8}
input{width:100%;padding:.6rem;border-radius:8px;border:1px solid #334155;background:#0f172a;color:#e2e8f0;box-sizing:border-box}
button{width:100%;margin-top:1.2rem;padding:.7rem;border:0;border-radius:8px;background:#38bdf8;color:#0f172a;font-weight:700;cursor:pointer}
.msg{margin-top:1rem;padding:.6rem;border-radius:8px;background:#7f1d1d;font-size:.85rem;word-break:break-all}
.ok{background:#064e3b} code{color:#fbbf24} a{color:#38bdf8}
</style></head><body><div class="card">
<?php if ($ok): ?>
  <h1>&#127881; &iexcl;Enhorabuena!</h1>
  <div class="msg ok">Has accedido correctamente.<br><br>
  <b>Usuario:</b> <code><?= htmlspecialchars($user_log) ?></code><br>
  <b>Contrase&ntilde;a:</b> <code><?= htmlspecialchars($pass_log) ?></code><br><br>
  Pista: estas credenciales tambi&eacute;n valen fuera del portal, y en
  <code>/var/backups</code> hay un fichero con la palabra <code>password</code>. &#128520;</div>
  <p style="text-align:center;margin-top:1rem"><a href="index.php">Volver</a></p>
<?php else: ?>
  <h1>&#128272; Portal de Acceso</h1>
  <form method="post" action="index.php">
    <label>Usuario</label><input type="text" name="usuario" autocomplete="off">
    <label>Contrase&ntilde;a</label><input type="password" name="password" autocomplete="off">
    <button type="submit">Entrar</button>
  </form>
  <?php if ($mensaje): ?><div class="msg"><?= $mensaje ?></div><?php endif; ?>
<?php endif; ?>
</div></body></html>
PHP

# --- Base de datos ---
mysql <<'SQL'
DROP DATABASE IF EXISTS portal;
CREATE DATABASE portal CHARACTER SET utf8mb4;
USE portal;
CREATE TABLE usuarios (id INT AUTO_INCREMENT PRIMARY KEY, usuario VARCHAR(50), password VARCHAR(100));
INSERT INTO usuarios (usuario,password) VALUES
  ('admin','admin'),
  ('debian','Debian2026*'),
  ('soporte','helpdesk2024');
CREATE TABLE secretos (id INT AUTO_INCREMENT PRIMARY KEY, clave VARCHAR(50), valor VARCHAR(200));
INSERT INTO secretos (clave,valor) VALUES
  ('nota','El backup con la pass de root esta en /var/backups'),
  ('flag_web','FLAG{SQLi_P0rtal_AG}');
CREATE USER IF NOT EXISTS 'webapp'@'localhost' IDENTIFIED BY 'webapp123';
GRANT ALL PRIVILEGES ON portal.* TO 'webapp'@'localhost';
FLUSH PRIVILEGES;
SQL

if [ $? -eq 0 ]; then c_ok "Base de datos 'portal' creada"; else c_err "Fallo creando la BBDD"; fi
systemctl restart apache2 && c_ok "Apache reiniciado"

# ============================================================================
#  INFORME DE VERIFICACION
# ============================================================================
echo ""
echo "############################################################"
echo "#                 INFORME DE VERIFICACION                  #"
echo "############################################################"

echo ""
echo "----- 2) Ocultar IP -----"
grep -qE '\\4|\\6' /etc/issue && echo "[FAIL] /etc/issue revela IP" || echo "[OK] /etc/issue no revela IP"
echo "Contenido /etc/issue:"; sed 's/^/    /' /etc/issue

echo ""
echo "----- 3) Usuarios -----"
id "$USER_ADMIN" 2>/dev/null && echo "[OK] usuario $USER_ADMIN existe" || echo "[FAIL] no existe $USER_ADMIN"
getent passwd root | cut -d: -f1 | grep -q root && echo "[OK] root presente"

echo ""
echo "----- 5) Fichero del hash de root -----"
if [ -f "$BACKUP_FILE" ]; then
  echo "[OK] existe $BACKUP_FILE (permisos: $(stat -c '%a' "$BACKUP_FILE"))"
  grep -qi password "$BACKUP_FILE" && echo "[OK] contiene la palabra 'password'" || echo "[FAIL] no contiene 'password'"
  echo "Contenido:"; sed 's/^/    /' "$BACKUP_FILE"
else echo "[FAIL] no existe $BACKUP_FILE"; fi
echo "sha256('$ROOT_PASS') = $(printf '%s' "$ROOT_PASS" | sha256sum | awk '{print $1}')"

echo ""
echo "----- 6) flag.txt -----"
[ -f "$FLAG_FILE" ] && echo "[OK] existe $FLAG_FILE (permisos: $(stat -c '%a' "$FLAG_FILE"))" || echo "[FAIL] no existe"

echo ""
echo "----- 7/8) Servicios -----"
for s in ssh vsftpd apache2 mariadb; do
  printf "  %-10s: %s\n" "$s" "$(systemctl is-active $s 2>/dev/null)"
done

echo ""
echo "----- Puertos a la escucha -----"
ss -tlnp 2>/dev/null | awk 'NR==1 || /:(21|22|80|3306)\s/'

echo ""
echo "----- Web portal (codigo HTTP) -----"
echo "  http://localhost/portal/ -> $(curl -s -o /dev/null -w '%{http_code}' http://localhost/portal/ 2>/dev/null)"

echo ""
echo "----- IP real (DHCP, solo para tu referencia) -----"
ip -4 addr show 2>/dev/null | awk '/inet /{print "    "$2" ("$NF")"}'

echo ""
echo "############################################################"
echo "#   Hecho. Pega este informe completo para verificarlo.    #"
echo "############################################################"
