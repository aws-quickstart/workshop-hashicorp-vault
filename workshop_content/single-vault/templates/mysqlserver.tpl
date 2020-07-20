#!/bin/bash

set -x 

# Set up MySQL Server
export DEBIAN_FRONTEND=noninteractive
sudo echo "127.0.0.1 $(hostname)" >> /etc/hosts

# Pre-set the MySQL password so apt doesn't pop up a password dialog
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password abc123"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password abc123"

# Install MySQL and the Nagios check script
apt-get update -y
apt-get -y install mysql-server

cat << EOF > /etc/mysql/mysql.conf.d/petclinic.cnf
[mysqld]
bind-address = 0.0.0.0
lower_case_table_names=1
character-set-server=utf8
collation-server=utf8_general_ci
innodb_large_prefix=on
innodb_file_format=Barracuda
EOF


systemctl restart mysql

mysql -u root -pabc123 -e "create user if not exists root@'%' identified by 'ech9Weith4Phei7W'"
mysql -u root -pabc123 -e "grant all privileges on *.* to root@'%' with grant option"
mysql -u root -pabc123 -e "grant proxy on '@' to root@'%'"
mysql -u root -pabc123 -e "create database if not exists petclinic"
mysql -u root -pabc123 -e "flush privileges"

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*