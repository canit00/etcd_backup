#!/usr/bin/env bash
# =======================================================================
# $Header: , 2017.10.09 BBTG $
# -----------------------------------------------------------------------
# Description:
#    Script which runs reshifter to backup cluster state
#
# Requirements:
#    /bin/sh is a symbolic link to /bin/bash
#
# Parameters:
#    None
#
# Notes:
#    BBTG filename:
#    /opt/dest_dir/<something>
#
# Revision history:
# -----------------------------------------------------------------------
# Modified     Author(s)             Description
# -----------------------------------------------------------------------
# 2017.10.09   Saul Alanis           Created script
# =======================================================================
#set -x
export MAILRC=/dev/null smtp=<smtp_server>
MAIL=`which mailx`
LOG=/var/tmp/reshifter-`date +%Y%m%d%M`.log
DATA_DIR=/root/reshifter

# ENV variables
export RS_ETCD_CLIENT_CERT=/etc/etcd/peer.crt
export RS_ETCD_CLIENT_KEY=/etc/etcd/peer.key
export RS_ETCD_CA_CERT=/etc/etcd/ca.crt

HOSTNAME=`hostname`
IP=`host ${HOSTNAME} |awk -F" " '{print $4}'`

touch $LOG

# test & validate reshifter connectivity before moving on
/usr/local/bin/reshifter stats -e https://${IP}:2379 2>&1 >> $LOG

if [[ ! $? -eq 0 ]]; then
  printf "etcd connectivy issues - backup failed, please inspect!\n" >> $LOG
  $MAIL -n -s "reshifter backup failed ${HOST}" user@somewhere.com < $LOG
  rm -f $LOG
  exit 1
fi

# create /tmp/reshifter/ if missing
if [[ ! -d /tmp/reshifter ]]; then
  mkdir /tmp/reshifter
  chmod 0770 /tmp/reshifter
fi

/usr/local/bin/reshifter backup create -e https://${IP}:2379 2>&1 >> $LOG

# Get backup ID and move it to DATA_DIR
ID=`awk -F" " '/zip/ {print $4}' $LOG`

if [[ ! -z "$ID" ]]; then
  mv $ID $DATA_DIR
fi

# initiate etcd dir backup
# https://docs.openshift.com/container-platform/3.5/admin_guide/backup_restore.html
if [[ $? -eq 0 ]]; then
  /usr/bin/ansible-playbook -i "localhost," -c local /usr/local/etc/pb_etcd_backup.yaml 
    if [[ $? -eq 0 ]]; then
      printf "etcd dir backup successful, logged in ansible logs\n" >> $LOG
    else
      printf "etcd dir backup failed, see ansible logs\n" >> $LOG
    fi
fi

# send notification
if [[ $? -eq 0 ]]; then
  $MAIL -n -s "reshifter backup success ${HOST}" user@somewhere.com < $LOG
  rm -f $LOG
  rm -rf /tmp/reshifter/*
else
  $MAIL -n -s "reshifter backup failed ${HOST}" user@somewhere.com < $LOG
  rm -f $LOG
fi
