#!/bin/sh
# Instalador do Observer MeshCore (mctomqtt em container).
#
#   ./instalar.sh              instala ou reconfigura (pergunta rádio, IATA, brokers)
#   ./instalar.sh --atualizar  baixa a versão nova do GitHub, reconstrói e reinicia (mantém a configuração)
#
# Respostas sem perguntar (opcional), por variável de ambiente:
#   OBSERVER_SERIAL, IATA, EMAIL, PRESETS="letsmesh meshmapper", BROKER_SERVIDOR, BROKER_PORTA,
#   BROKER_USUARIO, BROKER_SENHA, BROKER_TLS=s|n, SEM_PERGUNTAS=1
set -eu
cd "$(dirname "$0")"

msg()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
erro() { printf '\033[1;31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }
pergunta() {  # pergunta VAR "texto" "padrão"  (usa a variável de ambiente se já existir)
  eval "pronto=\${$1:-}"
  if [ -n "$pronto" ] || [ "${SEM_PERGUNTAS:-}" = 1 ]; then eval "$1=\"\${pronto:-$3}\""; return; fi
  printf '%s [%s]: ' "$2" "$3"; read -r v || v=""; eval "$1=\"\${v:-$3}\""
}
toml() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }   # escapa para string TOML

# ---------- requisitos ----------
command -v docker >/dev/null || erro "Docker não encontrado. Instale: https://docs.docker.com/engine/install/"
docker compose version >/dev/null 2>&1 || erro "Falta o plugin 'docker compose' (v2)."
docker info >/dev/null 2>&1 || erro "Sem acesso ao Docker. Rode com sudo ou adicione seu usuário ao grupo docker."

NOME=$(sed -n 's/^OBSERVER_CONTAINER=//p' .env 2>/dev/null); NOME=${NOME:-meshcore-observer}

# ---------- atualização ----------
if [ "${1:-}" = "--atualizar" ]; then
  [ -f .env ] && [ -f config/config.d/99-user.toml ] || erro "Ainda não instalado. Rode ./instalar.sh primeiro."
  if [ -d .git ]; then msg "Baixando a versão nova"; git pull --ff-only; fi
  msg "Reconstruindo e reiniciando"
  docker compose build --pull
  docker compose up -d
  docker compose ps
  exit 0
fi

if [ -f config/config.d/99-user.toml ] && [ "${SEM_PERGUNTAS:-}" != 1 ]; then
  printf 'Já existe uma configuração. Refazer do zero? (a atual vai para .bak) s/N: '; read -r r || r=""
  if [ "$r" != s ]; then
    msg "Mantendo a configuração; só reconstruindo e subindo"
    docker compose up -d --build; docker compose ps; exit 0
  fi
fi

