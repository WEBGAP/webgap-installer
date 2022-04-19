#!/bin/bash

##################################################
#__      __ ___     ___     ___     ___      ___ # 
#\ \    / /| __|   | _ )   / __|   /   \    | _ \# 
# \ \/\/ / | _|    | _ \  | (_ |   | - |    |  _/# 
#  \_/\_/  |___|   |___/   \___|   |_|_|   _|_|_ # 
#_|"""""|_|"""""|_|"""""|_|"""""|_|"""""|_| """ |# 
#"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'# 
##################################################

#checks to see if the script was run as root
if [ $(id -u) != 0 ]; then
    echo "$(tput setaf 3)This script must be run as root.$(tput setaf 9)" 
    exit 1
fi

#gets the operating system ID and saves as the variable osrelease1/2/3
osrelease=$(awk -F= '$1=="NAME" { print $2 ;}' /etc/os-release)
osrelease1=$(awk -F= '$1=="CENTOS_MANTISBT_PROJECT" { print $2 ;}' /etc/os-release)
osrelease2=$(awk -F= '$1=="UBUNTU_CODENAME" { print $2 ;}' /etc/os-release)

#if the operating system ID isn't rocky nor centos the script exits after displaying a message
if [ "$osrelease" != '"Rocky Linux"' ] && [ "$osrelease1" != '"CentOS-7"' ] && [ "$osrelease2" != focal ] ; then
    echo "$(tput setaf 3)Please install on CentOS 7, Rocky 8, or Ubuntu 20.04. You are trying to install on $(tput bold)$osrelease.$(tput setaf 9)"

    sleep 2
    exit 1
fi

