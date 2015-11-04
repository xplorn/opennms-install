#!/bin/bash -e
# Script to bootstrap a basic OpenNMS setup

# Default build identifier set to snapshot
RELEASE="stable"
ERROR_LOG="bootstrap.log"
DB_USER="opennms"
DB_PASS="opennms"
OPENNMS_HOME="/usr/share/opennms"
REQUIRED_USER="root"
USER=$(whoami)
MIRROR="debian.mirrors.opennms.org"
ANSWER="No"

REQUIRED_SYSTEMS="Ubuntu|Debian"
SYSTEM=$(cat /etc/issue | grep -E ${REQUIRED_SYSTEMS})

# Error codes
E_ILLEGAL_ARGS=126
E_BASH=127
E_UNSUPPORTED=128

####
# Help function used in error messages and -h option
usage() {
  echo ""
  echo "Bootstrap OpenNMS basic setup on Debian based system."
  echo ""
  echo "-r: Set a release: stable | testing | snapshot"
  echo "    Default: ${RELEASE}"
  echo "-m: Set alternative mirror server for packages"
  echo "    Default: ${MIRROR}"
  echo "-h: Show this help"
}

showDisclaimer() {
  echo ""
  echo "This script installs  OpenNMS ${RELEASE} on your system."
  echo "It will install all components necessary to run OpenNMS."
  echo ""
  echo "The following components will be installed:"
  echo ""
  echo " - Oracle Java 8 JDK"
  echo " - PostgreSQL Server"
  echo " - OpenNMS Repositories"
  echo " - OpenNMS with core services and Webapplication"
  echo " - Initialize and bootstrapping the database"
  echo " - Enable OpenNMS on system start"
  echo ""
  echo "If you have  OpenNMS already  installed, don't  use this"
  echo "script!"
  echo ""
  read -p "If you want to proceed, type YES: " ANSWER

  # Set bash to case insensitive
  shopt -s nocasematch

  if [[ "${ANSWER}" == "yes" ]]; then
    echo ""
    echo "Starting setup procedure ... "
    echo ""
  else
    echo ""
    echo "Your system is not changed. Thank you computing with us"
    echo ""
    exit ${E_BASH}
  fi

  # Set case sensitive
  shopt -u nocasematch
}

# Test if system is supported
cat /etc/issue | grep -E ${REQUIRED_SYSTEMS}  1>/dev/null 2>>${ERROR_LOG}
if [ ! ${?} -eq 0 ]; then
  echo "This is system is not a supported Ubuntu or Debian system."
  exit ${E_UNSUPPORTED}
fi

# Setting Postgres User and changing configuration files require
# root permissions.
if [ "${USER}" != "${REQUIRED_USER}" ]; then
  echo "This script requires root permissions to be executed."
  exit ${E_BASH}
fi

####
# The -r option is optional and allows to set the release of OpenNMS.
# The -m option allows to overwrite the package repository server.
while getopts r:m:h flag; do
  case ${flag} in
    r)
        RELEASE="${OPTARG}"
        ;;
    m)
        MIRROR="${OPTARG}"
        ;;
    h)
      usage
      exit ${E_ILLEGAL_ARGS}
      ;;
    *)
      usage
      exit ${E_ILLEGAL_ARGS}
      ;;
  esac
done

####
# Helper function which tests if a command was successful or failed
checkError() {
  if [ $1 -eq 0 ]; then
    echo "OK"
  else
    echo "FAILED"
    exit ${E_BASH}
  fi
}

####
# Install OpenNMS Debian repository for specific release
installOnmsRepo() {
  if [ ! -f /etc/apt/sources.list.d/opennms-${RELEASE}.list ]; then
    echo -n "Install OpenNMS Repository         ... "
    printf "deb http://${MIRROR} ${RELEASE} main\ndeb-src http://${MIRROR} ${RELEASE} main" \
           > /etc/apt/sources.list.d/opennms-${RELEASE}.list
    checkError ${?}

    echo -n "Install OpenNMS Repository Key     ... "
    wget -q -O - http://${MIRROR}/OPENNMS-GPG-KEY | sudo apt-key add - 1>/dev/null 2>>${ERROR_LOG}
    checkError ${?}
  fi
}

####
# Install the OpenNMS application from Debian repository
installOnmsApp() {
  echo -n "Update repository                  ... "
  apt-get update 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
  apt-get install -y opennms
  ${OPENNMS_HOME}/bin/runjava -s 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
  clear
}

####
# Helper to request Postgres credentials to initialize the
# OpenNMS database.
queryDbCredentials() {
  echo ""
  echo "PostgreSQL credentials for OpenNMS"
  read -p "Enter username: " DB_USER
  read -s -p "Enter password: " DB_PASS
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" 1>/dev/null 2>>${ERROR_LOG}
  sudo -u postgres psql -c "CREATE DATABASE opennms;" 1>/dev/null 2>>${ERROR_LOG}
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE opennms to ${DB_USER};" 1>/dev/null 2>>${ERROR_LOG}
  echo ""
}

####
# Generate OpenNMS configuration file for accessing the PostgreSQL
# Database with credentials
setCredentials() {
  if [ -f "${OPENNMS_HOME}/etc/opennms-datasources.xml" ]; then
    echo -n "Generate OpenNMS data source config   ... "
    printf '<?xml version="1.0" encoding="UTF-8"?>
<datasource-configuration>
  <connection-pool factory="org.opennms.core.db.C3P0ConnectionFactory"
    idleTimeout="600"
    loginTimeout="3"
    minPool="50"
    maxPool="50"
    maxSize="50" />

  <jdbc-data-source name="opennms"
                    database-name="opennms"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://localhost:5432/opennms"
                    user-name="%s"
                    password="%s" />

  <jdbc-data-source name="opennms-admin"
                    database-name="template1"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://localhost:5432/template1"
                    user-name="%s"
                    password="%s" />
</datasource-configuration>' ${DB_USER} ${DB_PASS} ${DB_USER} ${DB_PASS} \
  > ${OPENNMS_HOME}/etc/opennms-datasources.xml
  checkError ${?}
  fi
}

####
# Initialize the OpenNMS database schema
initializeOnmsDb() {
  if [ ! -f $OPENNMS_HOME/etc/configured ]; then
    echo -n "Initialize OpenNMS                    ... "
    ${OPENNMS_HOME}/bin/install -dis 1>/dev/null 2>>${ERROR_LOG}
    checkError ${?}
  fi
}

restartOnms() {
  echo -n "Starting OpenNMS                      ... "
  service opennms restart 1>/dev/null 2>>${ERROR_LOG}
  checkError ${?}
}

# Execute setup procedure
clear
showDisclaimer
installOnmsRepo
installOnmsApp
queryDbCredentials
setCredentials
initializeOnmsDb
restartOnms

echo "OpenNMS should be up and running. You can access the WebUI on http://this-system:8980"
echo "It is possible to login with the user admin and password admin"
echo ""
echo "Please change immediately the password for your admin user!"
echo "Thank you computing with us."
