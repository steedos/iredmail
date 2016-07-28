#!/usr/bin/env bash

# Author:   Zhang Huangbin (zhb _at_ iredmail.org)

#---------------------------------------------------------------------
# This file is part of iRedMail, which is an open source mail server
# solution for Red Hat(R) Enterprise Linux, CentOS, Debian and Ubuntu.
#
# iRedMail is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# iRedMail is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with iRedMail.  If not, see <http://www.gnu.org/licenses/>.
#---------------------------------------------------------------------

# -------------------------------------------------------
# -------------------- PostgreSQL -----------------------
# -------------------------------------------------------

# NOTE: iRedMail will force all clients to send encrypted password
#       after configuration completed and SQL data imported.
# Reference: functions/cleanup.sh, function cleanup_pgsql_force_password().

pgsql_initialize()
{
    ECHO_INFO "Configure PostgreSQL database server." 

    # Init db
    if [ X"${DISTRO}" == X'RHEL' ]; then
        if [ X"${DISTRO_VERSION}"  == X'6' ]; then
            ${PGSQL_RC_SCRIPT} initdb >> ${INSTALL_LOG} 2>&1
        else
            postgresql-setup initdb >> ${INSTALL_LOG} 2>&1
        fi
    elif [ X"${DISTRO}" == X'FREEBSD' ]; then
        # Start service when system start up.
        # 'postgresql_enable=YES' is required to start service immediately.
        service_control enable 'postgresql_enable' 'YES'

        ${PGSQL_RC_SCRIPT} initdb >> ${INSTALL_LOG} 2>&1
    elif [ X"${DISTRO}" == X'OPENBSD' ]; then
        mkdir -p ${PGSQL_DATA_DIR} >> ${INSTALL_LOG} 2>&1
        chown ${PGSQL_SYS_USER}:${PGSQL_SYS_GROUP} ${PGSQL_DATA_DIR}
        su - ${PGSQL_SYS_USER} -c "initdb -D ${PGSQL_DATA_DIR} -U ${PGSQL_SYS_USER} -A trust" >> ${INSTALL_LOG} 2>&1
    fi

    backup_file ${PGSQL_CONF_PG_HBA} ${PGSQL_CONF_POSTGRESQL}

    if [ -f ${PGSQL_CONF_POSTGRESQL} ]; then
        ECHO_DEBUG "Make sure PostgreSQL binds to local address: ${SQL_SERVER_ADDRESS}."
        perl -pi -e 's#.*(listen_addresses.=.)(.).*#${1}${2}$ENV{LOCAL_ADDRESS}${2}#' ${PGSQL_CONF_POSTGRESQL}

        ECHO_DEBUG "Set client_min_messages to ERROR."
        perl -pi -e 's#.*(client_min_messages =).*#${1} error#' ${PGSQL_CONF_POSTGRESQL}

        # SSL is enabled by default on Ubuntu.
        [ X"${DISTRO}" == X'FREEBSD' ] && \
            perl -pi -e 's/^#(ssl.=.)off(.*)/${1}on${2}/' ${PGSQL_CONF_POSTGRESQL}
    fi

    ECHO_DEBUG "Copy iRedMail SSL cert/key with strict permission."
    backup_file ${PGSQL_DATA_DIR}/server.{crt,key}
    rm -f ${PGSQL_DATA_DIR}/server.{crt,key} >> ${INSTALL_LOG} 2>&1
    cp -f ${SSL_CERT_FILE} ${PGSQL_SSL_CERT} >> ${INSTALL_LOG} 2>&1
    cp -f ${SSL_KEY_FILE} ${PGSQL_SSL_KEY} >> ${INSTALL_LOG} 2>&1
    chown ${PGSQL_SYS_USER}:${PGSQL_SYS_GROUP} ${PGSQL_SSL_CERT} ${PGSQL_SSL_KEY} >> ${INSTALL_LOG} 2>&1
    chmod 0600 ${PGSQL_SSL_CERT} ${PGSQL_SSL_KEY} >> ${INSTALL_LOG} 2>&1
    ln -s ${PGSQL_SSL_CERT} ${PGSQL_DATA_DIR}/server.crt >> ${INSTALL_LOG} 2>&1
    ln -s ${PGSQL_SSL_KEY} ${PGSQL_DATA_DIR}/server.key >> ${INSTALL_LOG} 2>&1

    ECHO_DEBUG "Start PostgreSQL server and sleep 5 seconds for initialization"
    service_control stop ${PGSQL_RC_SCRIPT_NAME} >> ${INSTALL_LOG} 2>&1
    sleep 5
    service_control start ${PGSQL_RC_SCRIPT_NAME} >> ${INSTALL_LOG} 2>&1
    sleep 5

    # Note: we must reset `postgres` password first, otherwise all connections
    # will fail, because we cannot set/change passwords at all, so we're trying
    # to connect with a wrong password.
    ECHO_DEBUG "Setting password for PostgreSQL admin: (${PGSQL_ROOT_USER})."
    su - ${PGSQL_SYS_USER} -c "psql -d template1" >> ${INSTALL_LOG} 2>&1 <<EOF
ALTER USER ${PGSQL_ROOT_USER} WITH ENCRYPTED PASSWORD '${PGSQL_ROOT_PASSWD}';
EOF

    ECHO_DEBUG "Update pg_hba.conf to force local users to authenticate with md5."
    perl -pi -e 's/^(local.*)/#${1}/g' ${PGSQL_CONF_PG_HBA}
    perl -pi -e 's/^(host.*)/#${1}/g' ${PGSQL_CONF_PG_HBA}
    echo "local all     ${PGSQL_SYS_USER}   peer" >> ${PGSQL_CONF_PG_HBA}
    echo 'local all     all                 md5' >> ${PGSQL_CONF_PG_HBA}
    echo 'host  all     all     0.0.0.0/0   md5' >> ${PGSQL_CONF_PG_HBA}

    ECHO_DEBUG "Restart PostgreSQL server and sleeping for 5 seconds."
    service_control stop ${PGSQL_RC_SCRIPT_NAME} >> ${INSTALL_LOG} 2>&1
    sleep 5
    service_control start ${PGSQL_RC_SCRIPT_NAME} >> ${INSTALL_LOG} 2>&1
    sleep 5

    ECHO_DEBUG "Generate ${PGSQL_DOT_PGPASS}."
    cat > ${PGSQL_DOT_PGPASS} <<EOF
*:*:*:${PGSQL_ROOT_USER}:${PGSQL_ROOT_PASSWD}
*:*:*:${VMAIL_DB_BIND_USER}:${VMAIL_DB_BIND_PASSWD}
*:*:*:${VMAIL_DB_ADMIN_USER}:${VMAIL_DB_ADMIN_PASSWD}
*:*:*:${IREDAPD_DB_USER}:${IREDAPD_DB_PASSWD}
*:*:*:${IREDADMIN_DB_USER}:${IREDADMIN_DB_PASSWD}
*:*:*:${SOGO_DB_USER}:${SOGO_DB_PASSWD}
*:*:*:${RCM_DB_USER}:${RCM_DB_PASSWD}
*:*:*:${AMAVISD_DB_USER}:${AMAVISD_DB_PASSWD}
EOF

    chown ${PGSQL_SYS_USER}:${PGSQL_SYS_GROUP} ${PGSQL_DOT_PGPASS}
    chmod 0600 ${PGSQL_DOT_PGPASS} >> ${INSTALL_LOG} 2>&1

    cat >> ${TIP_FILE} <<EOF
PostgreSQL:
    * Admin user: ${PGSQL_ROOT_USER}, Password: ${PGSQL_ROOT_PASSWD}
    * Bind account (read-only):
        - Name: ${VMAIL_DB_BIND_USER}, Password: ${VMAIL_DB_BIND_PASSWD}
    * Vmail admin account (read-write):
        - Name: ${VMAIL_DB_ADMIN_USER}, Password: ${VMAIL_DB_ADMIN_PASSWD}
    * Database stored in: ${PGSQL_DATA_DIR}
    * RC script: ${PGSQL_RC_SCRIPT}
    * Log file: /var/log/postgresql/
    * See also:
        - ${PGSQL_INIT_SQL_SAMPLE}
        - ${PGSQL_DOT_PGPASS}

EOF

    echo 'export status_pgsql_initialize="DONE"' >> ${STATUS_FILE}
}