##rocky command block##
if [ "$osrelease" == '"Rocky Linux"' ]; then

    #create package metadata store and upgrade operating system packages
    yum makecache
    yum -y upgrade

    #install required packages
    yum -y install yum-utils wget git epel-release setools setroubleshoot

    #download nginx repo for stable version
    wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1ADencnD7rNB0RqT2bB1iFiMVE5fupIOH' -O /etc/yum.repos.d/nginx.repo

    #add docker and nginx repo
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    #install docker-ce and nginx
    yum -y remove runc
    yum -y install docker-ce nginx

    #change boolean operators for nginx to allow memory execution, network connection establishment
    setsebool -P httpd_execmem 1
    setsebool -P httpd_can_network_connect 1
    setsebool -P httpd_graceful_shutdown 1
    setsebool -P httpd_can_network_relay 1

    #enable nginx
    systemctl enable nginx

    #download nginx configuration template
    wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1Jw_CcvIqatMn3WVkUI2uMTe3g7WLb58v' -O /etc/nginx/conf.d/default.conf

    #download docker compose
    curl -L "https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    #make docker-compose executable and enable
    chmod +x /usr/local/bin/docker-compose && ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

    #start docker-ce
    systemctl enable --now docker.service

    #create user docker and add to group docker
    useradd -g docker docker

    #install snapd to later install certbot
    yum install -y snapd

    #enable and start snapd
    systemctl enable --now snapd.socket

    #enable snap classic functionality for certbot installation
    ln -s /var/lib/snapd/snap /snap

    #disable firewalld zone drifiting
    sed -i 's/AllowZoneDrifting=yes/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf

    #ask for host interface IP to create firewall rules insert into configuration files
    echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9)"
    read ip

    #tests IPv4 address validity for octet formatting to assure numbers only and between 1 and 3 positions
    while ! [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
        do echo "$(tput setaf 3)Please check for IP address format and numerical accuracy.$(tput setaf 9)"

        sleep 5

        echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9)"
        read ip
    done

        #the trusted zone accepts all packets, no rules needed
    echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9)"
    read fw

    #tests the value of the variable fw against acceptable values
    while [ "$fw" != yes ] && [ "$fw" != y ]  && [ "$fw" != no ] && [ "$fw" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"

        sleep 2

        echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9)"
        read fw
    done

    #asks about vpc/dmz to add another firewall rule if deployed directly to the internet
    if [ "$fw" == no ] || [ "$fw" == n ]; then
        echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9)"
        read answer

        #checks for answer spelling; if spelling is incorrect the operator is informed and given another chance to answer
        while [ "$answer" != yes ] && [ "$answer" != y ]  && [ "$answer" != no ] && [ "$answer" != n ]
            do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
        
            sleep 2

            echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9)"
            read answer
        done
    fi

    #creates firewall rule if no vpc/dmz
    if [ "$answer" == no ] || [ "$answer" == n ]; then
        firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" port port="3306" protocol="tcp" drop'; firewall-cmd --reload
    fi 
            
    #creates or doesn't create firewall rules based on the fw variable value
    if [ "$fw" == no ] || [ "$fw" == n ]; then
        firewall-cmd --permanent --zone=public --add-service=https; firewall-cmd --permanent --zone=public --add-service=http; firewall-cmd --permanent --zone=public --add-port=8001/tcp; firewall-cmd --permanent --zone=public --add-port=3478/tcp; firewall-cmd --permanent --zone=public --add-port=3478/udp; firewall-cmd --permanent --zone=public --add-rich-rule="rule family=ipv4 source address=""$ip"" accept"; firewall-cmd --reload
    fi

    #restart snapd service for proper seeding before installation of certbot
    systemctl restart snapd.seeded.service

    #install snap core
    snap install core

    #install and enable certbot
    snap install --classic certbot 
    ln -s /snap/bin/certbot /usr/bin/certbot

    #add auto renewal for certbot to crontab
    SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null

    #download safeweb package
    wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg' -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg" -O /opt/webgap-deployment-20210921.tgz && rm -rf /tmp/cookies.txt

    #untar safeweb package
    tar -xzvf /opt/webgap-deployment-20210921.tgz -C /opt

    #make safeweb installer executable
    chmod +x /opt/deployment/install.sh

    #change safweb listening port to 8880 from 80 and 8443 from 443
    sed -i '49 s/443:8443/8443:8443/' /opt/deployment/app.yml
    sed -i '50 s/80:8080/8880:8080/' /opt/deployment/app.yml 

    #install safeweb package
    cd /opt/deployment; sh install.sh install

    #install safeweb turnserver container
    docker run -d -e EXTERNAL_IP="$ip" --name=turnserver --restart=always --net=host -p 3478:3478 -p 3478:3478/udp jyangnet/turnserver

    #capture input for the domain/subdomain used to access the embedded browser
    echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the front-end?$(tput setaf 9)"
    read frontend
    echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)" 
    read reply
    
    #input error handling for domain/subdomain confirmation question
    while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
    done

    #input error handling for the front-end domain/subdomain name question
    if [ "$reply" == no ] || [ "$reply" == n ]; then
        echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the front-end?$(tput setaf 9)"
        read frontend

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)" 
        read reply

        while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
        done
    fi

    #capture input for the domain/subdomain used to access the administration panel
    echo "$(tput setaf 3)Which domain or sudomain would you like to use to access the administration panel?$(tput setaf 9)"
    read backend
    echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
    read reply

    #input error handling for domain/subdomain confirmation question
    while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
    done

    #input error handling for the administration panel domain/subdomain name question
    if [ "$reply" == no ] || [ "$reply" == n ]; then
        echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the administration panel?$(tput setaf 9)"
        read backend

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)" 
        read reply

        while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
        done
    fi

    #replace & with variable values for the domain and subdomain in the nginx conf files
    sed -i "s/&/$frontend/" /etc/nginx/conf.d/default.conf
    sed -i "s/@/$backend/" /etc/nginx/conf.d/default.conf

    #turn server tokens off for consistent forward secrecy
    sed -i '26 i\   \ server_tokens off;' /etc/nginx/nginx.conf

    #run certbot twice - once for the front-end domain and once for the administration domain
    echo "$(tput setaf 3)Certbot is going to run for the front-end. Select only number 1.$(tput setaf 9)"
    sleep 3s
    certbot certonly --nginx --preferred-challenges http
    echo "$(tput setaf 3)Certbot is going to run for the administration panel. Select only number 2.$(tput setaf 9)"
    sleep 3s
    certbot certonly --nginx --preferred-challenges http

    #uncomment front-end nginx conf lines
    sed -i '2 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '3 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '47 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '48 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '51 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '52 s/#//' /etc/nginx/conf.d/default.conf

    #uncomment back-end nginx conf lines
    sed -i '88 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '89 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '92 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '93 s/#//' /etc/nginx/conf.d/default.conf

    #optimizations for nginx
    sed -i 's/#tcp_nopush     on;/tcp_nopush      on;/' /etc/nginx/nginx.conf
    sed -i '26 i \   \ tcp_nodelay      on;' /etc/nginx/nginx.conf
    sed -i '27 i \   \ types_hash_max_size 4096;' /etc/nginx/nginx.conf

    #create 4096 bit diffie-hellman key to replace the 2048 bit key
    openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 4096

    #add server IP and domain name to safewab.conf
    sed -i "2 s/SERVER_ADDRESS=66.160.146.247/SERVER_ADDRESS=$frontend/" /opt/deployment/safeweb.conf

