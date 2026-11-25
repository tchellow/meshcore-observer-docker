# Observer MeshCore em Docker

Roda um **observer MeshCore** em container: um repetidor ligado na USB do servidor tem seus pacotes lidos e publicados em brokers MQTT, como o LetsMesh, o MeshMapper ou o MQTT da sua comunidade (por exemplo, o que alimenta o CoreScope).

```
 rede LoRa ──► repetidor MeshCore (USB) ──► meshcore-observer ──► brokers MQTT
                (firmware com packet logging)    (mctomqtt)        LetsMesh · MeshMapper · próprio
```

O programa é o [Cisien/meshcoretomqtt](https://github.com/Cisien/meshcoretomqtt) (`mctomqtt`, licença MIT), incluído **sem alterações** em `app/` (a versão exata está em `app/.version_info`). Este repositório acrescenta o Dockerfile, o compose e um instalador que detecta o rádio e monta a configuração.

---

## Requisitos

- Linux com **Docker** e **docker compose v2** (testado em x86_64; deve funcionar em ARM, como Raspberry Pi e TV box)
- Um **repetidor MeshCore** ligado na USB, com firmware compilado com `-D MESH_PACKET_LOGGING=1` (o firmware "letsmesh" já vem assim) e versão **1.8.0 ou mais nova**, que suporta `get prv.key`
- O rádio precisa ser **exclusivo** do observer: dois programas não leem a mesma porta serial

## Instalação

```bash
git clone https://github.com/tchellow/meshcore-observer-docker.git
cd meshcore-observer-docker
./instalar.sh
```

O instalador:

1. lista os rádios em `/dev/serial/by-id/` (caminho estável, que não muda ao religar) e avisa se algum já está em uso por outro container;
2. pergunta o **código IATA** da região, com 3 letras do aeroporto mais próximo (ex.: `GRU`, `CWB`, `QDV`), que entra no tópico `meshcore/<IATA>/<chave>/...`;
3. pergunta quais **presets de broker** ativar (padrão: `letsmesh meshmapper`) e um **e-mail de contato** para eles (opcional);
4. pergunta um **broker próprio** com usuário/senha (opcional);
5. grava `config/config.d/` (permissão 700) e o `.env`, constrói a imagem, sobe o container e mostra o nome do repetidor e os brokers conectados.

Instalação sem perguntas:

```bash
SEM_PERGUNTAS=1 OBSERVER_SERIAL=/dev/serial/by-id/usb-Seeed_Studio_XIAO_nRF52840_XXXX-if00 \
IATA=GRU PRESETS="letsmesh meshmapper" EMAIL=voce@exemplo.com \
BROKER_SERVIDOR=mqtt.exemplo.com.br BROKER_PORTA=1883 BROKER_USUARIO=user BROKER_SENHA=senha \
./instalar.sh
```

### Atualizar

```bash
./instalar.sh --atualizar     # git pull + rebuild + restart; mantém a configuração
```

Rodar `./instalar.sh` de novo pergunta se você quer refazer a configuração. A anterior vai para `config/config.d.bak-<data>`.

## Configuração

A configuração é carregada nesta ordem, e cada arquivo sobrepõe o anterior:

| Arquivo | O que é |
|---|---|
| `config/config.toml` | referência completa do mctomqtt com os padrões. Não edite |
| `config/config.d/10-<preset>.toml` | brokers escolhidos na instalação, copiados de `presets/` |
| `config/config.d/99-user.toml` | **sua configuração**: IATA, porta serial, e-mail, broker próprio |

Modelo comentado em `config/99-user.toml.example`. Depois de editar, aplique com `docker compose restart`.

Presets incluídos (`presets/`): `letsmesh` (US + EU), `meshmapper`, `meshrank`, `chimesh`, `coloradomesh`, `meshat-se`, `waev`.

**Autenticação por token** (LetsMesh, MeshMapper…): o mctomqtt lê a chave privada **do próprio rádio** (`get prv.key`) e assina um token. A identidade do observer, portanto, vai junto com o rádio: trocar de servidor não muda nada, trocar de rádio muda.

`.env`:

| Variável | Para quê |
|---|---|
| `OBSERVER_SERIAL` | caminho do rádio no host (vira `/dev/meshcore` dentro do container) |
| `OBSERVER_CONTAINER` | nome do container (padrão `meshcore-observer`) |
| `TZ` | fuso horário dos logs |

## Acompanhando

```bash
docker logs -f meshcore-observer
```

A cada 5 minutos aparecem duas linhas de resumo:

- `[SERVICE]`: tempo ligado, pacotes RX/TX, **MQTT: N/N** (brokers conectados) e reconexões nas últimas 24 h;
- `[DEVICE]`: ruído (dB), uso do ar (Tx/Rx %), bateria e uptime do rádio.

## Dicas

- **Use sempre `/dev/serial/by-id/...`**, nunca `/dev/ttyACM0`: com dois rádios na mesma máquina, a numeração ACM troca a cada boot.
- **Rádio sumiu** (desligou da USB): o container perde o dispositivo. Religue o rádio e rode `docker compose up -d --force-recreate`.
- **Relógio**: o mctomqtt acerta a hora do repetidor pela hora do servidor. Mantenha o NTP do host ligado.
- **Remote serial** (comandos pelo LetsMesh) vem **desligado**. Para ligar, veja `[remote_serial]` em `config/config.toml` e sobreponha no `99-user.toml`.

## Estrutura

```
Dockerfile, docker-compose.yml   container
instalar.sh                      instalação / --atualizar
.env.example                     modelo do .env
app/                             mctomqtt (upstream, sem alterações)
config/config.toml               referência do upstream
config/99-user.toml.example      modelo da configuração local
presets/                         brokers prontos (upstream)
```

O `.env` e o `config/config.d/` (senhas, e-mail) **não** vão para o Git.

## Licença

O mctomqtt é © Andrew (Cisien), licença MIT: veja `LICENSE.mctomqtt`. Os arquivos deste repositório (Dockerfile, compose, instalador, documentação) também são MIT.