pgsql_import_vmail_users()
{
    export FIRST_USER_PASSWD_HASHED="$(generate_password_hash ${DEFAULT_PASSWORD_SCHEME} ${FIRST_USER_PASSWD})"

    ECHO_DEBUG "Generate sample SQL templates."
    cp -f ${SAMPLE_DIR}/postgresql/sql/init_vmail_db.sql ${PGSQL_DATA_DIR}/
    cp -f ${SAMPLE_DIR}/iredmail/iredmail.pgsql ${PGSQL_DATA_DIR}/iredmail.sql
    cp -f ${SAMPLE_DIR}/postgresql/sql/add_first_domain_and_user.sql ${PGSQL_DATA_DIR}/
    cp -f ${SAMPLE_DIR}/postgresql/sql/grant_permissions.sql ${PGSQL_DATA_DIR}/

    perl -pi -e 's#PH_VMAIL_DB_NAME#$ENV{VMAIL_DB_NAME}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_VMAIL_DB_BIND_USER#$ENV{VMAIL_DB_BIND_USER}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_VMAIL_DB_BIND_PASSWD#$ENV{VMAIL_DB_BIND_PASSWD}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_VMAIL_DB_ADMIN_USER#$ENV{VMAIL_DB_ADMIN_USER}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_VMAIL_DB_ADMIN_PASSWD#$ENV{VMAIL_DB_ADMIN_PASSWD}#g' ${PGSQL_DATA_DIR}/*.sql

    perl -pi -e 's#PH_FIRST_DOMAIN#$ENV{FIRST_DOMAIN}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_TRANSPORT#$ENV{TRANSPORT}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_FIRST_USER_PASSWD#$ENV{FIRST_USER_PASSWD_HASHED}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_FIRST_USER_MAILDIR_HASH_PART#$ENV{FIRST_USER_MAILDIR_HASH_PART}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_FIRST_USER#$ENV{FIRST_USER}#g' ${PGSQL_DATA_DIR}/*.sql
    perl -pi -e 's#PH_DOMAIN_ADMIN_NAME#$ENV{DOMAIN_ADMIN_NAME}#g' ${PGSQL_DATA_DIR}/*.sql

    if [ X"${DISTRO}" == X'RHEL' -a X"${DISTRO_VERSION}" == X'6' ]; then
        perl -pi -e 's#^(--)(CREATE LANGUAGE.*)#${2}#g' ${PGSQL_DATA_DIR}/init_vmail_db.sql
    fi

    perl -pi -e 's#^-- \\c#\\c#g' ${PGSQL_DATA_DIR}/iredmail.sql

    # Modify default SQL template, set storagebasedirectory, storagenode.
    perl -pi -e 's#(.*storagebasedirectory.*DEFAULT..)(.*)#${1}$ENV{STORAGE_BASE_DIR}${2}#' ${PGSQL_DATA_DIR}/iredmail.sql
    perl -pi -e 's#(.*storagenode.*DEFAULT..)(.*)#${1}$ENV{STORAGE_NODE}${2}#' ${PGSQL_DATA_DIR}/iredmail.sql

    chmod 0755 ${PGSQL_DATA_DIR}/*sql

    ECHO_DEBUG "Create roles (${VMAIL_DB_BIND_USER}, ${VMAIL_DB_ADMIN_USER}) and database: ${VMAIL_DB_NAME}."
    su - ${PGSQL_SYS_USER} -c "psql -d template1 -f ${PGSQL_DATA_DIR}/init_vmail_db.sql" >> ${INSTALL_LOG} 2>&1

    ECHO_DEBUG "Create tables in ${VMAIL_DB_NAME} database."
    su - ${PGSQL_SYS_USER} -c "psql -d template1 -f ${PGSQL_DATA_DIR}/iredmail.sql" >> ${INSTALL_LOG} 2>&1

    ECHO_DEBUG "Grant permissions."
    su - ${PGSQL_SYS_USER} -c "psql -d template1 -f ${PGSQL_DATA_DIR}/grant_permissions.sql" >> ${INSTALL_LOG} 2>&1

    ECHO_DEBUG "Add first domain and postmaster@ user."
    su - ${PGSQL_SYS_USER} -c "psql -d template1 -f ${PGSQL_DATA_DIR}/add_first_domain_and_user.sql" >> ${INSTALL_LOG} 2>&1

    mv ${PGSQL_DATA_DIR}/*sql ${RUNTIME_DIR}
    chmod 0700 ${RUNTIME_DIR}/*sql

    cat >> ${TIP_FILE} <<EOF
SQL commands used to initialize database and import mail accounts:
    - ${RUNTIME_DIR}/*.sql

EOF

    echo 'export status_pgsql_import_vmail_users="DONE"' >> ${STATUS_FILE}
}

pgsql_cron_backup()
{
    ECHO_INFO "Setup daily cron job to backup PostgreSQL databases with ${BACKUP_SCRIPT_PGSQL}"

    [ ! -d ${BACKUP_DIR} ] && mkdir -p ${BACKUP_DIR} >> ${INSTALL_LOG} 2>&1

    backup_file ${BACKUP_SCRIPT_PGSQL}
    cp ${TOOLS_DIR}/backup_pgsql.sh ${BACKUP_SCRIPT_PGSQL}
    chown ${SYS_ROOT_USER}:${SYS_ROOT_GROUP} ${BACKUP_SCRIPT_PGSQL}
    chmod 0700 ${BACKUP_SCRIPT_PGSQL}

    perl -pi -e 's#^(export PGSQL_SYS_USER=).*#${1}"$ENV{PGSQL_SYS_USER}"#' ${BACKUP_SCRIPT_PGSQL}
    perl -pi -e 's#^(export BACKUP_ROOTDIR=).*#${1}"$ENV{BACKUP_DIR}"#' ${BACKUP_SCRIPT_PGSQL}
    perl -pi -e 's#^(export DATABASES=).*#${1}"$ENV{SQL_BACKUP_DATABASES}"#' ${BACKUP_SCRIPT_PGSQL}

    # Add cron job
    cat >> ${CRON_SPOOL_DIR}/root <<EOF
# ${PROG_NAME}: Backup PostgreSQL databases on 03:01 AM
1   3   *   *   *   ${SHELL_BASH} ${BACKUP_SCRIPT_PGSQL}

EOF

    echo 'export status_pgsql_cron_backup="DONE"' >> ${STATUS_FILE}
}