##centos command block##
elif [ "$osrelease1" == '"CentOS-7"' ]; then

    #create package metadata store and upgrade operating system packages
    yum makecache fast
    yum -y upgrade

    #install required packages
    yum -y install yum-utils wget epel-release setools setroubleshoot

    #download nginx repo for stable version
    wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1ADencnD7rNB0RqT2bB1iFiMVE5fupIOH' -O /etc/yum.repos.d/nginx.repo

    #add docker and nginx repo
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    #install docker-ce and nginx
    yum -y remove runc
    yum -y install docker-ce nginx

    #change boolean operators for nginx to allow memory execution, network connection establishment
    setsebool -P httpd_execmem 1
    setsebool -P httpd_can_network_connect 1
    setsebool -P httpd_graceful_shutdown 1
    setsebool -P httpd_can_network_relay 1

    #enable nginx
    systemctl enable nginx

    #download nginx configuration template
    wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1Jw_CcvIqatMn3WVkUI2uMTe3g7WLb58v' -O /etc/nginx/conf.d/default.conf

    #download docker compose
    curl -L "https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    #make docker-compose executable and enable
    chmod +x /usr/local/bin/docker-compose && ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

    #start docker-ce
    systemctl enable --now docker.service

    #create user docker and add to group docker
    useradd -g docker docker

    #install snapd to later install certbot
    yum install -y snapd

    #enable and start snapd
    systemctl enable --now snapd.socket

    #enable snap classic functionality for certbot installation
    ln -s /var/lib/snapd/snap /snap

    #disable firewalld zone drifiting
    sed -i 's/AllowZoneDrifting=yes/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf

    #ask for host interface IP to create firewall rules insert into configuration files
    echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9)"
    read ip

    #tests IPv4 address validity for octet formatting to assure numbers only and between 1 and 3 positions
    while ! [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
        do echo "$(tput setaf 3)Please check for IP address format and numerical accuracy.$(tput setaf 9)"

        sleep 5

        echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9)"
        read ip
    done

    #the trusted zone accepts all packets, no rules needed
    echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9)"
    read fw

    #tests the value of the variable fw against acceptable values
    while [ "$fw" != yes ] && [ "$fw" != y ]  && [ "$fw" != no ] && [ "$fw" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"

        sleep 2

        echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9)"
        read fw
    done

    #asks about vpc/dmz to add another firewall rule if deployed directly to the internet
    if [ "$fw" == no ] || [ "$fw" == n ]; then
        echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9)"
        read answer

        #checks for answer spelling; if spelling is incorrect the operator is informed and given another chance to answer
        while [ "$answer" != yes ] && [ "$answer" != y ]  && [ "$answer" != no ] && [ "$answer" != n ]
            do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
        
            sleep 2

            echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9)"
            read answer
        done
    fi

    #creates firewall rule if no vpc/dmz
    if [ "$answer" == no ] || [ "$answer" == n ]; then
        firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" port port="3306" protocol="tcp" drop'; firewall-cmd --reload
    fi 
  
    #creates or doesn't create firewall rules based on the fw variable value
    if [ "$fw" == no ] || [ "$fw" == n ]; then
        firewall-cmd --permanent --zone=public --add-service=https; firewall-cmd --permanent --zone=public --add-service=http; firewall-cmd --permanent --zone=public --add-port=8001/tcp; firewall-cmd --permanent --zone=public --add-port=3478/tcp; firewall-cmd --permanent --zone=public --add-port=3478/udp; firewall-cmd --permanent --zone=public --add-rich-rule="rule family=ipv4 source address=""$ip"" accept"; firewall-cmd --reload
    fi

    #restart snapd service for proper seeding before installation of certbot
    systemctl restart snapd.seeded.service

    #install snap core
    snap install core

    #install and enable certbot
    snap install --classic certbot 
    ln -s /snap/bin/certbot /usr/bin/certbot

    #add auto renewal for certbot to crontab
    SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null

    #download safeweb package
    wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg' -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg" -O /opt/webgap-deployment-20210921.tgz && rm -rf /tmp/cookies.txt

    #untar safeweb package
    tar -xzvf /opt/webgap-deployment-20210921.tgz -C /opt

    #make safeweb installer executable
    chmod +x /opt/deployment/install.sh

    #change safweb listening port to 8880 from 80 and 8443 from 443
    sed -i '49 s/443:8443/8443:8443/' /opt/deployment/app.yml
    sed -i '50 s/80:8080/8880:8080/' /opt/deployment/app.yml 

    #install safeweb package
    cd /opt/deployment; sh install.sh install

    #install turnserver container
    docker run -d -e EXTERNAL_IP="$ip" --name=turnserver --restart=always --net=host -p 3478:3478 -p 3478:3478/udp jyangnet/turnserver

    #capture input for the domain/subdomain used to access the embedded browser
    echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the front-end?$(tput setaf 9)"
    read frontend
    echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)" 
    read reply

    #input error handling for domain/subdomain confirmation question
    while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
    done

    #input error handling for the front-end domain/subdomain name question
    if [ "$reply" == no ] || [ "$reply" == n ]; then
        echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the front-end?$(tput setaf 9)"
        read frontend

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)" 
        read reply

        while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
        done
    fi

    #capture input for the domain/subdomain used to access the administration panel
    echo "$(tput setaf 3)Which domain or sudomain would you like to use to access the administration panel?$(tput setaf 9)"
    read backend
    echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
    read reply

    #input error handling for domain/subdomain confirmation question
    while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
    done

    #input error handling for the administration panel domain/subdomain name question
    if [ "$reply" == no ] || [ "$reply" == n ]; then
        echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the administration panel?$(tput setaf 9)"
        read backend

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)" 
        read reply

        while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
        done
    fi

    #replace & with variable values for the front-end and back-end in the nginx conf files
    sed -i "s/&/$frontend/" /etc/nginx/conf.d/default.conf
    sed -i "s/@/$backend/" /etc/nginx/conf.d/default.conf

    #turn server tokens off for consistent forward secrecy
    sed -i '26 i\   \ server_tokens off;' /etc/nginx/nginx.conf

    #run certbot twice - once for the front-end domain and once for the administration domain
    echo "$(tput setaf 3)Certbot is going to run for the front-end. Please select only number 1.$(tput setaf 9)"
    sleep 3s
    certbot certonly --nginx --preferred-challenges http
    echo "$(tput setaf 3)Certbot is going to run for the administration panel. Please select only number 2.$(tput setaf 9)"
    sleep 3s
    certbot certonly --nginx --preferred-challenges http

    #uncomment front-end nginx conf lines
    sed -i '2 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '3 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '47 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '48 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '51 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '52 s/#//' /etc/nginx/conf.d/default.conf

    #uncomment back-end nginx conf lines
    sed -i '88 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '89 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '92 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '93 s/#//' /etc/nginx/conf.d/default.conf

    #optimizations for nginx
    sed -i 's/#tcp_nopush     on;/tcp_nopush      on;/' /etc/nginx/nginx.conf
    sed -i '26 i \   \ tcp_nodelay      on;' /etc/nginx/nginx.conf
    sed -i '27 i \   \ types_hash_max_size 4096;' /etc/nginx/nginx.conf

    #create 4096 bit diffie-hellman key to replace the 2048 bit key
    openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 4096

    #add server IP and domain name to safewab.conf
    sed -i "2 s/SERVER_ADDRESS=66.160.146.247/SERVER_ADDRESS=$frontend/" /opt/deployment/safeweb.conf
    sed -i "5 s/SERVER_IP=66.160.146.247/SERVER_IP=$ip/" /opt/deployment/safeweb.conf

