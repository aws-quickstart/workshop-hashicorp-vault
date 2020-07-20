#!/bin/bash

#### Install System Packages ####
apt-get update
apt-get install -qq -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    git \
    jq \
    unzip \
    default-jdk \
    maven > /dev/null 2>&1

apt-get clean
rm -rf /var/lib/apt/lists/*

#### Set up Vault Client ####
export DEBIAN_FRONTEND=noninteractive
sudo echo "127.0.0.1 $(hostname)" >> /etc/hosts

USER="vault"
COMMENT="Hashicorp vault user"
GROUP="vault"
HOME="/srv/vault"

user_ubuntu() {
  # UBUNTU user setup
  if ! getent group $${GROUP} >/dev/null
  then
    sudo addgroup --system $${GROUP} >/dev/null
  fi

  if ! getent passwd $${USER} >/dev/null
  then
    sudo adduser \
      --system \
      --disabled-login \
      --ingroup $${GROUP} \
      --home $${HOME} \
      --no-create-home \
      --gecos "$${COMMENT}" \
      --shell /bin/false \
      $${USER}  >/dev/null
  fi
}

user_ubuntu

VAULT_ZIP="vault_1.3.0_linux_amd64.zip"
VAULT_URL="https://releases.hashicorp.com/vault/1.3.0/vault_1.3.0_linux_amd64.zip"
sudo curl --silent --output /tmp/$${VAULT_ZIP} $${VAULT_URL}
sudo unzip -o /tmp/$${VAULT_ZIP} -d /usr/local/bin/
sudo chmod 0755 /usr/local/bin/vault
sudo chown vault:vault /usr/local/bin/vault
sudo mkdir -pm 0755 /etc/vault.d
sudo mkdir -pm 0755 /opt/vault
sudo chown vault:vault /opt/vault

cat << EOF | sudo tee /lib/systemd/system/vault.service
[Unit]
Description=Vault Agent
Requires=network-online.target
After=network-online.target
[Service]
Restart=on-failure
PermissionsStartOnly=true
ExecStartPre=/sbin/setcap 'cap_ipc_lock=+ep' /usr/local/bin/vault
ExecStart=/usr/local/bin/vault server -config /etc/vault.d
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGTERM
User=vault
Group=vault
[Install]
WantedBy=multi-user.target
EOF


cat << EOF | sudo tee /etc/vault.d/vault.hcl
storage "file" {
  path = "/opt/vault"
}
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

ui=true
EOF


sudo chmod 0664 /lib/systemd/system/vault.service
sudo systemctl daemon-reload
sudo chown -R vault:vault /etc/vault.d
sudo chmod -R 0644 /etc/vault.d/*
###########################################


#### Set Web  Server Environment #####
export SPRING_PROFILES_ACTIVE=mysql

#### Clone the Pet Clinic code from GitHub ####
if [ ! -d /opt/spring-petclinic ]; then
  git clone https://github.com/dcallao/spring-petclinic.git /opt/spring-petclinic
fi

###########################################


#### Set DB templates - root user #####
tee /opt/spring-petclinic/src/main/resources/application-mysql.properties <<EOF
# database init, supports mysql too
database=mysql
# SQL is written to be idempotent so this is safe
spring.datasource.initialization-mode=always
# Datasource driver class
spring.datasource.driver-class-name=com.mysql.jdbc.Driver
# Spring profile to start with
spring.profiles.active=mysql
# Database Credentials
# local database username
spring.datasource.username=${db_user}
# local database password
spring.datasource.password=${db_password}
# connection url
spring.datasource.url=jdbc:mysql://${mysql_endpoint}:3306/${db_name}
EOF

tee /opt/spring-petclinic/src/main/resources/application-mysql.properties.tmpl <<EOF
# database init, supports mysql too
database=mysql
# SQL is written to be idempotent so this is safe
spring.datasource.initialization-mode=always
# Datasource driver class
spring.datasource.driver-class-name=com.mysql.jdbc.Driver
# Spring profile to start with
spring.profiles.active=mysql
# Database Credentials
{{ with secret "database/static-creds/rotate-mysql-pass" }}
spring.datasource.username={{ .Data.username }}
spring.datasource.password={{ .Data.password }}
{{ end }}
spring.datasource.url=jdbc:mysql://${mysql_endpoint}:3306/${db_name}
EOF

#### Set up Vault environment ####
sudo tee -a /etc/environment <<EOF
export VAULT_ADDR="http://${vault_server_addr}:8200"
export VAULT_SKIP_VERIFY=true
EOF

source /etc/environment

sudo systemctl enable vault
###########################################

#### For Vault Auth Task #####
cat << EOF > /home/ubuntu/vault-agent.hcl
exit_after_auth = true
pid_file = "./pidfile"
auto_auth {
   method "aws" {
       mount_path = "auth/aws"
       config = {
           type = "iam"
           role = "client-role-iam"
       }
   }
   sink "file" {
       config = {
           path = "/home/ubuntu/vault-token-via-agent"
       }
   }
}
vault {
   address = "http://${vault_server_addr}:8200"
}
template {
   source      = "/opt/spring-petclinic/target/classes/application-mysql.properties.tmpl"
   destination = "/opt/spring-petclinic/target/classes/application-mysql.properties"
}
EOF

sudo chmod 0775 /home/ubuntu/vault-agent.hcl
###########################################


#### Start Web  Server #####
# Log into Vault using the AWS auth method
vault login -method=aws role=client-role-iam

# Start the Vault agent in /home/ubuntu
cd /home/ubuntu
vault agent -config=vault-agent.hcl -log-level=debug

# Start the Web Server in /opt/spring-petclinic
cd /opt/spring-petclinic
/usr/bin/mvn spring-boot:run
###########################################