# ---------- rádio ----------
echo
echo "Rádio MeshCore (repetidor com firmware compilado com -D MESH_PACKET_LOGGING=1) ligado na USB:"
if [ -z "${OBSERVER_SERIAL:-}" ]; then
  set -- $(ls /dev/serial/by-id/ 2>/dev/null || true)
  [ $# -gt 0 ] || erro "Nenhum dispositivo em /dev/serial/by-id/. Ligue o rádio na USB e rode de novo."
  i=1; for d in "$@"; do echo "  $i) $d"; i=$((i+1)); done
  # aviso: rádio já usado por outro container
  for d in "$@"; do
    usado=$(docker ps --format '{{.Names}}' | while read -r c; do docker inspect -f '{{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}' "$c" | grep -q "$d" && echo "$c"; done)
    [ -n "$usado" ] && echo "     (atenção: $d já está em uso por: $usado)"
  done
  pergunta ESCOLHA "Número do rádio" "1"
  eval "OBSERVER_SERIAL=/dev/serial/by-id/\${$ESCOLHA}"
fi
[ -e "$OBSERVER_SERIAL" ] || erro "Dispositivo não encontrado: $OBSERVER_SERIAL"
msg "Rádio: $OBSERVER_SERIAL"

# ---------- região e brokers ----------
echo
pergunta IATA "Código IATA de 3 letras da sua região (aeroporto mais próximo)" "XXX"
IATA=$(printf '%s' "$IATA" | tr a-z A-Z)
printf '%s' "$IATA" | grep -qE '^[A-Z]{3}$' || erro "IATA precisa ter 3 letras (ex.: GRU)."

echo
echo "Presets de broker disponíveis: $(ls presets | sed 's/\.toml$//' | tr '\n' ' ')"
pergunta PRESETS "Quais ativar (separados por espaço; vazio = nenhum)" "letsmesh meshmapper"
pergunta EMAIL "E-mail de contato para os brokers por token (LetsMesh/MeshMapper; vazio = nenhum)" ""

echo
echo "Broker próprio com usuário/senha (ex.: o MQTT da sua comunidade). Vazio = pular."
pergunta BROKER_SERVIDOR "Servidor" ""
if [ -n "$BROKER_SERVIDOR" ]; then
  pergunta BROKER_TLS "Usar TLS? s/n" "n"
  pergunta BROKER_PORTA "Porta" "$( [ "$BROKER_TLS" = s ] && echo 8883 || echo 1883)"
  pergunta BROKER_USUARIO "Usuário" ""
  if [ -z "${BROKER_SENHA:-}" ] && [ "${SEM_PERGUNTAS:-}" != 1 ]; then
    printf 'Senha: '; stty -echo 2>/dev/null || true; read -r BROKER_SENHA || BROKER_SENHA=""; stty echo 2>/dev/null || true; echo
  fi
fi

# ---------- grava configuração ----------
D=config/config.d
if [ -d "$D" ] && [ -n "$(ls -A "$D" 2>/dev/null)" ]; then
  B="$D.bak-$(date +%Y%m%d-%H%M%S)"; mv "$D" "$B"; msg "Configuração anterior guardada em $B"
fi
mkdir -p "$D"; chmod 700 config "$D"
for p in $PRESETS; do
  [ -f "presets/$p.toml" ] || erro "Preset não existe: $p"
  cp "presets/$p.toml" "$D/10-$p.toml"
done

U="$D/99-user.toml"
umask 077
{
  echo "# Observer MeshCore — gerado por instalar.sh em $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "[general]"
  echo "iata = \"$IATA\""
  echo "mesh_packet_logging = true"
  echo
  echo "[serial]"
  echo 'ports = ["/dev/meshcore"]'
  if [ -n "$BROKER_SERVIDOR" ]; then
    echo
    echo "[[broker]]"
    echo 'name = "custom-1"'
    echo "enabled = true"
    echo "server = \"$(toml "$BROKER_SERVIDOR")\""
    echo "port = $BROKER_PORTA"
    echo 'transport = "tcp"'
    echo "keepalive = 60"
    echo "qos = 0"
    echo "retain = true"
    if [ "$BROKER_TLS" = s ]; then printf '\n[broker.tls]\nenabled = true\nverify = true\n'; fi
    echo
    echo "[broker.auth]"
    echo 'method = "password"'
    echo "username = \"$(toml "$BROKER_USUARIO")\""
    echo "password = \"$(toml "${BROKER_SENHA:-}")\""
  fi
  if [ -n "$EMAIL" ]; then
    # um bloco por broker com auth por token nos presets escolhidos
    for p in $PRESETS; do
      awk '/^\[\[broker\]\]/{n=""} /^name *=/{n=$0} /^method *= *"token"/{print n}' "presets/$p.toml"
    done | while read -r linha; do
      printf '\n[[broker]]\n%s\n\n[broker.auth]\nemail = "%s"\n' "$linha" "$(toml "$EMAIL")"
    done
  fi
} > "$U"
umask 022

[ -f .env ] || cp .env.example .env
sed -i "s|^OBSERVER_SERIAL=.*|OBSERVER_SERIAL=$OBSERVER_SERIAL|" .env
chmod 600 .env
msg "Configuração gravada em $U"

# ---------- build e subida ----------
msg "Construindo a imagem e subindo o container"
docker compose up -d --build

msg "Aguardando o rádio e os brokers (até 60 s)"
i=0
while [ $i -lt 30 ]; do
  docker logs "$NOME" 2>&1 | grep -q "Connected to broker" && break
  i=$((i+1)); sleep 2
done
echo
docker logs "$NOME" 2>&1 | grep -E "Repeater name|Connected to /dev|Connected to broker|ERROR|Failed" | tail -12
echo
echo "------------------------------------------------------------"
echo " Container: $NOME   |   logs: docker logs -f $NOME"
echo " Resumo a cada 5 min no log: linhas [SERVICE] (RX/TX, MQTT conectados) e [DEVICE] (ruído, bateria)."
echo "------------------------------------------------------------"