##ubuntu command block##
else
   
    #switch ufw for firewalld
    systemctl stop ufw; apt -y remove ufw; apt -y install firewalld; systemctl enable --now firewalld

    #assign primary network interface to the public zone
    firewall-cmd --zone=public --permanent --change-interface=ens160; firewall-cmd --reload

    #disable firewalld zone drifiting
    sed -i 's/AllowZoneDrifting=yes/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf

    #downloads file for nginx repo to install stable version
    wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1Wi9B5Fi9Py-4jL9vd4Ap2uNcwtOEUFqq' -O /etc/apt/sources.list.d/nginx.list

    #updates GPG keys for the nginx repo
    curl -O https://nginx.org/keys/nginx_signing.key && apt-key add ./nginx_signing.key

    #add docker gpg key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    #add the docker-ce stable repo
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    #update apt metadata and install all apparmor profiles
    apt update && apt install apparmor-profiles apparmor-profiles-extra

    #install package updates and remove depreciated packages
    apt -y upgrade; apt -y autoremove

    #install docker-ce and nginx
    apt -y install docker-ce nginx

    #install docker compose
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; chmod +x /usr/local/bin/docker-compose; ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

    #download nginx configuration template
    wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1Jw_CcvIqatMn3WVkUI2uMTe3g7WLb58v' -O /etc/nginx/conf.d/default.conf

    #create user docker and add to group docker
    useradd -g docker docker

    #start docker-ce and enbale nginx
    systemctl enable --now docker.service; systemctl enable nginx

    #install snapd and enable/start
    apt -y install snapd; ln -s /var/lib/snapd/snap /snap; systemctl enable --now snapd.socket

    #ask for host interface IP to create firewall rules insert into configuration files
    echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9)"
    read ip

    #tests IPv4 address validity for octet formatting to assure numbers only and between 1 and 3 positions
    while ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
        do echo "$(tput setaf 3)Please check for IP address format and numerical accuracy.$(tput setaf 9)"

        sleep 5

        echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9)"
        read ip
    done   

    #the trusted zone accepts all packets, no rules needed
    echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9)"
    read fw

    #tests the value of the variable fw against acceptable values
    while [ "$fw" != yes ] && [ "$fw" != y ]  && [ "$fw" != no ] && [ "$fw" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"

        sleep 2

        echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9)"
        read fw
    done

    #asks about vpc/dmz to add another firewall rule if deployed directly to the internet
    if [ "$fw" == no ] || [ "$fw" == n ]; then
        echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9)"
        read answer

        #checks for answer spelling; if spelling is incorrect the operator is informed and given another chance to answer
        while [ "$answer" != yes ] && [ "$answer" != y ]  && [ "$answer" != no ] && [ "$answer" != n ]
            do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
        
            sleep 2

            echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9)"
            read answer
        done
    fi

    #creates firewall rule if no vpc/dmz
    if [ "$answer" == no ] || [ "$answer" == n ]; then
        firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" port port="3306" protocol="tcp" drop'; firewall-cmd --reload
    fi 
            
    #creates or doesn't create firewall rules based on the fw variable value
    if [ "$fw" == no ] || [ "$fw" == n ]; then
        firewall-cmd --permanent --zone=public --add-service=https; firewall-cmd --permanent --zone=public --add-service=http; firewall-cmd --permanent --zone=public --add-port=8001/tcp; firewall-cmd --permanent --zone=public --add-port=3478/tcp; firewall-cmd --permanent --zone=public --add-port=3478/udp; firewall-cmd --permanent --zone=public --add-rich-rule="rule family=ipv4 source address=""$ip"" accept"; firewall-cmd --reload
    fi

    #restart snapd service for proper seeding before installation of certbot, install snap core and certbot
    systemctl restart snapd.seeded.service; snap install core; snap install --classic certbot; ln -s /snap/bin/certbot /usr/bin/certbot

    #add auto renewal for certbot to crontab
    SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null

    #download safeweb package, untar, make package executable, edit install file for compatibility
    wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg' -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg" -O /opt/webgap-deployment-20210921.tgz && rm -rf /tmp/cookies.txt

    #untar safeweb package
    tar -xzvf /opt/webgap-deployment-20210921.tgz -C /opt

    #make safeweb installer executable
    chmod +x /opt/deployment/install.sh

    #change safweb listening port to 8880 from 80 and 8443 from 443
    sed -i '49 s/443:8443/8443:8443/' /opt/deployment/app.yml
    sed -i '50 s/80:8080/8880:8080/' /opt/deployment/app.yml

    #install safeweb package
    cd /opt/deployment; bash install.sh install

    #install turnserver container
    docker run -d  --name=turnserver --restart=always --net=host -p "$ip":3478:3478 -p "$ip":3478:3478/udp jyangnet/turnserver

    #capture input for the domain/subdomain used to access the embedded browser
    echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the front-end?$(tput setaf 9)"
    read frontend
    echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)" 
    read reply

    #input error handling for domain/subdomain confirmation question
    while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
    done

    #input error handling for the front-end domain/subdomain name question
    if [ "$reply" == no ] || [ "$reply" == n ]; then
        echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the front-end?$(tput setaf 9)"
        read frontend

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)" 
        read reply

        while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $frontend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
        done
    fi

    #capture input for the domain/subdomain used to access the administration panel
    echo "$(tput setaf 3)Which domain or subdomain would you like to use to access the administration panel?$(tput setaf 9)"
    read backend
    echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
    read reply

    #input error handling for domain/subdomain confirmation question
    while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
    done

    #input error handling for the administration panel domain/subdomain name question
    if [ "$reply" == no ] || [ "$reply" == n ]; then
        echo "$(tput setaf 3)Which domain or subdomain name would you like to use to access the administration panel?$(tput setaf 9)"
        read backend

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)" 
        read reply

        while [ "$reply" != yes ] && [ "$reply" != y ]  && [ "$reply" != no ] && [ "$reply" != n ]
        do echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
            
        sleep 2

        echo "$(tput setaf 3)Is $backend the correct spelling (yes/no)?$(tput setaf 9)"
        read reply
        done
    fi

    #replace & with variable values for the front-end and back-end in the nginx conf files
    sed -i "s/&/$frontend/" /etc/nginx/conf.d/default.conf
    sed -i "s/@/$backend/" /etc/nginx/conf.d/default.conf

    #turn server tokens off for consistent forward secrecy
    sed -i '26 i\   \ server_tokens off;' /etc/nginx/nginx.conf

    #run certbot twice - once for the front-end domain and once for the administration domain
    echo "$(tput setaf 3)Certbot is going to run for the front-end. Select only number 1.$(tput setaf 9)"
    sleep 3s
    certbot certonly --nginx --preferred-challenges http
    echo "$(tput setaf 3)Certbot is going to run for the administration panel. Select only number 2.$(tput setaf 9)"
    sleep 3s
    certbot certonly --nginx --preferred-challenges http

    #uncomment front-end nginx conf lines
    sed -i '2 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '3 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '47 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '48 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '51 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '52 s/#//' /etc/nginx/conf.d/default.conf

    #uncomment back-end nginx conf lines
    sed -i '88 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '89 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '92 s/#//' /etc/nginx/conf.d/default.conf
    sed -i '93 s/#//' /etc/nginx/conf.d/default.conf

    #optimizations for nginx
    sed -i 's/#tcp_nopush     on;/tcp_nopush      on;/' /etc/nginx/nginx.conf
    sed -i '26 i \   \ tcp_nodelay      on;' /etc/nginx/nginx.conf
    sed -i '27 i \   \ types_hash_max_size 4096;' /etc/nginx/nginx.conf

    #create 4096 bit diffie-hellman key to replace the 2048 bit key
    openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 4096

    #add server IP and domain name to safewab.conf
    sed -i "2 s/SERVER_ADDRESS=66.160.146.247/SERVER_ADDRESS=$frontend/" /opt/deployment/safeweb.conf
    sed -i "5 s/SERVER_IP=66.160.146.247/SERVER_IP=$ip/" /opt/deployment/safeweb.conf  
fi

cat << "EOF"
          *     ,MMM8&&&.            *
                MMMM88&&&&&    .
               MMMM88&&&&&&&
   *           MMM88&&&&&&&&
               MMM88&&&&&&&&
               'MMM88&&&&&&'
                 'MMM8&&&'      *
        |\___/|
        )     (             .              '
       =\     /=
         )===(       *
        /     \
        |     |
       /       \
       \       /
_/\_/\_/\__  _/_/\_/\_/\_/\_/\_/\_/\_/\_/\_
|  |  |  |( (  |  |  |  |  |  |  |  |  |  |
|  |  |  | ) ) |  |  |  |  |  |  |  |  |  |
|  |  |  |(_(  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |  |  |  |  |
jgs|  |  |  |  |  |  |  |  |  |  |  |  |  |
EOF
echo 
echo "Happy Browsing!"

sleep 3s

#restart server
echo "$(tput setaf 3)The server is going to restart in 10 seconds.$(tput setaf 9)"
sleep 10s
reboot