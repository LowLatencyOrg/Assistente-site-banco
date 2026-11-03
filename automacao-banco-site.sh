#!/bin/bash

BASE_DIR="$HOME/low-latency"

echo "Iniciando configuração do ambiente"

# ATUALIZAÇÃO DOS PACOTES
echo "Atualizando pacotes..."

if ! sudo apt update || ! sudo apt upgrade -y; then
    echo "Erro ao atualizar os pacotes."
    exit 1
fi

echo "Pacotes atualizados com sucesso!"

# INSTALAÇÃO DO DOCKER
if command -v docker >/dev/null 2>&1; then
    echo "Docker já está instalado:"
    docker --version
else
    echo "Instalando Docker..."
    sudo apt install -y docker.io
fi

sudo systemctl enable --now docker

# INSTALAÇÃO DO DOCKER COMPOSE
if ! sudo docker compose version >/dev/null 2>&1; then
    echo "Instalando Docker Compose..."
    sudo apt install -y docker-compose-v2
fi

echo "Docker e Docker Compose configurados!"

# DIRETÓRIO DO PROJETO
mkdir -p "$BASE_DIR"

# CLONAGEM DO BANCO
echo "Verificando arquivos do banco..."

git clone https://github.com/LowLatencyOrg/Banco-de-dados.git \
    "$BASE_DIR/Banco-de-dados"

if [ $? -ne 0 ]; then
    echo "Erro ao baixar o repositório do banco."
    exit 1
fi

# REDE DOCKER
echo "Verificando rede Docker..."

if ! sudo docker network inspect lowlatency-net >/dev/null 2>&1; then
    sudo docker network create lowlatency-net
fi

# VERIFICAÇÃO DO DISCO
if ! mountpoint -q /dados; then
    echo "O disco de persistência não está montado em /dados."
    exit 1
fi

sudo mkdir -p /dados/mysql

# SENHA DO MYSQL
read -r -s -p "Digite a senha do MySQL root: " MYSQL_ROOT_PASSWORD
echo

# INICIALIZAÇÃO DO BANCO
echo "Iniciando container MySQL..."

cd "$HOME/Assistente-site-banco" || exit 1

sudo env MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" BASE_DIR="$BASE_DIR" docker compose -f dockerCompose-banco.yaml up -d

if [ $? -ne 0 ]; then
    echo "Erro ao iniciar o banco."
    exit 1
fi

# AGUARDAR MYSQL
echo "Aguardando o MySQL iniciar..."

until sudo docker exec lowlatency-banco \
    mysqladmin ping -h localhost --silent; do
    sleep 2
done

echo "MySQL está pronto!"
echo "Container MySQL iniciado!"

# CRIAÇÃO DO USUÁRIO DA API
echo "Configurando usuário do banco..."

# TESTE DE CONEXÃO COM O ROOT
if ! sudo docker exec \
    -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
    lowlatency-banco \
    mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then

    echo "Erro: não foi possível autenticar no MySQL com a senha informada."
    exit 1
fi

echo "Conexão com o MySQL root confirmada!"

# CRIAÇÃO DO USUÁRIO DA API
if ! sudo docker exec \
    -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
    lowlatency-banco \
    mysql -u root -e "
    CREATE USER IF NOT EXISTS 'dba_user'@'%' IDENTIFIED BY '12345';
    ALTER USER 'dba_user'@'%' IDENTIFIED BY '12345';
    GRANT ALL PRIVILEGES ON lowLatency.* TO 'dba_user'@'%';
    FLUSH PRIVILEGES;
    "; then

    echo "Erro ao configurar o usuário do banco."
    exit 1
fi

unset MYSQL_ROOT_PASSWORD

echo "Usuário dba_user configurado!"
echo "Usuário dba_user configurado!"

# CLONAGEM DA API
echo "Verificando arquivos da API..."

git clone https://github.com/LowLatencyOrg/Site-Grupo03.git \
    "$BASE_DIR/Site-Grupo03"

if [ $? -ne 0 ]; then
    echo "Erro ao baixar o repositório da API."
    exit 1
fi


# CRIAÇÃO DO DOCKERFILE
echo "Criando Dockerfile..."

cat > "$BASE_DIR/Site-Grupo03/Dockerfile" <<'DOCKERFILE_EOF'
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 3333
CMD ["npm", "start"]
DOCKERFILE_EOF

# INICIALIZAÇÃO DA API
echo "Construindo e iniciando a API..."
cd "$HOME/Assistente-site-banco" || exit 1

sudo env BASE_DIR="$BASE_DIR" docker compose \
    -f dockerCompose-site.yaml \
    up -d --build

if [ $? -ne 0 ]; then
    echo "Erro ao iniciar a API."
    exit 1
fi

echo "API iniciada com sucesso!"
echo "Acesse: http://IP-PUBLICO-DA-EC2:3333"

echo "Configuração concluída!"
