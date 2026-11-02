#!/bin/bash

echo "Iniciando configuração do ambiente"
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
    sudo systemctl enable --now docker
fi

sudo systemctl enable --now docker

# INSTALAÇÃO DO DOCKER COMPOSE
if ! sudo docker compose version >/dev/null 2>&1; then
    echo "Instalando Docker Compose..."
    sudo apt install -y docker-compose-v2
fi

echo "Docker e Docker Compose configurados!"

# DIRETÓRIO DO PROJETO
mkdir -p "$HOME/low-latency"
cd "$HOME/low-latency" || exit 1

# CLONAGEM DO BANCO
echo "Baixando arquivos do banco..."

git clone https://github.com/LowLatencyOrg/Banco-de-dados.git

if [ ! -f "$HOME/low-latency/Banco-de-dados/script-low-latency.sql" ]; then
    echo "Arquivo SQL não encontrado."
    exit 1
fi

# REDE DOCKER
echo "Criando rede Docker..."
sudo docker network create lowlatency-net

# SENHA DO MYSQL
read -r -s -p "Digite a senha do MySQL root: " MYSQL_ROOT_PASSWORD
echo

export MYSQL_ROOT_PASSWORD

# DIRETÓRIO DE PERSISTÊNCIA
sudo mkdir -p /dados/mysql

# INICIALIZAÇÃO DO BANCO
echo "Iniciando container MySQL..."

sudo env MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" docker compose \
    -f docker-compose-banco.yml \
    up -d

if [ $? -ne 0 ]; then
    echo "Erro ao iniciar o banco."
    exit 1
fi

echo "Container MySQL iniciado!"

# CRIAÇÃO DO USUÁRIO DA API
echo "Configurando usuário do banco..."

sudo docker exec lowlatency-banco \
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
    CREATE USER 'dba_user'@'%' IDENTIFIED BY '12345';
    GRANT ALL PRIVILEGES ON lowLatency.* TO 'dba_user'@'%';
    FLUSH PRIVILEGES;
    "

if [ $? -ne 0 ]; then
    echo "Erro ao configurar o usuário do banco."
    exit 1
fi

unset MYSQL_ROOT_PASSWORD

echo "Usuário dba_user configurado!"

# INICIALIZAÇÃO DA API


echo "Baixando arquivos da API..."

git clone https://github.com/LowLatencyOrg/Site-Grupo03.git \
    "$HOME/low-latency/Site-Grupo03"

cd "$HOME/low-latency/Site-Grupo03" || exit 1

echo "Criando Dockerfile..."

cat > Dockerfile <<'DOCKERFILE_EOF'
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 3333
CMD ["npm", "start"]
DOCKERFILE_EOF

cd "$HOME/low-latency" || exit 1

echo "Construindo e iniciando a API..."

sudo -E docker compose \ -f docker-compose-api.yml \ up -d --build

if [ $? -ne 0 ]; then
    echo "Erro ao iniciar a API."
    exit 1
fi

echo "API iniciada com sucesso!"
echo "Acesse: http://IP-PUBLICO-DA-EC2:3333"

else
    echo "Inicialização da API cancelada."
fi

echo "Configuração concluída!"
